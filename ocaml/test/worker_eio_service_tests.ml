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

type request =
  | Suspend
  | Waiting
  | Expected_error
  | Echo of string
  | Raise_unexpected

type config =
  { suspended : unit Eio.Promise.t
  ; init_seen : bool Atomic.t
  ; suspend_started : bool Atomic.t
  ; waiting_started : bool Atomic.t
  ; active_handlers : int Atomic.t
  ; overlap_seen : bool Atomic.t
  ; unwind_count : int Atomic.t
  ; last_request_id : ID.Worker.request_id option Atomic.t
  }

let create_config () =
  let suspended, _resolver = Eio.Promise.create () in
  { suspended
  ; init_seen = Atomic.make false
  ; suspend_started = Atomic.make false
  ; waiting_started = Atomic.make false
  ; active_handlers = Atomic.make 0
  ; overlap_seen = Atomic.make false
  ; unwind_count = Atomic.make 0
  ; last_request_id = Atomic.make None
  }
;;

let with_active_handler config run =
  let previous = Atomic.fetch_and_add config.active_handlers 1 in
  if previous <> 0 then Atomic.set config.overlap_seen true;
  Fun.protect
    ~finally:(fun () -> ignore (Atomic.fetch_and_add config.active_handlers (-1) : int))
    run
;;

let service =
  Worker.Service.create
    ~push_topic_count:1
    ~concurrency:Worker.Service.Serial
    ~init:(fun session config ->
      ignore (Worker.Session_context.switch session : Eio.Switch.t);
      ignore (Worker.Session_context.clock session : Worker.mono_clock);
      ignore (Worker.Session_context.net session : Worker.net);
      require
        (Option.is_none (Worker.Session_context.data_dir session))
        "direct service unexpectedly received a data directory";
      Atomic.set config.init_seen true;
      Ok config)
    ~handle:(fun context config request ->
      Atomic.set config.last_request_id (Some (Worker.Request_context.request_id context));
      ignore (Worker.Request_context.switch context : Eio.Switch.t);
      ignore (Worker.Request_context.clock context : Worker.mono_clock);
      ignore (Worker.Request_context.net context : Worker.net);
      with_active_handler config (fun () ->
        match request with
        | Suspend ->
          Atomic.set config.suspend_started true;
          Fun.protect
            ~finally:(fun () -> Atomic.incr config.unwind_count)
            (fun () ->
               Eio.Promise.await config.suspended;
               Ok "suspended")
        | Waiting ->
          Atomic.set config.waiting_started true;
          Ok "waiting"
        | Expected_error -> Error "expected request failure"
        | Echo value -> Ok value
        | Raise_unexpected -> failwith "unexpected direct handler failure"))
    ~shutdown:(fun _config -> ())
    ()
;;

let accepted = function
  | Worker.Accepted request_id -> request_id
  | Full -> fail "direct request unexpectedly hit backpressure"
  | Not_ready -> fail "direct service was not ready"
  | Stopping -> fail "direct service was stopping"
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

let has_outcome events request_id predicate =
  List.exists
    (function
      | Worker.Response { request_id = actual; outcome; _ }
        when ID.Worker.Request_id.equal request_id actual -> predicate outcome
      | Response _ | Push _ | Terminal _ -> false)
    events
;;

let start runtime_epoch config =
  match
    Worker_runtime.start
      ~runtime_epoch:(ID.Runtime.Epoch.of_int64 runtime_epoch)
      service
      config
  with
  | Ok client -> client
  | Error error -> fail "direct service failed to start: %s" error
;;

