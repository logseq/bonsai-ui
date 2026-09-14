module Protocol = Bonsai_swiftui_protocol
module Runtime = Bonsai_swiftui_runtime
module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

module Benchmark_handler_map = Map.Make (struct
    type t = Runtime.Handler_id.t

    let compare = Runtime.Handler_id.compare
  end)

let fail format = Printf.ksprintf failwith format

let reconcile_exn
      reconciler
      ~base_revision
      ~target_revision
      ~old
      ~base_handler_frame
      widget
  =
  match
    Runtime.Reconciler.reconcile
      reconciler
      ~base_revision:(ID.Runtime.Renderer_revision.of_int64 base_revision)
      ~target_revision:(ID.Runtime.Renderer_revision.of_int64 target_revision)
      ~old
      ~base_handler_frame
      widget
  with
  | Ok output -> output
  | Error error -> fail "%s" (Runtime.Runtime_error.to_string error)
;;

let benchmark name iterations operation =
  Gc.compact ();
  let allocated_before = Gc.allocated_bytes () in
  let started = Unix.gettimeofday () in
  for iteration = 1 to iterations do
    operation iteration
  done;
  let elapsed = Unix.gettimeofday () -. started in
  let allocated_bytes = Gc.allocated_bytes () -. allocated_before in
  let microseconds = elapsed *. 1_000_000. /. Float.of_int iterations in
  let bytes_per_operation = allocated_bytes /. Float.of_int iterations in
  Printf.printf
    "%-34s %10.3f us/op  %12.0f bytes/op  (%d iterations)\n%!"
    name
    microseconds
    bytes_per_operation
    iterations
;;

let text_children count =
  List.init count (fun index ->
    Ui.View.text ~key:(Ui.Key.int index) (Printf.sprintf "Item %d" index))
;;

let mount widget =
  let reconciler =
    Runtime.Reconciler.create ~runtime_epoch:(ID.Runtime.Epoch.of_int64 1L)
  in
  let output =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      ~base_handler_frame:None
      widget
  in
  reconciler, output.mounted_tree, output.handler_frame
;;

let benchmark_unchanged () =
  let widget = Ui.View.column (text_children 1000) in
  let reconciler, initial, initial_handler_frame = mount widget in
  let tree = ref initial in
  let handler_frame = ref initial_handler_frame in
  let revision = ref 1L in
  benchmark "unchanged tree physical equality" 1000 (fun _ ->
    let target = Int64.succ !revision in
    let output =
      reconcile_exn
        reconciler
        ~base_revision:!revision
        ~target_revision:target
        ~old:(Some !tree)
        ~base_handler_frame:(Some !handler_frame)
        widget
    in
    if not (Runtime.Frame_patch.is_empty output.frame_patch)
    then fail "unchanged tree emitted a patch";
    tree := output.mounted_tree;
    handler_frame := output.handler_frame;
    revision := target)
;;

let benchmark_one_prop () =
  let reconciler, initial, initial_handler_frame = mount (Ui.View.text "Value 0") in
  let tree = ref initial in
  let handler_frame = ref initial_handler_frame in
  let revision = ref 1L in
  benchmark "one prop changed" 10000 (fun iteration ->
    let target = Int64.succ !revision in
    let output =
      reconcile_exn
        reconciler
        ~base_revision:!revision
        ~target_revision:target
        ~old:(Some !tree)
        ~base_handler_frame:(Some !handler_frame)
        (Ui.View.text (Printf.sprintf "Value %d" (iteration land 1)))
    in
    tree := output.mounted_tree;
    handler_frame := output.handler_frame;
    revision := target)
;;

let benchmark_full_snapshot count iterations =
  benchmark (Printf.sprintf "%d siblings full snapshot" count) iterations (fun _ ->
    ignore (mount (Ui.View.column (text_children count))))
;;

let benchmark_keyed_reverse count iterations =
  let ascending = List.init count Fun.id in
  let descending = List.rev ascending in
  let view indices =
    Ui.View.column
      (List.map
         (fun index ->
            Ui.View.text ~key:(Ui.Key.int index) (Printf.sprintf "Item %d" index))
         indices)
  in
  let reconciler, initial, initial_handler_frame = mount (view ascending) in
  let tree = ref initial in
  let handler_frame = ref initial_handler_frame in
  let revision = ref 1L in
  benchmark
    (Printf.sprintf "%d keyed siblings reverse" count)
    iterations
    (fun iteration ->
       let target = Int64.succ !revision in
       let output =
         reconcile_exn
           reconciler
           ~base_revision:!revision
           ~target_revision:target
           ~old:(Some !tree)
           ~base_handler_frame:(Some !handler_frame)
           (view (if iteration land 1 = 0 then ascending else descending))
       in
       tree := output.mounted_tree;
       handler_frame := output.handler_frame;
       revision := target)
