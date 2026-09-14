(** Bounded decoder for renderer-to-runtime event batches. *)

type error_code =
  | Invalid_magic
  | Unsupported_version
  | Invalid_header
  | Invalid_frame_kind
  | Invalid_payload_length
  | Too_many_events
  | Unknown_event_tag
  | Invalid_payload
  | Invalid_utf8
  | Truncated_input
  | Trailing_bytes
  | Application_payload_too_large

type error =
  { code : error_code
  ; message : string
  }

val encode : Inbound_event.batch -> (bytes, error) result
val decode : bytes -> (Inbound_event.batch, error) result
