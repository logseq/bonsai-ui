type connector =
  sw:Eio.Switch.t
  -> clock:Worker.mono_clock
  -> endpoint:Network_policy.endpoint
  -> (Network_tls.t, Network_protocol.error) result

type receiver =
  { generation : int
  ; buffer : Buffer.t
  ; mutable fragment_kind : [ `Text | `Binary ] option
  ; mutable terminal_emitted : bool
  ; mutable saw_close : bool
  ; close_transport : unit -> unit
  }

type connection =
  { generation : int
  ; tls : Network_tls.t
  ; runtime : Gluten_eio.Client.t
  ; wsd : Httpun_ws.Wsd.t
  ; receiver : receiver
  }

type phase =
  | Idle
  | Connecting of int
  | Live of connection
  | Disconnecting of connection

type outcome = (Network_protocol.websocket_command, Network_protocol.error) result

type command =
  | Connect of
      { generation : int
      ; endpoint : Network_policy.endpoint
      ; resolver : outcome Eio.Promise.u
      }
  | Send of
      { generation : int
      ; message : string
      ; resolver : outcome Eio.Promise.u
      }
  | Disconnect of
      { generation : int
      ; resolver : outcome Eio.Promise.u
      }
  | Stop of unit Eio.Promise.u

type t =
  { sw : Eio.Switch.t
  ; clock : Worker.mono_clock
  ; connect_transport : connector
  ; emit : Network_protocol.push -> unit
  ; queue : command Eio.Stream.t
  ; queue_capacity : int
  ; mutable phase : phase
  ; mutable stopping : bool
  ; mutable running : bool
  }

let create ~sw ~clock ~connect ~emit ?(queue_capacity = 16) () =
  if queue_capacity <= 0 then invalid_arg "WebSocket queue capacity must be positive";
  { sw
  ; clock
  ; connect_transport = connect
  ; emit
  ; queue = Eio.Stream.create queue_capacity
  ; queue_capacity
  ; phase = Idle
  ; stopping = false
  ; running = false
  }
;;

let active_generation t generation =
  match t.phase with
  | Idle -> false
  | Connecting active -> active = generation
  | Live connection | Disconnecting connection -> connection.generation = generation
;;

let emit t push = if not t.stopping then t.emit push

let emit_state t ~generation ?error state =
  emit t (Network_protocol.Websocket_state_changed { generation; state; error })
;;

let emit_message t ~generation ~kind ~message =
  emit t (Network_protocol.Websocket_message_received { generation; kind; message })
;;

let close_connection connection =
  (try Httpun_ws.Wsd.close connection.wsd with
   | _ -> ());
  (try
     ignore (Eio.Promise.await (Gluten_eio.Client.shutdown connection.runtime) : unit)
   with
   | _ -> ());
  Network_tls.close connection.tls
;;

let mark_terminal t receiver state error =
  if not receiver.terminal_emitted
  then (
    receiver.terminal_emitted <- true;
    receiver.close_transport ();
    if active_generation t receiver.generation then t.phase <- Idle;
    emit_state t ~generation:receiver.generation ?error state)
;;

let fail_receiver t receiver error =
  mark_terminal t receiver Network_protocol.Failed (Some error)
;;

let append_payload t receiver payload ~on_complete =
  let rec read () =
    Httpun_ws.Payload.schedule_read
      payload
      ~on_eof:on_complete
      ~on_read:(fun chunk ~off ~len ->
        if Buffer.length receiver.buffer + len > Network_policy.maximum_message_bytes
        then (
          Httpun_ws.Payload.close payload;
          fail_receiver t receiver Network_protocol.Message_too_large)
        else (
          Buffer.add_string receiver.buffer (Bigstringaf.substring chunk ~off ~len);
          read ()))
  in
  read ()
;;

