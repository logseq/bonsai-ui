module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

let native_kind_id = ID.Native_widget.Kind_id.of_int
let native_event_id = ID.Native_widget.Event_id.of_int
let check condition message = if not condition then failwith message

let expect_invalid_argument f message =
  match f () with
  | exception Invalid_argument _ -> ()
  | exception error -> raise error
  | () -> failwith message
;;

let widget_of_vertical_viewport viewport =
  viewport
  |> Ui.View.Viewport.Vertical.with_height ~height:240.
  |> Ui.View.For_testing.children
  |> fun children -> children.(0)
;;

let keyed ~key widget = Ui.View.Keyed.create ~key widget

let test_keyed_widget_root_evidence () =
  let old_key = Ui.Key.string "old-root" in
  let new_key = Ui.Key.string "new-root" in
  let test_id = Ui.Test_id.string "keyed-root" in
  let original = Ui.View.text ~key:old_key "Keyed row" |> Ui.View.with_test_id test_id in
  let canonical = Ui.View.text ~key:new_key "Keyed row" |> Ui.View.with_test_id test_id in
  let catalog =
    Ui.View.Collection.Catalog.create ~keys:[ new_key ] ~default_extent:48. ()
  in
  let viewport =
    Ui.View.Collection.vertical
      ~catalog
      ~first_index:0
      ~items:[ keyed ~key:new_key original ]
      ~on_visible_range:(Ui.Event.Handler.create (fun _ -> ()))
      ()
  in
  let (Av original_view) = Ui.View.Private.view original in
  let (Av canonical_view) = Ui.View.Private.view canonical in
  let owner = widget_of_vertical_viewport viewport in
  let (Av window) = Ui.View.Private.view (Ui.View.For_testing.children owner).(0) in
  check (Array.length window.children = 1) "keyed item added a wrapper node";
  let (Av keyed_view) = Ui.View.Private.view window.children.(0) in
  check
    (Ui.View.Private.kind_tag_equal
       (Ui.View.Private.node_kind_tag keyed_view.node)
       Ui.View.Private.K_text)
    "keyed item changed the root widget kind";
  check (Array.length keyed_view.children = 0) "keyed item changed root children";
  check
    (Option.equal Ui.Key.equal original_view.key (Some old_key))
    "keyed construction mutated the input widget";
  check
    (Option.equal Ui.Key.equal keyed_view.key (Some new_key))
    "keyed construction did not replace the root key";
  check
    (Option.equal Ui.Test_id.equal keyed_view.test_id (Some test_id))
    "keyed construction lost the root test ID";
  check
    (Int64.equal keyed_view.fingerprint canonical_view.fingerprint)
    "keyed construction did not recompute the canonical root fingerprint"
;;

