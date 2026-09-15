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

let collection_dependency_component observed_handler handlers graph =
  let count, set_count = Bonsai_v017.state ~equal:Int.equal 20 graph in
  let painted, set_painted = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let range =
    Test.Driver.Handler.create
      handlers
      ~name:"projected-collection-range"
      ~equal:(fun (left_count, left_set) (right_count, right_set) ->
        Int.equal left_count right_count && left_set == right_set)
      (Bonsai.Cont.both count set_painted)
      ~f:(fun (count, set_painted) payload ->
        match Ui.View.Collection.visible_range_of_payload payload with
        | None -> Bonsai.Effect.Ignore
        | Some range ->
          let last = Int64.to_int (Int64.min (Int64.of_int count) range.last_exclusive) in
          set_painted (fun _ -> last))
  in
  let append =
    Test.Driver.Handler.create
      handlers
      ~name:"append"
      ~equal:( == )
      set_count
      ~f:(fun set_count _ -> set_count (fun count -> count + 20))
  in
  Bonsai.Cont.map2
    (Bonsai.Cont.both count painted)
    (Bonsai.Cont.both range append)
    ~f:(fun (count, painted) (range, append) ->
      observed_handler := Some range;
      let catalog =
        Ui.View.Collection.Catalog.create
          ~keys:(List.init count Ui.Key.int)
          ~default_extent:40.
          ()
      in
      let rows =
        List.init 10 (fun index ->
          Ui.View.Keyed.create
            ~key:(Ui.Key.int index)
            (Ui.View.text (string_of_int index)))
      in
      Ui.View.column
        [ Ui.View.text (Printf.sprintf "Painted: %d" painted)
        ; Ui.View.button ~on_press:append ~child:(Ui.View.text "Append") ()
          |> Ui.View.with_test_id (Ui.Test_id.string "append")
        ; Ui.View.Collection.vertical
            ~catalog
            ~first_index:0
            ~items:rows
            ~on_visible_range:range
            ()
          |> Ui.View.Viewport.Vertical.with_height ~height:400.
        ])
;;

let () =
  let observed_handler = ref None in
  let handle =
    Test.Handle.create
      ~runtime_epoch:(ID.Runtime.Epoch.of_int64 702L)
      ~time_source:(Bonsai.Time_source.create ~start:Core.Time_ns.epoch)
      (collection_dependency_component observed_handler)
  in
  Fun.protect
    ~finally:(fun () -> Test.Handle.shutdown handle)
    (fun () ->
       let binding () = Option.get !observed_handler in
       let send last =
         Test.Handle.present handle;
         Test.Handle.visible_range
           handle
           (Test.Query.kind "Collection_catalog")
           ~first_index:0L
           ~last_exclusive:last;
         Test.Handle.present handle
       in
       let initial = binding () in
       send 10L;
       require
         (binding () == initial)
         "painted state replaced the generic collection handler";
       let revision = Test.Handle.revision handle in
       send 10L;
       require
         (Test.Handle.revision handle = revision)
         "no-op collection event emitted a patch";
       Test.Handle.click handle (Test.Query.test_id "append");
       require
         (binding () != initial)
         "changed collection behavior retained a stale handler";
       send 35L;
       require
         (Option.is_some
            (Test.Handle.find handle (Test.Query.visible_text "Painted: 35")))
         "updated collection handler read the old count")
;;
