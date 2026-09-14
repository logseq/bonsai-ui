module Date : sig
  type t = private
    { year : int
    ; month : int
    ; day : int
    }

  val create : year:int -> month:int -> day:int -> t
  val compare : t -> t -> int
end

module Time : sig
  type t = private
    { hour : int
    ; minute : int
    }

  val create : hour:int -> minute:int -> t
end

module Control_size : sig
  type t =
    | Mini
    | Small
    | Regular
    | Large
    | Extra_large
end

module Toggle_style : sig
  type t =
    | Automatic
    | Switch
    | Checkbox
    | Button
end

module Safe_area_regions : sig
  type t =
    | Container
    | Keyboard
    | All
end

module Progress_style : sig
  type t =
    | Linear
    | Circular
end

module Button_role : sig
  type t =
    | Normal
    | Cancel
    | Destructive
end

module Button_style : sig
  type t =
    | Automatic
    | Plain
    | Bordered
    | Prominent
end

(** Immutable, typed logical UI nodes.

    This module is renderer-independent. Application keys are optional and
    event closures remain in OCaml. *)

type t

(** Compile-time evidence that a widget root has an application key. *)
module Keyed : sig
  type widget = t
  type t

  (** [create ~key widget] returns [widget] with [key] on its existing root.
      Any previous root key is replaced; no wrapper node is added. *)
  val create : key:Key.t -> widget -> t
end

val with_test_id : Test_id.t -> t -> t
val empty : ?key:Key.t -> unit -> t

(** Native progress. Omit [value] for indeterminate activity; a supplied value
    must be finite and between zero and one. Style changes retain node identity. *)
val progress : ?key:Key.t -> ?value:float -> ?style:Progress_style.t -> unit -> t

(** Literal native Text. The optional line limit must be positive; omission
    permits unlimited lines. Truncation defaults to Tail, alignment to Start.
    Clipping and layout sizing are separate view modifiers. *)
val text
  :  ?key:Key.t
  -> ?style:Style.Text_style.t
  -> ?text_align:Style.Text_align.t
  -> ?line_limit:int
  -> ?truncation:Style.Text_truncation.t
  -> string
  -> t

(** One native Text with attributed runs, including Unicode and embedded newlines.
    Runs wrap together and inherit unspecified font/color attributes. *)
val rich_text : ?key:Key.t -> Style.Text_span.t list -> t

module Symbol_rendering : sig
  type t =
    | Monochrome
    | Hierarchical
    | Multicolor
end

(** An SF Symbols system image. [size] is an optional positive point size;
    otherwise the symbol inherits its surrounding font. Color inherits the
    surrounding foreground style when omitted. Names must exist on the target
    OS; the renderer rejects unavailable symbols. Use a semantics wrapper to
    label meaningful images; symbol content itself is decorative. *)
val symbol
  :  ?key:Key.t
  -> ?size:float
  -> ?color:Style.Color.t
  -> ?rendering:Symbol_rendering.t
  -> name:string
  -> unit
  -> t

(** Native Divider. Its parent stack determines orientation; use padding for
    spacing and indentation. Thickness and appearance follow the platform. *)
val divider : ?key:Key.t -> unit -> t

(** Native SwiftUI Label with view content for its title and icon. Both slots
    inherit the surrounding native label style and environment. Use a Button
    around a display label for activation; place accessory actions beside it. *)
val label : ?key:Key.t -> title:t -> icon:t -> unit -> t

