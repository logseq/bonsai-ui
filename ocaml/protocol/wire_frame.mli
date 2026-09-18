type civil_date =
  { year : int
  ; month : int
  ; day : int
  }

type civil_time =
  { hour : int
  ; minute : int
  }

(** Renderer-independent values carried by protocol frames.

    This type deliberately contains no Bonsai closures or application keys. *)

type navigation_split_state =
  { visibility : int
  ; compact_column : int
  ; selection_key : Bonsai_swiftui_spec.Id.Navigation.page_key option
  }

type frame_kind =
  | Full_snapshot
  | Incremental_frame

type node_kind =
  | Empty
  | Spacer
  | Text
  | Rich_text
  | Symbol
  | Image
  | Text_editor
  | Text_field
  | Secure_field
  | Collection_catalog
  | Collection_window
  | Removal
  | Refresh
  | Native_list
  | List_section
  | List_row
  | Scroll_targets
  | Scroll
  | Flow
  | Row
  | Weighted_row
  | Weighted_column
  | Column
  | Stack
  | Layout_priority
  | Offset
  | Padding
  | Frame
  | Background
  | Clip
  | Opacity
  | Animated_opacity
  | Projection_effect
  | Gesture
  | Focus_scope
  | Hover_region
  | Keyboard_listener
  | Button
  | Semantics
  | Theme
  | Date_picker
  | Time_picker
  | Menu
  | Picker
  | Slider
  | Range_slider
  | Table
  | Divider
  | Label
  | Badge
  | Sheet
  | Popover
  | Scroll_sections
  | Scroll_section
  | Toolbar
  | Help
  | Group_box
  | Progress
  | Overlay
  | Disclosure_group
  | Toggle
  | Swipe_actions
  | Swipe_action
  | Morphing_surface
  | Tabs
  | Tab
  | Navigation_split
  | Navigation_stack
  | Navigation_destination
  | Ignores_safe_area
  | Safe_area_padding
  | Control_size
  | Native_widget

type axis =
  | Horizontal
  | Vertical

type alignment =
  | Top_start
  | Top_center
  | Top_end
  | Center_start
  | Center
  | Center_end
  | Bottom_start
  | Bottom_center
  | Bottom_end

type image_source =
  | Resource of string
  | Remote of string

type image_sizing =
  | Original
  | Stretch
  | Fit
  | Fill

type brightness =
  | Light
  | Dark

type text_font_weight =
  | Normal
  | Medium
  | Semi_bold
  | Bold

type text_align =
  | Start
  | Center_text
  | End

type text_truncation =
  | Tail
  | Head
  | Middle

type text_style =
  { font_size : float option
  ; font_weight : text_font_weight option
  ; line_spacing : float option
  ; color : int32 option
  ; role : int
  ; foreground : int option
  ; italic : bool option
  }

type text_span =
  { value : string
  ; font_size : float option
  ; font_weight : text_font_weight option
  ; color : int32 option
  ; italic : bool option
  ; underline : bool
  ; strikethrough : bool
  }

type theme_mode =
  | System
  | Light
  | Dark

type theme =
  { mode : theme_mode
  ; tint : int32 option
  ; font_family : string option
  ; control_size : int
  ; defaults : bytes
  }

type text_props =
  { value : string
  ; style : text_style option
  ; text_align : text_align
  ; line_limit : int option
  ; truncation : text_truncation
  }

type semantics_role =
  | Generic
  | Semantics_button
  | Link
  | Image
  | Header
  | Semantics_toggle
  | Static_text

type text_range =
  { start_utf16 : int
  ; end_utf16 : int
  }

type text_editing_value =
  { text : string
  ; selection : text_range
  ; composing : text_range option
  }

type text_update_mode =
  | Ack
  | Correction
  | Force_replace

