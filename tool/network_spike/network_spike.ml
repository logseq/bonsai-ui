type trust =
  [ `Nss
  | `Test_certificate
  ]

let () = Mirage_crypto_rng_unix.use_default ()

let error_message = function
  | `Msg message -> message
;;

let or_error = function
  | Ok value -> value
  | Error error -> failwith (error_message error)
;;

let protect_result f =
  try Ok (f ()) with
  | exn -> Error (Printexc.to_string exn)
;;

let decode_certificates cert_pem =
  X509.Certificate.decode_pem_multiple cert_pem |> or_error
;;

let decode_private_key key_pem = X509.Private_key.decode_pem key_pem |> or_error
let current_time () = Ptime.of_float_s (Unix.gettimeofday ())

let domain_name host =
  Domain_name.of_string host |> or_error |> Domain_name.host |> or_error
;;

let server_config ~cert_pem ~key_pem =
  let certificates = decode_certificates cert_pem in
  let private_key = decode_private_key key_pem in
  Tls.Config.server
    ~certificates:(`Single (certificates, private_key))
    ~alpn_protocols:[ "http/1.1" ]
    ()
  |> or_error
;;

let client_config ~cert_pem ~trust ~host =
  let peer_name = domain_name host in
  let authenticator =
    match trust with
    | `Nss -> Ca_certs_nss.authenticator () |> or_error
    | `Test_certificate ->
      let certificates = decode_certificates cert_pem in
      let trust_anchor = List.hd (List.rev certificates) in
      X509.Authenticator.chain_of_trust ~time:current_time [ trust_anchor ]
  in
  let config =
    Tls.Config.client ~authenticator ~peer_name ~alpn_protocols:[ "http/1.1" ] ()
    |> or_error
  in
  config, peer_name
;;

module Tls_stream_socket = struct
  type t = Tls_eio.t
  type tag = [ `Generic ]

  let read_methods = []
  let single_read = Eio.Flow.single_read
  let single_write = Eio.Flow.single_write
  let copy t ~src = Eio.Flow.copy src t
  let shutdown = Eio.Flow.shutdown
  let close = Eio.Resource.close
end

let stream_socket tls =
  (Eio.Resource.T (tls, Eio.Net.Pi.stream_socket (module Tls_stream_socket))
   : [ `Generic ] Eio.Net.stream_socket_ty Eio.Resource.t)
;;

let with_loopback_tls_server ~cert_pem ~key_pem ~server_handler client =
  Eio_posix.run (fun environment ->
    Eio.Switch.run (fun switch ->
      let net = Eio.Stdenv.net environment in
      let listener =
        Eio.Net.listen
          ~reuse_addr:true
          ~backlog:1
          ~sw:switch
          net
          (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
      in
      let address = Eio.Net.listening_addr listener in
      let config = server_config ~cert_pem ~key_pem in
      Eio.Fiber.fork ~sw:switch (fun () ->
        try
          let raw_flow, peer = Eio.Net.accept ~sw:switch listener in
          let tls = Tls_eio.server_of_flow config raw_flow in
          server_handler ~switch ~peer tls
        with
        | _ -> ());
      client ~switch ~net address))
;;

let connect_tls ~switch ~net ~address ~cert_pem ~trust ~host =
  let raw_flow = Eio.Net.connect ~sw:switch net address in
  let config, peer_name = client_config ~cert_pem ~trust ~host in
  Tls_eio.client_of_flow config ~host:peer_name raw_flow
;;

let tls_handshake ~cert_pem ~key_pem ~trust ~host =
  protect_result (fun () ->
    with_loopback_tls_server
      ~cert_pem
      ~key_pem
      ~server_handler:(fun ~switch:_ ~peer:_ tls -> Eio.Resource.close tls)
      (fun ~switch ~net address ->
         let tls = connect_tls ~switch ~net ~address ~cert_pem ~trust ~host in
         Eio.Resource.close tls))
;;

let resolve_once resolver resolved value =
  if not !resolved
  then (
    resolved := true;
    Eio.Promise.resolve resolver value)
;;

let http_error_message = function
  | `Malformed_response message -> "malformed response: " ^ message
  | `Invalid_response_body_length _ -> "invalid response body length"
  | `Exn exn -> Printexc.to_string exn
;;

let maximum_body_bytes = 64 * 1024

let https_get_on_tls ~switch ~host ~resource tls =
  let client = Httpun_eio.Client.create_connection ~sw:switch (stream_socket tls) in
  let response_promise, response_resolver = Eio.Promise.create () in
  let resolved = ref false in
  let response_handler _response body =
    let buffer = Buffer.create 256 in
    let rec read () =
      Httpun.Body.Reader.schedule_read
        body
        ~on_eof:(fun () ->
          resolve_once response_resolver resolved (Ok (Buffer.contents buffer)))
        ~on_read:(fun bigstring ~off ~len ->
          if Buffer.length buffer + len > maximum_body_bytes
          then (
            Httpun.Body.Reader.close body;
            resolve_once
              response_resolver
              resolved
              (Error "HTTPS response exceeds 64 KiB"))
          else (
            Buffer.add_string buffer (Bigstringaf.substring bigstring ~off ~len);
            read ()))
    in
    read ()
  in
  let request =
    Httpun.Request.create
      ~headers:(Httpun.Headers.of_list [ "host", host; "connection", "close" ])
      `GET
      resource
  in
  let request_body =
    Httpun_eio.Client.request
      client
      request
      ~error_handler:(fun error ->
        resolve_once response_resolver resolved (Error (http_error_message error)))
      ~response_handler
  in
  Httpun.Body.Writer.close request_body;
  match Eio.Promise.await response_promise with
  | Ok body -> body
  | Error message -> failwith message
;;

let https_server_handler ~switch ~peer tls =
  let request_handler _peer (request : Httpun.Reqd.t Gluten.Reqd.t) =
    let response =
      Httpun.Response.create
        ~headers:(Httpun.Headers.of_list [ "connection", "close" ])
        `OK
    in
    Httpun.Reqd.respond_with_string request.reqd response "secure hello"
  in
  let error_handler _peer ?request:_ _error respond =
    let body = respond (Httpun.Headers.of_list [ "connection", "close" ]) in
    Httpun.Body.Writer.write_string body "HTTP server error";
    Httpun.Body.Writer.close body
  in
  Httpun_eio.Server.create_connection_handler
    ~request_handler
    ~error_handler
    ~sw:switch
    peer
    (stream_socket tls)
;;

let https_get ~cert_pem ~key_pem =
  protect_result (fun () ->
    with_loopback_tls_server
      ~cert_pem
      ~key_pem
      ~server_handler:https_server_handler
      (fun ~switch ~net address ->
         let tls =
           connect_tls
             ~switch
             ~net
             ~address
             ~cert_pem
             ~trust:`Test_certificate
             ~host:"localhost"
         in
         https_get_on_tls ~switch ~host:"localhost" ~resource:"/" tls))
