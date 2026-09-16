open Bonsai_swiftui_protocol
module ID = Bonsai_swiftui_spec.Id

let epoch = ID.Runtime.Epoch.of_int64
let revision = ID.Runtime.Renderer_revision.of_int64
let sequence = ID.Runtime.Event_sequence.of_int64
let node = ID.Ui.Node_id.of_int64
let handler = ID.Ui.Handler_id.of_int64
let request = ID.Host.Request_id.of_int64
let session = ID.Text_input.Session_id.of_int64
let document_revision = ID.Text_input.Document_revision.of_int64
let local_revision = ID.Text_input.Local_revision.of_int64
let animation = ID.Ui.Animation_id.of_int64
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

let fixture_named name =
  let path =
    let from_root = "protocol/generated/fixtures/" ^ name in
    if Sys.file_exists from_root
    then from_root
    else "../../protocol/generated/fixtures/" ^ name
  in
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel) |> bytes_of_hex)
;;

let fixture () = fixture_named "ocaml_counter_full.hex"

let counter_theme_operation =
  Wire_frame.Set_application_theme
    { title = Some "Counter"
    ; theme =
        { mode = System
        ; tint = Some 0xff6750a4l
        ; font_family = Some "Inter"
        ; control_size = 2
        ; defaults = Bytes.make 96 '\000'
        }
    }
;;

let counter_frame =
  Wire_frame.
    { runtime_epoch = epoch 7L
    ; base_revision = revision 0L
    ; target_revision = revision 1L
    ; kind = Full_snapshot
    ; operations =
        [ counter_theme_operation
        ; Create_node
            { node_id = node 1L
            ; kind = Column
            ; props = Column_props { spacing = None; alignment = 1 }
            ; event_bindings = []
            }
        ; Create_node
            { node_id = node 2L
            ; kind = Text
            ; props =
                Text_props
                  { value = "Count: 0"
                  ; style = None
                  ; text_align = Start
                  ; line_limit = None
                  ; truncation = Tail
                  }
            ; event_bindings = []
            }
        ; Set_children { node_id = node 1L; children = [ node 2L ] }
        ; Set_root (node 1L)
        ]
    }
;;

let test_retired_nodes_are_rejected () =
  let frame =
    { counter_frame with
      operations =
        [ Wire_frame.Create_node
            { node_id = node 1L
            ; kind = Column
            ; props = Column_props { spacing = None; alignment = 1 }
            ; event_bindings = []
            }
        ]
    }
  in
  let bytes =
    match Binary_codec.encode frame with
    | Ok bytes -> bytes
    | Error error -> fail "fixture encode: %s" error.message
  in
  let kind_offset = Generated_protocol.Limits.header_bytes + 5 + 5 + 8 in
  List.iter
    (fun kind ->
       let old = Bytes.copy bytes in
       Bytes.set old kind_offset (Char.chr kind);
       Bytes.set old (kind_offset + 1) '\x00';
       match Binary_codec.decode old with
       | Error { code = Binary_codec.Unknown_node_kind; _ } -> ()
       | Error error ->
         fail "retired node %d failed for wrong reason: %s" kind error.message
       | Ok _ -> fail "retired node %d decoded" kind)
    [ 30; 32; 33; 35; 36; 37; 70; 98; 99; 109; 110; 111; 114; 129; 131; 136 ]
;;

let test_retired_scroll_header_nodes_are_rejected () =
  List.iter
    (fun hex ->
       match Binary_codec.decode (bytes_of_hex hex) with
       | Error { code = Binary_codec.Unknown_node_kind; _ } -> ()
       | Error error ->
         fail "retired scroll header failed for wrong reason: %s" error.message
       | Ok _ -> fail "retired scroll header node was accepted")
    [ {|42 53 46 52 08 00 00 00 30 00 03 00
07 00 00 00 00 00 00 00 01 00 00 00
00 00 00 00 02 00 00 00 00 00 00 00
77 00 00 00 00 00 00 00 00 00 00 00
01 00 00 00 00 03 68 00 00 00 26 00
00 00 00 00 00 00 26 00 99 c0 c6 ff
01 00 00 00 00 01 01 01 01 56 34 12
ff 01 ef cd ab ff 02 00 00 00 01 01
0d 00 00 00 4e 61 74 69 76 65 20 68
65 61 64 65 72 01 00 00 00 00 00 28
69 40 01 00 00 00 00 00 50 54 40 00
00 00 00 00 c0 4f 40 01 01 01 00 00
00 00 00 a0 47 40 01 01 01 00 00 00
00 00 00 11 40 00 0a 00 00 00 00|}
    ; {|4253465208000000300003005a00000000000000010000000000000002000000000000002900000000000000000000000100000000031a0000000100000000000000270001000000000000000000000000c04a400a00000000|}
    ]
;;

let test_retired_navigation_bar_wire_is_rejected () =
  let bytes =
    bytes_of_hex
      {|
4253465208000000300003005a00000000000000010000000000000002000000
000000007b00000000000000000000000100000000036c000000010000000000
00007300ff0f00000000000000000000020004000000486f6d65010107000000
000110000000486f6d652064657374696e6174696f6e0800000053657474696e
67730000010000010201020000010001120000005072696d617279206e617669
676174696f6e0a00000000
|}
  in
  match Binary_codec.decode bytes with
  | Error { code = Binary_codec.Unknown_node_kind; _ } -> ()
  | Error error -> fail "retired navigation bar failed for wrong reason: %s" error.message
  | Ok _ -> fail "retired navigation bar node was accepted"
;;

let test_retired_route_wire_is_rejected () =
  let bytes =
    bytes_of_hex
      {|
42 53 46 52 08 00 00 00 30 00 03 00
49 00 00 00 00 00 00 00 04 00 00 00
00 00 00 00 05 00 00 00 00 00 00 00
a8 00 00 00 00 00 00 00 00 00 00 00
01 00 00 00 00 03 99 00 00 00 1e 00
00 00 00 00 00 00 43 00 ff fe ff 07
00 00 00 00 06 00 00 00 65 64 69 74
6f 72 00 01 01 0b 00 00 00 65 64 69
74 6f 72 2d 70 61 67 65 01 01 01 30
20 10 7f 01 0c 00 00 00 43 6c 6f 73
65 20 65 64 69 74 6f 72 02 01 01 45
01 00 00 af 00 00 00 02 00 01 01 13
00 00 00 41 64 6a 75 73 74 20 73 68
65 65 74 20 68 65 69 67 68 74 01 0b
00 00 00 48 61 6c 66 20 68 65 69 67
68 74 01 0b 00 00 00 46 75 6c 6c 20
68 65 69 67 68 74 00 00 00 00 00 00
00 00 00 00 00 00 00 0a 00 00 00 00
|}
  in
  match Binary_codec.decode bytes with
  | Error { code = Binary_codec.Unknown_node_kind; _ } -> ()
  | Error error -> fail "retired Page failed for the wrong reason: %s" error.message
  | Ok _ -> fail "retired Flutter Page node was accepted"
;;

let test_application_theme_round_trip () =
  List.iter
    (fun mode ->
       List.iter
         (fun control_size ->
            List.iter
              (fun (tint, font_family) ->
                 let theme : Wire_frame.theme =
                   { mode
                   ; tint
                   ; font_family
                   ; control_size
                   ; defaults = Bytes.make 96 '\000'
                   }
                 in
                 let frame =
                   { counter_frame with
                     operations =
                       [ Wire_frame.Set_application_theme
                           { title = Some "Theme test"; theme }
                       ]
                   }
                 in
                 match Binary_codec.encode frame with
                 | Error error -> fail "SwiftUI theme encode failed: %s" error.message
                 | Ok bytes ->
                   (match Binary_codec.decode bytes with
                    | Error error -> fail "SwiftUI theme decode failed: %s" error.message
                    | Ok decoded ->
                      expect
                        (decoded = frame)
                        "SwiftUI environment round trip changed values"))
              [ None, None; Some 0xff6750a4l, Some "Inter" ])
         [ 0; 1; 2; 3; 4 ])
    [ Wire_frame.System; Light; Dark ]
;;

let test_golden_fixture () =
  match Binary_codec.encode counter_frame with
  | Error error -> fail "encode failed: %s" error.message
  | Ok encoded -> expect (Bytes.equal encoded (fixture ())) "golden frame differs"
;;

let test_round_trip () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 7L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 2L
              ; props =
                  Text_props
                    { value = "计数: 1"
                    ; style = None
                    ; text_align = Start
                    ; line_limit = None
                    ; truncation = Tail
                    }
              }
          ]
      }
  in
  match Binary_codec.encode frame with
  | Error error -> fail "encode failed: %s" error.message
  | Ok encoded ->
    (match Binary_codec.decode encoded with
     | Error error -> fail "decode failed: %s" error.message
     | Ok decoded -> expect (decoded = frame) "round trip changed the incremental frame")
;;

