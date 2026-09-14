module ID = Bonsai_swiftui_spec.Id
module Protocol = Network_protocol
module Service = Network_service

let fail format = Printf.ksprintf (fun message -> Alcotest.fail message) format

let await ?(timeout = 2.) description predicate =
  let deadline = Unix.gettimeofday () +. timeout in
  let rec loop () =
    if predicate ()
    then ()
    else if Unix.gettimeofday () >= deadline
    then fail "timed out waiting for %s" description
    else (
      Unix.sleepf 0.001;
      loop ())
  in
  loop ()
;;

let accepted = function
  | Worker.Accepted request_id -> request_id
  | Full -> fail "request unexpectedly hit backpressure"
  | Not_ready -> fail "service was not ready"
  | Stopping -> fail "service was stopping"
;;

let response_count events =
  List.fold_left
    (fun count -> function
       | Worker.Response _ -> count + 1
       | Push _ | Terminal _ -> count)
    0
    events
;;

let rec drain_until_responses client expected events =
  let events = events @ Worker.For_testing.drain_events client ~max_events:64 in
  if response_count events >= expected
  then events
  else (
    Worker.For_testing.await_output client;
    drain_until_responses client expected events)
;;

let outcome_for events request_id =
  List.find_map
    (function
      | Worker.Response { request_id = actual; outcome; _ }
        when ID.Worker.Request_id.equal request_id actual -> Some outcome
      | Response _ | Push _ | Terminal _ -> None)
    events
  |> function
  | Some outcome -> outcome
  | None -> fail "missing response"
;;

let start epoch service =
  match
    Worker_runtime.start ~runtime_epoch:(ID.Runtime.Epoch.of_int64 epoch) service ()
  with
  | Ok client -> client
  | Error error -> fail "network service failed to start: %s" error
;;

let stop client =
  Worker_runtime.stop client;
  Worker_runtime.For_testing.await_state Worker_runtime.Idle
;;

let endpoint_path endpoint = endpoint.Network_policy.resource
let blocking_https_started = Atomic.make false

