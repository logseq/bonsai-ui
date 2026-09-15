(* Generated from [protocol/schema.sexp]. Do not edit. *)

module ID = Bonsai_swiftui_spec.Id

let protocol_major = 5
let protocol_minor = 0

module Limits = struct
  let header_bytes = 48
  let max_frame_bytes = 16777216
  let max_string_bytes = 1048576
  let max_application_payload_bytes = 1048576
  let max_operations = 1000000
  let max_nodes = 1000000
end

module Frame_kind = struct
  let handshake = ID.Protocol.Frame_kind.of_int 1
  let full_snapshot = ID.Protocol.Frame_kind.of_int 2
  let incremental_frame = ID.Protocol.Frame_kind.of_int 3
  let event_batch = ID.Protocol.Frame_kind.of_int 4
  let runtime_error = ID.Protocol.Frame_kind.of_int 5

  let debug_name id =
    match ID.Protocol.Frame_kind.to_int id with
    | 1 -> Some "handshake"
    | 2 -> Some "full_snapshot"
    | 3 -> Some "incremental_frame"
    | 4 -> Some "event_batch"
    | 5 -> Some "runtime_error"
    | _ -> None
  ;;
end

module Operation = struct
  let begin_frame = ID.Protocol.Operation.of_int 1
  let create_node = ID.Protocol.Operation.of_int 2
  let update_props = ID.Protocol.Operation.of_int 3
  let update_event_bindings = ID.Protocol.Operation.of_int 4
  let set_children = ID.Protocol.Operation.of_int 5
  let set_root = ID.Protocol.Operation.of_int 6
  let drop_node = ID.Protocol.Operation.of_int 7
  let host_request = ID.Protocol.Operation.of_int 8
  let runtime_notification = ID.Protocol.Operation.of_int 9
  let end_frame = ID.Protocol.Operation.of_int 10
  let application_request = ID.Protocol.Operation.of_int 11
  let set_application_theme = ID.Protocol.Operation.of_int 12

  let debug_name id =
    match ID.Protocol.Operation.to_int id with
    | 1 -> Some "begin_frame"
    | 2 -> Some "create_node"
    | 3 -> Some "update_props"
    | 4 -> Some "update_event_bindings"
    | 5 -> Some "set_children"
    | 6 -> Some "set_root"
    | 7 -> Some "drop_node"
    | 8 -> Some "host_request"
    | 9 -> Some "runtime_notification"
    | 10 -> Some "end_frame"
    | 11 -> Some "application_request"
    | 12 -> Some "set_application_theme"
    | _ -> None
  ;;
end

