type connector =
  sw:Eio.Switch.t
  -> clock:Worker.mono_clock
  -> endpoint:Network_policy.endpoint
  -> (Network_tls.t, Network_protocol.error) result

type response =
  { summary : Network_protocol.https_summary
  ; location : string option
  }

exception Headers_too_large
exception Too_many_informational_responses

type filtered_flow =
  { source : [ `Generic ] Eio.Net.stream_socket_ty Eio.Resource.t
  ; mutable pending : string
  ; mutable inspecting_headers : bool
  ; mutable informational_count : int
  ; mutable filter_error : Network_protocol.error option
  }

let find_header_end value =
  let rec loop index =
    if index + 3 >= String.length value
    then None
    else if
      value.[index] = '\r'
      && value.[index + 1] = '\n'
      && value.[index + 2] = '\r'
      && value.[index + 3] = '\n'
    then Some (index + 4)
    else loop (index + 1)
  in
  loop 0
;;

let status_code header =
  match String.index_opt header '\r' with
  | None -> None
  | Some line_end ->
    let line = String.sub header 0 line_end in
    (match String.split_on_char ' ' line with
     | _version :: code :: _ -> int_of_string_opt code
     | _ -> None)
;;

let rec inspect_headers flow =
  match find_header_end flow.pending with
  | None ->
    if String.length flow.pending > Network_policy.maximum_header_bytes
    then (
      flow.filter_error <- Some Network_protocol.Headers_too_large;
      raise Headers_too_large);
    let chunk = Cstruct.create 4096 in
    let bytes = Eio.Flow.single_read flow.source chunk in
    flow.pending <- flow.pending ^ Cstruct.to_string (Cstruct.sub chunk 0 bytes);
    inspect_headers flow
  | Some header_end ->
    if header_end > Network_policy.maximum_header_bytes
    then (
      flow.filter_error <- Some Network_protocol.Headers_too_large;
      raise Headers_too_large);
    let header = String.sub flow.pending 0 header_end in
    (match status_code header with
     | Some code when code >= 100 && code < 200 && code <> 101 ->
       flow.informational_count <- flow.informational_count + 1;
       if flow.informational_count > 8
       then (
         flow.filter_error <- Some Network_protocol.Http_protocol_error;
         raise Too_many_informational_responses);
       flow.pending
       <- String.sub flow.pending header_end (String.length flow.pending - header_end);
       inspect_headers flow
     | _ -> flow.inspecting_headers <- false)
;;

let copy_pending flow destination =
  let bytes = min (String.length flow.pending) (Cstruct.length destination) in
  Cstruct.blit_from_string flow.pending 0 destination 0 bytes;
  flow.pending <- String.sub flow.pending bytes (String.length flow.pending - bytes);
  bytes
;;

module Filtered_stream_socket = struct
  type t = filtered_flow
  type tag = [ `Generic ]

  let read_methods = []

  let single_read flow destination =
    if flow.inspecting_headers then inspect_headers flow;
    if String.length flow.pending > 0
    then copy_pending flow destination
    else Eio.Flow.single_read flow.source destination
  ;;

  let single_write flow = Eio.Flow.single_write flow.source
  let copy flow ~src = Eio.Flow.copy src flow.source
  let shutdown flow = Eio.Flow.shutdown flow.source
  let close flow = Eio.Resource.close flow.source
end

let filtered_socket tls =
  let flow =
    { source = Network_tls.stream_socket tls
    ; pending = ""
    ; inspecting_headers = true
    ; informational_count = 0
    ; filter_error = None
    }
  in
  ( (Eio.Resource.T (flow, Eio.Net.Pi.stream_socket (module Filtered_stream_socket))
     : [ `Generic ] Eio.Net.stream_socket_ty Eio.Resource.t)
  , flow )
;;

let resolve_once resolver resolved value =
  if not !resolved
  then (
    resolved := true;
    Eio.Promise.resolve resolver value)
;;

let http_error = function
  | `Exn Headers_too_large -> Network_protocol.Headers_too_large
  | `Exn Too_many_informational_responses -> Network_protocol.Http_protocol_error
  | `Malformed_response _ | `Invalid_response_body_length _ | `Exn _ ->
    Network_protocol.Http_protocol_error
;;

let header_bytes (response : Httpun.Response.t) =
  let status_line_bytes =
    String.length (Httpun.Version.to_string response.version)
    + 1
    + 3
    + 1
    + String.length response.reason
    + 2
  in
  Httpun.Headers.fold
    ~f:(fun name value total -> total + String.length name + 2 + String.length value + 2)
    ~init:(status_line_bytes + 2)
    response.headers
;;

let fixed_body_exceeds_limit (response : Httpun.Response.t) =
  match Httpun.Response.body_length ~request_method:`GET response with
  | `Fixed length ->
    Int64.compare length (Int64.of_int Network_policy.maximum_body_bytes) > 0
  | `Chunked | `Close_delimited | `Error _ -> false
;;

let response_of_body (response : Httpun.Response.t) body =
  { summary =
      { Network_protocol.status_code = Httpun.Status.to_code response.status
      ; content_type = Httpun.Headers.get response.headers "content-type"
      ; body_bytes = String.length body
      ; preview =
          Network_policy.truncate_preview
            ~max_bytes:Network_policy.maximum_preview_bytes
            body
      }
  ; location = Httpun.Headers.get response.headers "location"
  }
;;

let perform_request ~sw ~clock ~connect endpoint =
  match connect ~sw ~clock ~endpoint with
  | Error error -> Error error
  | Ok tls ->
    let socket, filtered_flow = filtered_socket tls in
    let client = Httpun_eio.Client.create_connection ~sw socket in
    let result, resolver = Eio.Promise.create () in
    let resolved = ref false in
    let response_handler response body =
      if Httpun.Status.is_informational response.Httpun.Response.status
      then ()
      else if header_bytes response > Network_policy.maximum_header_bytes
      then (
        Httpun.Body.Reader.close body;
        resolve_once resolver resolved (Error Network_protocol.Headers_too_large))
      else if fixed_body_exceeds_limit response
      then (
        Httpun.Body.Reader.close body;
        resolve_once resolver resolved (Error Network_protocol.Response_too_large))
      else (
        let buffer = Buffer.create 1024 in
        let rec read () =
          Httpun.Body.Reader.schedule_read
            body
            ~on_eof:(fun () ->
              resolve_once
                resolver
                resolved
                (Ok (response_of_body response (Buffer.contents buffer))))
            ~on_read:(fun chunk ~off ~len ->
              if Buffer.length buffer + len > Network_policy.maximum_body_bytes
              then (
                Httpun.Body.Reader.close body;
                resolve_once resolver resolved (Error Network_protocol.Response_too_large))
              else (
                Buffer.add_string buffer (Bigstringaf.substring chunk ~off ~len);
                read ()))
        in
        read ())
    in
    let request =
      Httpun.Request.create
        ~headers:
          (Httpun.Headers.of_list
             [ "host", endpoint.Network_policy.authority
             ; "accept", "*/*"
             ; "connection", "close"
             ; "user-agent", "bonsai-swiftui-network-example/1"
             ])
        `GET
        endpoint.resource
    in
    let request_body =
      Httpun_eio.Client.request
        client
        request
        ~error_handler:(fun error ->
          let error =
            Option.value ~default:(http_error error) filtered_flow.filter_error
          in
          resolve_once resolver resolved (Error error))
        ~response_handler
    in
    Httpun.Body.Writer.close request_body;
    Eio.Promise.await result
;;

let is_redirect status_code =
  status_code = 301
  || status_code = 302
  || status_code = 303
  || status_code = 307
  || status_code = 308
;;

let get
      ~sw
      ~clock
      ~connect
      ?(timeout_seconds = Network_policy.request_timeout_seconds)
      endpoint
  =
  try
    Eio.Switch.check sw;
    Eio.Time.Timeout.run_exn (Eio.Time.Timeout.seconds clock timeout_seconds) (fun () ->
      let rec follow redirect_count endpoint =
        let response =
          Eio.Switch.run (fun request_switch ->
            perform_request ~sw:request_switch ~clock ~connect endpoint)
        in
        match response with
        | Error error -> Error error
        | Ok { summary; location = Some location }
          when is_redirect summary.Network_protocol.status_code ->
          (match Network_policy.redirect ~current:endpoint ~location ~redirect_count with
           | Error error -> Error error
           | Ok redirected -> follow (redirect_count + 1) redirected)
        | Ok { summary; _ } -> Ok summary
      in
      follow 0 endpoint)
  with
  | Eio.Cancel.Cancelled _ as exn -> raise exn
  | Eio.Time.Timeout -> Error Network_protocol.Timeout
  | _ -> Error Network_protocol.Http_protocol_error
;;

let get_default ~sw ~clock ~net endpoint =
  get
    ~sw
    ~clock
    ~connect:(fun ~sw ~clock ~endpoint -> Network_tls.connect ~sw ~clock ~net ~endpoint)
    endpoint
;;