;;

let benchmark_keyed_edit name edit =
  let base = List.init 1000 Fun.id in
  let changed = edit base in
  let view indices =
    Ui.View.column
      (List.map
         (fun index -> Ui.View.text ~key:(Ui.Key.int index) (Int.to_string index))
         indices)
  in
  benchmark name 200 (fun iteration ->
    let reconciler, initial, initial_handler_frame = mount (view base) in
    ignore
      (reconcile_exn
         reconciler
         ~base_revision:1L
         ~target_revision:2L
         ~old:(Some initial)
         ~base_handler_frame:(Some initial_handler_frame)
         (view (if iteration land 1 = 0 then changed else base))))
;;

let benchmark_handler_change () =
  let view () =
    Ui.View.button
      ~on_press:(Ui.Event.Handler.create (fun _ -> ()))
      ~child:(Ui.View.text "Press")
      ()
  in
  let reconciler, initial, initial_handler_frame = mount (view ()) in
  let tree = ref initial in
  let handler_frame = ref initial_handler_frame in
  let revision = ref 1L in
  benchmark "handler-only change" 10000 (fun _ ->
    let target = Int64.succ !revision in
    let output =
      reconcile_exn
        reconciler
        ~base_revision:!revision
        ~target_revision:target
        ~old:(Some !tree)
        ~base_handler_frame:(Some !handler_frame)
        (view ())
    in
    tree := output.mounted_tree;
    handler_frame := output.handler_frame;
    revision := target)
;;

let benchmark_handler_heavy count =
  let handlers = Array.init count (fun _ -> Ui.Event.Handler.create (fun _ -> ())) in
  let replaced_handlers = Array.copy handlers in
  replaced_handlers.(count / 2) <- Ui.Event.Handler.create (fun _ -> ());
  let view handlers ~changed_label =
    Ui.View.column
      (List.init count (fun index ->
         Ui.View.button
           ~key:(Ui.Key.int index)
           ~on_press:handlers.(index)
           ~child:
             (Ui.View.text
                (if changed_label && index = 0
                 then "Changed"
                 else Printf.sprintf "Button %d" index))
           ()))
  in
  let base = view handlers ~changed_label:false in
  let property_changed = view handlers ~changed_label:true in
  let handler_changed = view replaced_handlers ~changed_label:false in
  let run name alternate =
    let reconciler, initial, initial_handler_frame = mount base in
    let tree = ref initial in
    let handler_frame = ref initial_handler_frame in
    let revision = ref 1L in
    benchmark name 100 (fun iteration ->
      let target = Int64.succ !revision in
      let output =
        reconcile_exn
          reconciler
          ~base_revision:!revision
          ~target_revision:target
          ~old:(Some !tree)
          ~base_handler_frame:(Some !handler_frame)
          (alternate iteration)
      in
      tree := output.mounted_tree;
      handler_frame := output.handler_frame;
      revision := target)
  in
  run (Printf.sprintf "handler-heavy unchanged (%d)" count) (fun _ -> base);
  run (Printf.sprintf "handler-heavy property change (%d)" count) (fun iteration ->
    if iteration land 1 = 0 then base else property_changed);
  run (Printf.sprintf "handler-heavy one replacement (%d)" count) (fun iteration ->
    if iteration land 1 = 0 then base else handler_changed)
;;

let handler_entries count =
  let handler = Ui.Event.Handler.create (fun _ -> ()) in
  List.init count (fun index ->
    let handler_id = Int64.of_int (index + 1) in
    Runtime.Handler_registry.Frame.
      { node_id = ID.Ui.Node_id.of_int64 handler_id
      ; event_tag = Ui.Event.Tag.Press
      ; handler_id = ID.Ui.Handler_id.of_int64 handler_id
      ; handler
      })
;;