module Node_kind = struct
  let empty = ID.Protocol.Node_kind.of_int 1
  let text = ID.Protocol.Node_kind.of_int 2
  let rich_text = ID.Protocol.Node_kind.of_int 3
  let symbol = ID.Protocol.Node_kind.of_int 4
  let image = ID.Protocol.Node_kind.of_int 5
  let text_editor = ID.Protocol.Node_kind.of_int 6
  let text_field = ID.Protocol.Node_kind.of_int 47
  let secure_field = ID.Protocol.Node_kind.of_int 49
  let collection_catalog = ID.Protocol.Node_kind.of_int 7
  let collection_window = ID.Protocol.Node_kind.of_int 8
  let scroll = ID.Protocol.Node_kind.of_int 9
  let progress = ID.Protocol.Node_kind.of_int 10
  let ignores_safe_area = ID.Protocol.Node_kind.of_int 11
  let safe_area_padding = ID.Protocol.Node_kind.of_int 12
  let navigation_stack = ID.Protocol.Node_kind.of_int 13
  let navigation_destination = ID.Protocol.Node_kind.of_int 14
  let navigation_split = ID.Protocol.Node_kind.of_int 15
  let flow = ID.Protocol.Node_kind.of_int 56
  let label = ID.Protocol.Node_kind.of_int 57
  let badge = ID.Protocol.Node_kind.of_int 58
  let date_picker = ID.Protocol.Node_kind.of_int 59
  let time_picker = ID.Protocol.Node_kind.of_int 60
  let menu = ID.Protocol.Node_kind.of_int 61
  let removal = ID.Protocol.Node_kind.of_int 78
  let refresh = ID.Protocol.Node_kind.of_int 77
  let scroll_targets = ID.Protocol.Node_kind.of_int 62
  let help = ID.Protocol.Node_kind.of_int 63
  let popover = ID.Protocol.Node_kind.of_int 72
  let sheet = ID.Protocol.Node_kind.of_int 73
  let toolbar = ID.Protocol.Node_kind.of_int 74
  let scroll_sections = ID.Protocol.Node_kind.of_int 75
  let scroll_section = ID.Protocol.Node_kind.of_int 76
  let row = ID.Protocol.Node_kind.of_int 16
  let column = ID.Protocol.Node_kind.of_int 17
  let weighted_row = ID.Protocol.Node_kind.of_int 18
  let stack = ID.Protocol.Node_kind.of_int 19
  let weighted_column = ID.Protocol.Node_kind.of_int 20
  let padding = ID.Protocol.Node_kind.of_int 21
  let frame = ID.Protocol.Node_kind.of_int 22
  let spacer = ID.Protocol.Node_kind.of_int 23
  let layout_priority = ID.Protocol.Node_kind.of_int 24
  let offset = ID.Protocol.Node_kind.of_int 25
  let background = ID.Protocol.Node_kind.of_int 26
  let clip = ID.Protocol.Node_kind.of_int 27
  let opacity = ID.Protocol.Node_kind.of_int 28
  let projection_effect = ID.Protocol.Node_kind.of_int 29
  let tabs = ID.Protocol.Node_kind.of_int 31
  let tab = ID.Protocol.Node_kind.of_int 40
  let morphing_surface = ID.Protocol.Node_kind.of_int 41
  let swipe_actions = ID.Protocol.Node_kind.of_int 42
  let swipe_action = ID.Protocol.Node_kind.of_int 43
  let toggle = ID.Protocol.Node_kind.of_int 44
  let gesture = ID.Protocol.Node_kind.of_int 48
  let focus_scope = ID.Protocol.Node_kind.of_int 51
  let hover_region = ID.Protocol.Node_kind.of_int 52
  let keyboard_listener = ID.Protocol.Node_kind.of_int 53
  let button = ID.Protocol.Node_kind.of_int 54
  let control_size = ID.Protocol.Node_kind.of_int 55
  let semantics = ID.Protocol.Node_kind.of_int 64
  let overlay = ID.Protocol.Node_kind.of_int 65
  let theme = ID.Protocol.Node_kind.of_int 69
  let animated_opacity = ID.Protocol.Node_kind.of_int 71
  let divider = ID.Protocol.Node_kind.of_int 105
  let group_box = ID.Protocol.Node_kind.of_int 106
  let reserved_node_kind_107 = ID.Protocol.Node_kind.of_int 107
  let picker = ID.Protocol.Node_kind.of_int 116
  let slider = ID.Protocol.Node_kind.of_int 45
  let range_slider = ID.Protocol.Node_kind.of_int 46
  let native_widget = ID.Protocol.Node_kind.of_int 128
  let table = ID.Protocol.Node_kind.of_int 79
  let disclosure_group = ID.Protocol.Node_kind.of_int 133

  let debug_name id =
    match ID.Protocol.Node_kind.to_int id with
    | 1 -> Some "empty"
    | 2 -> Some "text"
    | 3 -> Some "rich_text"
    | 4 -> Some "symbol"
    | 5 -> Some "image"
    | 6 -> Some "text_editor"
    | 47 -> Some "text_field"
    | 49 -> Some "secure_field"
    | 7 -> Some "collection_catalog"
    | 8 -> Some "collection_window"
    | 9 -> Some "scroll"
    | 10 -> Some "progress"
    | 11 -> Some "ignores_safe_area"
    | 12 -> Some "safe_area_padding"
    | 13 -> Some "navigation_stack"
    | 14 -> Some "navigation_destination"
    | 15 -> Some "navigation_split"
    | 56 -> Some "flow"
    | 57 -> Some "label"
    | 58 -> Some "badge"
    | 59 -> Some "date_picker"
    | 60 -> Some "time_picker"
    | 61 -> Some "menu"
    | 78 -> Some "removal"
    | 77 -> Some "refresh"
    | 62 -> Some "scroll_targets"
    | 63 -> Some "help"
    | 72 -> Some "popover"
    | 73 -> Some "sheet"
    | 74 -> Some "toolbar"
    | 75 -> Some "scroll_sections"
    | 76 -> Some "scroll_section"
    | 16 -> Some "row"
    | 17 -> Some "column"
    | 18 -> Some "weighted_row"
    | 19 -> Some "stack"
    | 20 -> Some "weighted_column"
    | 21 -> Some "padding"
    | 22 -> Some "frame"
    | 23 -> Some "spacer"
    | 24 -> Some "layout_priority"
    | 25 -> Some "offset"
    | 26 -> Some "background"
    | 27 -> Some "clip"
    | 28 -> Some "opacity"
    | 29 -> Some "projection_effect"
    | 31 -> Some "tabs"
    | 40 -> Some "tab"
    | 41 -> Some "morphing_surface"
    | 42 -> Some "swipe_actions"
    | 43 -> Some "swipe_action"
    | 44 -> Some "toggle"
    | 48 -> Some "gesture"
    | 51 -> Some "focus_scope"
    | 52 -> Some "hover_region"
    | 53 -> Some "keyboard_listener"
    | 54 -> Some "button"
    | 55 -> Some "control_size"
    | 64 -> Some "semantics"
    | 65 -> Some "overlay"
    | 69 -> Some "theme"
    | 71 -> Some "animated_opacity"
    | 105 -> Some "divider"
    | 106 -> Some "group_box"
    | 107 -> Some "reserved_node_kind_107"
    | 116 -> Some "picker"
    | 45 -> Some "slider"
    | 46 -> Some "range_slider"
    | 128 -> Some "native_widget"
    | 79 -> Some "table"
    | 133 -> Some "disclosure_group"
    | _ -> None
  ;;
end

