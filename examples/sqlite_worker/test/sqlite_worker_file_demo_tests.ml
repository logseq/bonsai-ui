module ID = Bonsai_swiftui_spec.Id
module Config = Sqlite_worker_config
module File_demo = Sqlite_worker_file_demo
module Protocol = Sqlite_worker_protocol

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let with_temporary_directory test =
  let marker = Filename.temp_file "bonsai_swiftui_file_demo_" ".tmp" in
  Sys.remove marker;
  Unix.mkdir marker 0o700;
  let cleanup () =
    Sys.readdir marker
    |> Array.iter (fun name -> Sys.remove (Filename.concat marker name));
    Unix.rmdir marker
  in
  Fun.protect ~finally:cleanup (fun () -> test marker)
;;

let checksum_string value =
  let checksum = ref 0L in
  String.iter
    (fun byte ->
       checksum
       := Int64.add
            (Int64.mul !checksum 1_099_511_628_211L)
            (Int64.of_int (Char.code byte)))
    value;
  !checksum
;;

let test_config_codec () =
  let expected =
    Config.
      { database_path = "/tmp/support/sqlite_worker/todos.sqlite3"
      ; application_support_directory = "/tmp/support/sqlite_worker"
      }
  in
  let encoded = Config.encode expected in
  require
    (Bytes.sub_string encoded 0 4 = "SWC1")
    "SQLite Worker config omitted its versioned magic";
  require (Config.decode encoded = Ok expected) "SQLite Worker config did not round-trip";
  require
    (Result.is_error (Config.decode (Bytes.of_string "not-a-config")))
    "SQLite Worker config accepted malformed bytes";
  require
    (Result.is_error
       (Config.decode
          (Config.encode
             { expected with application_support_directory = "relative/support" })))
    "SQLite Worker config accepted a relative confined directory"
;;

let test_real_write_read_limits_and_atomic_replace directory_path =
  Eio_posix.run (fun environment ->
    Eio.Switch.run (fun sw ->
      let directory =
        Eio.Path.open_dir ~sw Eio.Path.(Eio.Stdenv.fs environment / directory_path)
      in
      let total_bytes = (2 * File_demo.chunk_size) + 17 in
      let write_progress = ref [] in
      let request_id = ID.Worker.Request_id.of_int64 41L in
      require
        (File_demo.write
           ~sw
           ~directory
           ~request_id
           ~total_bytes
           ~progress:(fun progress -> write_progress := progress :: !write_progress)
         = Ok ())
        "bounded file write failed";
      let write_progress = List.rev !write_progress in
      require
        (List.map (fun progress -> progress.File_demo.completed_bytes) write_progress
         = [ File_demo.chunk_size; 2 * File_demo.chunk_size; total_bytes ])
        "write progress was not monotonic at 64 KiB boundaries";
      let final_path = Eio.Path.(directory / File_demo.file_name) in
      let contents = Eio.Path.load final_path in
      require
        (String.length contents = total_bytes)
        "file write produced the wrong length";
      require
        (Eio.Path.read_dir directory = [ File_demo.file_name ])
        "successful write retained a temporary file";
      let read_progress = ref [] in
      let read =
        File_demo.read ~sw ~directory ~progress:(fun progress ->
          read_progress := progress :: !read_progress)
      in
      (match read with
       | Error error -> fail "bounded file read failed: %s" error
       | Ok result ->
         require (result.total_bytes = total_bytes) "read returned the wrong byte count";
         require
           (Int64.equal result.checksum (checksum_string contents))
           "read returned the wrong deterministic checksum");
      require
        (List.for_all
           (fun progress -> progress.File_demo.completed_bytes <= progress.total_bytes)
           !read_progress)
        "read progress exceeded its declared total";
      require
        (Result.is_error
           (File_demo.write
              ~sw
              ~directory
              ~request_id
              ~total_bytes:(File_demo.max_file_size + 1)
              ~progress:(fun _ -> ())))
        "write accepted a file larger than 16 MiB"));
  let oversized = Filename.concat directory_path File_demo.file_name in
  Unix.truncate oversized (File_demo.max_file_size + 1);
  Eio_posix.run (fun environment ->
    Eio.Switch.run (fun sw ->
      let directory =
        Eio.Path.open_dir ~sw Eio.Path.(Eio.Stdenv.fs environment / directory_path)
      in
      require
        (Result.is_error (File_demo.read ~sw ~directory ~progress:(fun _ -> ())))
        "read accepted a file larger than 16 MiB"))
;;

let test_cancellation_removes_only_temporary_file directory_path =
  let old_contents = "previous completed file" in
  let final_native = Filename.concat directory_path File_demo.file_name in
  let channel = open_out_bin final_native in
  output_string channel old_contents;
  close_out channel;
  for boundary = 1 to 3 do
    let cancelled =
      try
        Eio_posix.run (fun environment ->
          Eio.Switch.run (fun sw ->
            let directory =
              Eio.Path.open_dir ~sw Eio.Path.(Eio.Stdenv.fs environment / directory_path)
            in
            File_demo.For_testing.write
              ~after_chunk:(fun chunk -> if chunk = boundary then Eio.Switch.fail sw Exit)
              ~sw
              ~directory
              ~request_id:(ID.Worker.Request_id.of_int64 (Int64.of_int boundary))
              ~total_bytes:(3 * File_demo.chunk_size)
              ~progress:(fun _ -> ())))
        |> ignore;
        false
      with
      | Exit | Eio.Cancel.Cancelled Exit -> true
    in
    require cancelled "chunk-boundary cancellation did not unwind the write";
    let channel = open_in_bin final_native in
    let retained = really_input_string channel (in_channel_length channel) in
    close_in channel;
    require
      (String.equal retained old_contents)
      "cancelled write replaced the previously completed file";
    require
      (Sys.readdir directory_path
       |> Array.to_list
       |> List.for_all (fun name -> not (Filename.check_suffix name ".tmp")))
      "cancelled write retained its temporary file"
  done
