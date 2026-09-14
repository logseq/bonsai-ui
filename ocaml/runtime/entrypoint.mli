(** Process-wide registry of applications linked into the native artifact. *)

val register : name:Bonsai_swiftui_spec.Id.Application.entrypoint_name -> App.t -> unit

module Private : sig
  val find : Bonsai_swiftui_spec.Id.Application.entrypoint_name -> App.t option
end

module For_testing : sig
  val clear : unit -> unit
  val find : Bonsai_swiftui_spec.Id.Application.entrypoint_name -> App.t option
end
