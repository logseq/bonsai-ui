module ID = Bonsai_swiftui_spec.Id

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

type host_response_status =
  | Host_ok
  | Host_error
  | Host_cancelled

type host_response =
  { request_id : ID.Host.request_id
  ; status : host_response_status
  ; value : bytes
  }

type application_error_code =
  | Unavailable
  | Payload_too_large
  | Handler_failed
  | Cancelled
  | Shutdown
  | Runtime_replaced
  | Invalid_response

type application_error =
  { code : application_error_code
  ; message : string
  }

type edge_insets =
  { left : float
  ; top : float
  ; right : float
  ; bottom : float
  }

type environment_brightness =
  | Environment_light
  | Environment_dark

type orientation =
  | Portrait
  | Landscape

type environment =
  { viewport_width : float
  ; viewport_height : float
  ; device_pixel_ratio : float
  ; text_scale : float
  ; brightness : environment_brightness
  ; platform : string
  ; locale : string
  ; safe_area : edge_insets
  ; keyboard_insets : edge_insets
  ; accessible_navigation : bool
  ; bold_text : bool
  ; invert_colors : bool
  ; disable_animations : bool
  ; reduced_motion : bool
  ; high_contrast : bool
  ; orientation : orientation
  ; pointer_kinds : int
  }

type payload =
  | Confirmation_response of
      { token : int64
      ; action_key : string option
      }
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
  | Scroll of
      { pixels : float
      ; delta : float
      }
  | Visible_range of
      { first_index : int64
      ; last_exclusive : int64
      }
  | Tab_selected of Bonsai_swiftui_spec.Id.Navigation.page_key
  | Navigation_split_changed of Wire_frame.navigation_split_state
  | Navigation_path_changed of Bonsai_swiftui_spec.Id.Navigation.page_key list
  | Host_response of host_response
  | Application_response of
      { request_id : int64
      ; payload : bytes
      }
  | Application_request_error of
      { request_id : int64
      ; error : application_error
      }
  | Application_event of bytes
  | Environment_changed of environment
  | Native_event of native_event

type t =
  { sequence : ID.Runtime.event_sequence
  ; displayed_revision : ID.Runtime.renderer_revision
  ; node_id : ID.Ui.node_id
  ; handler_id : ID.Ui.handler_id
  ; event_tag : ID.Protocol.event_tag
  ; payload : payload
  }

type batch =
  { runtime_epoch : ID.Runtime.epoch
  ; events : t list
  }