;;

module Blocking_sink = struct
  type t =
    { started : unit Eio.Promise.u
    ; blocked : unit Eio.Promise.t
    }

  let single_write t buffers =
    ignore (Eio.Promise.try_resolve t.started () : bool);
    Eio.Promise.await t.blocked;
    Cstruct.lenv buffers
  ;;

  let copy t ~src = Eio.Flow.Pi.simple_copy ~single_write t ~src
end

module Blocking_source = struct
  type t =
    { started : unit Eio.Promise.u
    ; blocked : unit Eio.Promise.t
    }

  let read_methods = []

  let single_read t _buffer =
    ignore (Eio.Promise.try_resolve t.started () : bool);
    Eio.Promise.await t.blocked;
    raise End_of_file
  ;;
end

let blocking_sink state = Eio.Resource.T (state, Eio.Flow.Pi.sink (module Blocking_sink))

let blocking_source state =
  Eio.Resource.T (state, Eio.Flow.Pi.source (module Blocking_source))
;;

let test_mock_flow_suspension_is_cancellable () =
  let test operation =
    let cancelled =
      try
        Eio_posix.run (fun _environment ->
          Eio.Switch.run (fun sw ->
            let started, started_resolver = Eio.Promise.create () in
            let blocked, _ = Eio.Promise.create () in
            Eio.Fiber.fork ~sw (fun () ->
              Eio.Promise.await started;
              Eio.Switch.fail sw Exit);
            operation started_resolver blocked));
        false
      with
      | Exit | Eio.Cancel.Cancelled Exit -> true
    in
    require cancelled "controlled mock flow did not suspend until cancellation"
  in
  test (fun started blocked ->
    File_demo.For_testing.write_chunks
      (blocking_sink Blocking_sink.{ started; blocked })
      ~total_bytes:File_demo.chunk_size
      ~progress:(fun _ -> ()));
  test (fun started blocked ->
    ignore
      (File_demo.For_testing.read_chunks
         (blocking_source Blocking_source.{ started; blocked })
         ~declared_total:File_demo.chunk_size
         ~progress:(fun _ -> ())))
;;

let response_for events request_id =
  List.find_map
    (function
      | Worker.Response { request_id = actual; outcome; _ }
        when ID.Worker.Request_id.equal request_id actual -> Some outcome
      | Response _ | Push _ | Terminal _ -> None)
    events
;;

let rec drain_until_response client request_id events =
  let events = events @ Worker.For_testing.drain_events client ~max_events:64 in
  match response_for events request_id with
  | Some outcome -> outcome, events
  | None ->
    Worker.For_testing.await_output client;
    drain_until_response client request_id events
;;

let accepted = function
  | Worker.Accepted request_id -> request_id
  | Full | Not_ready | Stopping -> fail "file demo request was not accepted"
;;

let test_worker_service_uses_confined_directory directory_path =
  let database_path = Filename.concat directory_path "todos.sqlite3" in
  let config = Config.{ database_path; application_support_directory = directory_path } in
  let client =
    match
      Worker_runtime.start
        ~runtime_epoch:(ID.Runtime.Epoch.of_int64 801L)
        Sqlite_worker_service.service
        config
    with
    | Ok client -> client
    | Error error -> fail "file demo Worker failed to start: %s" error
  in
  Worker.For_testing.await_output client;
  ignore (Worker.For_testing.drain_events client ~max_events:64 : _ list);
  let write_id =
    accepted
      (Worker.send
         client
         Protocol.
           { query_generation = 1L
           ; operation = Write_demo_file { total_bytes = File_demo.chunk_size + 7 }
           })
  in
  let write_outcome, write_events = drain_until_response client write_id [] in
  (match write_outcome with
   | Worker.Completed
       (Protocol.Completed { payload = File (File_written { total_bytes }); _ }) ->
     require (total_bytes = File_demo.chunk_size + 7) "Worker write response lost size"
   | _ -> fail "Worker write returned the wrong typed response");
  require
    (List.exists
       (function
         | Worker.Push
             { topic; payload = Protocol.File_progress { operation = Writing; _ }; _ } ->
           topic = Protocol.Topic.file_progress
         | _ -> false)
       write_events)
    "Worker write emitted no latest-wins progress";
  let read_id =
    accepted
      (Worker.send client Protocol.{ query_generation = 2L; operation = Read_demo_file })
  in
  let read_outcome, _ = drain_until_response client read_id [] in
  (match read_outcome with
   | Worker.Completed
       (Protocol.Completed { payload = File (File_read { total_bytes; checksum = _ }); _ })
     -> require (total_bytes = File_demo.chunk_size + 7) "Worker read response lost size"
   | _ -> fail "Worker read returned the wrong typed response");
  Worker_runtime.stop client
;;

let () =
  test_config_codec ();
  test_mock_flow_suspension_is_cancellable ();
  with_temporary_directory (fun directory ->
    test_real_write_read_limits_and_atomic_replace directory);
  with_temporary_directory test_cancellation_removes_only_temporary_file;
  with_temporary_directory test_worker_service_uses_confined_directory;
  Worker_runtime.For_testing.final_shutdown ()
;;