let test_https_routing_cancellation_and_pump_boundary () =
  Atomic.set blocking_https_started false;
  let calls = Atomic.make [] in
  let https_get ~sw ~clock:_ ~net:_ endpoint =
    Atomic.set calls (endpoint :: Atomic.get calls);
    match endpoint_path endpoint with
    | "/ok" ->
      Ok
        Protocol.
          { status_code = 200
          ; content_type = Some "text/plain"
          ; body_bytes = 2
          ; preview = "ok"
          }
    | "/provider-error" -> Error Protocol.Timeout
    | "/blocked" ->
      Atomic.set blocking_https_started true;
      let never, _resolver = Eio.Promise.create () in
      Eio.Promise.await never;
      ignore (sw : Eio.Switch.t);
      Error Protocol.Cancelled
    | path -> fail "unexpected HTTPS path: %s" path
  in
  let websocket ~sw:_ ~clock:_ ~net:_ ~emit:_ =
    { Service.run = (fun () -> ())
    ; connect = (fun ~generation:_ _ -> Error Protocol.Disconnected)
    ; send = (fun ~generation:_ _ -> Error Protocol.Disconnected)
    ; disconnect = (fun ~generation:_ -> Error Protocol.Disconnected)
    ; shutdown = (fun () -> ())
    }
  in
  let client = start 1301L (Service.create { https_get; websocket }) in
  Fun.protect
    ~finally:(fun () ->
      if (Worker_runtime.For_testing.diagnostics ()).state <> Worker_runtime.Idle
      then stop client)
    (fun () ->
       let ok_id =
         Worker.send
           client
           (Protocol.Https_get { request_id = 10; uri = "https://EXAMPLE.com/ok" })
         |> accepted
       in
       let invalid_id =
         Worker.send
           client
           (Protocol.Https_get { request_id = 11; uri = "http://example.com/unsafe" })
         |> accepted
       in
       let provider_error_id =
         Worker.send
           client
           (Protocol.Https_get
              { request_id = 12; uri = "https://example.com/provider-error" })
         |> accepted
       in
       let events = drain_until_responses client 3 [] in
       (match outcome_for events ok_id with
        | Worker.Completed
            (Protocol.Https_result
               { request_id = 10
               ; outcome =
                   Ok
                     { status_code = 200
                     ; content_type = Some "text/plain"
                     ; body_bytes = 2
                     ; preview = "ok"
                     }
               }) -> ()
        | _ -> fail "HTTPS success was not preserved");
       (match outcome_for events invalid_id with
        | Worker.Completed
            (Protocol.Https_result
               { request_id = 11; outcome = Error (Unsupported_scheme "http") }) -> ()
        | _ -> fail "invalid HTTPS URI was not returned as an application error");
       (match outcome_for events provider_error_id with
        | Worker.Completed
            (Protocol.Https_result { request_id = 12; outcome = Error Timeout }) -> ()
        | _ -> fail "HTTPS provider error was not preserved");
       Alcotest.(check int) "provider call count" 2 (List.length (Atomic.get calls));
       let blocked_id =
         Worker.send
           client
           (Protocol.Https_get { request_id = 13; uri = "https://example.com/blocked" })
         |> accepted
       in
       await "the blocking HTTPS provider" (fun () -> Atomic.get blocking_https_started);
       Worker.cancel client ~request_id:blocked_id;
       let cancelled = drain_until_responses client 1 [] in
       (match outcome_for cancelled blocked_id with
        | Worker.Cancelled -> ()
        | _ -> fail "request cancellation did not remain structural");
       let observed = ref 0 in
       let scheduled = ref 0 in
       Worker.on_event client (fun _event ->
         incr observed;
         Bonsai.Effect.return ());
       ignore
         (Worker.send
            client
            (Protocol.Https_get { request_id = 14; uri = "https://example.com/ok" })
          |> accepted
          : ID.Worker.request_id);
       await "a queued Worker output" (fun () ->
         Worker.For_testing.pending_output_count client > 0);
       Alcotest.(check int) "not visible before pump" 0 !observed;
       Worker.Private.drain_to_effects client ~max_events:64 ~schedule:(fun _effect ->
         incr scheduled);
       Alcotest.(check int) "visible during pump" 1 !observed;
       Alcotest.(check int) "effect scheduled once" 1 !scheduled;
       stop client)
;;

let test_websocket_commands_and_push_topics () =
  let daemon_started = Atomic.make false in
  let connect_endpoint = Atomic.make None in
  let websocket ~sw:_ ~clock:_ ~net:_ ~emit =
    { Service.run = (fun () -> Atomic.set daemon_started true)
    ; connect =
        (fun ~generation endpoint ->
          Atomic.set connect_endpoint (Some endpoint);
          emit
            (Protocol.Websocket_state_changed
               { generation; state = Connecting; error = None });
          emit
            (Protocol.Websocket_state_changed
               { generation; state = Connected_state; error = None });
          Ok Protocol.Connected)
    ; send =
        (fun ~generation message ->
          emit
            (Protocol.Websocket_message_received
               { generation; kind = Text; message = Some message });
          Ok Protocol.Sent)
    ; disconnect =
        (fun ~generation ->
          emit
            (Protocol.Websocket_state_changed { generation; state = Closed; error = None });
          Ok Protocol.Disconnected_command)
    ; shutdown = (fun () -> ())
    }
  in
  let https_get ~sw:_ ~clock:_ ~net:_ _endpoint = Error Protocol.Dns_failure in
  let client = start 1302L (Service.create { https_get; websocket }) in
  Fun.protect
    ~finally:(fun () ->
      if (Worker_runtime.For_testing.diagnostics ()).state <> Worker_runtime.Idle
      then stop client)
    (fun () ->
       await "the WebSocket session daemon" (fun () -> Atomic.get daemon_started);
       let connect_id =
         Worker.send
           client
           (Protocol.Websocket_connect
              { generation = 4; uri = "wss://EXAMPLE.com/socket" })
         |> accepted
       in
       let send_id =
         Worker.send
           client
           (Protocol.Websocket_send { generation = 4; message = "hello" })
         |> accepted
       in
       let disconnect_id =
         Worker.send client (Protocol.Websocket_disconnect { generation = 4 }) |> accepted
       in
       let events = drain_until_responses client 3 [] in
       let check_command request_id expected =
         match outcome_for events request_id with
         | Worker.Completed
             (Protocol.Websocket_command_result { generation = 4; outcome = Ok actual })
           -> Alcotest.(check bool) "WebSocket command" true (actual = expected)
         | _ -> fail "WebSocket command response was not preserved"
       in
       check_command connect_id Protocol.Connected;
       check_command send_id Protocol.Sent;
       check_command disconnect_id Protocol.Disconnected_command;
       (match Atomic.get connect_endpoint with
        | Some endpoint ->
          Alcotest.(check string) "normalized host" "example.com" endpoint.host;
          Alcotest.(check string) "resource" "/socket" endpoint.resource
        | None -> fail "connect provider was not called");
       let pushes =
         List.filter_map
           (function
             | Worker.Push { topic; payload; _ } -> Some (topic, payload)
             | Response _ | Terminal _ -> None)
           events
       in
       Alcotest.(check bool)
         "state push is visible"
         true
         (List.exists
            (fun (topic, _) ->
               ID.Worker.Push_topic.equal topic Protocol.Topic.websocket_state)
            pushes);
       Alcotest.(check bool)
         "message push is visible"
         true
         (List.exists
            (fun (topic, _) ->
               ID.Worker.Push_topic.equal topic Protocol.Topic.websocket_message)
            pushes);
       List.iter
         (fun (topic, payload) ->
            let expected =
              match payload with
              | Protocol.Websocket_state_changed _ -> Protocol.Topic.websocket_state
              | Websocket_message_received _ -> Protocol.Topic.websocket_message
            in
            Alcotest.(check bool)
              "push topic"
              true
              (ID.Worker.Push_topic.equal topic expected))
         pushes;
       stop client)
