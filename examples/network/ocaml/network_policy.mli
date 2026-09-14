type expected_scheme =
  [ `Https
  | `Wss
  ]

type endpoint =
  { uri : string
  ; scheme : expected_scheme
  ; host : string
  ; port : int
  ; authority : string
  ; resource : string
  }

val maximum_header_bytes : int
val maximum_body_bytes : int
val maximum_message_bytes : int
val maximum_preview_bytes : int
val maximum_transcript_entries : int
val maximum_redirects : int
val connect_timeout_seconds : float
val request_timeout_seconds : float

val validate_endpoint
  :  expected:expected_scheme
  -> string
  -> (endpoint, Network_protocol.error) result

val redirect
  :  current:endpoint
  -> location:string
  -> redirect_count:int
  -> (endpoint, Network_protocol.error) result

val check_header_size : int -> (unit, Network_protocol.error) result
val check_body_size : int -> (unit, Network_protocol.error) result
val check_message_size : int -> (unit, Network_protocol.error) result
val truncate_preview : max_bytes:int -> string -> string

type transcript_entry =
  { generation : int
  ; text : string
  }

val add_transcript : transcript_entry list -> transcript_entry -> transcript_entry list
val is_current_generation : active:int -> event:int -> bool
val next_generation : int -> (int, Network_protocol.error) result