module Event_tag = struct
  let press = ID.Protocol.Event_tag.of_int 1
  let long_press = ID.Protocol.Event_tag.of_int 2
  let tap = ID.Protocol.Event_tag.of_int 3
  let double_tap = ID.Protocol.Event_tag.of_int 4
  let pointer_enter = ID.Protocol.Event_tag.of_int 5
  let pointer_leave = ID.Protocol.Event_tag.of_int 6
  let pointer_down = ID.Protocol.Event_tag.of_int 7
  let pointer_up = ID.Protocol.Event_tag.of_int 8
  let key = ID.Protocol.Event_tag.of_int 9
  let focus_changed = ID.Protocol.Event_tag.of_int 10
  let text_edit = ID.Protocol.Event_tag.of_int 11
  let text_submit = ID.Protocol.Event_tag.of_int 12
  let scroll_notification = ID.Protocol.Event_tag.of_int 13
  let visible_range_changed = ID.Protocol.Event_tag.of_int 14
  let animation_completed = ID.Protocol.Event_tag.of_int 15
  let layout_observed = ID.Protocol.Event_tag.of_int 17
  let value_changed = ID.Protocol.Event_tag.of_int 18
  let host_response = ID.Protocol.Event_tag.of_int 19
  let environment_changed = ID.Protocol.Event_tag.of_int 20
  let native_event = ID.Protocol.Event_tag.of_int 21
  let semantics_action = ID.Protocol.Event_tag.of_int 22
  let resync_requested = ID.Protocol.Event_tag.of_int 23
  let text_limit_reached = ID.Protocol.Event_tag.of_int 24
  let application_response = ID.Protocol.Event_tag.of_int 25
  let application_request_error = ID.Protocol.Event_tag.of_int 26
  let application_event = ID.Protocol.Event_tag.of_int 27
  let navigation_destination_selected = ID.Protocol.Event_tag.of_int 28
  let radio_selected = ID.Protocol.Event_tag.of_int 29
  let picker_selected = ID.Protocol.Event_tag.of_int 53
  let menu_action = ID.Protocol.Event_tag.of_int 54
  let scroll_position_changed = ID.Protocol.Event_tag.of_int 55
  let refresh_request = ID.Protocol.Event_tag.of_int 56
  let removal_requested = ID.Protocol.Event_tag.of_int 57
  let removal_completed = ID.Protocol.Event_tag.of_int 58
  let slider_changed = ID.Protocol.Event_tag.of_int 30
  let slider_change_end = ID.Protocol.Event_tag.of_int 31
  let range_slider_changed = ID.Protocol.Event_tag.of_int 32
  let range_slider_change_end = ID.Protocol.Event_tag.of_int 33
  let table_sort_requested = ID.Protocol.Event_tag.of_int 37
  let table_row_selected = ID.Protocol.Event_tag.of_int 38
  let civil_date_changed = ID.Protocol.Event_tag.of_int 46
  let civil_time_changed = ID.Protocol.Event_tag.of_int 47
  let navigation_path_changed = ID.Protocol.Event_tag.of_int 50
  let navigation_split_changed = ID.Protocol.Event_tag.of_int 51
  let tab_selected = ID.Protocol.Event_tag.of_int 52

  let debug_name id =
    match ID.Protocol.Event_tag.to_int id with
    | 1 -> Some "press"
    | 2 -> Some "long_press"
    | 3 -> Some "tap"
    | 4 -> Some "double_tap"
    | 5 -> Some "pointer_enter"
    | 6 -> Some "pointer_leave"
    | 7 -> Some "pointer_down"
    | 8 -> Some "pointer_up"
    | 9 -> Some "key"
    | 10 -> Some "focus_changed"
    | 11 -> Some "text_edit"
    | 12 -> Some "text_submit"
    | 13 -> Some "scroll_notification"
    | 14 -> Some "visible_range_changed"
    | 15 -> Some "animation_completed"
    | 17 -> Some "layout_observed"
    | 18 -> Some "value_changed"
    | 19 -> Some "host_response"
    | 20 -> Some "environment_changed"
    | 21 -> Some "native_event"
    | 22 -> Some "semantics_action"
    | 23 -> Some "resync_requested"
    | 24 -> Some "text_limit_reached"
    | 25 -> Some "application_response"
    | 26 -> Some "application_request_error"
    | 27 -> Some "application_event"
    | 28 -> Some "navigation_destination_selected"
    | 29 -> Some "radio_selected"
    | 53 -> Some "picker_selected"
    | 54 -> Some "menu_action"
    | 55 -> Some "scroll_position_changed"
    | 56 -> Some "refresh_request"
    | 57 -> Some "removal_requested"
    | 58 -> Some "removal_completed"
    | 30 -> Some "slider_changed"
    | 31 -> Some "slider_change_end"
    | 32 -> Some "range_slider_changed"
    | 33 -> Some "range_slider_change_end"
    | 37 -> Some "table_sort_requested"
    | 38 -> Some "table_row_selected"
    | 46 -> Some "civil_date_changed"
    | 47 -> Some "civil_time_changed"
    | 50 -> Some "navigation_path_changed"
    | 51 -> Some "navigation_split_changed"
    | 52 -> Some "tab_selected"
    | _ -> None
  ;;
end

module Host_request = struct
  let clipboard_read = ID.Protocol.Host_request_kind.of_int 1
  let clipboard_write = ID.Protocol.Host_request_kind.of_int 2
  let open_url = ID.Protocol.Host_request_kind.of_int 3
  let pick_files = ID.Protocol.Host_request_kind.of_int 4
  let save_file = ID.Protocol.Host_request_kind.of_int 5
  let request_focus = ID.Protocol.Host_request_kind.of_int 6
  let clear_focus = ID.Protocol.Host_request_kind.of_int 7
  let scroll_to = ID.Protocol.Host_request_kind.of_int 8
  let set_window_title = ID.Protocol.Host_request_kind.of_int 9
  let set_window_size = ID.Protocol.Host_request_kind.of_int 10
  let show_native_menu = ID.Protocol.Host_request_kind.of_int 11
  let haptic_feedback = ID.Protocol.Host_request_kind.of_int 12
  let platform_information = ID.Protocol.Host_request_kind.of_int 13
  let measure_layout = ID.Protocol.Host_request_kind.of_int 14
  let show_notice = ID.Protocol.Host_request_kind.of_int 15
  let pick_date = ID.Protocol.Host_request_kind.of_int 16
  let pick_date_range = ID.Protocol.Host_request_kind.of_int 17
  let pick_time = ID.Protocol.Host_request_kind.of_int 18

  let debug_name id =
    match ID.Protocol.Host_request_kind.to_int id with
    | 1 -> Some "clipboard_read"
    | 2 -> Some "clipboard_write"
    | 3 -> Some "open_url"
    | 4 -> Some "pick_files"
    | 5 -> Some "save_file"
    | 6 -> Some "request_focus"
    | 7 -> Some "clear_focus"
    | 8 -> Some "scroll_to"
    | 9 -> Some "set_window_title"
    | 10 -> Some "set_window_size"
    | 11 -> Some "show_native_menu"
    | 12 -> Some "haptic_feedback"
    | 13 -> Some "platform_information"
    | 14 -> Some "measure_layout"
    | 15 -> Some "show_notice"
    | 16 -> Some "pick_date"
    | 17 -> Some "pick_date_range"
    | 18 -> Some "pick_time"
    | _ -> None
  ;;
