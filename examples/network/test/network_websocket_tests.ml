module Policy = Network_policy
module Protocol = Network_protocol
module Websocket = Network_websocket

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel))
;;

let fixture_path name =
  let path = Filename.concat "fixtures" name in
  if Sys.file_exists path
  then path
  else Alcotest.failf "network WebSocket fixture is missing: %s" name
;;

let cert_pem = read_file (fixture_path "localhost-cert.pem")
let key_pem = read_file (fixture_path "localhost-key.pem")

let decode_certificates value =
  match X509.Certificate.decode_pem_multiple value with
  | Ok certificates -> certificates
  | Error (`Msg message) -> Alcotest.fail message
;;

let certificates = decode_certificates cert_pem
let trust_anchor = List.hd (List.rev certificates)

let server_config () =
  let private_key =
    match X509.Private_key.decode_pem key_pem with
    | Ok key -> key
    | Error (`Msg message) -> Alcotest.fail message
  in
  match
    Tls.Config.server
      ~certificates:(`Single (certificates, private_key))
      ~alpn_protocols:[ "http/1.1" ]
      ()
  with
  | Ok config -> config
  | Error (`Msg message) -> Alcotest.fail message
;;

module Server_tls_socket = struct
  type t = Tls_eio.t
  type tag = [ `Generic ]

  let read_methods = []
  let single_read = Eio.Flow.single_read
  let single_write = Eio.Flow.single_write
  let copy flow ~src = Eio.Flow.copy src flow
  let shutdown = Eio.Flow.shutdown
  let close = Eio.Resource.close
end

let server_socket tls =
  (Eio.Resource.T (tls, Eio.Net.Pi.stream_socket (module Server_tls_socket))
   : [ `Generic ] Eio.Net.stream_socket_ty Eio.Resource.t)
;;

let sha1 value = value |> Digestif.SHA1.digest_string |> Digestif.SHA1.to_raw_string

let consume_payload payload callback =
  let buffer = Buffer.create 128 in
  let rec read () =
    Httpun_ws.Payload.schedule_read
      payload
      ~on_eof:(fun () -> callback (Buffer.contents buffer))
      ~on_read:(fun chunk ~off ~len ->
        Buffer.add_string buffer (Bigstringaf.substring chunk ~off ~len);
        read ())
  in
  read ()
;;

let websocket_server_handler behavior ~switch ~peer tls =
  let error_handler _peer ?request:_ _error respond =
    let body = respond Httpun.Headers.empty in
    Httpun.Body.Writer.close body
  in
  let request_handler peer (request : Httpun.Reqd.t Gluten.Reqd.t) =
    let upgrade () =
      let connection =
        Httpun_ws.Server_connection.create_websocket (behavior ~switch peer)
      in
      request.upgrade (Gluten.make (module Httpun_ws.Server_connection) connection)
    in
    match Httpun_ws.Handshake.respond_with_upgrade ~sha1 request.reqd upgrade with
    | Ok () -> ()
    | Error message ->
      let response =
        Httpun.Response.create
          ~headers:(Httpun.Headers.of_list [ "connection", "close" ])
          `Bad_request
      in
      Httpun.Reqd.respond_with_string request.reqd response message
  in
  Httpun_eio.Server.create_connection_handler
    ~request_handler
    ~error_handler
    ~sw:switch
    peer
    (server_socket tls)
;;

let with_tls_listener server client =
  Eio_posix.run (fun environment ->
    Eio.Switch.run (fun switch ->
      Network_tls.ensure_rng_initialized ();
      let net = Eio.Stdenv.net environment in
      let clock = Eio.Stdenv.mono_clock environment in
      let listener =
        Eio.Net.listen
          ~reuse_addr:true
          ~backlog:1
          ~sw:switch
          net
          (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
      in
      let address = Eio.Net.listening_addr listener in
      Eio.Fiber.fork ~sw:switch (fun () ->
        let flow, peer = Eio.Net.accept ~sw:switch listener in
        try
          let tls = Tls_eio.server_of_flow (server_config ()) flow in
          Eio.Switch.run (fun server_switch -> server ~switch:server_switch ~peer tls)
        with
        | Tls_eio.Tls_alert _
        | Tls_eio.Tls_failure _
        | Eio.Cancel.Cancelled _
        | Eio.Io _
        | End_of_file -> ()
        | Failure message when String.equal message "cannot write to closed writer" -> ());
      client ~switch ~clock ~net address))
;;

let with_websocket_server behavior = with_tls_listener (websocket_server_handler behavior)

let port_of_address = function
  | `Tcp (_, port) -> port
  | `Unix _ -> Alcotest.fail "expected a TCP test listener"
;;

let endpoint address =
  let uri = Printf.sprintf "wss://localhost:%d/socket" (port_of_address address) in
  match Policy.validate_endpoint ~expected:`Wss uri with
  | Ok endpoint -> endpoint
  | Error error -> Alcotest.fail (Protocol.error_to_string error)
