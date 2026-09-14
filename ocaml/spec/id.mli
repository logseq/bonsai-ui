(** Shared private identity types grouped by ownership and protocol boundary. *)

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

(** Runtime lifecycle and renderer transaction identities. *)
module Runtime : sig
  (** Opaque native handle used to address one logical runtime through the C ABI. *)
  type handle = private int64

  module Handle : Int64_id with type t = handle

  (** Identity fencing messages and renderer state to one runtime lifetime. *)
  type epoch = private int64

  module Epoch : Int64_id with type t = epoch

  (** Identity of one presentation-gated logical pump transaction. *)
  type presentation_id = private int64

  module Presentation_id : Int64_id with type t = presentation_id

  (** Version of renderer wire state within one runtime epoch. *)
  type renderer_revision = private int64

  module Renderer_revision : Int64_id with type t = renderer_revision

  (** Monotonic identity of one inbound renderer event. *)
  type event_sequence = private int64

  module Event_sequence : Int64_id with type t = event_sequence
end

(** Worker Domain and attached worker-session identities. *)
module Worker : sig
  (** Identity of one session attached to the process-wide Worker Domain. *)
  type generation = private int64

  module Generation : Int64_id with type t = generation

  (** Diagnostic identity of the process-wide OCaml Worker Domain. *)
  type domain_id = private Domain.id

  module Domain_id : sig
    type t = domain_id

    val of_domain_id : Domain.id -> t
    val to_domain_id : t -> Domain.id
  end

  (** Correlation identity for one worker-session request. *)
  type request_id = private int64

  module Request_id : Int64_id with type t = request_id

  (** Monotonic ordering identity for one worker push. *)
  type push_sequence = private int64

  module Push_sequence : Int64_id with type t = push_sequence

  (** Latest-wins mailbox topic identity declared by a worker service. *)
  type push_topic = private int

  module Push_topic : Int_id with type t = push_topic
end

(** UI reconciliation and application-supplied identities. *)
module Ui : sig
  (** Application-supplied reconciliation identity among siblings. *)
  type application_key = private
    | String of string
    | Int64 of int64

  module Application_key : sig
    type t = application_key

    val string : string -> t
    val int64 : int64 -> t
  end

  (** Application-supplied identity used by headless and renderer tests. *)
  type test_id = private string

  module Test_id : String_id with type t = test_id

  (** Mounted renderer node identity within one runtime epoch. *)
  type node_id = private int64

  module Node_id : Int64_id with type t = node_id

  (** Mounted event-handler identity within one runtime epoch. *)
  type handler_id = private int64

  module Handler_id : Int64_id with type t = handler_id

  (** Application-supplied semantic animation completion identity. *)
  type animation_id = private int64

  module Animation_id : Int64_id with type t = animation_id
end

(** Text-input session and document revision identities. *)
module Text_input : sig
  (** Editing-session identity for one text input. *)
  type session_id = private int64

  module Session_id : Int64_id with type t = session_id

  (** Canonical OCaml document revision for one text input. *)
  type document_revision = private int64

  module Document_revision : Int64_id with type t = document_revision

  (** Native-local edit revision for one text input session. *)
  type local_revision = private int64

  module Local_revision : Int64_id with type t = local_revision
end

(** Declarative navigation and state-restoration identities. *)
module Navigation : sig
  (** Application-supplied declarative navigation page identity. *)
  type page_key = private string

  module Page_key : String_id with type t = page_key

  (** Navigator restoration-scope identity. *)
  type restoration_scope_id = private string

  module Restoration_scope_id : String_id with type t = restoration_scope_id

  (** Page restoration identity. *)
  type restoration_id = private string

  module Restoration_id : String_id with type t = restoration_id
end

(** Platform input stream and key identities. *)
module Input : sig
  (** Platform pointer-stream identity. *)
  type pointer_id = private int64

  module Pointer_id : Int64_id with type t = pointer_id

  (** Platform logical keyboard-key identity. *)
  type logical_key = private int64

  module Logical_key : Int64_id with type t = logical_key

  (** Platform physical keyboard-key identity. *)
  type physical_key = private int64

  module Physical_key : Int64_id with type t = physical_key

  (** Accessibility semantics-action identity. *)
  type semantics_action_id = private int64

  module Semantics_action_id : Int64_id with type t = semantics_action_id
end

(** SwiftUI host-effect identities. *)
module Host : sig
  (** Correlation identity for one asynchronous host request. *)
  type request_id = private int64

  module Request_id : Int64_id with type t = request_id

  (** Internal ordering identity for one queued host operation. *)
  type operation_id = private int64

  module Operation_id : Int64_id with type t = operation_id

  (** Application-supplied native-menu item identity. *)
  type native_menu_item_id = private string

  module Native_menu_item_id : String_id with type t = native_menu_item_id
end

(** Registered native-widget extension identities. *)
module Native_widget : sig
  (** Stable registered native-widget kind identity. *)
  type kind_id = private int

  module Kind_id : Int_id with type t = kind_id

  (** Event identity scoped by a native-widget kind and schema version. *)
  type event_id = private int

  module Event_id : Int_id with type t = event_id
end

(** Native application registry identities. *)
module Application : sig
  (** Stable application identity at the native entrypoint registry boundary. *)
  type entrypoint_name = private string

  module Entrypoint_name : String_id with type t = entrypoint_name
end

(** Generated wire-protocol discriminants. *)
module Protocol : sig
  (** Binary frame-kind identity. *)
  type frame_kind = private int

  module Frame_kind : Int_id with type t = frame_kind

  (** Binary frame operation opcode identity. *)
  type operation = private int

  module Operation : Int_id with type t = operation

  (** Binary renderer node-kind identity. *)
  type node_kind = private int

  module Node_kind : Int_id with type t = node_kind

  (** Binary inbound event-tag identity. *)
  type event_tag = private int

  module Event_tag : Int_id with type t = event_tag

  (** Binary host-request kind identity. *)
  type host_request_kind = private int

  module Host_request_kind : Int_id with type t = host_request_kind

  (** Binary runtime-error category identity. *)
  type runtime_error = private int

  module Runtime_error : Int_id with type t = runtime_error

  (** Property field identity within a generated property group. *)
  type property = private int

  module Property : Int_id with type t = property
end

(** Native FFI boundary identities. *)
module Ffi : sig
  (** Error-code identity returned by the native ABI. *)
  type error_code = private int

  module Error_code : Int_id with type t = error_code
end