end

module Runtime_error = struct
  let protocol_error = ID.Protocol.Runtime_error.of_int 1
  let revision_mismatch = ID.Protocol.Runtime_error.of_int 2
  let duplicate_key = ID.Protocol.Runtime_error.of_int 3
  let unsupported_node_kind = ID.Protocol.Runtime_error.of_int 4
  let invalid_prop = ID.Protocol.Runtime_error.of_int 5
  let handler_missing = ID.Protocol.Runtime_error.of_int 6
  let stale_event = ID.Protocol.Runtime_error.of_int 7
  let host_effect_failure = ID.Protocol.Runtime_error.of_int 8
  let ocaml_exception = ID.Protocol.Runtime_error.of_int 9
  let swiftui_renderer_exception = ID.Protocol.Runtime_error.of_int 10
  let lifecycle_exception = ID.Protocol.Runtime_error.of_int 11
  let native_library_loading_error = ID.Protocol.Runtime_error.of_int 12

  let debug_name id =
    match ID.Protocol.Runtime_error.to_int id with
    | 1 -> Some "protocol_error"
    | 2 -> Some "revision_mismatch"
    | 3 -> Some "duplicate_key"
    | 4 -> Some "unsupported_node_kind"
    | 5 -> Some "invalid_prop"
    | 6 -> Some "handler_missing"
    | 7 -> Some "stale_event"
    | 8 -> Some "host_effect_failure"
    | 9 -> Some "ocaml_exception"
    | 10 -> Some "swiftui_renderer_exception"
    | 11 -> Some "lifecycle_exception"
    | 12 -> Some "native_library_loading_error"
    | _ -> None
  ;;
end

module Common_prop = struct
  let test_id = ID.Protocol.Property.of_int 1
  let semantics = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "test_id"
    | 2 -> Some "semantics"
    | _ -> None
  ;;
end

module Scroll_sections_prop = struct
  let vertical = ID.Protocol.Property.of_int 1
  let pin_headers = ID.Protocol.Property.of_int 2
  let pin_footers = ID.Protocol.Property.of_int 3
  let spacing = ID.Protocol.Property.of_int 4
  let shows_indicators = ID.Protocol.Property.of_int 5
  let initial_anchor = ID.Protocol.Property.of_int 6

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "vertical"
    | 2 -> Some "pin_headers"
    | 3 -> Some "pin_footers"
    | 4 -> Some "spacing"
    | 5 -> Some "shows_indicators"
    | 6 -> Some "initial_anchor"
    | _ -> None
  ;;
end

module Scroll_section_prop = struct
  let has_header = ID.Protocol.Property.of_int 1
  let has_footer = ID.Protocol.Property.of_int 2
  let hero_height = ID.Protocol.Property.of_int 3
  let stretch = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "has_header"
    | 2 -> Some "has_footer"
    | 3 -> Some "hero_height"
    | 4 -> Some "stretch"
    | _ -> None
  ;;
end

module Toolbar_prop = struct
  let placements = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "placements"
    | _ -> None
  ;;
end

module Sheet_prop = struct
  let presented = ID.Protocol.Property.of_int 1
  let fullscreen = ID.Protocol.Property.of_int 2
  let detents = ID.Protocol.Property.of_int 3
  let initial = ID.Protocol.Property.of_int 4
  let interactive = ID.Protocol.Property.of_int 5
  let indicator = ID.Protocol.Property.of_int 6
  let sizing = ID.Protocol.Property.of_int 7

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "presented"
    | 2 -> Some "fullscreen"
    | 3 -> Some "detents"
    | 4 -> Some "initial"
    | 5 -> Some "interactive"
    | 6 -> Some "indicator"
    | 7 -> Some "sizing"
    | _ -> None
  ;;
end

module Popover_prop = struct
  let presented = ID.Protocol.Property.of_int 1
  let edge = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "presented"
    | 2 -> Some "edge"
    | _ -> None
  ;;
end

module Help_prop = struct
  let message = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "message"
    | _ -> None
  ;;
end

module Toggle_prop = struct
  let value = ID.Protocol.Property.of_int 1
  let enabled = ID.Protocol.Property.of_int 2
  let style = ID.Protocol.Property.of_int 3

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "value"
    | 2 -> Some "enabled"
    | 3 -> Some "style"
    | _ -> None
  ;;
end

module Swipe_actions_prop = struct
  let enabled = ID.Protocol.Property.of_int 1
  let vertical = ID.Protocol.Property.of_int 2
  let close_on_scroll = ID.Protocol.Property.of_int 3
  let group = ID.Protocol.Property.of_int 4
  let close_when_opened = ID.Protocol.Property.of_int 5
  let close_when_tapped = ID.Protocol.Property.of_int 6

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "enabled"
    | 2 -> Some "vertical"
    | 3 -> Some "close_on_scroll"
    | 4 -> Some "group"
    | 5 -> Some "close_when_opened"
    | 6 -> Some "close_when_tapped"
    | _ -> None
  ;;
end

module Swipe_action_prop = struct
  let title = ID.Protocol.Property.of_int 1
  let side = ID.Protocol.Property.of_int 2
  let enabled = ID.Protocol.Property.of_int 3
  let role = ID.Protocol.Property.of_int 4
  let extent = ID.Protocol.Property.of_int 5
  let background = ID.Protocol.Property.of_int 6
  let auto_close = ID.Protocol.Property.of_int 7
  let full_swipe = ID.Protocol.Property.of_int 8

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "title"
    | 2 -> Some "side"
    | 3 -> Some "enabled"
    | 4 -> Some "role"
    | 5 -> Some "extent"
    | 6 -> Some "background"
    | 7 -> Some "auto_close"
    | 8 -> Some "full_swipe"
    | _ -> None
  ;;
