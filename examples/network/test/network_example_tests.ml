module ID = Bonsai_swiftui_spec.Id
module Protocol = Network_protocol
module Service = Network_service
module Test = Bonsai_swiftui_test

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let require_present handle test_id message =
  require (Option.is_some (Test.Handle.find handle (Test.Query.test_id test_id))) message
;;

let require_text handle value message =
  require
    (Option.is_some (Test.Handle.find handle (Test.Query.visible_text value)))
    message
;;

let require_no_text handle value message =
  require
    (Option.is_none (Test.Handle.find handle (Test.Query.visible_text value)))
    message
;;

let pump_worker handle =
  Test.Handle.present handle;
  Test.Handle.pump_next handle ()
;;

let pump_until_text handle value =
  let rec loop attempts =
    if attempts = 0
    then fail "timed out waiting for visible text %S" value
    else if Option.is_some (Test.Handle.find handle (Test.Query.visible_text value))
    then ()
    else (
      Unix.sleepf 0.001;
      pump_worker handle;
      loop (attempts - 1))
  in
  loop 500
;;

type fake =
  { https_calls : int Atomic.t
  ; https_blocked : bool Atomic.t
  ; websocket_emit : (Protocol.push -> unit) option Atomic.t
  ; websocket_generation : int Atomic.t
  ; last_sent_message : string option Atomic.t
  ; shutdown_count : int Atomic.t
  }

let create_fake () =
  { https_calls = Atomic.make 0
  ; https_blocked = Atomic.make false
  ; websocket_emit = Atomic.make None
  ; websocket_generation = Atomic.make 0
  ; last_sent_message = Atomic.make None
  ; shutdown_count = Atomic.make 0
  }
;;

let providers fake =
  let https_get ~sw:_ ~clock:_ ~net:_ _endpoint =
    let call = Atomic.fetch_and_add fake.https_calls 1 + 1 in
    match call with
    | 1 ->
      Ok
        Protocol.
          { status_code = 200
          ; content_type = Some "text/plain; charset=utf-8"
          ; body_bytes = 11
          ; preview = "hello world"
          }
    | 2 ->
      Atomic.set fake.https_blocked true;
      let never, _resolver = Eio.Promise.create () in
      Eio.Promise.await never;
      Error Protocol.Cancelled
    | 3 -> Error Protocol.Timeout
    | _ -> failwith "secret.example private payload"
  in
  let websocket ~sw:_ ~clock:_ ~net:_ ~emit =
    Atomic.set fake.websocket_emit (Some emit);
    { Service.run =
        (fun () ->
          let never, _resolver = Eio.Promise.create () in
          Eio.Promise.await never)
    ; connect =
        (fun ~generation _endpoint ->
          Atomic.set fake.websocket_generation generation;
          emit
            (Protocol.Websocket_state_changed
               { generation; state = Connecting; error = None });
          emit
            (Protocol.Websocket_state_changed
               { generation; state = Connected_state; error = None });
          Ok Protocol.Connected)
    ; send =
        (fun ~generation message ->
          Atomic.set fake.last_sent_message (Some message);
          emit
            (Protocol.Websocket_message_received
               { generation; kind = Text; message = Some ("Echo: " ^ message) });
          Ok Protocol.Sent)
    ; disconnect =
        (fun ~generation ->
          emit
            (Protocol.Websocket_state_changed
               { generation; state = Disconnecting; error = None });
          emit
            (Protocol.Websocket_state_changed { generation; state = Closed; error = None });
          Ok Protocol.Disconnected_command)
    ; shutdown = (fun () -> Atomic.incr fake.shutdown_count)
    }
  in
  Service.{ https_get; websocket }
;;

let create_handle runtime_epoch fake =
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let service = Service.create (providers fake) in
  let app =
    Network_example.create
      ~https_endpoint:"https://example.com/ok"
      ~websocket_endpoint:"wss://example.com/socket"
      ~service
      ()
  in
  Test.Handle.create_app
    ~runtime_epoch:(ID.Runtime.Epoch.of_int64 runtime_epoch)
    ~time_source
    app
    ~application_payload:Bytes.empty
;;

let emit fake push =
  match Atomic.get fake.websocket_emit with
  | Some emit -> emit push
  | None -> fail "WebSocket emitter is unavailable"
;;

let test_default_public_endpoints () =
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let handle =
    Test.Handle.create_app
      ~runtime_epoch:(ID.Runtime.Epoch.of_int64 1400L)
      ~time_source
      Network_example.app
      ~application_payload:Bytes.empty
  in
  Fun.protect
    ~finally:(fun () -> Test.Handle.shutdown handle)
    (fun () ->
       require_text
         handle
         "https://example.com/"
         "default HTTPS smoke endpoint is not rendered";
       require_text
         handle
         "wss://echo.websocket.org"
         "default WSS smoke endpoint is not rendered")
;;

