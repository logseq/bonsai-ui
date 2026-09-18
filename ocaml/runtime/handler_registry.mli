(** Revision-scoped OCaml event handlers. *)

module Frame : sig
  type entry =
    { node_id : Node_id.t
    ; event_tag : Bonsai_swiftui_ui.Event.Tag.t
    ; handler_id : Handler_id.t
    ; handler : Bonsai_swiftui_ui.Event.Handler.t
    }

  type t

  val revision : t -> Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  val find : t -> Handler_id.t -> entry option
  val find_list_scroll_completion : t -> Node_id.t -> entry option

  module Private : sig
    val create
      :  revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision
      -> entry list
      -> t

    val empty : revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision -> t

    val derive
      :  revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision
      -> base_revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision
      -> base:t
      -> removals:Handler_id.t list
      -> additions:entry list
      -> t
  end
end

type event =
  { runtime_epoch : Bonsai_swiftui_spec.Id.Runtime.epoch
  ; displayed_revision : Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  ; node_id : Node_id.t
  ; event_tag : Bonsai_swiftui_ui.Event.Tag.t
  ; handler_id : Handler_id.t
  ; event_sequence : Bonsai_swiftui_spec.Id.Runtime.event_sequence
  ; payload : Bonsai_swiftui_ui.Event.Payload.t
  }

type t

val create : runtime_epoch:Bonsai_swiftui_spec.Id.Runtime.epoch -> t
val install : t -> Frame.t -> (unit, Runtime_error.t) result

(** Marks a revision as displayed without retiring any handler frames. *)
val mark_displayed_revision
  :  t
  -> revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  -> (unit, Runtime_error.t) result

(** Retires handler frames strictly older than [revision]. *)
val retire_before : t -> revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision -> unit

(** Retires frames older than the revision immediately preceding the displayed
    revision. This bounded grace period accepts input that SwiftUI queued while
    the next frame was being committed. *)
val retire_superseded
  :  t
  -> displayed_revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  -> unit

(** Marks a revision displayed and retires frames outside the grace period.

    Runtime drivers that must run lifecycle work between those operations
    should call [mark_displayed_revision] and [retire_superseded] separately. *)
val commit_displayed_revision
  :  t
  -> revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  -> (unit, Runtime_error.t) result

module Validated_batch : sig
  type t
end

val validate_batch : t -> event list -> (Validated_batch.t, Runtime_error.t) result
val dispatch_validated : t -> Validated_batch.t -> (unit, Runtime_error.t) result
val dispatch : t -> event -> (unit, Runtime_error.t) result
val dispatch_batch : t -> event list -> (unit, Runtime_error.t) result
val retained_frame_count : t -> int
val clear : t -> unit

(** Retain only the original callback for a newly displayed request token.
    Repeating or clearing a token never rebinds it. Terminal events require this
    exact snapshot, independently of ordinary revision-scoped input bindings. *)
val retain_list_scroll_completion
  :  t
  -> revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  -> token:int64
  -> Frame.entry
  -> unit

val dispose_list_scroll_owner : t -> Node_id.t -> unit
val clear_list_scroll_completions : t -> unit