end

module Morphing_surface_prop = struct
  let expanded = ID.Protocol.Property.of_int 1
  let expand_duration_ms = ID.Protocol.Property.of_int 2
  let collapse_duration_ms = ID.Protocol.Property.of_int 3

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "expanded"
    | 2 -> Some "expand_duration_ms"
    | 3 -> Some "collapse_duration_ms"
    | _ -> None
  ;;
end

module Tabs_prop = struct
  let selection = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "selection"
    | _ -> None
  ;;
end

module Tab_prop = struct
  let page_key = ID.Protocol.Property.of_int 1
  let title = ID.Protocol.Property.of_int 2
  let symbol = ID.Protocol.Property.of_int 3
  let badge = ID.Protocol.Property.of_int 4
  let accessibility_label = ID.Protocol.Property.of_int 5

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "page_key"
    | 2 -> Some "title"
    | 3 -> Some "symbol"
    | 4 -> Some "badge"
    | 5 -> Some "accessibility_label"
    | _ -> None
  ;;
end

module Navigation_split_prop = struct
  let visibility = ID.Protocol.Property.of_int 1
  let compact_column = ID.Protocol.Property.of_int 2
  let selection_key = ID.Protocol.Property.of_int 3
  let sidebar_title = ID.Protocol.Property.of_int 4
  let content_title = ID.Protocol.Property.of_int 5
  let detail_title = ID.Protocol.Property.of_int 6

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "visibility"
    | 2 -> Some "compact_column"
    | 3 -> Some "selection_key"
    | 4 -> Some "sidebar_title"
    | 5 -> Some "content_title"
    | 6 -> Some "detail_title"
    | _ -> None
  ;;
end

module Navigation_stack_prop = struct
  let title = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "title"
    | _ -> None
  ;;
end

module Navigation_destination_prop = struct
  let page_key = ID.Protocol.Property.of_int 1
  let title = ID.Protocol.Property.of_int 2
  let can_pop = ID.Protocol.Property.of_int 3

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "page_key"
    | 2 -> Some "title"
    | 3 -> Some "can_pop"
    | _ -> None
  ;;
end

module Text_prop = struct
  let value = ID.Protocol.Property.of_int 1
  let text_style = ID.Protocol.Property.of_int 2
  let text_align = ID.Protocol.Property.of_int 3
  let line_limit = ID.Protocol.Property.of_int 4
  let truncation = ID.Protocol.Property.of_int 5

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "value"
    | 2 -> Some "text_style"
    | 3 -> Some "text_align"
    | 4 -> Some "line_limit"
    | 5 -> Some "truncation"
    | _ -> None
  ;;
end

module Rich_text_prop = struct
  let spans = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "spans"
    | _ -> None
  ;;
end

module Symbol_prop = struct
  let name = ID.Protocol.Property.of_int 1
  let size = ID.Protocol.Property.of_int 2
  let color = ID.Protocol.Property.of_int 3
  let rendering = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "name"
    | 2 -> Some "size"
    | 3 -> Some "color"
    | 4 -> Some "rendering"
    | _ -> None
  ;;
end

module Scroll_prop = struct
  let vertical = ID.Protocol.Property.of_int 1
  let shows_indicators = ID.Protocol.Property.of_int 2
  let fill_viewport = ID.Protocol.Property.of_int 3
  let initial_anchor = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "vertical"
    | 2 -> Some "shows_indicators"
    | 3 -> Some "fill_viewport"
    | 4 -> Some "initial_anchor"
    | _ -> None
  ;;
end

module Collection_catalog_prop = struct
  let keys = ID.Protocol.Property.of_int 1
  let default_extent = ID.Protocol.Property.of_int 2
  let overrides = ID.Protocol.Property.of_int 3
  let overscan = ID.Protocol.Property.of_int 4
  let expand_duration_ms = ID.Protocol.Property.of_int 5
  let collapse_duration_ms = ID.Protocol.Property.of_int 6
  let vertical = ID.Protocol.Property.of_int 7
  let initial_anchor = ID.Protocol.Property.of_int 8
  let initial_key = ID.Protocol.Property.of_int 9
  let measurement_revision = ID.Protocol.Property.of_int 10

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "keys"
    | 2 -> Some "default_extent"
    | 3 -> Some "overrides"
    | 4 -> Some "overscan"
    | 5 -> Some "expand_duration_ms"
    | 6 -> Some "collapse_duration_ms"
    | 7 -> Some "vertical"
    | 8 -> Some "initial_anchor"
    | 9 -> Some "initial_key"
    | 10 -> Some "measurement_revision"
    | _ -> None
  ;;
end

module Collection_window_prop = struct
  let first_index = ID.Protocol.Property.of_int 1
  let keys = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "first_index"
    | 2 -> Some "keys"
    | _ -> None
  ;;
end

module Text_field_prop = struct
  let session_id = ID.Protocol.Property.of_int 1
  let document_revision = ID.Protocol.Property.of_int 2
  let accepted_local_revision = ID.Protocol.Property.of_int 3
  let update_mode = ID.Protocol.Property.of_int 4
  let value = ID.Protocol.Property.of_int 5
  let enabled = ID.Protocol.Property.of_int 6
  let read_only = ID.Protocol.Property.of_int 7
  let submit_on_return = ID.Protocol.Property.of_int 8
  let max_utf8_bytes = ID.Protocol.Property.of_int 9
  let label = ID.Protocol.Property.of_int 10
  let prompt = ID.Protocol.Property.of_int 11
  let keyboard = ID.Protocol.Property.of_int 12
  let submit_label = ID.Protocol.Property.of_int 13
  let autofocus = ID.Protocol.Property.of_int 14

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "session_id"
    | 2 -> Some "document_revision"
    | 3 -> Some "accepted_local_revision"
    | 4 -> Some "update_mode"
    | 5 -> Some "value"
    | 6 -> Some "enabled"
    | 7 -> Some "read_only"
    | 8 -> Some "submit_on_return"
    | 9 -> Some "max_utf8_bytes"
    | 10 -> Some "label"
    | 11 -> Some "prompt"
    | 12 -> Some "keyboard"
    | 13 -> Some "submit_label"
    | 14 -> Some "autofocus"
    | _ -> None
  ;;
