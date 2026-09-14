module Http = Network_http
module Policy = Network_policy
module Protocol = Network_protocol

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
  else Alcotest.failf "network HTTP fixture is missing: %s" name
;;

let cert_pem = read_file (fixture_path "localhost-cert.pem")
let key_pem = read_file (fixture_path "localhost-key.pem")

let decode_certificates value =
  match X509.Certificate.decode_pem_multiple value with
  | Ok certificates -> certificates
  | Error (`Msg message) -> Alcotest.fail message
;;

let certificates = decode_certificates cert_pem
let trust_anchor = List.hd (List.rev certificates)

let server_config () =
  let private_key =
    match X509.Private_key.decode_pem key_pem with
    | Ok key -> key
    | Error (`Msg message) -> Alcotest.fail message
  in
  match
    Tls.Config.server
      ~certificates:(`Single (certificates, private_key))
      ~alpn_protocols:[ "http/1.1" ]
      ()
  with
  | Ok config -> config
  | Error (`Msg message) -> Alcotest.fail message
;;

let read_request flow =
  let buffer = Buffer.create 256 in
  let chunk = Cstruct.create 1024 in
  let rec loop () =
    if String.ends_with ~suffix:"\r\n\r\n" (Buffer.contents buffer)
    then Buffer.contents buffer
    else (
      let bytes = Eio.Flow.single_read flow chunk in
      Buffer.add_string buffer (Cstruct.to_string (Cstruct.sub chunk 0 bytes));
      loop ())
  in
  loop ()
;;

let close_quietly flow =
  try Eio.Resource.close flow with
  | _ -> ()
;;

let respond response request_callback tls =
  let request = read_request tls in
  request_callback request;
  Eio.Flow.copy_string response tls;
  Eio.Flow.shutdown tls `Send;
  (try
     let buffer = Cstruct.create 1 in
     while true do
       ignore (Eio.Flow.single_read tls buffer : int)
     done
   with
   | End_of_file | Eio.Io _ -> ());
  close_quietly tls
;;

let with_server handlers client =
  Eio_posix.run (fun environment ->
    Eio.Switch.run (fun switch ->
      let net = Eio.Stdenv.net environment in
      let clock = Eio.Stdenv.mono_clock environment in
      let listener =
        Eio.Net.listen
          ~reuse_addr:true
          ~backlog:(max 1 (List.length handlers))
          ~sw:switch
          net
          (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
      in
      let address = Eio.Net.listening_addr listener in
      Eio.Fiber.fork ~sw:switch (fun () ->
        List.iter
          (fun handler ->
             let flow, _peer = Eio.Net.accept ~sw:switch listener in
             try
               let tls = Tls_eio.server_of_flow (server_config ()) flow in
               handler ~clock tls
             with
             | Tls_eio.Tls_alert _
             | Tls_eio.Tls_failure _
             | Eio.Cancel.Cancelled _
             | Eio.Io _
             | End_of_file -> ())
          handlers);
      client ~switch ~clock ~net address))
;;

let port_of_address = function
  | `Tcp (_, port) -> port
  | `Unix _ -> Alcotest.fail "expected a TCP test listener"
;;

let endpoint address resource =
  let uri = Printf.sprintf "https://localhost:%d%s" (port_of_address address) resource in
  match Policy.validate_endpoint ~expected:`Https uri with
  | Ok endpoint -> endpoint
  | Error error -> Alcotest.fail (Protocol.error_to_string error)
;;

let connector net address ~sw ~clock ~endpoint:_ =
  Network_tls.connect_address
    ~sw
    ~clock
    ~net
    ~address
    ~host:"localhost"
    ~trust:(Network_tls.Certificates [ trust_anchor ])
    ~timeout_seconds:1.
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

let get ~switch ~clock ~net address ?timeout_seconds resource =
  Http.get
    ~sw:switch
    ~clock:(clock :> Worker.mono_clock)
    ~connect:(connector (net :> Worker.net) address)
    ?timeout_seconds
    (endpoint address resource)
;;