let test_styled_text_props_round_trip () =
  let frame line_spacing truncation =
    let props =
      Wire_frame.Text_props
        { value = "Quarterly planning"
        ; style =
            Some
              { font_size = Some 16.
              ; font_weight = Some Semi_bold
              ; line_spacing
              ; role = 0
              ; foreground = None
              ; italic = Some false
              ; color = Some 0xff183758l
              }
        ; text_align = End
        ; line_limit = Some 2
        ; truncation
        }
    in
    Wire_frame.
      { counter_frame with
        operations =
          [ Create_node { node_id = node 1L; kind = Text; props; event_bindings = [] }
          ; Update_props { node_id = node 1L; props }
          ]
      }
  in
  List.iter
    (fun line_spacing ->
       List.iter
         (fun truncation ->
            let frame = frame line_spacing truncation in
            match Binary_codec.encode frame with
            | Error error -> fail "styled text encode failed: %s" error.message
            | Ok encoded ->
              (match Binary_codec.decode encoded with
               | Error error -> fail "styled text decode failed: %s" error.message
               | Ok decoded ->
                 expect
                   (decoded = frame)
                   "styled text round trip changed style, alignment, line limit, or \
                    truncation"))
         Wire_frame.[ Tail; Head; Middle ])
    [ None; Some 0.; Some 6. ];
  List.iter
    (fun line_spacing ->
       match Binary_codec.encode (frame (Some line_spacing) Wire_frame.Tail) with
       | Error _ -> ()
       | Ok _ -> fail "text encoded an invalid line spacing")
    [ -1.; nan; infinity; neg_infinity ]
;;

let test_native_image_round_trip () =
  let frame source sizing scale =
    let props = Wire_frame.Image_props { source; sizing; scale } in
    Wire_frame.
      { counter_frame with
        operations =
          [ Create_node { node_id = node 1L; kind = Image; props; event_bindings = [] }
          ; Update_props { node_id = node 1L; props }
          ]
      }
  in
  List.iter
    (fun source ->
       List.iter
         (fun sizing ->
            List.iter
              (fun scale ->
                 let frame = frame source sizing scale in
                 match Binary_codec.encode frame with
                 | Error error -> fail "image encode failed: %s" error.message
                 | Ok bytes ->
                   (match Binary_codec.decode bytes with
                    | Error error -> fail "image decode failed: %s" error.message
                    | Ok decoded ->
                      expect (decoded = frame) "image round trip changed source or sizing"))
              [ 1.; 2. ])
         Wire_frame.[ Original; Stretch; Fit; Fill ])
    Wire_frame.
      [ Resource "images/example.png"; Remote "https://example.invalid/image.png" ];
  List.iter
    (fun (source, scale) ->
       match Binary_codec.encode (frame source Wire_frame.Fit scale) with
       | Error _ -> ()
       | Ok _ -> fail "image encoded an invalid source or scale")
    Wire_frame.
      [ Resource "../outside.png", 1.
      ; Remote "https://", 1.
      ; Resource "image.png", 0.
      ; Resource "image.png", nan
      ; Resource "image.png", infinity
      ]
;;

let test_rich_text_round_trip () =
  let span : Wire_frame.text_span =
    { value = "世界 👩🏽‍💻\n"
    ; font_size = Some 22.
    ; font_weight = Some Semi_bold
    ; color = Some 0x80010203l
    ; italic = Some true
    ; underline = true
    ; strikethrough = true
    }
  in
  let frame props =
    Wire_frame.
      { counter_frame with
        operations =
          [ Create_node
              { node_id = node 1L; kind = Rich_text; props; event_bindings = [] }
          ; Update_props { node_id = node 1L; props }
          ]
      }
  in
  List.iter
    (fun spans ->
       let frame = frame (Wire_frame.Rich_text_props { spans }) in
       match Binary_codec.encode frame with
       | Error error -> fail "rich text encode failed: %s" error.message
       | Ok bytes ->
         (match Binary_codec.decode bytes with
          | Error error -> fail "rich text decode failed: %s" error.message
          | Ok decoded -> expect (decoded = frame) "rich text round trip changed runs"))
    [ []
    ; [ span ]
    ; [ span
      ; { Wire_frame.value = "plain"
        ; font_size = None
        ; font_weight = None
        ; color = None
        ; italic = Some false
        ; underline = false
        ; strikethrough = false
        }
      ]
    ];
  List.iter
    (fun font_size ->
       match
         Binary_codec.encode
           (frame
              (Wire_frame.Rich_text_props
                 { spans = [ { span with font_size = Some font_size } ] }))
       with
       | Error _ -> ()
       | Ok _ -> fail "rich text encoded an invalid font size")
    [ 0.; -1.; nan; infinity; neg_infinity ]
;;

let test_animation_props_round_trip () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 7L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 9L
              ; props =
                  Animated_opacity_props
                    { opacity = 0.75
                    ; animation =
                        { id = animation 7001L; duration_ms = 250; curve = Ease_in_out }
                    }
              }
          ]
      }
  in
  match Binary_codec.encode frame with
  | Error error -> fail "animation encode failed: %s" error.message
  | Ok encoded ->
    (match Binary_codec.decode encoded with
     | Error error -> fail "animation decode failed: %s" error.message
     | Ok decoded -> expect (decoded = frame) "animation props changed during round trip")
;;

let test_layout_native_and_semantics_props_round_trip () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 9L
      ; base_revision = revision 0L
      ; target_revision = revision 1L
      ; kind = Full_snapshot
      ; operations =
          [ Create_node
              { node_id = node 1L
              ; kind = Padding
              ; props =
                  Padding_props { leading = 12.; top = 8.; trailing = 12.; bottom = 8. }
              ; event_bindings = []
              }
          ; Create_node
              { node_id = node 2L
              ; kind = Frame
              ; props =
                  Frame_props
                    { width = None
                    ; height = Some 48.
                    ; min_width = Some 0.
                    ; ideal_width = None
                    ; max_width = Some Fill_space
                    ; min_height = None
                    ; ideal_height = None
                    ; max_height = None
                    ; alignment = Center
                    }
              ; event_bindings = []
              }
          ; Create_node
              { node_id = node 3L
              ; kind = Scroll
              ; props =
                  Scroll_props
                    { vertical = true
                    ; shows_indicators = true
                    ; fill_viewport = false
                    ; initial_anchor = 0
                    }
              ; event_bindings =
                  [ { event_tag = Generated_protocol.Event_tag.scroll_notification
                    ; handler_id = handler 80L
                    }
                  ]
              }
          ; Create_node
              { node_id = node 4L
              ; kind = Semantics
              ; props =
                  Semantics_props
                    { label = Some "Accept terms"
                    ; hint = None
                    ; value = Some "Not accepted"
                    ; role = Semantics_toggle
                    ; selected = None
                    ; children = 0
                    ; hidden = false
                    ; live_region = false
                    ; heading_level = None
                    ; sort_priority = None
                    ; identifier = Some "accept-terms"
                    ; actions = [ 41L, "Archive" ]
                    }
              ; event_bindings = []
              }
          ; Create_node
              { node_id = node 5L
              ; kind = Theme
              ; props =
                  Theme_props
                    { mode = Dark
                    ; tint = Some 0xff6750a4l
                    ; font_family = None
                    ; control_size = 3
                    ; defaults = Bytes.make 96 '\000'
                    }
              ; event_bindings = []
              }
          ; Create_node
              { node_id = node 6L
              ; kind = Toggle
              ; props = Toggle_props { value = false; enabled = true; style = 2 }
              ; event_bindings =
                  [ { event_tag = Generated_protocol.Event_tag.value_changed
                    ; handler_id = handler 81L
                    }
                  ]
              }
          ]
      }
  in
  match Binary_codec.encode frame with
  | Error error -> fail "widget props encode failed: %s" error.message
  | Ok encoded ->
    (match Binary_codec.decode encoded with
     | Error error -> fail "widget props decode failed: %s" error.message
     | Ok decoded -> expect (decoded = frame) "widget props changed during round trip")
;;

let native_text_field_frame ?(appearance = 0) ?(composing_end = 4) () =
  Wire_frame.
    { runtime_epoch = epoch 10L
    ; base_revision = revision 4L
    ; target_revision = revision 5L
    ; kind = Incremental_frame
    ; operations =
        [ Update_props
            { node_id = node 12L
            ; props =
                Text_field_props
                  { editing =
                      { session_id = session 7L
                      ; document_revision = document_revision 9L
                      ; accepted_local_revision = local_revision 11L
                      ; update_mode = Correction
                      ; value =
                          { text = "拼😀音"
                          ; selection = { start_utf16 = 4; end_utf16 = 4 }
                          ; composing =
                              Some { start_utf16 = 0; end_utf16 = composing_end }
                          }
                      ; enabled = true
                      ; read_only = false
                      ; max_utf8_bytes = Some 64
                      ; submit_on_return = true
                      }
                  ; label = "Text input"
                  ; prompt = ""
                  ; secure = false
                  ; keyboard = 0
                  ; submit_label = 0
                  ; appearance
                  ; autofocus = true
                  }
            }
        ]
    }
;;