;;

let connector net address ~sw ~clock ~endpoint:_ =
  Network_tls.connect_address
    ~sw
    ~clock
    ~net
    ~address
    ~host:"localhost"
    ~trust:(Network_tls.Certificates [ trust_anchor ])
    ~timeout_seconds:1.
;;

let describe_event = function
  | Protocol.Websocket_state_changed { generation; state; error } ->
    let state =
      match state with
      | Idle -> "Idle"
      | Connecting -> "Connecting"
      | Connected_state -> "Connected"
      | Disconnecting -> "Disconnecting"
      | Closed -> "Closed"
      | Failed -> "Failed"
    in
    let error =
      match error with
      | None -> ""
      | Some error -> ":" ^ Protocol.error_to_string error
    in
    Printf.sprintf "state(%d,%s%s)" generation state error
  | Protocol.Websocket_message_received { generation; kind; message } ->
    let kind =
      match kind with
      | Text -> "Text"
      | Unsupported_binary -> "UnsupportedBinary"
      | Unsupported_text -> "UnsupportedText"
    in
    Printf.sprintf
      "message(%d,%s,%d)"
      generation
      kind
      (Option.fold ~none:0 ~some:String.length message)
;;

let await_event clock events predicate =
  let seen = ref [] in
  try
    Eio.Time.Timeout.run_exn (Eio.Time.Timeout.seconds clock 1.) (fun () ->
      let rec loop () =
        let event = Eio.Stream.take events in
        if predicate event
        then event
        else (
          seen := describe_event event :: !seen;
          loop ())
      in
      loop ())
  with
  | Eio.Time.Timeout ->
    Alcotest.failf
      "timed out waiting for WebSocket event; observed: %s"
      (String.concat ", " (List.rev !seen))
;;

let check_error label expected = function
  | Error actual when actual = expected -> ()
  | Error actual ->
    Alcotest.failf
      "%s: expected %s, received %s"
      label
      (Protocol.error_to_string expected)
      (Protocol.error_to_string actual)
  | Ok _ -> Alcotest.failf "%s unexpectedly succeeded" label
;;

let check_command label expected = function
  | Ok actual -> Alcotest.(check bool) label true (actual = expected)
  | Error error -> Alcotest.fail (Protocol.error_to_string error)
;;

let start_client ~switch ~clock ~net address =
  let events = Eio.Stream.create max_int in
  let client =
    Websocket.create
      ~sw:switch
      ~clock:(clock :> Worker.mono_clock)
      ~connect:(connector (net :> Worker.net) address)
      ~emit:(Eio.Stream.add events)
      ()
  in
  Eio.Fiber.fork ~sw:switch (fun () -> Websocket.run client);
  client, events
;;

let await_connected clock events generation =
  ignore
    (await_event clock events (function
       | Protocol.Websocket_state_changed
           { generation = actual; state = Connected_state; _ } -> actual = generation
       | _ -> false)
     : Protocol.push)
;;

