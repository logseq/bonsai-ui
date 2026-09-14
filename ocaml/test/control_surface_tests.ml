module Ui = Bonsai_swiftui_ui

let handler = Ui.Event.Handler.create (fun _ -> ())
let text value = Ui.View.text value
let expect condition message = if not condition then failwith message

let text_value text =
  let offset = Ui.Text_editing.Utf16.length text in
  let selection =
    Ui.Text_editing.Range.create ~text ~start_utf16:offset ~end_utf16:offset
  in
  Ui.Text_editing.Value.create ~text ~selection ()
;;

let native_text_field ?(read_only = false) ?(autofocus = false) () =
  Ui.View.text_field
    ~label:"Text input"
    ~read_only
    ~autofocus
    ~session_id:(Bonsai_swiftui_spec.Id.Text_input.Session_id.of_int64 9L)
    ~document_revision:(Bonsai_swiftui_spec.Id.Text_input.Document_revision.of_int64 3L)
    ~accepted_local_revision:
      (Bonsai_swiftui_spec.Id.Text_input.Local_revision.of_int64 2L)
    ~update_mode:Ui.Text_editing.Ack
    ~value:(text_value "draft")
    ~on_edit:handler
    ~on_submit:handler
    ~on_focus_changed:handler
    ()
;;

let expect_invalid_arg label f =
  match f () with
  | exception Invalid_argument _ -> ()
  | _ -> failwith (label ^ " did not reject invalid input")
;;

let picker_options =
  [ Ui.View.Picker.option ~id:10L ~label:(text "First") ()
  ; Ui.View.Picker.option ~id:20L ~enabled:false ~label:(text "Second") ()
  ]
;;

let data_columns =
  [ Ui.View.Table.column ~id:10L ~sortable:true ~title:"Name" ()
  ; Ui.View.Table.column ~id:20L ~numeric:true ~title:"Score" ()
  ]
;;

let data_rows = [ Ui.View.Table.row ~id:100L [ text "Ada"; text "42" ] ]

let steps =
  [ Ui.Workflow.step ~id:1L ~title:(text "Account") ~content:(text "Account form") ()
  ; Ui.Workflow.step
      ~id:2L
      ~state:Ui.Workflow.Complete
      ~title:(text "Review")
      ~content:(text "Review form")
      ()
  ]
;;

let widgets =
  [ Ui.View.button ~style:Prominent ~on_press:handler ~child:(text "Prominent") ()
  ; Ui.View.button ~style:Bordered ~on_press:handler ~child:(text "Bordered") ()
  ; Ui.View.button ~role:Destructive ~on_press:handler ~child:(text "Delete") ()
  ; Ui.View.button ~on_press:handler ~child:(text "Automatic") ()
  ; Ui.View.button ~style:Plain ~on_press:handler ~child:(text "Plain") ()
  ; Ui.View.button ~on_press:handler ~child:(text "Small") ()
    |> Ui.View.control_size ~size:Small
  ; Ui.View.button ~on_press:handler ~child:(text "Regular") ()
    |> Ui.View.control_size ~size:Regular
  ; Ui.View.button
      ~on_press:handler
      ~child:(Ui.View.row [ text "Extended icon"; text "Extended" ])
      ()
    |> Ui.View.control_size ~size:Large
  ; native_text_field ~read_only:true ~autofocus:true ()
  ; Ui.View.Table.create
      ~sort_column_id:10L
      ~selected_row_ids:[ 100L ]
      ~on_sort:handler
      ~on_row_selected:handler
      ~columns:data_columns
      ~rows:data_rows
      ()
    |> Ui.View.Body.with_size ~width:640. ~height:400.
  ; Ui.View.disclosure_group
      ~expanded:true
      ~on_changed:handler
      ~label:(text "Details")
      ~content:(text "Body")
      ()
  ; Ui.View.Date_picker.create
      ~selected:(Ui.View.Date.create ~year:2026 ~month:9 ~day:3)
      ~first:(Ui.View.Date.create ~year:2020 ~month:1 ~day:1)
      ~last:(Ui.View.Date.create ~year:2030 ~month:12 ~day:31)
      ~on_select:handler
      ()
  ; Ui.View.Time_picker.create
      ~value:(Ui.View.Time.create ~hour:9 ~minute:30)
      ~on_changed:handler
      ()
  ; Ui.View.Picker.create ~selected_id:(Some 10L) ~on_select:handler picker_options ()
  ; Ui.View.Slider.create
      ~value:0.25
      ~min:0.
      ~max:1.
      ~step:0.25
      ~label:"Quarter"
      ~on_change:handler
      ~on_change_end:handler
      ()
  ; Ui.View.Slider.range
      ~label_start:"Lower value"
      ~label_end:"Upper value"
      ~value:(Ui.View.Slider.Range.create ~start:0.25 ~end_:0.75)
      ~min:0.
      ~max:1.
      ~step:0.25
      ~on_change:handler
      ~on_change_end:handler
      ()
  ; Ui.View.toggle
      ~style:Ui.View.Toggle_style.Switch
      ~label:(Ui.View.text "Enabled")
      ~value:true
      ~on_changed:handler
      ()
  ; Ui.View.divider ()
  ; Ui.View.group_box ~label:(text "Title") (text "Card")
  ; Ui.View.progress ~style:Ui.View.Progress_style.Circular ~value:0.5 ()
  ; Ui.View.progress ~value:0.5 ()
  ; Ui.View.progress ()
  ; Ui.View.toggle
      ~style:Ui.View.Toggle_style.Switch
      ~label:(Ui.View.text "Notifications")
      ~value:true
      ~on_changed:handler
      ()
  ]
