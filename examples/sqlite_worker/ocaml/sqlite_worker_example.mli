(** Worker-backed Todo application. *)

val create_app
  :  service:
       ( Sqlite_worker_config.t
         , Sqlite_worker_protocol.request
         , Sqlite_worker_protocol.response
         , Sqlite_worker_protocol.push )
         Worker.Service.t
  -> App.t

val app : App.t
