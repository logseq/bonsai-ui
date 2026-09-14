(** The OCaml-owned mounted renderer tree. *)

type t

module Mounted_binding : sig
  type t =
    { event_tag : Bonsai_swiftui_ui.Event.Tag.t
    ; handler_id : Handler_id.t
    }
end

module Snapshot : sig
  type node =
    { node_id : Node_id.t
    ; key : Bonsai_swiftui_ui.Key.t option
    ; test_id : Bonsai_swiftui_ui.Test_id.t option
    ; node_tag : Bonsai_swiftui_ui.View.Private.kind_tag
    ; widget : Bonsai_swiftui_ui.View.t
    ; event_bindings : Mounted_binding.t array
    ; children : Node_id.t array
    }

  type t

  val empty : t
  val equal : t -> t -> bool
  val root_id : t -> Node_id.t option
  val node_count : t -> int
  val find : t -> Node_id.t -> node option
  val find_by_key : t -> Bonsai_swiftui_ui.Key.t -> node option
  val find_by_test_id : t -> Bonsai_swiftui_ui.Test_id.t -> node option
  val find_by_text : t -> string -> node option

  module Private : sig
    val create : root_id:Node_id.t option -> node list -> t
    val nodes : t -> node list
  end
end

val root_id : t -> Node_id.t
val node_count : t -> int
val snapshot : t -> Snapshot.t

module Private : sig
  type node =
    { node_id : Node_id.t
    ; key : Bonsai_swiftui_ui.Key.t option
    ; test_id : Bonsai_swiftui_ui.Test_id.t option
    ; node_tag : Bonsai_swiftui_ui.View.Private.kind_tag
    ; event_bindings : Mounted_binding.t array
    ; handlers : Bonsai_swiftui_ui.Event.Handler.t array
    ; children : node array
    ; source_widget : Bonsai_swiftui_ui.View.t
    }

  val root : t -> node
  val create : node -> t
end