let test_success_and_request_format () =
  let response =
    "HTTP/1.1 200 OK\r\n\
     Content-Type: text/plain\r\n\
     Content-Length: 12\r\n\
     Connection: close\r\n\
     \r\n\
     secure hello"
  in
  with_server
    [ (fun ~clock:_ tls ->
        respond
          response
          (fun request ->
             Alcotest.(check bool)
               "origin-form request"
               true
               (String.starts_with ~prefix:"GET /hello?q=1 HTTP/1.1\r\n" request);
             Alcotest.(check bool)
               "connection closes"
               true
               (String.lowercase_ascii request
                |> String.split_on_char '\n'
                |> List.exists (fun line -> String.equal line "connection: close\r")))
          tls)
    ]
    (fun ~switch ~clock ~net address ->
       match get ~switch ~clock ~net address "/hello?q=1" with
       | Error error -> Alcotest.fail (Protocol.error_to_string error)
       | Ok summary ->
         Alcotest.(check int) "status" 200 summary.status_code;
         Alcotest.(check (option string))
           "content type"
           (Some "text/plain")
           summary.content_type;
         Alcotest.(check int) "body bytes" 12 summary.body_bytes;
         Alcotest.(check string) "preview" "secure hello" summary.preview)
;;

let test_empty_body () =
  with_server
    [ (fun ~clock:_ tls ->
        respond "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n" ignore tls)
    ]
    (fun ~switch ~clock ~net address ->
       match get ~switch ~clock ~net address "/empty" with
       | Error error -> Alcotest.fail (Protocol.error_to_string error)
       | Ok summary ->
         Alcotest.(check int) "status" 204 summary.status_code;
         Alcotest.(check int) "empty body" 0 summary.body_bytes;
         Alcotest.(check string) "empty preview" "" summary.preview)
;;

let test_informational_response () =
  with_server
    [ (fun ~clock:_ tls ->
        respond
          "HTTP/1.1 100 Continue\r\n\
           \r\n\
           HTTP/1.1 200 OK\r\n\
           Content-Length: 2\r\n\
           Connection: close\r\n\
           \r\n\
           ok"
          ignore
          tls)
    ]
    (fun ~switch ~clock ~net address ->
       match get ~switch ~clock ~net address "/continue" with
       | Error error -> Alcotest.fail (Protocol.error_to_string error)
       | Ok summary ->
         Alcotest.(check int) "final status" 200 summary.status_code;
         Alcotest.(check string) "final body" "ok" summary.preview)
;;

let test_preview_is_bounded () =
  let body = String.make (Policy.maximum_preview_bytes + 7) 'p' in
  let response =
    Printf.sprintf
      "HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s"
      (String.length body)
      body
  in
  with_server
    [ (fun ~clock:_ tls -> respond response ignore tls) ]
    (fun ~switch ~clock ~net address ->
       match get ~switch ~clock ~net address "/preview" with
       | Error error -> Alcotest.fail (Protocol.error_to_string error)
       | Ok summary ->
         Alcotest.(check int) "full byte count" (String.length body) summary.body_bytes;
         Alcotest.(check int)
           "bounded preview"
           Policy.maximum_preview_bytes
           (String.length summary.preview))
;;

let test_header_limit () =
  let response =
    Printf.sprintf
      "HTTP/1.1 200 OK\r\nX-Large: %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
      (String.make Policy.maximum_header_bytes 'h')
  in
  with_server
    [ (fun ~clock:_ tls -> respond response ignore tls) ]
    (fun ~switch ~clock ~net address ->
       get ~switch ~clock ~net address "/large-header"
       |> check_error "header limit" Protocol.Headers_too_large)
;;

let test_body_limit () =
  let body = String.make (Policy.maximum_body_bytes + 1) 'b' in
  let response =
    Printf.sprintf
      "HTTP/1.1 200 OK\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s"
      (String.length body)
      body
  in
  with_server
    [ (fun ~clock:_ tls -> respond response ignore tls) ]
    (fun ~switch ~clock ~net address ->
       get ~switch ~clock ~net address "/large-body"
       |> check_error "body limit" Protocol.Response_too_large)
;;

let test_malformed_and_early_eof () =
  let run response expected =
    with_server
      [ (fun ~clock:_ tls -> respond response ignore tls) ]
      (fun ~switch ~clock ~net address ->
         get ~switch ~clock ~net address "/broken"
         |> check_error "malformed response" expected)
  in
  run "not an HTTP response" Protocol.Http_protocol_error;
  run
    "HTTP/1.1 200 OK\r\nContent-Length: 8\r\nConnection: close\r\n\r\nshort"
    Protocol.Http_protocol_error
