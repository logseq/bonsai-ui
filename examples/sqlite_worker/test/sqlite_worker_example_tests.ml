module Protocol = Sqlite_worker_protocol
module Config = Sqlite_worker_config
module Test = Bonsai_swiftui_test
module ID = Bonsai_swiftui_spec.Id

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let with_temporary_database test =
  let marker = Filename.temp_file "bonsai_swiftui_sqlite_example_" ".tmp" in
  Sys.remove marker;
  Unix.mkdir marker 0o700;
  let path = Filename.concat marker "todos.sqlite3" in
  let cleanup () =
    Sys.readdir marker
    |> Array.iter (fun name -> Sys.remove (Filename.concat marker name));
    Unix.rmdir marker
  in
  Fun.protect ~finally:cleanup (fun () -> test path)
;;

let worker_idle_wait_count () =
  (Worker_runtime.For_testing.diagnostics ()).idle_wait_count
;;

let pump_worker handle =
  Test.Handle.present handle;
  Test.Handle.pump_next handle ()
;;

let require_present handle test_id message =
  require (Option.is_some (Test.Handle.find handle (Test.Query.test_id test_id))) message
;;

let require_text handle value message =
  require
    (Option.is_some (Test.Handle.find handle (Test.Query.visible_text value)))
    message
;;

let create_handle ~runtime_epoch path =
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  Test.Handle.create_app
    ~runtime_epoch:(ID.Runtime.Epoch.of_int64 runtime_epoch)
    ~time_source
    Sqlite_worker_example.app
    ~application_payload:
      (Config.encode
         { database_path = path; application_support_directory = Filename.dirname path })
;;

let config path =
  Config.{ database_path = path; application_support_directory = Filename.dirname path }
;;

let settle_initial handle =
  let rec settle attempts =
    if attempts = 0
    then fail "worker did not settle its initial List request"
    else (
      let idle_before_pump = worker_idle_wait_count () in
      pump_worker handle;
      if Option.is_some (Test.Handle.find handle (Test.Query.visible_text "Ready"))
      then ()
      else (
        Worker_runtime.For_testing.await_idle_wait_count (idle_before_pump + 1);
        settle (attempts - 1)))
  in
  settle 3
;;

let worker_ok = function
  | Ok value -> value
  | Error error -> fail "unexpected Worker runtime error: %s" error
;;

let accepted = function
  | Worker.Accepted request_id -> request_id
  | Full -> fail "SQLite request unexpectedly hit backpressure"
  | Not_ready -> fail "SQLite worker was not ready"
  | Stopping -> fail "SQLite worker was stopping"
;;

let rec drain_until_mutation_and_pushes client events =
  let events = events @ Worker.For_testing.drain_events client ~max_events:64 in
  let has_response =
    List.exists
      (function
        | Worker.Response _ -> true
        | Push _ | Terminal _ -> false)
      events
  in
  let push_topics =
    List.filter_map
      (function
        | Worker.Push { topic; _ } -> Some topic
        | Response _ | Terminal _ -> None)
      events
  in
  if
    has_response
    && List.mem Protocol.Topic.store push_topics
    && List.mem Protocol.Topic.summary push_topics
  then events
  else (
    Worker.For_testing.await_output client;
    drain_until_mutation_and_pushes client events)
;;

let test_service_ready_response_before_autonomous_pushes path =
  let client =
    worker_ok
      (Worker_runtime.start
         ~runtime_epoch:(ID.Runtime.Epoch.of_int64 700L)
         Sqlite_worker_service.service
         (config path))
  in
  Worker.For_testing.await_output client;
  let initial = Worker.For_testing.drain_events client ~max_events:64 in
  require
    (List.exists
       (function
         | Worker.Push { topic; payload = Protocol.Ready _; _ } ->
           topic = Protocol.Topic.ready
         | _ -> false)
       initial)
    "service init did not emit unsolicited Ready";
  let request_id =
    accepted
      (Worker.send
         client
         Protocol.
           { query_generation = 1L
           ; operation = Create_todo { mutation_id = "ordering"; title = "ordered" }
           })
  in
  let events = drain_until_mutation_and_pushes client [] in
  let indexed = List.mapi (fun index event -> index, event) events in
  let response_index =
    List.find_map
      (function
        | index, Worker.Response { request_id = actual; outcome = Completed _; _ }
          when ID.Worker.Request_id.equal request_id actual -> Some index
        | _ -> None)
      indexed
    |> Option.get
  in
  let first_push_index =
    List.find_map
      (function
        | index, Worker.Push { topic; _ }
          when topic = Protocol.Topic.store || topic = Protocol.Topic.summary ->
          Some index
        | _ -> None)
      indexed
    |> Option.get
  in
  require
    (response_index < first_push_index)
    "mutation response was not observable before autonomous snapshot pushes";
  Worker_runtime.stop client
;;

