module Protocol = Bonsai_swiftui_protocol
module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let service ~initial_pushes =
  Worker.Service.create
    ~push_topic_count:(Int.max 1 initial_pushes)
    ~concurrency:Worker.Service.Serial
    ~init:(fun session () ->
      for topic = 0 to initial_pushes - 1 do
        Worker.Session_context.emit
          session
          ~topic:(ID.Worker.Push_topic.of_int topic)
          (Printf.sprintf "push-%d" topic)
      done;
      Ok ())
    ~handle:(fun _context () request -> Ok request)
    ~shutdown:(fun () -> ())
    ()
;;

let ok = function
  | Ok value -> value
  | Error error -> fail "unexpected Driver error: %s" (Driver.error_to_string error)
;;

let worker_ok = function
  | Ok value -> value
  | Error error -> fail "unexpected worker error: %s" error
;;

let decode_frame frame =
  match Protocol.Binary_codec.decode frame.Driver.bytes with
  | Ok wire -> wire
  | Error error -> fail "frame did not decode: %s" error.message
;;

let semantic_operations frame =
  List.filter
    (function
      | Protocol.Wire_frame.Runtime_stats _ -> false
      | _ -> true)
    frame.Protocol.Wire_frame.operations
;;

let text_values result =
  match result.Driver.frame with
  | None -> []
  | Some frame ->
    semantic_operations (decode_frame frame)
    |> List.filter_map (function
      | Protocol.Wire_frame.Create_node { props = Text_props { value; _ }; _ }
      | Update_props { props = Text_props { value; _ }; _ } -> Some value
      | _ -> None)
;;

let find_button_binding result =
  match result.Driver.frame with
  | None -> fail "initial worker Driver frame was absent"
  | Some frame ->
    semantic_operations (decode_frame frame)
    |> List.find_map (function
      | Protocol.Wire_frame.Create_node
          { node_id; kind = Button; event_bindings = [ { event_tag; handler_id } ]; _ } ->
        Some (node_id, event_tag, handler_id)
      | _ -> None)
    |> (function
     | Some binding -> binding
     | None -> fail "worker Driver frame had no Button binding")
;;

let make_component client log =
  let registered = ref false in
  fun handlers graph ->
    let count, set_count = Bonsai_v017.state ~equal:Int.equal 0 graph in
    let input_handler =
      Driver.Handler.create
        handlers
        ~name:"worker-driver-input"
        ~equal:( == )
        set_count
        ~f:(fun set_count -> function
        | Ui.Event.Payload.Unit ->
          Bonsai.Effect.Many
            [ Bonsai.Effect.of_thunk (fun () -> log := "input" :: !log)
            ; set_count (fun value -> value + 1)
            ]
        | _ -> Bonsai.Effect.return ())
    in
    let controls =
      Bonsai.Cont.map2 set_count input_handler ~f:(fun set_count input_handler ->
        set_count, input_handler)
    in
    Bonsai.Cont.map2 count controls ~f:(fun count (set_count, input_handler) ->
      if not !registered
      then (
        registered := true;
        Worker.on_event client (fun _event ->
          Bonsai.Effect.Many
            [ Bonsai.Effect.of_thunk (fun () -> log := "worker" :: !log)
            ; set_count (fun value -> value + 10)
            ]));
      log := "reconcile" :: !log;
      Ui.View.column
        [ Ui.View.text (Printf.sprintf "Count: %d" count)
        ; Ui.View.button ~on_press:input_handler ~child:(Ui.View.text "Increment") ()
        ])
;;

let create_driver ~runtime_epoch client log =
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  Driver.For_testing.create_widget_component
    ~runtime_epoch
    ~time_source
    ~before_flush:(fun ~schedule ->
      log := "drain" :: !log;
      Worker.Private.drain_to_effects client ~max_events:64 ~schedule)
    ~before_shutdown:(fun () -> Worker_runtime.stop client)
    (make_component client log)
;;

let present driver result ~monotonic_now_ns =
  ok
    (Driver.presentation_succeeded
       driver
       ~presentation_id:result.Driver.presentation_id
       ~renderer_revision:result.renderer_revision
       ~monotonic_now_ns)
;;

let input_batch ~runtime_epoch ~revision (node_id, event_tag, handler_id) =
  Protocol.Inbound_event.
    { runtime_epoch
    ; events =
        [ { sequence = ID.Runtime.Event_sequence.of_int64 1L
          ; displayed_revision = revision
          ; node_id
          ; handler_id
          ; event_tag
          ; payload = Unit
          }
        ]
    }
;;