let test_collection_window_boundaries_and_callback () =
  let module C = Ui.View.Collection in
  let check_window count overscan first last expected_first expected_last =
    let catalog =
      C.Catalog.create ~keys:(List.init count Ui.Key.int) ~default_extent:48. ~overscan ()
    in
    let window =
      C.Window.create ~catalog ~visible_first_index:first ~visible_last_exclusive:last
    in
    check
      (window.first_index = expected_first && window.last_exclusive = expected_last)
      "collection window did not clamp its overscan"
  in
  List.iter
    (fun (count, overscan, first, last, expected_first, expected_last) ->
       check_window count overscan first last expected_first expected_last)
    [ 0, 4, 0, 0, 0, 0
    ; 100, 4, 1, 8, 0, 12
    ; 100, 4, 20, 28, 16, 32
    ; 100, 4, 95, 100, 91, 100
    ; 5, 100, 2, 3, 0, 5
    ];
  let catalog =
    C.Catalog.create
      ~keys:(List.init 1000 Ui.Key.int)
      ~default_extent:48.
      ~overrides:[ { C.index = 3; extent = 120. }; { C.index = 104; extent = 312. } ]
      ()
  in
  List.iter
    (fun (first, last) ->
       expect_invalid_argument
         (fun () ->
            ignore
              (C.Window.create
                 ~catalog
                 ~visible_first_index:first
                 ~visible_last_exclusive:last))
         "invalid collection visible range was accepted")
    [ -1, 0; 5, 4; 0, 1001 ];
  let received = ref None in
  let handler =
    Ui.Event.Handler.create (fun payload ->
      received := C.visible_range_of_payload payload)
  in
  let viewport =
    C.vertical
      ~catalog
      ~first_index:100
      ~items:
        (List.init 20 (fun offset ->
           let index = 100 + offset in
           keyed ~key:(Ui.Key.int index) (Ui.View.text (string_of_int index))))
      ~on_visible_range:handler
      ()
  in
  let (Av owner) = Ui.View.Private.view (widget_of_vertical_viewport viewport) in
  let children = Ui.View.For_testing.children owner.children.(0) in
  check (Array.length children = 20) "collection mounted more than its supplied window";
  Array.iteri
    (fun offset child ->
       let (Av row) = Ui.View.Private.view child in
       check
         (Option.equal Ui.Key.equal row.key (Some (Ui.Key.int (100 + offset))))
         "collection changed a keyed row root")
    children;
  let binding =
    Array.find_opt
      (fun (binding : Ui.View.Private.event_binding) ->
         Ui.Event.Tag.equal binding.tag Ui.Event.Tag.Visible_range_changed)
      owner.event_bindings
  in
  let binding = Option.get binding in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Visible_range { first_index = 104L; last_exclusive = 116L });
  check
    (!received = Some { Ui.Event.Payload.first_index = 104L; last_exclusive = 116L })
    "collection visible range callback lost its bounds"
;;

type dial_event = Changed of int

let dial_extension =
  Ui.Native_widget.Extension.create
    ~kind_id:(native_kind_id 42)
    ~version:3
    ~capabilities:[ Ui.Native_widget.Capability.Stateful ]
    ~encode_props:(fun value -> Bytes.of_string (string_of_int value))
    ~decode_event:(fun ~event_id payload ->
      if ID.Native_widget.Event_id.equal event_id (native_event_id 7)
      then Ok (Changed (int_of_string (Bytes.to_string payload)))
      else Error "unknown dial event")
    ()
;;

let test_typed_native_widget () =
  let received = ref None in
  let widget =
    Ui.Native_widget.widget
      dial_extension
      ~key:(Ui.Key.string "dial")
      ~props:17
      ~on_event:(fun event -> received := Some event)
      ()
  in
  let (Av view) = Ui.View.Private.view widget in
  check
    (Ui.View.Private.kind_tag_equal
       (Ui.View.Private.node_kind_tag view.node)
       Ui.View.Private.K_native_widget)
    "native widget kind";
  (match view.node with
   | Native_widget { kind_id; version; capabilities; payload } ->
     check (ID.Native_widget.Kind_id.equal kind_id (native_kind_id 42)) "native kind ID";
     check (version = 3) "native version";
     check (Int64.equal capabilities 1L) "native capabilities";
     check (Bytes.equal payload (Bytes.of_string "17")) "native props payload"
   | _ -> failwith "native widget props");
  let binding = view.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 42
       ; version = 3
       ; event_id = native_event_id 7
       ; payload = Bytes.of_string "23"
       });
  check (!received = Some (Changed 23)) "typed native event"
;;

let message_composer_button
      ?(position = Ui.Native_widget.Message_composer.Trailing)
      ?(visibility = Ui.Native_widget.Message_composer.Always)
      ?(style = Ui.Native_widget.Message_composer.Plain)
      ?(enabled = true)
      ~id
      ~tooltip
      label
  =
  Ui.Native_widget.Message_composer.button
    ~id
    ~tooltip
    ~position
    ~visibility
    ~style
    ~enabled
    ~child:(Ui.View.text label)
    ()
;;

