(** Semantic identity supplied by an application for one child among siblings.

    Keys participate in OCaml reconciliation and are never converted into
    node IDs by hashing. *)

type t = Bonsai_swiftui_spec.Id.Ui.application_key

val string : string -> t
val int : int -> t
val int64 : int64 -> t
val compare : t -> t -> int
val equal : t -> t -> bool
val hash : t -> int
val to_debug_string : t -> string
