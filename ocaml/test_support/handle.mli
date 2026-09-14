(** A headless Bonsai runtime with logical-tree queries and renderer events. *)

type t

val create
  :  runtime_epoch:Bonsai_swiftui_spec.Id.Runtime.epoch
  -> time_source:Bonsai.Time_source.t
  -> (Driver.Handler.t -> Bonsai.Cont.graph -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t)
  -> t

(** Creates a headless instance of an [App.t], including its runtime-scoped
    worker lifecycle when applicable. *)
val create_app
  :  runtime_epoch:Bonsai_swiftui_spec.Id.Runtime.epoch
  -> time_source:Bonsai.Time_source.t
  -> App.t
  -> application_payload:bytes
  -> t

val show : t -> string
val show_diff : t -> string
val find : t -> Query.t -> Bonsai_swiftui_runtime.Mounted_tree.Snapshot.node option
val find_all : t -> Query.t -> Bonsai_swiftui_runtime.Mounted_tree.Snapshot.node list
val click : t -> Query.t -> unit
val long_press : t -> Query.t -> unit
val input_text : t -> Query.t -> string -> unit

val apply_text_edit
  :  t
  -> Query.t
  -> local_revision:Bonsai_swiftui_spec.Id.Text_input.local_revision
  -> base_document_revision:Bonsai_swiftui_spec.Id.Text_input.document_revision
  -> text:string
  -> selection_start:int
  -> selection_end:int
  -> ?composing_start:int
  -> ?composing_end:int
  -> unit
  -> unit

val key_down
  :  t
  -> Query.t
  -> logical_key:Bonsai_swiftui_spec.Id.Input.logical_key
  -> unit

val focus : t -> Query.t -> unit
val blur : t -> Query.t -> unit

val tab_selected
  :  t
  -> Query.t
  -> page_key:Bonsai_swiftui_spec.Id.Navigation.page_key
  -> unit

val navigation_split_changed
  :  t
  -> Query.t
  -> state:Bonsai_swiftui_ui.Navigation.Split_state.t
  -> unit

val native_event
  :  t
  -> Query.t
  -> kind_id:Bonsai_swiftui_spec.Id.Native_widget.kind_id
  -> version:int
  -> event_id:Bonsai_swiftui_spec.Id.Native_widget.event_id
  -> payload:bytes
  -> unit

val visible_range : t -> Query.t -> first_index:int64 -> last_exclusive:int64 -> unit
val resize : t -> width:float -> height:float -> unit
val set_environment : t -> Environment.snapshot -> unit

val respond_to_host_effect
  :  t
  -> ?request_id:Bonsai_swiftui_spec.Id.Host.request_id
  -> ?status:Bonsai_swiftui_protocol.Inbound_event.host_response_status
  -> bytes
  -> unit

val present : t -> unit

(** Runs one logical pump using the handle's next monotonic timestamp. *)
val pump_next : t -> ?events:Bonsai_swiftui_protocol.Inbound_event.batch -> unit -> unit

(** Runs one deterministic logical pump using runtime-relative monotonic time.
    Unlike [present], these helpers expose the ABI v2 presentation transaction
    directly. *)
val pump
  :  t
  -> monotonic_now_ns:int64
  -> ?events:Bonsai_swiftui_protocol.Inbound_event.batch
  -> unit
  -> Driver.pump_result

val presentation_succeeded : t -> monotonic_now_ns:int64 -> unit
val presentation_rejected : t -> reason:Driver.rejection_reason -> unit

val unresolved_presentation_id
  :  t
  -> Bonsai_swiftui_spec.Id.Runtime.presentation_id option

val last_frame : t -> Driver.frame option
val revision : t -> Bonsai_swiftui_spec.Id.Runtime.renderer_revision
val pending_host_effect_count : t -> int
val shutdown : t -> unit