let test_service_reports_worker_startup_timings path =
  let client =
    worker_ok
      (Worker_runtime.start
         ~runtime_epoch:(ID.Runtime.Epoch.of_int64 699L)
         Sqlite_worker_service.service
         (config path))
  in
  Worker.For_testing.await_output client;
  let initial = Worker.For_testing.drain_events client ~max_events:64 in
  let sqlite_open_us =
    List.find_map
      (function
        | Worker.Push { topic; payload = Protocol.Ready { sqlite_open_us; _ }; _ }
          when topic = Protocol.Topic.ready -> Some sqlite_open_us
        | _ -> None)
      initial
    |> Option.get
  in
  require (Int64.compare sqlite_open_us 0L >= 0) "SQLite startup timing was negative";
  ignore
    (accepted
       (Worker.send client Protocol.{ query_generation = 1L; operation = List_todos }));
  let rec await_timing events =
    let events = events @ Worker.For_testing.drain_events client ~max_events:64 in
    match
      List.find_map
        (function
          | Worker.Push { topic; payload = Protocol.Startup_timing timing; _ }
            when topic = Protocol.Topic.startup_timing -> Some timing
          | _ -> None)
        events
    with
    | Some timing -> timing
    | None ->
      Worker.For_testing.await_output client;
      await_timing events
  in
  let timing = await_timing [] in
  require
    (Int64.compare timing.initial_list_us 0L >= 0)
    "initial List timing was negative";
  require
    (Int64.compare timing.total_us timing.sqlite_open_us >= 0)
    "Worker startup total was shorter than SQLite initialization";
  require
    (Int64.compare timing.total_us timing.initial_list_us >= 0)
    "Worker startup total was shorter than the initial List query";
  Worker_runtime.stop client
;;

let test_ready_crud_pushes_and_persistence () =
  with_temporary_database (fun path ->
    let first = create_handle ~runtime_epoch:701L path in
    require_present first "worker-status" "worker status is missing while booting";
    require
      (Option.is_some (Test.Handle.find first (Test.Query.visible_text "Booting"))
       || Option.is_some (Test.Handle.find first (Test.Query.visible_text "Loading")))
      "worker did not begin in Booting or advance to Loading at the first pump";
    settle_initial first;
    require_text first "Ready" "Ready push did not trigger initial List request";
    require_present first "worker-startup-timing" "Worker startup timing panel is missing";
    require_text first "Worker startup timings" "Worker startup timing heading is missing";
    require_text first "SQLite open + migrate" "SQLite startup stage is not displayed";
    require_text first "Initial Todo query" "initial Todo query stage is not displayed";
    require_text first "Worker service total" "Worker service total is not displayed";
    require_text first "0 open · 0 completed" "initial summary is missing";
    require_present first "todo-title-input" "Todo title input is missing";
    require_present first "add-todo" "Add action is missing";
    require_present first "refresh-todos" "Refresh action is missing";
    require_present first "file-demo-panel" "file demo panel is missing";
    require_present first "write-demo-file" "file write action is missing";
    require_present first "read-demo-file" "file read action is missing";
    require_text first "Write 4 MiB demo file" "file write label is missing";
    require_text first "Read demo file" "file read label is missing";
    Test.Handle.present first;
    Test.Handle.click first (Test.Query.test_id "write-demo-file");
    require_present
      first
      "cancel-file-operation"
      "active file operation cannot be cancelled";
    require_text first "Writing demo file…" "file write did not render pending status";
    Test.Handle.present first;
    Test.Handle.click first (Test.Query.test_id "cancel-file-operation");
    require_text
      first
      "Cancelling file operation…"
      "file cancel did not render pending status";
    let rec settle_cancel attempts =
      if attempts = 0
      then fail "file cancellation did not settle"
      else (
        Unix.sleepf 0.001;
        pump_worker first;
        if
          Option.is_some
            (Test.Handle.find first (Test.Query.visible_text "File operation cancelled"))
        then ()
        else settle_cancel (attempts - 1))
    in
    settle_cancel 500;
    Test.Handle.present first;
    Test.Handle.click first (Test.Query.test_id "write-demo-file");
    let rec settle_file attempts =
      if attempts = 0
      then fail "file write did not settle"
      else (
        Unix.sleepf 0.001;
        pump_worker first;
        if
          Option.is_some
            (Test.Handle.find first (Test.Query.visible_text "Wrote 4194304 bytes"))
        then ()
        else settle_file (attempts - 1))
    in
    settle_file 500;
    Test.Handle.present first;
    Test.Handle.click first (Test.Query.test_id "read-demo-file");
    let rec settle_read attempts =
      if attempts = 0
      then fail "file read did not settle"
      else (
        Unix.sleepf 0.001;
        pump_worker first;
        if
          Option.is_some
            (Test.Handle.find first (Test.Query.visible_text "Read 4194304 bytes"))
        then ()
        else settle_read (attempts - 1))
    in
    settle_read 500;
    Test.Handle.present first;
    Test.Handle.input_text first (Test.Query.test_id "todo-title-input") "Persistent 🌳";
    Test.Handle.present first;
    let idle_before_add = worker_idle_wait_count () in
    Test.Handle.click first (Test.Query.test_id "add-todo");
    require_text first "Adding…" "Add did not render a pending state";
    Worker_runtime.For_testing.await_idle_wait_count (idle_before_add + 1);
    pump_worker first;
    require_present first "todo-row-1" "Add response/push did not render Todo row";
    require_text first "Persistent 🌳" "added Todo title is missing";
    require_text
      first
      "1 open · 0 completed"
      "snapshot and summary pushes were not applied";
    Test.Handle.present first;
    let idle_before_toggle = worker_idle_wait_count () in
    Test.Handle.click first (Test.Query.test_id "todo-toggle-1");
    Worker_runtime.For_testing.await_idle_wait_count (idle_before_toggle + 1);
    pump_worker first;
    require_text first "0 open · 1 completed" "Toggle did not update pushed summary";
    Test.Handle.shutdown first;
    require
      ((Worker_runtime.For_testing.diagnostics ()).state = Worker_runtime.Idle)
      "runtime destroy did not close SQLite and return Worker Domain to Idle";
    let second = create_handle ~runtime_epoch:702L path in
    settle_initial second;
    require_text second "Persistent 🌳" "sequential recreation lost persisted Todo";
    require_text
      second
      "0 open · 1 completed"
      "sequential recreation lost completion state";
    Test.Handle.shutdown second)
