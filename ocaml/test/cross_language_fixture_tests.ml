module Protocol = Bonsai_swiftui_protocol
module ID = Bonsai_swiftui_spec.Id

let epoch = ID.Runtime.Epoch.of_int64
let sequence = ID.Runtime.Event_sequence.of_int64
let revision = ID.Runtime.Renderer_revision.of_int64
let node = ID.Ui.Node_id.of_int64
let handler = ID.Ui.Handler_id.of_int64
let fail format = Printf.ksprintf failwith format

let expect condition format =
  Printf.ksprintf (fun message -> if not condition then failwith message) format
;;

let bytes_of_hex text =
  let digit = function
    | '0' .. '9' as value -> Char.code value - Char.code '0'
    | 'a' .. 'f' as value -> 10 + Char.code value - Char.code 'a'
    | 'A' .. 'F' as value -> 10 + Char.code value - Char.code 'A'
    | value -> fail "invalid hex digit %C" value
  in
  let compact =
    text
    |> String.to_seq
    |> Seq.filter (fun value -> not (Char.equal value ' ' || Char.equal value '\n'))
    |> String.of_seq
  in
  expect (String.length compact mod 2 = 0) "hex fixture has an odd number of digits";
  Bytes.init
    (String.length compact / 2)
    (fun index ->
       let offset = index * 2 in
       Char.chr ((digit compact.[offset] lsl 4) lor digit compact.[offset + 1]))
;;

let fixture name =
  let rec find_repository_root directory =
    let marker = Filename.concat directory ".git" in
    if Sys.file_exists marker
    then Some directory
    else (
      let parent = Filename.dirname directory in
      if String.equal parent directory then None else find_repository_root parent)
  in
  let path =
    match find_repository_root (Sys.getcwd ()) with
    | Some root -> Filename.concat root ("protocol/generated/fixtures/" ^ name)
    | None -> fail "cannot locate the repository root for fixture %s" name
  in
  if not (Sys.file_exists path)
  then fail "missing Swift-generated cross-language fixture: %s" name;
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel) |> bytes_of_hex)
;;

let expect_fixture name expected =
  let encoded = fixture name in
  let decoded =
    match Protocol.Event_batch_codec.decode encoded with
    | Ok batch -> batch
    | Error error -> fail "%s decode failed: %s" name error.message
  in
  expect (decoded = expected) "%s decoded to unexpected events" name;
  match Protocol.Event_batch_codec.encode expected with
  | Error error -> fail "%s encode failed: %s" name error.message
  | Ok reencoded ->
    if not (Bytes.equal encoded reencoded)
    then (
      let limit = min (Bytes.length encoded) (Bytes.length reencoded) in
      let rec first_difference index =
        if index = limit
        then None
        else if Char.equal (Bytes.get encoded index) (Bytes.get reencoded index)
        then first_difference (index + 1)
        else Some index
      in
      match first_difference 0 with
      | None ->
        fail
          "OCaml and Swift encoded different lengths for %s: Swift=%d OCaml=%d"
          name
          (Bytes.length encoded)
          (Bytes.length reencoded)
      | Some index ->
        fail
          "OCaml and Swift encoded different bytes for %s at offset %d: Swift=%02x \
           OCaml=%02x"
          name
          index
          (Char.code (Bytes.get encoded index))
          (Char.code (Bytes.get reencoded index)))
;;

let test_counter_press () =
  let open Protocol.Inbound_event in
  expect_fixture
    "swift_counter_press.hex"
    { runtime_epoch = epoch 21L
    ; events =
        [ { sequence = sequence 1L
          ; displayed_revision = revision 1L
          ; node_id = node 3L
          ; handler_id = handler 9001L
          ; event_tag = Protocol.Generated_protocol.Event_tag.press
          ; payload = Unit
          }
        ]
    }
;;

