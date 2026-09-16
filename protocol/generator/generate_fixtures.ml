module Protocol = Bonsai_swiftui_protocol
module ID = Bonsai_swiftui_spec.Id

let epoch = ID.Runtime.Epoch.of_int64
let revision = ID.Runtime.Renderer_revision.of_int64
let node = ID.Ui.Node_id.of_int64
let request = ID.Host.Request_id.of_int64
let animation = ID.Ui.Animation_id.of_int64

let hex bytes =
  let output = Buffer.create (Bytes.length bytes * 3) in
  Bytes.iteri
    (fun index byte ->
       if index > 0
       then
         if index mod 12 = 0
         then Buffer.add_char output '\n'
         else Buffer.add_char output ' ';
       Printf.bprintf output "%02x" (Char.code byte))
    bytes;
  Buffer.add_char output '\n';
  Buffer.contents output
;;

let read path =
  try
    let channel = open_in_bin path in
    Some
      (Fun.protect
         ~finally:(fun () -> close_in channel)
         (fun () -> really_input_string channel (in_channel_length channel)))
  with
  | Sys_error _ -> None
;;

let write path contents =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out channel)
    (fun () -> output_string channel contents)
;;

let encode_frame frame =
  match Protocol.Binary_codec.encode frame with
  | Ok bytes -> bytes
  | Error error -> failwith error.message
;;

let text_props value =
  Protocol.Wire_frame.Text_props
    { value; style = None; text_align = Start; line_limit = None; truncation = Tail }
;;

let counter_theme_operation =
  Protocol.Wire_frame.Set_application_theme
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

let viewport_body_frame : Protocol.Wire_frame.t =
  let open Protocol.Wire_frame in
  let create node_id kind props =
    Create_node
      { node_id = node (Int64.of_int node_id); kind; props; event_bindings = [] }
  in
  let row_ids = List.init 10 (fun index -> 10 + index) in
  { runtime_epoch = epoch 57L
  ; base_revision = revision 0L
  ; target_revision = revision 1L
  ; kind = Full_snapshot
  ; operations =
      [ counter_theme_operation
      ; create 2 Overlay (Overlay_props { alignment = Bottom_end })
      ; create
          3
          Weighted_column
          (Weighted_column_props
             { spacing = None
             ; alignment = 1
             ; items = [ Intrinsic; Share { weight = 1.; fills = true } ]
             })
      ; create
          4
          Button
          (Button_props { enabled = true; role = 0; style = 1; autofocus = false })
      ; create 5 Text (text_props "Search")
      ; Create_node
          { node_id = node 6L
          ; kind = Collection_catalog
          ; props =
              Collection_catalog_props
                { keys = List.init 100 string_of_int
                ; default_extent = 48.
                ; overrides = []
                ; overscan = 2
                ; expand_duration_ms = 0
                ; collapse_duration_ms = 0
                ; vertical = true
                ; initial_anchor = 0
                ; initial_key = None
                ; measurement_revision = None
                }
          ; event_bindings =
              [ { event_tag = Protocol.Generated_protocol.Event_tag.visible_range_changed
                ; handler_id = ID.Ui.Handler_id.of_int64 400L
                }
              ]
          }
      ; create
          9
          Collection_window
          (Collection_window_props { first_index = 0; keys = List.init 10 string_of_int })
      ; create
          7
          Button
          (Button_props { enabled = true; role = 0; style = 1; autofocus = false })
      ; create 8 Text (text_props "Capture")
      ; create
          20
          Padding
          (Padding_props { leading = 0.; top = 0.; trailing = 16.; bottom = 16. })
      ]
      @ List.mapi
          (fun index node_id ->
             create node_id Text (text_props (Printf.sprintf "Row %d" index)))
          row_ids
      @ [ Set_children { node_id = node 2L; children = [ node 3L; node 20L ] }
        ; Set_children { node_id = node 3L; children = [ node 4L; node 6L ] }
        ; Set_children { node_id = node 4L; children = [ node 5L ] }
        ; Set_children { node_id = node 6L; children = [ node 9L ] }
        ; Set_children
            { node_id = node 9L
            ; children = List.map (fun id -> node (Int64.of_int id)) row_ids
            }
        ; Set_children { node_id = node 7L; children = [ node 8L ] }
        ; Set_children { node_id = node 20L; children = [ node 7L ] }
        ; Set_root (node 2L)
        ]
  }
;;