;;

let test_add_uses_a_fresh_mutation_id_after_process_epoch_reset () =
  with_temporary_database (fun path ->
    let first = create_handle ~runtime_epoch:711L path in
    settle_initial first;
    Test.Handle.present first;
    Test.Handle.input_text first (Test.Query.test_id "todo-title-input") "First";
    Test.Handle.present first;
    let idle_before_first_add = worker_idle_wait_count () in
    Test.Handle.click first (Test.Query.test_id "add-todo");
    Worker_runtime.For_testing.await_idle_wait_count (idle_before_first_add + 1);
    pump_worker first;
    require_present first "todo-row-1" "first process did not add its Todo";
    Test.Handle.shutdown first;
    let second = create_handle ~runtime_epoch:711L path in
    settle_initial second;
    Test.Handle.present second;
    Test.Handle.input_text second (Test.Query.test_id "todo-title-input") "Second";
    Test.Handle.present second;
    let idle_before_second_add = worker_idle_wait_count () in
    Test.Handle.click second (Test.Query.test_id "add-todo");
    Worker_runtime.For_testing.await_idle_wait_count (idle_before_second_add + 1);
    pump_worker second;
    require_present
      second
      "todo-row-2"
      "process epoch reset reused the previous Add mutation ID";
    require_text second "Second" "second process did not add its Todo";
    Test.Handle.shutdown second)
;;

let test_toggle_uses_a_fresh_mutation_id_after_process_epoch_reset () =
  with_temporary_database (fun path ->
    let store =
      match Sqlite_worker_store.open_ ~path with
      | Ok store -> store
      | Error error ->
        fail "failed to seed Toggle database: %s" (Protocol.error_to_string error)
    in
    (match
       Sqlite_worker_store.create_todo store ~mutation_id:"seed" ~title:"Toggle me"
     with
     | Ok _ -> ()
     | Error error -> fail "failed to seed Todo: %s" (Protocol.error_to_string error));
    Sqlite_worker_store.close store;
    let first = create_handle ~runtime_epoch:712L path in
    settle_initial first;
    Test.Handle.present first;
    let idle_before_first_toggle = worker_idle_wait_count () in
    Test.Handle.click first (Test.Query.test_id "todo-toggle-1");
    Worker_runtime.For_testing.await_idle_wait_count (idle_before_first_toggle + 1);
    pump_worker first;
    require_text first "0 open · 1 completed" "first process did not complete its Todo";
    Test.Handle.shutdown first;
    let second = create_handle ~runtime_epoch:712L path in
    settle_initial second;
    Test.Handle.present second;
    let idle_before_second_toggle = worker_idle_wait_count () in
    Test.Handle.click second (Test.Query.test_id "todo-toggle-1");
    Worker_runtime.For_testing.await_idle_wait_count (idle_before_second_toggle + 1);
    pump_worker second;
    require_text
      second
      "1 open · 0 completed"
      "process epoch reset reused the previous Toggle mutation ID";
    Test.Handle.shutdown second)
;;

let () =
  with_temporary_database test_service_reports_worker_startup_timings;
  with_temporary_database test_service_ready_response_before_autonomous_pushes;
  test_ready_crud_pushes_and_persistence ();
  test_toggle_uses_a_fresh_mutation_id_after_process_epoch_reset ();
  test_add_uses_a_fresh_mutation_id_after_process_epoch_reset ();
  Worker_runtime.For_testing.final_shutdown ()
;;