;;

let expected =
  [ "Button"
  ; "Button"
  ; "Button"
  ; "Button"
  ; "Button"
  ; "Control_size"
  ; "Control_size"
  ; "Control_size"
  ; "Text_field"
  ; "Frame"
  ; "Disclosure_group"
  ; "Date_picker"
  ; "Time_picker"
  ; "Picker"
  ; "Slider"
  ; "Range_slider"
  ; "Toggle"
  ; "Divider"
  ; "Group_box"
  ; "Progress"
  ; "Progress"
  ; "Progress"
  ; "Toggle"
  ]
;;

let test_constructor_kinds () =
  let actual = List.map Ui.View.For_testing.kind_name widgets in
  if List.length actual <> List.length expected
  then failwith "Native constructor-kind list lengths differ";
  List.iteri
    (fun index actual ->
       let expected = List.nth expected index in
       if not (String.equal actual expected)
       then
         failwith
           (Printf.sprintf
              "Native constructor kind %d is %s, expected %s"
              index
              actual
              expected))
    actual
;;

let test_picker_validation () =
  expect_invalid_arg "duplicate picker option IDs" (fun () ->
    Ui.View.Picker.create
      ~selected_id:(Some 10L)
      ~on_select:handler
      [ Ui.View.Picker.option ~id:10L (); Ui.View.Picker.option ~id:10L () ]
      ());
  expect_invalid_arg "missing selected picker option" (fun () ->
    Ui.View.Picker.create ~selected_id:(Some 99L) ~on_select:handler picker_options ())
;;

let test_slider_validation () =
  let slider ?(value = 0.5) ?(min = 0.) ?(max = 1.) ?step () =
    Ui.View.Slider.create ~label:"Value" ~value ~min ~max ?step ~on_change_end:handler ()
  in
  expect_invalid_arg "non-finite slider value" (fun () -> slider ~value:nan ());
  expect_invalid_arg "reversed slider domain" (fun () -> slider ~min:2. ~max:1. ());
  expect_invalid_arg "out-of-range slider value" (fun () -> slider ~value:2. ());
  expect_invalid_arg "non-positive slider step" (fun () -> slider ~step:0. ());
  expect_invalid_arg "reversed range selection" (fun () ->
    Ui.View.Slider.range
      ~label_start:"Lower value"
      ~label_end:"Upper value"
      ~value:(Ui.View.Slider.Range.create ~start:0.8 ~end_:0.2)
      ~on_change_end:handler
      ())
;;

let test_fingerprints_include_controlled_values () =
  let first = Ui.View.Slider.create ~label:"Value" ~value:0.2 ~on_change_end:handler () in
  let second =
    Ui.View.Slider.create ~label:"Value" ~value:0.8 ~on_change_end:handler ()
  in
  expect
    (not (Ui.View.Private.node_equal_widgets first second))
    "slider controlled value was omitted from logical equality"
;;

let test_text_field_identity_includes_read_only_and_autofocus () =
  let default = native_text_field () in
  expect
    (not
       (Ui.View.Private.node_equal_widgets default (native_text_field ~read_only:true ())))
    "text field read_only was omitted from logical equality";
  expect
    (not
       (Ui.View.Private.node_equal_widgets default (native_text_field ~autofocus:true ())))
    "text field autofocus was omitted from logical equality"
;;

let test_additional_component_validation () =
  expect_invalid_arg "empty tooltip message" (fun () ->
    Ui.View.help ~message:"  " (text "child"));
  expect_invalid_arg "empty table columns" (fun () ->
    Ui.View.Table.create ~columns:[] ~rows:[] ());
  expect_invalid_arg "duplicate table column IDs" (fun () ->
    Ui.View.Table.create
      ~columns:
        [ Ui.View.Table.column ~id:1L ~title:"A" ()
        ; Ui.View.Table.column ~id:1L ~title:"B" ()
        ]
      ~rows:[]
      ());
  expect_invalid_arg "wrong table row width" (fun () ->
    Ui.View.Table.create
      ~columns:data_columns
      ~rows:[ Ui.View.Table.row ~id:1L [ text "A" ] ]
      ());
  expect_invalid_arg "unknown table sort column" (fun () ->
    Ui.View.Table.create ~sort_column_id:99L ~columns:data_columns ~rows:data_rows ());
  expect_invalid_arg "empty workflow" (fun () ->
    Ui.Workflow.create ~current_step_id:1L [] ());
  expect_invalid_arg "empty workflow action label" (fun () ->
    Ui.Workflow.create ~current_step_id:1L ~continue_label:" " steps ());
  expect_invalid_arg "duplicate step IDs" (fun () ->
    Ui.Workflow.create
      ~current_step_id:1L
      [ Ui.Workflow.step ~id:1L ~title:(text "A") ~content:(text "A") ()
      ; Ui.Workflow.step ~id:1L ~title:(text "B") ~content:(text "B") ()
      ]
      ());
  expect_invalid_arg "unknown current step" (fun () ->
    Ui.Workflow.create ~current_step_id:99L steps ())