let benchmark_handler_frames count =
  let entries = handler_entries count in
  let base =
    Runtime.Handler_registry.Frame.Private.create
      ~revision:(ID.Runtime.Renderer_revision.of_int64 1L)
      entries
  in
  let iterations = if count = 1000 then 5000 else 1000 in
  benchmark
    (Printf.sprintf "handler frame build (%d)" count)
    (if count = 1000 then 500 else 100)
    (fun _ ->
       ignore
         (Runtime.Handler_registry.Frame.Private.create
            ~revision:(ID.Runtime.Renderer_revision.of_int64 1L)
            entries));
  benchmark
    (Printf.sprintf "handler zero-change derive (%d)" count)
    iterations
    (fun iteration ->
       ignore
         (Runtime.Handler_registry.Frame.Private.derive
            ~revision:
              (ID.Runtime.Renderer_revision.of_int64 (Int64.of_int (iteration + 2)))
            ~base_revision:(ID.Runtime.Renderer_revision.of_int64 1L)
            ~base
            ~removals:[]
            ~additions:[]));
  let additions change_count =
    let handler = Ui.Event.Handler.create (fun _ -> ()) in
    List.init change_count (fun index ->
      let handler_id = Int64.of_int (count + index + 1) in
      Runtime.Handler_registry.Frame.
        { node_id = ID.Ui.Node_id.of_int64 handler_id
        ; event_tag = Ui.Event.Tag.Press
        ; handler_id = ID.Ui.Handler_id.of_int64 handler_id
        ; handler
        })
  in
  let removals change_count =
    List.init change_count (fun index ->
      ID.Ui.Handler_id.of_int64 (Int64.of_int (index + 1)))
  in
  List.iter
    (fun change_count ->
       let additions = additions change_count in
       let removals = removals change_count in
       benchmark
         (Printf.sprintf "handler %d-change derive (%d)" change_count count)
         iterations
         (fun iteration ->
            ignore
              (Runtime.Handler_registry.Frame.Private.derive
                 ~revision:
                   (ID.Runtime.Renderer_revision.of_int64 (Int64.of_int (iteration + 2)))
                 ~base_revision:(ID.Runtime.Renderer_revision.of_int64 1L)
                 ~base
                 ~removals
                 ~additions)))
    [ 1; 10 ];
  let lookup_iterations = 1_000_000 in
  let random = Random.State.make [| 0xB0; 0x5A; count |] in
  let lookup_ids =
    Array.init 65536 (fun _ ->
      ID.Ui.Handler_id.of_int64 (Int64.of_int (Random.State.int random count + 1)))
  in
  let lookup_id iteration = lookup_ids.(iteration land (Array.length lookup_ids - 1)) in
  benchmark
    (Printf.sprintf "handler map lookup (%d)" count)
    lookup_iterations
    (fun iteration ->
       ignore (Runtime.Handler_registry.Frame.find base (lookup_id iteration)));
  let hash = Hashtbl.create count in
  List.iter
    (fun (entry : Runtime.Handler_registry.Frame.entry) ->
       Hashtbl.add hash entry.handler_id entry)
    entries;
  benchmark
    (Printf.sprintf "handler hash lookup (%d)" count)
    lookup_iterations
    (fun iteration -> ignore (Hashtbl.find_opt hash (lookup_id iteration)))
;;

