(** One serialized Bonsai-to-renderer runtime.

    [Driver] owns Bonsai effect scheduling, reconciliation, revision-scoped
    handlers, binary frame encoding, and presentation-gated lifecycle calls. *)

module Handler : sig
  type t

  (** Creates a dependency-aware UI handler whose returned effect is scheduled
      by the next [pump].

      The returned handler retains its physical identity while [dependencies]
      are equal according to [equal]. A dependency change creates a fresh
      handler identity so revision-scoped event dispatch remains safe.

      Every value that can change callback behavior must be included in
      [dependencies]. A false-positive [equal] result can retain stale callback
      behavior; a false-negative result only causes an unnecessary event
      binding update. *)
  val create
    :  t
    -> ?name:string
    -> equal:('dependencies -> 'dependencies -> bool)
    -> 'dependencies Bonsai.Cont.t
    -> f:('dependencies -> Bonsai_swiftui_ui.Event.Payload.t -> unit Bonsai.Effect.t)
    -> Bonsai_swiftui_ui.Event.Handler.t Bonsai.Cont.t

  val create_native
    :  t
    -> ?name:string
    -> ('props, 'event) Bonsai_swiftui_ui.Native_widget.Extension.t
    -> equal:('dependencies -> 'dependencies -> bool)
    -> 'dependencies Bonsai.Cont.t
    -> f:('dependencies -> 'event -> unit Bonsai.Effect.t)
    -> Bonsai_swiftui_ui.Event.Handler.t Bonsai.Cont.t

  val host_effects : t -> Host_effect.t
  val application_platform : t -> Host_effect.Application_platform.t
  val environment : t -> Environment.t

  (** Returns an effect that completes during the next pump after Bonsai has
      applied input actions and before the candidate frame is reconciled. *)
  val wait_before_display : t -> unit Bonsai.Effect.t
end

module View : sig
  type t

  (** The application window bounds its body. Plain content uses [Bonsai_swiftui_ui.View.Body.static]. *)
  val create : theme:Bonsai_swiftui_ui.Theme.t -> body:Bonsai_swiftui_ui.View.Body.t -> t

  module Private : sig
    type view =
      { theme : Bonsai_swiftui_ui.Theme.t
      ; body : Bonsai_swiftui_ui.View.t
      }

    val view : t -> view
  end
end

type frame =
  { revision : Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  ; frame_patch : Bonsai_swiftui_runtime.Frame_patch.t
  ; bytes : bytes
  ; stats : Bonsai_swiftui_protocol.Wire_frame.runtime_stats
  }

type error =
  | Runtime_error of Bonsai_swiftui_runtime.Runtime_error.t
  | Event_error of Bonsai_swiftui_runtime.Event_dispatcher.error
  | Codec_error of Bonsai_swiftui_protocol.Binary_codec.error
  | Unsupported_widget of string
  | Invalid_state of string
  | Lifecycle_error of string
  | Host_response_error of string
  | Application_platform_error of string
  | Shutdown

val error_to_string : error -> string

type pump_result =
  { presentation_id : Bonsai_swiftui_spec.Id.Runtime.presentation_id
  ; renderer_revision : Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  ; frame : frame option
  ; recoverable_error : error option
  }

type rejection_reason =
  | Decode_failed
  | Frame_validation_failed
  | Renderer_epoch_mismatch
  | Renderer_revision_mismatch

type t

val create
  :  ?trace:(string -> unit)
  -> ?before_flush:(schedule:(unit Bonsai.Effect.t -> unit) -> unit)
  -> ?before_shutdown:(unit -> unit)
  -> ?application_title:string
  -> runtime_epoch:Bonsai_swiftui_spec.Id.Runtime.epoch
  -> time_source:Bonsai.Time_source.t
  -> (Handler.t -> Bonsai.Cont.graph -> View.t Bonsai.Cont.t)
  -> t

(** Advances logical time, consumes at most one atomic input batch, drains the
    bounded worker hook, flushes Bonsai once, and reserves one presentation
    token. *)
val pump
  :  t
  -> monotonic_now_ns:int64
  -> ?events:Bonsai_swiftui_protocol.Inbound_event.batch
  -> unit
  -> (pump_result, error) result

val presentation_succeeded
  :  t
  -> presentation_id:Bonsai_swiftui_spec.Id.Runtime.presentation_id
  -> renderer_revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  -> monotonic_now_ns:int64
  -> (unit, error) result

val presentation_rejected
  :  t
  -> presentation_id:Bonsai_swiftui_spec.Id.Runtime.presentation_id
  -> renderer_revision:Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  -> reason:rejection_reason
  -> (unit, error) result

val shutdown : ?application_error:Host_effect.Application_platform.error -> t -> unit
val is_shutdown : t -> bool

module For_testing : sig
  val create_widget_component
    :  ?trace:(string -> unit)
    -> ?before_flush:(schedule:(unit Bonsai.Effect.t -> unit) -> unit)
    -> ?before_shutdown:(unit -> unit)
    -> runtime_epoch:Bonsai_swiftui_spec.Id.Runtime.epoch
    -> time_source:Bonsai.Time_source.t
    -> (Handler.t -> Bonsai.Cont.graph -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t)
    -> t

  val runtime_epoch : t -> Bonsai_swiftui_spec.Id.Runtime.epoch
  val revision : t -> Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  val snapshot : t -> Bonsai_swiftui_runtime.Mounted_tree.Snapshot.t option
  val environment : t -> Environment.snapshot
  val pending_host_effect_count : t -> int
  val pending_application_request_count : t -> int
  val retained_handler_frame_count : t -> int

  val set_next_presentation_id
    :  t
    -> Bonsai_swiftui_spec.Id.Runtime.presentation_id
    -> unit

  val set_next_renderer_revision
    :  t
    -> Bonsai_swiftui_spec.Id.Runtime.renderer_revision
    -> unit
end