let finish_message t receiver =
  let value = Buffer.contents receiver.buffer in
  (match receiver.fragment_kind with
   | Some `Text when String.is_valid_utf_8 value ->
     emit_message
       t
       ~generation:receiver.generation
       ~kind:Network_protocol.Text
       ~message:(Some value)
   | Some `Text ->
     emit_message
       t
       ~generation:receiver.generation
       ~kind:Network_protocol.Unsupported_text
       ~message:None
   | Some `Binary ->
     emit_message
       t
       ~generation:receiver.generation
       ~kind:Network_protocol.Unsupported_binary
       ~message:None
   | None -> fail_receiver t receiver Network_protocol.Websocket_protocol_error);
  Buffer.clear receiver.buffer;
  receiver.fragment_kind <- None
;;

let consume_control payload callback =
  let buffer = Buffer.create 16 in
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

let frame_handler t receiver wsd ~opcode ~is_fin ~len payload =
  if receiver.terminal_emitted
  then Httpun_ws.Payload.close payload
  else (
    match (opcode : Httpun_ws.Websocket.Opcode.t) with
    | (`Text | `Binary) as kind ->
      if Option.is_some receiver.fragment_kind
      then (
        Httpun_ws.Payload.close payload;
        fail_receiver t receiver Network_protocol.Websocket_protocol_error)
      else (
        receiver.fragment_kind
        <- Some
             (match kind with
              | `Text -> `Text
              | `Binary -> `Binary);
        Buffer.clear receiver.buffer;
        if len > Network_policy.maximum_message_bytes
        then (
          Httpun_ws.Payload.close payload;
          fail_receiver t receiver Network_protocol.Message_too_large)
        else
          append_payload t receiver payload ~on_complete:(fun () ->
            if is_fin then finish_message t receiver))
    | `Continuation ->
      (match receiver.fragment_kind with
       | None ->
         Httpun_ws.Payload.close payload;
         fail_receiver t receiver Network_protocol.Websocket_protocol_error
       | Some _ ->
         if Buffer.length receiver.buffer + len > Network_policy.maximum_message_bytes
         then (
           Httpun_ws.Payload.close payload;
           fail_receiver t receiver Network_protocol.Message_too_large)
         else
           append_payload t receiver payload ~on_complete:(fun () ->
             if is_fin then finish_message t receiver))
    | `Ping ->
      consume_control payload (fun value ->
        let len = String.length value in
        let buffer = Bigstringaf.of_string ~off:0 ~len value in
        Httpun_ws.Wsd.send_pong
          ~application_data:{ Httpun.IOVec.buffer; off = 0; len }
          wsd)
    | `Pong -> consume_control payload ignore
    | `Connection_close ->
      receiver.saw_close <- true;
      consume_control payload (fun _ ->
        (try Httpun_ws.Wsd.close wsd with
         | _ -> ());
        mark_terminal t receiver Network_protocol.Closed None)
    | `Other _ ->
      Httpun_ws.Payload.close payload;
      fail_receiver t receiver Network_protocol.Websocket_protocol_error)
;;

let websocket_handlers t receiver wsd =
  let frame = frame_handler t receiver wsd in
  let eof ?error () =
    if not receiver.terminal_emitted
    then (
      match error, receiver.saw_close with
      | None, true -> mark_terminal t receiver Network_protocol.Closed None
      | None, false | Some _, _ ->
        fail_receiver t receiver Network_protocol.Websocket_protocol_error)
  in
  { Httpun_ws.Websocket_connection.frame; eof }
;;

let sha1 value = value |> Digestif.SHA1.digest_string |> Digestif.SHA1.to_raw_string

