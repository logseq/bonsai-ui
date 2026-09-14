(** Immutable values exchanged between domain 0 and the network Worker Domain. *)

type error =
  | Invalid_uri
  | Unsupported_scheme of string
  | Userinfo_not_allowed
  | Missing_host
  | Fragment_not_allowed
  | Invalid_port
  | Too_many_redirects
  | Insecure_redirect
  | Headers_too_large
  | Response_too_large
  | Message_too_large
  | Invalid_utf8
  | Timeout
  | Cancelled
  | Dns_failure
  | Tls_unknown_issuer
  | Tls_expired_certificate
  | Tls_hostname_mismatch
  | Tls_peer_alert
  | Tls_premature_eof
  | Tls_protocol_error
  | Http_protocol_error
  | Websocket_protocol_error
  | Unsupported_binary_message
  | Busy
  | Disconnected
  | Already_connected
  | Shutting_down
  | Transport_error of string

val error_to_string : error -> string

type https_summary =
  { status_code : int
  ; content_type : string option
  ; body_bytes : int
  ; preview : string
  }

type https_result =
  { request_id : int
  ; outcome : (https_summary, error) result
  }

type websocket_command =
  | Connected
  | Sent
  | Disconnected_command

type websocket_command_result =
  { generation : int
  ; outcome : (websocket_command, error) result
  }

type websocket_state =
  | Idle
  | Connecting
  | Connected_state
  | Disconnecting
  | Closed
  | Failed

type websocket_state_event =
  { generation : int
  ; state : websocket_state
  ; error : error option
  }

type websocket_message_kind =
  | Text
  | Unsupported_binary
  | Unsupported_text

type websocket_message_event =
  { generation : int
  ; kind : websocket_message_kind
  ; message : string option
  }

type request =
  | Https_get of
      { request_id : int
      ; uri : string
      }
  | Websocket_connect of
      { generation : int
      ; uri : string
      }
  | Websocket_send of
      { generation : int
      ; message : string
      }
  | Websocket_disconnect of { generation : int }

type response =
  | Https_result of https_result
  | Websocket_command_result of websocket_command_result

type push =
  | Websocket_state_changed of websocket_state_event
  | Websocket_message_received of websocket_message_event

module Topic : sig
  val websocket_state : Bonsai_swiftui_spec.Id.Worker.push_topic
  val websocket_message : Bonsai_swiftui_spec.Id.Worker.push_topic
  val count : int
end