;;

let test_additional_component_identity () =
  let table selected_row_ids =
    Ui.View.Table.create ~selected_row_ids ~columns:data_columns ~rows:data_rows ()
    |> Ui.View.Body.Private.to_widget
  in
  expect
    (not (Ui.View.Private.node_equal_widgets (table []) (table [ 100L ])))
    "data table controlled selection was omitted from logical equality";
  let disclosure expanded =
    Ui.View.disclosure_group
      ~expanded
      ~on_changed:handler
      ~label:(text "Details")
      ~content:(text "Body")
      ()
  in
  expect
    (not (Ui.View.Private.node_equal_widgets (disclosure false) (disclosure true)))
    "disclosure expansion was omitted from logical equality";
  expect
    (not
       (Ui.View.Private.node_equal_widgets
          (Ui.View.group_box (text "card"))
          (Ui.View.group_box ~label:(text "Title") (text "card"))))
    "group label presence was omitted from logical equality"
;;

let test_linear_progress_validation () =
  List.iter (fun value -> ignore (Ui.View.progress ~value ())) [ 0.; 1. ];
  List.iter
    (fun value ->
       expect_invalid_arg "invalid linear progress value" (fun () ->
         Ui.View.progress ~value ()))
    [ -0.01; 1.01; Float.nan; Float.infinity; Float.neg_infinity ]
;;

let test_linear_progress_identity_includes_kind_and_value () =
  let fingerprint widget =
    let (Ui.View.Private.Av view) = Ui.View.Private.view widget in
    view.fingerprint
  in
  let indeterminate = Ui.View.progress () in
  let determinate = Ui.View.progress ~value:0.5 () in
  let circular = Ui.View.progress ~style:Ui.View.Progress_style.Circular ~value:0.5 () in
  expect
    (not (Ui.View.Private.node_equal_widgets indeterminate determinate))
    "linear progress value was omitted from logical equality";
  expect
    (not (Int64.equal (fingerprint indeterminate) (fingerprint determinate)))
    "linear progress value was omitted from its fingerprint";
  expect
    (not (Ui.View.Private.node_equal_widgets determinate circular))
    "linear and circular progress shared logical identity";
  expect
    (not (Int64.equal (fingerprint determinate) (fingerprint circular)))
    "linear and circular progress shared a fingerprint"
;;

let test_native_menu_validation () =
  let open Ui.View.Menu in
  let leaf id = action ~id ~label:(text "Action") () in
  let create entries = create ~label:(text "Actions") ~on_select:handler entries in
  expect
    (Ui.View.For_testing.kind_name (create [ leaf (-7L) ]) = "Menu")
    "native menu kind";
  expect_invalid_arg "empty menu" (fun () -> create []);
  expect_invalid_arg "duplicate menu IDs" (fun () -> create [ leaf 1L; leaf 1L ]);
  expect_invalid_arg "duplicate nested menu IDs" (fun () ->
    create [ leaf 1L; submenu ~id:2L ~label:(text "More") [ leaf 1L ] ]);
  expect_invalid_arg "empty submenu" (fun () -> submenu ~id:1L ~label:(text "More") []);
  expect_invalid_arg "empty section" (fun () -> section ~id:1L []);
  let rec nested count =
    if count = 0
    then leaf 0L
    else submenu ~id:(Int64.of_int count) ~label:(text "More") [ nested (count - 1) ]
  in
  ignore (create [ nested 31 ]);
  expect_invalid_arg "excessive menu depth" (fun () -> create [ nested 32 ]);
  ignore (create (List.init 1024 (fun id -> leaf (Int64.of_int id))));
  expect_invalid_arg "excessive menu entries" (fun () ->
    create (List.init 1025 (fun id -> leaf (Int64.of_int id))));
  ignore (create [ leaf Int64.min_int; leaf Int64.max_int ]);
  expect
    (not
       (Ui.View.Private.node_equal_widgets
          (Ui.View.Menu.create
             ~enabled:true
             ~label:(text "Actions")
             ~on_select:handler
             [ leaf 1L ])
          (Ui.View.Menu.create
             ~enabled:false
             ~label:(text "Actions")
             ~on_select:handler
             [ leaf 1L ])))
    "menu enabled state was omitted from logical equality"
;;

let () =
  test_native_menu_validation ();
  test_constructor_kinds ();
  test_picker_validation ();
  test_slider_validation ();
  test_fingerprints_include_controlled_values ();
  test_text_field_identity_includes_read_only_and_autofocus ();
  test_additional_component_validation ();
  test_additional_component_identity ();
  test_linear_progress_validation ();
  test_linear_progress_identity_includes_kind_and_value ()
;;
