module ID = Bonsai_swiftui_spec.Id
module Ui = Bonsai_swiftui_ui

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let application_theme =
  Ui.Theme.create ~tint:(Ui.Style.Color.rgb ~red:103 ~green:80 ~blue:164) ()
;;

let set_u16_le bytes offset value =
  Bytes.set_uint8 bytes offset (value land 0xff);
  Bytes.set_uint8 bytes (offset + 1) ((value lsr 8) land 0xff)
;;

let set_u32_le bytes offset value =
  for index = 0 to 3 do
    Bytes.set_uint8 bytes (offset + index) ((value lsr (index * 8)) land 0xff)
  done
;;

let startup_config ~policy ~entrypoint ~payload =
  let entrypoint = Bytes.of_string entrypoint in
  let payload = Bytes.of_string payload in
  let config = Bytes.create (20 + Bytes.length entrypoint + Bytes.length payload) in
  Bytes.blit_string "BSR1" 0 config 0 4;
  set_u16_le config 4 1;
  set_u16_le config 6 0;
  Bytes.set_uint8 config 8 policy;
  Bytes.fill config 9 3 '\000';
  set_u32_le config 12 (Bytes.length entrypoint);
  set_u32_le config 16 (Bytes.length payload);
  Bytes.blit entrypoint 0 config 20 (Bytes.length entrypoint);
  Bytes.blit payload 0 config (20 + Bytes.length entrypoint) (Bytes.length payload);
  config
;;

type request =
  | Echo of string
  | Fail

let shutdown_count = Atomic.make 0

let service =
  Worker.Service.create
    ~push_topic_count:1
    ~concurrency:Worker.Service.Serial
    ~init:(fun session config ->
      if String.equal config "fail-init"
      then Error "intentional init failure"
      else (
        Worker.Session_context.emit session ~topic:(ID.Worker.Push_topic.of_int 0) "ready";
        Ok ()))
    ~handle:(fun _context () -> function
       | Echo value -> Ok value
       | Fail -> failwith "intentional backend service failure")
    ~shutdown:(fun () -> Atomic.incr shutdown_count)
    ()
;;

let live_client : (request, string, string) Worker.client option ref = ref None
let terminal_events = ref 0

let worker_component client _context _graph =
  live_client := Some client;
  Worker.on_event client (function
    | Worker.Terminal _ -> Bonsai.Effect.of_thunk (fun () -> Stdlib.incr terminal_events)
    | Response _ | Push _ -> Bonsai.Effect.return ());
  Bonsai.Cont.return
    (App.View.create
       ~theme:application_theme
       ~body:(Ui.View.Body.static (Ui.View.text "worker-backed")))
;;

let ui_component _context _graph =
  Bonsai.Cont.return
    (App.View.create
       ~theme:application_theme
       ~body:(Ui.View.Body.static (Ui.View.text "ui-only")))
;;

let client () =
  match !live_client with
  | Some client -> client
  | None -> fail "worker-backed App did not publish its domain-0 client"
;;

