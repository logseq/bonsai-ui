let register () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "network")
    Network_example.app;
  match Sys.getenv_opt "BONSAI_NATIVE_NETWORK_PORT" with
  | None -> ()
  | Some value ->
    let port = int_of_string value in
    if port < 1 || port > 65535 then invalid_arg "Invalid native network test port";
    let certificate_path = Sys.getenv "BONSAI_NATIVE_NETWORK_CERTIFICATE" in
    let channel = open_in_bin certificate_path in
    let pem =
      Fun.protect
        ~finally:(fun () -> close_in channel)
        (fun () -> really_input_string channel (in_channel_length channel))
    in
    let certificates =
      match X509.Certificate.decode_pem_multiple pem with
      | Ok certificates -> certificates
      | Error (`Msg message) -> failwith message
    in
    let trust_anchor =
      match List.rev certificates with
      | certificate :: _ -> certificate
      | [] -> failwith "Missing network test trust anchor"
    in
    let connect net ~sw ~clock ~endpoint:_ =
      Network_tls.connect_address
        ~sw
        ~clock
        ~net
        ~address:(`Tcp (Eio.Net.Ipaddr.V4.loopback, port))
        ~host:"localhost"
        ~trust:(Network_tls.Certificates [ trust_anchor ])
        ~timeout_seconds:3.
    in
    let providers =
      Network_service.
        { https_get =
            (fun ~sw ~clock ~net endpoint ->
              Network_http.get
                ~sw
                ~clock
                ~connect:(connect net)
                ~timeout_seconds:8.
                endpoint)
        ; websocket =
            (fun ~sw ~clock ~net ~emit ->
              let socket =
                Network_websocket.create ~sw ~clock ~connect:(connect net) ~emit ()
              in
              { run = (fun () -> Network_websocket.run socket)
              ; connect = Network_websocket.connect socket
              ; send = Network_websocket.send socket
              ; disconnect = Network_websocket.disconnect socket
              ; shutdown = (fun () -> Network_websocket.shutdown socket)
              })
        }
    in
    let app =
      Network_example.create
        ~https_endpoint:(Printf.sprintf "https://localhost:%d/request" port)
        ~websocket_endpoint:(Printf.sprintf "wss://localhost:%d/socket" port)
        ~service:(Network_service.create providers)
        ()
    in
    Native_backend.embed
      ~name:
        (Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "network-loopback")
      app
;;
