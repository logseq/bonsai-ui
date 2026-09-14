(** Bounded HTTP/1.1 GET requests over the private TLS adapter. *)

type connector =
  sw:Eio.Switch.t
  -> clock:Worker.mono_clock
  -> endpoint:Network_policy.endpoint
  -> (Network_tls.t, Network_protocol.error) result

val get
  :  sw:Eio.Switch.t
  -> clock:Worker.mono_clock
  -> connect:connector
  -> ?timeout_seconds:float
  -> Network_policy.endpoint
  -> (Network_protocol.https_summary, Network_protocol.error) result

val get_default
  :  sw:Eio.Switch.t
  -> clock:Worker.mono_clock
  -> net:Worker.net
  -> Network_policy.endpoint
  -> (Network_protocol.https_summary, Network_protocol.error) result