let test_native_text_field_props_round_trip () =
  List.iter
    (fun appearance ->
       let frame = native_text_field_frame ~appearance () in
       match Binary_codec.encode frame with
       | Error error -> fail "text input encode failed: %s" error.message
       | Ok encoded ->
         (match Binary_codec.decode encoded with
          | Error error -> fail "text input decode failed: %s" error.message
          | Ok decoded ->
            expect (decoded = frame) "text input props changed during round trip"))
    [ 0; 1 ];
  List.iter
    (fun appearance ->
       match Binary_codec.encode (native_text_field_frame ~appearance ()) with
       | Error { code = Invalid_props; _ } -> ()
       | _ -> fail "invalid field appearance was accepted")
    [ -1; 2 ]
;;

let test_text_input_rejects_split_surrogate_range () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 10L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 12L
              ; props =
                  Text_field_props
                    { editing =
                        { session_id = session 1L
                        ; document_revision = document_revision 1L
                        ; accepted_local_revision = local_revision 0L
                        ; update_mode = Ack
                        ; value =
                            { text = "😀"
                            ; selection = { start_utf16 = 1; end_utf16 = 1 }
                            ; composing = None
                            }
                        ; enabled = true
                        ; read_only = false
                        ; max_utf8_bytes = None
                        ; submit_on_return = true
                        }
                    ; label = "Text input"
                    ; prompt = ""
                    ; secure = false
                    ; keyboard = 0
                    ; submit_label = 0
                    ; appearance = 0
                    ; autofocus = false
                    }
              }
          ]
      }
  in
  match Binary_codec.encode frame with
  | Error { code = Invalid_props; _ } -> ()
  | Error error -> fail "unexpected split-surrogate error: %s" error.message
  | Ok _ -> fail "split surrogate range unexpectedly encoded"
;;

let expect_decode_error code bytes =
  match Binary_codec.decode bytes with
  | Ok _ -> fail "malformed input unexpectedly decoded"
  | Error error -> expect (error.code = code) "unexpected decoder error"
;;

let test_malformed_frames () =
  let valid = fixture () in
  let bad_magic = Bytes.copy valid in
  Bytes.set bad_magic 0 '\x00';
  expect_decode_error Invalid_magic bad_magic;
  expect_decode_error Truncated_input (Bytes.sub valid 0 47);
  let trailing = Bytes.extend valid 0 1 in
  expect_decode_error Invalid_payload_length trailing
;;

let test_event_batch_fixture () =
  let path =
    let from_root = "protocol/generated/fixtures/swift_counter_press.hex" in
    if Sys.file_exists from_root
    then from_root
    else "../../protocol/generated/fixtures/swift_counter_press.hex"
  in
  let channel = open_in_bin path in
  let encoded =
    Fun.protect
      ~finally:(fun () -> close_in channel)
      (fun () -> really_input_string channel (in_channel_length channel) |> bytes_of_hex)
  in
  match Event_batch_codec.decode encoded with
  | Error error -> fail "event batch decode failed: %s" error.message
  | Ok { Inbound_event.runtime_epoch; events = [ event ] } ->
    expect (runtime_epoch = epoch 21L) "unexpected event epoch";
    expect (event.sequence = sequence 1L) "unexpected event sequence";
    expect (event.displayed_revision = revision 1L) "unexpected displayed revision";
    expect (event.node_id = node 3L) "unexpected event node";
    expect (event.handler_id = handler 9001L) "unexpected handler";
    expect (event.event_tag = Generated_protocol.Event_tag.press) "unexpected tag";
    expect (event.payload = Unit) "unexpected payload"
  | Ok _ -> fail "unexpected event batch shape"
;;

let test_text_limit_reached_event_round_trip () =
  let batch : Inbound_event.batch =
    { runtime_epoch = epoch 21L
    ; events =
        [ { sequence = sequence 9L
          ; displayed_revision = revision 4L
          ; node_id = node 12L
          ; handler_id = handler 104L
          ; event_tag = Generated_protocol.Event_tag.text_limit_reached
          ; payload = Unit
          }
        ]
    }
  in
  match Event_batch_codec.encode batch with
  | Error error -> fail "text limit event encode failed: %s" error.message
  | Ok encoded ->
    expect (Bytes.length encoded < 128) "text limit event payload is not bounded";
    (match Event_batch_codec.decode encoded with
     | Error error -> fail "text limit event decode failed: %s" error.message
     | Ok decoded -> expect (decoded = batch) "text limit event changed during round trip")
;;

let test_text_input_rejects_invalid_utf8_byte_limits () =
  let encode max_utf8_bytes =
    Binary_codec.encode
      Wire_frame.
        { runtime_epoch = epoch 10L
        ; base_revision = revision 4L
        ; target_revision = revision 5L
        ; kind = Incremental_frame
        ; operations =
            [ Update_props
                { node_id = node 12L
                ; props =
                    Text_field_props
                      { editing =
                          { session_id = session 7L
                          ; document_revision = document_revision 9L
                          ; accepted_local_revision = local_revision 0L
                          ; update_mode = Ack
                          ; value =
                              { text = ""
                              ; selection = { start_utf16 = 0; end_utf16 = 0 }
                              ; composing = None
                              }
                          ; enabled = true
                          ; read_only = false
                          ; max_utf8_bytes
                          ; submit_on_return = true
                          }
                      ; label = "Text input"
                      ; prompt = ""
                      ; secure = false
                      ; keyboard = 0
                      ; submit_label = 0
                      ; appearance = 0
                      ; autofocus = false
                      }
                }
            ]
        }
  in
  List.iter
    (fun value ->
       match encode (Some value) with
       | Error { code = Invalid_props; _ } -> ()
       | Error error -> fail "unexpected byte limit error: %s" error.message
       | Ok _ -> fail "invalid max_utf8_bytes=%d unexpectedly encoded" value)
    [ 0; -1; 1_048_577; 0x1_0000_0000 ];
  match encode None with
  | Error error -> fail "unlimited text input failed: %s" error.message
  | Ok _ -> ()
;;

let test_unknown_event_tag () =
  let encoded =
    let path =
      let from_root = "protocol/generated/fixtures/swift_counter_press.hex" in
      if Sys.file_exists from_root
      then from_root
      else "../../protocol/generated/fixtures/swift_counter_press.hex"
    in
    let channel = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in channel)
      (fun () -> really_input_string channel (in_channel_length channel) |> bytes_of_hex)
  in
  List.iter
    (fun tag ->
       Bytes.set encoded 88 (Char.chr tag);
       match Event_batch_codec.decode encoded with
       | Error { code = Unknown_event_tag; _ } -> ()
       | Error error ->
         fail "retired/unknown event %d failed for wrong reason: %s" tag error.message
       | Ok _ -> fail "retired/unknown event tag %d unexpectedly decoded" tag)
    [ 35; 39; 40; 48; 49; 255 ]
;;

let test_interaction_props_round_trip () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 12L
      ; base_revision = revision 0L
      ; target_revision = revision 1L
      ; kind = Full_snapshot
      ; operations =
          [ Create_node
              { node_id = node 1L
              ; kind = Gesture
              ; props = Gesture_props
              ; event_bindings = []
              }
          ; Create_node
              { node_id = node 2L
              ; kind = Focus_scope
              ; props = Focus_scope_props { autofocus = true }
              ; event_bindings = []
              }
          ; Create_node
              { node_id = node 3L
              ; kind = Hover_region
              ; props = Hover_region_props { blocks_behind = false }
              ; event_bindings = []
              }
          ; Create_node
              { node_id = node 4L
              ; kind = Keyboard_listener
              ; props = Keyboard_listener_props { autofocus = true; key_policy = Handled }
              ; event_bindings = []
              }
          ]
      }
  in
  match Binary_codec.encode frame with
  | Error error -> fail "interaction encode failed: %s" error.message
  | Ok bytes ->
    (match Binary_codec.decode bytes with
     | Error error -> fail "interaction decode failed: %s" error.message
     | Ok decoded -> expect (decoded = frame) "interaction props changed")
;;

let test_interaction_event_round_trip () =
  let events =
    Inbound_event.
      [ { sequence = sequence 1L
        ; displayed_revision = revision 1L
        ; node_id = node 1L
        ; handler_id = handler 10L
        ; event_tag = Generated_protocol.Event_tag.tap
        ; payload =
            Tap
              { local_x = 1.
              ; local_y = 2.
              ; global_x = 3.
              ; global_y = 4.
              ; pointer_kind = Touch
              }
        }
      ; { sequence = sequence 2L
        ; displayed_revision = revision 1L
        ; node_id = node 1L
        ; handler_id = handler 11L
        ; event_tag = Generated_protocol.Event_tag.pointer_down
        ; payload =
            Pointer
              { pointer_id = ID.Input.Pointer_id.of_int64 7L
              ; local_x = 5.
              ; local_y = 6.
              ; global_x = 7.
              ; global_y = 8.
              ; pointer_kind = Mouse
              ; buttons = 1
              }
        }
      ; { sequence = sequence 3L
        ; displayed_revision = revision 1L
        ; node_id = node 2L
        ; handler_id = handler 12L
        ; event_tag = Generated_protocol.Event_tag.key
        ; payload =
            Key
              { logical_key = ID.Input.Logical_key.of_int64 97L
              ; physical_key = ID.Input.Physical_key.of_int64 0x70004L
              ; action = Key_down
              ; modifiers = 3
              }
        }
      ]
  in
  let batch = Inbound_event.{ runtime_epoch = epoch 12L; events } in
  match Event_batch_codec.encode batch with
  | Error error -> fail "interaction event encode failed: %s" error.message
  | Ok bytes ->
    (match Event_batch_codec.decode bytes with
     | Error error -> fail "interaction event decode failed: %s" error.message
     | Ok decoded -> expect (decoded = batch) "interaction event payload changed")
