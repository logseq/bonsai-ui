module ID = Bonsai_swiftui_spec.Id

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

let error_to_string = function
  | Invalid_title -> "Todo title must not be empty"
  | Title_too_long -> "Todo title must not exceed 512 UTF-8 bytes"
  | Invalid_path path -> Printf.sprintf "Invalid database path: %S" path
  | Unsupported_schema version ->
    Printf.sprintf "Unsupported database schema version: %d" version
  | Busy -> "Database is busy"
  | Full -> "Database is full"
  | Read_only -> "Database is read-only"
  | Cannot_open message -> Printf.sprintf "Cannot open database: %s" message
  | Corrupt message -> Printf.sprintf "Database is corrupt: %s" message
  | Todo_not_found todo_id -> Printf.sprintf "Todo %Ld does not exist" todo_id
  | Migration_failed message -> Printf.sprintf "Database migration failed: %s" message
  | Storage_error message -> Printf.sprintf "Database error: %s" message
  | File_unavailable -> "Demo file storage is unavailable"
  | Invalid_file_size size -> Printf.sprintf "Invalid demo file size: %d bytes" size
  | File_error message -> Printf.sprintf "Demo file error: %s" message
;;

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

module Topic = struct
  let ready = ID.Worker.Push_topic.of_int 0
  let store = ID.Worker.Push_topic.of_int 1
  let summary = ID.Worker.Push_topic.of_int 2
  let fatal = ID.Worker.Push_topic.of_int 3
  let startup_timing = ID.Worker.Push_topic.of_int 4
  let file_progress = ID.Worker.Push_topic.of_int 5
  let count = 6
end