let echo_behavior close_resolver ~switch:_ _peer wsd =
  let frame ~opcode ~is_fin ~len:_ payload =
    match (opcode : Httpun_ws.Websocket.Opcode.t) with
    | `Text | `Continuation ->
      consume_payload payload (fun value ->
        let bytes = Bytes.of_string value in
        Httpun_ws.Wsd.send_bytes
          wsd
          ~kind:(if opcode = `Text then `Text else `Continuation)
          ~is_fin
          bytes
          ~off:0
          ~len:(Bytes.length bytes))
    | `Ping -> consume_payload payload (fun _ -> Httpun_ws.Wsd.send_pong wsd)
    | `Connection_close ->
      consume_payload payload (fun close_payload ->
        Eio.Promise.resolve close_resolver close_payload;
        Httpun_ws.Wsd.close ~code:`Normal_closure wsd)
    | `Binary | `Pong | `Other _ -> consume_payload payload ignore
  in
  let eof ?error:_ () = () in
  { Httpun_ws.Websocket_connection.frame; eof }
;;

let test_connect_echo_disconnect_and_command_errors () =
  let close_payload, close_resolver = Eio.Promise.create () in
  with_websocket_server (echo_behavior close_resolver) (fun ~switch ~clock ~net address ->
    let client, events = start_client ~switch ~clock ~net address in
    Websocket.send client ~generation:1 "before connect"
    |> check_error "send while disconnected" Protocol.Disconnected;
    Websocket.connect client ~generation:1 (endpoint address)
    |> check_command "connected command" Protocol.Connected;
    await_connected clock events 1;
    Websocket.connect client ~generation:2 (endpoint address)
    |> check_error "duplicate connect" Protocol.Already_connected;
    Websocket.send client ~generation:0 "stale"
    |> check_error "stale send" Protocol.Disconnected;
    Websocket.send client ~generation:1 "secure echo"
    |> check_command "sent command" Protocol.Sent;
    let message =
      await_event clock events (function
        | Protocol.Websocket_message_received
            { generation = 1; kind = Text; message = Some _ } -> true
        | _ -> false)
    in
    (match message with
     | Protocol.Websocket_message_received { message = Some value; _ } ->
       Alcotest.(check string) "echo" "secure echo" value
     | _ -> Alcotest.fail "missing echo event");
    Websocket.disconnect client ~generation:1
    |> check_command "disconnect command" Protocol.Disconnected_command;
    let close_payload =
      Eio.Time.Timeout.run_exn (Eio.Time.Timeout.seconds clock 1.) (fun () ->
        Eio.Promise.await close_payload)
    in
    Alcotest.(check string) "normal close code" "\003\232" close_payload;
    ignore
      (await_event clock events (function
         | Protocol.Websocket_state_changed { generation = 1; state = Closed; _ } -> true
         | _ -> false)
       : Protocol.push);
    Websocket.shutdown client)
;;

let test_fragmentation_and_ping_pong () =
  let pong, pong_resolver = Eio.Promise.create () in
  let text_count = ref 0 in
  let behavior ~switch:_ _peer wsd =
    let frame ~opcode ~is_fin:_ ~len:_ payload =
      match (opcode : Httpun_ws.Websocket.Opcode.t) with
      | `Pong -> consume_payload payload (Eio.Promise.resolve pong_resolver)
      | `Text ->
        consume_payload payload (fun _ ->
          incr text_count;
          if !text_count = 1
          then (
            let first = Bytes.of_string "hel" in
            let second = Bytes.of_string "lo" in
            Httpun_ws.Wsd.send_bytes wsd ~kind:`Text ~is_fin:false first ~off:0 ~len:3;
            Httpun_ws.Wsd.send_bytes wsd ~kind:`Continuation second ~off:0 ~len:2)
          else (
            let ping = Bigstringaf.of_string ~off:0 ~len:4 "ping" in
            Httpun_ws.Wsd.send_ping
              ~application_data:{ Httpun.IOVec.buffer = ping; off = 0; len = 4 }
              wsd))
      | `Ping -> Httpun_ws.Wsd.send_pong wsd
      | `Connection_close -> Httpun_ws.Wsd.close wsd
      | `Continuation | `Binary | `Other _ -> consume_payload payload ignore
    in
    let eof ?error:_ () = () in
    { Httpun_ws.Websocket_connection.frame; eof }
  in
  with_websocket_server behavior (fun ~switch ~clock ~net address ->
    let client, events = start_client ~switch ~clock ~net address in
    Websocket.connect client ~generation:4 (endpoint address)
    |> check_command "connect" Protocol.Connected;
    Websocket.send client ~generation:4 "trigger server frames"
    |> check_command "frame trigger" Protocol.Sent;
    let event =
      await_event clock events (function
        | Protocol.Websocket_message_received
            { generation = 4; kind = Text; message = Some _ } -> true
        | _ -> false)
    in
    (match event with
     | Protocol.Websocket_message_received { message = Some value; _ } ->
       Alcotest.(check string) "fragment reassembly" "hello" value
     | _ -> Alcotest.fail "missing fragmented message");
    Websocket.send client ~generation:4 "trigger ping"
    |> check_command "ping trigger" Protocol.Sent;
    let pong_value =
      Eio.Time.Timeout.run_exn (Eio.Time.Timeout.seconds clock 1.) (fun () ->
        Eio.Promise.await pong)
    in
    Alcotest.(check string) "pong echoes ping payload" "ping" pong_value;
    ignore (Websocket.disconnect client ~generation:4);
    Websocket.shutdown client)
;;

let test_unsupported_messages_and_outgoing_limits () =
  let behavior ~switch:_ _peer wsd =
    let frame ~opcode ~is_fin:_ ~len:_ payload =
      (match (opcode : Httpun_ws.Websocket.Opcode.t) with
       | `Ping -> Httpun_ws.Wsd.send_pong wsd
       | `Connection_close -> Httpun_ws.Wsd.close wsd
       | `Text ->
         let binary = Bytes.of_string "\000\001" in
         let invalid = Bytes.of_string "\255" in
         Httpun_ws.Wsd.send_bytes wsd ~kind:`Binary binary ~off:0 ~len:2;
         Httpun_ws.Wsd.send_bytes wsd ~kind:`Text invalid ~off:0 ~len:1
       | `Continuation | `Binary | `Pong | `Other _ -> ());
      consume_payload payload ignore
    in
    let eof ?error:_ () = () in
    { Httpun_ws.Websocket_connection.frame; eof }
  in
  with_websocket_server behavior (fun ~switch ~clock ~net address ->
    let client, events = start_client ~switch ~clock ~net address in
    Websocket.connect client ~generation:5 (endpoint address)
    |> check_command "connect" Protocol.Connected;
    Websocket.send client ~generation:5 "trigger unsupported messages"
    |> check_command "trigger" Protocol.Sent;
    ignore
      (await_event clock events (function
         | Protocol.Websocket_message_received
             { generation = 5; kind = Unsupported_binary; _ } -> true
         | _ -> false)
       : Protocol.push);
    ignore
      (await_event clock events (function
         | Protocol.Websocket_message_received
             { generation = 5; kind = Unsupported_text; _ } -> true
         | _ -> false)
       : Protocol.push);
    Websocket.send
      client
      ~generation:5
      (String.make (Policy.maximum_message_bytes + 1) 'x')
    |> check_error "outgoing size" Protocol.Message_too_large;
    Websocket.send client ~generation:5 "\255"
    |> check_error "outgoing UTF-8" Protocol.Invalid_utf8;
    ignore (Websocket.disconnect client ~generation:5);
    Websocket.shutdown client)
;;

let test_oversized_incoming_message_fails_connection () =
  let behavior ~switch _peer wsd =
    Eio.Fiber.fork ~sw:switch (fun () ->
      Eio.Fiber.yield ();
      let payload = Bytes.make (Policy.maximum_message_bytes + 1) 'x' in
      Httpun_ws.Wsd.send_bytes wsd ~kind:`Text payload ~off:0 ~len:(Bytes.length payload));
    let frame ~opcode:_ ~is_fin:_ ~len:_ payload = consume_payload payload ignore in
    let eof ?error:_ () = () in
    { Httpun_ws.Websocket_connection.frame; eof }
  in
  with_websocket_server behavior (fun ~switch ~clock ~net address ->
    let client, events = start_client ~switch ~clock ~net address in
    Websocket.connect client ~generation:6 (endpoint address)
    |> check_command "connect" Protocol.Connected;
    ignore
      (await_event clock events (function
         | Protocol.Websocket_state_changed
             { generation = 6; state = Failed; error = Some Message_too_large } -> true
         | _ -> false)
       : Protocol.push);
    Websocket.shutdown client)
;;

let test_clean_and_abnormal_close () =
  let clean ~switch _peer wsd =
    Eio.Fiber.fork ~sw:switch (fun () ->
      Eio.Fiber.yield ();
      Httpun_ws.Wsd.close ~code:`Normal_closure wsd);
    let frame ~opcode:_ ~is_fin:_ ~len:_ payload = consume_payload payload ignore in
    let eof ?error:_ () = () in
    { Httpun_ws.Websocket_connection.frame; eof }
  in
  with_websocket_server clean (fun ~switch ~clock ~net address ->
    let client, events = start_client ~switch ~clock ~net address in
    Websocket.connect client ~generation:7 (endpoint address)
    |> check_command "connect" Protocol.Connected;
    ignore
      (await_event clock events (function
         | Protocol.Websocket_state_changed { generation = 7; state = Closed; _ } -> true
         | _ -> false)
       : Protocol.push);
    Websocket.shutdown client);
  let abnormal ~switch ~peer:_ tls =
    websocket_server_handler
      (fun ~switch _peer _wsd ->
         Eio.Fiber.fork ~sw:switch (fun () ->
           Eio.Fiber.yield ();
           Eio.Flow.shutdown tls `All;
           Eio.Resource.close tls);
         let frame ~opcode:_ ~is_fin:_ ~len:_ payload = consume_payload payload ignore in
         let eof ?error:_ () = () in
         { Httpun_ws.Websocket_connection.frame; eof })
      ~switch
      ~peer:(`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
      tls
  in
  with_tls_listener abnormal (fun ~switch ~clock ~net address ->
    let client, events = start_client ~switch ~clock ~net address in
    ignore (Websocket.connect client ~generation:8 (endpoint address));
    ignore
      (await_event clock events (function
         | Protocol.Websocket_state_changed
             { generation = 8; state = Failed; error = Some Websocket_protocol_error } ->
           true
         | _ -> false)
       : Protocol.push);
    Websocket.shutdown client)
;;

let test_invalid_upgrade_is_rejected () =
  let raw_server ~switch:_ ~peer:_ tls =
    let buffer = Cstruct.create 4096 in
    ignore (Eio.Flow.single_read tls buffer : int);
    Eio.Flow.copy_string
      "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
      tls;
    Eio.Flow.shutdown tls `Send
  in
  with_tls_listener raw_server (fun ~switch ~clock ~net address ->
    let client, _events = start_client ~switch ~clock ~net address in
    Websocket.connect client ~generation:9 (endpoint address)
    |> check_error "invalid upgrade" Protocol.Websocket_protocol_error;
    Websocket.shutdown client)
;;

let test_commands_during_connecting_fail_without_waiting () =
  Eio_posix.run (fun environment ->
    Eio.Switch.run (fun switch ->
      let clock = Eio.Stdenv.mono_clock environment in
      let connect_started, connect_started_resolver = Eio.Promise.create () in
      let release_connect, release_connect_resolver = Eio.Promise.create () in
      let initial_result, initial_result_resolver = Eio.Promise.create () in
      let client =
        Websocket.create
          ~sw:switch
          ~clock:(clock :> Worker.mono_clock)
          ~connect:(fun ~sw:_ ~clock:_ ~endpoint:_ ->
            ignore (Eio.Promise.try_resolve connect_started_resolver () : bool);
            Eio.Promise.await release_connect;
            Error Protocol.Dns_failure)
          ~emit:ignore
          ()
      in
      Eio.Fiber.fork ~sw:switch (fun () -> Websocket.run client);
      let endpoint =
        Policy.validate_endpoint ~expected:`Wss "wss://example.com/" |> Result.get_ok
      in
      Eio.Fiber.fork ~sw:switch (fun () ->
        Eio.Promise.resolve
          initial_result_resolver
          (Websocket.connect client ~generation:20 endpoint));
      Eio.Promise.await connect_started;
      let promptly label expected operation =
        let result =
          try
            Eio.Time.Timeout.run_exn (Eio.Time.Timeout.seconds clock 0.05) operation
          with
          | Eio.Time.Timeout -> Alcotest.failf "%s waited for the handshake" label
        in
        check_error label expected result
      in
      promptly "duplicate connect while connecting" Protocol.Already_connected (fun () ->
        Websocket.connect client ~generation:21 endpoint);
      promptly "send while connecting" Protocol.Disconnected (fun () ->
        Websocket.send client ~generation:20 "not connected yet");
      promptly "disconnect while connecting" Protocol.Disconnected (fun () ->
        Websocket.disconnect client ~generation:20);
      Eio.Promise.resolve release_connect_resolver ();
      Eio.Promise.await initial_result
      |> check_error "initial failed connection" Protocol.Dns_failure;
      Websocket.shutdown client))
;;

let test_queue_pressure_and_shutdown () =
  Eio_posix.run (fun environment ->
    Eio.Switch.run (fun switch ->
      let clock = Eio.Stdenv.mono_clock environment in
      let connect_called = Eio.Promise.create_resolved () in
      let events_after_shutdown = ref 0 in
      let client =
        Websocket.create
          ~sw:switch
          ~clock:(clock :> Worker.mono_clock)
          ~connect:(fun ~sw:_ ~clock:_ ~endpoint:_ ->
            Eio.Promise.await connect_called;
            Error Protocol.Dns_failure)
          ~emit:(fun _ -> incr events_after_shutdown)
          ~queue_capacity:1
          ()
      in
      Eio.Fiber.fork ~sw:switch (fun () ->
        ignore
          (Websocket.connect
             client
             ~generation:10
             (Policy.validate_endpoint ~expected:`Wss "wss://example.com/"
              |> Result.get_ok)));
      Eio.Fiber.yield ();
      Websocket.send client ~generation:10 "queued"
      |> check_error "full queue" Protocol.Busy;
      Eio.Fiber.fork ~sw:switch (fun () -> Websocket.run client);
      Eio.Fiber.yield ();
      Websocket.shutdown client;
      let event_count = !events_after_shutdown in
      Eio.Fiber.yield ();
      Alcotest.(check int) "no post-shutdown events" event_count !events_after_shutdown))
