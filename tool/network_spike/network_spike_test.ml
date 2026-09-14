let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel))
;;

let cert_pem = read_file "localhost-cert.pem"
let key_pem = read_file "localhost-key.pem"

let fail_result label = function
  | Ok value -> value
  | Error message -> Alcotest.failf "%s failed: %s" label message
;;

let check_rejected label = function
  | Error _ -> ()
  | Ok () -> Alcotest.failf "%s unexpectedly succeeded" label
;;

let test_unknown_ca_is_rejected () =
  Network_spike.tls_handshake ~cert_pem ~key_pem ~trust:`Nss ~host:"localhost"
  |> check_rejected "unknown CA handshake"
;;

let test_trusted_certificate_and_hostname_succeed () =
  Network_spike.tls_handshake
    ~cert_pem
    ~key_pem
    ~trust:`Test_certificate
    ~host:"localhost"
  |> fail_result "trusted handshake"
;;

let test_wrong_hostname_is_rejected () =
  Network_spike.tls_handshake
    ~cert_pem
    ~key_pem
    ~trust:`Test_certificate
    ~host:"wrong.example"
  |> check_rejected "wrong-host handshake"
;;

let test_https_uses_tls_flow_adapter () =
  let body =
    Network_spike.https_get ~cert_pem ~key_pem |> fail_result "loopback HTTPS GET"
  in
  Alcotest.(check string) "response body" "secure hello" body
;;

let test_https_cancellation_closes_transport () =
  let closed =
    Network_spike.https_cancel_closes_transport ~cert_pem ~key_pem
    |> fail_result "HTTPS cancellation"
  in
  Alcotest.(check bool) "transport closed" true closed
;;

let test_wss_uses_tls_flow_adapter () =
  let echoed =
    Network_spike.wss_echo ~cert_pem ~key_pem "secure echo"
    |> fail_result "loopback WSS echo"
  in
  Alcotest.(check string) "echo payload" "secure echo" echoed
;;

let test_wss_disconnect_closes_transport () =
  let closed =
    Network_spike.wss_disconnect_closes_transport ~cert_pem ~key_pem
    |> fail_result "WSS disconnect"
  in
  Alcotest.(check bool) "transport closed" true closed
;;

let () =
  Alcotest.run
    "network spike"
    [ ( "TLS"
      , [ Alcotest.test_case "unknown CA is rejected" `Quick test_unknown_ca_is_rejected
        ; Alcotest.test_case
            "trusted certificate and hostname succeed"
            `Quick
            test_trusted_certificate_and_hostname_succeed
        ; Alcotest.test_case
            "wrong hostname is rejected"
            `Quick
            test_wrong_hostname_is_rejected
        ] )
    ; ( "HTTPS"
      , [ Alcotest.test_case
            "httpun-eio consumes the TLS adapter"
            `Quick
            test_https_uses_tls_flow_adapter
        ; Alcotest.test_case
            "cancellation closes transport"
            `Quick
            test_https_cancellation_closes_transport
        ] )
    ; ( "WSS"
      , [ Alcotest.test_case
            "httpun-ws consumes the TLS adapter"
            `Quick
            test_wss_uses_tls_flow_adapter
        ; Alcotest.test_case
            "disconnect closes transport"
            `Quick
            test_wss_disconnect_closes_transport
        ] )
    ]
;;