let () =
  Entrypoint.For_testing.clear ();
  Entrypoint.register
    ~name:(ID.Application.Entrypoint_name.of_string "ui-only")
    (App.create ui_component);
  Entrypoint.register
    ~name:(ID.Application.Entrypoint_name.of_string "worker-backed")
    (App.create_with_worker
       ~decode_config:(fun payload -> Ok (Bytes.to_string payload))
       ~service
       worker_component);
  Native_backend.For_testing.reset_observations ();
  let fresh_worker = startup_config ~policy:0 ~entrypoint:"worker-backed" ~payload:"ok" in
  let replace_worker =
    startup_config ~policy:1 ~entrypoint:"worker-backed" ~payload:"ok"
  in
  let fresh_ui = startup_config ~policy:0 ~entrypoint:"ui-only" ~payload:"" in
  let replace_ui = startup_config ~policy:1 ~entrypoint:"ui-only" ~payload:"" in
  let first = Native_backend.create fresh_worker in
  require (first.status = Native_backend.Ok) "worker-backed runtime did not create";
  let first_domain =
    (Worker_runtime.For_testing.diagnostics ()).worker_domain_id |> Option.get
  in
  let duplicate = Native_backend.create fresh_ui in
  require
    (duplicate.status = Native_backend.Fatal_error)
    "second Fresh UI-only App overlapped worker-backed App";
  let duplicate_backend = Native_backend.For_testing.observations () in
  let duplicate_worker = Worker_runtime.For_testing.diagnostics () in
  require
    (duplicate_backend.driver_creations = 1 && duplicate_backend.peak_active_drivers = 1)
    "second Fresh allocated or overlapped a Driver";
  require
    (duplicate_worker.spawn_count = 1
     && duplicate_worker.active_sessions = 1
     && duplicate_worker.peak_active_sessions = 1)
    "second Fresh allocated or overlapped a worker session";
  let old_client = client () in
  Native_backend.For_testing.clear_state_history ();
  let replacement_ui = Native_backend.create replace_ui in
  require (replacement_ui.status = Native_backend.Ok) "worker-to-UI replacement failed";
  require
    (Native_backend.For_testing.state_history ()
     = [ Native_backend.For_testing.Destroying
       ; Native_backend.For_testing.Empty
       ; Native_backend.For_testing.Creating
       ; Native_backend.For_testing.Active
       ])
    "worker-to-UI replacement skipped the singleton transition";
  require (Atomic.get shutdown_count = 1) "old worker resources were not shut down";
  require
    ((Worker_runtime.For_testing.diagnostics ()).state = Worker_runtime.Idle)
    "worker session was not Idle before UI replacement became Active";
  require
    (Worker.send old_client (Echo "stale") = Worker.Stopping)
    "old client survived replacement";
  let replacement_worker = Native_backend.create replace_worker in
  require
    (replacement_worker.status = Native_backend.Ok)
    "UI-to-worker replacement failed";
  let replacement_diagnostics = Worker_runtime.For_testing.diagnostics () in
  require
    (replacement_diagnostics.worker_domain_id = Some first_domain)
    "replacement spawned a different Worker Domain";
  require
    (replacement_diagnostics.spawn_count = 1
     && replacement_diagnostics.join_count = 0
     && replacement_diagnostics.peak_active_sessions = 1)
    "replacement spawned, joined, or overlapped worker sessions";
  Native_backend.destroy replacement_worker.handle;
  require
    ((Worker_runtime.For_testing.diagnostics ()).state = Worker_runtime.Idle)
    "ordinary backend destroy did not leave Worker Domain Idle";
  let failed_init =
    Native_backend.create
      (startup_config ~policy:0 ~entrypoint:"worker-backed" ~payload:"fail-init")
  in
  require (failed_init.status = Native_backend.Fatal_error) "failed worker init succeeded";
  require
    (Core.String.is_substring failed_init.error ~substring:"intentional init failure")
    "failed worker init lost its diagnostic";
  require
    (Native_backend.For_testing.state () = Native_backend.For_testing.Empty)
    "failed worker init did not restore backend Empty";
  require
    ((Worker_runtime.For_testing.diagnostics ()).state = Worker_runtime.Idle)
    "failed worker init did not restore Worker Domain Idle";
  let failing_runtime = Native_backend.create fresh_worker in
  require (failing_runtime.status = Native_backend.Ok) "post-init-failure create failed";
  let failing_client = client () in
  ignore (Worker.send failing_client Fail);
  Worker_runtime.For_testing.await_state Worker_runtime.Idle;
  ignore (Native_backend.pump failing_runtime.handle 0L Bytes.empty);
  require
    (Native_backend.For_testing.state () = Native_backend.For_testing.Active)
    "caught service failure destroyed the backend runtime";
  require (!terminal_events = 1) "caught service failure emitted no terminal App event";
  Native_backend.destroy failing_runtime.handle;
  Worker_runtime.For_testing.crash_worker_loop ();
  Worker_runtime.For_testing.await_state Worker_runtime.Terminal;
  let ui_after_terminal = Native_backend.create fresh_ui in
  require
    (ui_after_terminal.status = Native_backend.Ok)
    "UI-only App could not start after Worker Domain Terminal";
  Native_backend.destroy ui_after_terminal.handle;
  let worker_after_terminal = Native_backend.create fresh_worker in
  require
    (worker_after_terminal.status = Native_backend.Fatal_error)
    "worker-backed App started after Worker Domain Terminal";
  let final_backend_observations = Native_backend.For_testing.observations () in
  require
    (final_backend_observations.peak_active_drivers = 1)
    "worker lifecycle integration overlapped Drivers";
  require
    ((Worker_runtime.For_testing.diagnostics ()).peak_active_sessions = 1)
    "worker lifecycle integration overlapped sessions";
  Native_backend.For_testing.final_shutdown ();
  let final_worker = Worker_runtime.For_testing.diagnostics () in
  require (final_worker.join_count = 1) "backend final shutdown did not join once";
  Native_backend.For_testing.final_shutdown ();
  require
    ((Worker_runtime.For_testing.diagnostics ()).join_count = 1)
    "repeated backend final shutdown joined again";
  let stopped_ui = Native_backend.create fresh_ui in
  require
    (stopped_ui.status = Native_backend.Fatal_error)
    "UI-only create after Finalized succeeded"
;;
