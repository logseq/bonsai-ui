module Protocol = Sqlite_worker_protocol

type t =
  { mutable database : Sqlite3.db option
  ; schema_version : int
  ; mutable database_revision : int64
  }

exception Store_error of Protocol.error

let schema_version_number = 1
let busy_timeout_ms = 250
let maximum_title_bytes = 512
let maximum_path_bytes = 1024 * 1024

let error_of_rc database ~context rc =
  let message = Printf.sprintf "%s: %s" context (Sqlite3.errmsg database) in
  match rc with
  | Sqlite3.Rc.BUSY | LOCKED -> Protocol.Busy
  | FULL -> Protocol.Full
  | READONLY -> Protocol.Read_only
  | CANTOPEN -> Protocol.Cannot_open message
  | CORRUPT | NOTADB -> Protocol.Corrupt message
  | _ -> Protocol.Storage_error message
;;

let raise_on_rc database ~context = function
  | Sqlite3.Rc.OK | DONE -> ()
  | rc -> raise (Store_error (error_of_rc database ~context rc))
;;

let protect database operation =
  try Ok (operation ()) with
  | Store_error error -> Error error
  | Sqlite3.SqliteError message | Sqlite3.Error message | Sqlite3.InternalError message ->
    Error (error_of_rc database ~context:message (Sqlite3.errcode database))
;;

let with_statement database sql operation =
  let statement = Sqlite3.prepare database sql in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize statement : Sqlite3.Rc.t))
    (fun () -> operation statement)
;;

let exec database ~context sql =
  Sqlite3.exec database sql |> raise_on_rc database ~context
;;

let rollback database = ignore (Sqlite3.exec database "ROLLBACK" : Sqlite3.Rc.t)

let with_transaction database operation =
  exec database ~context:"begin transaction" "BEGIN IMMEDIATE";
  try
    let value = operation () in
    exec database ~context:"commit transaction" "COMMIT";
    value
  with
  | error ->
    rollback database;
    raise error
;;

let query_single_int64 database ~context sql =
  with_statement database sql (fun statement ->
    match Sqlite3.step statement with
    | Sqlite3.Rc.ROW -> Sqlite3.column_int64 statement 0
    | rc ->
      raise_on_rc database ~context rc;
      raise (Store_error (Protocol.Storage_error (context ^ ": missing row"))))
;;

let read_schema_version database =
  query_single_int64 database ~context:"read schema version" "PRAGMA user_version"
  |> Int64.to_int
;;

let read_database_revision database =
  query_single_int64
    database
    ~context:"read database revision"
    "SELECT integer_value FROM metadata WHERE key = 'database_revision'"
;;

let migrate database =
  let version = read_schema_version database in
  if version > schema_version_number
  then raise (Store_error (Protocol.Unsupported_schema version));
  if version = 0
  then (
    try
      with_transaction database (fun () ->
        exec
          database
          ~context:"create todos table"
          "CREATE TABLE IF NOT EXISTS todos (id INTEGER PRIMARY KEY AUTOINCREMENT,title \
           TEXT NOT NULL,completed INTEGER NOT NULL CHECK (completed IN (0, 1)))";
        exec
          database
          ~context:"create applied mutations table"
          "CREATE TABLE IF NOT EXISTS applied_mutations (mutation_id TEXT PRIMARY \
           KEY,database_revision INTEGER NOT NULL)";
        exec
          database
          ~context:"create metadata table"
          "CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY,integer_value \
           INTEGER NOT NULL)";
        exec
          database
          ~context:"initialize database revision"
          "INSERT OR IGNORE INTO metadata(key, integer_value) VALUES \
           ('database_revision', 0)";
        exec database ~context:"set schema version" "PRAGMA user_version = 1")
    with
    | Store_error (Protocol.Busy as error) -> raise (Store_error error)
    | Store_error error ->
      raise (Store_error (Protocol.Migration_failed (Protocol.error_to_string error))))
;;

let valid_path path =
  (not (String.equal path ""))
  && String.length path <= maximum_path_bytes
  && (not (Filename.is_relative path))
  && (not (String.contains path '\000'))
  && String.is_valid_utf_8 path
;;

