(** Strongly typed application-native widget extensions.

    Extension payloads are opaque to the core renderer. A matching typed SwiftUI
    registration decodes them and owns the native view and resource lifecycle. *)

module Capability : sig
  type t =
    | Stateful
    | Resource
    | Semantics
    | Semantics_canvas
    | Virtualized

  val bit : t -> int64
  val bits : t list -> int64
end

(** Shared native decorative surfaces. Content keeps its layout and event ownership;
    the rounded background, inset border and shadow do not clip it. Gradients use
    evenly spaced colors (2..16); linear gradients run from top to bottom and
    angular gradients start at the trailing edge. Material tint is composited over
    native material. Reduced Transparency uses the tint's opaque RGB color.
    Surfaces introduce no animation. Standard native kind 8, version 1. *)
module Surface : sig
  type recipe =
    | Plain
    | Material_action_group
    | Content_card
    | Inset_section
    | Translucent_sheet
    | Search

  type shape =
    | Rounded
    | Capsule

  type fill =
    | Solid of Style.Color.t
    | Linear of Style.Color.t list
    | Angular of Style.Color.t list
    | Thin_material of Style.Color.t
    | Regular_material of Style.Color.t
    | Ultra_thin_material of Style.Color.t

  type shadow

  (** Finite offsets; finite non-negative blur radius. *)
  val shadow
    :  color:Style.Color.t
    -> radius:float
    -> ?x:float
    -> ?y:float
    -> unit
    -> shadow

  (** Radius and border width must be finite and non-negative. Border width
      defaults to zero for raw surfaces. A recipe supplies omitted paint properties;
      explicit properties take precedence. [content_inset] selects the shared page
      inset; Material_action_group supplies its own compact insets and row spacing.
      Capsule derives its radius from the actual height. [presentation_background] also applies the fill and radius
      to the containing native sheet (default false). Place it at the sheet content
      root. [opacity] in [0, 1] affects only the painted background, not its child.
      Material becomes opaque when Reduce Transparency is enabled.
      The supplied content is the single retained native child. *)
  val create
    :  ?key:Key.t
    -> ?corner_radius:float
    -> ?shadow:shadow
    -> ?border_color:Style.Color.t
    -> ?border_width:float
    -> ?opacity:float
    -> ?presentation_background:bool
    -> ?fill:fill
    -> ?recipe:recipe
    -> ?shape:shape
    -> ?content_inset:bool
    -> View.t
    -> View.t
end

