let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let require_ok label = function
  | Ok value -> value
  | Error message -> fail "%s failed: %s" label message
;;

let run cert_pem key_pem =
  try
    (match
       Network_spike.tls_handshake ~cert_pem ~key_pem ~trust:`Nss ~host:"localhost"
     with
     | Error _ -> ()
     | Ok () -> fail "NSS unexpectedly trusted the loopback test CA");
    Network_spike.tls_handshake
      ~cert_pem
      ~key_pem
      ~trust:`Test_certificate
      ~host:"localhost"
    |> require_ok "trusted loopback TLS";
    (match
       Network_spike.tls_handshake
         ~cert_pem
         ~key_pem
         ~trust:`Test_certificate
         ~host:"wrong.example"
     with
     | Error _ -> ()
     | Ok () -> fail "TLS accepted the wrong hostname");
    let body =
      Network_spike.https_get ~cert_pem ~key_pem |> require_ok "loopback HTTPS"
    in
    require (String.equal body "secure hello") "loopback HTTPS body was incorrect";
    Network_spike.https_cancel_closes_transport ~cert_pem ~key_pem
    |> require_ok "HTTPS cancellation"
    |> fun closed ->
    require closed "HTTPS cancellation left the transport open";
    let local_echo = "ios-loopback-echo" in
    let echoed =
      Network_spike.wss_echo ~cert_pem ~key_pem local_echo |> require_ok "loopback WSS"
    in
    require (String.equal echoed local_echo) "loopback WSS echo was incorrect";
    Network_spike.wss_disconnect_closes_transport ~cert_pem ~key_pem
    |> require_ok "WSS disconnect"
    |> fun closed ->
    require closed "WSS disconnect left the transport open";
    let public_body =
      Network_spike.public_https_get ~host:"example.com" ~port:443 ~resource:"/"
      |> require_ok "public HTTPS"
    in
    require (String.length public_body > 0) "public HTTPS returned an empty body";
    let public_echo = "bonsai-swiftui-ios-network-spike" in
    let public_echoed =
      Network_spike.public_wss_echo
        ~host:"echo.websocket.org"
        ~port:443
        ~resource:"/"
        public_echo
      |> require_ok "public WSS"
    in
    require (String.equal public_echoed public_echo) "public WSS echo was incorrect";
    Printf.sprintf "OK https_bytes=%d object_tls=tls-eio" (String.length public_body)
  with
  | exn -> "FAIL " ^ Printexc.to_string exn
;;

let () = Callback.register "bonsai_swiftui.network_spike_device_probe" run