let test_message_composer_contract_and_custom_buttons () =
  let events = ref [] in
  let buttons =
    [ message_composer_button
        ~id:10
        ~tooltip:"Add attachment"
        ~position:Leading
        "attachment"
    ; message_composer_button
        ~id:20
        ~tooltip:"Start voice input"
        ~visibility:When_empty
        ~style:Filled
        "voice"
    ; message_composer_button
        ~id:21
        ~tooltip:"Send message"
        ~visibility:When_non_empty
        ~style:Filled
        "send"
    ]
  in
  let widget =
    Ui.Native_widget.Message_composer.create
      ~key:(Ui.Key.string "composer")
      ~autofocus:true
      ~max_lines:7
      ~hint_text:"Ask anything \226\156\168"
      ~buttons
      ~on_event:(fun event -> events := event :: !events)
      ()
  in
  let (Av view) = Ui.View.Private.view widget in
  check (Array.length view.children = 3) "message composer custom button child count";
  Array.iteri
    (fun index expected ->
       let (Av child) = Ui.View.Private.view view.children.(index) in
       match child.node with
       | Ui.View.Private.Text { value; _ } ->
         check (String.equal value expected) "message composer custom button order"
       | _ -> failwith "message composer button child")
    [| "attachment"; "voice"; "send" |];
  (match view.node with
   | Native_widget { kind_id; version; capabilities; payload } ->
     check (kind_id = native_kind_id 6) "message composer kind ID";
     check (version = 1) "message composer schema version";
     check (Int64.equal capabilities 5L) "message composer capabilities";
     let props = Ui.Native_widget.Message_composer.For_testing.decode_props_exn payload in
     check props.enabled "message composer enabled default";
     check props.autofocus "message composer autofocus";
     check (props.max_lines = 7) "message composer max lines";
     check
       (String.equal props.hint_text "Ask anything \226\156\168")
       "message composer UTF-8 hint";
     check (List.length props.buttons = 3) "message composer button metadata count";
     let attachment = List.nth props.buttons 0 in
     check (attachment.id = 10) "message composer button ID";
     check (attachment.position = Leading) "message composer leading button";
     let voice = List.nth props.buttons 1 in
     check (voice.visibility = When_empty) "message composer empty visibility";
     check (voice.style = Filled) "message composer filled style";
     let send = List.nth props.buttons 2 in
     check (send.visibility = When_non_empty) "message composer non-empty visibility"
   | _ -> failwith "message composer native props");
  let binding = view.event_bindings.(0) in
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 6
       ; version = 1
       ; event_id = native_event_id 1
       ; payload = Bytes.of_string "hello \240\159\145\139"
       });
  Ui.Event.Handler.Private.invoke
    binding.handler
    (Native_event
       { kind_id = native_kind_id 6
       ; version = 1
       ; event_id = native_event_id 2
       ; payload =
           (let payload = Bytes.make 12 '\000' in
            Bytes.set_int32_le payload 0 21l;
            Bytes.blit_string "  send  " 0 payload 4 8;
            payload)
       });
  check
    (!events
     = [ Ui.Native_widget.Message_composer.Button_pressed
           { button_id = 21; text = "  send  " }
       ; Text_changed "hello \240\159\145\139"
       ])
    "message composer typed events"
;;

