(** Generated from [protocol/schema.sexp]. Do not edit. *)

val protocol_major : int
val protocol_minor : int

module Limits : sig
  val header_bytes : int
  val max_frame_bytes : int
  val max_string_bytes : int
  val max_application_payload_bytes : int
  val max_operations : int
  val max_nodes : int
end

module Frame_kind : sig
  val handshake : Bonsai_swiftui_spec.Id.Protocol.frame_kind
  val full_snapshot : Bonsai_swiftui_spec.Id.Protocol.frame_kind
  val incremental_frame : Bonsai_swiftui_spec.Id.Protocol.frame_kind
  val event_batch : Bonsai_swiftui_spec.Id.Protocol.frame_kind
  val runtime_error : Bonsai_swiftui_spec.Id.Protocol.frame_kind
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.frame_kind -> string option
end

module Operation : sig
  val begin_frame : Bonsai_swiftui_spec.Id.Protocol.operation
  val create_node : Bonsai_swiftui_spec.Id.Protocol.operation
  val update_props : Bonsai_swiftui_spec.Id.Protocol.operation
  val update_event_bindings : Bonsai_swiftui_spec.Id.Protocol.operation
  val set_children : Bonsai_swiftui_spec.Id.Protocol.operation
  val set_root : Bonsai_swiftui_spec.Id.Protocol.operation
  val drop_node : Bonsai_swiftui_spec.Id.Protocol.operation
  val host_request : Bonsai_swiftui_spec.Id.Protocol.operation
  val runtime_notification : Bonsai_swiftui_spec.Id.Protocol.operation
  val end_frame : Bonsai_swiftui_spec.Id.Protocol.operation
  val application_request : Bonsai_swiftui_spec.Id.Protocol.operation
  val set_application_theme : Bonsai_swiftui_spec.Id.Protocol.operation
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.operation -> string option
end

module Node_kind : sig
  val empty : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val text : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val rich_text : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val symbol : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val image : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val text_editor : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val text_field : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val secure_field : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val collection_catalog : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val collection_window : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val scroll : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val progress : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val ignores_safe_area : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val safe_area_padding : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val navigation_stack : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val navigation_destination : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val navigation_split : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val flow : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val label : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val badge : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val date_picker : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val time_picker : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val menu : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val removal : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val refresh : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val native_list : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val list_section : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val list_row : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val scroll_targets : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val help : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val popover : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val sheet : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val toolbar : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val scroll_sections : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val scroll_section : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val row : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val column : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val weighted_row : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val stack : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val weighted_column : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val padding : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val frame : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val spacer : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val layout_priority : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val offset : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val background : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val clip : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val opacity : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val projection_effect : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val tabs : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val tab : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val morphing_surface : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val swipe_actions : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val swipe_action : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val toggle : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val gesture : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val focus_scope : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val hover_region : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val keyboard_listener : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val button : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val control_size : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val semantics : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val overlay : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val theme : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val animated_opacity : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val divider : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val group_box : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val reserved_node_kind_107 : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val picker : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val slider : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val range_slider : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val native_widget : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val table : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val disclosure_group : Bonsai_swiftui_spec.Id.Protocol.node_kind
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.node_kind -> string option
end

module Event_tag : sig
  val press : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val long_press : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val tap : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val double_tap : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val pointer_enter : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val pointer_leave : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val pointer_down : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val pointer_up : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val key : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val focus_changed : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val text_edit : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val text_submit : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val scroll_notification : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val visible_range_changed : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val animation_completed : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val layout_observed : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val value_changed : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val host_response : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val environment_changed : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val native_event : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val semantics_action : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val resync_requested : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val text_limit_reached : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val application_response : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val application_request_error : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val application_event : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val navigation_destination_selected : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val radio_selected : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val picker_selected : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val menu_action : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val scroll_position_changed : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val refresh_request : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val removal_requested : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val removal_completed : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val slider_changed : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val slider_change_end : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val range_slider_changed : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val range_slider_change_end : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val table_sort_requested : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val table_row_selected : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val civil_date_changed : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val civil_time_changed : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val navigation_path_changed : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val navigation_split_changed : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val tab_selected : Bonsai_swiftui_spec.Id.Protocol.event_tag
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.event_tag -> string option
end

