module Protocol = Network_protocol
module Tls_client = Network_tls

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel))
;;

let fixture_path name =
  let path = Filename.concat "fixtures" name in
  if Sys.file_exists path
  then path
  else Alcotest.failf "network TLS fixture is missing: %s" name
;;

let cert_pem = read_file (fixture_path "localhost-cert.pem")
let key_pem = read_file (fixture_path "localhost-key.pem")

let decode_certificates value =
  match X509.Certificate.decode_pem_multiple value with
  | Ok certificates -> certificates
  | Error (`Msg message) -> Alcotest.fail message
;;

let decode_private_key value =
  match X509.Private_key.decode_pem value with
  | Ok key -> key
  | Error (`Msg message) -> Alcotest.fail message
;;

let certificates = decode_certificates cert_pem
let trust_anchor = List.hd (List.rev certificates)

let server_config_for certificates private_key =
  match
    Tls.Config.server
      ~certificates:(`Single (certificates, private_key))
      ~alpn_protocols:[ "http/1.1" ]
      ()
  with
  | Ok config -> config
  | Error (`Msg message) -> Alcotest.fail message
;;

let private_key = decode_private_key key_pem
let server_config () = server_config_for certificates private_key

let with_loopback_server server_handler client =
  Eio_posix.run (fun environment ->
    Eio.Switch.run (fun switch ->
      let net = Eio.Stdenv.net environment in
      let clock = Eio.Stdenv.mono_clock environment in
      let listener =
        Eio.Net.listen
          ~reuse_addr:true
          ~backlog:1
          ~sw:switch
          net
          (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
      in
      let address = Eio.Net.listening_addr listener in
      Eio.Fiber.fork ~sw:switch (fun () ->
        let flow, _peer = Eio.Net.accept ~sw:switch listener in
        try server_handler ~switch flow with
        | Tls_eio.Tls_alert _ | Tls_eio.Tls_failure _ | End_of_file -> ());
      client ~switch ~clock ~net address))
;;

let check_error label expected = function
  | Error actual when actual = expected -> ()
  | Error actual ->
    Alcotest.failf
      "%s: expected %s, received %s"
      label
      (Protocol.error_to_string expected)
      (Protocol.error_to_string actual)
  | Ok _ -> Alcotest.failf "%s unexpectedly succeeded" label
;;

let successful_connection ~switch ~clock ~net address =
  match
    Tls_client.connect_address
      ~sw:switch
      ~clock
      ~net
      ~address
      ~host:"localhost"
      ~trust:(Tls_client.Certificates [ trust_anchor ])
      ~timeout_seconds:1.
  with
  | Ok connection -> connection
  | Error error -> Alcotest.fail (Protocol.error_to_string error)
;;

let test_rng_is_initialized_once () =
  let before = Tls_client.For_testing.rng_initialization_count () in
  Tls_client.ensure_rng_initialized ();
  let after_first = Tls_client.For_testing.rng_initialization_count () in
  Tls_client.ensure_rng_initialized ();
  let after_second = Tls_client.For_testing.rng_initialization_count () in
  Alcotest.(check int) "one initialization" (before + 1) after_first;
  Alcotest.(check int) "second call is inert" after_first after_second
;;

let test_unknown_ca_is_classified () =
  with_loopback_server
    (fun ~switch:_ flow ->
       ignore (Tls_eio.server_of_flow (server_config ()) flow : Tls_eio.t))
    (fun ~switch ~clock ~net address ->
       Tls_client.connect_address
         ~sw:switch
         ~clock
         ~net
         ~address
         ~host:"localhost"
         ~trust:Tls_client.Nss
         ~timeout_seconds:1.
       |> check_error "unknown issuer" Protocol.Tls_unknown_issuer)
;;

let test_wrong_hostname_is_classified () =
  with_loopback_server
    (fun ~switch:_ flow ->
       ignore (Tls_eio.server_of_flow (server_config ()) flow : Tls_eio.t))
    (fun ~switch ~clock ~net address ->
       Tls_client.connect_address
         ~sw:switch
         ~clock
         ~net
         ~address
         ~host:"wrong.example"
         ~trust:(Tls_client.Certificates [ trust_anchor ])
         ~timeout_seconds:1.
       |> check_error "wrong hostname" Protocol.Tls_hostname_mismatch)
;;

let make_expired_certificate () =
  let leaf = List.hd certificates in
  let subject = X509.Certificate.subject leaf in
  let request =
    match X509.Signing_request.create subject private_key with
    | Ok request -> request
    | Error (`Msg message) -> Alcotest.fail message
  in
  let timestamp seconds =
    match Ptime.of_float_s seconds with
    | Some value -> value
    | None -> Alcotest.fail "invalid expired-certificate timestamp"
  in
  match
    X509.Signing_request.sign
      request
      ~valid_from:(timestamp 0.)
      ~valid_until:(timestamp 86400.)
      private_key
      subject
  with
  | Ok certificate -> certificate
  | Error _ -> Alcotest.fail "failed to create the expired test certificate"
;;

let test_expired_certificate_is_classified () =
  let expired_certificate = make_expired_certificate () in
  with_loopback_server
    (fun ~switch:_ flow ->
       ignore
         (Tls_eio.server_of_flow
            (server_config_for [ expired_certificate ] private_key)
            flow
          : Tls_eio.t))
    (fun ~switch ~clock ~net address ->
       Tls_client.connect_address
         ~sw:switch
         ~clock
         ~net
         ~address
         ~host:"localhost"
         ~trust:(Tls_client.Certificates [ expired_certificate ])
         ~timeout_seconds:1.
       |> check_error "expired certificate" Protocol.Tls_expired_certificate)
;;

let test_peer_alert_is_classified () =
  with_loopback_server
    (fun ~switch:_ flow ->
       Eio.Flow.copy_string "\x15\x03\x03\x00\x02\x02\x28" flow;
       Eio.Flow.shutdown flow `Send)
    (fun ~switch ~clock ~net address ->
       Tls_client.connect_address
         ~sw:switch
         ~clock
         ~net
         ~address
         ~host:"localhost"
         ~trust:(Tls_client.Certificates [ trust_anchor ])
         ~timeout_seconds:1.
       |> check_error "peer alert" Protocol.Tls_peer_alert)
;;

let test_premature_eof_is_classified () =
  with_loopback_server
    (fun ~switch:_ flow -> Eio.Resource.close flow)
    (fun ~switch ~clock ~net address ->
       Tls_client.connect_address
         ~sw:switch
         ~clock
         ~net
         ~address
         ~host:"localhost"
         ~trust:(Tls_client.Certificates [ trust_anchor ])
         ~timeout_seconds:1.
       |> check_error "premature EOF" Protocol.Tls_premature_eof)
;;

let test_protocol_failure_is_classified () =
  with_loopback_server
    (fun ~switch:_ flow ->
       Eio.Flow.copy_string "\xff\x03\x03\x00\x00" flow;
       let buffer = Cstruct.create 1 in
       try
         while true do
           ignore (Eio.Flow.single_read flow buffer : int)
         done
       with
       | End_of_file | Eio.Io _ -> ())
    (fun ~switch ~clock ~net address ->
       Tls_client.connect_address
         ~sw:switch
         ~clock
         ~net
         ~address
         ~host:"localhost"
         ~trust:(Tls_client.Certificates [ trust_anchor ])
         ~timeout_seconds:1.
       |> check_error "protocol failure" Protocol.Tls_protocol_error)
;;

let test_adapter_delegates_flow_capabilities () =
  with_loopback_server
    (fun ~switch:_ flow ->
       let tls = Tls_eio.server_of_flow (server_config ()) flow in
       let request = Cstruct.create 4 in
       let bytes = Eio.Flow.single_read tls request in
       Alcotest.(check string)
         "server request"
         "ping"
         (Cstruct.to_string (Cstruct.sub request 0 bytes));
       Eio.Flow.copy_string "pong" tls)
    (fun ~switch ~clock ~net address ->
       let connection = successful_connection ~switch ~clock ~net address in
       let socket = Tls_client.stream_socket connection in
       Eio.Flow.copy_string "ping" socket;
       let response = Cstruct.create 4 in
       let bytes = Eio.Flow.single_read socket response in
       Alcotest.(check string)
         "client response"
         "pong"
         (Cstruct.to_string (Cstruct.sub response 0 bytes)))
;;

let drain_until_closed flow closed_resolver =
  try
    let buffer = Cstruct.create 4096 in
    while true do
      ignore (Eio.Flow.single_read flow buffer : int)
    done
  with
  | End_of_file -> Eio.Promise.resolve closed_resolver true
  | _ -> Eio.Promise.resolve closed_resolver false
;;

let test_handshake_timeout_closes_transport () =
  let closed, closed_resolver = Eio.Promise.create () in
  with_loopback_server
    (fun ~switch:_ flow -> drain_until_closed flow closed_resolver)
    (fun ~switch ~clock ~net address ->
       Tls_client.connect_address
         ~sw:switch
         ~clock
         ~net
         ~address
         ~host:"localhost"
         ~trust:Tls_client.Nss
         ~timeout_seconds:0.02
       |> check_error "handshake timeout" Protocol.Timeout;
       Alcotest.(check bool) "timed-out socket closed" true (Eio.Promise.await closed))
;;

let test_explicit_close_closes_transport () =
  let closed, closed_resolver = Eio.Promise.create () in
  with_loopback_server
    (fun ~switch:_ flow ->
       let tls = Tls_eio.server_of_flow (server_config ()) flow in
       drain_until_closed tls closed_resolver)
    (fun ~switch ~clock ~net address ->
       let connection = successful_connection ~switch ~clock ~net address in
       Tls_client.close connection;
       Alcotest.(check bool) "TLS transport closed" true (Eio.Promise.await closed))
;;

exception Cancel_probe

let test_cancellation_closes_transport () =
  let closed, closed_resolver = Eio.Promise.create () in
  with_loopback_server
    (fun ~switch:_ flow -> drain_until_closed flow closed_resolver)
    (fun ~switch ~clock ~net address ->
       (try
          Eio.Switch.run (fun request_switch ->
            Eio.Fiber.fork ~sw:switch (fun () ->
              Eio.Time.Mono.sleep clock 0.02;
              Eio.Switch.fail request_switch Cancel_probe);
            ignore
              (Tls_client.connect_address
                 ~sw:request_switch
                 ~clock
                 ~net
                 ~address
                 ~host:"localhost"
                 ~trust:Tls_client.Nss
                 ~timeout_seconds:1.))
        with
        | Cancel_probe -> ());
       Alcotest.(check bool) "cancelled socket closed" true (Eio.Promise.await closed))
;;

let () =
  Alcotest.run
    "network TLS"
    [ ( "Configuration"
      , [ Alcotest.test_case "initializes RNG once" `Quick test_rng_is_initialized_once
        ; Alcotest.test_case "classifies unknown CA" `Quick test_unknown_ca_is_classified
        ; Alcotest.test_case
            "classifies wrong hostname"
            `Quick
            test_wrong_hostname_is_classified
        ; Alcotest.test_case
            "classifies expired certificates"
            `Quick
            test_expired_certificate_is_classified
        ; Alcotest.test_case "classifies peer alerts" `Quick test_peer_alert_is_classified
        ; Alcotest.test_case
            "classifies premature EOF"
            `Quick
            test_premature_eof_is_classified
        ; Alcotest.test_case
            "classifies protocol failures"
            `Quick
            test_protocol_failure_is_classified
        ] )
    ; ( "Resources"
      , [ Alcotest.test_case
            "delegates adapter capabilities"
            `Quick
            test_adapter_delegates_flow_capabilities
        ; Alcotest.test_case
            "times out and closes transport"
            `Quick
            test_handshake_timeout_closes_transport
        ; Alcotest.test_case
            "explicit close closes transport"
            `Quick
            test_explicit_close_closes_transport
        ; Alcotest.test_case
            "cancellation closes transport"
            `Quick
            test_cancellation_closes_transport
        ] )
    ]
;;
