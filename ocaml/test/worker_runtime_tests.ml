module ID = Bonsai_swiftui_spec.Id

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

type gate =
  { mutex : Mutex.t
  ; condition : Condition.t
  ; mutable started : bool
  ; mutable released : bool
  }

let create_gate () =
  { mutex = Mutex.create ()
  ; condition = Condition.create ()
  ; started = false
  ; released = false
  }
;;

let signal_started gate =
  Mutex.lock gate.mutex;
  gate.started <- true;
  Condition.broadcast gate.condition;
  Mutex.unlock gate.mutex
;;

let await_started gate =
  Mutex.lock gate.mutex;
  while not gate.started do
    Condition.wait gate.condition gate.mutex
  done;
  Mutex.unlock gate.mutex
;;

let release gate =
  Mutex.lock gate.mutex;
  gate.released <- true;
  Condition.broadcast gate.condition;
  Mutex.unlock gate.mutex
;;

let await_release gate =
  Mutex.lock gate.mutex;
  while not gate.released do
    Condition.wait gate.condition gate.mutex
  done;
  Mutex.unlock gate.mutex
;;

let reset_gate gate =
  Mutex.lock gate.mutex;
  gate.started <- false;
  gate.released <- false;
  Mutex.unlock gate.mutex
;;

type callback_log =
  { mutex : Mutex.t
  ; condition : Condition.t
  ; mutable entries : string list
  }

let create_log () =
  { mutex = Mutex.create (); condition = Condition.create (); entries = [] }
;;

let append_log log entry =
  Mutex.lock log.mutex;
  log.entries <- entry :: log.entries;
  Condition.broadcast log.condition;
  Mutex.unlock log.mutex
;;

let clear_log log =
  Mutex.lock log.mutex;
  log.entries <- [];
  Mutex.unlock log.mutex
;;

let await_log_length log length =
  Mutex.lock log.mutex;
  while List.length log.entries < length do
    Condition.wait log.condition log.mutex
  done;
  let entries = List.rev log.entries in
  Mutex.unlock log.mutex;
  entries
;;

type request =
  | Echo of string
  | Hold
  | Mark_dirty of int
  | Emit_push of string
  | Coalesce_push
  | Fail_callback

type config =
  { init_domain_id : Domain.id option Atomic.t
  ; hold_gate : gate
  ; log : callback_log
  ; shutdown_count : int Atomic.t
  }

type state = { config : config }

let service =
  Worker.Service.create
    ~push_topic_count:2
    ~concurrency:Worker.Service.Serial
    ~init:(fun session config ->
      Atomic.set config.init_domain_id (Some (Domain.self ()));
      Worker.Session_context.emit session ~topic:(ID.Worker.Push_topic.of_int 0) "ready";
      Ok { config })
    ~handle:(fun context state request ->
      match request with
      | Echo value -> Ok value
      | Hold ->
        signal_started state.config.hold_gate;
        await_release state.config.hold_gate;
        Ok "held"
      | Mark_dirty value ->
        append_log state.config.log (Printf.sprintf "R%d" value);
        Ok (Printf.sprintf "marked-%d" value)
      | Emit_push value ->
        Worker.Request_context.emit context ~topic:(ID.Worker.Push_topic.of_int 1) value;
        Ok "pushed"
      | Coalesce_push ->
        Worker.Request_context.emit context ~topic:(ID.Worker.Push_topic.of_int 1) "old";
        Worker.Request_context.emit context ~topic:(ID.Worker.Push_topic.of_int 1) "new";
        Ok "coalesced"
      | Fail_callback -> failwith "intentional service callback failure")
    ~shutdown:(fun state -> Atomic.incr state.config.shutdown_count)
    ()
;;

let create_config () =
  { init_domain_id = Atomic.make None
  ; hold_gate = create_gate ()
  ; log = create_log ()
  ; shutdown_count = Atomic.make 0
  }
;;

let ok = function
  | Ok value -> value
  | Error error -> fail "unexpected worker runtime error: %s" error
;;

let drain client = Worker.For_testing.drain_events client ~max_events:64

