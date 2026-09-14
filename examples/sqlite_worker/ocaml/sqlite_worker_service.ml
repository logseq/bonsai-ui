module Protocol = Sqlite_worker_protocol
module Store = Sqlite_worker_store
module File_demo = Sqlite_worker_file_demo

type 'persistence state =
  { store : Store.t
  ; persistence : 'persistence
  ; startup_started_us : int64
  ; sqlite_open_us : int64
  ; mutable startup_timing_pending : bool
  }

let now_us () = Int64.of_float (Unix.gettimeofday () *. 1_000_000.)

let elapsed_us started =
  let elapsed = Int64.sub (now_us ()) started in
  if Int64.compare elapsed 0L < 0 then 0L else elapsed
;;

let completed query_generation database_revision payload =
  Protocol.Completed { query_generation; database_revision; payload }
;;

let failed query_generation error = Protocol.Failed { query_generation; error }

let response_of_result
      query_generation
      payload
      (result : (Protocol.mutation_result, Protocol.error) result)
  =
  match result with
  | Ok result ->
    completed query_generation result.Protocol.database_revision (payload result)
  | Error error -> failed query_generation error
;;

let emit_store_snapshot context state =
  match Store.list_todos state.store with
  | Error error ->
    Worker.Request_context.emit context ~topic:Protocol.Topic.fatal (Protocol.Fatal error)
  | Ok snapshot ->
    let open_count, completed_count =
      List.fold_left
        (fun (open_count, completed_count) (todo : Protocol.todo) ->
           if todo.completed
           then open_count, completed_count + 1
           else open_count + 1, completed_count)
        (0, 0)
        snapshot.todos
    in
    Worker.Request_context.emit
      context
      ~topic:Protocol.Topic.store
      (Protocol.Store_changed snapshot);
    Worker.Request_context.emit
      context
      ~topic:Protocol.Topic.summary
      (Protocol.Summary_changed
         { database_revision = snapshot.database_revision; open_count; completed_count })
;;

let file_progress context operation (progress : File_demo.progress) =
  Worker.Request_context.emit
    context
    ~topic:Protocol.Topic.file_progress
    (Protocol.File_progress
       { operation
       ; completed_bytes = progress.completed_bytes
       ; total_bytes = progress.total_bytes
       })
;;

let file_failure request error =
  Protocol.Failed { query_generation = request.Protocol.query_generation; error }
;;

let file_completed state request payload =
  completed
    request.Protocol.query_generation
    (Store.database_revision state.store)
    payload
;;

let write_demo_file context state request total_bytes =
  match Worker.Request_context.data_dir context with
  | None -> Ok (file_failure request Protocol.File_unavailable)
  | Some directory ->
    if total_bytes <= 0 || total_bytes > File_demo.max_file_size
    then Ok (file_failure request (Protocol.Invalid_file_size total_bytes))
    else (
      match
        File_demo.write
          ~sw:(Worker.Request_context.switch context)
          ~directory
          ~request_id:(Worker.Request_context.request_id context)
          ~total_bytes
          ~progress:(file_progress context Protocol.Writing)
      with
      | Ok () ->
        Ok (file_completed state request (Protocol.File (File_written { total_bytes })))
      | Error error -> Ok (file_failure request (Protocol.File_error error)))
;;

let read_demo_file context state request =
  match Worker.Request_context.data_dir context with
  | None -> Ok (file_failure request Protocol.File_unavailable)
  | Some directory ->
    (match
       File_demo.read
         ~sw:(Worker.Request_context.switch context)
         ~directory
         ~progress:(file_progress context Protocol.Reading)
     with
     | Ok result ->
       Ok
         (file_completed
            state
            request
            (Protocol.File
               (File_read { total_bytes = result.total_bytes; checksum = result.checksum })))
     | Error error -> Ok (file_failure request (Protocol.File_error error)))
;;

type 'persistence persistence_probe =
  { open_ : Sqlite_worker_config.t -> ('persistence, string) result
  ; close : 'persistence -> unit
  }

let create_with_persistence_probe persistence_probe =
  Worker.Service.create
    ~push_topic_count:Protocol.Topic.count
    ~concurrency:Worker.Service.Serial
    ~data_directory:(fun config ->
      Ok config.Sqlite_worker_config.application_support_directory)
    ~init:(fun session config ->
      let startup_started_us = now_us () in
      match Store.open_ ~path:config.Sqlite_worker_config.database_path with
      | Error error -> Error (Protocol.error_to_string error)
      | Ok store ->
        (match persistence_probe.open_ config with
         | Error message ->
           Store.close store;
           Error message
         | Ok persistence ->
           let sqlite_open_us = elapsed_us startup_started_us in
           Worker.Session_context.emit
             session
             ~topic:Protocol.Topic.ready
             (Protocol.Ready
                { schema_version = Store.schema_version store
                ; database_revision = Store.database_revision store
                ; sqlite_open_us
                });
           Ok
             { store
             ; persistence
             ; startup_started_us
             ; sqlite_open_us
             ; startup_timing_pending = true
             }))
    ~handle:(fun context state request ->
      match request.Protocol.operation with
      | Protocol.List_todos ->
        let list_started_us = now_us () in
        let result = Store.list_todos state.store in
        let initial_list_us = elapsed_us list_started_us in
        if state.startup_timing_pending
        then (
          state.startup_timing_pending <- false;
          Worker.Request_context.emit
            context
            ~topic:Protocol.Topic.startup_timing
            (Protocol.Startup_timing
               { sqlite_open_us = state.sqlite_open_us
               ; initial_list_us
               ; total_us = elapsed_us state.startup_started_us
               }));
        let response =
          match result with
          | Ok snapshot ->
            completed
              request.query_generation
              snapshot.database_revision
              (Protocol.Snapshot snapshot)
          | Error error -> failed request.query_generation error
        in
        Ok response
      | Create_todo { mutation_id; title } ->
        let result = Store.create_todo state.store ~mutation_id ~title in
        (match result with
         | Ok { status = `Applied; _ } -> emit_store_snapshot context state
         | Ok { status = `Duplicate; _ } | Error _ -> ());
        Ok
          (response_of_result
             request.query_generation
             (fun value -> Protocol.Mutation value)
             result)
      | Set_completed { mutation_id; todo_id; completed } ->
        let result = Store.set_completed state.store ~mutation_id ~todo_id ~completed in
        (match result with
         | Ok { status = `Applied; _ } -> emit_store_snapshot context state
         | Ok { status = `Duplicate; _ } | Error _ -> ());
        Ok
          (response_of_result
             request.query_generation
             (fun value -> Protocol.Mutation value)
             result)
      | Write_demo_file { total_bytes } ->
        write_demo_file context state request total_bytes
      | Read_demo_file -> read_demo_file context state request)
    ~shutdown:(fun state ->
      Fun.protect
        ~finally:(fun () -> Store.close state.store)
        (fun () -> persistence_probe.close state.persistence))
    ()
;;

let service =
  create_with_persistence_probe { open_ = (fun _config -> Ok ()); close = (fun () -> ()) }
;;
