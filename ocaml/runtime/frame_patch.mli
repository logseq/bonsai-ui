(** Atomic logical patches emitted by the OCaml reconciler. *)

module Operation : sig
  type create_node =
    { node_id : Node_id.t
    ; key : Bonsai_swiftui_ui.Key.t option
    ; test_id : Bonsai_swiftui_ui.Test_id.t option
    ; node_tag : Bonsai_swiftui_ui.View.Private.kind_tag
    ; widget : Bonsai_swiftui_ui.View.t
    ; event_bindings : Mounted_tree.Mounted_binding.t array
    }

  type t =
    | Create_node of create_node
    | Update_node of
        { node_id : Node_id.t
        ; widget : Bonsai_swiftui_ui.View.t
        }
    | Update_event_bindings of
        { node_id : Node_id.t
        ; event_bindings : Mounted_tree.Mounted_binding.t array
        }
    | Set_children of
        { node_id : Node_id.t
        ; children : Node_id.t array
        }
    | Set_root of Node_id.t
    | Drop_node of Node_id.t
end

type kind =
  | Full_snapshot
  | Incremental_frame

type t

val kind : t -> kind
val base_revision : t -> Bonsai_swiftui_spec.Id.Runtime.renderer_revision
val target_revision : t -> Bonsai_swiftui_spec.Id.Runtime.renderer_revision
val operations : t -> Operation.t list
val is_empty : t -> bool

val apply
  :  old:Mounted_tree.Snapshot.t option
  -> t
  -> (Mounted_tree.Snapshot.t, Runtime_error.t) result

module Private : sig
  val create
    :  kind:kind
    -> base_revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision
    -> target_revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision
    -> Operation.t list
    -> t
end