;;

let expect_frame_round_trip label frame =
  match Binary_codec.encode frame with
  | Error error -> fail "%s encode failed: %s" label error.message
  | Ok bytes ->
    (match Binary_codec.decode bytes with
     | Error error -> fail "%s decode failed: %s" label error.message
     | Ok decoded -> expect (decoded = frame) "%s changed during round trip" label)
;;

let expect_event_batch_round_trip label batch =
  match Event_batch_codec.encode batch with
  | Error error -> fail "%s encode failed: %s" label error.message
  | Ok bytes ->
    (match Event_batch_codec.decode bytes with
     | Error error -> fail "%s decode failed: %s" label error.message
     | Ok decoded -> expect (decoded = batch) "%s changed during round trip" label)
;;

let test_host_requests_round_trip () =
  let open Wire_frame in
  expect_frame_round_trip
    "host requests"
    { runtime_epoch = epoch 31L
    ; base_revision = revision 2L
    ; target_revision = revision 3L
    ; kind = Incremental_frame
    ; operations =
        [ Host_request
            { request_id = request 1L; payload = Clipboard_write { text = "剪贴板😀" } }
        ; Host_request
            { request_id = request 2L
            ; payload =
                Pick_files { allowed_extensions = [ "txt"; "md" ]; allow_multiple = true }
            }
        ; Host_request
            { request_id = request 3L
            ; payload = Open_url { uri = "https://example.com/路径" }
            }
        ; Cancel_host_request { request_id = request 2L }
        ]
    }
;;

let test_host_response_events_round_trip () =
  let open Inbound_event in
  expect_event_batch_round_trip
    "host response events"
    { runtime_epoch = epoch 31L
    ; events =
        [ { sequence = sequence 1L
          ; displayed_revision = revision 3L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Generated_protocol.Event_tag.host_response
          ; payload =
              Host_response
                { request_id = request 1L
                ; status = Host_ok
                ; value = Bytes.of_string "accepted"
                }
          }
        ; { sequence = sequence 2L
          ; displayed_revision = revision 3L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Generated_protocol.Event_tag.host_response
          ; payload =
              Host_response
                { request_id = request 2L; status = Host_cancelled; value = Bytes.empty }
          }
        ]
    }
;;

let test_environment_event_round_trip () =
  let open Inbound_event in
  let environment =
    { viewport_width = 1440.
    ; viewport_height = 900.
    ; device_pixel_ratio = 2.
    ; text_scale = 1.1
    ; brightness = Environment_dark
    ; platform = "macos"
    ; locale = "zh_CN"
    ; safe_area = { left = 0.; top = 24.; right = 0.; bottom = 0. }
    ; keyboard_insets = { left = 0.; top = 0.; right = 0.; bottom = 280. }
    ; accessible_navigation = false
    ; bold_text = false
    ; invert_colors = false
    ; disable_animations = false
    ; reduced_motion = false
    ; high_contrast = true
    ; orientation = Landscape
    ; pointer_kinds = 5
    }
  in
  expect_event_batch_round_trip
    "environment event"
    { runtime_epoch = epoch 31L
    ; events =
        [ { sequence = sequence 1L
          ; displayed_revision = revision 3L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Generated_protocol.Event_tag.environment_changed
          ; payload = Environment_changed environment
          }
        ]
    }
;;

let test_native_widget_props_round_trip () =
  let open Wire_frame in
  expect_frame_round_trip
    "native widget props"
    { runtime_epoch = epoch 7L
    ; base_revision = revision 0L
    ; target_revision = revision 1L
    ; kind = Full_snapshot
    ; operations =
        [ Create_node
            { node_id = node 1L
            ; kind = Native_widget
            ; props =
                Native_widget_props
                  { kind_id = ID.Native_widget.Kind_id.of_int 42
                  ; version = 3
                  ; capabilities = 5L
                  ; payload = Bytes.of_string "\000typed\255"
                  }
            ; event_bindings =
                [ { event_tag = ID.Protocol.Event_tag.of_int 21; handler_id = handler 9L }
                ]
            }
        ; Set_root (node 1L)
        ]
    }
;;

let test_button_props_round_trip () =
  let open Wire_frame in
  expect_frame_round_trip
    "button props"
    { runtime_epoch = epoch 7L
    ; base_revision = revision 0L
    ; target_revision = revision 1L
    ; kind = Full_snapshot
    ; operations =
        [ Create_node
            { node_id = node 1L
            ; kind = Button
            ; props =
                Button_props { enabled = false; role = 2; style = 3; autofocus = false }
            ; event_bindings =
                [ { event_tag = Generated_protocol.Event_tag.press
                  ; handler_id = handler 9L
                  }
                ]
            }
        ; Set_root (node 1L)
        ]
    }
;;

let test_native_event_round_trip () =
  let open Inbound_event in
  expect_event_batch_round_trip
    "native event"
    { runtime_epoch = epoch 4L
    ; events =
        [ { sequence = sequence 1L
          ; displayed_revision = revision 3L
          ; node_id = node 8L
          ; handler_id = handler 9L
          ; event_tag = Generated_protocol.Event_tag.native_event
          ; payload =
              Native_event
                { kind_id = ID.Native_widget.Kind_id.of_int 42
                ; version = 3
                ; event_id = ID.Native_widget.Event_id.of_int 7
                ; payload = Bytes.of_string "\000\023\255"
                }
          }
        ]
    }
;;

let test_runtime_stats_round_trip () =
  let open Wire_frame in
  expect_frame_round_trip
    "runtime stats"
    { runtime_epoch = epoch 9L
    ; base_revision = revision 0L
    ; target_revision = revision 1L
    ; kind = Full_snapshot
    ; operations =
        [ Create_node
            { node_id = node 1L; kind = Empty; props = Empty_props; event_bindings = [] }
        ; Set_root (node 1L)
        ; Runtime_stats
            { event_batch_size = 3
            ; bonsai_flush_ns = 11L
            ; result_read_ns = 12L
            ; reconcile_ns = 13L
            ; encode_ns = 14L
            ; patch_count = 2
            ; patch_bytes = 80
            ; lifecycle_ns = 15L
            ; full_snapshot_count = 1
            ; resync_count = 0
            }
        ]
    }
;;

let zero_runtime_stats =
  Wire_frame.
    { event_batch_size = 0
    ; bonsai_flush_ns = 0L
    ; result_read_ns = 0L
    ; reconcile_ns = 0L
    ; encode_ns = 0L
    ; patch_count = 0
    ; patch_bytes = 0
    ; lifecycle_ns = 0L
    ; full_snapshot_count = 0
    ; resync_count = 0
    }
;;

let runtime_encode_exn frame =
  match Binary_codec.encode_runtime_frame frame with
  | Ok encoded -> encoded
  | Error error -> fail "runtime encode failed: %s" error.message
;;

let patch_runtime_exn encoded ~encode_ns ~patch_bytes =
  match Binary_codec.patch_runtime_stats encoded ~encode_ns ~patch_bytes with
  | Ok () -> ()
  | Error error -> fail "runtime stats patch failed: %s" error.message
;;

let replace_runtime_stats frame ~encode_ns ~patch_bytes =
  let operations =
    List.map
      (function
        | Wire_frame.Runtime_stats stats ->
          Wire_frame.Runtime_stats { stats with encode_ns; patch_bytes }
        | operation -> operation)
      frame.Wire_frame.operations
  in
  { frame with operations }
;;

let runtime_stats_exn frame =
  match
    List.filter_map
      (function
        | Wire_frame.Runtime_stats stats -> Some stats
        | _ -> None)
      frame.Wire_frame.operations
  with
  | [ stats ] -> stats
  | _ -> fail "decoded runtime frame did not contain exactly one stats operation"
;;