type collection_catalog =
  { keys : string list
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

type collection_window =
  { first_index : int
  ; keys : string list
  }

type text_editor =
  { session_id : Bonsai_swiftui_spec.Id.Text_input.session_id
  ; document_revision : Bonsai_swiftui_spec.Id.Text_input.document_revision
  ; accepted_local_revision : Bonsai_swiftui_spec.Id.Text_input.local_revision
  ; update_mode : text_update_mode
  ; value : text_editing_value
  ; enabled : bool
  ; read_only : bool
  ; submit_on_return : bool
  ; max_utf8_bytes : int option
  }

type text_field =
  { editing : text_editor
  ; label : string
  ; prompt : string
  ; secure : bool
  ; keyboard : int
  ; submit_label : int
  ; appearance : int
  ; autofocus : bool
  }

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

type key_policy =
  | Handled
  | Ignored

type animation_curve =
  | Linear
  | Ease_in
  | Ease_out
  | Ease_in_out

type animation =
  { id : Bonsai_swiftui_spec.Id.Ui.animation_id
  ; duration_ms : int
  ; curve : animation_curve
  }

type frame_limit =
  | Points of float
  | Fill_space

type frame_props =
  { width : float option
  ; height : float option
  ; min_width : float option
  ; ideal_width : float option
  ; max_width : frame_limit option
  ; min_height : float option
  ; ideal_height : float option
  ; max_height : frame_limit option
  ; alignment : alignment
  }

type props =
  | Empty_props
  | Spacer_props of { min_length : float option }
  | Text_props of text_props
  | Rich_text_props of { spans : text_span list }
  | Symbol_props of
      { name : string
      ; size : float option
      ; color : int32 option
      ; rendering : int
      }
  | Collection_catalog_props of collection_catalog
  | Collection_window_props of collection_window
  | Removal_props of
      { request_token : int64
      ; request_state : int
      ; vertical : bool
      ; collapse_vertical : bool
      ; title : string
      ; duration_ms : int
      }
  | Native_list_props
  | List_section_props of
      { has_header : bool
      ; has_footer : bool
      ; separator : int
      }
  | List_row_props of { separator : int }
  | Refresh_props of
      { request_token : int64
      ; request_state : int
      ; show_token : int64 option
      }
  | Scroll_targets_props of
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
  | Scroll_props of
      { vertical : bool
      ; shows_indicators : bool
      ; fill_viewport : bool
      ; initial_anchor : int
      }
  | Text_editor_props of
      { editing : text_editor
      ; autofocus : bool
      }
  | Text_field_props of text_field
  | Image_props of
      { source : image_source
      ; sizing : image_sizing
      ; scale : float
      }
  | Weighted_row_props of
      { spacing : float option
      ; alignment : int
      ; items : weighted_sizing list
      }
  | Weighted_column_props of
      { spacing : float option
      ; alignment : int
      ; items : weighted_sizing list
      }
  | Flow_props of
      { spacing : float
      ; line_spacing : float
      ; alignment : int
      }
  | Row_props of
      { spacing : float option
      ; alignment : int
      }
  | Column_props of
      { spacing : float option
      ; alignment : int
      }
  | Stack_props of { alignment : alignment }
  | Layout_priority_props of { priority : float }
  | Offset_props of
      { x : float
      ; y : float
      }
  | Button_props of
      { enabled : bool
      ; role : int
      ; style : int
      ; autofocus : bool
      }
  | Padding_props of
      { leading : float
      ; top : float
      ; trailing : float
      ; bottom : float
      }
  | Frame_props of frame_props
  | Background_props of
      { color : int32
      ; corner_radius : float
      }
  | Clip_props of
      { corner_radius : float
      ; antialiased : bool
      }
  | Opacity_props of { opacity : float }
  | Animated_opacity_props of
      { opacity : float
      ; animation : animation
      }
  | Projection_effect_props of { matrix3 : float array }
  | Gesture_props
  | Focus_scope_props of { autofocus : bool }
  | Hover_region_props of { blocks_behind : bool }
  | Keyboard_listener_props of
      { autofocus : bool
      ; key_policy : key_policy
      }
  | Semantics_props of
      { label : string option
      ; hint : string option
      ; value : string option
      ; role : semantics_role
      ; selected : bool option
      ; children : int
      ; hidden : bool
      ; live_region : bool
      ; heading_level : int option
      ; sort_priority : float option
      ; identifier : string option
      ; actions : (int64 * string) list
      }
  | Theme_props of theme
  | Date_picker_props of
      { selected : civil_date
      ; first : civil_date
      ; last : civil_date
      ; label : string
      ; enabled : bool
      }
  | Time_picker_props of
      { value : civil_time
      ; format : int
      ; label : string
      ; enabled : bool
      }
  | Menu_props of
      { items : menu_item list
      ; enabled : bool
      }
  | Picker_props of
      { selected_id : int64 option
      ; options : picker_option list
      ; label : string
      ; style : int
      ; enabled : bool
      }
  | Slider_props of
      { value : float
      ; min : float
      ; max : float
      ; step : float option
      ; label : string
      ; enabled : bool
      ; vertical : bool
      ; has_on_change : bool
      }
  | Range_slider_props of
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
  | Table_props of
      { columns : table_column list
      ; rows : table_row list
      ; sort_column_id : int64 option
      ; sort_ascending : bool
      ; selected_row_ids : int64 list
      ; has_on_sort : bool
      ; has_on_row_selected : bool
      }
  | Divider_props
  | Label_props
  | Badge_props of
      { count : int64 option
      ; alignment : int
      ; visible : bool
      }
  | Sheet_props of
      { presented : bool
      ; fullscreen : bool
      ; detents : int
      ; fraction : float
      ; initial : int
      ; interactive : bool
      ; indicator : bool
      ; sizing : int
      }
  | Popover_props of
      { presented : bool
      ; edge : int
      }
  | Scroll_sections_props of
      { vertical : bool
      ; pin_headers : bool
      ; pin_footers : bool
      ; spacing : float
      ; shows_indicators : bool
      ; initial_anchor : int
      }
  | Scroll_section_props of
      { has_header : bool
      ; has_footer : bool
      ; hero_height : float option
      ; stretch : bool
      }
  | Toolbar_props of { placements : int list }
  | Help_props of { message : string }
  | Group_box_props of { has_label : bool }
  | Progress_props of
      { value : float option
      ; style : int
      }
  | Overlay_props of { alignment : alignment }
  | Disclosure_group_props of
      { expanded : bool
      ; enabled : bool
      }
  | Toggle_props of
      { value : bool
      ; enabled : bool
      ; style : int
      }
  | Swipe_actions_props of
      { enabled : bool
      ; allows_full_swipe : bool
      }
  | Swipe_action_props of
      { title : string
      ; side : int
      ; enabled : bool
      ; role : int
      ; background : int
      ; symbol : string option
      }
  | Morphing_surface_props of
      { expanded : bool
      ; expand_duration_ms : int
      ; collapse_duration_ms : int
      }
  | Tabs_props of { selection : Bonsai_swiftui_spec.Id.Navigation.page_key }
  | Tab_props of
      { page_key : Bonsai_swiftui_spec.Id.Navigation.page_key
      ; title : string
      ; symbol : string
      ; badge : string option
      ; accessibility_label : string option
      }
  | Navigation_split_props of
      { state : navigation_split_state
      ; sidebar_title : string
      ; content_title : string option
      ; detail_title : string
      }
  | Navigation_stack_props of { title : string }
  | Navigation_destination_props of
      { page_key : Bonsai_swiftui_spec.Id.Navigation.page_key
      ; title : string
      ; can_pop : bool
      }
  | Control_size_props of { size : int }
  | Ignores_safe_area_props of
      { regions : int
      ; edges : int
      }
  | Safe_area_padding_props of
      { leading : float
      ; top : float
      ; trailing : float
      ; bottom : float
      }
  | Native_widget_props of
      { kind_id : Bonsai_swiftui_spec.Id.Native_widget.kind_id
      ; version : int
      ; capabilities : int64
      ; payload : bytes
      }

type file_picker_options =
  { allowed_extensions : string list
  ; allow_multiple : bool
  }

type save_file_options =
  { suggested_name : string option
  ; data : bytes
  }

type scroll_to =
  { node_id : Bonsai_swiftui_spec.Id.Ui.node_id
  ; alignment : float
  ; animated : bool
  }

type size =
  { width : float
  ; height : float
  }

type native_menu_item =
  { item_id : Bonsai_swiftui_spec.Id.Host.native_menu_item_id
  ; label : string
  ; enabled : bool
  }

val validate_native_menu_items : native_menu_item list -> (unit, string) result

type haptic_kind =
  | Haptic_light
  | Haptic_medium
  | Haptic_heavy
  | Haptic_selection

type civil_date_range =
  { start : civil_date
  ; end_ : civil_date
  }

type host_request_payload =
  | Clipboard_read
  | Clipboard_write of { text : string }
  | Open_url of { uri : string }
  | Pick_files of file_picker_options
  | Save_file of save_file_options
  | Request_focus of { node_id : Bonsai_swiftui_spec.Id.Ui.node_id }
  | Clear_focus
  | Scroll_to of scroll_to
  | Set_window_title of { title : string }
  | Set_window_size of size
  | Show_native_menu of { items : native_menu_item list }
  | Haptic_feedback of haptic_kind
  | Platform_information
  | Measure_layout of { node_id : Bonsai_swiftui_spec.Id.Ui.node_id }
  | Show_notice of
      { message : string
      ; action_label : string option
      ; duration_ms : int
      }
  | Pick_date of
      { initial : civil_date option
      ; first : civil_date
      ; last : civil_date
      }
  | Pick_date_range of
      { initial : civil_date_range option
      ; first : civil_date
      ; last : civil_date
      }
  | Pick_time of
      { initial : civil_time
      ; format : int
      }

type event_binding =
  { event_tag : Bonsai_swiftui_spec.Id.Protocol.event_tag
  ; handler_id : Bonsai_swiftui_spec.Id.Ui.handler_id
  }

type runtime_stats =
  { event_batch_size : int
  ; bonsai_flush_ns : int64
  ; result_read_ns : int64
  ; reconcile_ns : int64
  ; encode_ns : int64
  ; patch_count : int
  ; patch_bytes : int
  ; lifecycle_ns : int64
  ; full_snapshot_count : int
  ; resync_count : int
  }

type operation =
  | Create_node of
      { node_id : Bonsai_swiftui_spec.Id.Ui.node_id
      ; kind : node_kind
      ; props : props
      ; event_bindings : event_binding list
      }
  | Update_props of
      { node_id : Bonsai_swiftui_spec.Id.Ui.node_id
      ; props : props
      }
  | Update_event_bindings of
      { node_id : Bonsai_swiftui_spec.Id.Ui.node_id
      ; event_bindings : event_binding list
      }
  | Set_children of
      { node_id : Bonsai_swiftui_spec.Id.Ui.node_id
      ; children : Bonsai_swiftui_spec.Id.Ui.node_id list
      }
  | Set_root of Bonsai_swiftui_spec.Id.Ui.node_id
  | Set_application_theme of
      { title : string option
      ; theme : theme
      }
  | Drop_node of Bonsai_swiftui_spec.Id.Ui.node_id
  | Host_request of
      { request_id : Bonsai_swiftui_spec.Id.Host.request_id
      ; payload : host_request_payload
      }
  | Cancel_host_request of { request_id : Bonsai_swiftui_spec.Id.Host.request_id }
  | Application_request of
      { request_id : int64
      ; payload : bytes
      }
  | Runtime_stats of runtime_stats

type t =
  { runtime_epoch : Bonsai_swiftui_spec.Id.Runtime.epoch
  ; base_revision : Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  ; target_revision : Bonsai_swiftui_spec.Id.Runtime.renderer_revision
  ; kind : frame_kind
  ; operations : operation list
  }
