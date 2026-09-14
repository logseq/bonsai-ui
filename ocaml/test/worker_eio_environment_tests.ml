module ID = Bonsai_swiftui_spec.Id

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let service =
  Worker.Service.create
    ~push_topic_count:1
    ~concurrency:Worker.Service.Serial
    ~init:(fun context () ->
      let environment = Worker.Session_context.environment context in
      require
        (Eio.Stdenv.mono_clock environment == Worker.Session_context.clock context)
        "session environment exposes a different clock";
      require
        ((Eio.Stdenv.net environment :> Worker.net) == Worker.Session_context.net context)
        "session environment exposes a different network";
      Ok ())
    ~handle:(fun context () () ->
      let environment = Worker.Request_context.environment context in
      require
        (Eio.Stdenv.mono_clock environment == Worker.Request_context.clock context)
        "request environment exposes a different clock";
      require
        ((Eio.Stdenv.net environment :> Worker.net) == Worker.Request_context.net context)
        "request environment exposes a different network";
      Ok ())
    ~shutdown:(fun () -> ())
    ()
;;

let () =
  let client =
    match
      Worker_runtime.start ~runtime_epoch:(ID.Runtime.Epoch.of_int64 904L) service ()
    with
    | Ok client -> client
    | Error error -> fail "environment Worker failed to start: %s" error
  in
  let request_id =
    match Worker.send client () with
    | Worker.Accepted request_id -> request_id
    | Full | Not_ready | Stopping -> fail "environment request was not accepted"
  in
  let rec await_response () =
    match
      Worker.For_testing.drain_events client ~max_events:64
      |> List.find_map (function
        | Worker.Response { request_id = actual; outcome; _ }
          when ID.Worker.Request_id.equal request_id actual -> Some outcome
        | Response _ | Push _ | Terminal _ -> None)
    with
    | Some (Worker.Completed ()) -> ()
    | Some _ -> fail "environment request did not complete"
    | None ->
      Worker.For_testing.await_output client;
      await_response ()
  in
  await_response ();
  Worker_runtime.stop client;
  Worker_runtime.For_testing.final_shutdown ()
;;
