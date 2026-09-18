(** Typed renderer events and opaque callback identity. *)

module Tag : sig
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

  val compare : t -> t -> int
  val equal : t -> t -> bool
  val to_string : t -> string
end

module Key_policy : sig
  type t =
    | Handled
    | Ignored
end

module Payload : sig
  type text_selection =
    { start_utf16 : int
    ; end_utf16 : int
    }

  type text_edit =
    { session_id : Bonsai_swiftui_spec.Id.Text_input.session_id
    ; local_revision : Bonsai_swiftui_spec.Id.Text_input.local_revision
    ; base_document_revision : Bonsai_swiftui_spec.Id.Text_input.document_revision
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
    { kind_id : Bonsai_swiftui_spec.Id.Native_widget.kind_id
    ; version : int
    ; event_id : Bonsai_swiftui_spec.Id.Native_widget.event_id
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
    { pointer_id : Bonsai_swiftui_spec.Id.Input.pointer_id
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

  (** Native physical keys use [(HID page lsl 16) lor usage], with page [0x07]
      for Keyboard/Keypad keys and [0] for unknown keys. Logical character keys
      use the unmodified Unicode scalar after NFC normalization. Non-character
      keys use [0x110000 + physical_key]; ambiguous characters use [0]. A held
      key keeps its logical identity through repeats and release.

      Modifier bits follow Apple flags: 16 Caps Lock, 17 Shift, 18 Control,
      19 Option, 20 Command, 21 numeric keypad, 22 Help and 23 Function.
      Help and Function flags are macOS-specific. Device-specific side bits
      are excluded; the physical key identifies left/right modifier events. *)
  type key =
    { logical_key : Bonsai_swiftui_spec.Id.Input.logical_key
    ; physical_key : Bonsai_swiftui_spec.Id.Input.physical_key
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

module Handler : sig
  type t

  (** [create] assigns callback identity. [name] is debug-only and never
      serialized as executable data. *)
  val create : ?name:string -> (Payload.t -> unit) -> t

  val name : t -> string option

  module Private : sig
    val same : t -> t -> bool
    val invoke : t -> Payload.t -> unit
  end
end