let test_initial_https_success_cancel_and_error () =
  let fake = create_fake () in
  let handle = create_handle 1401L fake in
  Fun.protect
    ~finally:(fun () -> Test.Handle.shutdown handle)
    (fun () ->
       require_text handle "Secure Network Lab" "screen title is missing";
       require_present handle "https-panel" "HTTPS panel is missing";
       require_present handle "https-run" "HTTPS Run action is missing";
       require_present handle "websocket-panel" "WebSocket panel is missing";
       require_text handle "HTTPS: Idle" "initial HTTPS state is not Idle";
       require_text handle "WebSocket: Idle" "initial WebSocket state is not Idle";
       require_text handle "https://example.com/ok" "HTTPS endpoint is not rendered";
       require_text handle "wss://example.com/socket" "WSS endpoint is not rendered";
       Test.Handle.present handle;
       Test.Handle.click handle (Test.Query.test_id "https-run");
       pump_until_text handle "Status: 200";
       require_text
         handle
         "Content-Type: text/plain; charset=utf-8"
         "content type is missing";
       require_text handle "Body: 11 bytes" "body size is missing";
       require_text handle "hello world" "HTTPS preview is missing";
       Test.Handle.present handle;
       Test.Handle.click handle (Test.Query.test_id "https-run");
       let rec await_blocked attempts =
         if attempts = 0
         then fail "second HTTPS request did not block"
         else if Atomic.get fake.https_blocked
         then ()
         else (
           Unix.sleepf 0.001;
           await_blocked (attempts - 1))
       in
       await_blocked 500;
       require_present handle "https-cancel" "pending HTTPS request cannot be cancelled";
       Test.Handle.present handle;
       Test.Handle.click handle (Test.Query.test_id "https-cancel");
       pump_until_text handle "HTTPS: Cancelled";
       Test.Handle.present handle;
       Test.Handle.click handle (Test.Query.test_id "https-run");
       pump_until_text handle "Network operation timed out";
       Test.Handle.present handle;
       Test.Handle.click handle (Test.Query.test_id "https-run");
       pump_until_text handle "Network worker failed";
       require_no_text
         handle
         "secret.example private payload"
         "internal Worker failure leaked into the UI")
;;

let test_websocket_revisions_transcript_bounds_and_stale_fencing () =
  let fake = create_fake () in
  let handle = create_handle 1402L fake in
  Fun.protect
    ~finally:(fun () -> Test.Handle.shutdown handle)
    (fun () ->
       Test.Handle.present handle;
       Test.Handle.click handle (Test.Query.test_id "websocket-connect");
       pump_until_text handle "WebSocket: Connected";
       require_present handle "websocket-message-input" "message input is missing";
       require_present handle "websocket-send" "Send action is missing";
       Test.Handle.present handle;
       Test.Handle.input_text
         handle
         (Test.Query.test_id "websocket-message-input")
         "first draft";
       let generation = Atomic.get fake.websocket_generation in
       emit
         fake
         (Protocol.Websocket_message_received
            { generation; kind = Text; message = Some "interleaved" });
       pump_worker handle;
       Test.Handle.present handle;
       Test.Handle.input_text
         handle
         (Test.Query.test_id "websocket-message-input")
         "final 🌳";
       Test.Handle.present handle;
       Test.Handle.click handle (Test.Query.test_id "websocket-send");
       pump_until_text handle "Message: Echo: final 🌳";
       require
         (Atomic.get fake.last_sent_message = Some "final 🌳")
         "push reconciliation replaced the latest text-input revision";
       for index = 0 to 54 do
         emit
           fake
           (Protocol.Websocket_message_received
              { generation
              ; kind = Text
              ; message = Some (Printf.sprintf "event-%d" index)
              });
         pump_worker handle
       done;
       require
         (List.length
            (Test.Handle.find_all handle (Test.Query.test_id "transcript-entry"))
          = Network_policy.maximum_transcript_entries)
         "transcript is not bounded to 50 entries";
       require_no_text handle "Message: event-0" "old transcript entry was not evicted";
       require_text handle "Message: event-54" "latest transcript entry is missing";
       Test.Handle.present handle;
       Test.Handle.click handle (Test.Query.test_id "websocket-disconnect");
       pump_until_text handle "WebSocket: Closed";
       Test.Handle.present handle;
       Test.Handle.click handle (Test.Query.test_id "websocket-connect");
       pump_until_text handle "WebSocket: Connected";
       let next_generation = Atomic.get fake.websocket_generation in
       require (next_generation > generation) "reconnect did not advance the generation";
       emit
         fake
         (Protocol.Websocket_message_received
            { generation; kind = Text; message = Some "stale event" });
       pump_worker handle;
       emit
         fake
         (Protocol.Websocket_message_received
            { generation = next_generation; kind = Text; message = Some "fresh event" });
       pump_worker handle;
       require_no_text
         handle
         "Message: stale event"
         "stale generation mutated the transcript";
       require_text handle "Message: fresh event" "current generation event is missing")
;;

let () =
  Alcotest.run
    "network example"
    [ ( "Configuration"
      , [ Alcotest.test_case
            "renders the verified public smoke endpoints"
            `Quick
            test_default_public_endpoints
        ] )
    ; ( "HTTPS"
      , [ Alcotest.test_case
            "renders initial state, success, cancellation, and errors"
            `Quick
            test_initial_https_success_cancel_and_error
        ] )
    ; ( "WebSocket"
      , [ Alcotest.test_case
            "preserves revisions and bounds generation-fenced transcript"
            `Quick
            test_websocket_revisions_transcript_bounds_and_stale_fencing
        ] )
    ];
  Worker_runtime.For_testing.final_shutdown ()
;;
