module Date = struct
  type t =
    { year : int
    ; month : int
    ; day : int
    }

  let is_leap year = year mod 400 = 0 || (year mod 4 = 0 && year mod 100 <> 0)

  let create ~year ~month ~day =
    if year < 1 || year > 9999
    then invalid_arg "View.Date.create: year must be in 1..9999";
    if month < 1 || month > 12 then invalid_arg "View.Date.create: month must be in 1..12";
    let days =
      [| 31; (if is_leap year then 29 else 28); 31; 30; 31; 30; 31; 31; 30; 31; 30; 31 |]
    in
    if day < 1 || day > days.(month - 1)
    then invalid_arg "View.Date.create: day is outside the month";
    { year; month; day }
  ;;

  let compare left right =
    Stdlib.compare (left.year, left.month, left.day) (right.year, right.month, right.day)
  ;;
end

module Time = struct
  type t =
    { hour : int
    ; minute : int
    }

  let create ~hour ~minute =
    if hour < 0 || hour > 23 then invalid_arg "View.Time.create: hour must be in 0..23";
    if minute < 0 || minute > 59
    then invalid_arg "View.Time.create: minute must be in 0..59";
    { hour; minute }
  ;;
end

module Control_size = struct
  type t =
    | Mini
    | Small
    | Regular
    | Large
    | Extra_large
end

module Toggle_style = struct
  type t =
    | Automatic
    | Switch
    | Checkbox
    | Button
end

module Safe_area_regions = struct
  type t =
    | Container
    | Keyboard
    | All
end

module Progress_style = struct
  type t =
    | Linear
    | Circular
end

module Symbol_rendering = struct
  type t = Theme.Symbol_rendering.t =
    | Monochrome
    | Hierarchical
    | Multicolor
end

module Button_role = struct
  type t =
    | Normal
    | Cancel
    | Destructive
end

module Button_style = struct
  type t =
    | Automatic
    | Plain
    | Bordered
    | Prominent
end

module ID = Bonsai_swiftui_spec.Id

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

let kind_tag_compare left right = Stdlib.compare left right
let kind_tag_equal left right = kind_tag_compare left right = 0

let kind_tag_to_string = function
  | K_empty -> "Empty"
  | K_spacer -> "Spacer"
  | K_text -> "Text"
  | K_rich_text -> "Rich_text"
  | K_symbol -> "Symbol"
  | K_image -> "Image"
  | K_collection_catalog -> "Collection_catalog"
  | K_collection_window -> "Collection_window"
  | K_removal -> "Removal"
  | K_refresh -> "Refresh"
  | K_scroll_targets -> "Scroll_targets"
  | K_scroll -> "Scroll"
  | K_text_editor -> "Text_editor"
  | K_text_field -> "Text_field"
  | K_secure_field -> "Secure_field"
  | K_flow -> "Flow"
  | K_row -> "Row"
  | K_column -> "Column"
  | K_weighted_row -> "Weighted_row"
  | K_weighted_column -> "Weighted_column"
  | K_stack -> "Stack"
  | K_layout_priority -> "Layout_priority"
  | K_offset -> "Offset"
  | K_padding -> "Padding"
  | K_frame -> "Frame"
  | K_background -> "Background"
  | K_clip -> "Clip"
  | K_opacity -> "Opacity"
  | K_animated_opacity -> "Animated_opacity"
  | K_projection_effect -> "Projection_effect"
  | K_gesture -> "Gesture"
  | K_focus_scope -> "Focus_scope"
  | K_hover_region -> "Hover_region"
  | K_keyboard_listener -> "Keyboard_listener"
  | K_button -> "Button"
  | K_semantics -> "Semantics"
  | K_theme -> "Theme"
  | K_date_picker -> "Date_picker"
  | K_time_picker -> "Time_picker"
  | K_menu -> "Menu"
  | K_picker -> "Picker"
  | K_slider -> "Slider"
  | K_range_slider -> "Range_slider"
  | K_table -> "Table"
  | K_divider -> "Divider"
  | K_label -> "Label"
  | K_badge -> "Badge"
  | K_sheet -> "Sheet"
  | K_popover -> "Popover"
  | K_scroll_sections -> "Scroll_sections"
  | K_scroll_section -> "Scroll_section"
  | K_toolbar -> "Toolbar"
  | K_help -> "Help"
  | K_group_box -> "Group_box"
  | K_progress -> "Progress"
  | K_overlay -> "Overlay"
  | K_disclosure_group -> "Disclosure_group"
  | K_toggle -> "Toggle"
  | K_swipe_actions -> "Swipe_actions"
  | K_swipe_action -> "Swipe_action"
  | K_morphing_surface -> "Morphing_surface"
  | K_tabs -> "Tabs"
  | K_tab -> "Tab"
  | K_navigation_split -> "Navigation_split"
  | K_navigation_stack -> "Navigation_stack"
  | K_navigation_destination -> "Navigation_destination"
  | K_ignores_safe_area -> "Ignores_safe_area"
  | K_safe_area_padding -> "Safe_area_padding"
  | K_control_size -> "Control_size"
  | K_native_widget -> "Native_widget"
;;

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

let validate_u32 ~context ~label value =
  if value < 0 || Int64.of_int value > 0xffff_ffffL
  then invalid_arg (Printf.sprintf "%s: %s must be a valid u32" context label)
;;