let test_serial_cancellation_and_failure_policy () =
  let config = create_config () in
  let client = start 601L config in
  require (Atomic.get config.init_seen) "direct init did not receive its session context";
  let suspended_id = accepted (Worker.send client Suspend) in
  await "the suspended direct handler to start" (fun () ->
    Atomic.get config.suspend_started);
  let waiting_id = accepted (Worker.send client Waiting) in
  Unix.sleepf 0.02;
  require
    (not (Atomic.get config.waiting_started))
    "Serial entered a second handler while the first was suspended";
  Worker.cancel client ~request_id:waiting_id;
  Worker.cancel client ~request_id:suspended_id;
  let cancelled = drain_until_responses client 2 [] in
  require
    (has_outcome cancelled waiting_id (function
       | Cancelled -> true
       | _ -> false))
    "request cancelled while waiting for Serial did not return Cancelled";
  require
    (has_outcome cancelled suspended_id (function
       | Cancelled -> true
       | _ -> false))
    "suspended request switch cancellation did not return Cancelled";
  require
    (not (Atomic.get config.waiting_started))
    "handler started after cancellation while waiting for Serial";
  require (Atomic.get config.unwind_count = 1) "request cancellation did not unwind once";
  require (not (Atomic.get config.overlap_seen)) "Serial handlers overlapped";
  let expected_id = accepted (Worker.send client Expected_error) in
  let echo_id = accepted (Worker.send client (Echo "after-error")) in
  let expected = drain_until_responses client 2 [] in
  require
    (has_outcome expected expected_id (function
       | Failed "expected request failure" -> true
       | _ -> false))
    "expected direct handler error did not fail only its request";
  require
    (has_outcome expected echo_id (function
       | Completed "after-error" -> true
       | _ -> false))
    "direct service did not remain usable after an expected error";
  require
    (Atomic.get config.last_request_id = Some echo_id)
    "Request_context exposed the wrong request ID";
  let raised_id = accepted (Worker.send client Raise_unexpected) in
  let failed = drain_until_terminal client [] in
  require
    (has_outcome failed raised_id (function
       | Failed error ->
         Core.String.is_substring error ~substring:"direct handler failure"
       | _ -> false))
    "unexpected direct handler exception did not fail its request";
  require
    (List.exists
       (function
         | Worker.Terminal { error; _ } ->
           Core.String.is_substring error ~substring:"direct handler failure"
         | Response _ | Push _ -> false)
       failed)
    "unexpected direct handler exception did not terminate its session";
  Worker_runtime.For_testing.await_state Worker_runtime.Idle
;;

let test_stop_cancels_active_request_switch () =
  let config = create_config () in
  let client = start 602L config in
  let suspended_id = accepted (Worker.send client Suspend) in
  await "the stop test handler to suspend" (fun () -> Atomic.get config.suspend_started);
  Worker_runtime.stop client;
  let stopped = drain_until_responses client 1 [] in
  require
    (has_outcome stopped suspended_id (function
       | Shutdown -> true
       | _ -> false))
    "Stop did not map active request switch cancellation to Shutdown";
  require (Atomic.get config.unwind_count = 1) "Stop did not unwind the active request";
  require
    ((Worker_runtime.For_testing.diagnostics ()).state = Worker_runtime.Idle)
    "direct service Stop did not return the supervisor to Idle"
;;

let test_final_shutdown_cancels_suspended_init () =
  let suspended, _resolver = Eio.Promise.create () in
  let init_started = Atomic.make false in
  let init_service =
    Worker.Service.create
      ~push_topic_count:1
      ~concurrency:Worker.Service.Serial
      ~init:(fun _session () ->
        Atomic.set init_started true;
        Eio.Promise.await suspended;
        Ok ())
      ~handle:(fun _context () request -> Ok request)
      ~shutdown:(fun () -> ())
      ()
  in
  let starter =
    Domain.spawn (fun () ->
      Worker_runtime.start ~runtime_epoch:(ID.Runtime.Epoch.of_int64 603L) init_service ())
  in
  await "the direct init fiber to suspend" (fun () -> Atomic.get init_started);
  Worker_runtime.For_testing.final_shutdown ();
  require
    (Result.is_error (Domain.join starter))
    "final shutdown allowed suspended direct init to report Ready";
  let diagnostics = Worker_runtime.For_testing.diagnostics () in
  require (diagnostics.state = Worker_runtime.Stopped) "final shutdown did not stop";
  require (diagnostics.join_count = 1) "final shutdown did not join the backend once"
;;

let () =
  test_serial_cancellation_and_failure_policy ();
  test_stop_cancels_active_request_switch ();
  test_final_shutdown_cancels_suspended_init ()
;;
