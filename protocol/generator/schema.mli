(** Minimal validated view of the protocol schema used by code generation. *)

type entry =
  { name : string
  ; id : int
  }

type property =
  { name : string
  ; id : int
  ; encoding : string
  }

type property_group =
  { name : string
  ; properties : property list
  }

type limits =
  { header_bytes : int
  ; max_frame_bytes : int
  ; max_string_bytes : int
  ; max_application_payload_bytes : int
  ; max_operations : int
  ; max_nodes : int
  }

type t =
  { major : int
  ; minor : int
  ; limits : limits
  ; frame_kinds : entry list
  ; operations : entry list
  ; node_kinds : entry list
  ; event_tags : entry list
  ; host_requests : entry list
  ; runtime_errors : entry list
  ; common_props : property list
  ; kind_props : property_group list
  }

val parse : string -> (t, string) result
val load : string -> (t, string) result
