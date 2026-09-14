(** Stateful allocator and expected-linear tree reconciler. *)

type t

type output =
  { mounted_tree : Mounted_tree.t
  ; frame_patch : Frame_patch.t
  ; handler_frame : Handler_registry.Frame.t
  }

val create : runtime_epoch:Bonsai_swiftui_spec.Id.Runtime.epoch -> t

val reconcile
  :  t
  -> base_revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  -> target_revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  -> old:Mounted_tree.t option
  -> base_handler_frame:Handler_registry.Frame.t option
  -> Bonsai_swiftui_ui.View.t
  -> (output, Runtime_error.t) result