let test_pump_order_barrier_and_stale_rejection () =
  let runtime_epoch = ID.Runtime.Epoch.of_int64 301L in
  let client =
    worker_ok (Worker_runtime.start ~runtime_epoch (service ~initial_pushes:0) ())
  in
  let log = ref [] in
  let driver = create_driver ~runtime_epoch client log in
  let initial = ok (Driver.pump driver ~monotonic_now_ns:0L ()) in
  let binding = find_button_binding initial in
  ignore (Worker.send client "behind-barrier");
  Worker.For_testing.await_output client;
  let pending_before = Worker.For_testing.pending_output_count client in
  require
    (Result.is_error (Driver.pump driver ~monotonic_now_ns:0L ()))
    "presentation barrier accepted a second worker drain";
  require
    (Worker.For_testing.pending_output_count client = pending_before)
    "presentation barrier consumed worker output";
  present driver initial ~monotonic_now_ns:0L;
  log := [];
  let events = input_batch ~runtime_epoch ~revision:initial.renderer_revision binding in
  let updated = ok (Driver.pump driver ~monotonic_now_ns:1L ~events ()) in
  require
    (List.exists (String.equal "Count: 11") (text_values updated))
    "input and worker effects were not flushed into one candidate";
  require
    (List.rev !log = [ "drain"; "input"; "worker"; "reconcile" ])
    "pump order was not input dispatch -> worker drain -> effects -> reconcile";
  present driver updated ~monotonic_now_ns:1L;
  Worker.For_testing.inject_push
    client
    ~runtime_epoch:(ID.Runtime.Epoch.of_int64 999L)
    ~worker_generation:(Worker.worker_generation client)
    ~push_sequence:(ID.Worker.Push_sequence.of_int64 100L)
    ~topic:(ID.Worker.Push_topic.of_int 0)
    "stale";
  Worker.For_testing.inject_push
    client
    ~runtime_epoch
    ~worker_generation:(ID.Worker.Generation.succ (Worker.worker_generation client))
    ~push_sequence:(ID.Worker.Push_sequence.of_int64 101L)
    ~topic:(ID.Worker.Push_topic.of_int 0)
    "stale-generation";
  log := [];
  let stale = ok (Driver.pump driver ~monotonic_now_ns:2L ()) in
  require
    (not (List.exists (String.equal "worker") !log))
    "stale runtime epoch reached a worker subscriber";
  present driver stale ~monotonic_now_ns:2L;
  Worker.For_testing.inject_push
    client
    ~runtime_epoch
    ~worker_generation:(Worker.worker_generation client)
    ~push_sequence:(ID.Worker.Push_sequence.of_int64 1L)
    ~topic:(ID.Worker.Push_topic.of_int 0)
    "fresh";
  log := [];
  let fresh = ok (Driver.pump driver ~monotonic_now_ns:3L ()) in
  require
    (List.exists (String.equal "worker") !log)
    "stale push incorrectly advanced the accepted push sequence";
  present driver fresh ~monotonic_now_ns:3L;
  Driver.shutdown driver
;;

let test_bounded_drain () =
  let runtime_epoch = ID.Runtime.Epoch.of_int64 302L in
  let client =
    worker_ok (Worker_runtime.start ~runtime_epoch (service ~initial_pushes:65) ())
  in
  Worker.For_testing.await_output client;
  let log = ref [] in
  let driver = create_driver ~runtime_epoch client log in
  let first = ok (Driver.pump driver ~monotonic_now_ns:0L ()) in
  require
    (List.length (List.filter (String.equal "worker") !log) = 64)
    "one Driver pump drained more or fewer than 64 worker events";
  require
    (Worker.For_testing.pending_output_count client = 1)
    "bounded drain did not retain the remaining worker event";
  present driver first ~monotonic_now_ns:0L;
  log := [];
  let second = ok (Driver.pump driver ~monotonic_now_ns:1L ()) in
  require
    (List.length (List.filter (String.equal "worker") !log) = 1)
    "later Driver pump did not drain the retained worker event";
  present driver second ~monotonic_now_ns:1L;
  Driver.shutdown driver
;;

let () =
  test_pump_order_barrier_and_stale_rejection ();
  test_bounded_drain ();
  let diagnostics = Worker_runtime.For_testing.diagnostics () in
  require (diagnostics.spawn_count = 1) "Driver tests spawned multiple Worker Domains";
  require (diagnostics.join_count = 0) "ordinary Driver shutdown joined Worker Domain";
  require (diagnostics.peak_active_sessions = 1) "Driver tests overlapped sessions";
  Worker_runtime.For_testing.final_shutdown ();
  require
    ((Worker_runtime.For_testing.diagnostics ()).join_count = 1)
    "Driver test final shutdown did not join exactly once"
;;
