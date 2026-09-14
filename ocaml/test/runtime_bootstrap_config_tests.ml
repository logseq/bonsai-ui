module ID = Bonsai_swiftui_spec.Id

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message
let entrypoint = ID.Application.Entrypoint_name.to_string

let set_u16_le bytes offset value =
  Bytes.set_uint8 bytes offset (value land 0xff);
  Bytes.set_uint8 bytes (offset + 1) ((value lsr 8) land 0xff)
;;

let set_u32_le bytes offset value =
  for index = 0 to 3 do
    Bytes.set_uint8 bytes (offset + index) ((value lsr (index * 8)) land 0xff)
  done
;;

let envelope ?(major = 1) ?(minor = 0) ?(policy = 0) ?(reserved = 0) ~entrypoint payload =
  let entrypoint = Bytes.of_string entrypoint in
  let bytes = Bytes.create (20 + Bytes.length entrypoint + Bytes.length payload) in
  Bytes.blit_string "BSR1" 0 bytes 0 4;
  set_u16_le bytes 4 major;
  set_u16_le bytes 6 minor;
  Bytes.set_uint8 bytes 8 policy;
  Bytes.set_uint8 bytes 9 reserved;
  Bytes.set_uint8 bytes 10 0;
  Bytes.set_uint8 bytes 11 0;
  set_u32_le bytes 12 (Bytes.length entrypoint);
  set_u32_le bytes 16 (Bytes.length payload);
  Bytes.blit entrypoint 0 bytes 20 (Bytes.length entrypoint);
  Bytes.blit payload 0 bytes (20 + Bytes.length entrypoint) (Bytes.length payload);
  bytes
;;

let decoded bytes =
  match Runtime_bootstrap_config.decode bytes with
  | Ok decoded -> decoded
  | Error error -> fail "unexpected decode failure: %s" error
;;

let require_error bytes expected =
  match Runtime_bootstrap_config.decode bytes with
  | Error error ->
    require
      (Core.String.is_substring error ~substring:expected)
      (Printf.sprintf "decode error %S did not contain %S" error expected)
  | Ok _ -> fail "malformed startup envelope was accepted"
;;

let () =
  let payload = Bytes.of_string "opaque\000payload" in
  let fresh = decoded (envelope ~entrypoint:"counter" payload) in
  require (entrypoint fresh.entrypoint = "counter") "Fresh entrypoint was not decoded";
  require
    (fresh.launch_policy = Runtime_bootstrap_config.Fresh)
    "Fresh launch policy byte was not decoded";
  require (Bytes.equal fresh.application_payload payload) "opaque payload changed";
  let replace = decoded (envelope ~policy:1 ~entrypoint:"counter" Bytes.empty) in
  require
    (replace.launch_policy = Runtime_bootstrap_config.Replace_existing)
    "Replace_existing launch policy byte was not decoded";
  require_error (Bytes.of_string "legacy-entrypoint") "magic";
  let old_envelope = envelope ~entrypoint:"counter" Bytes.empty in
  Bytes.blit_string "BFR1" 0 old_envelope 0 4;
  require_error old_envelope "magic";
  require_error (envelope ~minor:1 ~entrypoint:"counter" Bytes.empty) "minor";
  require_error (Bytes.of_string "BSR1") "truncated";
  require_error (envelope ~major:2 ~entrypoint:"counter" Bytes.empty) "major";
  require_error (envelope ~policy:2 ~entrypoint:"counter" Bytes.empty) "policy";
  require_error (envelope ~reserved:1 ~entrypoint:"counter" Bytes.empty) "reserved";
  require_error (envelope ~entrypoint:"" Bytes.empty) "empty";
  require_error (envelope ~entrypoint:"nul\000name" Bytes.empty) "NUL";
  require_error (envelope ~entrypoint:(String.make 256 'a') Bytes.empty) "255";
  require_error (envelope ~entrypoint:"\255" Bytes.empty) "UTF-8";
  require_error
    (envelope ~entrypoint:"counter" (Bytes.make ((1024 * 1024) + 1) 'x'))
    "1 MiB";
  let maximum_payload = Bytes.make (1024 * 1024) 'x' in
  let maximum = decoded (envelope ~entrypoint:"counter" maximum_payload) in
  require
    (Bytes.equal maximum.application_payload maximum_payload)
    "1 MiB application payload changed";
  let oversized_declaration = envelope ~entrypoint:"counter" Bytes.empty in
  set_u32_le oversized_declaration 16 ((1024 * 1024) + 1);
  require_error oversized_declaration "1 MiB";
  let trailing =
    Bytes.cat (envelope ~entrypoint:"counter" Bytes.empty) (Bytes.of_string "x")
  in
  require_error trailing "length";
  let truncated = envelope ~entrypoint:"counter" Bytes.empty in
  set_u32_le truncated 12 255;
  require_error truncated "length";
  let overflow = envelope ~entrypoint:"counter" Bytes.empty in
  Bytes.fill overflow 12 4 '\255';
  require_error overflow "255"
;;