let test_message_composer_validation_and_event_filtering () =
  let button = message_composer_button ~id:1 ~tooltip:"One" "one" in
  List.iter
    (fun max_lines ->
       expect_invalid_argument
         (fun () ->
            ignore
              (Ui.Native_widget.Message_composer.create
                 ~max_lines
                 ~buttons:[]
                 ~on_event:(fun _ -> ())
                 ()))
         "message composer accepted invalid max_lines")
    [ 0; -1; 0x1_0000 ];
  List.iter
    (fun id ->
       expect_invalid_argument
         (fun () -> ignore (message_composer_button ~id ~tooltip:"Invalid" "x"))
         "message composer accepted invalid button ID")
    [ 0; -1; 0x1_0000_0000 ];
  expect_invalid_argument
    (fun () -> ignore (message_composer_button ~id:2 ~tooltip:"" "empty"))
    "message composer accepted empty tooltip";
  expect_invalid_argument
    (fun () ->
       ignore
         (Ui.Native_widget.Message_composer.create
            ~buttons:[ button; button ]
            ~on_event:(fun _ -> ())
            ()))
    "message composer accepted duplicate button IDs";
  let received = ref [] in
  let widget =
    Ui.Native_widget.Message_composer.create
      ~buttons:[ button ]
      ~on_event:(fun event -> received := event :: !received)
      ()
  in
  let binding =
    (let (Av v) = Ui.View.Private.view widget in
     v.event_bindings).(0)
  in
  let invoke kind_id version event_id payload =
    Ui.Event.Handler.Private.invoke
      binding.handler
      (Native_event { kind_id; version; event_id; payload })
  in
  invoke (native_kind_id 99) 1 (native_event_id 1) (Bytes.of_string "ignored");
  invoke (native_kind_id 6) 2 (native_event_id 1) (Bytes.of_string "ignored");
  invoke (native_kind_id 6) 1 (native_event_id 9) Bytes.empty;
  invoke (native_kind_id 6) 1 (native_event_id 2) (Bytes.make 3 '\000');
  check (!received = []) "message composer malformed event was accepted";
  invoke (native_kind_id 6) 1 (native_event_id 1) (Bytes.of_string "accepted");
  check
    (!received = [ Ui.Native_widget.Message_composer.Text_changed "accepted" ])
    "message composer valid event was filtered"
;;

let expandable_message_composer_button
      ?(position = Ui.Native_widget.Expandable_message_composer.Trailing)
      ?(visibility = Ui.Native_widget.Expandable_message_composer.Always)
      ?(style = Ui.Native_widget.Expandable_message_composer.Plain)
      ?(enabled = true)
      ~id
      ~tooltip
      label
  =
  Ui.Native_widget.Expandable_message_composer.button
    ~id
    ~tooltip
    ~position
    ~visibility
    ~style
    ~enabled
    ~child:(Ui.View.text label)
    ()
;;

let (_ :
      ?key:Ui.Key.t
      -> ?enabled:bool
      -> fab_presentation:Ui.Native_widget.Expandable_message_composer.fab_presentation
      -> fab_label:string
      -> fab_tooltip:string
      -> fab_icon:Ui.View.t
      -> ?animation_duration_ms:int
      -> ?animation_curve:Ui.Animation.Curve.t
      -> ?max_lines:int
      -> ?hint_text:string
      -> buttons:Ui.Native_widget.Expandable_message_composer.button list
      -> on_event:(Ui.Native_widget.Expandable_message_composer.event -> unit)
      -> unit
      -> Ui.View.t)
  =
  Ui.Native_widget.Expandable_message_composer.create
;;

let (_ :
      ?key:Ui.Key.t
      -> ?enabled:bool
      -> fab_presentation:Ui.Native_widget.Expandable_message_composer.fab_presentation
      -> fab_label:string
      -> fab_tooltip:string
      -> fab_icon:Ui.View.t
      -> ?animation_duration_ms:int
      -> ?animation_curve:Ui.Animation.Curve.t
      -> ?max_lines:int
      -> ?hint_text:string
      -> buttons:Ui.Native_widget.Expandable_message_composer.button list
      -> on_event:Ui.Event.Handler.t
      -> unit
      -> Ui.View.t)
  =
  Ui.Native_widget.Expandable_message_composer.create_with_handler
;;

let expandable_message_composer_payload widget =
  let (Av view) = Ui.View.Private.view widget in
  match view.node with
  | Native_widget { kind_id; version; capabilities; payload } ->
    check (kind_id = native_kind_id 7) "expandable composer kind ID";
    check (version = 2) "expandable composer schema version";
    check (Int64.equal capabilities 5L) "expandable composer capabilities";
    payload
  | _ -> failwith "expandable composer native props"
;;

