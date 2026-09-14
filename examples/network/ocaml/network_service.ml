module Policy = Network_policy
module Protocol = Network_protocol

type websocket =
  { run : unit -> unit
  ; connect :
      generation:int
      -> Policy.endpoint
      -> (Protocol.websocket_command, Protocol.error) result
  ; send : generation:int -> string -> (Protocol.websocket_command, Protocol.error) result
  ; disconnect : generation:int -> (Protocol.websocket_command, Protocol.error) result
  ; shutdown : unit -> unit
  }

type providers =
  { https_get :
      sw:Eio.Switch.t
      -> clock:Worker.mono_clock
      -> net:Worker.net
      -> Policy.endpoint
      -> (Protocol.https_summary, Protocol.error) result
  ; websocket :
      sw:Eio.Switch.t
      -> clock:Worker.mono_clock
      -> net:Worker.net
      -> emit:(Protocol.push -> unit)
      -> websocket
  }

type state =
  { websocket : websocket
  ; stopping : bool Atomic.t
  }

let websocket_topic = function
  | Protocol.Websocket_state_changed _ -> Protocol.Topic.websocket_state
  | Websocket_message_received _ -> Protocol.Topic.websocket_message
;;

let create (providers : providers) =
  Worker.Service.create
    ~push_topic_count:Protocol.Topic.count
    ~concurrency:Worker.Service.Serial
    ~init:(fun session () ->
      let stopping = Atomic.make false in
      let websocket =
        providers.websocket
          ~sw:(Worker.Session_context.switch session)
          ~clock:(Worker.Session_context.clock session)
          ~net:(Worker.Session_context.net session)
          ~emit:(fun push ->
            if not (Atomic.get stopping)
            then Worker.Session_context.emit session ~topic:(websocket_topic push) push)
      in
      Worker.Session_context.fork_daemon session ~name:"network-websocket" websocket.run;
      Ok { websocket; stopping })
    ~handle:(fun context state request ->
      match request with
      | Protocol.Https_get { request_id; uri } ->
        let outcome =
          match Policy.validate_endpoint ~expected:`Https uri with
          | Error error -> Error error
          | Ok endpoint ->
            providers.https_get
              ~sw:(Worker.Request_context.switch context)
              ~clock:(Worker.Request_context.clock context)
              ~net:(Worker.Request_context.net context)
              endpoint
        in
        Ok (Protocol.Https_result { request_id; outcome })
      | Websocket_connect { generation; uri } ->
        let outcome =
          match Policy.validate_endpoint ~expected:`Wss uri with
          | Error error -> Error error
          | Ok endpoint -> state.websocket.connect ~generation endpoint
        in
        Ok (Protocol.Websocket_command_result { generation; outcome })
      | Websocket_send { generation; message } ->
        let outcome = state.websocket.send ~generation message in
        Ok (Protocol.Websocket_command_result { generation; outcome })
      | Websocket_disconnect { generation } ->
        let outcome = state.websocket.disconnect ~generation in
        Ok (Protocol.Websocket_command_result { generation; outcome }))
    ~shutdown:(fun state ->
      Atomic.set state.stopping true;
      state.websocket.shutdown ())
    ()
;;

let default_providers =
  { https_get = Network_http.get_default
  ; websocket =
      (fun ~sw ~clock ~net ~emit ->
        let websocket =
          Network_websocket.create ~sw ~clock ~connect:(Network_tls.connect ~net) ~emit ()
        in
        { run = (fun () -> Network_websocket.run websocket)
        ; connect = Network_websocket.connect websocket
        ; send = Network_websocket.send websocket
        ; disconnect = Network_websocket.disconnect websocket
        ; shutdown = (fun () -> Network_websocket.shutdown websocket)
        })
  }
;;

let service = create default_providers