let benchmark_handler_copy_crossover count =
  let entries = handler_entries count in
  let map_base =
    List.fold_left
      (fun map (entry : Runtime.Handler_registry.Frame.entry) ->
         Benchmark_handler_map.add entry.handler_id entry map)
      Benchmark_handler_map.empty
      entries
  in
  let hash_base = Hashtbl.create count in
  List.iter
    (fun (entry : Runtime.Handler_registry.Frame.entry) ->
       Hashtbl.add hash_base entry.handler_id entry)
    entries;
  let replacement_counts =
    match count with
    | 100 -> [ 0; 1; 2; 3; 4; 5; 6; 7; 8; 10; 12; 15; 20; 50; 100 ]
    | 1000 ->
      [ 0
      ; 1
      ; 2
      ; 5
      ; 10
      ; 20
      ; 25
      ; 30
      ; 40
      ; 50
      ; 100
      ; 125
      ; 150
      ; 175
      ; 200
      ; 250
      ; 300
      ; 400
      ; 500
      ; 1000
      ]
    | 10000 ->
      [ 0
      ; 1
      ; 2
      ; 5
      ; 10
      ; 20
      ; 50
      ; 100
      ; 200
      ; 250
      ; 300
      ; 400
      ; 500
      ; 1000
      ; 1250
      ; 1500
      ; 1750
      ; 2000
      ; 2250
      ; 2500
      ; 3000
      ; 4000
      ; 5000
      ; 10000
      ]
    | _ -> invalid_arg "unsupported handler crossover size"
  in
  List.iter
    (fun replacements ->
       let handler = Ui.Event.Handler.create (fun _ -> ()) in
       let removals =
         if replacements = 0
         then []
         else
           List.init replacements (fun index ->
             let bucket_midpoint = ((index * count) + (count / 2)) / replacements in
             ID.Ui.Handler_id.of_int64 (Int64.of_int (bucket_midpoint + 1)))
       in
       let additions =
         List.init replacements (fun index ->
           let handler_id = Int64.of_int (count + index + 1) in
           Runtime.Handler_registry.Frame.
             { node_id = ID.Ui.Node_id.of_int64 handler_id
             ; event_tag = Ui.Event.Tag.Press
             ; handler_id = ID.Ui.Handler_id.of_int64 handler_id
             ; handler
             })
       in
       let map_iterations =
         if replacements = 0 then 100_000 else max 100 (250_000 / replacements)
       in
       let hash_iterations = max 100 (500_000 / count) in
       benchmark
         (Printf.sprintf "handler map-share H=%d N=%d" count replacements)
         map_iterations
         (fun _ ->
            let copied = map_base in
            let without_removed =
              List.fold_left
                (fun map handler_id -> Benchmark_handler_map.remove handler_id map)
                copied
                removals
            in
            let updated =
              List.fold_left
                (fun map (entry : Runtime.Handler_registry.Frame.entry) ->
                   Benchmark_handler_map.add entry.handler_id entry map)
                without_removed
                additions
            in
            ignore (Sys.opaque_identity updated));
       benchmark
         (Printf.sprintf "handler hash-copy H=%d N=%d" count replacements)
         hash_iterations
         (fun _ ->
            let copied = Hashtbl.copy hash_base in
            List.iter (Hashtbl.remove copied) removals;
            List.iter
              (fun (entry : Runtime.Handler_registry.Frame.entry) ->
                 Hashtbl.add copied entry.handler_id entry)
              additions;
            ignore (Sys.opaque_identity copied)))
    replacement_counts
;;

let measure_retained_handler_frames count =
  Gc.compact ();
  let before = (Gc.stat ()).live_words in
  let entries = handler_entries count in
  let base =
    Runtime.Handler_registry.Frame.Private.create
      ~revision:(ID.Runtime.Renderer_revision.of_int64 1L)
      entries
  in
  let replacement = List.hd (handler_entries 1) in
  let replacement =
    Runtime.Handler_registry.Frame.
      { replacement with
        node_id = ID.Ui.Node_id.of_int64 (Int64.of_int (count + 1))
      ; handler_id = ID.Ui.Handler_id.of_int64 (Int64.of_int (count + 1))
      }
  in
  let derived =
    Runtime.Handler_registry.Frame.Private.derive
      ~revision:(ID.Runtime.Renderer_revision.of_int64 2L)
      ~base_revision:(ID.Runtime.Renderer_revision.of_int64 1L)
      ~base
      ~removals:[ ID.Ui.Handler_id.of_int64 1L ]
      ~additions:[ replacement ]
  in
  Gc.compact ();
  let retained_words = (Gc.stat ()).live_words - before in
  ignore (Sys.opaque_identity (base, derived));
  Printf.printf
    "%-34s %10d bytes  (two revisions)\n%!"
    (Printf.sprintf "handler retained memory (%d)" count)
    (retained_words * (Sys.word_size / 8))
;;

let protocol_frame count =
  let operations =
    List.init count (fun index ->
      Protocol.Wire_frame.Create_node
        { node_id = ID.Ui.Node_id.of_int64 (Int64.of_int (index + 1))
        ; kind = Text
        ; props =
            Text_props
              { value = Printf.sprintf "Item %d" index
              ; style = None
              ; text_align = Start
              ; line_limit = None
              ; truncation = Tail
              }
        ; event_bindings = []
        })
  in
  Protocol.Wire_frame.
    { runtime_epoch = ID.Runtime.Epoch.of_int64 1L
    ; base_revision = ID.Runtime.Renderer_revision.of_int64 0L
    ; target_revision = ID.Runtime.Renderer_revision.of_int64 1L
    ; kind = Full_snapshot
    ; operations
    }
;;

let encode_exn frame =
  match Protocol.Binary_codec.encode frame with
  | Ok bytes -> bytes
  | Error error -> fail "%s" error.message
;;

let decode_exn bytes =
  match Protocol.Binary_codec.decode bytes with
  | Ok frame -> frame
  | Error error -> fail "%s" error.message