module Extension : sig
  type ('props, 'event) t

  val create
    :  kind_id:Bonsai_swiftui_spec.Id.Native_widget.kind_id
    -> version:int
    -> capabilities:Capability.t list
    -> encode_props:('props -> bytes)
    -> decode_event:
         (event_id:Bonsai_swiftui_spec.Id.Native_widget.event_id
          -> bytes
          -> ('event, string) result)
    -> unit
    -> ('props, 'event) t
end

val event_handler
  :  ?name:string
  -> ('props, 'event) Extension.t
  -> ('event -> unit)
  -> Event.Handler.t

val widget
  :  ('props, 'event) Extension.t
  -> ?key:Key.t
  -> props:'props
  -> on_event:('event -> unit)
  -> ?children:View.t list
  -> unit
  -> View.t

val widget_with_handler
  :  ('props, 'event) Extension.t
  -> ?key:Key.t
  -> props:'props
  -> on_event:Event.Handler.t
  -> ?children:View.t list
  -> unit
  -> View.t

(** A standard SwiftUI composer with an explicitly ephemeral native draft.
    Text observations do not overwrite that draft; sending does not clear it.
    Stable keys retain the draft, UTF-16 selection and marked text through
    configuration changes. A changed key resets ownership. The shared text
    adapter enforces a one-MiB UTF-8 draft limit. *)
module Message_composer : sig
  type button_position =
    | Leading
    | Trailing

  type button_visibility =
    | Always
    | When_empty
    | When_non_empty

  type button_style =
    | Plain
    | Filled

  type button

  type event =
    | Text_changed of string
    | Button_pressed of
        { button_id : int
        ; text : string
        }

  val kind_id : Bonsai_swiftui_spec.Id.Native_widget.kind_id
  val text_changed_event_id : Bonsai_swiftui_spec.Id.Native_widget.event_id
  val button_pressed_event_id : Bonsai_swiftui_spec.Id.Native_widget.event_id

  (** Defines a composer button whose visual content is any OCaml [View.t].
      The native host owns the tap target and reports [id] with the current
      editor text. Button IDs must be positive and unique within a composer. *)
  val button
    :  id:int
    -> tooltip:string
    -> ?position:button_position
    -> ?visibility:button_visibility
    -> ?style:button_style
    -> ?enabled:bool
    -> child:View.t
    -> unit
    -> button

  val create
    :  ?key:Key.t
    -> ?enabled:bool
    -> ?autofocus:bool
    -> ?max_lines:int
    -> ?hint_text:string
    -> buttons:button list
    -> on_event:(event -> unit)
    -> unit
    -> View.t

  val create_with_handler
    :  ?key:Key.t
    -> ?enabled:bool
    -> ?autofocus:bool
    -> ?max_lines:int
    -> ?hint_text:string
    -> buttons:button list
    -> on_event:Event.Handler.t
    -> unit
    -> View.t

  val event_of_payload : Event.Payload.t -> event option

  module For_testing : sig
    type button_props =
      { id : int
      ; tooltip : string
      ; position : button_position
      ; visibility : button_visibility
      ; style : button_style
      ; enabled : bool
      }

    type props =
      { enabled : bool
      ; autofocus : bool
      ; max_lines : int
      ; hint_text : string
      ; buttons : button_props list
      }

    val decode_props_exn : bytes -> props
  end
end

module Expandable_message_composer : sig
  type fab_presentation =
    | Extended
    | Compact

  type button_position =
    | Leading
    | Trailing

  type button_visibility =
    | Always
    | When_empty
    | When_non_empty

  type button_style =
    | Plain
    | Filled

  type button

  type event =
    | Text_changed of string
    | Button_pressed of
        { button_id : int
        ; text : string
        }

  val kind_id : Bonsai_swiftui_spec.Id.Native_widget.kind_id
  val text_changed_event_id : Bonsai_swiftui_spec.Id.Native_widget.event_id
  val button_pressed_event_id : Bonsai_swiftui_spec.Id.Native_widget.event_id

  (** Defines one composer action. The FAB icon is always the first native
      child; button children follow this metadata order. *)
  val button
    :  id:int
    -> tooltip:string
    -> ?position:button_position
    -> ?visibility:button_visibility
    -> ?style:button_style
    -> ?enabled:bool
    -> child:View.t
    -> unit
    -> button

  (** A native SwiftUI launcher and Sheet sharing one ephemeral editor draft.
      Compact/Extended changes retain the open Sheet, draft and selection when
      the logical key is stable. Closing and reopening retain the draft and
      request focus again. The duration and curve animate the launcher; Sheet
      transitions use native behavior. Zero duration and Reduce Motion suppress
      explicit launcher animation. Place the launcher with Body/overlay
      composition. The standard registration uses kind 7, version 2. *)
  val create
    :  ?key:Key.t
    -> ?enabled:bool
    -> fab_presentation:fab_presentation
    -> fab_label:string
    -> fab_tooltip:string
    -> fab_icon:View.t
    -> ?animation_duration_ms:int
    -> ?animation_curve:Animation.Curve.t
    -> ?max_lines:int
    -> ?hint_text:string
    -> buttons:button list
    -> on_event:(event -> unit)
    -> unit
    -> View.t

  val create_with_handler
    :  ?key:Key.t
    -> ?enabled:bool
    -> fab_presentation:fab_presentation
    -> fab_label:string
    -> fab_tooltip:string
    -> fab_icon:View.t
    -> ?animation_duration_ms:int
    -> ?animation_curve:Animation.Curve.t
    -> ?max_lines:int
    -> ?hint_text:string
    -> buttons:button list
    -> on_event:Event.Handler.t
    -> unit
    -> View.t

  val event_of_payload : Event.Payload.t -> event option

  module For_testing : sig
    type button_props =
      { id : int
      ; tooltip : string
      ; position : button_position
      ; visibility : button_visibility
      ; style : button_style
      ; enabled : bool
      }

    type props =
      { enabled : bool
      ; fab_presentation : fab_presentation
      ; fab_label : string
      ; fab_tooltip : string
      ; animation_duration_ms : int
      ; animation_curve : Animation.Curve.t
      ; max_lines : int
      ; hint_text : string
      ; buttons : button_props list
      }

    val decode_props_exn : bytes -> props
  end
end