let additional_native_frame : Protocol.Wire_frame.t =
  let open Protocol.Wire_frame in
  let props =
    [ Table_props
        { columns =
            [ { title = "Column"
              ; has_details = false
              ; column_id = 11L
              ; tooltip = Some "Name"
              ; numeric = false
              ; sortable = true
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
    ; Badge_props { count = None; alignment = 0; visible = true }
    ; Badge_props { count = Some Int64.max_int; alignment = 2; visible = false }
    ; Label_props
    ; Group_box_props { has_label = false }
    ; Group_box_props { has_label = true }
    ; Divider_props
    ]
  in
  { runtime_epoch = epoch 77L
  ; base_revision = revision 1L
  ; target_revision = revision 2L
  ; kind = Incremental_frame
  ; operations =
      List.mapi
        (fun index props ->
           Update_props { node_id = node (Int64.of_int (index + 1)); props })
        props
  }
;;

let counter_frame : Protocol.Wire_frame.t =
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

let fixtures : (string * Protocol.Wire_frame.t) list =
  let open Protocol.Wire_frame in
  [ ( "ocaml_empty_incremental.hex"
    , { runtime_epoch = epoch 7L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations = []
      } )
  ; ( "ocaml_scroll_sections.hex"
    , { runtime_epoch = epoch 7L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 75L
              ; props =
                  Scroll_sections_props
                    { vertical = true
                    ; pin_headers = true
                    ; pin_footers = false
                    ; spacing = 7.25
                    ; shows_indicators = false
                    ; initial_anchor = 0
                    }
              }
          ; Update_props
              { node_id = node 76L
              ; props =
                  Scroll_section_props
                    { has_header = false
                    ; has_footer = false
                    ; hero_height = Some 201.25
                    ; stretch = true
                    }
              }
          ]
      } )
  ; "ocaml_counter_full.hex", counter_frame
  ; ( "ocaml_unicode_update.hex"
    , { runtime_epoch = epoch 7L
      ; base_revision = revision 1L
      ; target_revision = revision 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 2L
              ; props =
                  Text_props
                    { value = "计数: 😀"
                    ; style = None
                    ; text_align = Start
                    ; line_limit = None
                    ; truncation = Tail
                    }
              }
          ]
      } )
  ; ( "ocaml_reordered_children.hex"
    , { runtime_epoch = epoch 7L
      ; base_revision = revision 2L
      ; target_revision = revision 3L
      ; kind = Incremental_frame
      ; operations =
          [ Set_children { node_id = node 1L; children = [ node 3L; node 2L ] } ]
      } )
  ; ( "ocaml_host_request.hex"
    , { runtime_epoch = epoch 31L
      ; base_revision = revision 2L
      ; target_revision = revision 3L
      ; kind = Incremental_frame
      ; operations =
          [ Host_request
              { request_id = request 41L; payload = Clipboard_write { text = "剪贴板😀" } }
          ]
      } )
  ; ( "ocaml_application_request.hex"
    , { runtime_epoch = epoch 41L
      ; base_revision = revision 8L
      ; target_revision = revision 9L
      ; kind = Incremental_frame
      ; operations =
          [ Application_request
              { request_id = 501L
              ; payload = Bytes.of_string "\000opaque\255application\128"
              }
          ]
      } )
  ; ( "ocaml_animated_opacity.hex"
    , { runtime_epoch = epoch 7L
      ; base_revision = revision 3L
      ; target_revision = revision 4L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 9L
              ; props =
                  Animated_opacity_props
                    { opacity = 0.25
                    ; animation =
                        { id = animation 7001L; duration_ms = 250; curve = Ease_in_out }
                    }
              }
          ]
      } )
  ; ( "ocaml_bounded_text_field.hex"
    , { runtime_epoch = epoch 10L
      ; base_revision = revision 4L
      ; target_revision = revision 5L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = node 12L
              ; props =
                  Text_field_props
                    { editing =
                        { session_id = ID.Text_input.Session_id.of_int64 7L
                        ; document_revision = ID.Text_input.Document_revision.of_int64 9L
                        ; accepted_local_revision =
                            ID.Text_input.Local_revision.of_int64 11L
                        ; update_mode = Correction
                        ; value =
                            { text = "拼😀音"
                            ; selection = { start_utf16 = 4; end_utf16 = 4 }
                            ; composing = Some { start_utf16 = 0; end_utf16 = 4 }
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
                    ; appearance = 0
                    ; autofocus = true
                    }
              }
          ]
      } )
  ; "ocaml_viewport_body.hex", viewport_body_frame
  ; "ocaml_additional_native_components.hex", additional_native_frame
  ]
;;

let () =
  let check = Array.to_list Sys.argv |> List.exists (String.equal "--check") in
  let root = Sys.getcwd () in
  let fixture name = Filename.concat root ("protocol/generated/fixtures/" ^ name) in
  let stale = ref [] in
  List.iter
    (fun (name, frame) ->
       let path = fixture name in
       let expected = encode_frame frame |> hex in
       if check
       then (if read path <> Some expected then stale := path :: !stale)
       else write path expected)
    fixtures;
  match List.rev !stale with
  | [] -> ()
  | paths ->
    List.iter (fun path -> prerr_endline ("Generated fixture is stale: " ^ path)) paths;
    exit 1
;;
