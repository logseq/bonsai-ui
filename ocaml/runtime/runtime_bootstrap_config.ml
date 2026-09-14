module ID = Bonsai_swiftui_spec.Id

type launch_policy =
  | Fresh
  | Replace_existing

type t =
  { entrypoint : ID.Application.entrypoint_name
  ; launch_policy : launch_policy
  ; application_payload : bytes
  }

let header_length = 20
let maximum_entrypoint_length = 255
let maximum_payload_length = 1024 * 1024

let has_magic bytes =
  Bytes.length bytes >= 4
  && Bytes.get bytes 0 = 'B'
  && Bytes.get bytes 1 = 'S'
  && Bytes.get bytes 2 = 'R'
  && Bytes.get bytes 3 = '1'
;;

let get_u16_le bytes offset =
  Bytes.get_uint8 bytes offset lor (Bytes.get_uint8 bytes (offset + 1) lsl 8)
;;

let get_u32_le bytes offset =
  let value = ref 0L in
  for index = 0 to 3 do
    value
    := Int64.logor
         !value
         (Int64.shift_left
            (Int64.of_int (Bytes.get_uint8 bytes (offset + index)))
            (index * 8))
  done;
  !value
;;

let validate_entrypoint entrypoint =
  let length = String.length entrypoint in
  if length = 0
  then Error "Startup entrypoint must not be empty"
  else if length > maximum_entrypoint_length
  then Error "Startup entrypoint must be at most 255 bytes"
  else if String.contains entrypoint '\000'
  then Error "Startup entrypoint must not contain NUL"
  else if not (String.is_valid_utf_8 entrypoint)
  then Error "Startup entrypoint must be valid UTF-8"
  else Ok (ID.Application.Entrypoint_name.of_string entrypoint)
;;

let decode_versioned bytes =
  let length = Bytes.length bytes in
  if length < header_length
  then Error "Startup envelope is truncated"
  else if get_u16_le bytes 4 <> 1
  then Error "Unsupported startup envelope major version"
  else if get_u16_le bytes 6 <> 0
  then Error "Unsupported startup envelope minor version"
  else if
    Bytes.get_uint8 bytes 9 <> 0
    || Bytes.get_uint8 bytes 10 <> 0
    || Bytes.get_uint8 bytes 11 <> 0
  then Error "Startup envelope reserved bytes must be zero"
  else (
    let launch_policy =
      match Bytes.get_uint8 bytes 8 with
      | 0 -> Ok Fresh
      | 1 -> Ok Replace_existing
      | _ -> Error "Unknown startup launch policy"
    in
    let entrypoint_length = get_u32_le bytes 12 in
    let payload_length = get_u32_le bytes 16 in
    let total_length =
      Int64.add (Int64.of_int header_length) (Int64.add entrypoint_length payload_length)
    in
    if Int64.compare entrypoint_length (Int64.of_int maximum_entrypoint_length) > 0
    then Error "Startup entrypoint must be at most 255 bytes"
    else if Int64.compare payload_length (Int64.of_int maximum_payload_length) > 0
    then Error "Startup application payload must be at most 1 MiB"
    else if not (Int64.equal total_length (Int64.of_int length))
    then Error "Startup envelope length does not match its contents"
    else (
      match launch_policy with
      | Error _ as error -> error
      | Ok launch_policy ->
        let entrypoint_length = Int64.to_int entrypoint_length in
        let payload_length = Int64.to_int payload_length in
        let entrypoint = Bytes.sub_string bytes header_length entrypoint_length in
        (match validate_entrypoint entrypoint with
         | Error _ as error -> error
         | Ok entrypoint ->
           let application_payload =
             Bytes.sub bytes (header_length + entrypoint_length) payload_length
           in
           Ok { entrypoint; launch_policy; application_payload })))
;;

let decode bytes =
  if has_magic bytes
  then decode_versioned bytes
  else Error "Invalid startup envelope magic; expected BSR1"
;;