;;

let () =
  Alcotest.run
    "network WebSocket"
    [ ( "Protocol"
      , [ Alcotest.test_case
            "connects, echoes, disconnects, and rejects invalid commands"
            `Quick
            test_connect_echo_disconnect_and_command_errors
        ; Alcotest.test_case
            "reassembles fragments and answers ping"
            `Quick
            test_fragmentation_and_ping_pong
        ; Alcotest.test_case
            "classifies unsupported messages and outgoing limits"
            `Quick
            test_unsupported_messages_and_outgoing_limits
        ; Alcotest.test_case
            "rejects oversized incoming messages"
            `Quick
            test_oversized_incoming_message_fails_connection
        ; Alcotest.test_case
            "rejects invalid upgrade"
            `Quick
            test_invalid_upgrade_is_rejected
        ; Alcotest.test_case
            "rejects commands promptly while connecting"
            `Quick
            test_commands_during_connecting_fail_without_waiting
        ] )
    ; ( "Lifecycle"
      , [ Alcotest.test_case
            "classifies clean and abnormal close"
            `Quick
            test_clean_and_abnormal_close
        ; Alcotest.test_case
            "bounds queue and emits nothing after shutdown"
            `Quick
            test_queue_pressure_and_shutdown
        ] )
    ]
;;
