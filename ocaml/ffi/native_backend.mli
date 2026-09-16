(** OCaml-owned singleton runtime slot behind the stable C ABI.

    C stores only the positive [int64] handle returned here. It never stores an
    OCaml heap value. *)

type status =
  | Ok
  | Recoverable_error
  | Fatal_error

type create_result =
  { status : status
  ; handle : Bonsai_swiftui_spec.Id.Runtime.handle
  ; error : string
  }

type output =
  { status : status
  ; bytes : bytes
  ; presentation_id : Bonsai_swiftui_spec.Id.Runtime.presentation_id
  ; revision : Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  ; error_code : Bonsai_swiftui_spec.Id.Ffi.error_code
  ; error : string
  }

(** Registers an application runtime entrypoint and forces the shared native
    bridge into its complete object. *)
val embed : name:Bonsai_swiftui_spec.Id.Application.entrypoint_name -> App.t -> unit

val create : bytes -> create_result
val shutdown_pump : Bonsai_swiftui_spec.Id.Runtime.handle -> int64 -> bytes -> output
val pump : Bonsai_swiftui_spec.Id.Runtime.handle -> int64 -> bytes -> output

val presentation_succeeded
  :  Bonsai_swiftui_spec.Id.Runtime.handle
  -> Bonsai_swiftui_spec.Id.Runtime.presentation_id
  -> Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  -> int64
  -> output

val presentation_rejected
  :  Bonsai_swiftui_spec.Id.Runtime.handle
  -> Bonsai_swiftui_spec.Id.Runtime.presentation_id
  -> Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  -> int
  -> output

val destroy : Bonsai_swiftui_spec.Id.Runtime.handle -> unit

module For_testing : sig
  type runtime_state =
    | Empty
    | Creating
    | Active
    | Destroying
    | Finalized

  type observations =
    { driver_creations : int
    ; driver_shutdowns : int
    ; active_drivers : int
    ; peak_active_drivers : int
    }

  val state : unit -> runtime_state
  val state_history : unit -> runtime_state list
  val runtime_count : unit -> int
  val observations : unit -> observations
  val reset_observations : unit -> unit
  val clear_state_history : unit -> unit
  val final_shutdown : unit -> unit
end