let test_runtime_stats_backpatch () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 91L
      ; base_revision = revision 0L
      ; target_revision = revision 1L
      ; kind = Full_snapshot
      ; operations =
          [ Create_node
              { node_id = node 1L
              ; kind = Empty
              ; props = Empty_props
              ; event_bindings = []
              }
          ; Set_root (node 1L)
          ; Runtime_stats zero_runtime_stats
          ]
      }
  in
  let encoded = runtime_encode_exn frame in
  let bytes = Binary_codec.Runtime_encoded_frame.bytes encoded in
  let patch_bytes = Bytes.length bytes in
  patch_runtime_exn encoded ~encode_ns:123_456L ~patch_bytes;
  let decoded =
    match Binary_codec.decode bytes with
    | Ok frame -> frame
    | Error error -> fail "backpatched frame did not decode: %s" error.message
  in
  let stats = runtime_stats_exn decoded in
  expect (Int64.equal stats.encode_ns 123_456L) "backpatch changed encode_ns";
  expect (stats.patch_bytes = patch_bytes) "backpatch did not write the final byte length";
  let expected = replace_runtime_stats frame ~encode_ns:123_456L ~patch_bytes in
  expect (decoded = expected) "backpatch changed fields outside runtime stats";
  match Binary_codec.encode expected with
  | Error error -> fail "ordinary comparison encode failed: %s" error.message
  | Ok ordinary ->
    expect
      (Bytes.equal bytes ordinary)
      "backpatched bytes differ from ordinary encoding of the same frame"
;;

let test_runtime_stats_backpatch_limits () =
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 92L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations = [ Runtime_stats zero_runtime_stats ]
      }
  in
  let encoded = runtime_encode_exn frame in
  patch_runtime_exn encoded ~encode_ns:Int64.max_int ~patch_bytes:0xffffffff;
  let decoded =
    match Binary_codec.decode (Binary_codec.Runtime_encoded_frame.bytes encoded) with
    | Ok frame -> frame
    | Error error -> fail "maximum-value runtime frame did not decode: %s" error.message
  in
  let stats = runtime_stats_exn decoded in
  expect (Int64.equal stats.encode_ns Int64.max_int) "maximum encode_ns changed";
  expect (stats.patch_bytes = 0xffffffff) "maximum patch_bytes changed"
;;

let test_runtime_encode_requires_exactly_one_stats_operation () =
  (match Binary_codec.encode_runtime_frame counter_frame with
   | Error _ -> ()
   | Ok _ -> fail "runtime encoder accepted a frame without runtime stats");
  let duplicate =
    Wire_frame.
      { runtime_epoch = epoch 93L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations =
          [ Runtime_stats zero_runtime_stats; Runtime_stats zero_runtime_stats ]
      }
  in
  match Binary_codec.encode_runtime_frame duplicate with
  | Error _ -> ()
  | Ok _ -> fail "runtime encoder accepted duplicate runtime stats"
;;

let test_runtime_stats_backpatch_variants () =
  let frames =
    Wire_frame.
      [ { runtime_epoch = epoch 95L
        ; base_revision = revision 0L
        ; target_revision = revision 1L
        ; kind = Full_snapshot
        ; operations =
            [ Create_node
                { node_id = node 1L
                ; kind = Empty
                ; props = Empty_props
                ; event_bindings = []
                }
            ; Set_root (node 1L)
            ; Runtime_stats zero_runtime_stats
            ]
        }
      ; { runtime_epoch = epoch 95L
        ; base_revision = revision 1L
        ; target_revision = revision 2L
        ; kind = Incremental_frame
        ; operations =
            [ Update_props { node_id = node 1L; props = Empty_props }
            ; Runtime_stats zero_runtime_stats
            ]
        }
      ; { runtime_epoch = epoch 95L
        ; base_revision = revision 2L
        ; target_revision = revision 3L
        ; kind = Incremental_frame
        ; operations =
            [ Host_request
                { request_id = request 7L
                ; payload = Clipboard_write { text = "patched" }
                }
            ; Runtime_stats zero_runtime_stats
            ]
        }
      ; { runtime_epoch = epoch 95L
        ; base_revision = revision 3L
        ; target_revision = revision 4L
        ; kind = Incremental_frame
        ; operations = [ Runtime_stats zero_runtime_stats ]
        }
      ]
  in
  List.iteri
    (fun index frame ->
       let encoded = runtime_encode_exn frame in
       let bytes = Binary_codec.Runtime_encoded_frame.bytes encoded in
       let encode_ns = Int64.of_int (index + 1) in
       let patch_bytes = Bytes.length bytes in
       patch_runtime_exn encoded ~encode_ns ~patch_bytes;
       match Binary_codec.decode bytes with
       | Error error -> fail "runtime variant did not decode: %s" error.message
       | Ok decoded ->
         expect
           (decoded = replace_runtime_stats frame ~encode_ns ~patch_bytes)
           "runtime backpatch changed a frame variant")
    frames
;;

let test_application_request_round_trip_and_bounds () =
  let below = Bytes.of_string "\000\001\127\128\255" in
  let boundary =
    Bytes.make Generated_protocol.Limits.max_application_payload_bytes '\255'
  in
  let frame =
    Wire_frame.
      { runtime_epoch = epoch 96L
      ; base_revision = revision 3L
      ; target_revision = revision 4L
      ; kind = Incremental_frame
      ; operations =
          [ Application_request { request_id = 71L; payload = below }
          ; Application_request { request_id = 72L; payload = boundary }
          ]
      }
  in
  let encoded =
    match Binary_codec.encode frame with
    | Ok bytes -> bytes
    | Error error -> fail "application request encode failed: %s" error.message
  in
  (match Binary_codec.decode encoded with
   | Ok decoded -> expect (decoded = frame) "application request bytes changed"
   | Error error -> fail "application request decode failed: %s" error.message);
  let oversized =
    Wire_frame.
      { frame with
        operations =
          [ Application_request
              { request_id = 73L
              ; payload =
                  Bytes.make
                    (Generated_protocol.Limits.max_application_payload_bytes + 1)
                    '\000'
              }
          ]
      }
  in
  match Binary_codec.encode oversized with
  | Error { code = Application_payload_too_large; _ } -> ()
  | Error error -> fail "oversized application request returned %s" error.message
  | Ok _ -> fail "oversized application request encoded"
;;

let test_application_response_error_and_event_round_trip () =
  let open Inbound_event in
  let batch =
    { runtime_epoch = epoch 96L
    ; events =
        [ { sequence = sequence 1L
          ; displayed_revision = revision 4L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Generated_protocol.Event_tag.application_response
          ; payload =
              Application_response
                { request_id = 71L; payload = Bytes.of_string "\000\255response" }
          }
        ; { sequence = sequence 2L
          ; displayed_revision = revision 4L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Generated_protocol.Event_tag.application_request_error
          ; payload =
              Application_request_error
                { request_id = 72L
                ; error =
                    { code = Handler_failed; message = "application handler failed" }
                }
          }
        ; { sequence = sequence 3L
          ; displayed_revision = revision 4L
          ; node_id = node 0L
          ; handler_id = handler 0L
          ; event_tag = Generated_protocol.Event_tag.application_event
          ; payload = Application_event (Bytes.of_string "\128\000event")
          }
        ]
    }
  in
  let encoded =
    match Event_batch_codec.encode batch with
    | Ok bytes -> bytes
    | Error error -> fail "application event encode failed: %s" error.message
  in
  match Event_batch_codec.decode encoded with
  | Ok decoded -> expect (decoded = batch) "application event bytes changed"
  | Error error -> fail "application event decode failed: %s" error.message
;;

let props_frame props =
  Wire_frame.
    { runtime_epoch = epoch 90L
    ; base_revision = revision 1L
    ; target_revision = revision 2L
    ; kind = Incremental_frame
    ; operations = [ Update_props { node_id = node 1L; props } ]
    }
;;

let expect_invalid_props_encode label frame =
  match Binary_codec.encode frame with
  | Error { code = Invalid_props; _ } -> ()
  | Error error -> fail "%s produced the wrong encode error: %s" label error.message
  | Ok _ -> fail "%s unexpectedly encoded" label
;;

let find_float64 bytes value =
  let needle = Bytes.create 8 in
  Bytes.set_int64_le needle 0 (Int64.bits_of_float value);
  let rec search offset =
    if offset + Bytes.length needle > Bytes.length bytes
    then fail "float64 value %g was not found" value
    else (
      let rec matches index =
        index = Bytes.length needle
        || (Char.equal (Bytes.get bytes (offset + index)) (Bytes.get needle index)
            && matches (index + 1))
      in
      if matches 0 then offset else search (offset + 1))
  in
  search 0
;;

let replace_float64_at bytes offset value =
  let result = Bytes.copy bytes in
  Bytes.set_int64_le result offset (Int64.bits_of_float value);
  result
;;

let replace_float64 bytes before after =
  replace_float64_at bytes (find_float64 bytes before) after
;;

let expect_invalid_props_decode label bytes =
  match Binary_codec.decode bytes with
  | Error { code = Invalid_props; _ } -> ()
  | Error error -> fail "%s produced the wrong decode error: %s" label error.message
  | Ok _ -> fail "%s unexpectedly decoded" label
;;

