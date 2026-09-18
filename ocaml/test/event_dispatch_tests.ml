module Protocol = Bonsai_swiftui_protocol
module Runtime = Bonsai_swiftui_runtime
module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

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
  Bytes.init
    (String.length compact / 2)
    (fun index ->
       let offset = index * 2 in
       Char.chr ((digit compact.[offset] lsl 4) lor digit compact.[offset + 1]))
;;

let press_batch () =
  let path =
    let from_root = "protocol/generated/fixtures/swift_counter_press.hex" in
    if Sys.file_exists from_root
    then from_root
    else "../../protocol/generated/fixtures/swift_counter_press.hex"
  in
  let channel = open_in_bin path in
  let bytes =
    Fun.protect
      ~finally:(fun () -> close_in channel)
      (fun () -> really_input_string channel (in_channel_length channel) |> bytes_of_hex)
  in
  match Protocol.Event_batch_codec.decode bytes with
  | Ok batch -> batch
  | Error error -> fail "fixture decode failed: %s" error.message
;;

let test_counter_press_dispatch () =
  let invocations = ref 0 in
  let handler =
    Ui.Event.Handler.create ~name:"increment" (function
      | Unit -> incr invocations
      | _ -> fail "press delivered a non-unit payload")
  in
  let frame =
    Runtime.Handler_registry.Frame.Private.create
      ~revision:(ID.Runtime.Renderer_revision.of_int64 1L)
      [ { node_id = Runtime.Node_id.Private.of_int64 3L
        ; event_tag = Ui.Event.Tag.Press
        ; handler_id = Runtime.Handler_id.Private.of_int64 9001L
        ; handler
        }
      ]
  in
  let registry =
    Runtime.Handler_registry.create ~runtime_epoch:(ID.Runtime.Epoch.of_int64 21L)
  in
  (match Runtime.Handler_registry.install registry frame with
   | Ok () -> ()
   | Error error -> fail "install failed: %s" (Runtime.Runtime_error.to_string error));
  (match
     Runtime.Handler_registry.commit_displayed_revision
       registry
       ~revision:(ID.Runtime.Renderer_revision.of_int64 1L)
   with
   | Ok () -> ()
   | Error error ->
     fail "frame presentation failed: %s" (Runtime.Runtime_error.to_string error));
  (match Runtime.Event_dispatcher.dispatch_batch registry (press_batch ()) with
   | Ok () -> ()
   | Error _ -> fail "event batch dispatch failed");
  expect (!invocations = 1) "Counter press did not invoke exactly one handler"
;;

