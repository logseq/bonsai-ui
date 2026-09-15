module Test = Bonsai_swiftui_test
module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id
module Runtime = Bonsai_swiftui_runtime

let require b message = if not b then failwith message
let query = Test.Query.test_id
let node h id = Option.get (Test.Handle.find h (query id))
let present h id = Option.is_some (Test.Handle.find h (query id))
let text h value = Option.is_some (Test.Handle.find h (Test.Query.visible_text value))

let click h id =
  Test.Handle.present h;
  Test.Handle.click h (query id)
;;

let emit h id tag payload =
  Test.Handle.present h;
  let (Av view) = Ui.View.Private.view (node h id).widget in
  let binding =
    Array.find_opt
      (fun (b : Ui.View.Private.event_binding) -> Ui.Event.Tag.equal b.tag tag)
      view.event_bindings
    |> Option.get
  in
  Ui.Event.Handler.Private.invoke binding.handler payload;
  Test.Handle.pump_next h ()
;;

let menu h id value = emit h id Ui.Event.Tag.Menu_action (Ui.Event.Payload.Int64 value)

let sheet_open h =
  let (Av v) = Ui.View.Private.view (node h "templates-sheet").widget in
  match v.node with
  | Ui.View.Private.Sheet { presented; _ } -> presented
  | _ -> false
;;

let input h id value =
  Test.Handle.present h;
  Test.Handle.input_text h (query id) value
;;

let with_handle f =
  let h =
    Test.Handle.create
      ~runtime_epoch:(ID.Runtime.Epoch.of_int64 912L)
      ~time_source:(Bonsai.Time_source.create ~start:Core.Time_ns.epoch)
      Note.component
  in
  Fun.protect ~finally:(fun () -> Test.Handle.shutdown h) (fun () -> f h)
;;

let cases =
  [ ( "initial document and light appearance"
    , fun h ->
        require (text h "Cornell Note Template") "Missing seeded Cornell document";
        require (not (sheet_open h)) "Templates initially presented";
        require (present h "document-background") "Missing shared background";
        require (present h "bottom-controls") "Missing anchored tools" )
  ; ( "templates search, empty, clear and native dismissal"
    , fun h ->
        click h "back";
        require (sheet_open h) "Back did not open templates";
        require (not (present h "clear-search")) "Empty search has a clear control";
        input h "template-search" "  READING  ";
        require (present h "clear-search") "Nonempty search lacks a clear control";
        require (present h "template-reading") "Case-insensitive search lost reading";
        require (not (present h "template-cornell")) "Search did not filter Cornell";
        input h "template-search" "no such template";
        require (text h "No templates found") "Missing empty state";
        click h "clear-search";
        require (text h "MY TEMPLATES") "Clear did not restore categories";
        emit h "templates-sheet" Ui.Event.Tag.Value_changed (Ui.Event.Payload.Bool false);
        require
          ((not (sheet_open h)) && text h "Cornell Note Template")
          "Dismissal changed the note" )
  ; ( "selection, close, and seed isolation"
    , fun h ->
        menu h "more-menu" 1L;
        click h "template-reading";
        require
          ((not (sheet_open h)) && text h "Robert Pirosh")
          "Reading selection failed";
        click h "back";
        click h "close-templates";
        require (text h "Robert Pirosh") "Close discarded the note";
        click h "back";
        click h "template-cornell";
        require (text h "Cornell Note Template") "Cornell selection failed" )
  ; ( "independent disclosures retain identity"
    , fun h ->
        let id = (node h "disclosure-key-points").node_id in
        require (not (present h "details-key-points")) "Initially expanded";
        click h "disclosure-key-points";
        click h "disclosure-supporting-details";
        require
          (present h "details-key-points" && present h "details-supporting-details")
          "Not independently expanded";
        click h "disclosure-key-points";
        require
          ((not (present h "details-key-points"))
           && present h "details-supporting-details")
          "Collapse affected sibling";
        require
          (Runtime.Node_id.equal id (node h "disclosure-key-points").node_id)
          "Disclosure identity changed" )
  ; ( "editing, Unicode, reopening and fresh template"
    , fun h ->
        click h "edit";
        input h "title-editor" "Field notes 🌿";
        input h "body-editor" "A new observation.\nA second line.";
        click h "done-editing";
        require
          (text h "Field notes 🌿" && text h "A new observation.\nA second line.")
          "Edits did not reach styled view";
        click h "edit";
        click h "done-editing";
        require (text h "Field notes 🌿") "Reopening lost session edits";
        click h "back";
        click h "template-cornell";
        require
          (text h "Cornell Note Template" && not (text h "Field notes 🌿"))
          "Edited deterministic seed" )
  ; ( "themes, insertion and named mock actions"
    , fun h ->
        menu h "theme-menu" 2L;
        require (present h "theme-cool") "Theme did not change";
        menu h "insert-menu" 1L;
        menu h "insert-menu" 2L;
        require
          (text h "A new paragraph to explore." && text h "Review this note")
          "Insertion missing";
        menu h "tools-menu" 1L;
        require (text h "Word count preview") "Tool produced no result";
        click h "close-preview";
        click h "share";
        require (text h "Share preview") "Share produced no mock result";
        click h "close-preview";
        menu h "theme-menu" 1L;
        require (present h "theme-warm") "Warm theme did not return";
        click h "back";
        click h "template-cornell";
        require (not (text h "A new paragraph to explore.")) "Insertion mutated seed" )
  ]
;;

let test_clearing_search_rejects_edits_from_the_replaced_input_session h =
  click h "back";
  input h "template-search" "reading";
  let (Av view) = Ui.View.Private.view (node h "template-search").widget in
  let delayed =
    match view.node with
    | Ui.View.Private.Text_field
        { session_id; document_revision; accepted_local_revision; _ } ->
      Ui.Event.Payload.Text_edit
        { session_id
        ; base_document_revision = document_revision
        ; local_revision = ID.Text_input.Local_revision.succ accepted_local_revision
        ; text = "obsolete"
        ; selection = { start_utf16 = 8; end_utf16 = 8 }
        ; composing = None
        }
    | _ -> failwith "Expected search input"
  in
  click h "clear-search";
  emit h "template-search" Ui.Event.Tag.Text_edit delayed;
  require (text h "MY TEMPLATES") "A delayed edit resurrected the cleared query"
;;

let () =
  let failures = ref [] in
  List.iter
    (fun (name, test) ->
       try
         with_handle test;
         Printf.printf "PASS: %s\n%!" name
       with
       | e ->
         failures := name :: !failures;
         Printf.eprintf "FAIL: %s: %s\n%!" name (Printexc.to_string e))
    (( "cleared search rejects delayed edits"
     , test_clearing_search_rejects_edits_from_the_replaced_input_session )
     :: cases);
  require (!failures = []) "Note behavior acceptance failed"
;;