let test_frame_optional_dimensions_protocol () =
  let props
        ?width
        ?height
        ?min_width
        ?ideal_width
        ?max_width
        ?min_height
        ?ideal_height
        ?max_height
        ()
    =
    Wire_frame.Frame_props
      { width
      ; height
      ; min_width
      ; ideal_width
      ; max_width
      ; min_height
      ; ideal_height
      ; max_height
      ; alignment = Center
      }
  in
  expect_frame_round_trip "fixed frame" (props_frame (props ~width:0. ~height:20. ()));
  expect_frame_round_trip
    "ideal frame"
    (props_frame
       (props
          ~min_width:10.
          ~ideal_width:30.
          ~max_width:(Points 80.)
          ~min_height:0.
          ~ideal_height:20.
          ~max_height:Fill_space
          ()));
  expect_invalid_props_encode
    "fixed/flexible conflict"
    (props_frame (props ~width:40. ~max_width:Fill_space ()));
  expect_invalid_props_encode
    "ideal below minimum"
    (props_frame (props ~min_width:40. ~ideal_width:20. ()));
  expect_invalid_props_encode
    "ideal above maximum"
    (props_frame (props ~ideal_width:40. ~max_width:(Points 20.) ()));
  expect_frame_round_trip "unbounded frame" (props_frame (props ~min_height:44. ()));
  expect_frame_round_trip
    "bounded frame"
    (props_frame
       (props
          ~min_width:10.
          ~max_width:(Wire_frame.Points 100.)
          ~min_height:20.
          ~max_height:(Wire_frame.Points 200.)
          ()));
  let transitions =
    Wire_frame.
      { runtime_epoch = epoch 90L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props { node_id = node 1L; props = props ~min_height:44. () }
          ; Update_props
              { node_id = node 1L
              ; props = props ~min_height:44. ~max_height:(Wire_frame.Points 200.) ()
              }
          ; Update_props { node_id = node 1L; props = props ~min_height:44. () }
          ]
      }
  in
  expect_frame_round_trip "frame None/Some patch transitions" transitions;
  List.iter
    (fun invalid ->
       expect_invalid_props_encode
         "invalid frame maximum width"
         (props_frame (props ~max_width:(Wire_frame.Points invalid) ()));
       expect_invalid_props_encode
         "invalid frame maximum height"
         (props_frame (props ~max_height:(Wire_frame.Points invalid) ())))
    [ -1.; Float.nan; Float.infinity; Float.neg_infinity ];
  expect_invalid_props_encode
    "frame maximum width below minimum"
    (props_frame (props ~min_width:11. ~max_width:(Wire_frame.Points 10.) ()));
  expect_invalid_props_encode
    "frame maximum height below minimum"
    (props_frame (props ~min_height:21. ~max_height:(Wire_frame.Points 20.) ()));
  let encoded =
    match
      Binary_codec.encode
        (props_frame
           (props ~min_width:10. ~max_width:(Wire_frame.Points 123.25) ~min_height:20. ()))
    with
    | Ok bytes -> bytes
    | Error error -> fail "valid frame failed to encode: %s" error.message
  in
  List.iter
    (fun invalid ->
       expect_invalid_props_decode
         "invalid decoded frame maximum width"
         (replace_float64 encoded 123.25 invalid))
    [ -1.; 5.; Float.nan; Float.infinity; Float.neg_infinity ];
  let encoded =
    match
      Binary_codec.encode
        (props_frame
           (props ~min_width:10. ~min_height:20. ~max_height:(Wire_frame.Points 321.5) ()))
    with
    | Ok bytes -> bytes
    | Error error -> fail "valid frame failed to encode: %s" error.message
  in
  List.iter
    (fun invalid ->
       expect_invalid_props_decode
         "invalid decoded frame maximum height"
         (replace_float64 encoded 321.5 invalid))
    [ -1.; 15.; Float.nan; Float.infinity; Float.neg_infinity ]
;;

let test_complete_native_protocol_round_trip () =
  let open Wire_frame in
  let props =
    [ Button_props { enabled = true; role = 0; style = 3; autofocus = false }
    ; Text_field_props
        { editing =
            { session_id = session 4L
            ; document_revision = document_revision 9L
            ; accepted_local_revision = local_revision 6L
            ; update_mode = Ack
            ; value =
                { text = "readonly"
                ; selection = { start_utf16 = 0; end_utf16 = 8 }
                ; composing = None
                }
            ; enabled = true
            ; read_only = true
            ; max_utf8_bytes = Some 128
            ; submit_on_return = true
            }
        ; label = "Reference"
        ; prompt = ""
        ; secure = false
        ; keyboard = 0
        ; submit_label = 0
        ; appearance = 0
        ; autofocus = true
        }
    ; Table_props
        { columns =
            [ { title = "Column"
              ; has_details = false
              ; column_id = 11L
              ; tooltip = Some "Name"
              ; numeric = false
              ; sortable = true
              }
            ; { title = "Column"
              ; has_details = false
              ; column_id = 12L
              ; tooltip = None
              ; numeric = true
              ; sortable = false
              }
            ]
        ; rows = [ { row_id = 21L; selection_enabled = true } ]
        ; sort_column_id = Some 11L
        ; sort_ascending = false
        ; selected_row_ids = [ 21L ]
        ; has_on_sort = true
        ; has_on_row_selected = true
        }
    ; Disclosure_group_props { expanded = true; enabled = true }
    ; Disclosure_group_props { expanded = false; enabled = false }
    ; Date_picker_props
        { selected = { year = 1582; month = 10; day = 10 }
        ; first = { year = 1; month = 1; day = 1 }
        ; last = { year = 9999; month = 12; day = 31 }
        ; selectable_dates =
            [ { year = 1582; month = 10; day = 10 }
            ; { year = 2000; month = 2; day = 29 }
            ]
        ; label = "Historical date"
        ; enabled = true
        }
    ; Time_picker_props
        { value = { hour = 23; minute = 59 }
        ; format = 2
        ; label = "Time"
        ; enabled = false
        }
    ; Menu_props
        { enabled = true
        ; items =
            [ { menu_id = 20L
              ; kind = 4
              ; enabled = true
              ; selected = false
              ; role = 0
              ; has_label = true
              ; child_count = 1
              }
            ; { menu_id = -7L
              ; kind = 0
              ; enabled = false
              ; selected = false
              ; role = 2
              ; has_label = true
              ; child_count = 0
              }
            ; { menu_id = 9L
              ; kind = 1
              ; enabled = true
              ; selected = true
              ; role = 0
              ; has_label = true
              ; child_count = 0
              }
            ; { menu_id = 10L
              ; kind = 2
              ; enabled = false
              ; selected = false
              ; role = 0
              ; has_label = false
              ; child_count = 0
              }
            ]
        }
    ; Picker_props
        { label = "Choice"
        ; style = 0
        ; enabled = true
        ; selected_id = Some (-7L)
        ; options =
            [ { option_id = -7L; enabled = true; has_label = true }
            ; { option_id = 9L; enabled = false; has_label = false }
            ]
        }
    ; Slider_props
        { value = 0.25
        ; min = 0.
        ; max = 1.
        ; step = Some 0.25
        ; label = "Quarter"
        ; enabled = true
        ; has_on_change = true
        ; vertical = false
        }
    ; Range_slider_props
        { start = 0.2
        ; end_ = 0.8
        ; min = 0.
        ; max = 1.
        ; step = None
        ; label_start = "Lower value"
        ; label_end = "Upper value"
        ; enabled = true
        ; has_on_change = false
        ; vertical = false
        }
    ; Badge_props { count = None; alignment = 0; visible = true }
    ; Badge_props { count = Some 0L; alignment = 1; visible = false }
    ; Badge_props { count = Some Int64.max_int; alignment = 2; visible = true }
    ; Label_props
    ; Group_box_props { has_label = false }
    ; Group_box_props { has_label = true }
    ; Divider_props
    ; Progress_props { value = Some 0.5; circular = false }
    ]
  in
  let operations =
    List.mapi
      (fun index props ->
         Update_props { node_id = node (Int64.of_int (index + 1)); props })
      props
    @ [ Host_request
          { request_id = request 91L
          ; payload =
              Show_notice
                { message = "Saved"; action_label = Some "Undo"; duration_ms = 1500 }
          }
      ]
  in
  List.iteri
    (fun index props ->
       expect_frame_round_trip
         (Printf.sprintf "complete native props %d" index)
         { runtime_epoch = epoch 77L
         ; base_revision = revision 1L
         ; target_revision = revision 2L
         ; kind = Incremental_frame
         ; operations = [ Update_props { node_id = node 1L; props } ]
         })
    props;
  let frame =
    { runtime_epoch = epoch 77L
    ; base_revision = revision 1L
    ; target_revision = revision 2L
    ; kind = Incremental_frame
    ; operations
    }
  in
  match Binary_codec.encode frame with
  | Error error -> fail "complete native encode failed: %s" error.message
  | Ok encoded ->
    (match Binary_codec.decode encoded with
     | Error error -> fail "complete native decode failed: %s" error.message
     | Ok decoded ->
       expect (decoded = frame) "complete native protocol round trip changed")
;;