;;

let test_shutdown_stops_daemon_and_suppresses_late_pushes () =
  let daemon_started = Atomic.make false in
  let shutdown_count = Atomic.make 0 in
  let saved_emit = Atomic.make None in
  let websocket ~sw:_ ~clock:_ ~net:_ ~emit =
    Atomic.set saved_emit (Some emit);
    { Service.run =
        (fun () ->
          Atomic.set daemon_started true;
          let never, _resolver = Eio.Promise.create () in
          Eio.Promise.await never)
    ; connect = (fun ~generation:_ _ -> Ok Protocol.Connected)
    ; send = (fun ~generation:_ _ -> Ok Protocol.Sent)
    ; disconnect = (fun ~generation:_ -> Ok Protocol.Disconnected_command)
    ; shutdown = (fun () -> Atomic.incr shutdown_count)
    }
  in
  let https_get ~sw:_ ~clock:_ ~net:_ _endpoint = Error Protocol.Dns_failure in
  let client = start 1303L (Service.create { https_get; websocket }) in
  await "the shutdown test daemon" (fun () -> Atomic.get daemon_started);
  stop client;
  Alcotest.(check int) "shutdown count" 1 (Atomic.get shutdown_count);
  ignore
    (Worker.For_testing.drain_events client ~max_events:64 : (_, _) Worker.event list);
  (match Atomic.get saved_emit with
   | None -> fail "service did not supply a WebSocket emitter"
   | Some emit ->
     emit
       (Protocol.Websocket_state_changed
          { generation = 99; state = Failed; error = Some Shutting_down }));
  Alcotest.(check int)
    "no output after shutdown"
    0
    (Worker.For_testing.pending_output_count client)
;;

let () =
  Alcotest.run
    "network service"
    [ ( "HTTPS"
      , [ Alcotest.test_case
            "routes results, cancels structurally, and preserves the pump boundary"
            `Quick
            test_https_routing_cancellation_and_pump_boundary
        ] )
    ; ( "WebSocket"
      , [ Alcotest.test_case
            "routes commands and push topics"
            `Quick
            test_websocket_commands_and_push_topics
        ; Alcotest.test_case
            "shuts down once and suppresses late pushes"
            `Quick
            test_shutdown_stops_daemon_and_suppresses_late_pushes
        ] )
    ];
  Worker_runtime.For_testing.final_shutdown ()
;;
