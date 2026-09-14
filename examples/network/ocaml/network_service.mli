(** Worker service that owns HTTPS requests and one session WebSocket. *)

type websocket =
  { run : unit -> unit
  ; connect :
      generation:int
      -> Network_policy.endpoint
      -> (Network_protocol.websocket_command, Network_protocol.error) result
  ; send :
      generation:int
      -> string
      -> (Network_protocol.websocket_command, Network_protocol.error) result
  ; disconnect :
      generation:int
      -> (Network_protocol.websocket_command, Network_protocol.error) result
  ; shutdown : unit -> unit
  }

type providers =
  { https_get :
      sw:Eio.Switch.t
      -> clock:Worker.mono_clock
      -> net:Worker.net
      -> Network_policy.endpoint
      -> (Network_protocol.https_summary, Network_protocol.error) result
  ; websocket :
      sw:Eio.Switch.t
      -> clock:Worker.mono_clock
      -> net:Worker.net
      -> emit:(Network_protocol.push -> unit)
      -> websocket
  }

val create
  :  providers
  -> ( unit
       , Network_protocol.request
       , Network_protocol.response
       , Network_protocol.push )
       Worker.Service.t

val service
  : ( unit
      , Network_protocol.request
      , Network_protocol.response
      , Network_protocol.push )
      Worker.Service.t