;;

let runtime_encode_exn frame =
  match Protocol.Binary_codec.encode_runtime_frame frame with
  | Ok encoded -> encoded
  | Error error -> fail "%s" error.message
;;

let patch_runtime_exn encoded ~encode_ns ~patch_bytes =
  match Protocol.Binary_codec.patch_runtime_stats encoded ~encode_ns ~patch_bytes with
  | Ok () -> ()
  | Error error -> fail "%s" error.message
;;

let benchmark_protocol () =
  let full = protocol_frame 1000 in
  let encoded = encode_exn full in
  let zero_stats =
    Protocol.Wire_frame.
      { event_batch_size = 0
      ; bonsai_flush_ns = 0L
      ; result_read_ns = 0L
      ; reconcile_ns = 0L
      ; encode_ns = 0L
      ; patch_count = List.length full.operations
      ; patch_bytes = 0
      ; lifecycle_ns = 0L
      ; full_snapshot_count = 1
      ; resync_count = 0
      }
  in
  let runtime_frame stats =
    Protocol.Wire_frame.
      { full with operations = full.operations @ [ Runtime_stats stats ] }
  in
  let runtime_zero = runtime_frame zero_stats in
  let sample_runtime_encoded = runtime_encode_exn runtime_zero in
  let runtime_length =
    Protocol.Binary_codec.Runtime_encoded_frame.bytes sample_runtime_encoded
    |> Bytes.length
  in
  let final_stats = { zero_stats with encode_ns = 1L; patch_bytes = runtime_length } in
  let runtime_final = runtime_frame final_stats in
  let incremental =
    Protocol.Wire_frame.
      { runtime_epoch = ID.Runtime.Epoch.of_int64 1L
      ; base_revision = ID.Runtime.Renderer_revision.of_int64 1L
      ; target_revision = ID.Runtime.Renderer_revision.of_int64 2L
      ; kind = Incremental_frame
      ; operations =
          [ Update_props
              { node_id = ID.Ui.Node_id.of_int64 1L
              ; props =
                  Text_props
                    { value = "Changed"
                    ; style = None
                    ; text_align = Start
                    ; line_limit = None
                    ; truncation = Tail
                    }
              }
          ]
      }
  in
  benchmark "protocol encode full snapshot" 500 (fun _ -> ignore (encode_exn full));
  benchmark "runtime encode one pass" 500 (fun _ ->
    ignore (runtime_encode_exn runtime_zero));
  benchmark "runtime stats backpatch" 100000 (fun _ ->
    patch_runtime_exn sample_runtime_encoded ~encode_ns:1L ~patch_bytes:runtime_length);
  benchmark "runtime codec total" 500 (fun _ ->
    let encoded = runtime_encode_exn runtime_zero in
    patch_runtime_exn encoded ~encode_ns:1L ~patch_bytes:runtime_length);
  benchmark "legacy runtime codec two-pass" 500 (fun _ ->
    ignore (encode_exn runtime_zero);
    ignore (encode_exn runtime_final));
  benchmark "protocol decode full snapshot" 500 (fun _ -> ignore (decode_exn encoded));
  benchmark "protocol encode incremental" 10000 (fun _ -> ignore (encode_exn incremental));
  let encoded_incremental = encode_exn incremental in
  benchmark "protocol decode incremental" 10000 (fun _ ->
    ignore (decode_exn encoded_incremental))
;;

let () =
  Printf.printf "bonsai_swiftui OCaml benchmark\n%!";
  benchmark_unchanged ();
  benchmark_one_prop ();
  benchmark_full_snapshot 1000 100;
  benchmark_full_snapshot 10000 10;
  benchmark_keyed_edit "insert at front (1000 keyed)" (fun values -> -1 :: values);
  benchmark_keyed_edit "delete middle (1000 keyed)" (fun values ->
    List.filteri (fun index _ -> index <> 500) values);
  benchmark_keyed_reverse 1000 100;
  benchmark_keyed_reverse 10000 10;
  benchmark_handler_change ();
  benchmark_handler_heavy 1000;
  benchmark_handler_frames 1000;
  benchmark_handler_frames 10000;
  benchmark_handler_copy_crossover 100;
  benchmark_handler_copy_crossover 1000;
  benchmark_handler_copy_crossover 10000;
  measure_retained_handler_frames 1000;
  measure_retained_handler_frames 10000;
  benchmark_protocol ()
;;
