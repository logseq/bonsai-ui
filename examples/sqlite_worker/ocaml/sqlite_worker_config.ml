type t =
  { database_path : string
  ; application_support_directory : string
  }

let magic = "SWC1"
let header_size = 12

let set_u32_le bytes offset value =
  for byte = 0 to 3 do
    Bytes.set bytes (offset + byte) (Char.chr ((value lsr (byte * 8)) land 0xff))
  done
;;

let get_u32_le bytes offset =
  let value = ref 0 in
  for byte = 0 to 3 do
    value := !value lor (Char.code (Bytes.get bytes (offset + byte)) lsl (byte * 8))
  done;
  !value
;;

let encode t =
  let database_length = String.length t.database_path in
  let directory_length = String.length t.application_support_directory in
  let bytes = Bytes.create (header_size + database_length + directory_length) in
  Bytes.blit_string magic 0 bytes 0 4;
  set_u32_le bytes 4 database_length;
  set_u32_le bytes 8 directory_length;
  Bytes.blit_string t.database_path 0 bytes header_size database_length;
  Bytes.blit_string
    t.application_support_directory
    0
    bytes
    (header_size + database_length)
    directory_length;
  bytes
;;

let validate_path name path =
  if String.equal path ""
  then Error (name ^ " must not be empty")
  else if String.contains path '\000'
  then Error (name ^ " must not contain NUL")
  else if Filename.is_relative path
  then Error (name ^ " must be absolute")
  else Ok ()
;;

let decode bytes =
  let length = Bytes.length bytes in
  if length < header_size || not (Bytes.sub_string bytes 0 4 = magic)
  then Error "Invalid SQLite Worker application payload magic"
  else (
    let database_length = get_u32_le bytes 4 in
    let directory_length = get_u32_le bytes 8 in
    if
      database_length > length - header_size
      || directory_length > length - header_size - database_length
      || header_size + database_length + directory_length <> length
    then Error "Invalid SQLite Worker application payload lengths"
    else (
      let database_path = Bytes.sub_string bytes header_size database_length in
      let application_support_directory =
        Bytes.sub_string bytes (header_size + database_length) directory_length
      in
      match
        ( validate_path "SQLite database path" database_path
        , validate_path
            "SQLite Worker Application Support directory"
            application_support_directory )
      with
      | Ok (), Ok () -> Ok { database_path; application_support_directory }
      | Error error, _ | _, Error error -> Error error))
;;
