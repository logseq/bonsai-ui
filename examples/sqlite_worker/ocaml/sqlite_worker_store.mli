(** A single-Domain SQLite store with explicit resource ownership. *)

type t

val open_ : path:string -> (t, Sqlite_worker_protocol.error) result
val schema_version : t -> int
val database_revision : t -> int64

val list_todos
  :  t
  -> (Sqlite_worker_protocol.snapshot, Sqlite_worker_protocol.error) result

val create_todo
  :  t
  -> mutation_id:string
  -> title:string
  -> (Sqlite_worker_protocol.mutation_result, Sqlite_worker_protocol.error) result

val set_completed
  :  t
  -> mutation_id:string
  -> todo_id:int64
  -> completed:bool
  -> (Sqlite_worker_protocol.mutation_result, Sqlite_worker_protocol.error) result

(** [close t] is idempotent and closes the connection synchronously. *)
val close : t -> unit