(** A decorative overlay anchored at the content's top edge. Omitted count
    displays a dot; zero displays zero. Counts must be non-negative. Alignment
    is directional and visibility does not remove or disable content. Supply
    meaningful count/notification text through the content's semantics. *)
val badge
  :  ?key:Key.t
  -> ?count:int
  -> ?alignment:Layout.Horizontal_alignment.t
  -> ?visible:bool
  -> t
  -> t

(** OCaml-controlled modal content. Native dismissal requests deliver Bool false.
    iOS detents are Medium/Large; the initial detent defaults to the first entry.
    macOS retains its native sheet sizing. Content stays logically mounted. *)
module Sheet : sig
  type detent =
    | Medium
    | Large

  type sizing =
    | Automatic
    | Fitted
    | Form
    | Page

  (** Native presentation size proposal; iOS detents separately control height. *)
  val create
    :  ?key:Key.t
    -> ?sizing:sizing
    -> ?detents:detent list
    -> ?initial_detent:detent
    -> ?interactive_dismiss:bool
    -> ?shows_drag_indicator:bool
    -> presented:bool
    -> on_presented_changed:Event.Handler.t
    -> content:t
    -> t
    -> t

  (** Native fullscreen cover on iOS, native sheet on macOS. Close explicitly
      through OCaml; interactive dismissal is disabled. *)
  val full_screen
    :  ?key:Key.t
    -> presented:bool
    -> on_presented_changed:Event.Handler.t
    -> content:t
    -> t
    -> t
end

(** A native anchored presentation with OCaml-owned visibility. Native dismissal
    requests deliver [Event.Payload.Bool false]. Open through an ordinary Button
    or another OCaml state change. Content remains logically mounted while closed. *)
module Popover : sig
  type edge =
    | Automatic
    | Top
    | Bottom
    | Leading
    | Trailing

  val create
    :  ?key:Key.t
    -> ?edge:edge
    -> presented:bool
    -> on_presented_changed:Event.Handler.t
    -> content:t
    -> t
    -> t
end

(** Native help text and accessibility hint. The message must not be blank. *)
val help : ?key:Key.t -> message:string -> t -> t

(** A native GroupBox with optional view content in its label. Content occupies
    the first child slot so adding or removing a label preserves its identity.
    Compose buttons in the label or content for independent actions. *)
val group_box : ?key:Key.t -> ?label:t -> t -> t

(** An asynchronously loaded native image. Original sizing and scale 1 are the
    defaults. Scale is positive, finite pixels per point; size and clipping use
    separate frame/clip modifiers. Source changes cancel the obsolete load. *)
val image
  :  ?key:Key.t
  -> ?sizing:Style.Image_sizing.t
  -> ?scale:float
  -> source:Style.Image_source.t
  -> unit
  -> t

(** A native scrollable plain-text editor. Selection and composing state use
    the revisioned Text_editing contract. Return inserts a newline by default;
    submit_on_return sends on_submit outside composition. Use frame and padding
    for layout. max_utf8_bytes, when provided, is in 1..1048576. *)
val text_editor
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?read_only:bool
  -> ?submit_on_return:bool
  -> ?max_utf8_bytes:int
  -> session_id:Bonsai_swiftui_spec.Id.Text_input.session_id
  -> document_revision:Bonsai_swiftui_spec.Id.Text_input.document_revision
  -> accepted_local_revision:Bonsai_swiftui_spec.Id.Text_input.local_revision
  -> update_mode:Text_editing.update_mode
  -> value:Text_editing.Value.t
  -> on_edit:Event.Handler.t
  -> on_submit:Event.Handler.t
  -> on_focus_changed:Event.Handler.t
  -> ?on_limit_reached:Event.Handler.t
  -> unit
  -> t

(** Native single-line text entry with revisioned editing. Return submits by
    default. Layout, adornments and supporting text use ordinary composition. *)
val text_field
  :  ?key:Key.t
  -> label:string
  -> ?prompt:string
  -> ?keyboard:Text_editing.Keyboard.t
  -> ?submit_label:Text_editing.Submit_label.t
  -> ?autofocus:bool
  -> ?enabled:bool
  -> ?read_only:bool
  -> ?submit_on_return:bool
  -> ?max_utf8_bytes:int
  -> session_id:Bonsai_swiftui_spec.Id.Text_input.session_id
  -> document_revision:Bonsai_swiftui_spec.Id.Text_input.document_revision
  -> accepted_local_revision:Bonsai_swiftui_spec.Id.Text_input.local_revision
  -> update_mode:Text_editing.update_mode
  -> value:Text_editing.Value.t
  -> on_edit:Event.Handler.t
  -> on_submit:Event.Handler.t
  -> on_focus_changed:Event.Handler.t
  -> ?on_limit_reached:Event.Handler.t
  -> unit
  -> t

(** Native secure text entry with the same revision and event contract. *)
val secure_field
  :  ?key:Key.t
  -> label:string
  -> ?prompt:string
  -> ?keyboard:Text_editing.Keyboard.t
  -> ?submit_label:Text_editing.Submit_label.t
  -> ?autofocus:bool
  -> ?enabled:bool
  -> ?read_only:bool
  -> ?submit_on_return:bool
  -> ?max_utf8_bytes:int
  -> session_id:Bonsai_swiftui_spec.Id.Text_input.session_id
  -> document_revision:Bonsai_swiftui_spec.Id.Text_input.document_revision
  -> accepted_local_revision:Bonsai_swiftui_spec.Id.Text_input.local_revision
  -> update_mode:Text_editing.update_mode
  -> value:Text_editing.Value.t
  -> on_edit:Event.Handler.t
  -> on_submit:Event.Handler.t
  -> on_focus_changed:Event.Handler.t
  -> ?on_limit_reached:Event.Handler.t
  -> unit
  -> t

(** Wrap intrinsic children into top-aligned rows within the proposed width.
    Spacing values must be finite and non-negative. An unconstrained width uses
    one row; children wider than the proposal may overflow without clipping. *)
val flow
  :  ?key:Key.t
  -> ?spacing:float
  -> ?line_spacing:float
  -> ?alignment:Layout.Horizontal_alignment.t
  -> t list
  -> t

(** Native HStack. An omitted spacing uses SwiftUI's default; an explicit
    spacing must be finite and may be negative. Vertical alignment includes
    first and last text baselines. *)
val row
  :  ?key:Key.t
  -> ?spacing:float
  -> ?alignment:Layout.Vertical_alignment.t
  -> t list
  -> t

(** Native VStack with leading, center, or trailing alignment. Spacing follows
    the same contract as [row]. *)
val column
  :  ?key:Key.t
  -> ?spacing:float
  -> ?alignment:Layout.Horizontal_alignment.t
  -> t list
  -> t

(** Native ZStack, using the nine direction-aware frame alignments. *)
val stack : ?key:Key.t -> ?alignment:Layout.Alignment.t -> t list -> t

(** Sets native layout priority. Any finite value is accepted. *)
val layout_priority : ?key:Key.t -> float -> t -> t

(** Offsets rendered content without changing its layout measurement. The
    finite x/y point distances default to zero and may be negative. *)
val offset : ?key:Key.t -> ?x:float -> ?y:float -> t -> t

val padding : ?key:Key.t -> insets:Layout.Edge_insets.t -> t -> t

(** A native adaptive spacer. An omitted minimum uses the platform default;
    an explicit minimum must be finite and non-negative. Use [min_length:0.]
    inside a fixed frame for an exact blank gap. An [empty] view is omitted
    by SwiftUI even when framed and cannot reserve that space. *)
val spacer : ?key:Key.t -> ?min_length:float -> unit -> t

(** Adds a native SwiftUI frame. Omitted dimensions follow the child's layout
    proposal. [Fill] expands along that axis when space is available. A fixed
    dimension cannot be combined with min/ideal/max values on the same axis.
    All point dimensions must be finite and non-negative, with min <= ideal
    <= max for each supplied pair. Framing does not imply clipping. *)
val frame
  :  ?key:Key.t
  -> ?width:float
  -> ?height:float
  -> ?min_width:float
  -> ?ideal_width:float
  -> ?max_width:Layout.Frame_limit.t
  -> ?min_height:float
  -> ?ideal_height:float
  -> ?max_height:Layout.Frame_limit.t
  -> ?alignment:Layout.Alignment.t
  -> t
  -> t

(** Adds a solid native background without changing layout or clipping the child.
    [corner_radius] defaults to zero and must be finite and non-negative. *)
val background : ?key:Key.t -> ?corner_radius:float -> color:Style.Color.t -> t -> t

(** Clips to a continuous rounded rectangle. The radius defaults to zero and
    must be finite and non-negative; [antialiased] defaults to true. *)
val clip : ?key:Key.t -> ?corner_radius:float -> ?antialiased:bool -> t -> t

val opacity : ?key:Key.t -> float -> t -> t

(** Publish a target and native animation intent. Initial mount uses the target
    without completion. Changed intents replace earlier pending completions;
    [on_completed] receives [Event.Payload.Int64 animation_id] after completion
    while the node is mounted, active and presented. *)
val animated_opacity
  :  ?key:Key.t
  -> animation:Animation.t
  -> opacity:float
  -> on_completed:Event.Handler.t
  -> t
  -> t

(** Apply a native plane projection without changing the child layout extent.
    Modifier nesting determines composition order. *)
val projection_effect : ?key:Key.t -> transform:Style.Projection.t -> t -> t

(** Axis-specific scrolling content that is not an ordinary widget until it is
    placed in a bounded body slot or given an explicit finite extent. *)
module Viewport : sig
  type widget = t

  module Vertical : sig
    type t

    val with_test_id : Test_id.t -> t -> t
    val padding : insets:Layout.Edge_insets.t -> t -> t
    val background : ?corner_radius:float -> color:Style.Color.t -> t -> t
    val semantics : properties:Semantics.t -> t -> t

    val ignores_safe_area
      :  ?regions:Safe_area_regions.t
      -> ?edges:Layout.Edge.t list
      -> t
      -> t

    val safe_area_padding : insets:Layout.Edge_insets.t -> t -> t
    val theme : data:Theme.t -> t -> t
    val overlay : ?key:Key.t -> ?alignment:Layout.Alignment.t -> overlay:widget -> t -> t
    val with_height : height:float -> t -> widget
  end

  module Horizontal : sig
    type t

    val with_test_id : Test_id.t -> t -> t
    val padding : insets:Layout.Edge_insets.t -> t -> t
    val background : ?corner_radius:float -> color:Style.Color.t -> t -> t
    val semantics : properties:Semantics.t -> t -> t

    val ignores_safe_area
      :  ?regions:Safe_area_regions.t
      -> ?edges:Layout.Edge.t list
      -> t
      -> t

    val safe_area_padding : insets:Layout.Edge_insets.t -> t -> t
    val theme : data:Theme.t -> t -> t
    val overlay : ?key:Key.t -> ?alignment:Layout.Alignment.t -> overlay:widget -> t -> t
    val with_width : width:float -> t -> widget
  end
end

module Scroll_anchor : sig
  type t =
    | Start
    | End
end

(** A native SwiftUI ScrollView containing ordinary view content. The content
    is eager; use [Collection] for windowed materialization. [fill_viewport]
    defaults to false. When true, content receives at least the viewport extent
    along the scroll axis, while retaining any larger intrinsic size. A Weighted
    stack with fixed header/footer items and a share distributes that extra space.

    Native geometry observations deliver [Event.Payload.Scroll] in points along
    the scroll axis. Horizontal pixels increase from logical leading in either
    layout direction. The initial sample and each resumed observer establish a
    baseline. Native scroll phase changes deliver zero-delta boundaries.
    Adjacent same-direction increments may merge; reversals, zero increments,
    other events and presented-revision changes remain ordered. The optional
    [on_scroll] binding is also available on Scroll_sections, Scroll_targets and
    Collection without replacing their position or visible-range bindings. *)
module Scroll : sig
  val vertical
    :  ?key:Key.t
    -> ?on_scroll:Event.Handler.t
    -> ?shows_indicators:bool
    -> ?fill_viewport:bool
    -> ?initial_anchor:Scroll_anchor.t
    -> t
    -> Viewport.Vertical.t

  val horizontal
    :  ?key:Key.t
    -> ?on_scroll:Event.Handler.t
    -> ?shows_indicators:bool
    -> ?fill_viewport:bool
    -> ?initial_anchor:Scroll_anchor.t
    -> t
    -> Viewport.Horizontal.t
end

(** Native lazy sections with optional pinned headers and footers. Section and row
    keys are unique within their respective sibling lists. A stretching hero is
    allowed only as the first section of a vertical container. *)
module Scroll_sections : sig
  type section

  val section : key:Key.t -> ?header:t -> ?footer:t -> Keyed.t list -> section
  val hero : key:Key.t -> height:float -> ?stretch:bool -> t -> section

  val vertical
    :  ?key:Key.t
    -> ?on_scroll:Event.Handler.t
    -> ?pin_headers:bool
    -> ?pin_footers:bool
    -> ?spacing:float
    -> ?shows_indicators:bool
    -> ?initial_anchor:Scroll_anchor.t
    -> section list
    -> Viewport.Vertical.t

  val horizontal
    :  ?key:Key.t
    -> ?on_scroll:Event.Handler.t
    -> ?pin_headers:bool
    -> ?pin_footers:bool
    -> ?spacing:float
    -> ?shows_indicators:bool
    -> ?initial_anchor:Scroll_anchor.t
    -> section list
    -> Viewport.Horizontal.t
end

(** Per-item removal. Bind commands to the application's stable item key.
    Pending preserves the item; Rejected restores it; Accepted animates collapse
    and then reports [Event.Payload.Int64 request_token] through on_removed.
    Request payloads contain the token and logical direction. A replacement
    token cancels older transient state and completion. *)
module Removal : sig
  type request_state =
    | Ready
    | Pending
    | Accepted
    | Rejected

  type direction =
    | Start_to_end
    | End_to_start
    | Up
    | Down

  val request_of_payload : Event.Payload.t -> (int64 * direction) option

  val create
    :  key:Key.t
    -> ?axis:Layout.Axis.t
    -> ?collapse_axis:Layout.Axis.t
    -> ?title:string
    -> ?duration_ms:int
    -> request_token:int64
    -> request_state:request_state
    -> on_request:Event.Handler.t
    -> on_removed:Event.Handler.t
    -> t
    -> t
end

(** Attach refresh before other viewport decorations. Each new request uses a
    new token. Pending acknowledges a request; Completed releases its native async
    action. Changes to show_token trigger the same action programmatically. *)
module Refresh : sig
  type request_state =
    | Ready
    | Pending
    | Completed

  val vertical
    :  ?key:Key.t
    -> ?show_token:int64
    -> request_token:int64
    -> request_state:request_state
    -> on_request:Event.Handler.t
    -> Viewport.Vertical.t
    -> Viewport.Vertical.t
end

(** Native scroll targets with OCaml-controlled position. Nonempty content requires
    a position naming an item; empty content requires None. The fraction is in
    (0, 1], spacing is finite and nonnegative, and item IDs are unique.
    Position changes deliver [Event.Payload.Int64]. Compose Buttons for actions. *)
module Scroll_targets : sig
  type alignment =
    | Start
    | Center
    | End

  type item

  val item : id:int64 -> t -> item

  val horizontal
    :  ?key:Key.t
    -> ?on_scroll:Event.Handler.t
    -> ?fraction:float
    -> ?spacing:float
    -> ?alignment:alignment
    -> ?snapping:bool
    -> ?enabled:bool
    -> ?shows_indicators:bool
    -> position:int64 option
    -> on_position_changed:Event.Handler.t
    -> item list
    -> Viewport.Horizontal.t

  val vertical
    :  ?key:Key.t
    -> ?on_scroll:Event.Handler.t
    -> ?fraction:float
    -> ?spacing:float
    -> ?alignment:alignment
    -> ?snapping:bool
    -> ?enabled:bool
    -> ?shows_indicators:bool
    -> position:int64 option
    -> on_position_changed:Event.Handler.t
    -> item list
    -> Viewport.Vertical.t
end

(** An axis-specific collection with an immutable key/extent catalog and a bounded,
    keyed materialized window. Catalog changes and window changes are distinct
    protocol updates. Extents are heights in vertical collections and widths in
    horizontal collections. Horizontal placement follows layout direction. *)
module Collection : sig
  (** [Declared] uses exact supplied extents. [Measured] uses them as estimates
      until SwiftUI measures each materialized row's intrinsic extent. The
      non-negative revision must change when content can invalidate cached
      offscreen sizes. Width/height, Dynamic Type, layout direction and scoped
      font-family changes invalidate native measurements automatically. Rows
      must have a finite positive intrinsic extent along the scrolling axis;
      use minimum sizes rather than filling that axis. *)
  type sizing =
    | Declared
    | Measured of { revision : int64 }

  module Initial_position : sig
    type t =
      | Start
      | End
      | Item of Key.t
  end

  type extent =
    { index : int
    ; extent : float
    }

  module Catalog : sig
    type t

    (** Durations are unsigned 32-bit milliseconds and default to zero.
        Expansion uses ease-out cubic; collapse uses ease-in-out cubic.
        The native host interpolates sparse extent changes for stable keys.
        Structural changes and reduced motion resolve immediately. *)
    val create
      :  keys:Key.t list
      -> default_extent:float
      -> ?sizing:sizing
      -> ?overrides:extent list
      -> ?overscan:int
      -> ?expand_duration_ms:int
      -> ?collapse_duration_ms:int
      -> unit
      -> t

    val count : t -> int
  end

  module Window : sig
    type t =
      { first_index : int
      ; last_exclusive : int
      }

    val create
      :  catalog:Catalog.t
      -> visible_first_index:int
      -> visible_last_exclusive:int
      -> t
  end

  val vertical
    :  ?key:Key.t
    -> ?initial_position:Initial_position.t
    -> ?on_scroll:Event.Handler.t
    -> catalog:Catalog.t
    -> first_index:int
    -> items:Keyed.t list
    -> on_visible_range:Event.Handler.t
    -> unit
    -> Viewport.Vertical.t

  val horizontal
    :  ?key:Key.t
    -> ?initial_position:Initial_position.t
    -> ?on_scroll:Event.Handler.t
    -> catalog:Catalog.t
    -> first_index:int
    -> items:Keyed.t list
    -> on_visible_range:Event.Handler.t
    -> unit
    -> Viewport.Horizontal.t

  val visible_range_of_payload : Event.Payload.t -> Event.Payload.visible_range option
end

(** Native views respect their host's safe areas by default. Expand into the
    selected regions and directional edges explicitly. Defaults to Container
    and all four edges; an empty edge list preserves the native safe area. *)
val ignores_safe_area
  :  ?key:Key.t
  -> ?regions:Safe_area_regions.t
  -> ?edges:Layout.Edge.t list
  -> t
  -> t

(** Add signed finite insets to the safe area seen by descendants. *)
val safe_area_padding : ?key:Key.t -> insets:Layout.Edge_insets.t -> t -> t

(** Set the native SwiftUI control-size environment for descendants. *)
val control_size : ?key:Key.t -> size:Control_size.t -> t -> t

val gesture
  :  ?key:Key.t
  -> ?on_tap:Event.Handler.t
  -> ?on_double_tap:Event.Handler.t
  -> ?on_long_press:Event.Handler.t
  -> ?on_pointer_down:Event.Handler.t
  -> ?on_pointer_up:Event.Handler.t
  -> t
  -> t

(** Observe whether the scope or any descendant owns native keyboard focus.
    Moving focus between descendants does not emit another change. [autofocus]
    requests focus once after the scope is mounted, enabled, and presented;
    later activation does not steal focus after that request succeeds. *)
val focus_scope
  :  ?key:Key.t
  -> ?autofocus:bool
  -> on_focus_changed:Event.Handler.t
  -> t
  -> t

(** Observe pointer entry and exit within the child's bounds without changing its
    layout or intercepting native control actions. [blocks_behind] defaults to
    [true] and excludes overlapping hover regions behind this region; containing
    ancestor regions still receive transitions. *)
val hover_region
  :  ?key:Key.t
  -> ?blocks_behind:bool
  -> on_enter:Event.Handler.t
  -> on_leave:Event.Handler.t
  -> t
  -> t

val keyboard_listener
  :  ?key:Key.t
  -> ?autofocus:bool
  -> ?key_policy:Event.Key_policy.t
  -> on_key:Event.Handler.t
  -> t
  -> t

val semantics
  :  ?key:Key.t
  -> ?on_action:Event.Handler.t
  -> properties:Semantics.t
  -> t
  -> t

val theme : ?key:Key.t -> data:Theme.t -> t -> t

module Date_picker : sig
  val create
    :  ?key:Key.t
    -> ?label:string
    -> ?enabled:bool
    -> ?selectable_dates:Date.t list
    -> selected:Date.t
    -> first:Date.t
    -> last:Date.t
    -> on_select:Event.Handler.t
    -> unit
    -> t
end

module Time_picker : sig
  type format =
    | System
    | Hour_12
    | Hour_24

  val create
    :  ?key:Key.t
    -> ?label:string
    -> ?enabled:bool
    -> ?format:format
    -> value:Time.t
    -> on_changed:Event.Handler.t
    -> unit
    -> t
end

module Menu : sig
  type entry

  val action
    :  id:int64
    -> label:t
    -> ?enabled:bool
    -> ?role:Button_role.t
    -> unit
    -> entry

  val choice : id:int64 -> label:t -> selected:bool -> ?enabled:bool -> unit -> entry
  val divider : id:int64 -> entry
  val section : id:int64 -> ?label:t -> entry list -> entry
  val submenu : id:int64 -> label:t -> ?enabled:bool -> entry list -> entry

  val create
    :  ?key:Key.t
    -> ?enabled:bool
    -> on_select:Event.Handler.t
    -> label:t
    -> entry list
    -> t
end

module Picker : sig
  type choice

  type style =
    | Automatic
    | Menu
    | Segmented
    | Inline

  val option : id:int64 -> ?enabled:bool -> ?label:t -> unit -> choice

  val create
    :  ?key:Key.t
    -> ?label:string
    -> ?style:style
    -> ?enabled:bool
    -> selected_id:int64 option
    -> on_select:Event.Handler.t
    -> choice list
    -> unit
    -> t
end

(** Overlays content without changing the base view's measurement. Alignment
    defaults to Center and follows layout direction. Compose frame, padding and
    offset on the overlay to express anchors; overflow is not implicitly clipped. *)
val overlay : ?key:Key.t -> ?alignment:Layout.Alignment.t -> overlay:t -> t -> t

(** Native action control. [autofocus] defaults to false. A requested focus
    waits for presentation and enablement, and stops retrying after native
    focus is acquired. Changing false to true requests focus again. *)
val button
  :  ?key:Key.t
  -> ?enabled:bool
  -> ?role:Button_role.t
  -> ?style:Button_style.t
  -> ?autofocus:bool
  -> on_press:Event.Handler.t
  -> child:t
  -> unit
  -> t

(** Proposal-based weighted stacks. Fixed items measure intrinsically along
    the main axis; shares receive proportional remaining space. An unspecified
    main-axis proposal measures every item intrinsically. *)
module Weighted : sig
  type child

  val fixed : t -> child

  (** [weight] defaults to one and must be finite and positive. [fills] defaults
      to true; false lets the child shrink within its proposed share. Shares
      do not redistribute space left unused by another content-sized child. *)
  val share : ?weight:float -> ?fills:bool -> t -> child

  val row
    :  ?key:Key.t
    -> ?spacing:float
    -> ?alignment:Layout.Vertical_alignment.t
    -> child list
    -> t

  val column
    :  ?key:Key.t
    -> ?spacing:float
    -> ?alignment:Layout.Horizontal_alignment.t
    -> child list
    -> t
end

(** Native toolbar content attached to a navigation page or window. Each item
    has a stable application key and contains an ordinary Button, Toggle, Menu,
    label or other core view. The system owns placement and overflow. *)
module Toolbar : sig
  type placement =
    | Automatic
    | Principal
    | Navigation
    | Primary_action
    | Secondary_action
    | Status
    | Confirmation_action
    | Cancellation_action
    | Destructive_action

  type item

  val item : key:Key.t -> ?placement:placement -> t -> item

  (** Empty lists remove all items; at most 256 items and one principal item.
      Item keys must be unique. Content is the first child and retains its identity. *)
  val create : ?key:Key.t -> items:item list -> t -> t
end

(** Content validated for framework slots that provide finite constraints. *)
module Body : sig
  type widget = t
  type t

  (** Supply finite positive bounds before embedding a body in ordinary content. *)
  val with_size : width:float -> height:float -> t -> widget

  val static : widget -> t
  val with_test_id : Test_id.t -> t -> t
  val padding : insets:Layout.Edge_insets.t -> t -> t
  val background : ?corner_radius:float -> color:Style.Color.t -> t -> t
  val semantics : properties:Semantics.t -> t -> t

  val ignores_safe_area
    :  ?regions:Safe_area_regions.t
    -> ?edges:Layout.Edge.t list
    -> t
    -> t

  val safe_area_padding : insets:Layout.Edge_insets.t -> t -> t
  val theme : data:Theme.t -> t -> t
  val toolbar : ?key:Key.t -> items:Toolbar.item list -> t -> t

  module Vertical : sig
    type child

    val fixed : widget -> child
    val fill : ?weight:float -> Viewport.Vertical.t -> child
    val create : ?key:Key.t -> child list -> t
  end

  module Horizontal : sig
    type child

    val fixed : widget -> child
    val fill : ?weight:float -> Viewport.Horizontal.t -> child
    val create : ?key:Key.t -> child list -> t
  end

  val overlay : ?key:Key.t -> ?alignment:Layout.Alignment.t -> overlay:widget -> t -> t

  module Private : sig
    val to_widget : t -> widget
  end
end

(** A finite native table. Compact width presents every labeled cell in rows. *)
module Table : sig
  type column
  type row

  (** Native headers use title. Arbitrary details and help remain available in
      the Column details disclosure. Numeric cells align to the trailing edge. *)
  val column
    :  id:int64
    -> title:string
    -> ?help:string
    -> ?numeric:bool
    -> ?sortable:bool
    -> ?details:t
    -> unit
    -> column

  val row : id:int64 -> ?selection_enabled:bool -> t list -> row

  (** Stable row/column IDs scope cell identity. OCaml owns canonical sorting and
      selection; callbacks carry Int64_bool (column/direction or row/membership).
      Select-all and cell actions are ordinary application Buttons. *)
  val create
    :  ?key:Key.t
    -> ?sort_column_id:int64
    -> ?sort_ascending:bool
    -> ?selected_row_ids:int64 list
    -> ?on_sort:Event.Handler.t
    -> ?on_row_selected:Event.Handler.t
    -> columns:column list
    -> rows:row list
    -> unit
    -> Body.t
end

module Navigation_stack : sig
  type destination

  val destination
    :  ?key:Key.t
    -> page_key:Bonsai_swiftui_spec.Id.Navigation.page_key
    -> title:string
    -> ?can_pop:bool
    -> Body.t
    -> destination

  (** Root and destination pages provide finite constraints to typed bodies.
      The root is outside the path. Native back actions request a shorter path
      through [Navigation_path_changed]; OCaml owns acceptance and pushes. *)
  val create
    :  ?key:Key.t
    -> title:string
    -> on_path_change:Event.Handler.t
    -> path:destination list
    -> Body.t
    -> t
end

(** Two or three bounded native columns, each accepting typed scrolling content. *)
module Navigation_split : sig
  val create
    :  ?key:Key.t
    -> state:Navigation.Split_state.t
    -> sidebar_title:string
    -> content_title:string
    -> detail_title:string
    -> on_change:Event.Handler.t
    -> sidebar:Body.t
    -> content:Body.t
    -> detail:Body.t
    -> unit
    -> t

  (** Sidebar and detail without a middle content column. The state's preferred
      compact column must be Sidebar or Detail; Content raises Invalid_argument. *)
  val two_columns
    :  ?key:Key.t
    -> state:Navigation.Split_state.t
    -> sidebar_title:string
    -> detail_title:string
    -> on_change:Event.Handler.t
    -> sidebar:Body.t
    -> detail:Body.t
    -> unit
    -> t
end

(** Native controlled DisclosureGroup. Changes deliver [Event.Payload.Bool].
    The label belongs to the disclosure control; its nested controls cannot emit
    input. Collapsed content is retained logically and excluded from input and
    accessibility. [enabled=false] disables the header and expanded content. *)
val disclosure_group
  :  ?key:Key.t
  -> ?enabled:bool
  -> expanded:bool
  -> on_changed:Event.Handler.t
  -> label:t
  -> content:t
  -> unit
  -> t

(** A controlled Boolean control. Changes deliver [Event.Payload.Bool].
    Labels describe the control; nested interactive label content cannot dispatch input. *)
val toggle
  :  ?key:Key.t
  -> ?style:Toggle_style.t
  -> ?enabled:bool
  -> value:bool
  -> on_changed:Event.Handler.t
  -> label:t
  -> unit
  -> t

module Slider : sig
  module Range : sig
    type t

    val create : start:float -> end_:float -> t
  end

  (** Values are controlled by OCaml. Optional change handlers receive continuous
      updates; the required end handler receives the final value. Step is an
      optional positive interval in domain units. Vertical sliders need bounded height. *)
  val create
    :  ?key:Key.t
    -> ?min:float
    -> ?max:float
    -> ?step:float
    -> ?enabled:bool
    -> ?axis:Layout.Axis.t
    -> ?on_change:Event.Handler.t
    -> value:float
    -> label:string
    -> on_change_end:Event.Handler.t
    -> unit
    -> t

  val range
    :  ?key:Key.t
    -> ?min:float
    -> ?max:float
    -> ?step:float
    -> ?enabled:bool
    -> ?axis:Layout.Axis.t
    -> ?on_change:Event.Handler.t
    -> value:Range.t
    -> label_start:string
    -> label_end:string
    -> on_change_end:Event.Handler.t
    -> unit
    -> t
end

module Swipe_actions : sig
  type action

  type side =
    | Start
    | End
    (** Start and End follow layout direction horizontally, and mean top and bottom vertically.
      At most one action per side may be triggered by a full swipe. OCaml owns removal. *)

  val action
    :  ?key:Key.t
    -> ?enabled:bool
    -> ?role:Button_role.t
    -> ?extent:float
    -> ?auto_close:bool
    -> ?full_swipe:bool
    -> side:side
    -> title:string
    -> background:Style.Color.t
    -> on_press:Event.Handler.t
    -> child:t
    -> unit
    -> action

  val create
    :  key:Key.t
    -> ?enabled:bool
    -> ?axis:Layout.Axis.t
    -> ?close_on_scroll:bool
    -> ?group:string
    -> ?close_when_opened:bool
    -> ?close_when_tapped:bool
    -> actions:action list
    -> content:t
    -> unit
    -> t
end

module Morphing_surface : sig
  (** Retains both keyed content branches while animating their surface and
      intrinsic height. Only the selected branch accepts input or accessibility
      actions. Native Reduce Motion and scene inactivity finish the transition.
      Durations are unsigned 32-bit milliseconds; zero disables interpolation. *)
  val create
    :  ?key:Key.t
    -> ?expand_duration_ms:int
    -> ?collapse_duration_ms:int
    -> expanded:bool
    -> compact_content:t
    -> expanded_content:t
    -> unit
    -> t
end

module Tabs : sig
  type item

  (** Each page has a nonempty stable key and an SF Symbol name. Its bounded
      content may contain typed scroll or collection viewports. Badge text and
      accessibility labels must be nonblank when present; omitted metadata uses
      native defaults. Badge text preserves zero and large counts literally. *)
  val item
    :  ?key:Key.t
    -> ?badge:string
    -> ?accessibility_label:string
    -> page_key:Bonsai_swiftui_spec.Id.Navigation.page_key
    -> title:string
    -> symbol:string
    -> Body.t
    -> item

  (** One to 256 pages with unique byte-exact keys. Selection must identify a
      page. Native selections emit [Tab_selected]; OCaml owns accepted state.
      Reordering pages preserves their identity and their content state. *)
  val create
    :  ?key:Key.t
    -> selection:Bonsai_swiftui_spec.Id.Navigation.page_key
    -> on_change:Event.Handler.t
    -> item list
    -> t
end

module For_testing : sig
  val kind_name : t -> string
  val key : t -> Key.t option
  val test_id : t -> Test_id.t option
  val children : t -> t array
  val text_content : t -> string option
end

module Private : sig
  type kind_tag =
    | K_empty
    | K_spacer
    | K_text
    | K_rich_text
    | K_symbol
    | K_image
    | K_text_editor
    | K_text_field
    | K_secure_field
    | K_collection_catalog
    | K_collection_window
    | K_removal
    | K_refresh
    | K_scroll_targets
    | K_scroll
    | K_flow
    | K_row
    | K_column
    | K_weighted_row
    | K_weighted_column
    | K_stack
    | K_layout_priority
    | K_offset
    | K_padding
    | K_frame
    | K_background
    | K_clip
    | K_opacity
    | K_animated_opacity
    | K_projection_effect
    | K_gesture
    | K_focus_scope
    | K_hover_region
    | K_keyboard_listener
    | K_button
    | K_semantics
    | K_theme
    | K_date_picker
    | K_time_picker
    | K_menu
    | K_picker
    | K_slider
    | K_range_slider
    | K_table
    | K_divider
    | K_label
    | K_badge
    | K_sheet
    | K_popover
    | K_scroll_sections
    | K_scroll_section
    | K_toolbar
    | K_help
    | K_group_box
    | K_progress
    | K_overlay
    | K_disclosure_group
    | K_toggle
    | K_swipe_actions
    | K_swipe_action
    | K_morphing_surface
    | K_tabs
    | K_tab
    | K_navigation_split
    | K_navigation_stack
    | K_navigation_destination
    | K_ignores_safe_area
    | K_safe_area_padding
    | K_control_size
    | K_native_widget

  val kind_tag_compare : kind_tag -> kind_tag -> int
  val kind_tag_equal : kind_tag -> kind_tag -> bool
  val kind_tag_to_string : kind_tag -> string

  type weighted_sizing =
    | Intrinsic
    | Share of
        { weight : float
        ; fills : bool
        }

  type menu_item =
    { menu_id : int64
    ; kind : int
    ; enabled : bool
    ; selected : bool
    ; role : int
    ; has_label : bool
    ; child_count : int
    }

  type picker_option =
    { option_id : int64
    ; enabled : bool
    ; has_label : bool
    }

  type table_column =
    { column_id : int64
    ; title : string
    ; has_details : bool
    ; tooltip : string option
    ; numeric : bool
    ; sortable : bool
    }

  type table_row =
    { row_id : int64
    ; selection_enabled : bool
    }

  type 'k node =
    | Empty : [ `Empty ] node
    | Spacer : { min_length : float option } -> [ `Spacer ] node
    | Text :
        { value : string
        ; style : Style.Text_style.Private.view option
        ; text_align : Style.Text_align.t
        ; line_limit : int option
        ; truncation : Style.Text_truncation.t
        }
        -> [ `Text ] node
    | Rich_text : { spans : Style.Text_span.Private.view list } -> [ `Rich_text ] node
    | Symbol :
        { name : string
        ; size : float option
        ; color : int32 option
        ; rendering : Symbol_rendering.t
        }
        -> [ `Symbol ] node
    | Removal :
        { request_token : int64
        ; request_state : int
        ; vertical : bool
        ; collapse_vertical : bool
        ; title : string
        ; duration_ms : int
        }
        -> [ `Removal ] node
    | Refresh :
        { request_token : int64
        ; request_state : int
        ; show_token : int64 option
        }
        -> [ `Refresh ] node
    | Scroll_targets :
        { vertical : bool
        ; ids : int64 list
        ; position : int64 option
        ; fraction : float
        ; spacing : float
        ; alignment : int
        ; snapping : bool
        ; enabled : bool
        ; shows_indicators : bool
        }
        -> [ `Scroll_targets ] node
    | Scroll :
        { vertical : bool
        ; shows_indicators : bool
        ; fill_viewport : bool
        ; initial_anchor : int
        }
        -> [ `Scroll ] node
    | Collection_catalog :
        { keys : string array
        ; default_extent : float
        ; overrides : (int * float) list
        ; overscan : int
        ; expand_duration_ms : int
        ; collapse_duration_ms : int
        ; vertical : bool
        ; initial_anchor : int
        ; initial_key : string option
        ; measurement_revision : int64 option
        }
        -> [ `Collection_catalog ] node
    | Collection_window :
        { first_index : int
        ; keys : string array
        }
        -> [ `Collection_window ] node
    | Text_editor :
        { session_id : Bonsai_swiftui_spec.Id.Text_input.session_id
        ; document_revision : Bonsai_swiftui_spec.Id.Text_input.document_revision
        ; accepted_local_revision : Bonsai_swiftui_spec.Id.Text_input.local_revision
        ; update_mode : Text_editing.update_mode
        ; value : Text_editing.Value.t
        ; enabled : bool
        ; read_only : bool
        ; submit_on_return : bool
        ; max_utf8_bytes : int option
        }
        -> [ `Text_editor ] node
    | Text_field :
        { session_id : Bonsai_swiftui_spec.Id.Text_input.session_id
        ; document_revision : Bonsai_swiftui_spec.Id.Text_input.document_revision
        ; accepted_local_revision : Bonsai_swiftui_spec.Id.Text_input.local_revision
        ; update_mode : Text_editing.update_mode
        ; value : Text_editing.Value.t
        ; enabled : bool
        ; read_only : bool
        ; submit_on_return : bool
        ; max_utf8_bytes : int option
        ; label : string
        ; prompt : string
        ; secure : bool
        ; keyboard : Text_editing.Keyboard.t
        ; submit_label : Text_editing.Submit_label.t
        ; autofocus : bool
        }
        -> [ `Text_field ] node
    | Image :
        { source : Style.Image_source.t
        ; sizing : Style.Image_sizing.t
        ; scale : float
        }
        -> [ `Image ] node
    | Flow :
        { spacing : float
        ; line_spacing : float
        ; alignment : Layout.Horizontal_alignment.t
        }
        -> [ `Flow ] node
    | Row :
        { spacing : float option
        ; alignment : Layout.Vertical_alignment.t
        }
        -> [ `Row ] node
    | Column :
        { spacing : float option
        ; alignment : Layout.Horizontal_alignment.t
        }
        -> [ `Column ] node
    | Weighted_row :
        { spacing : float option
        ; alignment : Layout.Vertical_alignment.t
        ; items : weighted_sizing list
        }
        -> [ `Weighted_row ] node
    | Weighted_column :
        { spacing : float option
        ; alignment : Layout.Horizontal_alignment.t
        ; items : weighted_sizing list
        }
        -> [ `Weighted_column ] node
    | Stack : { alignment : Layout.Alignment.t } -> [ `Stack ] node
    | Layout_priority : { priority : float } -> [ `Layout_priority ] node
    | Offset :
        { x : float
        ; y : float
        }
        -> [ `Offset ] node
    | Button :
        { enabled : bool
        ; role : Button_role.t
        ; style : Button_style.t
        ; autofocus : bool
        }
        -> [ `Button ] node
    | Padding :
        { leading : float
        ; top : float
        ; trailing : float
        ; bottom : float
        }
        -> [ `Padding ] node
    | Frame :
        { width : float option
        ; height : float option
        ; min_width : float option
        ; ideal_width : float option
        ; max_width : Layout.Frame_limit.t option
        ; min_height : float option
        ; ideal_height : float option
        ; max_height : Layout.Frame_limit.t option
        ; alignment : Layout.Alignment.t
        }
        -> [ `Frame ] node
    | Background :
        { color : int32
        ; corner_radius : float
        }
        -> [ `Background ] node
    | Clip :
        { corner_radius : float
        ; antialiased : bool
        }
        -> [ `Clip ] node
    | Opacity : { opacity : float } -> [ `Opacity ] node
    | Animated_opacity :
        { opacity : float
        ; animation : Animation.t
        }
        -> [ `Animated_opacity ] node
    | Projection_effect : { matrix3 : float array } -> [ `Projection_effect ] node
    | Gesture : [ `Gesture ] node
    | Focus_scope : { autofocus : bool } -> [ `Focus_scope ] node
    | Hover_region : { blocks_behind : bool } -> [ `Hover_region ] node
    | Keyboard_listener :
        { autofocus : bool
        ; key_policy : Event.Key_policy.t
        }
        -> [ `Keyboard_listener ] node
    | Semantics : Semantics.Private.view -> [ `Semantics ] node
    | Theme : Theme.Private.view -> [ `Theme ] node
    | Date_picker :
        { selected : Date.t
        ; first : Date.t
        ; last : Date.t
        ; selectable_dates : Date.t list
        ; label : string
        ; enabled : bool
        }
        -> [ `Date_picker ] node
    | Time_picker :
        { value : Time.t
        ; format : int
        ; label : string
        ; enabled : bool
        }
        -> [ `Time_picker ] node
    | Menu :
        { items : menu_item list
        ; enabled : bool
        }
        -> [ `Menu ] node
    | Picker :
        { selected_id : int64 option
        ; options : picker_option list
        ; label : string
        ; style : int
        ; enabled : bool
        }
        -> [ `Picker ] node
    | Slider :
        { value : float
        ; min : float
        ; max : float
        ; step : float option
        ; label : string
        ; enabled : bool
        ; vertical : bool
        ; has_on_change : bool
        }
        -> [ `Slider ] node
    | Range_slider :
        { start : float
        ; end_ : float
        ; min : float
        ; max : float
        ; step : float option
        ; label_start : string
        ; label_end : string
        ; enabled : bool
        ; vertical : bool
        ; has_on_change : bool
        }
        -> [ `Range_slider ] node
    | Table :
        { columns : table_column list
        ; rows : table_row list
        ; sort_column_id : int64 option
        ; sort_ascending : bool
        ; selected_row_ids : int64 list
        ; has_on_sort : bool
        ; has_on_row_selected : bool
        }
        -> [ `Table ] node
    | Divider : [ `Divider ] node
    | Label : [ `Label ] node
    | Badge :
        { count : int option
        ; alignment : Layout.Horizontal_alignment.t
        ; visible : bool
        }
        -> [ `Badge ] node
    | Sheet :
        { presented : bool
        ; fullscreen : bool
        ; detents : int
        ; initial : int
        ; interactive : bool
        ; indicator : bool
        ; sizing : int
        }
        -> [ `Sheet ] node
    | Popover :
        { presented : bool
        ; edge : int
        }
        -> [ `Popover ] node
    | Scroll_sections :
        { vertical : bool
        ; pin_headers : bool
        ; pin_footers : bool
        ; spacing : float
        ; shows_indicators : bool
        ; initial_anchor : int
        }
        -> [ `Scroll_sections ] node
    | Scroll_section :
        { has_header : bool
        ; has_footer : bool
        ; hero_height : float option
        ; stretch : bool
        }
        -> [ `Scroll_section ] node
    | Toolbar : { placements : int list } -> [ `Toolbar ] node
    | Help : { message : string } -> [ `Help ] node
    | Group_box : { has_label : bool } -> [ `Group_box ] node
    | Progress :
        { value : float option
        ; style : Progress_style.t
        }
        -> [ `Progress ] node
    | Overlay : { alignment : Layout.Alignment.t } -> [ `Overlay ] node
    | Disclosure_group :
        { expanded : bool
        ; enabled : bool
        }
        -> [ `Disclosure_group ] node
    | Toggle :
        { value : bool
        ; enabled : bool
        ; style : int
        }
        -> [ `Toggle ] node
    | Swipe_actions :
        { enabled : bool
        ; vertical : bool
        ; close_on_scroll : bool
        ; group : string option
        ; close_when_opened : bool
        ; close_when_tapped : bool
        }
        -> [ `Swipe_actions ] node
    | Swipe_action :
        { title : string
        ; side : int
        ; enabled : bool
        ; role : int
        ; extent : float
        ; background : int
        ; auto_close : bool
        ; full_swipe : bool
        }
        -> [ `Swipe_action ] node
    | Morphing_surface :
        { expanded : bool
        ; expand_duration_ms : int
        ; collapse_duration_ms : int
        }
        -> [ `Morphing_surface ] node
    | Tabs : { selection : Bonsai_swiftui_spec.Id.Navigation.page_key } -> [ `Tabs ] node
    | Tab :
        { page_key : Bonsai_swiftui_spec.Id.Navigation.page_key
        ; title : string
        ; symbol : string
        ; badge : string option
        ; accessibility_label : string option
        }
        -> [ `Tab ] node
    | Navigation_split :
        { state : Navigation.Split_state.t
        ; sidebar_title : string
        ; content_title : string option
        ; detail_title : string
        }
        -> [ `Navigation_split ] node
    | Navigation_stack : { title : string } -> [ `Navigation_stack ] node
    | Navigation_destination :
        { page_key : Bonsai_swiftui_spec.Id.Navigation.page_key
        ; title : string
        ; can_pop : bool
        }
        -> [ `Navigation_destination ] node
    | Control_size : { size : Control_size.t } -> [ `Control_size ] node
    | Ignores_safe_area :
        { regions : Safe_area_regions.t
        ; edges : int
        }
        -> [ `Ignores_safe_area ] node
    | Safe_area_padding : Layout.Edge_insets.t -> [ `Safe_area_padding ] node
    | Native_widget :
        { kind_id : Bonsai_swiftui_spec.Id.Native_widget.kind_id
        ; version : int
        ; capabilities : int64
        ; payload : bytes
        }
        -> [ `Native_widget ] node

  type event_binding =
    { tag : Event.Tag.t
    ; handler : Event.Handler.t
    }

  type 'k view =
    { key : Key.t option
    ; test_id : Test_id.t option
    ; node : 'k node
    ; event_bindings : event_binding array
    ; children : t array
    ; fingerprint : int64
    }

  type any_view = Av : 'k view -> any_view

  val view : t -> any_view
  val node_equal_widgets : t -> t -> bool
  val kind_tag_of_widget : t -> kind_tag
  val node_kind_tag : 'k node -> kind_tag
  val node_equal : 'k1 node -> 'k2 node -> bool

  val picker
    :  ?key:Key.t
    -> selected_id:int64 option
    -> label:string
    -> style:int
    -> enabled:bool
    -> options:picker_option list
    -> children:t list
    -> on_select:Event.Handler.t
    -> unit
    -> t

  val table
    :  ?key:Key.t
    -> columns:table_column list
    -> rows:table_row list
    -> sort_column_id:int64 option
    -> sort_ascending:bool
    -> selected_row_ids:int64 list
    -> on_sort:Event.Handler.t option
    -> on_row_selected:Event.Handler.t option
    -> children:t list
    -> unit
    -> t

  val native_widget
    :  ?key:Key.t
    -> kind_id:Bonsai_swiftui_spec.Id.Native_widget.kind_id
    -> version:int
    -> capabilities:int64
    -> payload:bytes
    -> on_event:Event.Handler.t
    -> children:t list
    -> unit
    -> t

  val vertical_viewport : t -> Viewport.Vertical.t
  val horizontal_viewport : t -> Viewport.Horizontal.t
end
