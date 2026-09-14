module ID = Bonsai_swiftui_spec.Id
module Test = Bonsai_swiftui_test
module Ui = Bonsai_swiftui_ui

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let component handlers graph =
  let count, increment = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let increment =
    Test.Driver.Handler.create
      handlers
      ~name:"increment"
      ~equal:( == )
      increment
      ~f:(fun set_count _ -> set_count (fun count -> count + 1))
  in
  Bonsai.Cont.map2 count increment ~f:(fun count increment ->
    Ui.View.column
      ~key:(Ui.Key.string "main")
      [ Ui.View.text (Printf.sprintf "Count: %d" count)
      ; Ui.View.button ~on_press:increment ~child:(Ui.View.text "Increment") ()
        |> Ui.View.with_test_id (Ui.Test_id.string "increment")
      ])
;;

let () =
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let handle =
    Test.Handle.create
      ~runtime_epoch:(ID.Runtime.Epoch.of_int64 701L)
      ~time_source
      component
  in
  require
    (String.equal
       (Test.Handle.show handle)
       "Column key=main\n\
       \  Text \"Count: 0\"\n\
       \  Button test_id=increment events=[press]\n\
       \    Text \"Increment\"")
    "initial pretty-printed tree changed";
  Test.Handle.present handle;
  Test.Handle.click handle (Test.Query.test_id "increment");
  require
    (Option.is_some (Test.Handle.find handle (Test.Query.visible_text "Count: 1")))
    "click did not update Bonsai state";
  require
    (String.equal
       (Test.Handle.show_diff handle)
       "-   Text \"Count: 0\"\n+   Text \"Count: 1\"")
    "show_diff was not stable";
  Test.Handle.present handle;
  Test.Handle.shutdown handle
;;