let response_count events =
  List.fold_left
    (fun count -> function
       | Worker.Response _ -> count + 1
       | Push _ | Terminal _ -> count)
    0
    events
;;

let rec drain_until_responses client expected events =
  let events = events @ drain client in
  if response_count events >= expected
  then events
  else (
    Worker.For_testing.await_output client;
    drain_until_responses client expected events)
;;

let rec drain_until_terminal client events =
  let events = events @ drain client in
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

let accepted = function
  | Worker.Accepted request_id -> request_id
  | Full -> fail "request unexpectedly hit backpressure"
  | Not_ready -> fail "worker client was not ready"
  | Stopping -> fail "worker client was stopping"
;;

let test_request_push_backpressure_fairness_and_cancellation client config =
  Worker.For_testing.await_output client;
  let ready = drain client in
  require
    (List.exists
       (function
         | Worker.Push { topic; payload = "ready"; _ }
           when ID.Worker.Push_topic.equal topic (ID.Worker.Push_topic.of_int 0) -> true
         | _ -> false)
       ready)
    "worker init did not emit its unsolicited Ready push";
  let echo_id = accepted (Worker.send client (Echo "hello")) in
  let echo_events = drain_until_responses client 1 [] in
  require
    (List.exists
       (function
         | Worker.Response { request_id; outcome = Completed "hello"; _ } ->
           ID.Worker.Request_id.equal request_id echo_id
         | _ -> false)
       echo_events)
    "domain-0 request did not receive its correlated Worker Domain response";
  ignore (accepted (Worker.send client Hold));
  await_started config.hold_gate;
  for index = 1 to 31 do
    ignore (accepted (Worker.send client (Echo (string_of_int index))))
  done;
  require
    (Worker.send client (Echo "overflow") = Worker.Full)
    "outstanding response capacity did not return Full";
  release config.hold_gate;
  ignore (drain_until_responses client 32 []);
  reset_gate config.hold_gate;
  clear_log config.log;
  ignore (accepted (Worker.send client Hold));
  await_started config.hold_gate;
  let cancelled_before_dispatch = accepted (Worker.send client (Mark_dirty 90)) in
  ignore (accepted (Worker.send client (Mark_dirty 91)));
  Worker.cancel client ~request_id:cancelled_before_dispatch;
  release config.hold_gate;
  ignore (drain_until_responses client 3 []);
  let priority = await_log_length config.log 1 in
  require
    (priority = [ "R91" ])
    "Cancel control did not run before queued normal request dispatch";
  clear_log config.log;
  reset_gate config.hold_gate;
  ignore (accepted (Worker.send client Hold));
  await_started config.hold_gate;
  let yields_before =
    (Worker_runtime.For_testing.diagnostics ()).coordinator_yield_count
  in
  for index = 1 to 16 do
    ignore (accepted (Worker.send client (Mark_dirty index)))
  done;
  release config.hold_gate;
  ignore (drain_until_responses client 17 []);
  let fairness = await_log_length config.log 16 in
  require
    (fairness
     = [ "R1"
       ; "R2"
       ; "R3"
       ; "R4"
       ; "R5"
       ; "R6"
       ; "R7"
       ; "R8"
       ; "R9"
       ; "R10"
       ; "R11"
       ; "R12"
       ; "R13"
       ; "R14"
       ; "R15"
       ; "R16"
       ])
    "bounded request dispatch reordered or starved requests";
  require
    ((Worker_runtime.For_testing.diagnostics ()).coordinator_yield_count
     >= yields_before + 2)
    "Coordinator did not yield after bounded normal request batches";
  ignore (accepted (Worker.send client (Emit_push "unsolicited")));
  let pushed = drain_until_responses client 1 [] in
  require
    (List.exists
       (function
         | Worker.Push { topic; payload = "unsolicited"; _ }
           when ID.Worker.Push_topic.equal topic (ID.Worker.Push_topic.of_int 1) -> true
         | _ -> false)
       pushed)
    "Worker Domain unsolicited push did not reach domain 0";
  ignore (accepted (Worker.send client Coalesce_push));
  let coalesced = drain_until_responses client 1 [] in
  require
    (List.exists
       (function
         | Worker.Push { topic; payload = "new"; _ }
           when ID.Worker.Push_topic.equal topic (ID.Worker.Push_topic.of_int 1) -> true
         | _ -> false)
       coalesced
     && not
          (List.exists
             (function
               | Worker.Push { topic; payload = "old"; _ }
                 when ID.Worker.Push_topic.equal topic (ID.Worker.Push_topic.of_int 1) ->
                 true
               | _ -> false)
             coalesced))
    "push lane did not retain only the latest value for a topic"