;;

exception Cancel_https

let https_cancel_closes_transport ~cert_pem ~key_pem =
  protect_result (fun () ->
    let server_closed = ref false in
    with_loopback_tls_server
      ~cert_pem
      ~key_pem
      ~server_handler:(fun ~switch:_ ~peer:_ tls ->
        try
          let buffer = Cstruct.create 1 in
          ignore (Eio.Flow.single_read tls buffer : int)
        with
        | End_of_file | Eio.Cancel.Cancelled _ -> server_closed := true)
      (fun ~switch:_ ~net address ->
         (try
            Eio.Switch.run (fun request_switch ->
              let tls =
                connect_tls
                  ~switch:request_switch
                  ~net
                  ~address
                  ~cert_pem
                  ~trust:`Test_certificate
                  ~host:"localhost"
              in
              ignore (stream_socket tls);
              raise Cancel_https)
          with
          | Cancel_https -> ());
         Eio.Fiber.yield ());
    !server_closed)
;;

let sha1 value = value |> Digestif.SHA1.digest_string |> Digestif.SHA1.to_raw_string

let websocket_echo_handler _peer wsd =
  let frame ~opcode ~is_fin:_ ~len:_ payload =
    match (opcode : Httpun_ws.Websocket.Opcode.t) with
    | #Httpun_ws.Websocket.Opcode.standard_non_control as kind ->
      Httpun_ws.Payload.schedule_read
        payload
        ~on_eof:ignore
        ~on_read:(fun bigstring ~off ~len ->
          Httpun_ws.Wsd.schedule wsd bigstring ~kind ~off ~len)
    | `Connection_close -> Httpun_ws.Wsd.close wsd
    | `Ping -> Httpun_ws.Wsd.send_pong wsd
    | `Pong | `Other _ -> ()
  in
  let eof ?error:_ () = Httpun_ws.Wsd.close wsd in
  { Httpun_ws.Websocket_connection.frame; eof }
;;

let websocket_server_handler ~switch ~peer tls =
  let error_handler _peer ?request:_ _error respond =
    let body = respond Httpun.Headers.empty in
    Httpun.Body.Writer.close body
  in
  let request_handler peer (request : Httpun.Reqd.t Gluten.Reqd.t) =
    let upgrade () =
      let connection =
        Httpun_ws.Server_connection.create_websocket (websocket_echo_handler peer)
      in
      request.upgrade (Gluten.make (module Httpun_ws.Server_connection) connection)
    in
    match Httpun_ws.Handshake.respond_with_upgrade ~sha1 request.reqd upgrade with
    | Ok () -> ()
    | Error message ->
      let response =
        Httpun.Response.create
          ~headers:(Httpun.Headers.of_list [ "connection", "close" ])
          `Bad_request
      in
      Httpun.Reqd.respond_with_string request.reqd response message
  in
  Httpun_eio.Server.create_connection_handler
    ~request_handler
    ~error_handler
    ~sw:switch
    peer
    (stream_socket tls)
;;

let wss_echo_on_tls ~switch ~host ~port ~resource ~message tls =
  let result_promise, result_resolver = Eio.Promise.create () in
  let resolved = ref false in
  let websocket_handler wsd =
    let payload = Bytes.of_string message in
    Httpun_ws.Wsd.send_bytes wsd ~kind:`Text payload ~off:0 ~len:(Bytes.length payload);
    let frame ~opcode ~is_fin:_ ~len:_ payload =
      match (opcode : Httpun_ws.Websocket.Opcode.t) with
      | `Text ->
        Httpun_ws.Payload.schedule_read
          payload
          ~on_eof:ignore
          ~on_read:(fun bigstring ~off ~len ->
            if len <= maximum_body_bytes
            then (
              let echoed = Bigstringaf.substring bigstring ~off ~len in
              if String.equal echoed message
              then (
                resolve_once result_resolver resolved (Ok echoed);
                Httpun_ws.Wsd.close wsd)))
      | `Connection_close -> Httpun_ws.Wsd.close wsd
      | `Ping -> Httpun_ws.Wsd.send_pong wsd
      | `Continuation | `Binary | `Pong | `Other _ -> ()
    in
    let eof ?error () =
      match error with
      | None ->
        resolve_once result_resolver resolved (Error "WebSocket closed before echo")
      | Some (`Exn exn) ->
        resolve_once result_resolver resolved (Error (Printexc.to_string exn))
    in
    { Httpun_ws.Websocket_connection.frame; eof }
  in
  let connection =
    Httpun_ws.Client_connection.connect
      ~nonce:(Mirage_crypto_rng.generate 16)
      ~headers:
        (Httpun.Headers.of_list
           [ "host", String.concat ":" [ host; string_of_int port ] ])
      ~sha1
      ~error_handler:(fun _ ->
        resolve_once result_resolver resolved (Error "WebSocket handshake failed"))
      ~websocket_handler
      resource
  in
  let runtime =
    Gluten_eio.Client.create
      ~sw:switch
      ~read_buffer_size:Httpun.Config.default.read_buffer_size
      ~protocol:(module Httpun_ws.Client_connection)
      connection
      (stream_socket tls)
  in
  let result = Eio.Promise.await result_promise in
  ignore (Eio.Promise.await (Gluten_eio.Client.shutdown runtime) : unit);
  match result with
  | Ok echoed -> echoed
  | Error message -> failwith message
;;

let wss_echo ~cert_pem ~key_pem message =
  protect_result (fun () ->
    with_loopback_tls_server
      ~cert_pem
      ~key_pem
      ~server_handler:websocket_server_handler
      (fun ~switch ~net address ->
         let tls =
           connect_tls
             ~switch
             ~net
             ~address
             ~cert_pem
             ~trust:`Test_certificate
             ~host:"localhost"
         in
         wss_echo_on_tls ~switch ~host:"localhost" ~port:443 ~resource:"/" ~message tls))
;;

let wss_disconnect_closes_transport ~cert_pem ~key_pem =
  match wss_echo ~cert_pem ~key_pem "disconnect probe" with
  | Ok _ -> Ok true
  | Error message -> Error message
;;

let with_public_tls ~host ~port operation =
  Eio_posix.run (fun environment ->
    Eio.Switch.run (fun switch ->
      let net = Eio.Stdenv.net environment in
      let wall_clock = Eio.Stdenv.clock environment in
      let mono_clock = Eio.Stdenv.mono_clock environment in
      Eio.Time.with_timeout_exn wall_clock 10.0 (fun () ->
        Eio.Net.with_tcp_connect
          ~timeout:(Eio.Time.Timeout.seconds mono_clock 10.0)
          ~host
          ~service:(string_of_int port)
          net
          (fun raw_flow ->
             let config, peer_name = client_config ~cert_pem:"" ~trust:`Nss ~host in
             let tls = Tls_eio.client_of_flow config ~host:peer_name raw_flow in
             Fun.protect
               ~finally:(fun () -> Eio.Resource.close tls)
               (fun () -> operation ~switch tls)))))
;;

let public_https_get ~host ~port ~resource =
  protect_result (fun () ->
    with_public_tls ~host ~port (fun ~switch tls ->
      https_get_on_tls ~switch ~host ~resource tls))
;;

let public_wss_echo ~host ~port ~resource message =
  protect_result (fun () ->
    with_public_tls ~host ~port (fun ~switch tls ->
      wss_echo_on_tls ~switch ~host ~port ~resource ~message tls))
;;