module Host_request : sig
  val clipboard_read : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val clipboard_write : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val open_url : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val pick_files : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val save_file : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val request_focus : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val clear_focus : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val scroll_to : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val set_window_title : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val set_window_size : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val show_native_menu : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val haptic_feedback : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val platform_information : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val measure_layout : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val show_notice : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val pick_date : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val pick_date_range : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val pick_time : Bonsai_swiftui_spec.Id.Protocol.host_request_kind
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.host_request_kind -> string option
end

module Runtime_error : sig
  val protocol_error : Bonsai_swiftui_spec.Id.Protocol.runtime_error
  val revision_mismatch : Bonsai_swiftui_spec.Id.Protocol.runtime_error
  val duplicate_key : Bonsai_swiftui_spec.Id.Protocol.runtime_error
  val unsupported_node_kind : Bonsai_swiftui_spec.Id.Protocol.runtime_error
  val invalid_prop : Bonsai_swiftui_spec.Id.Protocol.runtime_error
  val handler_missing : Bonsai_swiftui_spec.Id.Protocol.runtime_error
  val stale_event : Bonsai_swiftui_spec.Id.Protocol.runtime_error
  val host_effect_failure : Bonsai_swiftui_spec.Id.Protocol.runtime_error
  val ocaml_exception : Bonsai_swiftui_spec.Id.Protocol.runtime_error
  val swiftui_renderer_exception : Bonsai_swiftui_spec.Id.Protocol.runtime_error
  val lifecycle_exception : Bonsai_swiftui_spec.Id.Protocol.runtime_error
  val native_library_loading_error : Bonsai_swiftui_spec.Id.Protocol.runtime_error
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.runtime_error -> string option
end

