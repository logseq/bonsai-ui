module ID = Bonsai_swiftui_spec.Id

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

let error_to_string = function
  | Invalid_uri -> "Invalid URI"
  | Unsupported_scheme scheme -> Printf.sprintf "Unsupported URI scheme: %s" scheme
  | Userinfo_not_allowed -> "URI user information is not allowed"
  | Missing_host -> "URI host is required"
  | Fragment_not_allowed -> "URI fragments are not allowed"
  | Invalid_port -> "URI port must be between 1 and 65535"
  | Too_many_redirects -> "HTTPS redirect limit exceeded"
  | Insecure_redirect -> "HTTPS redirects must remain secure"
  | Headers_too_large -> "HTTP response headers exceed 16 KiB"
  | Response_too_large -> "HTTPS response body exceeds 64 KiB"
  | Message_too_large -> "WebSocket message exceeds 64 KiB"
  | Invalid_utf8 -> "Text is not valid UTF-8"
  | Timeout -> "Network operation timed out"
  | Cancelled -> "Network operation was cancelled"
  | Dns_failure -> "DNS resolution failed"
  | Tls_unknown_issuer -> "TLS certificate issuer is not trusted"
  | Tls_expired_certificate -> "TLS certificate has expired"
  | Tls_hostname_mismatch -> "TLS hostname verification failed"
  | Tls_peer_alert -> "TLS peer rejected the connection"
  | Tls_premature_eof -> "TLS peer closed the connection unexpectedly"
  | Tls_protocol_error -> "TLS protocol failed"
  | Http_protocol_error -> "HTTP protocol failed"
  | Websocket_protocol_error -> "WebSocket protocol failed"
  | Unsupported_binary_message -> "Binary WebSocket messages are unsupported"
  | Busy -> "Network service is busy"
  | Disconnected -> "WebSocket is disconnected"
  | Already_connected -> "WebSocket is already connected"
  | Shutting_down -> "Network service is shutting down"
  | Transport_error _ -> "Network transport failed"
;;

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

module Topic = struct
  let websocket_state = ID.Worker.Push_topic.of_int 0
  let websocket_message = ID.Worker.Push_topic.of_int 1
  let count = 2
end
