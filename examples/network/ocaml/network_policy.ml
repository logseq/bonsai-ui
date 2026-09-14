type expected_scheme =
  [ `Https
  | `Wss
  ]

type endpoint =
  { uri : string
  ; scheme : expected_scheme
  ; host : string
  ; port : int
  ; authority : string
  ; resource : string
  }

let maximum_header_bytes = 16 * 1024
let maximum_body_bytes = 64 * 1024
let maximum_message_bytes = 64 * 1024
let maximum_preview_bytes = 4 * 1024
let maximum_transcript_entries = 50
let maximum_redirects = 3
let connect_timeout_seconds = 10.
let request_timeout_seconds = 10.

let scheme_name = function
  | `Https -> "https"
  | `Wss -> "wss"
;;

let default_port = function
  | `Https -> 443
  | `Wss -> 443
;;

let authority ~host ~port ~default_port =
  let rendered_host = if String.contains host ':' then "[" ^ host ^ "]" else host in
  if port = default_port then rendered_host else Printf.sprintf "%s:%d" rendered_host port
;;

let validate_endpoint ~expected value =
  try
    if not (String.is_valid_utf_8 value)
    then Error Network_protocol.Invalid_uri
    else (
      let parsed = Uri.of_string value in
      match Uri.scheme parsed with
      | None -> Error Network_protocol.Invalid_uri
      | Some raw_scheme ->
        let actual_scheme = String.lowercase_ascii raw_scheme in
        let required_scheme = scheme_name expected in
        if not (String.equal actual_scheme required_scheme)
        then Error (Network_protocol.Unsupported_scheme actual_scheme)
        else if Option.is_some (Uri.userinfo parsed)
        then Error Network_protocol.Userinfo_not_allowed
        else if Option.is_some (Uri.fragment parsed)
        then Error Network_protocol.Fragment_not_allowed
        else (
          match Uri.host parsed with
          | None | Some "" -> Error Network_protocol.Missing_host
          | Some raw_host ->
            let host = String.lowercase_ascii raw_host in
            let default_port = default_port expected in
            let port = Option.value ~default:default_port (Uri.port parsed) in
            if port < 1 || port > 65535
            then Error Network_protocol.Invalid_port
            else (
              let normalized =
                parsed
                |> fun uri ->
                Uri.with_scheme uri (Some required_scheme)
                |> fun uri ->
                Uri.with_host uri (Some host)
                |> fun uri ->
                Uri.with_port uri (if port = default_port then None else Some port)
              in
              let normalized =
                if String.equal (Uri.path normalized) ""
                then Uri.with_path normalized "/"
                else normalized
              in
              Ok
                { uri = Uri.to_string normalized
                ; scheme = expected
                ; host
                ; port
                ; authority = authority ~host ~port ~default_port
                ; resource = Uri.path_and_query normalized
                })))
  with
  | _ -> Error Network_protocol.Invalid_uri
;;

let redirect ~current ~location ~redirect_count =
  if redirect_count >= maximum_redirects
  then Error Network_protocol.Too_many_redirects
  else (
    try
      let resolved =
        Uri.resolve
          (scheme_name current.scheme)
          (Uri.of_string current.uri)
          (Uri.of_string location)
      in
      match Uri.scheme resolved with
      | Some scheme when not (String.equal (String.lowercase_ascii scheme) "https") ->
        Error Network_protocol.Insecure_redirect
      | _ -> validate_endpoint ~expected:`Https (Uri.to_string resolved)
    with
    | _ -> Error Network_protocol.Invalid_uri)
;;

let check_size ~maximum ~error bytes = if bytes > maximum then Error error else Ok ()

let check_header_size bytes =
  check_size ~maximum:maximum_header_bytes ~error:Network_protocol.Headers_too_large bytes
;;

let check_body_size bytes =
  check_size ~maximum:maximum_body_bytes ~error:Network_protocol.Response_too_large bytes
;;

let check_message_size bytes =
  check_size
    ~maximum:maximum_message_bytes
    ~error:Network_protocol.Message_too_large
    bytes
;;

let truncate_preview ~max_bytes value =
  let limit = min (max 0 max_bytes) (String.length value) in
  let rec loop offset last_valid =
    if offset >= limit
    then String.sub value 0 last_valid
    else (
      let decoded = String.get_utf_8_uchar value offset in
      if not (Uchar.utf_decode_is_valid decoded)
      then String.sub value 0 last_valid
      else (
        let next = offset + Uchar.utf_decode_length decoded in
        if next > limit then String.sub value 0 last_valid else loop next next))
  in
  loop 0 0
;;

type transcript_entry =
  { generation : int
  ; text : string
  }

let rec drop count values =
  if count <= 0
  then values
  else (
    match values with
    | [] -> []
    | _ :: rest -> drop (count - 1) rest)
;;

let add_transcript entries entry =
  let entries = entries @ [ entry ] in
  let overflow = List.length entries - maximum_transcript_entries in
  drop overflow entries
;;

let is_current_generation ~active ~event = active = event

let next_generation generation =
  if generation < 0 || generation = max_int
  then Error Network_protocol.Busy
  else Ok (generation + 1)
;;
