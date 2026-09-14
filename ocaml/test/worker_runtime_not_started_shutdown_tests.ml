let require condition message = if not condition then failwith message

let () =
  let before = Worker_runtime.For_testing.diagnostics () in
  require (before.state = Worker_runtime.Not_started) "worker did not begin Not_started";
  require
    (before.backend_run_count = 0 && not before.backend_running)
    "unused Worker runtime started an Eio backend";
  Worker_runtime.For_testing.final_shutdown ();
  Worker_runtime.For_testing.final_shutdown ();
  let after = Worker_runtime.For_testing.diagnostics () in
  require (after.state = Worker_runtime.Stopped) "Not_started shutdown did not stop";
  require
    (after.backend_run_count = 0 && not after.backend_running)
    "Not_started shutdown started an Eio backend";
  require (after.spawn_count = 0) "Not_started shutdown spawned a Domain";
  require (after.join_count = 0) "Not_started shutdown joined a Domain"
;;