end

module Secure_field_prop = struct
  let session_id = ID.Protocol.Property.of_int 1
  let document_revision = ID.Protocol.Property.of_int 2
  let accepted_local_revision = ID.Protocol.Property.of_int 3
  let update_mode = ID.Protocol.Property.of_int 4
  let value = ID.Protocol.Property.of_int 5
  let enabled = ID.Protocol.Property.of_int 6
  let read_only = ID.Protocol.Property.of_int 7
  let submit_on_return = ID.Protocol.Property.of_int 8
  let max_utf8_bytes = ID.Protocol.Property.of_int 9
  let label = ID.Protocol.Property.of_int 10
  let prompt = ID.Protocol.Property.of_int 11
  let keyboard = ID.Protocol.Property.of_int 12
  let submit_label = ID.Protocol.Property.of_int 13
  let autofocus = ID.Protocol.Property.of_int 14

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "session_id"
    | 2 -> Some "document_revision"
    | 3 -> Some "accepted_local_revision"
    | 4 -> Some "update_mode"
    | 5 -> Some "value"
    | 6 -> Some "enabled"
    | 7 -> Some "read_only"
    | 8 -> Some "submit_on_return"
    | 9 -> Some "max_utf8_bytes"
    | 10 -> Some "label"
    | 11 -> Some "prompt"
    | 12 -> Some "keyboard"
    | 13 -> Some "submit_label"
    | 14 -> Some "autofocus"
    | _ -> None
  ;;
end

module Text_editor_prop = struct
  let session_id = ID.Protocol.Property.of_int 1
  let document_revision = ID.Protocol.Property.of_int 2
  let accepted_local_revision = ID.Protocol.Property.of_int 3
  let update_mode = ID.Protocol.Property.of_int 4
  let value = ID.Protocol.Property.of_int 5
  let enabled = ID.Protocol.Property.of_int 6
  let read_only = ID.Protocol.Property.of_int 7
  let submit_on_return = ID.Protocol.Property.of_int 8
  let max_utf8_bytes = ID.Protocol.Property.of_int 9

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "session_id"
    | 2 -> Some "document_revision"
    | 3 -> Some "accepted_local_revision"
    | 4 -> Some "update_mode"
    | 5 -> Some "value"
    | 6 -> Some "enabled"
    | 7 -> Some "read_only"
    | 8 -> Some "submit_on_return"
    | 9 -> Some "max_utf8_bytes"
    | _ -> None
  ;;
end

module Image_prop = struct
  let source = ID.Protocol.Property.of_int 1
  let sizing = ID.Protocol.Property.of_int 2
  let scale = ID.Protocol.Property.of_int 3

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "source"
    | 2 -> Some "sizing"
    | 3 -> Some "scale"
    | _ -> None
  ;;
end

module Flow_prop = struct
  let spacing = ID.Protocol.Property.of_int 1
  let line_spacing = ID.Protocol.Property.of_int 2
  let alignment = ID.Protocol.Property.of_int 3

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "spacing"
    | 2 -> Some "line_spacing"
    | 3 -> Some "alignment"
    | _ -> None
  ;;
end

module Row_prop = struct
  let spacing = ID.Protocol.Property.of_int 1
  let alignment = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "spacing"
    | 2 -> Some "alignment"
    | _ -> None
  ;;
end

module Column_prop = struct
  let spacing = ID.Protocol.Property.of_int 1
  let alignment = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "spacing"
    | 2 -> Some "alignment"
    | _ -> None
  ;;
end

module Weighted_row_prop = struct
  let spacing = ID.Protocol.Property.of_int 1
  let alignment = ID.Protocol.Property.of_int 2
  let items = ID.Protocol.Property.of_int 3

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "spacing"
    | 2 -> Some "alignment"
    | 3 -> Some "items"
    | _ -> None
  ;;
end

module Weighted_column_prop = struct
  let spacing = ID.Protocol.Property.of_int 1
  let alignment = ID.Protocol.Property.of_int 2
  let items = ID.Protocol.Property.of_int 3

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "spacing"
    | 2 -> Some "alignment"
    | 3 -> Some "items"
    | _ -> None
  ;;
end

module Stack_prop = struct
  let alignment = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "alignment"
    | _ -> None
  ;;
end

module Layout_priority_prop = struct
  let priority = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "priority"
    | _ -> None
  ;;
end

module Offset_prop = struct
  let x = ID.Protocol.Property.of_int 1
  let y = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "x"
    | 2 -> Some "y"
    | _ -> None
  ;;
end

module Padding_prop = struct
  let insets = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "insets"
    | _ -> None
  ;;
end

module Spacer_prop = struct
  let min_length = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "min_length"
    | _ -> None
  ;;
end