let open_ ~path =
  if not (valid_path path)
  then Error (Protocol.Invalid_path path)
  else (
    match Sqlite3.db_open ~mutex:`FULL path with
    | database ->
      let result =
        protect database (fun () ->
          Sqlite3.busy_timeout database busy_timeout_ms;
          exec database ~context:"enable foreign keys" "PRAGMA foreign_keys = ON";
          migrate database;
          let database_revision = read_database_revision database in
          { database = Some database
          ; schema_version = schema_version_number
          ; database_revision
          })
      in
      (match result with
       | Ok _ -> result
       | Error _ ->
         ignore (Sqlite3.db_close database : bool);
         result)
    | (exception Sqlite3.SqliteError message)
    | (exception Sqlite3.Error message)
    | (exception Sqlite3.InternalError message) -> Error (Protocol.Cannot_open message))
;;

let database_exn store =
  match store.database with
  | Some database -> database
  | None -> invalid_arg "SQLite store is closed"
;;

let schema_version store = store.schema_version
let database_revision store = store.database_revision

let list_todos store =
  let database = database_exn store in
  protect database (fun () ->
    let todos =
      with_statement
        database
        "SELECT id, title, completed FROM todos ORDER BY id DESC LIMIT 100"
        (fun statement ->
           let rec read rows =
             match Sqlite3.step statement with
             | Sqlite3.Rc.ROW ->
               let todo =
                 Protocol.
                   { id = Sqlite3.column_int64 statement 0
                   ; title = Sqlite3.column_text statement 1
                   ; completed = Sqlite3.column_bool statement 2
                   }
               in
               read (todo :: rows)
             | DONE -> List.rev rows
             | rc ->
               raise_on_rc database ~context:"list todos" rc;
               assert false
           in
           read [])
    in
    Protocol.{ todos; database_revision = store.database_revision })
;;

let existing_mutation_revision database mutation_id =
  with_statement
    database
    "SELECT database_revision FROM applied_mutations WHERE mutation_id = ?"
    (fun statement ->
       Sqlite3.bind_text statement 1 mutation_id
       |> raise_on_rc database ~context:"bind mutation id";
       match Sqlite3.step statement with
       | Sqlite3.Rc.ROW -> Some (Sqlite3.column_int64 statement 0)
       | DONE -> None
       | rc ->
         raise_on_rc database ~context:"find mutation" rc;
         assert false)
;;

let insert_mutation database ~mutation_id ~database_revision =
  with_statement
    database
    "INSERT INTO applied_mutations(mutation_id, database_revision) VALUES (?, ?)"
    (fun statement ->
       Sqlite3.bind_text statement 1 mutation_id
       |> raise_on_rc database ~context:"bind mutation id";
       Sqlite3.bind_int64 statement 2 database_revision
       |> raise_on_rc database ~context:"bind mutation revision";
       Sqlite3.step statement |> raise_on_rc database ~context:"record mutation")
;;

let increment_database_revision database next_revision =
  with_statement
    database
    "UPDATE metadata SET integer_value = ? WHERE key = 'database_revision'"
    (fun statement ->
       Sqlite3.bind_int64 statement 1 next_revision
       |> raise_on_rc database ~context:"bind database revision";
       Sqlite3.step statement
       |> raise_on_rc database ~context:"increment database revision")
;;

let mutate store ~mutation_id operation =
  let database = database_exn store in
  protect database (fun () ->
    match
      with_transaction database (fun () ->
        match existing_mutation_revision database mutation_id with
        | Some database_revision -> `Duplicate database_revision
        | None ->
          let next_revision = Int64.succ store.database_revision in
          operation database;
          insert_mutation database ~mutation_id ~database_revision:next_revision;
          increment_database_revision database next_revision;
          `Applied next_revision)
    with
    | `Duplicate database_revision -> Protocol.{ status = `Duplicate; database_revision }
    | `Applied database_revision ->
      store.database_revision <- database_revision;
      Protocol.{ status = `Applied; database_revision })
;;

let create_todo store ~mutation_id ~title =
  let title = String.trim title in
  if String.equal title ""
  then Error Protocol.Invalid_title
  else if String.length title > maximum_title_bytes
  then Error Protocol.Title_too_long
  else
    mutate store ~mutation_id (fun database ->
      with_statement
        database
        "INSERT INTO todos(title, completed) VALUES (?, 0)"
        (fun statement ->
           Sqlite3.bind_text statement 1 title
           |> raise_on_rc database ~context:"bind Todo title";
           Sqlite3.step statement |> raise_on_rc database ~context:"create Todo"))
;;

let set_completed store ~mutation_id ~todo_id ~completed =
  mutate store ~mutation_id (fun database ->
    with_statement
      database
      "UPDATE todos SET completed = ? WHERE id = ?"
      (fun statement ->
         Sqlite3.bind_bool statement 1 completed
         |> raise_on_rc database ~context:"bind Todo completion";
         Sqlite3.bind_int64 statement 2 todo_id
         |> raise_on_rc database ~context:"bind Todo id";
         Sqlite3.step statement |> raise_on_rc database ~context:"update Todo";
         if Sqlite3.changes database = 0
         then raise (Store_error (Protocol.Todo_not_found todo_id))))
;;

let close store =
  match store.database with
  | None -> ()
  | Some database ->
    if not (Sqlite3.db_close database)
    then failwith "SQLite store close failed because resources remain active";
    store.database <- None
;;
