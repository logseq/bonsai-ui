(** Worker Domain service that exclusively owns the SQLite store. *)

type 'persistence persistence_probe =
  { open_ : Sqlite_worker_config.t -> ('persistence, string) result
  ; close : 'persistence -> unit
  }

val create_with_persistence_probe
  :  'persistence persistence_probe
  -> ( Sqlite_worker_config.t
       , Sqlite_worker_protocol.request
       , Sqlite_worker_protocol.response
       , Sqlite_worker_protocol.push )
       Worker.Service.t

val service
  : ( Sqlite_worker_config.t
      , Sqlite_worker_protocol.request
      , Sqlite_worker_protocol.response
      , Sqlite_worker_protocol.push )
      Worker.Service.t
