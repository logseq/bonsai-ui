(** Isolated Phase 0 proof for the process-wide Eio Worker backend. *)

type t

type diagnostics =
  { backend_run_count : int
  ; worker_domain_id : Domain.id option
  ; processed_requests : int list
  ; attached_session : int option
  ; session_attach_count : int
  ; idle_wait_count : int
  ; join_count : int
  }

val create : request_capacity:int -> t

(** Starts one long-lived Eio POSIX loop on a spawned OCaml Domain. *)
val start : t -> (unit, string) result

(** Publishes out-of-band session controls. These do not consume request
    mailbox capacity. *)
val attach : t -> int -> unit

val detach : t -> unit

(** Performs a non-blocking enqueue into the bounded request mailbox. *)
val try_enqueue_request : t -> int -> [ `Ok | `Full | `Closed ]

val diagnostics : t -> diagnostics

(** Stops and joins a started backend at most once. It is a no-op for a
    backend that was never started. *)
val final_shutdown : t -> unit
