module ID = Bonsai_swiftui_spec.Id

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let await ?(timeout = 2.0) description predicate =
  let deadline = Unix.gettimeofday () +. timeout in
  let rec loop () =
    if predicate ()
    then ()
    else if Unix.gettimeofday () >= deadline
    then fail "timed out waiting for %s" description
    else (
      Unix.sleepf 0.001;
      loop ())
  in
  loop ()
;;

let update_peak peak value =
  let rec loop observed =
    if value <= observed
    then ()
    else if not (Atomic.compare_and_set peak observed value)
    then loop (Atomic.get peak)
  in
  loop (Atomic.get peak)
;;

type request =
  | Hold of int
  | Trigger_daemon_failure

type config =
  { holds : unit Eio.Promise.t array
  ; entered : bool Atomic.t array
  ; active_handlers : int Atomic.t
  ; peak_handlers : int Atomic.t
  ; daemon_block : unit Eio.Promise.t
  ; daemon_failure : unit Eio.Promise.t
  ; daemon_failure_resolver : unit Eio.Promise.u
  ; daemon_started : bool Atomic.t
  ; daemon_unwound : int Atomic.t
  ; shutdown_after_daemon : bool Atomic.t
  ; fail_daemon : bool
  }

let create_config ~fail_daemon =
  let holds = Array.init 3 (fun _ -> fst (Eio.Promise.create ())) in
  let daemon_block, _ = Eio.Promise.create () in
  let daemon_failure, daemon_failure_resolver = Eio.Promise.create () in
  { holds
  ; entered = Array.init 3 (fun _ -> Atomic.make false)
  ; active_handlers = Atomic.make 0
  ; peak_handlers = Atomic.make 0
  ; daemon_block
  ; daemon_failure
  ; daemon_failure_resolver
  ; daemon_started = Atomic.make false
  ; daemon_unwound = Atomic.make 0
  ; shutdown_after_daemon = Atomic.make false
  ; fail_daemon
  }
;;

let make_service concurrency =
  Worker.Service.create
    ~push_topic_count:1
    ~concurrency
    ~init:(fun context config ->
      Worker.Session_context.fork_daemon context ~name:"phase3-test-daemon" (fun () ->
        Atomic.set config.daemon_started true;
        Fun.protect
          ~finally:(fun () -> Atomic.incr config.daemon_unwound)
          (fun () ->
             if config.fail_daemon
             then (
               Eio.Promise.await config.daemon_failure;
               failwith "intentional daemon failure")
             else Eio.Promise.await config.daemon_block));
      Ok config)
    ~handle:(fun _context config -> function
       | Hold index ->
         Atomic.set config.entered.(index) true;
         let active = Atomic.fetch_and_add config.active_handlers 1 + 1 in
         update_peak config.peak_handlers active;
         Fun.protect
           ~finally:(fun () ->
             ignore (Atomic.fetch_and_add config.active_handlers (-1) : int))
           (fun () ->
              Eio.Promise.await config.holds.(index);
              Ok index)
       | Trigger_daemon_failure ->
         Eio.Promise.resolve config.daemon_failure_resolver ();
         Ok 99)
    ~shutdown:(fun config ->
      Atomic.set config.shutdown_after_daemon (Atomic.get config.daemon_unwound = 1))
    ()
;;

let accepted = function
  | Worker.Accepted request_id -> request_id
  | Full -> fail "Phase 3 request unexpectedly hit backpressure"
  | Not_ready -> fail "Phase 3 service was not ready"
  | Stopping -> fail "Phase 3 service was stopping"
;;

let response_count events =
  List.fold_left
    (fun count -> function
       | Worker.Response _ -> count + 1
       | Push _ | Terminal _ -> count)
    0
    events
;;

let rec drain_until_responses client expected events =
  let events = events @ Worker.For_testing.drain_events client ~max_events:64 in
  if response_count events >= expected
  then events
  else (
    Worker.For_testing.await_output client;
    drain_until_responses client expected events)
;;

let rec drain_until_terminal client events =
  let events = events @ Worker.For_testing.drain_events client ~max_events:64 in
  if
    List.exists
      (function
        | Worker.Terminal _ -> true
        | Response _ | Push _ -> false)
      events
  then events
  else (
    Worker.For_testing.await_output client;
    drain_until_terminal client events)
;;

