(** Immutable messages shared by the SQLite Worker Domain and domain 0. *)

type todo =
  { id : int64
  ; title : string
  ; completed : bool
  }

type snapshot =
  { todos : todo list
  ; database_revision : int64
  }

type mutation_status =
  [ `Applied
  | `Duplicate
  ]

type mutation_result =
  { status : mutation_status
  ; database_revision : int64
  }

type error =
  | Invalid_title
  | Title_too_long
  | Invalid_path of string
  | Unsupported_schema of int
  | Busy
  | Full
  | Read_only
  | Cannot_open of string
  | Corrupt of string
  | Todo_not_found of int64
  | Migration_failed of string
  | Storage_error of string
  | File_unavailable
  | Invalid_file_size of int
  | File_error of string

val error_to_string : error -> string

type operation =
  | List_todos
  | Create_todo of
      { mutation_id : string
      ; title : string
      }
  | Set_completed of
      { mutation_id : string
      ; todo_id : int64
      ; completed : bool
      }
  | Write_demo_file of { total_bytes : int }
  | Read_demo_file

type request =
  { query_generation : int64
  ; operation : operation
  }

type response_payload =
  | Snapshot of snapshot
  | Mutation of mutation_result
  | File of file_response

and file_response =
  | File_written of { total_bytes : int }
  | File_read of
      { total_bytes : int
      ; checksum : int64
      }

type response =
  | Completed of
      { query_generation : int64
      ; database_revision : int64
      ; payload : response_payload
      }
  | Failed of
      { query_generation : int64
      ; error : error
      }

type summary =
  { database_revision : int64
  ; open_count : int
  ; completed_count : int
  }

type startup_timing =
  { sqlite_open_us : int64
  ; initial_list_us : int64
  ; total_us : int64
  }

type push =
  | Ready of
      { schema_version : int
      ; database_revision : int64
      ; sqlite_open_us : int64
      }
  | Store_changed of snapshot
  | Summary_changed of summary
  | Startup_timing of startup_timing
  | Fatal of error
  | File_progress of
      { operation : file_operation
      ; completed_bytes : int
      ; total_bytes : int
      }

and file_operation =
  | Writing
  | Reading

module Topic : sig
  val ready : Bonsai_swiftui_spec.Id.Worker.push_topic
  val store : Bonsai_swiftui_spec.Id.Worker.push_topic
  val summary : Bonsai_swiftui_spec.Id.Worker.push_topic
  val fatal : Bonsai_swiftui_spec.Id.Worker.push_topic
  val startup_timing : Bonsai_swiftui_spec.Id.Worker.push_topic
  val file_progress : Bonsai_swiftui_spec.Id.Worker.push_topic
  val count : int
end