let test_linear_progress_protocol_boundaries () =
  let props value = Wire_frame.Progress_props { value; circular = false } in
  List.iter
    (fun value ->
       expect_frame_round_trip
         "linear progress value boundary"
         (props_frame (props value)))
    [ None; Some 0.; Some 0.5; Some 1. ];
  List.iter
    (fun invalid ->
       expect_invalid_props_encode
         "invalid linear progress encode"
         (props_frame (props (Some invalid))))
    [ -0.01; 1.01; Float.nan; Float.infinity; Float.neg_infinity ];
  let encoded =
    match Binary_codec.encode (props_frame (props (Some 0.375))) with
    | Ok bytes -> bytes
    | Error error -> fail "valid linear progress failed to encode: %s" error.message
  in
  List.iter
    (fun invalid ->
       expect_invalid_props_decode
         "invalid linear progress decode"
         (replace_float64 encoded 0.375 invalid))
    [ -0.01; 1.01; Float.nan; Float.infinity; Float.neg_infinity ]
;;

let test_additional_native_protocol_validation () =
  let open Wire_frame in
  let column id =
    { title = "Column"
    ; has_details = false
    ; column_id = id
    ; tooltip = None
    ; numeric = false
    ; sortable = false
    }
  in
  let row id = { row_id = id; selection_enabled = true } in
  let invalid =
    [ Table_props
        { columns = [ column 1L; column 1L ]
        ; rows = [ row 2L ]
        ; sort_column_id = None
        ; sort_ascending = true
        ; selected_row_ids = []
        ; has_on_sort = false
        ; has_on_row_selected = false
        }
    ; Table_props
        { columns = [ column 1L ]
        ; rows = [ row 2L ]
        ; sort_column_id = Some 1L
        ; sort_ascending = true
        ; selected_row_ids = []
        ; has_on_sort = true
        ; has_on_row_selected = false
        }
    ; Badge_props { count = Some (-1L); alignment = 2; visible = true }
    ; Badge_props { count = None; alignment = 3; visible = true }
    ]
  in
  List.iteri
    (fun index props ->
       expect_invalid_props_encode
         (Printf.sprintf "invalid additional native props %d" index)
         (props_frame props))
    invalid
;;

let test_native_typed_event_payload_round_trip () =
  let open Inbound_event in
  let events =
    [ Generated_protocol.Event_tag.navigation_destination_selected, Int64 2L
    ; Generated_protocol.Event_tag.radio_selected, Int64 (-9L)
    ; Generated_protocol.Event_tag.slider_changed, Float 0.25
    ; Generated_protocol.Event_tag.slider_change_end, Float 0.75
    ; ( Generated_protocol.Event_tag.range_slider_changed
      , Float_range { start = 0.1; end_ = 0.9 } )
    ; ( Generated_protocol.Event_tag.range_slider_change_end
      , Float_range { start = 0.2; end_ = 0.8 } )
    ; ( Generated_protocol.Event_tag.table_sort_requested
      , Int64_bool { id = 11L; value = false } )
    ; ( Generated_protocol.Event_tag.table_row_selected
      , Int64_bool { id = 21L; value = true } )
    ; ( Generated_protocol.Event_tag.civil_date_changed
      , Civil_date { year = 2026; month = 9; day = 4 } )
    ; ( Generated_protocol.Event_tag.civil_time_changed
      , Civil_time { hour = 14; minute = 30 } )
    ]
  in
  let batch =
    { runtime_epoch = epoch 77L
    ; events =
        List.mapi
          (fun index (event_tag, payload) ->
             { sequence = sequence (Int64.of_int (index + 1))
             ; displayed_revision = revision 2L
             ; node_id = node 1L
             ; handler_id = handler (Int64.of_int (index + 10))
             ; event_tag
             ; payload
             })
          events
    }
  in
  match Event_batch_codec.encode batch with
  | Error error -> fail "native event encode failed: %s" error.message
  | Ok encoded ->
    (match Event_batch_codec.decode encoded with
     | Error error -> fail "native event decode failed: %s" error.message
     | Ok decoded -> expect (decoded = batch) "native typed event round trip changed")
;;

let test_marked_selection_is_validated_in_both_wire_directions () =
  (match Binary_codec.encode (native_text_field_frame ~composing_end:1 ()) with
   | Error { code = Invalid_props; _ } -> ()
   | _ -> fail "outgoing text props accepted selection outside marked text");
  let encoded =
    match Binary_codec.encode (native_text_field_frame ()) with
    | Ok encoded -> encoded
    | Error error -> fail "%s" error.message
  in
  let text_start = Bytes.index encoded '\230' in
  expect (Bytes.sub_string encoded text_start 10 = "拼😀音") "text fixture location changed";
  let composing_end_offset = text_start + 10 + 8 + 1 + 4 in
  Bytes.set_int32_le encoded composing_end_offset 1l;
  (match Binary_codec.decode encoded with
   | Error { code = Invalid_props; _ } -> ()
   | _ -> fail "incoming text props accepted selection outside marked text");
  let encoded_event = fixture_named "swift_text_edit_unicode.hex" in
  let batch =
    match Event_batch_codec.decode encoded_event with
    | Ok batch -> batch
    | Error error -> fail "%s" error.message
  in
  let events =
    List.map
      (fun (event : Inbound_event.t) ->
         match event.payload with
         | Text_edit edit ->
           { event with
             payload =
               Text_edit { edit with composing = Some { start_utf16 = 0; end_utf16 = 1 } }
           }
         | _ -> fail "text edit fixture payload changed")
      batch.events
  in
  (match Event_batch_codec.encode { batch with events } with
   | Error { code = Invalid_payload; _ } -> ()
   | _ -> fail "outgoing edit accepted selection outside marked text");
  Bytes.set_int32_le encoded_event (Bytes.length encoded_event - 4) 1l;
  match Event_batch_codec.decode encoded_event with
  | Error { code = Invalid_payload; _ } -> ()
  | _ -> fail "incoming edit accepted selection outside marked text"
;;

let test_native_scroll_protocol () =
  List.iter
    (fun initial_anchor ->
       List.iter
         (fun fill_viewport ->
            List.iter
              (fun (vertical, shows_indicators) ->
                 expect_frame_round_trip
                   "native scroll"
                   (props_frame
                      (Scroll_props
                         { vertical; shows_indicators; fill_viewport; initial_anchor })))
              [ true, true; true, false; false, true; false, false ])
         [ false; true ])
    [ 0; 1 ];
  expect_invalid_props_encode
    "invalid initial scroll anchor"
    (props_frame
       (Scroll_props
          { vertical = true
          ; shows_indicators = true
          ; fill_viewport = false
          ; initial_anchor = 2
          }))
;;

let test_collection_protocol () =
  let catalog : Wire_frame.collection_catalog =
    { keys = [ "1"; "\"1\""; "3" ]
    ; default_extent = 40.
    ; overrides = [ 1, 180. ]
    ; overscan = 4
    ; expand_duration_ms = 240
    ; collapse_duration_ms = 190
    ; vertical = true
    ; initial_anchor = 0
    ; initial_key = None
    ; measurement_revision = None
    }
  in
  let window : Wire_frame.collection_window =
    { first_index = 1; keys = [ "\"1\""; "3" ] }
  in
  expect_frame_round_trip
    "collection catalog"
    (props_frame (Collection_catalog_props catalog));
  List.iter
    (fun revision ->
       expect_frame_round_trip
         "measured collection revision"
         (props_frame
            (Collection_catalog_props
               { catalog with measurement_revision = Some revision })))
    [ 0L; 1L; Int64.max_int ];
  expect_frame_round_trip
    "horizontal collection catalog"
    (props_frame (Collection_catalog_props { catalog with vertical = false }));
  List.iter
    (fun (initial_anchor, initial_key) ->
       expect_frame_round_trip
         "initial collection position"
         (props_frame
            (Collection_catalog_props { catalog with initial_anchor; initial_key })))
    [ 1, None; 2, Some "3" ];
  expect_frame_round_trip
    "collection window"
    (props_frame (Collection_window_props window));
  List.iter
    (fun catalog ->
       expect_invalid_props_encode
         "invalid collection catalog"
         (props_frame (Collection_catalog_props catalog)))
    [ { catalog with measurement_revision = Some (-1L) }
    ; { catalog with initial_anchor = 3 }
    ; { catalog with initial_key = Some "1" }
    ; { catalog with initial_anchor = 1; initial_key = Some "1" }
    ; { catalog with initial_anchor = 2 }
    ; { catalog with initial_anchor = 2; initial_key = Some "missing" }
    ; { catalog with keys = [ "1"; "1" ] }
    ; { catalog with default_extent = nan }
    ; { catalog with overrides = [ 3, 80. ] }
    ; { catalog with overrides = [ 2, 80.; 1, 80. ] }
    ; { catalog with overscan = -1 }
    ; { catalog with expand_duration_ms = -1 }
    ; { catalog with collapse_duration_ms = 4_294_967_296 }
    ];
  expect_invalid_props_encode
    "invalid collection window"
    (props_frame (Collection_window_props { window with first_index = -1 }))
;;

