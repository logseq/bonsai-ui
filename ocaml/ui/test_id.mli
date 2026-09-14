(** Stable application-supplied identity used only by headless and renderer tests. *)

type t = Bonsai_swiftui_spec.Id.Ui.test_id

val string : string -> t
val equal : t -> t -> bool
val to_string : t -> string
