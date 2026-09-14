module Protocol = Sqlite_worker_protocol
module Store = Sqlite_worker_store

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let store_ok = function
  | Ok value -> value
  | Error error -> fail "unexpected store error: %s" (Protocol.error_to_string error)
;;

let with_temporary_directory test =
  let marker = Filename.temp_file "bonsai_swiftui_sqlite_worker_" ".tmp" in
  Sys.remove marker;
  Unix.mkdir marker 0o700;
  let database_path = Filename.concat marker "todos.sqlite3" in
  let cleanup () =
    List.iter
      (fun path -> if Sys.file_exists path then Sys.remove path)
      [ database_path; database_path ^ "-journal" ];
    Unix.rmdir marker
  in
  Fun.protect ~finally:cleanup (fun () -> test marker database_path)
;;

let on_domain run = Domain.spawn run |> Domain.join

let require_todo snapshot ~title ~completed =
  List.find_opt
    (fun (todo : Protocol.todo) -> String.equal todo.title title)
    snapshot.Protocol.todos
  |> function
  | Some todo ->
    require (Bool.equal todo.completed completed) "Todo completion state changed";
    todo
  | None -> fail "Todo %S is missing" title
;;

let test_migration_unicode_reopen_and_close () =
  with_temporary_directory (fun _directory database_path ->
    on_domain (fun () ->
      let store = store_ok (Store.open_ ~path:database_path) in
      require (Store.schema_version store = 1) "first open did not migrate schema";
      require (Store.database_revision store = 0L) "first migration revision was not zero";
      let created =
        store_ok
          (Store.create_todo
             store
             ~mutation_id:"create-unicode"
             ~title:"  你好 'bonsai' 🌳  ")
      in
      require (created.status = `Applied) "first mutation was not applied";
      require (created.database_revision = 1L) "first mutation did not increment revision";
      let snapshot = store_ok (Store.list_todos store) in
      ignore (require_todo snapshot ~title:"你好 'bonsai' 🌳" ~completed:false);
      Store.close store;
      Store.close store);
    on_domain (fun () ->
      let reopened = store_ok (Store.open_ ~path:database_path) in
      require (Store.schema_version reopened = 1) "reopen reran an incompatible migration";
      require (Store.database_revision reopened = 1L) "reopen lost database revision";
      ignore
        (require_todo
           (store_ok (Store.list_todos reopened))
           ~title:"你好 'bonsai' 🌳"
           ~completed:false);
      Store.close reopened))
;;

let test_validation_list_bound_idempotency_and_transactional_revision () =
  with_temporary_directory (fun _directory database_path ->
    on_domain (fun () ->
      let store = store_ok (Store.open_ ~path:database_path) in
      require
        (Store.create_todo store ~mutation_id:"empty" ~title:" \t\n"
         = Error Protocol.Invalid_title)
        "blank title was accepted";
      require
        (Store.create_todo store ~mutation_id:"long" ~title:(String.make 513 'x')
         = Error Protocol.Title_too_long)
        "title longer than 512 UTF-8 bytes was accepted";
      let first =
        store_ok (Store.create_todo store ~mutation_id:"same-create" ~title:"first")
      in
      let duplicate =
        store_ok (Store.create_todo store ~mutation_id:"same-create" ~title:"different")
      in
      require
        (first.status = `Applied && duplicate.status = `Duplicate)
        "duplicate create was applied twice";
      require
        (first.database_revision = 1L && duplicate.database_revision = 1L)
        "duplicate create changed its durable revision";
      let todo =
        require_todo (store_ok (Store.list_todos store)) ~title:"first" ~completed:false
      in
      let toggled =
        store_ok
          (Store.set_completed
             store
             ~mutation_id:"same-toggle"
             ~todo_id:todo.id
             ~completed:true)
      in
      let duplicate_toggle =
        store_ok
          (Store.set_completed
             store
             ~mutation_id:"same-toggle"
             ~todo_id:todo.id
             ~completed:false)
      in
      require
        (toggled.status = `Applied && duplicate_toggle.status = `Duplicate)
        "duplicate toggle was applied twice";
      require
        (toggled.database_revision = 2L && duplicate_toggle.database_revision = 2L)
        "duplicate toggle changed its durable revision";
      ignore
        (require_todo (store_ok (Store.list_todos store)) ~title:"first" ~completed:true);
      for index = 2 to 106 do
        ignore
          (store_ok
             (Store.create_todo
                store
                ~mutation_id:(Printf.sprintf "bulk-%d" index)
                ~title:(Printf.sprintf "Todo %03d" index)))
      done;
      let bounded = store_ok (Store.list_todos store) in
      require (List.length bounded.todos = 100) "list query exceeded its 100-row bound";
      require
        ((List.hd bounded.todos).title = "Todo 106")
        "bounded list did not return newest rows first";
      require
        (bounded.database_revision = 107L)
        "transactional database revision did not match applied mutations";
      Store.close store))
;;

let test_path_schema_busy_corrupt_and_open_failures () =
  require
    (Store.open_ ~path:"relative/todos.sqlite3"
     = Error (Protocol.Invalid_path "relative/todos.sqlite3"))
    "relative database path was accepted";
  require
    (Store.open_ ~path:"" = Error (Protocol.Invalid_path ""))
    "empty database path was accepted";
  require
    (Store.open_ ~path:"/tmp/invalid\000path.sqlite3"
     = Error (Protocol.Invalid_path "/tmp/invalid\000path.sqlite3"))
    "NUL-containing database path was accepted";
  let oversized_path = "/" ^ String.make (1024 * 1024) 'x' in
  require
    (Store.open_ ~path:oversized_path = Error (Protocol.Invalid_path oversized_path))
    "oversized database path was accepted";
  let malformed_utf8_path = "/tmp/invalid\255path.sqlite3" in
  require
    (Store.open_ ~path:malformed_utf8_path
     = Error (Protocol.Invalid_path malformed_utf8_path))
    "malformed UTF-8 database path was accepted";
  with_temporary_directory (fun directory database_path ->
    let future_path = Filename.concat directory "future.sqlite3" in
    let future = Sqlite3.db_open future_path in
    ignore (Sqlite3.exec future "PRAGMA user_version = 2");
    ignore (Sqlite3.db_close future);
    on_domain (fun () ->
      require
        (Store.open_ ~path:future_path = Error (Protocol.Unsupported_schema 2))
        "future schema was downgraded or accepted");
    Sys.remove future_path;
    let corrupt_path = Filename.concat directory "corrupt.sqlite3" in
    let output = open_out_bin corrupt_path in
    output_string output "not a sqlite database";
    close_out output;
    on_domain (fun () ->
      match Store.open_ ~path:corrupt_path with
      | Error (Protocol.Corrupt _) -> ()
      | Ok store ->
        Store.close store;
        fail "corrupt database was silently recreated"
      | Error error ->
        fail "corrupt database returned wrong error: %s" (Protocol.error_to_string error));
    Sys.remove corrupt_path;
    on_domain (fun () ->
      match Store.open_ ~path:directory with
      | Error (Protocol.Cannot_open _) -> ()
      | Ok store ->
        Store.close store;
        fail "directory path opened as a database"
      | Error error ->
        fail "unopenable path returned wrong error: %s" (Protocol.error_to_string error));
    let mutex = Mutex.create () in
    let condition = Condition.create () in
    let phase = ref 0 in
    let worker =
      Domain.spawn (fun () ->
        let store = store_ok (Store.open_ ~path:database_path) in
        Mutex.lock mutex;
        phase := 1;
        Condition.broadcast condition;
        while !phase < 2 do
          Condition.wait condition mutex
        done;
        Mutex.unlock mutex;
        let result = Store.create_todo store ~mutation_id:"busy" ~title:"blocked" in
        Store.close store;
        result)
    in
    Mutex.lock mutex;
    while !phase < 1 do
      Condition.wait condition mutex
    done;
    Mutex.unlock mutex;
    let locker = Sqlite3.db_open database_path in
    ignore (Sqlite3.exec locker "BEGIN EXCLUSIVE");
    Mutex.lock mutex;
    phase := 2;
    Condition.broadcast condition;
    Mutex.unlock mutex;
    (match Domain.join worker with
     | Error Protocol.Busy -> ()
     | Ok _ -> fail "exclusive lock did not produce finite Busy"
     | Error error ->
       fail "busy lock returned wrong error: %s" (Protocol.error_to_string error));
    ignore (Sqlite3.exec locker "ROLLBACK");
    ignore (Sqlite3.db_close locker))
;;

let () =
  test_migration_unicode_reopen_and_close ();
  test_validation_list_bound_idempotency_and_transactional_revision ();
  test_path_schema_busy_corrupt_and_open_failures ()
;;