let outcome_count events request_id =
  List.fold_left
    (fun count -> function
       | Worker.Response { request_id = actual; _ }
         when ID.Worker.Request_id.equal request_id actual -> count + 1
       | Response _ | Push _ | Terminal _ -> count)
    0
    events
;;

let start epoch service config =
  match
    Worker_runtime.start ~runtime_epoch:(ID.Runtime.Epoch.of_int64 epoch) service config
  with
  | Ok client -> client
  | Error error -> fail "Phase 3 service failed to start: %s" error
;;

let test_concurrent_bound_daemon_lifecycle_and_metrics () =
  let config = create_config ~fail_daemon:false in
  let service = make_service (Worker.Service.Concurrent { max_in_flight = 2 }) in
  let client = start 701L service config in
  await "the session daemon to start" (fun () -> Atomic.get config.daemon_started);
  let first = accepted (Worker.send client (Hold 0)) in
  let second = accepted (Worker.send client (Hold 1)) in
  let third = accepted (Worker.send client (Hold 2)) in
  await "two concurrent handlers to enter" (fun () ->
    Atomic.get config.active_handlers = 2);
  require (not (Atomic.get config.entered.(2))) "Concurrent 2 entered a third handler";
  await "the third request to wait for a permit" (fun () ->
    let diagnostics = Worker_runtime.For_testing.diagnostics () in
    diagnostics.active_request_fibers = 3 && diagnostics.waiting_request_fibers = 1);
  let diagnostics = Worker_runtime.For_testing.diagnostics () in
  require
    (diagnostics.configured_concurrency_limit = Some 2)
    "diagnostics exposed the wrong concurrency limit";
  require (diagnostics.active_handlers = 2) "diagnostics lost active handlers";
  require (diagnostics.peak_active_handlers = 2) "diagnostics lost peak handlers";
  require (diagnostics.active_background_fibers = 1) "diagnostics lost the active daemon";
  require
    (diagnostics.peak_active_background_fibers = 1)
    "diagnostics lost the daemon peak";
  require
    (diagnostics.logical_live_fibers >= 5)
    "diagnostics undercounted the live Coordinator, requests, and daemon";
  Worker.cancel client ~request_id:first;
  await "the third handler to enter after cancellation" (fun () ->
    Atomic.get config.entered.(2));
  require (Atomic.get config.peak_handlers = 2) "Concurrent 2 exceeded its bound";
  Worker_runtime.stop client;
  let events = drain_until_responses client 3 [] in
  List.iter
    (fun request_id ->
       require
         (outcome_count events request_id = 1)
         "Concurrent cancellation race did not publish exactly once")
    [ first; second; third ];
  require
    (Atomic.get config.daemon_unwound = 1)
    "normal Stop did not unwind the daemon exactly once";
  require
    (Atomic.get config.shutdown_after_daemon)
    "shutdown ran before the session daemon finished";
  let stopped = Worker_runtime.For_testing.diagnostics () in
  require (stopped.active_request_fibers = 0) "request fiber metric leaked after Stop";
  require (stopped.active_handlers = 0) "handler metric leaked after Stop";
  require
    (stopped.active_background_fibers = 0)
    "background fiber metric leaked after Stop";
  require
    (stopped.request_queue_wait_count = 3
     && Int64.compare stopped.max_request_queue_wait_ns 0L >= 0)
    "request queue wait metrics did not cover every request";
  require
    (stopped.handler_wall_count = 3 && Int64.compare stopped.max_handler_wall_ns 0L >= 0)
    "handler wall metrics did not cover every entered handler";
  require
    (stopped.cancellation_unwind_count = 3
     && Int64.compare stopped.max_cancellation_unwind_ns 0L >= 0)
    "cancellation unwind metrics did not cover Cancel and Stop";
  require
    (Option.is_some stopped.session_cancellation_duration_ns)
    "session cancellation duration was not recorded";
  require
    (Option.is_some stopped.shutdown_duration_ns)
    "shutdown duration was not recorded"
;;

let test_immediate_stop_cancels_a_new_daemon () =
  let config = create_config ~fail_daemon:false in
  let client = start 703L (make_service Worker.Service.Serial) config in
  Worker_runtime.stop client;
  require
    (Atomic.get config.daemon_unwound = 1)
    "immediate Stop missed a daemon before its switch was registered";
  require
    (Atomic.get config.shutdown_after_daemon)
    "immediate Stop ran shutdown before daemon cleanup"
;;