let test_expandable_message_composer_contract_and_events () =
  let events = ref [] in
  let buttons =
    [ expandable_message_composer_button
        ~id:10
        ~tooltip:"Add attachment 📎"
        ~position:Leading
        "attachment"
    ; expandable_message_composer_button
        ~id:21
        ~tooltip:"Send message"
        ~visibility:When_non_empty
        ~style:Filled
        ~enabled:false
        "send"
    ]
  in
  let widget =
    Ui.Native_widget.Expandable_message_composer.create
      ~key:(Ui.Key.string "expandable-composer")
      ~enabled:false
      ~fab_presentation:Extended
      ~fab_label:"Capture ✨"
      ~fab_tooltip:"Open capture 🚀"
      ~fab_icon:(Ui.View.text "capture-icon")
      ~animation_duration_ms:375
      ~animation_curve:Ui.Animation.Curve.Ease_out
      ~max_lines:9
      ~hint_text:"Write 你好"
      ~buttons
      ~on_event:(fun event -> events := event :: !events)
      ()
  in
  let (Av view) = Ui.View.Private.view widget in
  check
    (Option.equal Ui.Key.equal view.key (Some (Ui.Key.string "expandable-composer")))
    "expandable composer key";
  check (Array.length view.children = 3) "expandable composer child count";
  Array.iteri
    (fun index expected ->
       let (Av child) = Ui.View.Private.view view.children.(index) in
       match child.node with
       | Ui.View.Private.Text { value; _ } ->
         check (String.equal value expected) "expandable composer child order"
       | _ -> failwith "expandable composer child")
    [| "capture-icon"; "attachment"; "send" |];
  let props =
    widget
    |> expandable_message_composer_payload
    |> Ui.Native_widget.Expandable_message_composer.For_testing.decode_props_exn
  in
  check (not props.enabled) "expandable composer enabled";
  check (props.fab_presentation = Extended) "expandable FAB presentation";
  check (String.equal props.fab_label "Capture ✨") "expandable FAB label";
  check (String.equal props.fab_tooltip "Open capture 🚀") "expandable FAB tooltip";
  check (props.animation_duration_ms = 375) "expandable animation duration";
  check (props.animation_curve = Ui.Animation.Curve.Ease_out) "expandable curve";
  check (props.max_lines = 9) "expandable max lines";
  check (String.equal props.hint_text "Write 你好") "expandable hint";
  check (List.length props.buttons = 2) "expandable button count";
  let attachment = List.nth props.buttons 0 in
  check (attachment.id = 10 && attachment.position = Leading) "expandable leading button";
  let send = List.nth props.buttons 1 in
  check
    (send.visibility = When_non_empty && send.style = Filled && not send.enabled)
    "expandable button metadata";
  let binding = view.event_bindings.(0) in
  let invoke kind_id version event_id payload =
    Ui.Event.Handler.Private.invoke
      binding.handler
      (Native_event { kind_id; version; event_id; payload })
  in
  invoke
    (native_kind_id 7)
    2
    Ui.Native_widget.Expandable_message_composer.text_changed_event_id
    (Bytes.of_string "  hello 👋  ");
  let button_payload = Bytes.make 16 (Char.chr 0) in
  Bytes.set_int32_le button_payload 0 21l;
  Bytes.blit_string "  send  🚀" 0 button_payload 4 12;
  invoke
    (native_kind_id 7)
    2
    Ui.Native_widget.Expandable_message_composer.button_pressed_event_id
    button_payload;
  check
    (!events
     = [ Ui.Native_widget.Expandable_message_composer.Button_pressed
           { button_id = 21; text = "  send  🚀" }
       ; Text_changed "  hello 👋  "
       ])
    "expandable composer typed raw-text events";
  let payload_event event_id payload =
    Ui.Native_widget.Expandable_message_composer.event_of_payload
      (Native_event { kind_id = native_kind_id 7; version = 2; event_id; payload })
  in
  check
    (payload_event
       Ui.Native_widget.Expandable_message_composer.text_changed_event_id
       (Bytes.of_string "text")
     = Some (Ui.Native_widget.Expandable_message_composer.Text_changed "text"))
    "expandable event_of_payload";
  List.iter
    (fun (kind_id, version, event_id, payload) -> invoke kind_id version event_id payload)
    [ native_kind_id 6, 2, native_event_id 1, Bytes.of_string "wrong kind"
    ; native_kind_id 7, 1, native_event_id 1, Bytes.of_string "old version"
    ; native_kind_id 7, 3, native_event_id 1, Bytes.of_string "wrong version"
    ; native_kind_id 7, 2, native_event_id 9, Bytes.empty
    ; native_kind_id 7, 2, native_event_id 2, Bytes.make 3 (Char.chr 0)
    ; native_kind_id 7, 2, native_event_id 2, Bytes.make 4 (Char.chr 0)
    ; ( native_kind_id 7
      , 2
      , native_event_id 1
      , Bytes.of_string (String.make 1 (Char.chr 255)) )
    ];
  check (List.length !events = 2) "expandable malformed event was accepted"
