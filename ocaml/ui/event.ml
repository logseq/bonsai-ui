module ID = Bonsai_swiftui_spec.Id

module Tag = struct
  type t =
    | Press
    | Long_press
    | Tap
    | Double_tap
    | Pointer_enter
    | Pointer_leave
    | Pointer_down
    | Pointer_up
    | Key
    | Focus_changed
    | Text_edit
    | Text_submit
    | Text_limit_reached
    | Scroll_notification
    | Visible_range_changed
    | Animation_completed
    | Tab_selected
    | Navigation_split_changed
    | Navigation_path_changed
    | Layout_observed
    | Value_changed
    | Native_event
    | Semantics_action
    | Navigation_destination_selected
    | Radio_selected
    | Removal_requested
    | Removal_completed
    | List_scroll_completed
    | Refresh_request
    | Scroll_position_changed
    | Menu_action
    | Confirmation_response
    | Picker_selected
    | Slider_changed
    | Slider_change_end
    | Range_slider_changed
    | Range_slider_change_end
    | Table_sort_requested
    | Table_row_selected
    | Civil_date_changed
    | Civil_time_changed

  let compare left right = Stdlib.compare left right
  let equal left right = compare left right = 0

  let to_string = function
    | Press -> "press"
    | Long_press -> "long_press"
    | Tap -> "tap"
    | Double_tap -> "double_tap"
    | Pointer_enter -> "pointer_enter"
    | Pointer_leave -> "pointer_leave"
    | Pointer_down -> "pointer_down"
    | Pointer_up -> "pointer_up"
    | Key -> "key"
    | Focus_changed -> "focus_changed"
    | Text_edit -> "text_edit"
    | Text_submit -> "text_submit"
    | Text_limit_reached -> "text_limit_reached"
    | Scroll_notification -> "scroll_notification"
    | Visible_range_changed -> "visible_range_changed"
    | Animation_completed -> "animation_completed"
    | Tab_selected -> "tab_selected"
    | Navigation_split_changed -> "navigation_split_changed"
    | Navigation_path_changed -> "navigation_path_changed"
    | Layout_observed -> "layout_observed"
    | Value_changed -> "value_changed"
    | Native_event -> "native_event"
    | Semantics_action -> "semantics_action"
    | Navigation_destination_selected -> "navigation_destination_selected"
    | Radio_selected -> "radio_selected"
    | Removal_requested -> "removal_requested"
    | Removal_completed -> "removal_completed"
    | List_scroll_completed -> "list_scroll_completed"
    | Refresh_request -> "refresh_request"
    | Scroll_position_changed -> "scroll_position_changed"
    | Menu_action -> "menu_action"
    | Confirmation_response -> "confirmation_response"
    | Picker_selected -> "picker_selected"
    | Slider_changed -> "slider_changed"
    | Slider_change_end -> "slider_change_end"
    | Range_slider_changed -> "range_slider_changed"
    | Range_slider_change_end -> "range_slider_change_end"
    | Table_sort_requested -> "table_sort_requested"
    | Table_row_selected -> "table_row_selected"
    | Civil_date_changed -> "civil_date_changed"
    | Civil_time_changed -> "civil_time_changed"
  ;;
end

module Key_policy = struct
  type t =
    | Handled
    | Ignored
end

module Payload = struct
  type text_selection =
    { start_utf16 : int
    ; end_utf16 : int
    }

  type text_edit =
    { session_id : ID.Text_input.session_id
    ; local_revision : ID.Text_input.local_revision
    ; base_document_revision : ID.Text_input.document_revision
    ; text : string
    ; selection : text_selection
    ; composing : text_selection option
    }

  type scroll =
    { pixels : float
    ; delta : float
    }

  type visible_range =
    { first_index : int64
    ; last_exclusive : int64
    }

  type native_event =
    { kind_id : ID.Native_widget.kind_id
    ; version : int
    ; event_id : ID.Native_widget.event_id
    ; payload : bytes
    }

  type pointer_kind =
    | Mouse
    | Touch
    | Stylus
    | Inverted_stylus
    | Trackpad
    | Unknown_pointer

  type tap =
    { local_x : float
    ; local_y : float
    ; global_x : float
    ; global_y : float
    ; pointer_kind : pointer_kind
    }

  type pointer =
    { pointer_id : ID.Input.pointer_id
    ; local_x : float
    ; local_y : float
    ; global_x : float
    ; global_y : float
    ; pointer_kind : pointer_kind
    ; buttons : int
    }

  type key_action =
    | Key_down
    | Key_up
    | Key_repeat

  type key =
    { logical_key : ID.Input.logical_key
    ; physical_key : ID.Input.physical_key
    ; action : key_action
    ; modifiers : int
    }

  type confirmation_result =
    | Action of string
    | Dismissed

  type confirmation_response =
    { token : int64
    ; result : confirmation_result
    }

  type t =
    | Confirmation_response of confirmation_response
    | Unit
    | Bool of bool
    | Text of string
    | Text_edit of text_edit
    | Int64 of int64
    | Int64_bool of
        { id : int64
        ; value : bool
        }
    | Int64_pair of
        { first : int64
        ; second : int64
        }
    | Float of float
    | Float_range of
        { start : float
        ; end_ : float
        }
    | Civil_date of
        { year : int
        ; month : int
        ; day : int
        }
    | Civil_time of
        { hour : int
        ; minute : int
        }
    | Tap of tap
    | Pointer of pointer
    | Key of key
    | Scroll of scroll
    | Visible_range of visible_range
    | Tab_selected of Bonsai_swiftui_spec.Id.Navigation.page_key
    | Navigation_split_changed of Navigation.Split_state.t
    | Navigation_path_changed of Bonsai_swiftui_spec.Id.Navigation.page_key list
    | Native_event of native_event
end

module Handler = struct
  type t =
    { name : string option
    ; callback : Payload.t -> unit
    }

  let create ?name callback = { name; callback }
  let name t = t.name

  module Private = struct
    let same left right = left == right
    let invoke t payload = t.callback payload
  end
end
