(** Secure HTTPS and WebSocket example application. *)

val create
  :  https_endpoint:string
  -> websocket_endpoint:string
  -> service:
       ( unit
         , Network_protocol.request
         , Network_protocol.response
         , Network_protocol.push )
         Worker.Service.t
  -> unit
  -> App.t

val app : App.t
