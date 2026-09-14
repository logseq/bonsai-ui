module type Int64_id = sig
  type t = private int64

  val of_int64 : int64 -> t
  val to_int64 : t -> int64
  val compare : t -> t -> int
  val equal : t -> t -> bool
  val succ : t -> t
  val pred : t -> t
  val zero : t
  val one : t
  val max_value : t
end

module type Int_id = sig
  type t = private int

  val of_int : int -> t
  val to_int : t -> int
  val compare : t -> t -> int
  val equal : t -> t -> bool
end

module type String_id = sig
  type t = private string

  val of_string : string -> t
  val to_string : t -> string
  val compare : t -> t -> int
  val equal : t -> t -> bool
end

module Int64_id = struct
  type t = int64

  let of_int64 value = value
  let to_int64 value = value
  let compare = Int64.compare
  let equal = Int64.equal
  let succ = Int64.succ
  let pred = Int64.pred
  let zero = 0L
  let one = 1L
  let max_value = Int64.max_int
end

module Int_id = struct
  type t = int

  let of_int value = value
  let to_int value = value
  let compare = Int.compare
  let equal = Int.equal
end

module String_id = struct
  type t = string

  let of_string value = value
  let to_string value = value
  let compare = String.compare
  let equal = String.equal
end

module Runtime = struct
  type handle = int64

  module Handle = Int64_id

  type epoch = int64

  module Epoch = Int64_id

  type presentation_id = int64

  module Presentation_id = Int64_id

  type renderer_revision = int64

  module Renderer_revision = Int64_id

  type event_sequence = int64

  module Event_sequence = Int64_id
end

module Worker = struct
  type generation = int64

  module Generation = Int64_id

  type domain_id = Domain.id

  module Domain_id = struct
    type t = domain_id

    let of_domain_id value = value
    let to_domain_id value = value
  end

  type request_id = int64

  module Request_id = Int64_id

  type push_sequence = int64

  module Push_sequence = Int64_id

  type push_topic = int

  module Push_topic = Int_id
end

module Ui = struct
  type application_key =
    | String of string
    | Int64 of int64

  module Application_key = struct
    type t = application_key

    let string value = String value
    let int64 value = Int64 value
  end

  type test_id = string

  module Test_id = String_id

  type node_id = int64

  module Node_id = Int64_id

  type handler_id = int64

  module Handler_id = Int64_id

  type animation_id = int64

  module Animation_id = Int64_id
end

module Text_input = struct
  type session_id = int64

  module Session_id = Int64_id

  type document_revision = int64

  module Document_revision = Int64_id

  type local_revision = int64

  module Local_revision = Int64_id
end

module Navigation = struct
  type page_key = string

  module Page_key = String_id

  type restoration_scope_id = string

  module Restoration_scope_id = String_id

  type restoration_id = string

  module Restoration_id = String_id
end

module Input = struct
  type pointer_id = int64

  module Pointer_id = Int64_id

  type logical_key = int64

  module Logical_key = Int64_id

  type physical_key = int64

  module Physical_key = Int64_id

  type semantics_action_id = int64

  module Semantics_action_id = Int64_id
end

module Host = struct
  type request_id = int64

  module Request_id = Int64_id

  type operation_id = int64

  module Operation_id = Int64_id

  type native_menu_item_id = string

  module Native_menu_item_id = String_id
end

module Native_widget = struct
  type kind_id = int

  module Kind_id = Int_id

  type event_id = int

  module Event_id = Int_id
end

module Application = struct
  type entrypoint_name = string

  module Entrypoint_name = String_id
end

module Protocol = struct
  type frame_kind = int

  module Frame_kind = Int_id

  type operation = int

  module Operation = Int_id

  type node_kind = int

  module Node_kind = Int_id

  type event_tag = int

  module Event_tag = Int_id

  type host_request_kind = int

  module Host_request_kind = Int_id

  type runtime_error = int

  module Runtime_error = Int_id

  type property = int

  module Property = Int_id
end

module Ffi = struct
  type error_code = int

  module Error_code = Int_id
end
