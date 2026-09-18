(** Typed asynchronous requests executed by the SwiftUI host. *)

type t

type error =
  | Failed of string
  | Cancelled
  | Shutdown
  | Invalid_response of string

type file =
  { path : string option
  ; data : bytes option
  }

type platform_information =
  { operating_system : string
  ; operating_system_version : string
  ; locale_name : string
  }

type layout =
  { left : float
  ; top : float
  ; width : float
  ; height : float
  }

type native_menu_item =
  { item_id : Bonsai_swiftui_spec.Id.Host.native_menu_item_id
  ; label : string
  ; enabled : bool
  }

type haptic_kind =
  | Haptic_light
  | Haptic_medium
  | Haptic_heavy
  | Haptic_selection

type notice_close_reason =
  | Action
  | Dismiss
  | Swipe
  | Timeout

type civil_date =
  { year : int
  ; month : int
  ; day : int
  }

type civil_date_range =
  { start : civil_date
  ; end_ : civil_date
  }

type civil_time =
  { hour : int
  ; minute : int
  }

type time_format =
  | System
  | Hour12
  | Hour24

val civil_date : year:int -> month:int -> day:int -> civil_date
val civil_date_range : start:civil_date -> end_:civil_date -> civil_date_range
val civil_time : hour:int -> minute:int -> civil_time

module Application_platform : sig
  type t

  type error =
    | Unavailable
    | Payload_too_large
    | Handler_failed of string
    | Cancelled
    | Shutdown
    | Runtime_replaced
    | Invalid_response of string

  val maximum_payload_bytes : int

  module Cancellation : sig
    type t

    val create : unit -> t
    val cancel : t -> unit
  end

  val request
    :  ?cancellation:Cancellation.t
    -> t
    -> bytes
    -> (bytes, error) result Bonsai.Effect.t

  val on_event : t -> (bytes -> unit Bonsai.Effect.t) -> unit

  module Prepared_operations : sig
    type t

    val operations : t -> Bonsai_swiftui_protocol.Wire_frame.operation list
  end

  val prepare_operations : ?maximum_count:int -> t -> Prepared_operations.t
  val commit_operations : t -> Prepared_operations.t -> (unit, string) result

  module Private : sig
    val create : schedule:(unit Bonsai.Effect.t -> unit) -> t

    module Validated_input : sig
      type t

      val request_id : t -> int64 option
    end

    val validate_input
      :  t
      -> Bonsai_swiftui_protocol.Inbound_event.payload
      -> (Validated_input.t, string) result

    val resolve_validated : t -> Validated_input.t -> (unit, string) result
    val shutdown : t -> error -> unit
    val begin_shutdown : t -> unit
    val pending_count : t -> int
  end
end

module Cancellation : sig
  type t

  val create : unit -> t
  val cancel : t -> unit
  val is_cancelled : t -> bool
end

module Clipboard : sig
  val read
    :  ?cancellation:Cancellation.t
    -> t
    -> unit
    -> (string, error) result Bonsai.Effect.t

  val write
    :  ?cancellation:Cancellation.t
    -> t
    -> string
    -> (unit, error) result Bonsai.Effect.t
end

val open_url
  :  ?cancellation:Cancellation.t
  -> t
  -> string
  -> (unit, error) result Bonsai.Effect.t

(** Return every selected file in selection order, or an empty list when the
    native chooser is cancelled. Multiple selection is enabled explicitly. *)
val pick_files
  :  ?cancellation:Cancellation.t
  -> ?allowed_extensions:string list
  -> ?allow_multiple:bool
  -> t
  -> unit
  -> (file list, error) result Bonsai.Effect.t

val save_file
  :  ?cancellation:Cancellation.t
  -> ?suggested_name:string
  -> data:bytes
  -> t
  -> unit
  -> (file option, error) result Bonsai.Effect.t

val request_focus
  :  ?cancellation:Cancellation.t
  -> t
  -> node_id:Bonsai_swiftui_spec.Id.Ui.node_id
  -> (unit, error) result Bonsai.Effect.t

val clear_focus
  :  ?cancellation:Cancellation.t
  -> t
  -> unit
  -> (unit, error) result Bonsai.Effect.t

(** Scroll a presented container by a normalized fraction of its available
    travel. [alignment] defaults to zero, must be finite, and is clamped to
    [0.0 .. 1.0]. [animated] defaults to true and uses a 250 ms ease-in-out
    transition unless Reduce Motion is enabled. Success follows observed native
    positioning. Cancellation, user interruption, replacement by another request
    and loss of active ownership stop pending motion. Non-scrollable, detached
    and retired node identities fail explicitly. *)
val scroll_to
  :  ?cancellation:Cancellation.t
  -> ?alignment:float
  -> ?animated:bool
  -> t
  -> node_id:Bonsai_swiftui_spec.Id.Ui.node_id
  -> (unit, error) result Bonsai.Effect.t

