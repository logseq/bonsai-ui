(** Renderer-independent queries over a mounted logical tree. *)

type t

val test_id : string -> t
val key : Bonsai_swiftui_ui.Key.t -> t
val role : string -> t
val visible_text : string -> t
val semantics_label : string -> t
val kind : string -> t

module Private : sig
  val matches : t -> Bonsai_swiftui_runtime.Mounted_tree.Snapshot.node -> bool
end