;;

let () =
  let domain0_id = Domain.self () in
  let config = create_config () in
  let first =
    ok
      (Worker_runtime.start
         ~runtime_epoch:(ID.Runtime.Epoch.of_int64 101L)
         service
         config)
  in
  let first_diagnostics = Worker_runtime.For_testing.diagnostics () in
  require
    (first_diagnostics.state = Worker_runtime.Attached)
    "first worker session was not Attached";
  require (first_diagnostics.spawn_count = 1) "first worker session did not spawn once";
  require
    (first_diagnostics.backend_run_count = 1 && first_diagnostics.backend_running)
    "first worker session did not start exactly one live Eio backend";
  require
    (first_diagnostics.coordinator_start_count = 1
     && first_diagnostics.active_coordinators = 1
     && first_diagnostics.peak_active_coordinators = 1)
    "first worker session did not start exactly one Coordinator";
  require (first_diagnostics.join_count = 0) "ordinary startup joined the Worker Domain";
  require
    (Atomic.get config.init_domain_id <> Some domain0_id)
    "service init ran on OCaml domain 0";
  Worker_runtime.For_testing.await_idle_wait_count 1;
  require
    ((Worker_runtime.For_testing.diagnostics ()).idle_wait_count >= 1)
    "idle Worker Domain did not block on its condition";
  test_request_push_backpressure_fairness_and_cancellation first config;
  let first_domain_id = Option.get first_diagnostics.worker_domain_id in
  let first_generation = Worker.worker_generation first in
  reset_gate config.hold_gate;
  ignore (accepted (Worker.send first Hold));
  await_started config.hold_gate;
  for index = 1 to 31 do
    ignore (accepted (Worker.send first (Echo (Printf.sprintf "stop-%d" index))))
  done;
  let stopper = Domain.spawn (fun () -> Worker_runtime.stop first) in
  while not (Worker.For_testing.is_stopping first) do
    Domain.cpu_relax ()
  done;
  release config.hold_gate;
  Domain.join stopper;
  let shutdown_events = drain_until_responses first 32 [] in
  require
    (List.for_all
       (function
         | Worker.Response { outcome = Shutdown; _ } -> true
         | Push _ | Terminal _ -> true
         | Response _ -> false)
       shutdown_events)
    "out-of-band Stop did not complete pending requests as Shutdown";
  let after_destroy = Worker_runtime.For_testing.diagnostics () in
  require (after_destroy.state = Worker_runtime.Idle) "ordinary stop did not return Idle";
  require (after_destroy.spawn_count = 1) "ordinary stop respawned the Worker Domain";
  require (after_destroy.join_count = 0) "ordinary stop joined the Worker Domain";
  require
    (after_destroy.backend_run_count = 1 && after_destroy.backend_running)
    "ordinary stop exited or restarted the Eio backend";
  require
    (after_destroy.coordinator_start_count = 1 && after_destroy.active_coordinators = 0)
    "ordinary stop did not finish its Coordinator";
  require
    (Worker.send first (Echo "stale") = Worker.Stopping)
    "stopped client accepted a stale request";
  let second_config = create_config () in
  let second =
    ok
      (Worker_runtime.start
         ~runtime_epoch:(ID.Runtime.Epoch.of_int64 102L)
         service
         second_config)
  in
  let second_diagnostics = Worker_runtime.For_testing.diagnostics () in
  require
    (second_diagnostics.worker_domain_id = Some first_domain_id)
    "sequential recreation did not reuse the same Worker Domain";
  require (second_diagnostics.spawn_count = 1) "sequential recreation spawned again";
  require (second_diagnostics.join_count = 0) "sequential recreation joined the Domain";
  require
    (second_diagnostics.backend_run_count = 1 && second_diagnostics.backend_running)
    "sequential recreation did not reuse the live Eio backend";
  require
    (second_diagnostics.coordinator_start_count = 2
     && second_diagnostics.active_coordinators = 1
     && second_diagnostics.peak_active_coordinators = 1)
    "sequential recreation overlapped or failed to replace its Coordinator";
  require
    (second_diagnostics.active_sessions = 1 && second_diagnostics.peak_active_sessions = 1)
    "sequential recreation overlapped worker sessions";
  require
    (not (ID.Worker.Generation.equal first_generation (Worker.worker_generation second)))
    "sequential worker sessions reused a generation";
  Worker.For_testing.await_output second;
  ignore (drain second);
  ignore (accepted (Worker.send second Fail_callback));
  let failure_events = drain_until_terminal second [] in
  require
    (List.exists
       (function
         | Worker.Response { outcome = Failed error; _ } ->
           Core.String.is_substring
             error
             ~substring:"intentional service callback failure"
         | _ -> false)
       failure_events)
    "caught callback failure did not complete its accepted request";
  require
    (List.exists
       (function
         | Worker.Terminal { error; _ } ->
           Core.String.is_substring
             error
             ~substring:"intentional service callback failure"
         | _ -> false)
       failure_events)
    "caught callback failure did not emit a terminal application event";
  Worker_runtime.For_testing.await_state Worker_runtime.Idle;
  require
    ((Worker_runtime.For_testing.diagnostics ()).spawn_count = 1)
    "caught callback failure made the Worker Domain non-reusable";
  let after_callback_failure = Worker_runtime.For_testing.diagnostics () in
  require
    (after_callback_failure.backend_run_count = 1
     && after_callback_failure.backend_running
     && after_callback_failure.coordinator_start_count = 2
     && after_callback_failure.active_coordinators = 0)
    "caught callback failure escaped the session scope or stopped the Eio backend";
  let third_config = create_config () in
  let third =
    ok
      (Worker_runtime.start
         ~runtime_epoch:(ID.Runtime.Epoch.of_int64 103L)
         service
         third_config)
  in
  require
    ((Worker_runtime.For_testing.diagnostics ()).worker_domain_id = Some first_domain_id)
    "post-failure session did not reuse the Worker Domain";
  require
    ((Worker_runtime.For_testing.diagnostics ()).coordinator_start_count = 3)
    "post-failure session did not start a fresh Coordinator";
  Worker_runtime.stop third;
  Worker_runtime.For_testing.crash_worker_loop ();
  Worker_runtime.For_testing.await_state Worker_runtime.Terminal;
  require
    (Result.is_error
       (Worker_runtime.start
          ~runtime_epoch:(ID.Runtime.Epoch.of_int64 104L)
          service
          (create_config ())))
    "terminal Worker Domain accepted another session";
  Worker_runtime.For_testing.final_shutdown ();
  let stopped = Worker_runtime.For_testing.diagnostics () in
  require (stopped.state = Worker_runtime.Stopped) "final shutdown did not stop subsystem";
  require (stopped.spawn_count = 1) "final shutdown changed spawn count";
  require (stopped.join_count = 1) "final shutdown did not join exactly once";
  require
    (stopped.backend_run_count = 1 && not stopped.backend_running)
    "final shutdown did not exit the single Eio backend";
  require
    (stopped.coordinator_start_count = 3 && stopped.active_coordinators = 0)
    "final shutdown left a Coordinator active";
  Worker_runtime.For_testing.final_shutdown ();
  require
    ((Worker_runtime.For_testing.diagnostics ()).join_count = 1)
    "repeated final shutdown joined again";
  require
    (Result.is_error
       (Worker_runtime.start
          ~runtime_epoch:(ID.Runtime.Epoch.of_int64 105L)
          service
          (create_config ())))
    "worker-backed start after Stopped succeeded"
;;
