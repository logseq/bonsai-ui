let fail label message =
  Printf.eprintf "%s failed: %s\n%!" label message;
  exit 1
;;

let () =
  match Network_spike.public_https_get ~host:"example.com" ~port:443 ~resource:"/" with
  | Error message -> fail "public HTTPS" message
  | Ok body ->
    if String.length body = 0 then fail "public HTTPS" "empty response body";
    Printf.printf "NETWORK_SPIKE_PUBLIC_HTTPS_OK bytes=%d\n%!" (String.length body)
;;

let () =
  let message = "bonsai-swiftui-network-spike" in
  match
    Network_spike.public_wss_echo
      ~host:"echo.websocket.org"
      ~port:443
      ~resource:"/"
      message
  with
  | Error error -> fail "public WSS" error
  | Ok echoed when String.equal echoed message ->
    Printf.printf "NETWORK_SPIKE_PUBLIC_WSS_OK\n%!"
  | Ok echoed -> fail "public WSS" ("unexpected echo: " ^ echoed)
;;