let test_init_error_cancels_daemons () =
  let daemon_block, _ = Eio.Promise.create () in
  let daemon_started = Atomic.make false in
  let daemon_unwound = Atomic.make 0 in
  let service =
    Worker.Service.create
      ~push_topic_count:1
      ~concurrency:Worker.Service.Serial
      ~init:(fun context () ->
        Worker.Session_context.fork_daemon context ~name:"init-error-daemon" (fun () ->
          Atomic.set daemon_started true;
          Fun.protect
            ~finally:(fun () -> Atomic.incr daemon_unwound)
            (fun () -> Eio.Promise.await daemon_block));
        Error "intentional init error")
      ~handle:(fun _context () request -> Ok request)
      ~shutdown:(fun () -> ())
      ()
  in
  let result =
    Worker_runtime.start ~runtime_epoch:(ID.Runtime.Epoch.of_int64 704L) service ()
  in
  require (Result.is_error result) "an init error unexpectedly started the service";
  require (Atomic.get daemon_started) "the init-error daemon never started";
  require
    (Atomic.get daemon_unwound = 1)
    "an init error did not unwind its session daemon";
  Worker_runtime.For_testing.await_state Worker_runtime.Idle
;;

let test_daemon_failure_cancels_suspended_init () =
  let suspended_init, _ = Eio.Promise.create () in
  let daemon_started = Atomic.make false in
  let service =
    Worker.Service.create
      ~push_topic_count:1
      ~concurrency:Worker.Service.Serial
      ~init:(fun context () ->
        Worker.Session_context.fork_daemon
          context
          ~name:"startup-failure-daemon"
          (fun () ->
             Atomic.set daemon_started true;
             failwith "daemon failed during init");
        Eio.Promise.await suspended_init;
        Ok ())
      ~handle:(fun _context () request -> Ok request)
      ~shutdown:(fun () -> ())
      ()
  in
  let result = Atomic.make None in
  let starter =
    Domain.spawn (fun () ->
      Atomic.set
        result
        (Some
           (Worker_runtime.start
              ~runtime_epoch:(ID.Runtime.Epoch.of_int64 705L)
              service
              ())))
  in
  await "the startup daemon failure to cancel init" (fun () ->
    Option.is_some (Atomic.get result));
  Domain.join starter;
  require (Atomic.get daemon_started) "the startup failure daemon never ran";
  (match Atomic.get result with
   | Some (Error error) ->
     require
       (Core.String.is_substring error ~substring:"daemon failed during init")
       "startup lost the daemon failure diagnostic"
   | Some (Ok _) -> fail "a daemon failure during init reported Ready"
   | None -> fail "startup daemon failure lost its result");
  Worker_runtime.For_testing.await_state Worker_runtime.Idle
;;

let test_daemon_failure_terminates_session () =
  let config = create_config ~fail_daemon:true in
  let client = start 702L (make_service Worker.Service.Serial) config in
  await "the failing daemon to start" (fun () -> Atomic.get config.daemon_started);
  ignore (accepted (Worker.send client Trigger_daemon_failure) : ID.Worker.request_id);
  let events = drain_until_terminal client [] in
  require
    (List.exists
       (function
         | Worker.Terminal { error; _ } ->
           Core.String.is_substring error ~substring:"intentional daemon failure"
         | Response _ | Push _ -> false)
       events)
    "an unhandled daemon exception did not terminate the session";
  Worker_runtime.For_testing.await_state Worker_runtime.Idle;
  require
    (Atomic.get config.daemon_unwound = 1)
    "the failing daemon did not unwind exactly once";
  require
    (Atomic.get config.shutdown_after_daemon)
    "daemon failure ran shutdown before daemon cleanup"
;;

let test_invalid_concurrency_limit_is_rejected () =
  let rejected =
    try
      ignore
        (make_service (Worker.Service.Concurrent { max_in_flight = 0 })
         : (config, request, int, unit) Worker.Service.t);
      false
    with
    | Invalid_argument _ -> true
  in
  require rejected "Concurrent accepted a zero max_in_flight"
;;

let () =
  test_invalid_concurrency_limit_is_rejected ();
  test_init_error_cancels_daemons ();
  test_daemon_failure_cancels_suspended_init ();
  test_immediate_stop_cancels_a_new_daemon ();
  test_concurrent_bound_daemon_lifecycle_and_metrics ();
  test_daemon_failure_terminates_session ();
  Worker_runtime.For_testing.final_shutdown ()
;;
