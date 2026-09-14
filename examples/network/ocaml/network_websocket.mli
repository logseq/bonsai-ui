(** A session-owned, single-connection secure WebSocket daemon. *)

type connector =
  sw:Eio.Switch.t
  -> clock:Worker.mono_clock
  -> endpoint:Network_policy.endpoint
  -> (Network_tls.t, Network_protocol.error) result

type t

val create
  :  sw:Eio.Switch.t
  -> clock:Worker.mono_clock
  -> connect:connector
  -> emit:(Network_protocol.push -> unit)
  -> ?queue_capacity:int
  -> unit
  -> t

val run : t -> unit

val connect
  :  t
  -> generation:int
  -> Network_policy.endpoint
  -> (Network_protocol.websocket_command, Network_protocol.error) result

val send
  :  t
  -> generation:int
  -> string
  -> (Network_protocol.websocket_command, Network_protocol.error) result

val disconnect
  :  t
  -> generation:int
  -> (Network_protocol.websocket_command, Network_protocol.error) result

val shutdown : t -> unit
