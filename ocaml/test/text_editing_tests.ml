module Ui = Bonsai_swiftui_ui

let expect condition message = if not condition then failwith message

let test_utf16_indices_do_not_alias_utf8_bytes () =
  let text = "A😀中é" in
  expect (Ui.Text_editing.Utf16.length text = 6) "unexpected UTF-16 length";
  expect
    (Ui.Text_editing.Utf16.to_utf8_byte_offset text 3 = Some 5)
    "UTF-16 to UTF-8 conversion was wrong";
  expect
    (Ui.Text_editing.Utf16.of_utf8_byte_offset text 5 = Some 3)
    "UTF-8 to UTF-16 conversion was wrong";
  expect
    (Ui.Text_editing.Utf16.to_utf8_byte_offset text 2 = None)
    "split surrogate pair was accepted";
  expect
    (Ui.Text_editing.Utf16.of_utf8_byte_offset text 2 = None)
    "mid-codepoint UTF-8 offset was accepted"
;;

let test_selection_and_composing_validate_boundaries () =
  let text = "拼😀音" in
  let selection = Ui.Text_editing.Range.create ~text ~start_utf16:1 ~end_utf16:3 in
  let composing = Ui.Text_editing.Range.create ~text ~start_utf16:0 ~end_utf16:4 in
  let value = Ui.Text_editing.Value.create ~text ~selection ~composing () in
  expect
    (String.equal (Ui.Text_editing.Value.text value) text)
    "text editing value changed text";
  expect
    (Ui.Text_editing.Range.start_utf16 (Ui.Text_editing.Value.selection value) = 1)
    "selection start changed";
  expect
    (Option.is_some (Ui.Text_editing.Value.composing value))
    "composing range was lost";
  let rejected =
    try
      ignore (Ui.Text_editing.Range.create ~text ~start_utf16:2 ~end_utf16:3);
      false
    with
    | Invalid_argument _ -> true
  in
  expect rejected "range accepted an offset inside a surrogate pair"
;;

let test_empty_composing_range_normalizes_to_none () =
  let text = "abc" in
  let selection = Ui.Text_editing.Range.create ~text ~start_utf16:3 ~end_utf16:3 in
  let composing = Ui.Text_editing.Range.create ~text ~start_utf16:1 ~end_utf16:1 in
  let value = Ui.Text_editing.Value.create ~text ~selection ~composing () in
  expect
    (Option.is_none (Ui.Text_editing.Value.composing value))
    "empty composing range was not normalized"
;;

let test_marked_text_contains_the_selection () =
  let text = "abc" in
  let composing = Ui.Text_editing.Range.create ~text ~start_utf16:1 ~end_utf16:2 in
  List.iter
    (fun (start_utf16, end_utf16) ->
       let selection = Ui.Text_editing.Range.create ~text ~start_utf16 ~end_utf16 in
       let rejected =
         try
           ignore (Ui.Text_editing.Value.create ~text ~selection ~composing ());
           false
         with
         | Invalid_argument _ -> true
       in
       expect rejected "marked text accepted a selection outside its range")
    [ 0, 0; 2, 3 ];
  List.iter
    (fun offset ->
       let selection =
         Ui.Text_editing.Range.create ~text ~start_utf16:offset ~end_utf16:offset
       in
       ignore (Ui.Text_editing.Value.create ~text ~selection ~composing ()))
    [ 1; 2 ]
;;

let () =
  test_utf16_indices_do_not_alias_utf8_bytes ();
  test_selection_and_composing_validate_boundaries ();
  test_empty_composing_range_normalizes_to_none ();
  test_marked_text_contains_the_selection ();
  print_endline "text editing tests passed"
;;