let () =
  test_native_scroll_protocol ();
  test_collection_protocol ();
  test_golden_fixture ();
  test_application_theme_round_trip ();
  test_round_trip ();
  test_styled_text_props_round_trip ();
  test_native_image_round_trip ();
  test_rich_text_round_trip ();
  test_animation_props_round_trip ();
  test_layout_native_and_semantics_props_round_trip ();
  test_native_text_field_props_round_trip ();
  test_text_input_rejects_split_surrogate_range ();
  test_marked_selection_is_validated_in_both_wire_directions ();
  test_malformed_frames ();
  test_event_batch_fixture ();
  test_text_limit_reached_event_round_trip ();
  test_text_input_rejects_invalid_utf8_byte_limits ();
  test_unknown_event_tag ();
  test_interaction_props_round_trip ();
  test_interaction_event_round_trip ();
  test_host_requests_round_trip ();
  test_host_response_events_round_trip ();
  test_environment_event_round_trip ();
  test_button_props_round_trip ();
  test_native_widget_props_round_trip ();
  test_native_event_round_trip ();
  test_runtime_stats_round_trip ();
  test_runtime_stats_backpatch ();
  test_runtime_stats_backpatch_limits ();
  test_runtime_encode_requires_exactly_one_stats_operation ();
  test_runtime_stats_backpatch_variants ();
  test_application_request_round_trip_and_bounds ();
  test_application_response_error_and_event_round_trip ();
  test_frame_optional_dimensions_protocol ();
  test_complete_native_protocol_round_trip ();
  test_linear_progress_protocol_boundaries ();
  test_additional_native_protocol_validation ();
  test_native_typed_event_payload_round_trip ();
  print_endline "protocol tests passed"
;;

let () =
  let destination key =
    Wire_frame.Navigation_destination_props
      { page_key = ID.Navigation.Page_key.of_string key
      ; title = "Message"
      ; can_pop = true
      }
  in
  let frame props =
    { counter_frame with
      kind = Incremental_frame
    ; base_revision = revision 1L
    ; target_revision = revision 2L
    ; operations = [ Wire_frame.Update_props { node_id = node 1L; props } ]
    }
  in
  List.iter
    (fun props ->
       let expected = frame props in
       match Binary_codec.encode expected with
       | Error error -> fail "native navigation encode failed: %s" error.message
       | Ok bytes ->
         expect
           (Binary_codec.decode bytes = Ok expected)
           "native navigation round trip changed props")
    [ Wire_frame.Navigation_stack_props { title = "Inbox" }; destination "邮件" ];
  (match Binary_codec.encode (frame (destination "")) with
   | Error { code = Invalid_props; _ } -> ()
   | _ -> fail "empty navigation key was encoded");
  (match Binary_codec.encode_runtime_frame (frame (destination "")) with
   | Error { code = Invalid_props; _ } -> ()
   | _ -> fail "empty runtime navigation key was encoded");
  print_endline
    "ok - native navigation properties preserve identity and reject empty keys"
;;

let () =
  test_retired_route_wire_is_rejected ();
  test_retired_navigation_bar_wire_is_rejected ();
  test_retired_scroll_header_nodes_are_rejected ();
  test_retired_nodes_are_rejected ();
  let open Wire_frame in
  let properties position =
    Scroll_targets_props
      { vertical = false
      ; ids = [ Int64.min_int; Int64.max_int ]
      ; position
      ; fraction = 0.65
      ; spacing = 12.
      ; alignment = 1
      ; snapping = true
      ; enabled = true
      ; shows_indicators = false
      }
  in
  let full =
    { counter_frame with
      operations =
        [ Create_node
            { node_id = node 1L
            ; kind = Scroll_targets
            ; props = properties (Some Int64.min_int)
            ; event_bindings = []
            }
        ; Set_root (node 1L)
        ]
    }
  in
  expect_frame_round_trip "scroll targets signed identity and layout" full;
  let incremental =
    { full with
      kind = Incremental_frame
    ; base_revision = revision 1L
    ; target_revision = revision 2L
    ; operations =
        [ Update_props { node_id = node 1L; props = properties (Some Int64.max_int) } ]
    }
  in
  expect_frame_round_trip "scroll target position update" incremental
;;

let () =
  let props badge accessibility_label =
    Wire_frame.Tab_props
      { page_key = ID.Navigation.Page_key.of_string "mail"
      ; title = "Mail"
      ; symbol = "tray"
      ; badge
      ; accessibility_label
      }
  in
  List.iter
    (fun badge ->
       List.iter
         (fun label ->
            expect_frame_round_trip "tab metadata" (props_frame (props badge label)))
         [ None; Some "Inbox messages" ])
    [ None; Some "0"; Some "4611686018427387903"; Some "•" ];
  List.iter
    (fun empty ->
       expect_invalid_props_encode
         "empty tab badge"
         (props_frame (props (Some empty) None));
       expect_invalid_props_encode
         "empty tab label"
         (props_frame (props None (Some empty))))
    [ ""; " "; "\n\t\012\r" ]
;;

let () =
  match
    Binary_codec.decode
      (bytes_of_hex
         "4253465208000000300003005a0000000000000001000000000000000200000000000000210000000000000000000000010000000003120000000100000000000000220000000000000000000a00000000")
  with
  | Error { code = Binary_codec.Unknown_node_kind; _ } -> ()
  | Error error -> fail "retired fill failed for wrong reason: %s" error.message
  | Ok _ -> fail "retired Sliver fill node was accepted"
;;

let () =
  let item id label : Wire_frame.native_menu_item =
    { item_id = ID.Host.Native_menu_item_id.of_string id; label; enabled = true }
  in
  let frame items =
    Wire_frame.
      { runtime_epoch = epoch 1L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations =
          [ Host_request { request_id = request 1L; payload = Show_native_menu { items } }
          ]
      }
  in
  List.iter
    (fun items -> expect_frame_round_trip "native action menu" (frame items))
    [ [ item "保存😀" "Save copy 😀" ]
    ; List.init 1024 (fun i -> item (string_of_int i) "Action")
    ];
  List.iter
    (fun items -> expect_invalid_props_encode "invalid action menu" (frame items))
    [ [ item
          (String.make (Generated_protocol.Limits.max_string_bytes - 4) 'x')
          "Oversized response"
      ]
    ; []
    ; [ item "" "Action" ]
    ; [ item "a" " \n\t" ]
    ; [ item "a" "A"; item "a" "B" ]
    ; List.init 1025 (fun i -> item (string_of_int i) "Action")
    ];
  let valid =
    match Binary_codec.encode (frame [ item "a" "A"; item "b" "B" ]) with
    | Ok bytes -> bytes
    | Error error -> fail "action menu encoding failed: %s" error.message
  in
  (* Fixed BSFR header, Begin, HostRequest header, request ID/kind/count, then strings. *)
  List.iter
    (fun (offset, value) ->
       let invalid = Bytes.copy valid in
       Bytes.set invalid offset value;
       expect_invalid_props_decode "invalid action menu domain" invalid)
    [ 85, 'a'; 79, ' '; 68, '\000' ]
;;

let () =
  let open Wire_frame in
  let date year month day : civil_date = { year; month; day } in
  let first = date 1 1 1 in
  let last = date 9999 12 31 in
  let selected = date 1582 10 10 in
  let frame payload =
    { runtime_epoch = epoch 1L
    ; base_revision = revision 1L
    ; target_revision = revision 2L
    ; kind = Incremental_frame
    ; operations = [ Host_request { request_id = request 1L; payload } ]
    }
  in
  let valid =
    [ Pick_date { initial = Some selected; first; last }
    ; Pick_date { initial = None; first; last }
    ; Pick_date_range { initial = Some { start = selected; end_ = last }; first; last }
    ; Pick_date_range { initial = None; first; last }
    ]
    @ List.init 3 (fun format ->
      Pick_time { initial = { hour = 23; minute = 59 }; format })
  in
  List.iter
    (fun payload -> expect_frame_round_trip "civil host picker" (frame payload))
    valid;
  List.iter
    (fun payload ->
       expect_invalid_props_encode "invalid civil host picker" (frame payload))
    [ Pick_date { initial = Some (date 1500 2 29); first; last }
    ; Pick_date { initial = None; first = last; last = first }
    ; Pick_date { initial = Some first; first = selected; last }
    ; Pick_date_range { initial = Some { start = last; end_ = first }; first; last }
    ; Pick_date_range
        { initial = Some { start = first; end_ = last }; first = selected; last }
    ; Pick_time { initial = { hour = 24; minute = 0 }; format = 0 }
    ; Pick_time { initial = { hour = 0; minute = 60 }; format = 0 }
    ; Pick_time { initial = { hour = 0; minute = 0 }; format = 3 }
    ];
  let bytes =
    match
      Binary_codec.encode
        (frame (Pick_time { initial = { hour = 23; minute = 59 }; format = 0 }))
    with
    | Ok bytes -> bytes
    | Error error -> fail "civil host encoding: %s" error.message
  in
  List.iter
    (fun (offset, value) ->
       let invalid = Bytes.copy bytes in
       Bytes.set invalid offset (Char.chr value);
       expect_invalid_props_decode "invalid civil host wire" invalid)
    [ 68, 24; 69, 60; 70, 3 ]
;;
