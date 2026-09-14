(** Versioned, bounded little-endian frame encoding. *)

type error_code =
  | Invalid_magic
  | Unsupported_version
  | Invalid_header
  | Invalid_frame_kind
  | Invalid_flags
  | Invalid_payload_length
  | Frame_too_large
  | Too_many_operations
  | String_too_large
  | Unknown_operation
  | Unknown_node_kind
  | Invalid_props
  | Invalid_utf8
  | Invalid_operation_order
  | Truncated_input
  | Trailing_bytes
  | Application_payload_too_large

type error =
  { code : error_code
  ; message : string
  }

module Runtime_encoded_frame : sig
  type t

  val bytes : t -> bytes
end

val encode : Wire_frame.t -> (bytes, error) result
val encode_runtime_frame : Wire_frame.t -> (Runtime_encoded_frame.t, error) result

val patch_runtime_stats
  :  Runtime_encoded_frame.t
  -> encode_ns:int64
  -> patch_bytes:int
  -> (unit, error) result

val decode : bytes -> (Wire_frame.t, error) result
