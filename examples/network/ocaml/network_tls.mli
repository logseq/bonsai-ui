(** TLS configuration, connection ownership, and the protocol-flow adapter. *)

type trust =
  | Nss
  | Certificates of X509.Certificate.t list

type t

val ensure_rng_initialized : unit -> unit

val connect_address
  :  sw:Eio.Switch.t
  -> clock:_ Eio.Time.Mono.t
  -> net:_ Eio.Net.t
  -> address:Eio.Net.Sockaddr.stream
  -> host:string
  -> trust:trust
  -> timeout_seconds:float
  -> (t, Network_protocol.error) result

val connect
  :  sw:Eio.Switch.t
  -> clock:_ Eio.Time.Mono.t
  -> net:_ Eio.Net.t
  -> endpoint:Network_policy.endpoint
  -> (t, Network_protocol.error) result

val stream_socket : t -> [ `Generic ] Eio.Net.stream_socket_ty Eio.Resource.t
val close : t -> unit

module For_testing : sig
  val rng_initialization_count : unit -> int
end