;;

let redirect_response location =
  Printf.sprintf
    "HTTP/1.1 302 Found\r\nLocation: %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    location
;;

let test_redirects () =
  with_server
    [ (fun ~clock:_ tls -> respond (redirect_response "/final") ignore tls)
    ; (fun ~clock:_ tls ->
        respond
          "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nfinal"
          ignore
          tls)
    ]
    (fun ~switch ~clock ~net address ->
       match get ~switch ~clock ~net address "/start" with
       | Error error -> Alcotest.fail (Protocol.error_to_string error)
       | Ok summary -> Alcotest.(check string) "redirected body" "final" summary.preview);
  with_server
    [ (fun ~clock:_ tls ->
        respond (redirect_response "http://localhost/plain") ignore tls)
    ]
    (fun ~switch ~clock ~net address ->
       get ~switch ~clock ~net address "/downgrade"
       |> check_error "redirect downgrade" Protocol.Insecure_redirect);
  with_server
    (List.init 4 (fun _ ~clock:_ tls -> respond (redirect_response "/loop") ignore tls))
    (fun ~switch ~clock ~net address ->
       get ~switch ~clock ~net address "/loop"
       |> check_error "redirect loop" Protocol.Too_many_redirects)
;;

let drain_until_closed flow resolver =
  try
    let buffer = Cstruct.create 4096 in
    while true do
      ignore (Eio.Flow.single_read flow buffer : int)
    done
  with
  | End_of_file -> Eio.Promise.resolve resolver true
  | _ -> Eio.Promise.resolve resolver false
;;

let test_response_timeout_closes_transport () =
  let closed, closed_resolver = Eio.Promise.create () in
  with_server
    [ (fun ~clock:_ tls ->
        ignore (read_request tls : string);
        drain_until_closed tls closed_resolver)
    ]
    (fun ~switch ~clock ~net address ->
       get ~switch ~clock ~net address ~timeout_seconds:0.02 "/timeout"
       |> check_error "response timeout" Protocol.Timeout;
       Alcotest.(check bool) "timed-out transport closes" true (Eio.Promise.await closed))
;;

exception Cancel_http

let test_cancellation_closes_transport () =
  let closed, closed_resolver = Eio.Promise.create () in
  with_server
    [ (fun ~clock:_ tls ->
        ignore (read_request tls : string);
        drain_until_closed tls closed_resolver)
    ]
    (fun ~switch ~clock ~net address ->
       (try
          Eio.Switch.run (fun request_switch ->
            Eio.Fiber.fork ~sw:switch (fun () ->
              Eio.Time.Mono.sleep clock 0.02;
              Eio.Switch.fail request_switch Cancel_http);
            ignore
              (get
                 ~switch:request_switch
                 ~clock
                 ~net
                 address
                 ~timeout_seconds:1.
                 "/cancel"))
        with
        | Cancel_http -> ());
       Alcotest.(check bool) "cancelled transport closes" true (Eio.Promise.await closed))
;;

let () =
  Alcotest.run
    "network HTTP"
    [ ( "Success"
      , [ Alcotest.test_case
            "formats GET and summarizes response"
            `Quick
            test_success_and_request_format
        ; Alcotest.test_case "handles an empty body" `Quick test_empty_body
        ; Alcotest.test_case
            "handles informational responses"
            `Quick
            test_informational_response
        ; Alcotest.test_case "bounds the preview" `Quick test_preview_is_bounded
        ] )
    ; ( "Limits"
      , [ Alcotest.test_case "rejects oversized headers" `Quick test_header_limit
        ; Alcotest.test_case "rejects oversized bodies" `Quick test_body_limit
        ; Alcotest.test_case
            "rejects malformed and early EOF"
            `Quick
            test_malformed_and_early_eof
        ; Alcotest.test_case "follows only bounded secure redirects" `Quick test_redirects
        ] )
    ; ( "Lifecycle"
      , [ Alcotest.test_case
            "times out and closes"
            `Quick
            test_response_timeout_closes_transport
        ; Alcotest.test_case
            "cancels and closes"
            `Quick
            test_cancellation_closes_transport
        ] )
    ]
;;