;;

let test_expandable_message_composer_validation_and_malformed_props () =
  let create
        ?(fab_presentation = Ui.Native_widget.Expandable_message_composer.Extended)
        ?(fab_label = "Capture")
        ?(fab_tooltip = "Open capture")
        ?(animation_duration_ms = 200)
        ?(animation_curve = Ui.Animation.Curve.Ease_out)
        ?(max_lines = 5)
        ?(hint_text = "Ask anything")
        ?(buttons = [])
        ()
    =
    Ui.Native_widget.Expandable_message_composer.create
      ~fab_presentation
      ~fab_label
      ~fab_tooltip
      ~fab_icon:(Ui.View.empty ())
      ~animation_duration_ms
      ~animation_curve
      ~max_lines
      ~hint_text
      ~buttons
      ~on_event:(fun _ -> ())
      ()
  in
  List.iter
    (fun duration ->
       expect_invalid_argument
         (fun () -> ignore (create ~animation_duration_ms:duration ()))
         "expandable composer accepted invalid duration")
    [ -1; 0x1_0000 ];
  List.iter
    (fun max_lines ->
       expect_invalid_argument
         (fun () -> ignore (create ~max_lines ()))
         "expandable composer accepted invalid max_lines")
    [ 0; -1; 0x1_0000 ];
  let invalid_utf8 = String.make 1 (Char.chr 255) in
  List.iter
    (fun (label, tooltip, hint) ->
       expect_invalid_argument
         (fun () ->
            ignore (create ~fab_label:label ~fab_tooltip:tooltip ~hint_text:hint ()))
         "expandable composer accepted invalid UTF-8 or empty required text")
    [ "", "tooltip", "hint"
    ; "label", "", "hint"
    ; invalid_utf8, "tooltip", "hint"
    ; "label", invalid_utf8, "hint"
    ; "label", "tooltip", invalid_utf8
    ];
  List.iter
    (fun id ->
       expect_invalid_argument
         (fun () ->
            ignore (expandable_message_composer_button ~id ~tooltip:"Invalid" "x"))
         "expandable composer accepted invalid button ID")
    [ 0; -1; 0x1_0000_0000 ];
  expect_invalid_argument
    (fun () -> ignore (expandable_message_composer_button ~id:1 ~tooltip:"" "x"))
    "expandable composer accepted empty button tooltip";
  expect_invalid_argument
    (fun () ->
       ignore (expandable_message_composer_button ~id:1 ~tooltip:invalid_utf8 "x"))
    "expandable composer accepted invalid button tooltip UTF-8";
  let duplicate = expandable_message_composer_button ~id:1 ~tooltip:"One" "one" in
  expect_invalid_argument
    (fun () -> ignore (create ~buttons:[ duplicate; duplicate ] ()))
    "expandable composer accepted duplicate button IDs";
  let valid = expandable_message_composer_payload (create ()) in
  let compact =
    expandable_message_composer_payload (create ~fab_presentation:Compact ())
  in
  let compact_props =
    Ui.Native_widget.Expandable_message_composer.For_testing.decode_props_exn compact
  in
  check (Bytes.get_uint8 valid 20 = 0) "extended presentation byte";
  check (Bytes.get_uint8 compact 20 = 1) "compact presentation byte";
  check (compact_props.fab_presentation = Compact) "compact presentation round trip";
  let handler_widget =
    Ui.Native_widget.Expandable_message_composer.create_with_handler
      ~fab_presentation:Compact
      ~fab_label:"Capture"
      ~fab_tooltip:"Open capture"
      ~fab_icon:(Ui.View.empty ())
      ~buttons:[]
      ~on_event:(Ui.Event.Handler.create (fun _ -> ()))
      ()
  in
  let handler_props =
    handler_widget
    |> expandable_message_composer_payload
    |> Ui.Native_widget.Expandable_message_composer.For_testing.decode_props_exn
  in
  check
    (handler_props.fab_presentation = Compact)
    "create_with_handler compact presentation";
  let invalid_payloads =
    [ Bytes.sub valid 0 23
    ; Bytes.cat valid (Bytes.make 1 (Char.chr 0))
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 0 (Char.chr 2);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 1 (Char.chr 4);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 20 (Char.chr 2);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 21 (Char.chr 1);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 22 (Char.chr 1);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 23 (Char.chr 1);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 4 (Char.chr 0);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 8 (Char.chr 0);
       bytes)
    ; (let bytes = Bytes.copy valid in
       Bytes.set bytes 24 (Char.chr 255);
       bytes)
    ]
  in
  List.iter
    (fun payload ->
       expect_invalid_argument
         (fun () ->
            ignore
              (Ui.Native_widget.Expandable_message_composer.For_testing.decode_props_exn
                 payload))
         "expandable composer accepted malformed props")
    invalid_payloads
