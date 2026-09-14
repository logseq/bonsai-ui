type trust =
  | Nss
  | Certificates of X509.Certificate.t list

type t =
  { tls : Tls_eio.t
  ; mutable closed : bool
  }

let rng_initialized = ref false
let rng_initialization_count = ref 0

let ensure_rng_initialized () =
  if not !rng_initialized
  then (
    Mirage_crypto_rng_unix.use_default ();
    rng_initialized := true;
    incr rng_initialization_count)
;;

let current_time () = Ptime.of_float_s (Unix.gettimeofday ())

let domain_name host =
  match Domain_name.of_string host with
  | Error (`Msg _) -> Error Network_protocol.Invalid_uri
  | Ok name ->
    (match Domain_name.host name with
     | Error (`Msg _) -> Error Network_protocol.Invalid_uri
     | Ok host -> Ok host)
;;

let authenticator = function
  | Nss ->
    (match Ca_certs_nss.authenticator () with
     | Ok authenticator -> Ok authenticator
     | Error (`Msg message) -> Error (Network_protocol.Transport_error message))
  | Certificates certificates ->
    Ok (X509.Authenticator.chain_of_trust ~time:current_time certificates)
;;

let client_config ~host ~trust =
  match domain_name host, authenticator trust with
  | Error error, _ | _, Error error -> Error error
  | Ok peer_name, Ok authenticator ->
    (match
       Tls.Config.client ~authenticator ~peer_name ~alpn_protocols:[ "http/1.1" ] ()
     with
     | Ok config -> Ok (config, peer_name)
     | Error (`Msg message) -> Error (Network_protocol.Transport_error message))
;;

let error_of_validation = function
  | `LeafInvalidName _ -> Network_protocol.Tls_hostname_mismatch
  | `LeafCertificateExpired _ -> Network_protocol.Tls_expired_certificate
  | `InvalidChain | `EmptyCertificateChain -> Network_protocol.Tls_unknown_issuer
  | `LeafInvalidIP _
  | `LeafInvalidVersion _
  | `LeafInvalidExtensions _
  | `InvalidFingerprint _
  | `Bad_signature _
  | `Bad_encoding _
  | `Hash_not_allowed _
  | `Unsupported_keytype _
  | `Unsupported_algorithm _
  | `Msg _ -> Network_protocol.Tls_protocol_error
;;

exception Handshake_premature_eof

let error_of_exception = function
  | Eio.Time.Timeout -> Network_protocol.Timeout
  | Tls_eio.Tls_alert _ -> Network_protocol.Tls_peer_alert
  | Tls_eio.Tls_failure (`Error (`AuthenticationFailure validation_error)) ->
    error_of_validation validation_error
  | Tls_eio.Tls_failure (`Alert _) -> Network_protocol.Tls_peer_alert
  | Tls_eio.Tls_failure _ -> Network_protocol.Tls_protocol_error
  | End_of_file | Handshake_premature_eof -> Network_protocol.Tls_premature_eof
  | exn -> Network_protocol.Transport_error (Printexc.to_string exn)
;;

let close connection =
  if not connection.closed
  then (
    connection.closed <- true;
    (try Eio.Flow.shutdown connection.tls `All with
     | _ -> ());
    try Eio.Resource.close connection.tls with
    | _ -> ())
;;

module Tls_stream_socket = struct
  type t = Tls_eio.t
  type tag = [ `Generic ]

  let read_methods = []
  let single_read = Eio.Flow.single_read
  let single_write = Eio.Flow.single_write
  let copy flow ~src = Eio.Flow.copy src flow
  let shutdown = Eio.Flow.shutdown
  let close = Eio.Resource.close
end

let stream_socket connection =
  (Eio.Resource.T (connection.tls, Eio.Net.Pi.stream_socket (module Tls_stream_socket))
   : [ `Generic ] Eio.Net.stream_socket_ty Eio.Resource.t)
;;

let connect_address ~sw ~clock ~net ~address ~host ~trust ~timeout_seconds =
  ensure_rng_initialized ();
  match client_config ~host ~trust with
  | Error error -> Error error
  | Ok (config, peer_name) ->
    let raw_flow = ref None in
    let close_raw () =
      match !raw_flow with
      | None -> ()
      | Some flow ->
        (try Eio.Resource.close flow with
         | _ -> ())
    in
    (try
       Eio.Time.Timeout.run_exn
         (Eio.Time.Timeout.seconds clock timeout_seconds)
         (fun () ->
            let flow = Eio.Net.connect ~sw net address in
            raw_flow := Some flow;
            let tls =
              try Tls_eio.client_of_flow config ~host:peer_name flow with
              | Eio.Io _ -> raise Handshake_premature_eof
            in
            let connection = { tls; closed = false } in
            Eio.Switch.on_release sw (fun () -> close connection);
            Ok connection)
     with
     | Eio.Cancel.Cancelled _ as exn ->
       close_raw ();
       raise exn
     | exn ->
       close_raw ();
       Error (error_of_exception exn))
;;

let connect ~sw ~clock ~net ~endpoint =
  try
    Eio.Time.Timeout.run_exn
      (Eio.Time.Timeout.seconds clock Network_policy.connect_timeout_seconds)
      (fun () ->
         let addresses =
           Eio.Net.getaddrinfo_stream
             ~service:(string_of_int endpoint.Network_policy.port)
             net
             endpoint.host
         in
         let rec try_addresses last_error = function
           | [] -> Error (Option.value ~default:Network_protocol.Dns_failure last_error)
           | address :: rest ->
             (match
                connect_address
                  ~sw
                  ~clock
                  ~net
                  ~address
                  ~host:endpoint.host
                  ~trust:Nss
                  ~timeout_seconds:Network_policy.connect_timeout_seconds
              with
              | Ok connection -> Ok connection
              | Error
                  (( Network_protocol.Tls_unknown_issuer
                   | Tls_expired_certificate
                   | Tls_hostname_mismatch
                   | Tls_peer_alert
                   | Tls_premature_eof
                   | Tls_protocol_error ) as error) -> Error error
              | Error error -> try_addresses (Some error) rest)
         in
         try_addresses None addresses)
  with
  | Eio.Cancel.Cancelled _ as exn -> raise exn
  | Eio.Time.Timeout -> Error Network_protocol.Timeout
  | _ -> Error Network_protocol.Dns_failure
;;

module For_testing = struct
  let rng_initialization_count () = !rng_initialization_count
end