module Common_prop : sig
  val test_id : Bonsai_swiftui_spec.Id.Protocol.property
  val semantics : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Native_list_prop : sig
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module List_section_prop : sig
  val has_header : Bonsai_swiftui_spec.Id.Protocol.property
  val has_footer : Bonsai_swiftui_spec.Id.Protocol.property
  val separator : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module List_row_prop : sig
  val separator : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Scroll_sections_prop : sig
  val vertical : Bonsai_swiftui_spec.Id.Protocol.property
  val pin_headers : Bonsai_swiftui_spec.Id.Protocol.property
  val pin_footers : Bonsai_swiftui_spec.Id.Protocol.property
  val spacing : Bonsai_swiftui_spec.Id.Protocol.property
  val shows_indicators : Bonsai_swiftui_spec.Id.Protocol.property
  val initial_anchor : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Scroll_section_prop : sig
  val has_header : Bonsai_swiftui_spec.Id.Protocol.property
  val has_footer : Bonsai_swiftui_spec.Id.Protocol.property
  val hero_height : Bonsai_swiftui_spec.Id.Protocol.property
  val stretch : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Toolbar_prop : sig
  val placements : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Sheet_prop : sig
  val presented : Bonsai_swiftui_spec.Id.Protocol.property
  val fullscreen : Bonsai_swiftui_spec.Id.Protocol.property
  val detents : Bonsai_swiftui_spec.Id.Protocol.property
  val initial : Bonsai_swiftui_spec.Id.Protocol.property
  val interactive : Bonsai_swiftui_spec.Id.Protocol.property
  val indicator : Bonsai_swiftui_spec.Id.Protocol.property
  val sizing : Bonsai_swiftui_spec.Id.Protocol.property
  val fraction : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Popover_prop : sig
  val presented : Bonsai_swiftui_spec.Id.Protocol.property
  val edge : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Help_prop : sig
  val message : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Toggle_prop : sig
  val value : Bonsai_swiftui_spec.Id.Protocol.property
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val style : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Swipe_actions_prop : sig
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val allows_full_swipe : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Swipe_action_prop : sig
  val title : Bonsai_swiftui_spec.Id.Protocol.property
  val side : Bonsai_swiftui_spec.Id.Protocol.property
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val role : Bonsai_swiftui_spec.Id.Protocol.property
  val background : Bonsai_swiftui_spec.Id.Protocol.property
  val symbol : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Morphing_surface_prop : sig
  val expanded : Bonsai_swiftui_spec.Id.Protocol.property
  val expand_duration_ms : Bonsai_swiftui_spec.Id.Protocol.property
  val collapse_duration_ms : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Tabs_prop : sig
  val selection : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Tab_prop : sig
  val page_key : Bonsai_swiftui_spec.Id.Protocol.property
  val title : Bonsai_swiftui_spec.Id.Protocol.property
  val symbol : Bonsai_swiftui_spec.Id.Protocol.property
  val badge : Bonsai_swiftui_spec.Id.Protocol.property
  val accessibility_label : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Navigation_split_prop : sig
  val visibility : Bonsai_swiftui_spec.Id.Protocol.property
  val compact_column : Bonsai_swiftui_spec.Id.Protocol.property
  val selection_key : Bonsai_swiftui_spec.Id.Protocol.property
  val sidebar_title : Bonsai_swiftui_spec.Id.Protocol.property
  val content_title : Bonsai_swiftui_spec.Id.Protocol.property
  val detail_title : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Navigation_stack_prop : sig
  val title : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Navigation_destination_prop : sig
  val page_key : Bonsai_swiftui_spec.Id.Protocol.property
  val title : Bonsai_swiftui_spec.Id.Protocol.property
  val can_pop : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Text_prop : sig
  val value : Bonsai_swiftui_spec.Id.Protocol.property
  val text_style : Bonsai_swiftui_spec.Id.Protocol.property
  val text_align : Bonsai_swiftui_spec.Id.Protocol.property
  val line_limit : Bonsai_swiftui_spec.Id.Protocol.property
  val truncation : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Rich_text_prop : sig
  val spans : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Symbol_prop : sig
  val name : Bonsai_swiftui_spec.Id.Protocol.property
  val size : Bonsai_swiftui_spec.Id.Protocol.property
  val color : Bonsai_swiftui_spec.Id.Protocol.property
  val rendering : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Scroll_prop : sig
  val vertical : Bonsai_swiftui_spec.Id.Protocol.property
  val shows_indicators : Bonsai_swiftui_spec.Id.Protocol.property
  val fill_viewport : Bonsai_swiftui_spec.Id.Protocol.property
  val initial_anchor : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Collection_catalog_prop : sig
  val keys : Bonsai_swiftui_spec.Id.Protocol.property
  val default_extent : Bonsai_swiftui_spec.Id.Protocol.property
  val overrides : Bonsai_swiftui_spec.Id.Protocol.property
  val overscan : Bonsai_swiftui_spec.Id.Protocol.property
  val expand_duration_ms : Bonsai_swiftui_spec.Id.Protocol.property
  val collapse_duration_ms : Bonsai_swiftui_spec.Id.Protocol.property
  val vertical : Bonsai_swiftui_spec.Id.Protocol.property
  val initial_anchor : Bonsai_swiftui_spec.Id.Protocol.property
  val initial_key : Bonsai_swiftui_spec.Id.Protocol.property
  val measurement_revision : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Collection_window_prop : sig
  val first_index : Bonsai_swiftui_spec.Id.Protocol.property
  val keys : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Text_field_prop : sig
  val session_id : Bonsai_swiftui_spec.Id.Protocol.property
  val document_revision : Bonsai_swiftui_spec.Id.Protocol.property
  val accepted_local_revision : Bonsai_swiftui_spec.Id.Protocol.property
  val update_mode : Bonsai_swiftui_spec.Id.Protocol.property
  val value : Bonsai_swiftui_spec.Id.Protocol.property
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val read_only : Bonsai_swiftui_spec.Id.Protocol.property
  val submit_on_return : Bonsai_swiftui_spec.Id.Protocol.property
  val max_utf8_bytes : Bonsai_swiftui_spec.Id.Protocol.property
  val label : Bonsai_swiftui_spec.Id.Protocol.property
  val prompt : Bonsai_swiftui_spec.Id.Protocol.property
  val keyboard : Bonsai_swiftui_spec.Id.Protocol.property
  val submit_label : Bonsai_swiftui_spec.Id.Protocol.property
  val autofocus : Bonsai_swiftui_spec.Id.Protocol.property
  val appearance : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Secure_field_prop : sig
  val session_id : Bonsai_swiftui_spec.Id.Protocol.property
  val document_revision : Bonsai_swiftui_spec.Id.Protocol.property
  val accepted_local_revision : Bonsai_swiftui_spec.Id.Protocol.property
  val update_mode : Bonsai_swiftui_spec.Id.Protocol.property
  val value : Bonsai_swiftui_spec.Id.Protocol.property
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val read_only : Bonsai_swiftui_spec.Id.Protocol.property
  val submit_on_return : Bonsai_swiftui_spec.Id.Protocol.property
  val max_utf8_bytes : Bonsai_swiftui_spec.Id.Protocol.property
  val label : Bonsai_swiftui_spec.Id.Protocol.property
  val prompt : Bonsai_swiftui_spec.Id.Protocol.property
  val keyboard : Bonsai_swiftui_spec.Id.Protocol.property
  val submit_label : Bonsai_swiftui_spec.Id.Protocol.property
  val autofocus : Bonsai_swiftui_spec.Id.Protocol.property
  val appearance : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Text_editor_prop : sig
  val session_id : Bonsai_swiftui_spec.Id.Protocol.property
  val document_revision : Bonsai_swiftui_spec.Id.Protocol.property
  val accepted_local_revision : Bonsai_swiftui_spec.Id.Protocol.property
  val update_mode : Bonsai_swiftui_spec.Id.Protocol.property
  val value : Bonsai_swiftui_spec.Id.Protocol.property
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val read_only : Bonsai_swiftui_spec.Id.Protocol.property
  val submit_on_return : Bonsai_swiftui_spec.Id.Protocol.property
  val max_utf8_bytes : Bonsai_swiftui_spec.Id.Protocol.property
  val autofocus : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Image_prop : sig
  val source : Bonsai_swiftui_spec.Id.Protocol.property
  val sizing : Bonsai_swiftui_spec.Id.Protocol.property
  val scale : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Flow_prop : sig
  val spacing : Bonsai_swiftui_spec.Id.Protocol.property
  val line_spacing : Bonsai_swiftui_spec.Id.Protocol.property
  val alignment : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Row_prop : sig
  val spacing : Bonsai_swiftui_spec.Id.Protocol.property
  val alignment : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Column_prop : sig
  val spacing : Bonsai_swiftui_spec.Id.Protocol.property
  val alignment : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Weighted_row_prop : sig
  val spacing : Bonsai_swiftui_spec.Id.Protocol.property
  val alignment : Bonsai_swiftui_spec.Id.Protocol.property
  val items : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Weighted_column_prop : sig
  val spacing : Bonsai_swiftui_spec.Id.Protocol.property
  val alignment : Bonsai_swiftui_spec.Id.Protocol.property
  val items : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Stack_prop : sig
  val alignment : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Layout_priority_prop : sig
  val priority : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Offset_prop : sig
  val x : Bonsai_swiftui_spec.Id.Protocol.property
  val y : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Padding_prop : sig
  val insets : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Spacer_prop : sig
  val min_length : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Frame_prop : sig
  val width : Bonsai_swiftui_spec.Id.Protocol.property
  val height : Bonsai_swiftui_spec.Id.Protocol.property
  val min_width : Bonsai_swiftui_spec.Id.Protocol.property
  val ideal_width : Bonsai_swiftui_spec.Id.Protocol.property
  val max_width : Bonsai_swiftui_spec.Id.Protocol.property
  val min_height : Bonsai_swiftui_spec.Id.Protocol.property
  val ideal_height : Bonsai_swiftui_spec.Id.Protocol.property
  val max_height : Bonsai_swiftui_spec.Id.Protocol.property
  val alignment : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Background_prop : sig
  val color : Bonsai_swiftui_spec.Id.Protocol.property
  val corner_radius : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Clip_prop : sig
  val corner_radius : Bonsai_swiftui_spec.Id.Protocol.property
  val antialiased : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Opacity_prop : sig
  val opacity : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Animated_opacity_prop : sig
  val opacity : Bonsai_swiftui_spec.Id.Protocol.property
  val animation_id : Bonsai_swiftui_spec.Id.Protocol.property
  val duration_ms : Bonsai_swiftui_spec.Id.Protocol.property
  val curve : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Projection_effect_prop : sig
  val matrix3 : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Focus_scope_prop : sig
  val autofocus : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Hover_region_prop : sig
  val blocks_behind : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Keyboard_listener_prop : sig
  val autofocus : Bonsai_swiftui_spec.Id.Protocol.property
  val key_policy : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Semantics_prop : sig
  val label : Bonsai_swiftui_spec.Id.Protocol.property
  val hint : Bonsai_swiftui_spec.Id.Protocol.property
  val value : Bonsai_swiftui_spec.Id.Protocol.property
  val role : Bonsai_swiftui_spec.Id.Protocol.property
  val selected : Bonsai_swiftui_spec.Id.Protocol.property
  val children : Bonsai_swiftui_spec.Id.Protocol.property
  val hidden : Bonsai_swiftui_spec.Id.Protocol.property
  val live_region : Bonsai_swiftui_spec.Id.Protocol.property
  val heading_level : Bonsai_swiftui_spec.Id.Protocol.property
  val sort_priority : Bonsai_swiftui_spec.Id.Protocol.property
  val identifier : Bonsai_swiftui_spec.Id.Protocol.property
  val actions : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Theme_prop : sig
  val data : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Removal_prop : sig
  val request_token : Bonsai_swiftui_spec.Id.Protocol.property
  val request_state : Bonsai_swiftui_spec.Id.Protocol.property
  val vertical : Bonsai_swiftui_spec.Id.Protocol.property
  val collapse_vertical : Bonsai_swiftui_spec.Id.Protocol.property
  val title : Bonsai_swiftui_spec.Id.Protocol.property
  val duration_ms : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Refresh_prop : sig
  val request_token : Bonsai_swiftui_spec.Id.Protocol.property
  val request_state : Bonsai_swiftui_spec.Id.Protocol.property
  val show_token : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Scroll_targets_prop : sig
  val vertical : Bonsai_swiftui_spec.Id.Protocol.property
  val ids : Bonsai_swiftui_spec.Id.Protocol.property
  val position : Bonsai_swiftui_spec.Id.Protocol.property
  val fraction : Bonsai_swiftui_spec.Id.Protocol.property
  val spacing : Bonsai_swiftui_spec.Id.Protocol.property
  val alignment : Bonsai_swiftui_spec.Id.Protocol.property
  val snapping : Bonsai_swiftui_spec.Id.Protocol.property
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val shows_indicators : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Menu_prop : sig
  val items : Bonsai_swiftui_spec.Id.Protocol.property
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Picker_prop : sig
  val selected_id : Bonsai_swiftui_spec.Id.Protocol.property
  val options : Bonsai_swiftui_spec.Id.Protocol.property
  val label : Bonsai_swiftui_spec.Id.Protocol.property
  val style : Bonsai_swiftui_spec.Id.Protocol.property
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Slider_prop : sig
  val value : Bonsai_swiftui_spec.Id.Protocol.property
  val min : Bonsai_swiftui_spec.Id.Protocol.property
  val max : Bonsai_swiftui_spec.Id.Protocol.property
  val step : Bonsai_swiftui_spec.Id.Protocol.property
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val vertical : Bonsai_swiftui_spec.Id.Protocol.property
  val has_on_change : Bonsai_swiftui_spec.Id.Protocol.property
  val label : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Range_slider_prop : sig
  val start : Bonsai_swiftui_spec.Id.Protocol.property
  val end_value : Bonsai_swiftui_spec.Id.Protocol.property
  val min : Bonsai_swiftui_spec.Id.Protocol.property
  val max : Bonsai_swiftui_spec.Id.Protocol.property
  val step : Bonsai_swiftui_spec.Id.Protocol.property
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val vertical : Bonsai_swiftui_spec.Id.Protocol.property
  val has_on_change : Bonsai_swiftui_spec.Id.Protocol.property
  val label_start : Bonsai_swiftui_spec.Id.Protocol.property
  val label_end : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Divider_prop : sig
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Label_prop : sig
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Date_picker_prop : sig
  val selected : Bonsai_swiftui_spec.Id.Protocol.property
  val first : Bonsai_swiftui_spec.Id.Protocol.property
  val last : Bonsai_swiftui_spec.Id.Protocol.property
  val label : Bonsai_swiftui_spec.Id.Protocol.property
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Time_picker_prop : sig
  val value : Bonsai_swiftui_spec.Id.Protocol.property
  val format : Bonsai_swiftui_spec.Id.Protocol.property
  val label : Bonsai_swiftui_spec.Id.Protocol.property
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Badge_prop : sig
  val count : Bonsai_swiftui_spec.Id.Protocol.property
  val alignment : Bonsai_swiftui_spec.Id.Protocol.property
  val visible : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Group_box_prop : sig
  val has_label : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Progress_prop : sig
  val value : Bonsai_swiftui_spec.Id.Protocol.property
  val style : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Table_prop : sig
  val columns : Bonsai_swiftui_spec.Id.Protocol.property
  val rows : Bonsai_swiftui_spec.Id.Protocol.property
  val sort_column_id : Bonsai_swiftui_spec.Id.Protocol.property
  val sort_ascending : Bonsai_swiftui_spec.Id.Protocol.property
  val selected_row_ids : Bonsai_swiftui_spec.Id.Protocol.property
  val has_on_sort : Bonsai_swiftui_spec.Id.Protocol.property
  val has_on_row_selected : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Disclosure_group_prop : sig
  val expanded : Bonsai_swiftui_spec.Id.Protocol.property
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Overlay_prop : sig
  val alignment : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Ignores_safe_area_prop : sig
  val regions : Bonsai_swiftui_spec.Id.Protocol.property
  val edges : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Safe_area_padding_prop : sig
  val insets : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Control_size_prop : sig
  val size : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Button_prop : sig
  val enabled : Bonsai_swiftui_spec.Id.Protocol.property
  val role : Bonsai_swiftui_spec.Id.Protocol.property
  val style : Bonsai_swiftui_spec.Id.Protocol.property
  val autofocus : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end

module Native_widget_prop : sig
  val kind_id : Bonsai_swiftui_spec.Id.Protocol.property
  val version : Bonsai_swiftui_spec.Id.Protocol.property
  val capabilities : Bonsai_swiftui_spec.Id.Protocol.property
  val payload : Bonsai_swiftui_spec.Id.Protocol.property
  val debug_name : Bonsai_swiftui_spec.Id.Protocol.property -> string option
end
