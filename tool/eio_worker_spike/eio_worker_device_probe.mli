(** Physical-iPhone acceptance probe for the Eio Worker runtime closure. *)

(** Runs the bounded backend and provider checks. The result begins
    with [OK] on success and [FAIL] on failure. *)
val run : directory:string -> string
