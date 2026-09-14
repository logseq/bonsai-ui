module ID = Bonsai_swiftui_spec.Id

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
      { expected : ID.Runtime.renderer_revision
      ; actual : ID.Runtime.renderer_revision
      }
  | Wrong_runtime_epoch of
      { expected : ID.Runtime.epoch
      ; actual : ID.Runtime.epoch
      }
  | Stale_event of { revision : ID.Runtime.renderer_revision }
  | Duplicate_or_out_of_order_event of { sequence : ID.Runtime.event_sequence }
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

let duplicate_side_to_string = function
  | Existing -> "existing"
  | Candidate -> "candidate"
;;

let path_segment_to_string { kind; key } =
  let kind = Bonsai_swiftui_ui.View.Private.kind_tag_to_string kind in
  match key with
  | None -> kind
  | Some key ->
    Printf.sprintf "%s[key=%s]" kind (Bonsai_swiftui_ui.Key.to_debug_string key)
;;

let duplicate_occurrence_to_string key { child_index; kind } =
  Printf.sprintf
    "child[%d]: %s[key=%s]"
    child_index
    (Bonsai_swiftui_ui.View.Private.kind_tag_to_string kind)
    (Bonsai_swiftui_ui.Key.to_debug_string key)
;;

let duplicate_path_to_string parent_path =
  parent_path
  |> List.mapi (fun index segment ->
    Printf.sprintf
      "  %s%s"
      (if index = 0 then "" else "> ")
      (path_segment_to_string segment))
  |> String.concat "\n"
;;

let to_string = function
  | Duplicate_key { key; side; parent_path; first; second } ->
    Printf.sprintf
      "duplicate key %s in %s children\n\n\
       View tree path:\n\
       %s\n\n\
       Duplicate siblings:\n\
      \  %s\n\
      \  %s"
      (Bonsai_swiftui_ui.Key.to_debug_string key)
      (duplicate_side_to_string side)
      (duplicate_path_to_string parent_path)
      (duplicate_occurrence_to_string key first)
      (duplicate_occurrence_to_string key second)
  | Invalid_patch message -> "invalid patch: " ^ message
  | Revision_mismatch { expected; actual } ->
    Printf.sprintf
      "revision mismatch: expected %Ld, got %Ld"
      (ID.Runtime.Renderer_revision.to_int64 expected)
      (ID.Runtime.Renderer_revision.to_int64 actual)
  | Wrong_runtime_epoch { expected; actual } ->
    Printf.sprintf
      "runtime epoch mismatch: expected %Ld, got %Ld"
      (ID.Runtime.Epoch.to_int64 expected)
      (ID.Runtime.Epoch.to_int64 actual)
  | Stale_event { revision } ->
    Printf.sprintf
      "stale event for revision %Ld"
      (ID.Runtime.Renderer_revision.to_int64 revision)
  | Duplicate_or_out_of_order_event { sequence } ->
    Printf.sprintf
      "duplicate or out-of-order event sequence %Ld"
      (ID.Runtime.Event_sequence.to_int64 sequence)
  | Handler_missing { handler_id } ->
    Printf.sprintf "missing handler %Ld" (Handler_id.to_int64 handler_id)
  | Handler_mismatch { handler_id; node_id; event_tag } ->
    Printf.sprintf
      "handler %Ld does not match node %Ld and event %s"
      (Handler_id.to_int64 handler_id)
      (Node_id.to_int64 node_id)
      (Bonsai_swiftui_ui.Event.Tag.to_string event_tag)
  | Handler_exception { handler_id; message; backtrace = _ } ->
    Printf.sprintf "handler %Ld raised: %s" (Handler_id.to_int64 handler_id) message
;;
