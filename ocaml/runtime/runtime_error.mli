(** Structured errors that may safely cross the runtime boundary. *)

type tree_side =
  | Existing
  | Candidate

type path_segment =
  { kind : Bonsai_swiftui_ui.View.Private.kind_tag
  ; key : Bonsai_swiftui_ui.Key.t option
  }

type duplicate_occurrence =
  { child_index : int
  ; kind : Bonsai_swiftui_ui.View.Private.kind_tag
  }

type t =
  | Duplicate_key of
      { key : Bonsai_swiftui_ui.Key.t
      ; side : tree_side
      ; parent_path : path_segment list
      ; first : duplicate_occurrence
      ; second : duplicate_occurrence
      }
  | Invalid_patch of string
  | Revision_mismatch of
      { expected : Bonsai_swiftui_spec.Id.Runtime.renderer_revision
      ; actual : Bonsai_swiftui_spec.Id.Runtime.renderer_revision
      }
  | Wrong_runtime_epoch of
      { expected : Bonsai_swiftui_spec.Id.Runtime.epoch
      ; actual : Bonsai_swiftui_spec.Id.Runtime.epoch
      }
  | Stale_event of { revision : Bonsai_swiftui_spec.Id.Runtime.renderer_revision }
  | Duplicate_or_out_of_order_event of
      { sequence : Bonsai_swiftui_spec.Id.Runtime.event_sequence }
  | Handler_missing of { handler_id : Handler_id.t }
  | Handler_mismatch of
      { handler_id : Handler_id.t
      ; node_id : Node_id.t
      ; event_tag : Bonsai_swiftui_ui.Event.Tag.t
      }
  | Handler_exception of
      { handler_id : Handler_id.t
      ; message : string
      ; backtrace : string
      }

val to_string : t -> string