let connect_impl t generation endpoint =
  match t.phase with
  | Connecting _ | Live _ | Disconnecting _ -> Error Network_protocol.Already_connected
  | Idle ->
    t.phase <- Connecting generation;
    emit_state t ~generation Network_protocol.Connecting;
    (match t.connect_transport ~sw:t.sw ~clock:t.clock ~endpoint with
     | Error error ->
       t.phase <- Idle;
       emit_state t ~generation ~error Network_protocol.Failed;
       Error error
     | Ok tls ->
       let receiver =
         { generation
         ; buffer = Buffer.create 256
         ; fragment_kind = None
         ; terminal_emitted = false
         ; saw_close = false
         ; close_transport = (fun () -> Network_tls.close tls)
         }
       in
       let handshake, handshake_resolver = Eio.Promise.create () in
       let handshake_resolved = ref false in
       let resolve_handshake value =
         if not !handshake_resolved
         then (
           handshake_resolved := true;
           Eio.Promise.resolve handshake_resolver value)
       in
       let connection =
         Httpun_ws.Client_connection.connect
           ~nonce:(Mirage_crypto_rng.generate 16)
           ~headers:(Httpun.Headers.of_list [ "host", endpoint.Network_policy.authority ])
           ~sha1
           ~error_handler:(fun _ ->
             resolve_handshake (Error Network_protocol.Websocket_protocol_error))
           ~websocket_handler:(fun wsd ->
             resolve_handshake (Ok wsd);
             websocket_handlers t receiver wsd)
           endpoint.resource
       in
       let runtime =
         Gluten_eio.Client.create
           ~sw:t.sw
           ~read_buffer_size:Httpun.Config.default.read_buffer_size
           ~protocol:(module Httpun_ws.Client_connection)
           connection
           (Network_tls.stream_socket tls)
       in
       let handshake_result =
         try
           Eio.Time.Timeout.run_exn
             (Eio.Time.Timeout.seconds t.clock Network_policy.connect_timeout_seconds)
             (fun () -> Eio.Promise.await handshake)
         with
         | Eio.Time.Timeout -> Error Network_protocol.Timeout
       in
       (match handshake_result with
        | Error error ->
          (try ignore (Eio.Promise.await (Gluten_eio.Client.shutdown runtime) : unit) with
           | _ -> ());
          Network_tls.close tls;
          t.phase <- Idle;
          emit_state t ~generation ~error Network_protocol.Failed;
          Error error
        | Ok wsd ->
          let live = { generation; tls; runtime; wsd; receiver } in
          t.phase <- Live live;
          emit_state t ~generation Network_protocol.Connected_state;
          Ok Network_protocol.Connected))
;;

let send_impl t generation message =
  match t.phase with
  | Live connection when connection.generation = generation ->
    if not (String.is_valid_utf_8 message)
    then Error Network_protocol.Invalid_utf8
    else if String.length message > Network_policy.maximum_message_bytes
    then Error Network_protocol.Message_too_large
    else (
      let bytes = Bytes.of_string message in
      Httpun_ws.Wsd.send_bytes
        connection.wsd
        ~kind:`Text
        bytes
        ~off:0
        ~len:(Bytes.length bytes);
      Ok Network_protocol.Sent)
  | Idle | Connecting _ | Disconnecting _ | Live _ -> Error Network_protocol.Disconnected
;;

let disconnect_impl t generation =
  match t.phase with
  | Live connection when connection.generation = generation ->
    t.phase <- Disconnecting connection;
    emit_state t ~generation Network_protocol.Disconnecting;
    (try
       let flushed, resolver = Eio.Promise.create () in
       Httpun_ws.Wsd.close ~code:`Normal_closure connection.wsd;
       Httpun_ws.Wsd.flushed connection.wsd (fun () -> Eio.Promise.resolve resolver ());
       Eio.Time.Timeout.run_exn (Eio.Time.Timeout.seconds t.clock 1.) (fun () ->
         Eio.Promise.await flushed)
     with
     | _ -> ());
    if not connection.receiver.terminal_emitted
    then (
      connection.receiver.terminal_emitted <- true;
      emit_state t ~generation Network_protocol.Closed);
    close_connection connection;
    t.phase <- Idle;
    Ok Network_protocol.Disconnected_command
  | Idle | Connecting _ | Disconnecting _ | Live _ -> Error Network_protocol.Disconnected
;;