module Frame_prop = struct
  let width = ID.Protocol.Property.of_int 1
  let height = ID.Protocol.Property.of_int 2
  let min_width = ID.Protocol.Property.of_int 3
  let ideal_width = ID.Protocol.Property.of_int 4
  let max_width = ID.Protocol.Property.of_int 5
  let min_height = ID.Protocol.Property.of_int 6
  let ideal_height = ID.Protocol.Property.of_int 7
  let max_height = ID.Protocol.Property.of_int 8
  let alignment = ID.Protocol.Property.of_int 9

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "width"
    | 2 -> Some "height"
    | 3 -> Some "min_width"
    | 4 -> Some "ideal_width"
    | 5 -> Some "max_width"
    | 6 -> Some "min_height"
    | 7 -> Some "ideal_height"
    | 8 -> Some "max_height"
    | 9 -> Some "alignment"
    | _ -> None
  ;;
end

module Background_prop = struct
  let color = ID.Protocol.Property.of_int 1
  let corner_radius = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "color"
    | 2 -> Some "corner_radius"
    | _ -> None
  ;;
end

module Clip_prop = struct
  let corner_radius = ID.Protocol.Property.of_int 1
  let antialiased = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "corner_radius"
    | 2 -> Some "antialiased"
    | _ -> None
  ;;
end

module Opacity_prop = struct
  let opacity = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "opacity"
    | _ -> None
  ;;
end

module Animated_opacity_prop = struct
  let opacity = ID.Protocol.Property.of_int 1
  let animation_id = ID.Protocol.Property.of_int 2
  let duration_ms = ID.Protocol.Property.of_int 3
  let curve = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "opacity"
    | 2 -> Some "animation_id"
    | 3 -> Some "duration_ms"
    | 4 -> Some "curve"
    | _ -> None
  ;;
end

module Projection_effect_prop = struct
  let matrix3 = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "matrix3"
    | _ -> None
  ;;
end

module Focus_scope_prop = struct
  let autofocus = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "autofocus"
    | _ -> None
  ;;
end

module Hover_region_prop = struct
  let blocks_behind = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "blocks_behind"
    | _ -> None
  ;;
end

module Keyboard_listener_prop = struct
  let autofocus = ID.Protocol.Property.of_int 1
  let key_policy = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "autofocus"
    | 2 -> Some "key_policy"
    | _ -> None
  ;;
end

module Semantics_prop = struct
  let label = ID.Protocol.Property.of_int 1
  let hint = ID.Protocol.Property.of_int 2
  let value = ID.Protocol.Property.of_int 3
  let role = ID.Protocol.Property.of_int 4
  let selected = ID.Protocol.Property.of_int 5
  let children = ID.Protocol.Property.of_int 6
  let hidden = ID.Protocol.Property.of_int 7
  let live_region = ID.Protocol.Property.of_int 8
  let heading_level = ID.Protocol.Property.of_int 9
  let sort_priority = ID.Protocol.Property.of_int 10
  let identifier = ID.Protocol.Property.of_int 11
  let actions = ID.Protocol.Property.of_int 12

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "label"
    | 2 -> Some "hint"
    | 3 -> Some "value"
    | 4 -> Some "role"
    | 5 -> Some "selected"
    | 6 -> Some "children"
    | 7 -> Some "hidden"
    | 8 -> Some "live_region"
    | 9 -> Some "heading_level"
    | 10 -> Some "sort_priority"
    | 11 -> Some "identifier"
    | 12 -> Some "actions"
    | _ -> None
  ;;
end

module Theme_prop = struct
  let data = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "data"
    | _ -> None
  ;;
end

module Removal_prop = struct
  let request_token = ID.Protocol.Property.of_int 1
  let request_state = ID.Protocol.Property.of_int 2
  let vertical = ID.Protocol.Property.of_int 3
  let collapse_vertical = ID.Protocol.Property.of_int 4
  let title = ID.Protocol.Property.of_int 5
  let duration_ms = ID.Protocol.Property.of_int 6

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "request_token"
    | 2 -> Some "request_state"
    | 3 -> Some "vertical"
    | 4 -> Some "collapse_vertical"
    | 5 -> Some "title"
    | 6 -> Some "duration_ms"
    | _ -> None
  ;;
end

module Refresh_prop = struct
  let request_token = ID.Protocol.Property.of_int 1
  let request_state = ID.Protocol.Property.of_int 2
  let show_token = ID.Protocol.Property.of_int 3

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "request_token"
    | 2 -> Some "request_state"
    | 3 -> Some "show_token"
    | _ -> None
  ;;
end

module Scroll_targets_prop = struct
  let vertical = ID.Protocol.Property.of_int 1
  let ids = ID.Protocol.Property.of_int 2
  let position = ID.Protocol.Property.of_int 3
  let fraction = ID.Protocol.Property.of_int 4
  let spacing = ID.Protocol.Property.of_int 5
  let alignment = ID.Protocol.Property.of_int 6
  let snapping = ID.Protocol.Property.of_int 7
  let enabled = ID.Protocol.Property.of_int 8
  let shows_indicators = ID.Protocol.Property.of_int 9

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "vertical"
    | 2 -> Some "ids"
    | 3 -> Some "position"
    | 4 -> Some "fraction"
    | 5 -> Some "spacing"
    | 6 -> Some "alignment"
    | 7 -> Some "snapping"
    | 8 -> Some "enabled"
    | 9 -> Some "shows_indicators"
    | _ -> None
  ;;
end

module Menu_prop = struct
  let items = ID.Protocol.Property.of_int 1
  let enabled = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "items"
    | 2 -> Some "enabled"
    | _ -> None
  ;;
end

module Picker_prop = struct
  let selected_id = ID.Protocol.Property.of_int 1
  let options = ID.Protocol.Property.of_int 2
  let label = ID.Protocol.Property.of_int 3
  let style = ID.Protocol.Property.of_int 4
  let enabled = ID.Protocol.Property.of_int 5

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "selected_id"
    | 2 -> Some "options"
    | 3 -> Some "label"
    | 4 -> Some "style"
    | 5 -> Some "enabled"
    | _ -> None
  ;;
end