let test_host_response () =
  let open Protocol.Inbound_event in
  expect_fixture
    "swift_host_response.hex"
    { runtime_epoch = epoch 31L
    ; events =
        [ { sequence = sequence 2L
          ; displayed_revision = revision 3L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Protocol.Generated_protocol.Event_tag.host_response
          ; payload =
              Host_response
                { request_id = ID.Host.Request_id.of_int64 44L
                ; status = Host_error
                ; value = Bytes.of_string "denied: 剪贴板😀"
                }
          }
        ]
    }
;;

let test_text_edit_unicode () =
  let open Protocol.Inbound_event in
  expect_fixture
    "swift_text_edit_unicode.hex"
    { runtime_epoch = epoch 22L
    ; events =
        [ { sequence = sequence 3L
          ; displayed_revision = revision 2L
          ; node_id = node 4L
          ; handler_id = handler 44L
          ; event_tag = Protocol.Generated_protocol.Event_tag.text_edit
          ; payload =
              Text_edit
                { session_id = ID.Text_input.Session_id.of_int64 7L
                ; local_revision = ID.Text_input.Local_revision.of_int64 3L
                ; base_document_revision = ID.Text_input.Document_revision.of_int64 2L
                ; text = "拼😀音"
                ; selection = { start_utf16 = 4; end_utf16 = 4 }
                ; composing = Some { start_utf16 = 0; end_utf16 = 4 }
                }
          }
        ]
    }
;;

let test_text_limit_reached () =
  let open Protocol.Inbound_event in
  expect_fixture
    "swift_text_limit_reached.hex"
    { runtime_epoch = epoch 22L
    ; events =
        [ { sequence = sequence 4L
          ; displayed_revision = revision 2L
          ; node_id = node 4L
          ; handler_id = handler 45L
          ; event_tag = Protocol.Generated_protocol.Event_tag.text_limit_reached
          ; payload = Unit
          }
        ]
    }
;;

let test_environment_changed () =
  let open Protocol.Inbound_event in
  expect_fixture
    "swift_environment_changed.hex"
    { runtime_epoch = epoch 31L
    ; events =
        [ { sequence = sequence 4L
          ; displayed_revision = revision 3L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Protocol.Generated_protocol.Event_tag.environment_changed
          ; payload =
              Environment_changed
                { viewport_width = 1440.
                ; viewport_height = 900.
                ; device_pixel_ratio = 2.
                ; text_scale = 1.25
                ; brightness = Environment_dark
                ; platform = "macos"
                ; locale = "zh-CN"
                ; safe_area = { left = 0.; top = 24.; right = 0.; bottom = 0. }
                ; keyboard_insets = { left = 0.; top = 0.; right = 0.; bottom = 280. }
                ; accessible_navigation = false
                ; bold_text = true
                ; invert_colors = false
                ; disable_animations = false
                ; reduced_motion = true
                ; high_contrast = true
                ; orientation = Landscape
                ; pointer_kinds = 10
                }
          }
        ]
    }
;;

let test_application_response () =
  let open Protocol.Inbound_event in
  expect_fixture
    "swift_application_response.hex"
    { runtime_epoch = epoch 41L
    ; events =
        [ { sequence = sequence 8L
          ; displayed_revision = revision 9L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Protocol.Generated_protocol.Event_tag.application_response
          ; payload =
              Application_response
                { request_id = 501L; payload = Bytes.of_string "\000opaque\255" }
          }
        ]
    }
;;

let test_application_event () =
  let open Protocol.Inbound_event in
  expect_fixture
    "swift_application_event.hex"
    { runtime_epoch = epoch 41L
    ; events =
        [ { sequence = sequence 9L
          ; displayed_revision = revision 9L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Protocol.Generated_protocol.Event_tag.application_event
          ; payload = Application_event (Bytes.of_string "\128\000event")
          }
        ]
    }
;;

let () =
  test_counter_press ();
  test_host_response ();
  test_text_edit_unicode ();
  test_text_limit_reached ();
  test_environment_changed ();
  test_application_response ();
  test_application_event ();
  print_endline "cross-language fixture tests passed"
;;