let resolve_terminal = function
  | Connect { resolver; _ } | Send { resolver; _ } | Disconnect { resolver; _ } ->
    Eio.Promise.resolve resolver (Error Network_protocol.Shutting_down)
  | Stop resolver -> Eio.Promise.resolve resolver ()
;;

let rec drain_queue t =
  match Eio.Stream.take_nonblocking t.queue with
  | None -> ()
  | Some command ->
    resolve_terminal command;
    drain_queue t
;;

let terminate t =
  if not t.stopping then t.stopping <- true;
  (match t.phase with
   | Live connection | Disconnecting connection -> close_connection connection
   | Idle | Connecting _ -> ());
  t.phase <- Idle;
  drain_queue t
;;

let run t =
  if t.running then invalid_arg "WebSocket daemon is already running";
  t.running <- true;
  Fun.protect
    ~finally:(fun () ->
      terminate t;
      t.running <- false)
    (fun () ->
       let rec loop () =
         match Eio.Stream.take t.queue with
         | Connect { generation; endpoint; resolver } ->
           let outcome =
             try connect_impl t generation endpoint with
             | Eio.Cancel.Cancelled _ as exn -> raise exn
             | _ -> Error Network_protocol.Websocket_protocol_error
           in
           Eio.Promise.resolve resolver outcome;
           loop ()
         | Send { generation; message; resolver } ->
           let outcome =
             try send_impl t generation message with
             | _ -> Error Network_protocol.Websocket_protocol_error
           in
           Eio.Promise.resolve resolver outcome;
           loop ()
         | Disconnect { generation; resolver } ->
           let outcome =
             try disconnect_impl t generation with
             | Eio.Cancel.Cancelled _ as exn -> raise exn
             | _ -> Error Network_protocol.Websocket_protocol_error
           in
           Eio.Promise.resolve resolver outcome;
           loop ()
         | Stop resolver ->
           t.stopping <- true;
           (match t.phase with
            | Live connection | Disconnecting connection -> close_connection connection
            | Idle | Connecting _ -> ());
           t.phase <- Idle;
           drain_queue t;
           Eio.Promise.resolve resolver ()
       in
       loop ())
;;

let submit t command =
  if t.stopping
  then Error Network_protocol.Shutting_down
  else if Eio.Stream.length t.queue >= t.queue_capacity
  then Error Network_protocol.Busy
  else (
    Eio.Stream.add t.queue command;
    Ok ())
;;

let connect t ~generation endpoint =
  if t.stopping
  then Error Network_protocol.Shutting_down
  else (
    match t.phase with
    | Connecting _ | Live _ | Disconnecting _ -> Error Network_protocol.Already_connected
    | Idle ->
      let result, resolver = Eio.Promise.create () in
      (match submit t (Connect { generation; endpoint; resolver }) with
       | Error error -> Error error
       | Ok () -> Eio.Promise.await result))
;;

let send t ~generation message =
  if t.stopping
  then Error Network_protocol.Shutting_down
  else (
    match t.phase with
    | Connecting _ | Disconnecting _ -> Error Network_protocol.Disconnected
    | Idle | Live _ ->
      let result, resolver = Eio.Promise.create () in
      (match submit t (Send { generation; message; resolver }) with
       | Error error -> Error error
       | Ok () -> Eio.Promise.await result))
;;

let disconnect t ~generation =
  if t.stopping
  then Error Network_protocol.Shutting_down
  else (
    match t.phase with
    | Connecting _ | Disconnecting _ -> Error Network_protocol.Disconnected
    | Idle | Live _ ->
      let result, resolver = Eio.Promise.create () in
      (match submit t (Disconnect { generation; resolver }) with
       | Error error -> Error error
       | Ok () -> Eio.Promise.await result))
;;

let shutdown t =
  if not t.stopping
  then (
    let stopped, resolver = Eio.Promise.create () in
    Eio.Stream.add t.queue (Stop resolver);
    Eio.Promise.await stopped)
;;