let test_text_edit_dispatch () =
  let received = ref None in
  let handler =
    Ui.Event.Handler.create ~name:"edit" (function
      | Text_edit edit -> received := Some edit
      | _ -> fail "text edit delivered the wrong payload")
  in
  let frame =
    Runtime.Handler_registry.Frame.Private.create
      ~revision:(ID.Runtime.Renderer_revision.of_int64 2L)
      [ { node_id = Runtime.Node_id.Private.of_int64 4L
        ; event_tag = Ui.Event.Tag.Text_edit
        ; handler_id = Runtime.Handler_id.Private.of_int64 44L
        ; handler
        }
      ]
  in
  let registry =
    Runtime.Handler_registry.create ~runtime_epoch:(ID.Runtime.Epoch.of_int64 22L)
  in
  (match Runtime.Handler_registry.install registry frame with
   | Ok () -> ()
   | Error error -> fail "install failed: %s" (Runtime.Runtime_error.to_string error));
  (match
     Runtime.Handler_registry.commit_displayed_revision
       registry
       ~revision:(ID.Runtime.Renderer_revision.of_int64 2L)
   with
   | Ok () -> ()
   | Error error ->
     fail "frame presentation failed: %s" (Runtime.Runtime_error.to_string error));
  let batch =
    Protocol.Inbound_event.
      { runtime_epoch = ID.Runtime.Epoch.of_int64 22L
      ; events =
          [ { sequence = ID.Runtime.Event_sequence.of_int64 1L
            ; displayed_revision = ID.Runtime.Renderer_revision.of_int64 2L
            ; node_id = ID.Ui.Node_id.of_int64 4L
            ; handler_id = ID.Ui.Handler_id.of_int64 44L
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
  in
  (match Runtime.Event_dispatcher.dispatch_batch registry batch with
   | Ok () -> ()
   | Error _ -> fail "text edit dispatch failed");
  match !received with
  | Some edit ->
    expect
      (ID.Text_input.Local_revision.equal
         edit.local_revision
         (ID.Text_input.Local_revision.of_int64 3L))
      "local revision changed";
    expect (String.equal edit.text "拼😀音") "text changed";
    expect (Option.is_some edit.composing) "composing range was lost"
  | None -> fail "text edit handler was not invoked"
;;

let () =
  test_counter_press_dispatch ();
  test_text_edit_dispatch ();
  print_endline "event dispatch tests passed"
;;

let test_list_scroll_terminal_ownership () =
  let module H = Runtime.Handler_registry in
  let revision n = ID.Runtime.Renderer_revision.of_int64 n in
  let owner = Runtime.Node_id.Private.of_int64 40L in
  let epoch = ID.Runtime.Epoch.of_int64 21L in
  let original_calls = ref 0
  and replacement_calls = ref 0 in
  let entry id calls : H.Frame.entry =
    { node_id = owner
    ; event_tag = Ui.Event.Tag.List_scroll_completed
    ; handler_id = Runtime.Handler_id.Private.of_int64 id
    ; handler = Ui.Event.Handler.create (fun _ -> incr calls)
    }
  in
  let original = entry 90L original_calls
  and replacement = entry 91L replacement_calls in
  let registry = H.create ~runtime_epoch:epoch in
  let success = function
    | Ok x -> x
    | Error e -> fail "%s" (Runtime.Runtime_error.to_string e)
  in
  let rejected = function
    | Error _ -> ()
    | Ok _ -> fail "invalid terminal callback was admitted"
  in
  let current_revision = ref (revision 1L) in
  let install n entries =
    current_revision := revision n;
    success (H.install registry (H.Frame.Private.create ~revision:(revision n) entries));
    success (H.commit_displayed_revision registry ~revision:(revision n))
  in
  let own token binding =
    H.retain_list_scroll_completion registry ~revision:!current_revision ~token binding
  in
  let event
        ?(handler = original.handler_id)
        ?(node = owner)
        ?(epoch = epoch)
        ?(displayed = 5L)
        ?(outcome = 0L)
        sequence
        token
    : H.event
    =
    { runtime_epoch = epoch
    ; displayed_revision = revision displayed
    ; node_id = node
    ; event_tag = Ui.Event.Tag.List_scroll_completed
    ; handler_id = handler
    ; event_sequence = ID.Runtime.Event_sequence.of_int64 sequence
    ; payload = Ui.Event.Payload.Int64_pair { first = token; second = outcome }
    }
  in
  install 1L [ original ];
  own 1L original;
  List.iter
    (fun n ->
       install n [ replacement ];
       own 1L replacement)
    [ 2L; 3L; 4L; 5L ];
  expect (H.retained_frame_count registry = 2) "terminal retention kept whole old frames";
  rejected (H.dispatch registry (event ~handler:replacement.handler_id 1L 1L));
  rejected
    (H.dispatch registry (event ~node:(Runtime.Node_id.Private.of_int64 41L) 1L 1L));
  rejected (H.dispatch registry (event ~epoch:(ID.Runtime.Epoch.of_int64 22L) 1L 1L));
  rejected (H.dispatch registry (event ~displayed:6L 1L 1L));
  rejected (H.dispatch registry (event ~outcome:6L 1L 1L));
  rejected (H.dispatch registry { (event 1L 1L) with payload = Ui.Event.Payload.Unit });
  rejected (H.dispatch_batch registry [ event 1L 1L; event 2L 1L ]);
  expect (!original_calls = 0 && !replacement_calls = 0) "invalid batch invoked a handler";
  success (H.dispatch registry (event 1L 1L));
  expect
    (!original_calls = 1 && !replacement_calls = 0)
    "completion did not retain its original handler";
  rejected (H.dispatch registry (event 2L 1L));
  own 1L replacement;
  rejected (H.dispatch registry (event ~handler:replacement.handler_id 2L 1L));
  own 2L replacement;
  rejected
    (H.dispatch registry (event ~displayed:4L ~handler:replacement.handler_id 2L 2L));
  install 6L [];
  (* Clearing the request leaves its captured cancellation handler live. *)
  success
    (H.dispatch
       registry
       (event ~displayed:6L ~handler:replacement.handler_id ~outcome:3L 2L 2L));
  expect (!replacement_calls = 1) "clearing a request lost its cancellation callback";
  own 3L replacement;
  H.dispose_list_scroll_owner registry owner;
  rejected
    (H.dispatch registry (event ~displayed:6L ~handler:replacement.handler_id 3L 3L));
  rejected
    (H.dispatch
       registry
       { (event ~displayed:1L 3L 1L) with event_tag = Ui.Event.Tag.Press });
  install 7L [ replacement ];
  own 4L replacement;
  let validated =
    success
      (H.validate_batch
         registry
         [ event ~displayed:7L ~handler:replacement.handler_id 3L 4L ])
  in
  H.dispose_list_scroll_owner registry owner;
  rejected (H.dispatch_validated registry validated);
  own 5L replacement;
  let validated =
    success
      (H.validate_batch
         registry
         [ event ~displayed:7L ~handler:replacement.handler_id 3L 5L ])
  in
  success (H.dispatch_validated registry validated);
  rejected (H.dispatch_validated registry validated);
  expect (!replacement_calls = 2) "disposed or consumed terminal snapshot was replayed";
  H.clear registry;
  rejected (H.dispatch registry (event ~displayed:6L 3L 1L))
;;

let () = test_list_scroll_terminal_ownership ()
