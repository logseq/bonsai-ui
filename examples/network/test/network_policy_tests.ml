module Policy = Network_policy
module Protocol = Network_protocol

let fail_error label = function
  | Ok value -> value
  | Error error -> Alcotest.failf "%s: %s" label (Protocol.error_to_string error)
;;

let check_error label expected = function
  | Error actual -> Alcotest.(check bool) label true (actual = expected)
  | Ok _ -> Alcotest.failf "%s unexpectedly succeeded" label
;;

let test_https_endpoint_normalization () =
  let endpoint =
    Policy.validate_endpoint ~expected:`Https "HTTPS://Example.COM:443/a%20b?q=one%20two"
    |> fail_error "HTTPS endpoint"
  in
  Alcotest.(check string)
    "scheme and host normalized"
    "https://example.com/a%20b?q=one%20two"
    endpoint.uri;
  Alcotest.(check string) "host" "example.com" endpoint.host;
  Alcotest.(check int) "default port" 443 endpoint.port;
  Alcotest.(check string) "host authority" "example.com" endpoint.authority;
  Alcotest.(check string) "origin-form resource" "/a%20b?q=one%20two" endpoint.resource
;;

let test_wss_custom_port () =
  let endpoint =
    Policy.validate_endpoint ~expected:`Wss "wss://echo.example:8443/socket"
    |> fail_error "WSS endpoint"
  in
  Alcotest.(check int) "custom port" 8443 endpoint.port;
  Alcotest.(check string) "custom authority" "echo.example:8443" endpoint.authority
;;

let test_rejected_uri_forms () =
  [ `Https, "https://user@example.com/", Protocol.Userinfo_not_allowed
  ; `Https, "https:///missing", Protocol.Missing_host
  ; `Https, "http://example.com/", Protocol.Unsupported_scheme "http"
  ; `Wss, "ws://example.com/", Protocol.Unsupported_scheme "ws"
  ; `Https, "https://example.com/a#fragment", Protocol.Fragment_not_allowed
  ; `Https, "https://example.com:0/", Protocol.Invalid_port
  ; `Https, "https://example.com:65536/", Protocol.Invalid_port
  ; `Https, "not a uri", Protocol.Invalid_uri
  ]
  |> List.iter (fun (expected, uri, error) ->
    Policy.validate_endpoint ~expected uri |> check_error uri error)
;;

let test_size_limits () =
  Policy.check_header_size Policy.maximum_header_bytes |> fail_error "header boundary";
  Policy.check_header_size (Policy.maximum_header_bytes + 1)
  |> check_error "header over limit" Protocol.Headers_too_large;
  Policy.check_body_size Policy.maximum_body_bytes |> fail_error "body boundary";
  Policy.check_body_size (Policy.maximum_body_bytes + 1)
  |> check_error "body over limit" Protocol.Response_too_large;
  Policy.check_message_size Policy.maximum_message_bytes |> fail_error "message boundary";
  Policy.check_message_size (Policy.maximum_message_bytes + 1)
  |> check_error "message over limit" Protocol.Message_too_large
;;

let test_redirect_policy () =
  let current =
    Policy.validate_endpoint ~expected:`Https "https://example.com/one/index"
    |> fail_error "current endpoint"
  in
  let relative =
    Policy.redirect ~current ~location:"../two?q=3" ~redirect_count:0
    |> fail_error "relative redirect"
  in
  Alcotest.(check string)
    "relative redirect resolved"
    "https://example.com/two?q=3"
    relative.uri;
  Policy.redirect ~current ~location:"http://example.com/plain" ~redirect_count:0
  |> check_error "secure downgrade" Protocol.Insecure_redirect;
  Policy.redirect
    ~current
    ~location:"https://example.com/four"
    ~redirect_count:Policy.maximum_redirects
  |> check_error "redirect count" Protocol.Too_many_redirects
;;

let test_error_messages_are_stable_and_sanitized () =
  Alcotest.(check string)
    "hostname error"
    "TLS hostname verification failed"
    (Protocol.error_to_string Protocol.Tls_hostname_mismatch);
  Alcotest.(check string)
    "transport detail hidden"
    "Network transport failed"
    (Protocol.error_to_string
       (Protocol.Transport_error "secret.example: private payload"))
;;

let test_utf8_safe_preview () =
  Alcotest.(check string)
    "ASCII prefix"
    "abc"
    (Policy.truncate_preview ~max_bytes:3 "abcdef");
  let preview = Policy.truncate_preview ~max_bytes:5 "ab😀cd" in
  Alcotest.(check string) "does not split a scalar" "ab" preview;
  Alcotest.(check bool) "preview remains valid UTF-8" true (String.is_valid_utf_8 preview)
;;

let test_transcript_is_bounded () =
  let entries =
    List.init 51 (fun index ->
      { Policy.generation = 1; text = string_of_int (index + 1) })
    |> List.fold_left Policy.add_transcript []
  in
  Alcotest.(check int)
    "bounded length"
    Policy.maximum_transcript_entries
    (List.length entries);
  Alcotest.(check string) "oldest entry discarded" "2" (List.hd entries).text;
  Alcotest.(check string) "newest entry retained" "51" (List.hd (List.rev entries)).text
;;

let test_connection_generations () =
  let next = Policy.next_generation 41 |> fail_error "next generation" in
  Alcotest.(check int) "monotonic generation" 42 next;
  Alcotest.(check bool)
    "current event accepted"
    true
    (Policy.is_current_generation ~active:42 ~event:42);
  Alcotest.(check bool)
    "stale event rejected"
    false
    (Policy.is_current_generation ~active:42 ~event:41);
  Policy.next_generation max_int |> check_error "generation exhaustion" Protocol.Busy
;;

let () =
  Alcotest.run
    "network policy"
    [ ( "URI"
      , [ Alcotest.test_case "normalizes HTTPS" `Quick test_https_endpoint_normalization
        ; Alcotest.test_case "supports WSS custom ports" `Quick test_wss_custom_port
        ; Alcotest.test_case "rejects unsafe URI forms" `Quick test_rejected_uri_forms
        ; Alcotest.test_case "enforces redirect policy" `Quick test_redirect_policy
        ] )
    ; ( "Bounds"
      , [ Alcotest.test_case "enforces size limits" `Quick test_size_limits
        ; Alcotest.test_case "truncates UTF-8 safely" `Quick test_utf8_safe_preview
        ; Alcotest.test_case "bounds the transcript" `Quick test_transcript_is_bounded
        ] )
    ; ( "State"
      , [ Alcotest.test_case
            "sanitizes stable errors"
            `Quick
            test_error_messages_are_stable_and_sanitized
        ; Alcotest.test_case
            "fences connection generations"
            `Quick
            test_connection_generations
        ] )
    ]
;;