module Private_types = struct
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
        ; rendering : Symbol_rendering.t option
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
        ; appearance : Text_editing.Field_appearance.t
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
        ; fraction : float
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
        { kind_id : ID.Native_widget.kind_id
        ; version : int
        ; capabilities : int64
        ; payload : bytes
        }
        -> [ `Native_widget ] node

  type event_binding =
    { tag : Event.Tag.t
    ; handler : Event.Handler.t
    }

  type t = T : 'k view -> t

  and 'k view =
    { key : Key.t option
    ; test_id : Test_id.t option
    ; node : 'k node
    ; event_bindings : event_binding array
    ; children : t array
    ; fingerprint : int64
    }
end

[@@@ocaml.warning "-34"]

type t = Private_types.t
type 'k view = 'k Private_types.view
type 'k node = 'k Private_types.node
type event_binding = Private_types.event_binding

[@@@ocaml.warning "+34"]

open Private_types

let node_kind_tag (type k) (n : k node) : kind_tag =
  match n with
  | Empty -> K_empty
  | Spacer _ -> K_spacer
  | Text _ -> K_text
  | Rich_text _ -> K_rich_text
  | Symbol _ -> K_symbol
  | Image _ -> K_image
  | Collection_catalog _ -> K_collection_catalog
  | Collection_window _ -> K_collection_window
  | Removal _ -> K_removal
  | Refresh _ -> K_refresh
  | Scroll_targets _ -> K_scroll_targets
  | Scroll _ -> K_scroll
  | Text_editor _ -> K_text_editor
  | Text_field fields -> if fields.secure then K_secure_field else K_text_field
  | Flow _ -> K_flow
  | Row _ -> K_row
  | Column _ -> K_column
  | Weighted_row _ -> K_weighted_row
  | Weighted_column _ -> K_weighted_column
  | Stack _ -> K_stack
  | Layout_priority _ -> K_layout_priority
  | Offset _ -> K_offset
  | Button _ -> K_button
  | Padding _ -> K_padding
  | Frame _ -> K_frame
  | Background _ -> K_background
  | Clip _ -> K_clip
  | Opacity _ -> K_opacity
  | Animated_opacity _ -> K_animated_opacity
  | Projection_effect _ -> K_projection_effect
  | Gesture -> K_gesture
  | Focus_scope _ -> K_focus_scope
  | Hover_region _ -> K_hover_region
  | Keyboard_listener _ -> K_keyboard_listener
  | Semantics _ -> K_semantics
  | Theme _ -> K_theme
  | Date_picker _ -> K_date_picker
  | Time_picker _ -> K_time_picker
  | Menu _ -> K_menu
  | Picker _ -> K_picker
  | Slider _ -> K_slider
  | Range_slider _ -> K_range_slider
  | Table _ -> K_table
  | Divider -> K_divider
  | Label -> K_label
  | Badge _ -> K_badge
  | Sheet _ -> K_sheet
  | Popover _ -> K_popover
  | Scroll_sections _ -> K_scroll_sections
  | Scroll_section _ -> K_scroll_section
  | Toolbar _ -> K_toolbar
  | Help _ -> K_help
  | Group_box _ -> K_group_box
  | Progress _ -> K_progress
  | Overlay _ -> K_overlay
  | Disclosure_group _ -> K_disclosure_group
  | Toggle _ -> K_toggle
  | Swipe_actions _ -> K_swipe_actions
  | Swipe_action _ -> K_swipe_action
  | Morphing_surface _ -> K_morphing_surface
  | Tabs _ -> K_tabs
  | Tab _ -> K_tab
  | Navigation_split _ -> K_navigation_split
  | Navigation_stack _ -> K_navigation_stack
  | Navigation_destination _ -> K_navigation_destination
  | Control_size _ -> K_control_size
  | Ignores_safe_area _ -> K_ignores_safe_area
  | Safe_area_padding _ -> K_safe_area_padding
  | Native_widget _ -> K_native_widget
;;

let node_equal (type k1 k2) (a : k1 node) (b : k2 node) : bool =
  match a, b with
  | Empty, Empty | Gesture, Gesture -> true
  | Weighted_row x, Weighted_row y ->
    x.spacing = y.spacing && x.alignment = y.alignment && x.items = y.items
  | Weighted_column x, Weighted_column y ->
    x.spacing = y.spacing && x.alignment = y.alignment && x.items = y.items
  | Flow x, Flow y ->
    Float.equal x.spacing y.spacing
    && Float.equal x.line_spacing y.line_spacing
    && x.alignment = y.alignment
  | Row x, Row y ->
    Option.equal Float.equal x.spacing y.spacing && x.alignment = y.alignment
  | Column x, Column y ->
    Option.equal Float.equal x.spacing y.spacing && x.alignment = y.alignment
  | Stack x, Stack y -> x.alignment = y.alignment
  | Layout_priority x, Layout_priority y -> Float.equal x.priority y.priority
  | Offset x, Offset y -> Float.equal x.x y.x && Float.equal x.y y.y
  | Spacer x, Spacer y -> Option.equal Float.equal x.min_length y.min_length
  | Text x, Text y ->
    String.equal x.value y.value
    && Option.equal ( = ) x.style y.style
    && x.text_align = y.text_align
    && Option.equal Int.equal x.line_limit y.line_limit
    && x.truncation = y.truncation
  | Rich_text x, Rich_text y -> List.equal ( = ) x.spans y.spans
  | Symbol x, Symbol y ->
    String.equal x.name y.name
    && x.rendering = y.rendering
    && Option.equal Float.equal x.size y.size
    && Option.equal Int32.equal x.color y.color
  | Removal x, Removal y ->
    x.request_token = y.request_token
    && x.request_state = y.request_state
    && x.vertical = y.vertical
    && x.collapse_vertical = y.collapse_vertical
    && x.title = y.title
    && x.duration_ms = y.duration_ms
  | Refresh x, Refresh y ->
    x.request_token = y.request_token
    && x.request_state = y.request_state
    && x.show_token = y.show_token
  | Scroll_targets x, Scroll_targets y ->
    x.vertical = y.vertical
    && x.ids = y.ids
    && x.position = y.position
    && x.fraction = y.fraction
    && x.spacing = y.spacing
    && x.alignment = y.alignment
    && x.snapping = y.snapping
    && x.enabled = y.enabled
    && x.shows_indicators = y.shows_indicators
  | Scroll x, Scroll y ->
    x.vertical = y.vertical
    && x.shows_indicators = y.shows_indicators
    && x.fill_viewport = y.fill_viewport
    && x.initial_anchor = y.initial_anchor
  | Collection_catalog x, Collection_catalog y ->
    (x.keys == y.keys || x.keys = y.keys)
    && x.vertical = y.vertical
    && x.initial_anchor = y.initial_anchor
    && x.initial_key = y.initial_key
    && x.measurement_revision = y.measurement_revision
    && x.default_extent = y.default_extent
    && x.overrides = y.overrides
    && x.overscan = y.overscan
    && x.expand_duration_ms = y.expand_duration_ms
    && x.collapse_duration_ms = y.collapse_duration_ms
  | Collection_window x, Collection_window y ->
    x.first_index = y.first_index && x.keys = y.keys
  | Text_editor x, Text_editor y ->
    x.session_id = y.session_id
    && x.document_revision = y.document_revision
    && x.accepted_local_revision = y.accepted_local_revision
    && x.update_mode = y.update_mode
    && Text_editing.Value.equal x.value y.value
    && x.enabled = y.enabled
    && x.read_only = y.read_only
    && x.submit_on_return = y.submit_on_return
    && x.max_utf8_bytes = y.max_utf8_bytes
  | Text_field x, Text_field y ->
    x.session_id = y.session_id
    && x.document_revision = y.document_revision
    && x.accepted_local_revision = y.accepted_local_revision
    && x.update_mode = y.update_mode
    && Text_editing.Value.equal x.value y.value
    && x.enabled = y.enabled
    && x.read_only = y.read_only
    && x.submit_on_return = y.submit_on_return
    && x.max_utf8_bytes = y.max_utf8_bytes
    && x.label = y.label
    && x.prompt = y.prompt
    && x.secure = y.secure
    && x.keyboard = y.keyboard
    && x.submit_label = y.submit_label
    && x.appearance = y.appearance
    && x.autofocus = y.autofocus
  | Image x, Image y ->
    x.source = y.source && x.sizing = y.sizing && Float.equal x.scale y.scale
  | Button x, Button y ->
    Bool.equal x.enabled y.enabled
    && x.role = y.role
    && x.style = y.style
    && Bool.equal x.autofocus y.autofocus
  | Padding x, Padding y ->
    Float.equal x.leading y.leading
    && Float.equal x.top y.top
    && Float.equal x.trailing y.trailing
    && Float.equal x.bottom y.bottom
  | Frame x, Frame y ->
    x.width = y.width
    && x.height = y.height
    && x.min_width = y.min_width
    && x.ideal_width = y.ideal_width
    && x.max_width = y.max_width
    && x.min_height = y.min_height
    && x.ideal_height = y.ideal_height
    && x.max_height = y.max_height
    && x.alignment = y.alignment
  | Background x, Background y ->
    Int32.equal x.color y.color && Float.equal x.corner_radius y.corner_radius
  | Clip x, Clip y ->
    Float.equal x.corner_radius y.corner_radius && Bool.equal x.antialiased y.antialiased
  | Opacity x, Opacity y -> Float.equal x.opacity y.opacity
  | Animated_opacity x, Animated_opacity y ->
    Float.equal x.opacity y.opacity && Animation.Private.equal x.animation y.animation
  | Projection_effect x, Projection_effect y ->
    Array.length x.matrix3 = Array.length y.matrix3
    && Array.for_all2 Float.equal x.matrix3 y.matrix3
  | Focus_scope x, Focus_scope y -> Bool.equal x.autofocus y.autofocus
  | Hover_region x, Hover_region y -> Bool.equal x.blocks_behind y.blocks_behind
  | Keyboard_listener x, Keyboard_listener y ->
    Bool.equal x.autofocus y.autofocus && x.key_policy = y.key_policy
  | Semantics x, Semantics y -> x = y
  | Theme x, Theme y -> x = y
  | Date_picker x, Date_picker y ->
    x.selected = y.selected
    && x.first = y.first
    && x.last = y.last
    && x.selectable_dates = y.selectable_dates
    && x.label = y.label
    && x.enabled = y.enabled
  | Time_picker x, Time_picker y ->
    x.value = y.value && x.format = y.format && x.label = y.label && x.enabled = y.enabled
  | Menu x, Menu y -> x.items = y.items && x.enabled = y.enabled
  | Picker x, Picker y ->
    x.label = y.label
    && x.style = y.style
    && x.enabled = y.enabled
    && Option.equal Int64.equal x.selected_id y.selected_id
    && List.equal
         (fun (left : picker_option) (right : picker_option) ->
            Int64.equal left.option_id right.option_id
            && Bool.equal left.enabled right.enabled
            && Bool.equal left.has_label right.has_label)
         x.options
         y.options
  | Slider x, Slider y ->
    x.value = y.value
    && x.min = y.min
    && x.max = y.max
    && x.step = y.step
    && x.label = y.label
    && x.enabled = y.enabled
    && x.vertical = y.vertical
    && x.has_on_change = y.has_on_change
  | Range_slider x, Range_slider y ->
    x.start = y.start
    && x.end_ = y.end_
    && x.min = y.min
    && x.max = y.max
    && x.step = y.step
    && x.label_start = y.label_start
    && x.label_end = y.label_end
    && x.enabled = y.enabled
    && x.vertical = y.vertical
    && x.has_on_change = y.has_on_change
  | Table x, Table y ->
    List.equal ( = ) x.columns y.columns
    && List.equal ( = ) x.rows y.rows
    && Option.equal Int64.equal x.sort_column_id y.sort_column_id
    && Bool.equal x.sort_ascending y.sort_ascending
    && List.equal Int64.equal x.selected_row_ids y.selected_row_ids
    && Bool.equal x.has_on_sort y.has_on_sort
    && Bool.equal x.has_on_row_selected y.has_on_row_selected
  | Divider, Divider -> true
  | Label, Label -> true
  | Badge x, Badge y ->
    Option.equal Int.equal x.count y.count
    && x.alignment = y.alignment
    && Bool.equal x.visible y.visible
  | Sheet x, Sheet y ->
    x.presented = y.presented
    && x.fullscreen = y.fullscreen
    && x.detents = y.detents
    && Float.equal x.fraction y.fraction
    && x.initial = y.initial
    && x.interactive = y.interactive
    && x.indicator = y.indicator
    && x.sizing = y.sizing
  | Popover x, Popover y -> Bool.equal x.presented y.presented && Int.equal x.edge y.edge
  | Scroll_sections x, Scroll_sections y ->
    x.vertical = y.vertical
    && x.initial_anchor = y.initial_anchor
    && x.pin_headers = y.pin_headers
    && x.pin_footers = y.pin_footers
    && Float.equal x.spacing y.spacing
    && x.shows_indicators = y.shows_indicators
  | Scroll_section x, Scroll_section y ->
    x.has_header = y.has_header
    && x.has_footer = y.has_footer
    && x.hero_height = y.hero_height
    && x.stretch = y.stretch
  | Toolbar x, Toolbar y -> x.placements = y.placements
  | Help x, Help y -> String.equal x.message y.message
  | Group_box x, Group_box y -> Bool.equal x.has_label y.has_label
  | Progress x, Progress y ->
    Option.equal Float.equal x.value y.value && x.style = y.style
  | Overlay x, Overlay y -> x.alignment = y.alignment
  | Disclosure_group x, Disclosure_group y ->
    x.expanded = y.expanded && x.enabled = y.enabled
  | Toggle x, Toggle y -> x.value = y.value && x.enabled = y.enabled && x.style = y.style
  | Swipe_actions x, Swipe_actions y ->
    x.enabled = y.enabled
    && x.vertical = y.vertical
    && x.close_on_scroll = y.close_on_scroll
    && x.group = y.group
    && x.close_when_opened = y.close_when_opened
    && x.close_when_tapped = y.close_when_tapped
  | Swipe_action x, Swipe_action y ->
    x.title = y.title
    && x.side = y.side
    && x.enabled = y.enabled
    && x.role = y.role
    && Float.equal x.extent y.extent
    && x.background = y.background
    && x.auto_close = y.auto_close
    && x.full_swipe = y.full_swipe
  | Morphing_surface x, Morphing_surface y ->
    Bool.equal x.expanded y.expanded
    && Int.equal x.expand_duration_ms y.expand_duration_ms
    && Int.equal x.collapse_duration_ms y.collapse_duration_ms
  | Tabs x, Tabs y -> ID.Navigation.Page_key.equal x.selection y.selection
  | Tab x, Tab y ->
    ID.Navigation.Page_key.equal x.page_key y.page_key
    && String.equal x.title y.title
    && String.equal x.symbol y.symbol
    && Option.equal String.equal x.badge y.badge
    && Option.equal String.equal x.accessibility_label y.accessibility_label
  | Navigation_split x, Navigation_split y ->
    Navigation.Split_state.equal x.state y.state
    && String.equal x.sidebar_title y.sidebar_title
    && Option.equal String.equal x.content_title y.content_title
    && String.equal x.detail_title y.detail_title
  | Navigation_stack x, Navigation_stack y -> String.equal x.title y.title
  | Navigation_destination x, Navigation_destination y ->
    ID.Navigation.Page_key.equal x.page_key y.page_key
    && String.equal x.title y.title
    && Bool.equal x.can_pop y.can_pop
  | Control_size x, Control_size y -> x.size = y.size
  | Ignores_safe_area x, Ignores_safe_area y -> x.regions = y.regions && x.edges = y.edges
  | Safe_area_padding x, Safe_area_padding y -> x = y
  | Native_widget x, Native_widget y ->
    x.kind_id = y.kind_id
    && x.version = y.version
    && Int64.equal x.capabilities y.capabilities
    && Bytes.equal x.payload y.payload
  | _ -> false
;;

let hash_combine state value =
  Int64.(mul (logxor state (of_int (Hashtbl.hash value))) 0x100000001b3L)
;;

let fingerprint (type k) ~key ~test_id ~(node : k node) ~event_bindings ~children =
  let state = ref 0xcbf29ce484222325L in
  state := hash_combine !state key;
  state := hash_combine !state test_id;
  state := hash_combine !state (node_kind_tag node);
  state := hash_combine !state node;
  Array.iter
    (fun binding ->
       state := hash_combine !state binding.tag;
       state := hash_combine !state (Event.Handler.name binding.handler))
    event_bindings;
  Array.iter
    (fun child ->
       let (T child_view) = child in
       state := hash_combine !state child_view.fingerprint)
    children;
  !state
;;

let create_typed (type k) ~key ~(node : k node) ~event_bindings ~children =
  let test_id = None in
  let fingerprint = fingerprint ~key ~test_id ~node ~event_bindings ~children in
  T { key; test_id; node; event_bindings; children; fingerprint }
;;

let with_test_id test_id widget =
  let (T view) = widget in
  let fingerprint =
    fingerprint
      ~key:view.key
      ~test_id:(Some test_id)
      ~node:view.node
      ~event_bindings:view.event_bindings
      ~children:view.children
  in
  T { view with test_id = Some test_id; fingerprint }
;;

let with_application_key key (T view) =
  let key = Some key in
  let fingerprint =
    fingerprint
      ~key
      ~test_id:view.test_id
      ~node:view.node
      ~event_bindings:view.event_bindings
      ~children:view.children
  in
  T { view with key; fingerprint }
;;

module Keyed = struct
  type nonrec widget = t
  type t = widget

  let create ~key widget = with_application_key key widget
  let to_widget item = item
end

let plain_children widgets = Array.of_list widgets
let keyed_children items = items |> List.map Keyed.to_widget |> plain_children
let empty ?key () = create_typed ~key ~node:Empty ~event_bindings:[||] ~children:[||]

let text
      ?key
      ?style
      ?(text_align = Style.Text_align.Start)
      ?line_limit
      ?(truncation = Style.Text_truncation.Tail)
      value
  =
  Option.iter
    (fun value -> if value <= 0 then invalid_arg "View.text: line_limit must be positive")
    line_limit;
  create_typed
    ~key
    ~node:
      (Text
         { value
         ; style = Option.map Style.Text_style.Private.view style
         ; text_align
         ; line_limit
         ; truncation
         })
    ~event_bindings:[||]
    ~children:[||]
;;

let rich_text ?key spans =
  if List.length spans > 65535
  then invalid_arg "View.rich_text supports at most 65535 spans";
  let spans = List.map Style.Text_span.Private.view spans in
  create_typed ~key ~node:(Rich_text { spans }) ~event_bindings:[||] ~children:[||]
;;

let optional_dimension label = function
  | None -> None
  | Some value ->
    if (not (Float.is_finite value)) || Float.compare value 0. < 0
    then invalid_arg (Printf.sprintf "View.%s must be finite and non-negative" label);
    Some value
;;

let symbol ?key ?size ?color ?rendering ~name () =
  if
    String.length name = 0
    || not
         (String.for_all
            (function
              | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '.' | '_' -> true
              | _ -> false)
            name)
  then invalid_arg "View.symbol: name must be an SF Symbols system name";
  Option.iter
    (fun size ->
       if (not (Float.is_finite size)) || Float.compare size 0. <= 0
       then invalid_arg "View.symbol: size must be finite and positive")
    size;
  create_typed
    ~key
    ~node:
      (Symbol
         { name; size; color = Option.map Style.Color.Private.to_argb32 color; rendering })
    ~event_bindings:[||]
    ~children:[||]
;;

let image ?key ?(sizing = Style.Image_sizing.Original) ?(scale = 1.) ~source () =
  if (not (Float.is_finite scale)) || scale <= 0.
  then invalid_arg "View.image: scale must be finite and positive";
  create_typed
    ~key
    ~node:(Image { source; sizing; scale })
    ~event_bindings:[||]
    ~children:[||]
;;

let text_editor
      ?key
      ?(enabled = true)
      ?(read_only = false)
      ?(submit_on_return = false)
      ?max_utf8_bytes
      ~session_id
      ~document_revision
      ~accepted_local_revision
      ~update_mode
      ~value
      ~on_edit
      ~on_submit
      ~on_focus_changed
      ?on_limit_reached
      ()
  =
  if
    List.exists
      (fun value -> Int64.compare value 0L < 0)
      [ ID.Text_input.Session_id.to_int64 session_id
      ; ID.Text_input.Document_revision.to_int64 document_revision
      ; ID.Text_input.Local_revision.to_int64 accepted_local_revision
      ]
  then invalid_arg "View.text_editor: identities must be non-negative";
  Option.iter
    (fun maximum ->
       if maximum <= 0 || maximum > 1_048_576
       then invalid_arg "View.text_editor: max_utf8_bytes must be in 1..1048576")
    max_utf8_bytes;
  let bindings =
    [ { tag = Event.Tag.Text_edit; handler = on_edit }
    ; { tag = Event.Tag.Text_submit; handler = on_submit }
    ; { tag = Event.Tag.Focus_changed; handler = on_focus_changed }
    ]
    @ Option.to_list
        (Option.map
           (fun handler -> { tag = Event.Tag.Text_limit_reached; handler })
           on_limit_reached)
  in
  create_typed
    ~key
    ~node:
      (Text_editor
         { session_id
         ; document_revision
         ; accepted_local_revision
         ; update_mode
         ; value
         ; enabled
         ; read_only
         ; submit_on_return
         ; max_utf8_bytes
         })
    ~event_bindings:(Array.of_list bindings)
    ~children:[||]
;;

let native_text_field
      ~secure
      ?key
      ~label
      ?(prompt = "")
      ?(keyboard = Text_editing.Keyboard.Text)
      ?(submit_label = Text_editing.Submit_label.Done)
      ?(appearance = Text_editing.Field_appearance.Rounded)
      ?(autofocus = false)
      ?(enabled = true)
      ?(read_only = false)
      ?(submit_on_return = true)
      ?max_utf8_bytes
      ~session_id
      ~document_revision
      ~accepted_local_revision
      ~update_mode
      ~value
      ~on_edit
      ~on_submit
      ~on_focus_changed
      ?on_limit_reached
      ()
  =
  if
    List.exists
      (fun value -> Int64.compare value 0L < 0)
      [ ID.Text_input.Session_id.to_int64 session_id
      ; ID.Text_input.Document_revision.to_int64 document_revision
      ; ID.Text_input.Local_revision.to_int64 accepted_local_revision
      ]
  then invalid_arg "View.text_field: identities must be non-negative";
  Option.iter
    (fun maximum ->
       if maximum <= 0 || maximum > 1_048_576
       then invalid_arg "View.text_field: max_utf8_bytes must be in 1..1048576")
    max_utf8_bytes;
  let bindings =
    [ { tag = Event.Tag.Text_edit; handler = on_edit }
    ; { tag = Event.Tag.Text_submit; handler = on_submit }
    ; { tag = Event.Tag.Focus_changed; handler = on_focus_changed }
    ]
    @ Option.to_list
        (Option.map
           (fun handler -> { tag = Event.Tag.Text_limit_reached; handler })
           on_limit_reached)
  in
  create_typed
    ~key
    ~node:
      (Text_field
         { session_id
         ; document_revision
         ; accepted_local_revision
         ; update_mode
         ; value
         ; enabled
         ; read_only
         ; submit_on_return
         ; max_utf8_bytes
         ; secure
         ; label
         ; prompt
         ; keyboard
         ; submit_label
         ; appearance
         ; autofocus
         })
    ~event_bindings:(Array.of_list bindings)
    ~children:[||]
;;

let text_field = native_text_field ~secure:false
let secure_field = native_text_field ~secure:true

let finite_layout_value label value =
  if not (Float.is_finite value) then invalid_arg ("View." ^ label ^ " must be finite")
;;

let flow
      ?key
      ?(spacing = 8.)
      ?(line_spacing = 8.)
      ?(alignment = Layout.Horizontal_alignment.Leading)
      children
  =
  List.iter
    (fun value ->
       finite_layout_value "flow spacing" value;
       if value < 0. then invalid_arg "View.flow spacing must be non-negative")
    [ spacing; line_spacing ];
  create_typed
    ~key
    ~node:(Flow { spacing; line_spacing; alignment })
    ~event_bindings:[||]
    ~children:(plain_children children)
;;

let row ?key ?spacing ?(alignment = Layout.Vertical_alignment.Center) children =
  Option.iter (finite_layout_value "row.spacing") spacing;
  create_typed
    ~key
    ~node:(Row { spacing; alignment })
    ~event_bindings:[||]
    ~children:(plain_children children)
;;

let column ?key ?spacing ?(alignment = Layout.Horizontal_alignment.Center) children =
  Option.iter (finite_layout_value "column.spacing") spacing;
  create_typed
    ~key
    ~node:(Column { spacing; alignment })
    ~event_bindings:[||]
    ~children:(plain_children children)
;;

let stack ?key ?(alignment = Layout.Alignment.Center) children =
  create_typed
    ~key
    ~node:(Stack { alignment })
    ~event_bindings:[||]
    ~children:(plain_children children)
;;

let layout_priority ?key priority child =
  finite_layout_value "layout_priority" priority;
  create_typed
    ~key
    ~node:(Layout_priority { priority })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let offset ?key ?(x = 0.) ?(y = 0.) child =
  finite_layout_value "offset.x" x;
  finite_layout_value "offset.y" y;
  create_typed
    ~key
    ~node:(Offset { x; y })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let button
      ?key
      ?(enabled = true)
      ?(role = Button_role.Normal)
      ?(style = Button_style.Automatic)
      ?(autofocus = false)
      ~on_press
      ~child
      ()
  =
  create_typed
    ~key
    ~node:(Button { enabled; role; style; autofocus })
    ~event_bindings:
      (if enabled then [| { tag = Event.Tag.Press; handler = on_press } |] else [||])
    ~children:(plain_children [ child ])
;;

let padding ?key ~insets child =
  let leading, top, trailing, bottom = Layout.Edge_insets.Private.to_sides insets in
  create_typed
    ~key
    ~node:(Padding { leading; top; trailing; bottom })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let spacer ?key ?min_length () =
  create_typed
    ~key
    ~node:(Spacer { min_length = optional_dimension "spacer.min_length" min_length })
    ~event_bindings:[||]
    ~children:[||]
;;

let frame
      ?key
      ?width
      ?height
      ?min_width
      ?ideal_width
      ?max_width
      ?min_height
      ?ideal_height
      ?max_height
      ?(alignment = Layout.Alignment.Center)
      child
  =
  let validate_axis fixed minimum ideal maximum =
    List.iter
      (fun value -> ignore (optional_dimension "frame dimension" value))
      [ fixed; minimum; ideal ];
    let maximum_points =
      match maximum with
      | None | Some Layout.Frame_limit.Fill -> None
      | Some (Points value) -> optional_dimension "frame maximum" (Some value)
    in
    if
      Option.is_some fixed
      && (Option.is_some minimum || Option.is_some ideal || Option.is_some maximum)
    then invalid_arg "View.frame: fixed and flexible dimensions conflict";
    List.iter
      (function
        | Some lower, Some upper when Float.compare lower upper > 0 ->
          invalid_arg "View.frame: minimum, ideal and maximum must be ordered"
        | _ -> ())
      [ minimum, ideal; minimum, maximum_points; ideal, maximum_points ]
  in
  validate_axis width min_width ideal_width max_width;
  validate_axis height min_height ideal_height max_height;
  create_typed
    ~key
    ~node:
      (Frame
         { width
         ; height
         ; min_width
         ; ideal_width
         ; max_width
         ; min_height
         ; ideal_height
         ; max_height
         ; alignment
         })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let background ?key ?(corner_radius = 0.) ~color child =
  ignore (optional_dimension "background.corner_radius" (Some corner_radius));
  create_typed
    ~key
    ~node:(Background { color = Style.Color.Private.to_argb32 color; corner_radius })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let clip ?key ?(corner_radius = 0.) ?(antialiased = true) child =
  ignore (optional_dimension "clip.corner_radius" (Some corner_radius));
  create_typed
    ~key
    ~node:(Clip { corner_radius; antialiased })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let opacity ?key opacity child =
  if
    (not (Float.is_finite opacity))
    || Float.compare opacity 0. < 0
    || Float.compare opacity 1. > 0
  then invalid_arg "View.opacity: opacity must be finite and in 0..1";
  create_typed
    ~key
    ~node:(Opacity { opacity })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let animated_opacity ?key ~animation ~opacity ~on_completed child =
  if
    (not (Float.is_finite opacity))
    || Float.compare opacity 0. < 0
    || Float.compare opacity 1. > 0
  then invalid_arg "View.animated_opacity: opacity must be finite and in 0..1";
  create_typed
    ~key
    ~node:(Animated_opacity { opacity; animation })
    ~event_bindings:[| { tag = Event.Tag.Animation_completed; handler = on_completed } |]
    ~children:(plain_children [ child ])
;;

let projection_effect ?key ~transform child =
  create_typed
    ~key
    ~node:(Projection_effect { matrix3 = Style.Projection.Private.to_array transform })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let control_size ?key ~size child =
  create_typed
    ~key
    ~node:(Control_size { size })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let ignores_safe_area
      ?key
      ?(regions = Safe_area_regions.Container)
      ?(edges = [ Layout.Edge.Leading; Top; Trailing; Bottom ])
      child
  =
  let edges =
    List.fold_left
      (fun bits edge ->
         bits
         lor
         match edge with
         | Layout.Edge.Leading -> 1
         | Top -> 2
         | Trailing -> 4
         | Bottom -> 8)
      0
      edges
  in
  create_typed
    ~key
    ~node:(Ignores_safe_area { regions; edges })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let safe_area_padding ?key ~insets child =
  create_typed
    ~key
    ~node:(Safe_area_padding insets)
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let optional_binding tag = function
  | None -> []
  | Some handler -> [ { tag; handler } ]
;;

let gesture
      ?key
      ?on_tap
      ?on_double_tap
      ?on_long_press
      ?on_pointer_down
      ?on_pointer_up
      child
  =
  let event_bindings =
    optional_binding Event.Tag.Tap on_tap
    @ optional_binding Double_tap on_double_tap
    @ optional_binding Long_press on_long_press
    @ optional_binding Pointer_down on_pointer_down
    @ optional_binding Pointer_up on_pointer_up
  in
  if event_bindings = []
  then invalid_arg "View.gesture: at least one event handler is required";
  create_typed
    ~key
    ~node:Gesture
    ~event_bindings:(Array.of_list event_bindings)
    ~children:(plain_children [ child ])
;;

let focus_scope ?key ?(autofocus = false) ~on_focus_changed child =
  create_typed
    ~key
    ~node:(Focus_scope { autofocus })
    ~event_bindings:[| { tag = Event.Tag.Focus_changed; handler = on_focus_changed } |]
    ~children:(plain_children [ child ])
;;

let hover_region ?key ?(blocks_behind = true) ~on_enter ~on_leave child =
  create_typed
    ~key
    ~node:(Hover_region { blocks_behind })
    ~event_bindings:
      [| { tag = Event.Tag.Pointer_enter; handler = on_enter }
       ; { tag = Event.Tag.Pointer_leave; handler = on_leave }
      |]
    ~children:(plain_children [ child ])
;;

let keyboard_listener
      ?key
      ?(autofocus = false)
      ?(key_policy = Event.Key_policy.Ignored)
      ~on_key
      child
  =
  create_typed
    ~key
    ~node:(Keyboard_listener { autofocus; key_policy })
    ~event_bindings:[| { tag = Event.Tag.Key; handler = on_key } |]
    ~children:(plain_children [ child ])
;;

let semantics ?key ?on_action ~properties child =
  let properties = Semantics.Private.view properties in
  let event_bindings =
    match properties.actions, on_action with
    | [], None -> [||]
    | [], Some _ ->
      invalid_arg "View.semantics: on_action requires at least one declared action"
    | _ :: _, None -> invalid_arg "View.semantics: declared actions require on_action"
    | _ :: _, Some handler -> [| { tag = Event.Tag.Semantics_action; handler } |]
  in
  create_typed
    ~key
    ~node:(Semantics properties)
    ~event_bindings
    ~children:(plain_children [ child ])
;;

let theme ?key ~data child =
  create_typed
    ~key
    ~node:(Theme (Theme.Private.view data))
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let overlay ?key ?(alignment = Layout.Alignment.Center) ~overlay base =
  create_typed
    ~key
    ~node:(Overlay { alignment })
    ~event_bindings:[||]
    ~children:(plain_children [ base; overlay ])
;;

let native_widget ?key ~kind_id ~version ~capabilities ~payload ~on_event ~children () =
  create_typed
    ~key
    ~node:(Native_widget { kind_id; version; capabilities; payload })
    ~event_bindings:[| { tag = Event.Tag.Native_event; handler = on_event } |]
    ~children:(plain_children children)
;;

let picker ?key ~selected_id ~label ~style ~enabled ~options ~children ~on_select () =
  create_typed
    ~key
    ~node:(Picker { selected_id; options; label; style; enabled })
    ~event_bindings:
      (if enabled
       then [| { tag = Event.Tag.Picker_selected; handler = on_select } |]
       else [||])
    ~children:(plain_children children)
;;

module Date_picker = struct
  let create
        ?key
        ?(label = "Date")
        ?(enabled = true)
        ?(selectable_dates = [])
        ~selected
        ~first
        ~last
        ~on_select
        ()
    =
    if String.trim label = "" then invalid_arg "View.Date_picker.create: empty label";
    if List.length selectable_dates > 65535
    then invalid_arg "View.Date_picker.create: too many selectable dates";
    if Date.compare first last > 0
    then invalid_arg "View.Date_picker.create: reversed bounds";
    let bounded date = Date.compare first date <= 0 && Date.compare date last <= 0 in
    if not (bounded selected)
    then invalid_arg "View.Date_picker.create: selected date outside bounds";
    if not (List.for_all bounded selectable_dates)
    then invalid_arg "View.Date_picker.create: selectable date outside bounds";
    let selectable_dates = List.sort_uniq Date.compare selectable_dates in
    if selectable_dates <> [] && not (List.mem selected selectable_dates)
    then invalid_arg "View.Date_picker.create: selected date is not selectable";
    create_typed
      ~key
      ~node:(Date_picker { selected; first; last; selectable_dates; label; enabled })
      ~event_bindings:
        (if enabled
         then [| { tag = Event.Tag.Civil_date_changed; handler = on_select } |]
         else [||])
      ~children:[||]
  ;;
end

module Time_picker = struct
  type format =
    | System
    | Hour_12
    | Hour_24

  let create
        ?key
        ?(label = "Time")
        ?(enabled = true)
        ?(format = System)
        ~value
        ~on_changed
        ()
    =
    if String.trim label = "" then invalid_arg "View.Time_picker.create: empty label";
    let format =
      match format with
      | System -> 0
      | Hour_12 -> 1
      | Hour_24 -> 2
    in
    create_typed
      ~key
      ~node:(Time_picker { value; format; label; enabled })
      ~event_bindings:
        (if enabled
         then [| { tag = Event.Tag.Civil_time_changed; handler = on_changed } |]
         else [||])
      ~children:[||]
  ;;
end

module Menu = struct
  type entry =
    { id : int64
    ; kind : int
    ; enabled : bool
    ; selected : bool
    ; role : int
    ; label : t option
    ; entries : entry list
    }

  let action ~id ~label ?(enabled = true) ?(role = Button_role.Normal) () =
    let role =
      match role with
      | Button_role.Normal -> 0
      | Cancel -> 1
      | Destructive -> 2
    in
    { id; kind = 0; enabled; selected = false; role; label = Some label; entries = [] }
  ;;

  let choice ~id ~label ~selected ?(enabled = true) () =
    { id; kind = 1; enabled; selected; role = 0; label = Some label; entries = [] }
  ;;

  let divider ~id =
    { id
    ; kind = 2
    ; enabled = false
    ; selected = false
    ; role = 0
    ; label = None
    ; entries = []
    }
  ;;

  let section ~id ?label entries =
    if entries = [] then invalid_arg "View.Menu.section: entries must not be empty";
    { id; kind = 3; enabled = true; selected = false; role = 0; label; entries }
  ;;

  let submenu ~id ~label ?(enabled = true) entries =
    if entries = [] then invalid_arg "View.Menu.submenu: entries must not be empty";
    { id; kind = 4; enabled; selected = false; role = 0; label = Some label; entries }
  ;;

  let create ?key ?(enabled = true) ~on_select ~label entries =
    if entries = [] then invalid_arg "View.Menu.create: entries must not be empty";
    let ids = Hashtbl.create 16 in
    let rec flatten depth entry =
      if depth > 32 then invalid_arg "View.Menu.create: nesting exceeds 32 levels";
      if Hashtbl.mem ids entry.id then invalid_arg "View.Menu.create: IDs must be unique";
      Hashtbl.add ids entry.id ();
      if Hashtbl.length ids > 1024
      then invalid_arg "View.Menu.create: at most 1024 entries";
      let item =
        { menu_id = entry.id
        ; kind = entry.kind
        ; enabled = entry.enabled
        ; selected = entry.selected
        ; role = entry.role
        ; has_label = Option.is_some entry.label
        ; child_count = List.length entry.entries
        }
      in
      let children = List.map (flatten (depth + 1)) entry.entries in
      ( item :: List.concat_map fst children
      , Option.to_list
          (Option.map (with_application_key (Key.int64 entry.id)) entry.label)
        @ List.concat_map snd children )
    in
    let flattened = List.map (flatten 1) entries in
    create_typed
      ~key
      ~node:(Menu { items = List.concat_map fst flattened; enabled })
      ~event_bindings:
        (if enabled
         then [| { tag = Event.Tag.Menu_action; handler = on_select } |]
         else [||])
      ~children:
        (plain_children
           (with_application_key (Key.string "menu-label") label
            :: List.concat_map snd flattened))
  ;;
end

module Picker = struct
  type choice =
    { id : int64
    ; enabled : bool
    ; label : t option
    }

  let option ~id ?(enabled = true) ?label () = { id; enabled; label }

  type style =
    | Automatic
    | Menu
    | Segmented
    | Inline

  let create
        ?key
        ?(label = "Choice")
        ?(style = Automatic)
        ?(enabled = true)
        ~selected_id
        ~on_select
        options
        ()
    =
    if List.length options > 256 then invalid_arg "Picker.create: at most 256 options";
    if String.trim label = "" then invalid_arg "Picker.create: label must not be empty";
    let style =
      match style with
      | Automatic -> 0
      | Menu -> 1
      | Segmented -> 2
      | Inline -> 3
    in
    let ids = Hashtbl.create (List.length options) in
    List.iter
      (fun option ->
         if Hashtbl.mem ids option.id
         then invalid_arg "Picker.create: option IDs must be unique";
         Hashtbl.add ids option.id ())
      options;
    (match selected_id with
     | Some id when not (Hashtbl.mem ids id) ->
       invalid_arg "Picker.create: selected_id must name an option"
     | None | Some _ -> ());
    picker
      ?key
      ~selected_id
      ~label
      ~style
      ~enabled
      ~options:
        (List.map
           (fun option ->
              { option_id = option.id
              ; enabled = option.enabled
              ; has_label = Option.is_some option.label
              })
           options)
      ~children:
        (List.filter_map
           (fun option ->
              Option.map (with_application_key (Key.int64 option.id)) option.label)
           options)
      ~on_select
      ()
  ;;
end

let table
      ?key
      ~columns
      ~rows
      ~sort_column_id
      ~sort_ascending
      ~selected_row_ids
      ~on_sort
      ~on_row_selected
      ~children
      ()
  =
  let binding tag = Option.map (fun handler -> { tag; handler }) in
  create_typed
    ~key
    ~node:
      (Table
         { columns
         ; rows
         ; sort_column_id
         ; sort_ascending
         ; selected_row_ids
         ; has_on_sort = Option.is_some on_sort
         ; has_on_row_selected = Option.is_some on_row_selected
         })
    ~event_bindings:
      (Array.of_list
         (List.filter_map
            Fun.id
            [ binding Event.Tag.Table_sort_requested on_sort
            ; binding Event.Tag.Table_row_selected on_row_selected
            ]))
    ~children:(plain_children children)
;;

let divider ?key () = create_typed ~key ~node:Divider ~event_bindings:[||] ~children:[||]

let badge
      ?key
      ?count
      ?(alignment = Layout.Horizontal_alignment.Trailing)
      ?(visible = true)
      child
  =
  Option.iter
    (fun count -> if count < 0 then invalid_arg "View.badge: count must be non-negative")
    count;
  create_typed
    ~key
    ~node:(Badge { count; alignment; visible })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let label ?key ~title ~icon () =
  create_typed
    ~key
    ~node:Label
    ~event_bindings:[||]
    ~children:(plain_children [ title; icon ])
;;

module Sheet = struct
  type detent =
    | Medium
    | Large
    | Fraction of float

  type sizing =
    | Automatic
    | Fitted
    | Form
    | Page

  let node
        ?key
        ~presented
        ~fullscreen
        ~detents
        ~fraction
        ~initial
        ~interactive
        ~indicator
        ~sizing
        ~on_presented_changed
        ~content
        background
    =
    create_typed
      ~key
      ~node:
        (Sheet
           { presented
           ; fullscreen
           ; detents
           ; initial
           ; interactive
           ; indicator
           ; sizing
           ; fraction
           })
      ~event_bindings:
        [| { tag = Event.Tag.Value_changed; handler = on_presented_changed } |]
      ~children:(plain_children [ background; content ])
  ;;

  let create
        ?key
        ?(sizing = Automatic)
        ?(detents = [ Large ])
        ?initial_detent
        ?(interactive_dismiss = true)
        ?(shows_drag_indicator = true)
        ~presented
        ~on_presented_changed
        ~content
        background
    =
    let initial =
      match initial_detent, detents with
      | Some initial, _ -> initial
      | None, initial :: _ -> initial
      | None, [] -> invalid_arg "View.Sheet: detents must not be empty"
    in
    if detents = [] || not (List.mem initial detents)
    then invalid_arg "View.Sheet: initial detent must be available";
    let mask =
      List.fold_left
        (fun mask detent ->
           let bit =
             match detent with
             | Medium -> 1
             | Large -> 2
             | Fraction value ->
               if (not (Float.is_finite value)) || value <= 0. || value > 1.
               then invalid_arg "View.Sheet: fraction must be finite and in (0, 1]";
               4
           in
           if mask land bit <> 0 then invalid_arg "View.Sheet: duplicate detent";
           mask lor bit)
        0
        detents
    in
    node
      ?key
      ~presented
      ~fullscreen:false
      ~sizing:
        (match sizing with
         | Automatic -> 0
         | Fitted -> 1
         | Form -> 2
         | Page -> 3)
      ~detents:mask
      ~fraction:
        (List.fold_left
           (fun value -> function
              | Fraction f -> f
              | _ -> value)
           0.
           detents)
      ~initial:
        (match initial with
         | Medium -> 0
         | Large -> 1
         | Fraction _ -> 2)
      ~interactive:interactive_dismiss
      ~indicator:shows_drag_indicator
      ~on_presented_changed
      ~content
      background
  ;;

  let full_screen ?key ~presented ~on_presented_changed ~content background =
    node
      ?key
      ~presented
      ~fullscreen:true
      ~sizing:0
      ~detents:2
      ~fraction:0.
      ~initial:1
      ~interactive:false
      ~indicator:false
      ~on_presented_changed
      ~content
      background
  ;;
end

module Popover = struct
  type edge =
    | Automatic
    | Top
    | Bottom
    | Leading
    | Trailing

  let create ?key ?(edge = Automatic) ~presented ~on_presented_changed ~content anchor =
    let edge =
      match edge with
      | Automatic -> 0
      | Top -> 1
      | Bottom -> 2
      | Leading -> 3
      | Trailing -> 4
    in
    create_typed
      ~key
      ~node:(Popover { presented; edge })
      ~event_bindings:
        [| { tag = Event.Tag.Value_changed; handler = on_presented_changed } |]
      ~children:(plain_children [ anchor; content ])
  ;;
end

let help ?key ~message child =
  if String.trim message = "" then invalid_arg "View.help: message must not be empty";
  create_typed
    ~key
    ~node:(Help { message })
    ~event_bindings:[||]
    ~children:(plain_children [ child ])
;;

let group_box ?key ?label content =
  create_typed
    ~key
    ~node:(Group_box { has_label = Option.is_some label })
    ~event_bindings:[||]
    ~children:(plain_children (content :: Option.to_list label))
;;

let progress ?key ?value ?(style = Progress_style.Linear) () =
  Option.iter
    (fun value ->
       if (not (Float.is_finite value)) || value < 0. || value > 1.
       then invalid_arg "View.progress: value must be finite and in 0..1")
    value;
  create_typed ~key ~node:(Progress { value; style }) ~event_bindings:[||] ~children:[||]
;;

module Weighted = struct
  type child =
    { content : t
    ; sizing : weighted_sizing
    }

  let fixed content = { content; sizing = Intrinsic }

  let share ?(weight = 1.) ?(fills = true) content =
    if (not (Float.is_finite weight)) || Float.compare weight 0. <= 0
    then invalid_arg "View.Weighted.share: weight must be finite and positive";
    { content; sizing = Share { weight; fills } }
  ;;

  let row ?key ?spacing ?(alignment = Layout.Vertical_alignment.Center) children =
    Option.iter (finite_layout_value "Weighted.row.spacing") spacing;
    create_typed
      ~key
      ~node:
        (Weighted_row
           { spacing; alignment; items = List.map (fun child -> child.sizing) children })
      ~event_bindings:[||]
      ~children:(plain_children (List.map (fun child -> child.content) children))
  ;;

  let column ?key ?spacing ?(alignment = Layout.Horizontal_alignment.Center) children =
    Option.iter (finite_layout_value "Weighted.column.spacing") spacing;
    create_typed
      ~key
      ~node:
        (Weighted_column
           { spacing; alignment; items = List.map (fun child -> child.sizing) children })
      ~event_bindings:[||]
      ~children:(plain_children (List.map (fun child -> child.content) children))
  ;;
end

type vertical_viewport = Vertical_viewport of t
type horizontal_viewport = Horizontal_viewport of t

let vertical_viewport widget = Vertical_viewport widget
let horizontal_viewport widget = Horizontal_viewport widget

module Viewport = struct
  type nonrec widget = t

  let positive_extent label value =
    if (not (Float.is_finite value)) || Float.compare value 0. <= 0
    then invalid_arg (Printf.sprintf "View.Viewport.%s must be finite and positive" label)
  ;;

  module Vertical = struct
    type t = vertical_viewport

    let map f (Vertical_viewport widget) = Vertical_viewport (f widget)
    let widget (Vertical_viewport widget) = widget
    let with_test_id test_id = map (with_test_id test_id)
    let padding ~insets = map (padding ~insets)
    let background ?corner_radius ~color = map (background ?corner_radius ~color)
    let semantics ~properties = map (semantics ~properties)
    let ignores_safe_area ?regions ?edges = map (ignores_safe_area ?regions ?edges)
    let safe_area_padding ~insets = map (safe_area_padding ~insets)
    let theme ~data = map (theme ~data)

    let overlay ?key ?alignment ~overlay:content =
      map (overlay ?key ?alignment ~overlay:content)
    ;;

    let with_height ~height viewport =
      positive_extent "Vertical.with_height" height;
      frame ~height (widget viewport)
    ;;
  end

  module Horizontal = struct
    type t = horizontal_viewport

    let map f (Horizontal_viewport widget) = Horizontal_viewport (f widget)
    let widget (Horizontal_viewport widget) = widget
    let with_test_id test_id = map (with_test_id test_id)
    let padding ~insets = map (padding ~insets)
    let background ?corner_radius ~color = map (background ?corner_radius ~color)
    let semantics ~properties = map (semantics ~properties)
    let ignores_safe_area ?regions ?edges = map (ignores_safe_area ?regions ?edges)
    let safe_area_padding ~insets = map (safe_area_padding ~insets)
    let theme ~data = map (theme ~data)

    let overlay ?key ?alignment ~overlay:content =
      map (overlay ?key ?alignment ~overlay:content)
    ;;

    let with_width ~width viewport =
      positive_extent "Horizontal.with_width" width;
      frame ~width (widget viewport)
    ;;
  end
end

let scroll_observer_bindings = function
  | None -> [||]
  | Some handler -> [| { tag = Event.Tag.Scroll_notification; handler } |]
;;

module Scroll_anchor = struct
  type t =
    | Start
    | End
end

let scroll_anchor_code = function
  | Scroll_anchor.Start -> 0
  | Scroll_anchor.End -> 1
;;

module Scroll = struct
  let content
        ?key
        ?on_scroll
        ~vertical
        ~shows_indicators
        ~fill_viewport
        ~initial_anchor
        child
    =
    create_typed
      ~key
      ~node:
        (Scroll
           { vertical
           ; shows_indicators
           ; fill_viewport
           ; initial_anchor = scroll_anchor_code initial_anchor
           })
      ~event_bindings:(scroll_observer_bindings on_scroll)
      ~children:[| child |]
  ;;

  let vertical
        ?key
        ?on_scroll
        ?(shows_indicators = true)
        ?(fill_viewport = false)
        ?(initial_anchor = Scroll_anchor.Start)
        child
    =
    content
      ?key
      ?on_scroll
      ~vertical:true
      ~shows_indicators
      ~fill_viewport
      ~initial_anchor
      child
    |> vertical_viewport
  ;;

  let horizontal
        ?key
        ?on_scroll
        ?(shows_indicators = true)
        ?(fill_viewport = false)
        ?(initial_anchor = Scroll_anchor.Start)
        child
    =
    content
      ?key
      ?on_scroll
      ~vertical:false
      ~shows_indicators
      ~fill_viewport
      ~initial_anchor
      child
    |> horizontal_viewport
  ;;
end

module Scroll_sections = struct
  type section =
    { key : Key.t
    ; view : t
    ; hero : bool
    }

  let section ~key ?header ?footer items =
    let keys = List.map (fun (T item) -> item.key) items in
    if
      List.exists Option.is_none keys
      || List.length (List.sort_uniq compare keys) <> List.length keys
    then invalid_arg "View.Scroll_sections: item keys must be present and unique";
    let slot = function
      | None -> frame (empty ())
      | Some view -> frame view
    in
    let view =
      create_typed
        ~key:(Some key)
        ~node:
          (Scroll_section
             { has_header = Option.is_some header
             ; has_footer = Option.is_some footer
             ; hero_height = None
             ; stretch = false
             })
        ~event_bindings:[||]
        ~children:(plain_children (slot header :: slot footer :: items))
    in
    { key; view; hero = false }
  ;;

  let hero ~key ~height ?(stretch = false) child =
    if (not (Float.is_finite height)) || height <= 0.
    then invalid_arg "View.Scroll_sections: hero height must be positive";
    let view =
      create_typed
        ~key:(Some key)
        ~node:
          (Scroll_section
             { has_header = false
             ; has_footer = false
             ; hero_height = Some height
             ; stretch
             })
        ~event_bindings:[||]
        ~children:[| frame (empty ()); frame (empty ()); child |]
    in
    { key; view; hero = true }
  ;;

  let content
        ?key
        ?on_scroll
        ?(pin_headers = false)
        ?(pin_footers = false)
        ?(spacing = 0.)
        ?(shows_indicators = true)
        ?(initial_anchor = Scroll_anchor.Start)
        ~vertical
        sections
    =
    if (not (Float.is_finite spacing)) || spacing < 0.
    then invalid_arg "View.Scroll_sections: invalid spacing";
    if List.length sections > 1024
    then invalid_arg "View.Scroll_sections: at most 1024 sections";
    let keys = List.map (fun section -> section.key) sections in
    if List.length (List.sort_uniq Key.compare keys) <> List.length keys
    then invalid_arg "View.Scroll_sections: duplicate section key";
    List.iteri
      (fun index section ->
         if section.hero && ((not vertical) || index <> 0)
         then invalid_arg "View.Scroll_sections: hero must lead a vertical container")
      sections;
    create_typed
      ~key
      ~node:
        (Scroll_sections
           { vertical
           ; pin_headers
           ; pin_footers
           ; spacing
           ; shows_indicators
           ; initial_anchor = scroll_anchor_code initial_anchor
           })
      ~event_bindings:(scroll_observer_bindings on_scroll)
      ~children:(plain_children (List.map (fun section -> section.view) sections))
  ;;

  let vertical
        ?key
        ?on_scroll
        ?pin_headers
        ?pin_footers
        ?spacing
        ?shows_indicators
        ?initial_anchor
        sections
    =
    content
      ?key
      ?on_scroll
      ?pin_headers
      ?pin_footers
      ?spacing
      ?shows_indicators
      ?initial_anchor
      ~vertical:true
      sections
    |> vertical_viewport
  ;;

  let horizontal
        ?key
        ?on_scroll
        ?pin_headers
        ?pin_footers
        ?spacing
        ?shows_indicators
        ?initial_anchor
        sections
    =
    content
      ?key
      ?on_scroll
      ?pin_headers
      ?pin_footers
      ?spacing
      ?shows_indicators
      ?initial_anchor
      ~vertical:false
      sections
    |> horizontal_viewport
  ;;
end

module Removal = struct
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

  let request_of_payload = function
    | Event.Payload.Int64_pair { first = token; second } ->
      (match second with
       | 0L -> Some (token, Start_to_end)
       | 1L -> Some (token, End_to_start)
       | 2L -> Some (token, Up)
       | 3L -> Some (token, Down)
       | _ -> None)
    | _ -> None
  ;;

  let create
        ~key
        ?(axis = Layout.Axis.Horizontal)
        ?(collapse_axis = Layout.Axis.Vertical)
        ?(title = "Delete")
        ?(duration_ms = 180)
        ~request_token
        ~request_state
        ~on_request
        ~on_removed
        child
    =
    if String.trim title = "" then invalid_arg "View.Removal: title must not be blank";
    if duration_ms < 0 || Int64.of_int duration_ms > 0xffffffffL
    then invalid_arg "View.Removal: duration must be unsigned 32-bit milliseconds";
    create_typed
      ~key:(Some key)
      ~node:
        (Removal
           { request_token
           ; title
           ; duration_ms
           ; vertical = axis = Layout.Axis.Vertical
           ; collapse_vertical = collapse_axis = Layout.Axis.Vertical
           ; request_state =
               (match request_state with
                | Ready -> 0
                | Pending -> 1
                | Accepted -> 2
                | Rejected -> 3)
           })
      ~event_bindings:
        [| { tag = Event.Tag.Removal_requested; handler = on_request }
         ; { tag = Event.Tag.Removal_completed; handler = on_removed }
        |]
      ~children:[| child |]
  ;;
end

module Refresh = struct
  type request_state =
    | Ready
    | Pending
    | Completed

  let vertical ?key ?show_token ~request_token ~request_state ~on_request viewport =
    let child = Viewport.Vertical.widget viewport in
    let (T child_view) = child in
    (match node_kind_tag child_view.node with
     | K_scroll | K_scroll_sections | K_collection_catalog | K_scroll_targets -> ()
     | _ ->
       invalid_arg "View.Refresh: wrap the native vertical container before decorating it");
    create_typed
      ~key
      ~node:
        (Refresh
           { request_token
           ; show_token
           ; request_state =
               (match request_state with
                | Ready -> 0
                | Pending -> 1
                | Completed -> 2)
           })
      ~event_bindings:[| { tag = Event.Tag.Refresh_request; handler = on_request } |]
      ~children:[| child |]
    |> vertical_viewport
  ;;
end

module Scroll_targets = struct
  type alignment =
    | Start
    | Center
    | End

  type item =
    { id : int64
    ; child : t
    }

  let item ~id child = { id; child }

  let content
        ?key
        ?on_scroll
        ?(fraction = 1.)
        ?(spacing = 0.)
        ?(alignment = Start)
        ?(snapping = true)
        ?(enabled = true)
        ?(shows_indicators = true)
        ~vertical
        ~position
        ~on_position_changed
        items
    =
    if
      (not (Float.is_finite fraction))
      || fraction <= 0.
      || fraction > 1.
      || (not (Float.is_finite spacing))
      || spacing < 0.
    then invalid_arg "View.Scroll_targets: invalid fraction or spacing";
    if List.length items > 65535 then invalid_arg "View.Scroll_targets: too many items";
    let ids = List.map (fun item -> item.id) items in
    let seen = Hashtbl.create (List.length ids) in
    List.iter
      (fun id ->
         if Hashtbl.mem seen id then invalid_arg "View.Scroll_targets: duplicate item ID";
         Hashtbl.add seen id ())
      ids;
    (match ids, position with
     | [], None -> ()
     | _ :: _, Some id when Hashtbl.mem seen id -> ()
     | _ -> invalid_arg "View.Scroll_targets: position must name an item");
    let alignment =
      match alignment with
      | Start -> 0
      | Center -> 1
      | End -> 2
    in
    create_typed
      ~key
      ~node:
        (Scroll_targets
           { vertical
           ; ids
           ; position
           ; fraction
           ; spacing
           ; alignment
           ; snapping
           ; enabled
           ; shows_indicators
           })
      ~event_bindings:
        (Array.append
           (scroll_observer_bindings on_scroll)
           (if enabled
            then
              [| { tag = Event.Tag.Scroll_position_changed
                 ; handler = on_position_changed
                 }
              |]
            else [||]))
      ~children:
        (Array.of_list
           (List.map
              (fun item -> with_application_key (Key.int64 item.id) item.child)
              items))
  ;;

  let horizontal
        ?key
        ?on_scroll
        ?fraction
        ?spacing
        ?alignment
        ?snapping
        ?enabled
        ?shows_indicators
        ~position
        ~on_position_changed
        items
    =
    content
      ?key
      ?on_scroll
      ?fraction
      ?spacing
      ?alignment
      ?snapping
      ?enabled
      ?shows_indicators
      ~vertical:false
      ~position
      ~on_position_changed
      items
    |> horizontal_viewport
  ;;

  let vertical
        ?key
        ?on_scroll
        ?fraction
        ?spacing
        ?alignment
        ?snapping
        ?enabled
        ?shows_indicators
        ~position
        ~on_position_changed
        items
    =
    content
      ?key
      ?on_scroll
      ?fraction
      ?spacing
      ?alignment
      ?snapping
      ?enabled
      ?shows_indicators
      ~vertical:true
      ~position
      ~on_position_changed
      items
    |> vertical_viewport
  ;;
end

module Collection = struct
  type sizing =
    | Declared
    | Measured of { revision : int64 }

  module Initial_position = struct
    type t =
      | Start
      | End
      | Item of Key.t
  end

  type extent =
    { index : int
    ; extent : float
    }

  module Catalog = struct
    type t =
      { keys : string array
      ; key_set : (string, unit) Hashtbl.t
      ; measurement_revision : int64 option
      ; default_extent : float
      ; overrides : (int * float) list
      ; overscan : int
      ; expand_duration_ms : int
      ; collapse_duration_ms : int
      }

    let create
          ~keys
          ~default_extent
          ?(sizing = Declared)
          ?(overrides = [])
          ?(overscan = 4)
          ?(expand_duration_ms = 0)
          ?(collapse_duration_ms = 0)
          ()
      =
      let measurement_revision =
        match sizing with
        | Declared -> None
        | Measured { revision } when revision >= 0L -> Some revision
        | Measured _ ->
          invalid_arg "Collection.Catalog.create: negative measurement revision"
      in
      let count = List.length keys in
      let positive value =
        Float.is_finite value && value > 0. && value <= 9_007_199_254_740_992.
      in
      if count > 1_000_000 || not (positive default_extent)
      then invalid_arg "Collection.Catalog.create: invalid count or default extent";
      validate_u32 ~context:"Collection.Catalog.create" ~label:"overscan" overscan;
      validate_u32
        ~context:"Collection.Catalog.create"
        ~label:"expand_duration_ms"
        expand_duration_ms;
      validate_u32
        ~context:"Collection.Catalog.create"
        ~label:"collapse_duration_ms"
        collapse_duration_ms;
      let seen = Hashtbl.create count in
      let keys =
        Array.of_list
          (List.map
             (fun key ->
                let key = Key.to_debug_string key in
                if String.length key > 1_048_576 || Hashtbl.mem seen key
                then invalid_arg "Collection.Catalog.create: duplicate or oversized key";
                Hashtbl.add seen key ();
                key)
             keys)
      in
      let previous = ref (-1) in
      let adjustment = ref 0. in
      let overrides =
        List.map
          (fun (extent : extent) ->
             if
               extent.index <= !previous
               || extent.index >= count
               || not (positive extent.extent)
             then invalid_arg "Collection.Catalog.create: invalid or unordered extent";
             previous := extent.index;
             adjustment := !adjustment +. extent.extent -. default_extent;
             extent.index, extent.extent)
          overrides
      in
      let total = (float_of_int count *. default_extent) +. !adjustment in
      if
        (not (Float.is_finite total))
        || total < 0.
        || total > 9_007_199_254_740_992.
        || (count > 0 && total = 0.)
      then invalid_arg "Collection.Catalog.create: unrepresentable total extent";
      { keys
      ; key_set = seen
      ; measurement_revision
      ; default_extent
      ; overrides
      ; overscan
      ; expand_duration_ms
      ; collapse_duration_ms
      }
    ;;

    let count t = Array.length t.keys
  end

  module Window = struct
    type t =
      { first_index : int
      ; last_exclusive : int
      }

    let create ~(catalog : Catalog.t) ~visible_first_index ~visible_last_exclusive =
      let count = Catalog.count catalog in
      if
        visible_first_index < 0
        || visible_last_exclusive < visible_first_index
        || visible_last_exclusive > count
      then invalid_arg "Collection.Window.create: invalid visible range";
      if visible_first_index = visible_last_exclusive
      then { first_index = visible_first_index; last_exclusive = visible_last_exclusive }
      else
        { first_index = visible_first_index - min visible_first_index catalog.overscan
        ; last_exclusive =
            visible_last_exclusive + min (count - visible_last_exclusive) catalog.overscan
        }
    ;;
  end

  let content
        ?key
        ?(initial_position = Initial_position.Start)
        ?on_scroll
        ~vertical
        ~(catalog : Catalog.t)
        ~first_index
        ~items
        ~on_visible_range
        ()
    =
    let initial_anchor, initial_key =
      match initial_position with
      | Initial_position.Start -> 0, None
      | Initial_position.End -> 1, None
      | Initial_position.Item key ->
        let key = Key.to_debug_string key in
        if not (Hashtbl.mem catalog.key_set key)
        then invalid_arg "Collection: initial item must belong to the catalog";
        2, Some key
    in
    let children = keyed_children items in
    let count = Array.length children in
    if
      first_index < 0
      || first_index > Catalog.count catalog
      || count > Catalog.count catalog - first_index
    then invalid_arg "Collection: window is outside catalog";
    Array.iteri
      (fun index (T child) ->
         match child.key with
         | Some key
           when String.equal (Key.to_debug_string key) catalog.keys.(first_index + index)
           -> ()
         | _ -> invalid_arg "Collection: materialized key differs from catalog")
      children;
    let keys = Array.sub catalog.keys first_index count in
    let window =
      create_typed
        ~key:(Some (Key.string "window"))
        ~node:(Collection_window { first_index; keys })
        ~event_bindings:[||]
        ~children
    in
    create_typed
      ~key
      ~node:
        (Collection_catalog
           { keys = catalog.keys
           ; default_extent = catalog.default_extent
           ; overrides = catalog.overrides
           ; overscan = catalog.overscan
           ; expand_duration_ms = catalog.expand_duration_ms
           ; collapse_duration_ms = catalog.collapse_duration_ms
           ; vertical
           ; initial_anchor
           ; initial_key
           ; measurement_revision = catalog.measurement_revision
           })
      ~event_bindings:
        (Array.append
           (scroll_observer_bindings on_scroll)
           [| { tag = Event.Tag.Visible_range_changed; handler = on_visible_range } |])
      ~children:[| window |]
  ;;

  let vertical
        ?key
        ?initial_position
        ?on_scroll
        ~catalog
        ~first_index
        ~items
        ~on_visible_range
        ()
    =
    content
      ?key
      ?initial_position
      ?on_scroll
      ~vertical:true
      ~catalog
      ~first_index
      ~items
      ~on_visible_range
      ()
    |> vertical_viewport
  ;;

  let horizontal
        ?key
        ?initial_position
        ?on_scroll
        ~catalog
        ~first_index
        ~items
        ~on_visible_range
        ()
    =
    content
      ?key
      ?initial_position
      ?on_scroll
      ~vertical:false
      ~catalog
      ~first_index
      ~items
      ~on_visible_range
      ()
    |> horizontal_viewport
  ;;

  let visible_range_of_payload = function
    | Event.Payload.Visible_range range -> Some range
    | _ -> None
  ;;
end

type body = Body of t

type vertical_body_child =
  | Vertical_fixed of t
  | Vertical_fill of float * vertical_viewport

type horizontal_body_child =
  | Horizontal_fixed of t
  | Horizontal_fill of float * horizontal_viewport

module Toolbar = struct
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

  type item =
    { key : Key.t
    ; placement : placement
    ; content : t
    }

  let item ~key ?(placement = Automatic) content = { key; placement; content }

  let placement_id = function
    | Automatic -> 0
    | Principal -> 1
    | Navigation -> 2
    | Primary_action -> 3
    | Secondary_action -> 4
    | Status -> 5
    | Confirmation_action -> 6
    | Cancellation_action -> 7
    | Destructive_action -> 8
  ;;

  let create ?key ~items content =
    if List.length items > 256 then invalid_arg "View.Toolbar: at most 256 items";
    if List.length (List.filter (fun item -> item.placement = Principal) items) > 1
    then invalid_arg "View.Toolbar: at most one principal item";
    let keys = List.map (fun item -> item.key) items in
    if List.length (List.sort_uniq Key.compare keys) <> List.length keys
    then invalid_arg "View.Toolbar: duplicate item keys";
    create_typed
      ~key
      ~node:
        (Toolbar { placements = List.map (fun item -> placement_id item.placement) items })
      ~event_bindings:[||]
      ~children:
        (plain_children
           (content
            :: List.map (fun item -> with_application_key item.key item.content) items))
  ;;
end

module Body = struct
  type nonrec widget = t
  type t = body

  let with_size ~width ~height (Body widget) =
    if
      (not (Float.is_finite width && Float.is_finite height))
      || width <= 0.
      || height <= 0.
    then invalid_arg "View.Body.with_size: dimensions must be finite and positive";
    frame ~width ~height widget
  ;;

  let static widget = Body widget
  let map f (Body widget) = Body (f widget)
  let with_test_id test_id = map (with_test_id test_id)
  let padding ~insets = map (padding ~insets)
  let background ?corner_radius ~color = map (background ?corner_radius ~color)
  let semantics ~properties = map (semantics ~properties)
  let ignores_safe_area ?regions ?edges = map (ignores_safe_area ?regions ?edges)
  let safe_area_padding ~insets = map (safe_area_padding ~insets)
  let theme ~data = map (theme ~data)
  let toolbar ?key ~items = map (Toolbar.create ?key ~items)

  let positive_weight axis weight =
    if (not (Float.is_finite weight)) || Float.compare weight 0. <= 0
    then
      invalid_arg
        (Printf.sprintf "View.Body.%s.fill: weight must be finite and positive" axis);
    weight
  ;;

  let nonempty axis children =
    if children = []
    then
      invalid_arg
        (Printf.sprintf "View.Body.%s.create: at least one child is required" axis)
  ;;

  module Vertical = struct
    type child = vertical_body_child

    let fixed widget = Vertical_fixed widget

    let fill ?(weight = 1.) viewport =
      Vertical_fill (positive_weight "Vertical" weight, viewport)
    ;;

    let create ?key children =
      nonempty "Vertical" children;
      children
      |> List.map (function
        | Vertical_fixed widget -> Weighted.fixed widget
        | Vertical_fill (weight, viewport) ->
          Weighted.share ~weight (Viewport.Vertical.widget viewport))
      |> Weighted.column ?key
      |> fun widget -> Body widget
    ;;
  end

  module Horizontal = struct
    type child = horizontal_body_child

    let fixed widget = Horizontal_fixed widget

    let fill ?(weight = 1.) viewport =
      Horizontal_fill (positive_weight "Horizontal" weight, viewport)
    ;;

    let create ?key children =
      nonempty "Horizontal" children;
      children
      |> List.map (function
        | Horizontal_fixed widget -> Weighted.fixed widget
        | Horizontal_fill (weight, viewport) ->
          Weighted.share ~weight (Viewport.Horizontal.widget viewport))
      |> Weighted.row ?key
      |> fun widget -> Body widget
    ;;
  end

  let overlay ?key ?alignment ~overlay:content =
    map (overlay ?key ?alignment ~overlay:content)
  ;;

  module Private = struct
    let to_widget (Body widget) = widget
  end
end

module Table = struct
  type column =
    { id : int64
    ; title : string
    ; help : string option
    ; numeric : bool
    ; sortable : bool
    ; details : t option
    }

  type row =
    { id : int64
    ; selection_enabled : bool
    ; cells : t list
    }

  let column ~id ~title ?help ?(numeric = false) ?(sortable = false) ?details () =
    if String.trim title = ""
    then invalid_arg "View.Table.column: title must not be empty";
    Option.iter
      (fun value ->
         if String.trim value = ""
         then invalid_arg "View.Table.column: help must not be empty")
      help;
    { id; title; help; numeric; sortable; details }
  ;;

  let row ~id ?(selection_enabled = true) cells = { id; selection_enabled; cells }

  let unique context ids =
    let result = Hashtbl.create (List.length ids) in
    List.iter
      (fun id ->
         if Hashtbl.mem result id then invalid_arg ("View.Table: duplicate " ^ context);
         Hashtbl.add result id ())
      ids;
    result
  ;;

  let create
        ?key
        ?sort_column_id
        ?(sort_ascending = true)
        ?(selected_row_ids = [])
        ?on_sort
        ?on_row_selected
        ~columns
        ~rows
        ()
    =
    if columns = [] || List.length columns > 65535
    then invalid_arg "View.Table: column count must be 1..65535";
    if List.length rows > 65535 then invalid_arg "View.Table: at most 65535 rows";
    let _ = unique "column ID" (List.map (fun (column : column) -> column.id) columns) in
    let row_ids = unique "row ID" (List.map (fun (row : row) -> row.id) rows) in
    let _ = unique "selected ID" selected_row_ids in
    List.iter
      (fun id ->
         if not (Hashtbl.mem row_ids id)
         then invalid_arg "View.Table: selected row is absent")
      selected_row_ids;
    List.iter
      (fun (row : row) ->
         if List.length row.cells <> List.length columns
         then invalid_arg "View.Table: each row needs one cell per column")
      rows;
    Option.iter
      (fun id ->
         if
           not
             (List.exists
                (fun (column : column) -> column.id = id && column.sortable)
                columns)
         then invalid_arg "View.Table: sort column must exist and be sortable")
      sort_column_id;
    let keyed key content = with_application_key (Key.string key) content in
    let children =
      List.map
        (fun (column : column) ->
           keyed
             ("header:" ^ Int64.to_string column.id)
             (Option.value column.details ~default:(text column.title)))
        columns
      @ List.concat_map
          (fun (row : row) ->
             List.map2
               (fun (column : column) cell ->
                  keyed (Printf.sprintf "cell:%Ld:%Ld" row.id column.id) cell)
               columns
               row.cells)
          rows
    in
    Body
      (table
         ?key
         ~columns:
           (List.map
              (fun (column : column) ->
                 ({ column_id = column.id
                  ; title = column.title
                  ; tooltip = column.help
                  ; numeric = column.numeric
                  ; sortable = column.sortable
                  ; has_details = Option.is_some column.details
                  }
                  : table_column))
              columns)
         ~rows:
           (List.map
              (fun (row : row) ->
                 ({ row_id = row.id; selection_enabled = row.selection_enabled }
                  : table_row))
              rows)
         ~sort_column_id
         ~sort_ascending
         ~selected_row_ids:(List.sort Int64.compare selected_row_ids)
         ~on_sort
         ~on_row_selected
         ~children
         ())
  ;;
end

module Navigation_stack = struct
  type destination = t

  let destination ?key ~page_key ~title ?(can_pop = true) (Body child) =
    let key_string = ID.Navigation.Page_key.to_string page_key in
    if String.length key_string = 0
    then invalid_arg "Navigation_stack.destination: empty page key";
    let key =
      match key with
      | Some key -> key
      | None -> Key.string ("navigation-destination:" ^ key_string)
    in
    create_typed
      ~key:(Some key)
      ~node:(Navigation_destination { page_key; title; can_pop })
      ~event_bindings:[||]
      ~children:(plain_children [ child ])
  ;;

  let create ?key ~title ~on_path_change ~path (Body root) =
    if List.length path > 256
    then invalid_arg "Navigation_stack.create: path exceeds 256 destinations";
    let seen = Hashtbl.create (List.length path) in
    List.iter
      (fun (T view) ->
         match view.node with
         | Navigation_destination { page_key; _ } ->
           let key = ID.Navigation.Page_key.to_string page_key in
           if Hashtbl.mem seen key
           then invalid_arg "Navigation_stack.create: duplicate page key";
           Hashtbl.add seen key ()
         | _ -> invalid_arg "Navigation_stack.create: invalid destination")
      path;
    create_typed
      ~key
      ~node:(Navigation_stack { title })
      ~event_bindings:
        [| { tag = Event.Tag.Navigation_path_changed; handler = on_path_change } |]
      ~children:(plain_children (root :: path))
  ;;
end

module Navigation_split = struct
  let create
        ?key
        ~state
        ~sidebar_title
        ~content_title
        ~detail_title
        ~on_change
        ~sidebar
        ~content
        ~detail
        ()
    =
    create_typed
      ~key
      ~node:
        (Navigation_split
           { state; sidebar_title; content_title = Some content_title; detail_title })
      ~event_bindings:
        [| { tag = Event.Tag.Navigation_split_changed; handler = on_change } |]
      ~children:
        (plain_children (List.map Body.Private.to_widget [ sidebar; content; detail ]))
  ;;

  let two_columns ?key ~state ~sidebar_title ~detail_title ~on_change ~sidebar ~detail () =
    if Navigation.Split_state.compact_column state = Navigation.Split_column.Content
    then invalid_arg "Navigation_split.two_columns: Content is not a column";
    create_typed
      ~key
      ~node:
        (Navigation_split { state; sidebar_title; content_title = None; detail_title })
      ~event_bindings:
        [| { tag = Event.Tag.Navigation_split_changed; handler = on_change } |]
      ~children:(plain_children (List.map Body.Private.to_widget [ sidebar; detail ]))
  ;;
end

let disclosure_group ?key ?(enabled = true) ~expanded ~on_changed ~label ~content () =
  create_typed
    ~key
    ~node:(Disclosure_group { expanded; enabled })
    ~event_bindings:
      (if enabled
       then [| { tag = Event.Tag.Value_changed; handler = on_changed } |]
       else [||])
    ~children:(plain_children [ label; content ])
;;

let toggle
      ?key
      ?(style = Toggle_style.Automatic)
      ?(enabled = true)
      ~value
      ~on_changed
      ~label
      ()
  =
  let style =
    match style with
    | Toggle_style.Automatic -> 0
    | Switch -> 1
    | Checkbox -> 2
    | Button -> 3
  in
  create_typed
    ~key
    ~node:(Toggle { value; enabled; style })
    ~event_bindings:
      (if enabled
       then [| { tag = Event.Tag.Value_changed; handler = on_changed } |]
       else [||])
    ~children:(plain_children [ label ])
;;

module Slider = struct
  module Range = struct
    type t =
      { start : float
      ; end_ : float
      }

    let create ~start ~end_ = { start; end_ }
  end

  let validate ~value ~min ~max ~step ~label =
    if
      (not
         (Float.is_finite value
          && Float.is_finite min
          && Float.is_finite max
          && Float.is_finite (max -. min)))
      || min >= max
      || value < min
      || value > max
      || label = ""
    then invalid_arg "View.Slider: invalid value, domain, or label";
    match step with
    | Some step
      when (not (Float.is_finite step))
           || step <= 0.
           || step > max -. min
           || min +. step <= min
           || max -. step >= max -> invalid_arg "View.Slider: invalid step"
    | _ -> ()
  ;;

  let bindings ~enabled ~changed ~ended ~on_change ~on_change_end =
    if not enabled
    then [||]
    else
      Array.of_list
        (Option.to_list (Option.map (fun handler -> { tag = changed; handler }) on_change)
         @ [ { tag = ended; handler = on_change_end } ])
  ;;

  let create
        ?key
        ?(min = 0.)
        ?(max = 1.)
        ?step
        ?(enabled = true)
        ?(axis = Layout.Axis.Horizontal)
        ?on_change
        ~value
        ~label
        ~on_change_end
        ()
    =
    validate ~value ~min ~max ~step ~label;
    create_typed
      ~key
      ~node:
        (Slider
           { value
           ; min
           ; max
           ; step
           ; label
           ; enabled
           ; vertical = axis = Vertical
           ; has_on_change = Option.is_some on_change
           })
      ~event_bindings:
        (bindings
           ~enabled
           ~changed:Event.Tag.Slider_changed
           ~ended:Event.Tag.Slider_change_end
           ~on_change
           ~on_change_end)
      ~children:[||]
  ;;

  let range
        ?key
        ?(min = 0.)
        ?(max = 1.)
        ?step
        ?(enabled = true)
        ?(axis = Layout.Axis.Horizontal)
        ?on_change
        ~(value : Range.t)
        ~label_start
        ~label_end
        ~on_change_end
        ()
    =
    validate ~value:value.start ~min ~max ~step ~label:label_start;
    validate ~value:value.end_ ~min ~max ~step ~label:label_end;
    if value.start > value.end_ then invalid_arg "View.Slider.range: reversed interval";
    create_typed
      ~key
      ~node:
        (Range_slider
           { start = value.start
           ; end_ = value.end_
           ; min
           ; max
           ; step
           ; label_start
           ; label_end
           ; enabled
           ; vertical = axis = Vertical
           ; has_on_change = Option.is_some on_change
           })
      ~event_bindings:
        (bindings
           ~enabled
           ~changed:Event.Tag.Range_slider_changed
           ~ended:Event.Tag.Range_slider_change_end
           ~on_change
           ~on_change_end)
      ~children:[||]
  ;;
end

module Swipe_actions = struct
  type action = t

  type side =
    | Start
    | End

  let action
        ?key
        ?(enabled = true)
        ?(role = Button_role.Normal)
        ?(extent = 80.)
        ?(auto_close = true)
        ?(full_swipe = false)
        ~side
        ~title
        ~background
        ~on_press
        ~child
        ()
    =
    if
      String.length title = 0
      || (not (Float.is_finite extent))
      || extent < 44.
      || extent > 4096.
    then invalid_arg "View.Swipe_actions.action: invalid title or extent";
    let side =
      match side with
      | Start -> 0
      | End -> 1
    in
    let role =
      match role with
      | Button_role.Normal -> 0
      | Cancel -> 1
      | Destructive -> 2
    in
    create_typed
      ~key
      ~node:
        (Swipe_action
           { title
           ; side
           ; enabled
           ; role
           ; extent
           ; background =
               Int32.to_int (Style.Color.Private.to_argb32 background) land 0xffff_ffff
           ; auto_close
           ; full_swipe
           })
      ~event_bindings:
        (if enabled then [| { tag = Event.Tag.Press; handler = on_press } |] else [||])
      ~children:(plain_children [ child ])
  ;;

  let create
        ~key
        ?(enabled = true)
        ?(axis = Layout.Axis.Horizontal)
        ?(close_on_scroll = true)
        ?group
        ?(close_when_opened = true)
        ?(close_when_tapped = true)
        ~actions
        ~content
        ()
    =
    if group = Some "" || List.length actions > 64
    then invalid_arg "View.Swipe_actions.create: invalid group or action count";
    let full = Array.make 2 false in
    List.iter
      (fun action ->
         let (T view) = action in
         match view.node with
         | Swipe_action p ->
           if p.full_swipe
           then (
             if full.(p.side)
             then
               invalid_arg
                 "View.Swipe_actions.create: multiple full-swipe actions on one side";
             full.(p.side) <- true)
         | _ -> invalid_arg "View.Swipe_actions.create: invalid action")
      actions;
    create_typed
      ~key:(Some key)
      ~node:
        (Swipe_actions
           { enabled
           ; vertical = axis = Layout.Axis.Vertical
           ; close_on_scroll
           ; group
           ; close_when_opened
           ; close_when_tapped
           })
      ~event_bindings:[||]
      ~children:(plain_children (content :: actions))
  ;;
end

module Morphing_surface = struct
  let create
        ?key
        ?(expand_duration_ms = 240)
        ?(collapse_duration_ms = 190)
        ~expanded
        ~content
        ()
    =
    validate_u32
      ~context:"View.Morphing_surface.create"
      ~label:"expand_duration_ms"
      expand_duration_ms;
    validate_u32
      ~context:"View.Morphing_surface.create"
      ~label:"collapse_duration_ms"
      collapse_duration_ms;
    create_typed
      ~key
      ~node:(Morphing_surface { expanded; expand_duration_ms; collapse_duration_ms })
      ~event_bindings:[||]
      ~children:(plain_children [ content ])
  ;;
end

module Tabs = struct
  type item = t

  let item ?key ?badge ?accessibility_label ~page_key ~title ~symbol body =
    List.iter
      (Option.iter (fun text ->
         if String.trim text = "" then invalid_arg "View.Tabs.item: empty metadata"))
      [ badge; accessibility_label ];
    let name = ID.Navigation.Page_key.to_string page_key in
    if String.length name = 0 || String.length symbol = 0
    then invalid_arg "View.Tabs.item: empty page key or symbol";
    let key =
      match key with
      | Some key -> key
      | None -> Key.string ("tab:" ^ name)
    in
    create_typed
      ~key:(Some key)
      ~node:(Tab { page_key; title; symbol; badge; accessibility_label })
      ~event_bindings:[||]
      ~children:(plain_children [ Body.Private.to_widget body ])
  ;;

  let create ?key ~selection ~on_change items =
    if items = [] || List.length items > 256
    then invalid_arg "View.Tabs.create: expected one to 256 items";
    let seen = Hashtbl.create (List.length items) in
    List.iter
      (fun (T view) ->
         match view.node with
         | Tab { page_key; _ } ->
           let name = ID.Navigation.Page_key.to_string page_key in
           if Hashtbl.mem seen name
           then invalid_arg "View.Tabs.create: duplicate page key";
           Hashtbl.add seen name ()
         | _ -> invalid_arg "View.Tabs.create: invalid item")
      items;
    if not (Hashtbl.mem seen (ID.Navigation.Page_key.to_string selection))
    then invalid_arg "View.Tabs.create: unknown selection";
    create_typed
      ~key
      ~node:(Tabs { selection })
      ~event_bindings:[| { tag = Event.Tag.Tab_selected; handler = on_change } |]
      ~children:(plain_children items)
  ;;
end

module For_testing = struct
  let kind_name widget =
    let (T view) = widget in
    kind_tag_to_string (node_kind_tag view.node)
  ;;

  let key widget =
    let (T view) = widget in
    view.key
  ;;

  let test_id widget =
    let (T view) = widget in
    view.test_id
  ;;

  let children widget =
    let (T view) = widget in
    Array.copy view.children
  ;;

  let text_content widget =
    let (T view) = widget in
    match view.node with
    | Text { value; _ } -> Some value
    | _ -> None
  ;;
end

module Private = struct
  type nonrec kind_tag = kind_tag =
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

  let kind_tag_compare = kind_tag_compare
  let kind_tag_equal = kind_tag_equal
  let kind_tag_to_string = kind_tag_to_string

  type nonrec weighted_sizing = weighted_sizing =
    | Intrinsic
    | Share of
        { weight : float
        ; fills : bool
        }

  type nonrec menu_item = menu_item =
    { menu_id : int64
    ; kind : int
    ; enabled : bool
    ; selected : bool
    ; role : int
    ; has_label : bool
    ; child_count : int
    }

  type nonrec picker_option = picker_option =
    { option_id : int64
    ; enabled : bool
    ; has_label : bool
    }

  type nonrec table_column = table_column =
    { column_id : int64
    ; title : string
    ; has_details : bool
    ; tooltip : string option
    ; numeric : bool
    ; sortable : bool
    }

  type nonrec table_row = table_row =
    { row_id : int64
    ; selection_enabled : bool
    }

  include Private_types

  type any_view = Av : 'k view -> any_view

  let view widget =
    let (T v) = widget in
    Av v
  ;;

  let node_equal_widgets left right =
    let (Av left_view) = view left in
    let (Av right_view) = view right in
    node_equal left_view.node right_view.node
  ;;

  let kind_tag_of_widget widget =
    let (Av view) = view widget in
    node_kind_tag view.node
  ;;

  let node_kind_tag = node_kind_tag
  let node_equal = node_equal
  let picker = picker
  let table = table
  let native_widget = native_widget
  let vertical_viewport = vertical_viewport
  let horizontal_viewport = horizontal_viewport
end