module Slider_prop = struct
  let value = ID.Protocol.Property.of_int 1
  let min = ID.Protocol.Property.of_int 2
  let max = ID.Protocol.Property.of_int 3
  let step = ID.Protocol.Property.of_int 4
  let enabled = ID.Protocol.Property.of_int 5
  let vertical = ID.Protocol.Property.of_int 6
  let has_on_change = ID.Protocol.Property.of_int 7
  let label = ID.Protocol.Property.of_int 8

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "value"
    | 2 -> Some "min"
    | 3 -> Some "max"
    | 4 -> Some "step"
    | 5 -> Some "enabled"
    | 6 -> Some "vertical"
    | 7 -> Some "has_on_change"
    | 8 -> Some "label"
    | _ -> None
  ;;
end

module Range_slider_prop = struct
  let start = ID.Protocol.Property.of_int 1
  let end_value = ID.Protocol.Property.of_int 2
  let min = ID.Protocol.Property.of_int 3
  let max = ID.Protocol.Property.of_int 4
  let step = ID.Protocol.Property.of_int 5
  let enabled = ID.Protocol.Property.of_int 6
  let vertical = ID.Protocol.Property.of_int 7
  let has_on_change = ID.Protocol.Property.of_int 8
  let label_start = ID.Protocol.Property.of_int 9
  let label_end = ID.Protocol.Property.of_int 10

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "start"
    | 2 -> Some "end_value"
    | 3 -> Some "min"
    | 4 -> Some "max"
    | 5 -> Some "step"
    | 6 -> Some "enabled"
    | 7 -> Some "vertical"
    | 8 -> Some "has_on_change"
    | 9 -> Some "label_start"
    | 10 -> Some "label_end"
    | _ -> None
  ;;
end

module Divider_prop = struct
  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | _ -> None
  ;;
end

module Label_prop = struct
  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | _ -> None
  ;;
end

module Date_picker_prop = struct
  let selected = ID.Protocol.Property.of_int 1
  let first = ID.Protocol.Property.of_int 2
  let last = ID.Protocol.Property.of_int 3
  let selectable_dates = ID.Protocol.Property.of_int 4
  let label = ID.Protocol.Property.of_int 5
  let enabled = ID.Protocol.Property.of_int 6

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "selected"
    | 2 -> Some "first"
    | 3 -> Some "last"
    | 4 -> Some "selectable_dates"
    | 5 -> Some "label"
    | 6 -> Some "enabled"
    | _ -> None
  ;;
end

module Time_picker_prop = struct
  let value = ID.Protocol.Property.of_int 1
  let format = ID.Protocol.Property.of_int 2
  let label = ID.Protocol.Property.of_int 3
  let enabled = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "value"
    | 2 -> Some "format"
    | 3 -> Some "label"
    | 4 -> Some "enabled"
    | _ -> None
  ;;
end

module Badge_prop = struct
  let count = ID.Protocol.Property.of_int 1
  let alignment = ID.Protocol.Property.of_int 2
  let visible = ID.Protocol.Property.of_int 3

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "count"
    | 2 -> Some "alignment"
    | 3 -> Some "visible"
    | _ -> None
  ;;
end

module Group_box_prop = struct
  let has_label = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "has_label"
    | _ -> None
  ;;
end

module Progress_prop = struct
  let value = ID.Protocol.Property.of_int 1
  let circular = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "value"
    | 2 -> Some "circular"
    | _ -> None
  ;;
end

module Table_prop = struct
  let columns = ID.Protocol.Property.of_int 1
  let rows = ID.Protocol.Property.of_int 2
  let sort_column_id = ID.Protocol.Property.of_int 3
  let sort_ascending = ID.Protocol.Property.of_int 4
  let selected_row_ids = ID.Protocol.Property.of_int 5
  let has_on_sort = ID.Protocol.Property.of_int 6
  let has_on_row_selected = ID.Protocol.Property.of_int 7

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "columns"
    | 2 -> Some "rows"
    | 3 -> Some "sort_column_id"
    | 4 -> Some "sort_ascending"
    | 5 -> Some "selected_row_ids"
    | 6 -> Some "has_on_sort"
    | 7 -> Some "has_on_row_selected"
    | _ -> None
  ;;
end

module Disclosure_group_prop = struct
  let expanded = ID.Protocol.Property.of_int 1
  let enabled = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "expanded"
    | 2 -> Some "enabled"
    | _ -> None
  ;;
end

module Overlay_prop = struct
  let alignment = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "alignment"
    | _ -> None
  ;;
end

module Ignores_safe_area_prop = struct
  let regions = ID.Protocol.Property.of_int 1
  let edges = ID.Protocol.Property.of_int 2

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "regions"
    | 2 -> Some "edges"
    | _ -> None
  ;;
end

module Safe_area_padding_prop = struct
  let insets = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "insets"
    | _ -> None
  ;;
end

module Control_size_prop = struct
  let size = ID.Protocol.Property.of_int 1

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "size"
    | _ -> None
  ;;
end

module Button_prop = struct
  let enabled = ID.Protocol.Property.of_int 1
  let role = ID.Protocol.Property.of_int 2
  let style = ID.Protocol.Property.of_int 3
  let autofocus = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "enabled"
    | 2 -> Some "role"
    | 3 -> Some "style"
    | 4 -> Some "autofocus"
    | _ -> None
  ;;
end

module Native_widget_prop = struct
  let kind_id = ID.Protocol.Property.of_int 1
  let version = ID.Protocol.Property.of_int 2
  let capabilities = ID.Protocol.Property.of_int 3
  let payload = ID.Protocol.Property.of_int 4

  let debug_name id =
    match ID.Protocol.Property.to_int id with
    | 1 -> Some "kind_id"
    | 2 -> Some "version"
    | 3 -> Some "capabilities"
    | 4 -> Some "payload"
    | _ -> None
  ;;
end