;;

let test_native_scroll_sections_contract () =
  let module S = Ui.View.Scroll_sections in
  let key = Ui.Key.string "section" in
  let row = keyed ~key:(Ui.Key.string "row") (Ui.View.text "Row") in
  let section = S.section ~key ~header:(Ui.View.text "Header") [ row ] in
  let hero =
    S.hero ~key:(Ui.Key.string "hero") ~height:160. ~stretch:true (Ui.View.text "Hero")
  in
  let (Av view) =
    Ui.View.Private.view
      (widget_of_vertical_viewport (S.vertical ~pin_headers:true [ hero; section ]))
  in
  check (Array.length view.children = 2) "native sections lost their children";
  let (Av section_view) = Ui.View.Private.view view.children.(1) in
  check (Array.length section_view.children = 3) "header/footer slots must precede rows";
  let (Av header) = Ui.View.Private.view section_view.children.(0) in
  check (Option.is_none header.key) "header wrapper must not claim an application row key";
  List.iter
    (fun f -> expect_invalid_argument f "invalid native section construction accepted")
    [ (fun () -> ignore (S.vertical [ section; section ]))
    ; (fun () -> ignore (S.vertical [ section; hero ]))
    ; (fun () -> ignore (S.horizontal [ hero ]))
    ; (fun () -> ignore (S.section ~key [ row; row ]))
    ; (fun () -> ignore (S.vertical ~spacing:Float.nan []))
    ; (fun () -> ignore (S.vertical ~spacing:(-1.) []))
    ; (fun () -> ignore (S.hero ~key ~height:0. (Ui.View.empty ())))
    ; (fun () -> ignore (S.hero ~key ~height:Float.infinity (Ui.View.empty ())))
    ]
;;

let () =
  test_native_scroll_sections_contract ();
  test_typed_native_widget ();
  test_keyed_widget_root_evidence ();
  test_collection_window_boundaries_and_callback ();
  test_message_composer_contract_and_custom_buttons ();
  test_message_composer_validation_and_event_filtering ();
  test_expandable_message_composer_contract_and_events ();
  test_expandable_message_composer_validation_and_malformed_props ()
;;