val set_window_title
  :  ?cancellation:Cancellation.t
  -> t
  -> string
  -> (unit, error) result Bonsai.Effect.t

val set_window_size
  :  ?cancellation:Cancellation.t
  -> t
  -> width:float
  -> height:float
  -> (unit, error) result Bonsai.Effect.t

(** Present a scrollable SwiftUI action chooser in the owned window. Items require
    unique nonempty UTF-8 IDs, nonblank labels and a count from 1 through 1024;
    invalid inputs raise [Invalid_argument]. IDs preserve their exact bytes and
    are limited to 1 MiB minus the five-byte optional-string response prefix.
    Disabled items remain visible. Selecting an item returns its ID; native
    dismissal returns [None]. Cancellation and loss of active window ownership
    return [Error Cancelled]. Concurrent modal requests fail explicitly. *)
val show_native_menu
  :  ?cancellation:Cancellation.t
  -> t
  -> native_menu_item list
  -> (Bonsai_swiftui_spec.Id.Host.native_menu_item_id option, error) result
       Bonsai.Effect.t

(** Submit feedback after active presentation. iOS uses the matching impact
    weight or selection generator; macOS uses AppKit generic feedback for all
    kinds. [Ok ()] means native submission, not confirmed physical delivery.
    Hardware capability, system preferences and accessibility settings govern
    delivery. Cancellation before dispatch prevents submission. *)
val haptic_feedback
  :  ?cancellation:Cancellation.t
  -> t
  -> haptic_kind
  -> (unit, error) result Bonsai.Effect.t

val platform_information
  :  ?cancellation:Cancellation.t
  -> t
  -> unit
  -> (platform_information, error) result Bonsai.Effect.t

val measure_layout
  :  ?cancellation:Cancellation.t
  -> t
  -> node_id:Bonsai_swiftui_spec.Id.Ui.node_id
  -> (layout, error) result Bonsai.Effect.t

(** Show a notification in the owned window's bottom safe area. Requests display
    in order; the duration (default 4000 ms) starts when displayed and pauses
    while the window is inactive. Cancellation returns [Error Cancelled]. *)
val show_notice
  :  ?cancellation:Cancellation.t
  -> ?action_label:string
  -> ?duration_ms:int
  -> t
  -> message:string
  -> unit
  -> (notice_close_reason, error) result Bonsai.Effect.t

(** Present a system DatePicker for Gregorian year/month/day values. Bounds are
    inclusive and must be within 1582-10-15 through 9999-12-31.
    Omitted initial selection uses [first]. Save returns [Some date]; native
    dismissal or Cancel returns [None]. Invalid values raise [Invalid_argument].
    Requests share one modal slot with date-range, time, menu and file dialogs. *)
val pick_date
  :  ?cancellation:Cancellation.t
  -> ?initial:civil_date
  -> first:civil_date
  -> last:civil_date
  -> t
  -> unit
  -> (civil_date option, error) result Bonsai.Effect.t

(** Select an inclusive date range with the same bounds as [pick_date].
    Omitted initial selection is [first, first].
    Moving the start beyond the end advances the end; end choices start at the
    selected start. An initial reversed range is invalid. *)
val pick_date_range
  :  ?cancellation:Cancellation.t
  -> ?initial:civil_date_range
  -> first:civil_date
  -> last:civil_date
  -> t
  -> unit
  -> (civil_date_range option, error) result Bonsai.Effect.t

(** Select civil clock fields, independent of time zone. [format] defaults to
    [System]; [Hour12] and [Hour24] override the hour cycle while retaining the
    locale. Values are committed only on Save. *)
val pick_time
  :  ?cancellation:Cancellation.t
  -> ?format:time_format
  -> initial:civil_time
  -> t
  -> unit
  -> (civil_time option, error) result Bonsai.Effect.t

module Prepared_operations : sig
  type t

  val operations : t -> Bonsai_swiftui_protocol.Wire_frame.operation list
end

val prepare_operations : t -> Prepared_operations.t
val commit_operations : t -> Prepared_operations.t -> (unit, string) result

module Private : sig
  val create : schedule:(unit Bonsai.Effect.t -> unit) -> t

  module Validated_response : sig
    type t

    val request_id : t -> Bonsai_swiftui_spec.Id.Host.request_id
  end

  val validate_response
    :  t
    -> Bonsai_swiftui_protocol.Inbound_event.host_response
    -> (Validated_response.t, string) result

  val resolve_validated : t -> Validated_response.t -> (unit, string) result

  val resolve
    :  t
    -> Bonsai_swiftui_protocol.Inbound_event.host_response
    -> (unit, string) result

  val shutdown : t -> unit
  val pending_count : t -> int
end
