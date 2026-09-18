module Protocol = Sqlite_worker_protocol
module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

type status =
  [ `Booting
  | `Loading
  | `Ready
  | `Busy
  | `Error
  | `Terminal
  ]

type state =
  { runtime_epoch : ID.Runtime.epoch
  ; worker_generation : ID.Worker.generation
  ; status : status
  ; todos : Protocol.todo list
  ; has_snapshot : bool
  ; open_count : int
  ; completed_count : int
  ; query_generation : int64
  ; latest_database_revision : int64
  ; last_push_sequence : ID.Worker.push_sequence
  ; title : string
  ; title_document_revision : ID.Text_input.document_revision
  ; title_local_revision : ID.Text_input.local_revision
  ; title_update_mode : Ui.Text_editing.update_mode
  ; mutation_namespace : string
  ; next_mutation : int64
  ; pending_label : string option
  ; error_message : string option
  ; sqlite_open_us : int64 option
  ; startup_timing : Protocol.startup_timing option
  ; pending_file_request : ID.Worker.request_id option
  ; file_operation : Protocol.file_operation option
  ; file_completed_bytes : int
  ; file_total_bytes : int
  ; file_checksum : int64 option
  ; file_status : string option
  }

let summarize todos =
  List.fold_left
    (fun (open_count, completed_count) (todo : Protocol.todo) ->
       if todo.completed
       then open_count, completed_count + 1
       else open_count + 1, completed_count)
    (0, 0)
    todos
;;

let fresh_mutation_namespace () =
  let random = Random.State.make_self_init () in
  Printf.sprintf
    "%08x%08x%08x%08x"
    (Random.State.bits random)
    (Random.State.bits random)
    (Random.State.bits random)
    (Random.State.bits random)
;;

let initial_state client =
  { runtime_epoch = Worker.runtime_epoch client
  ; worker_generation = Worker.worker_generation client
  ; status = `Booting
  ; todos = []
  ; has_snapshot = false
  ; open_count = 0
  ; completed_count = 0
  ; query_generation = 0L
  ; latest_database_revision = 0L
  ; last_push_sequence = ID.Worker.Push_sequence.zero
  ; title = ""
  ; title_document_revision = ID.Text_input.Document_revision.zero
  ; title_local_revision = ID.Text_input.Local_revision.zero
  ; title_update_mode = Ui.Text_editing.Ack
  ; mutation_namespace = fresh_mutation_namespace ()
  ; next_mutation = 1L
  ; pending_label = None
  ; error_message = None
  ; sqlite_open_us = None
  ; startup_timing = None
  ; pending_file_request = None
  ; file_operation = None
  ; file_completed_bytes = 0
  ; file_total_bytes = 0
  ; file_checksum = None
  ; file_status = None
  }
;;

let matching_envelope state ~runtime_epoch ~worker_generation =
  ID.Runtime.Epoch.equal state.runtime_epoch runtime_epoch
  && ID.Worker.Generation.equal state.worker_generation worker_generation
;;

let apply_snapshot state snapshot =
  let open_count, completed_count = summarize snapshot.Protocol.todos in
  { state with
    status = `Ready
  ; todos = snapshot.todos
  ; has_snapshot = true
  ; open_count
  ; completed_count
  ; latest_database_revision = snapshot.database_revision
  ; pending_label = None
  ; error_message = None
  }
;;

let is_pending_file state request_id =
  match state.pending_file_request with
  | Some pending -> ID.Worker.Request_id.equal pending request_id
  | None -> false
;;

let apply_response state request_id response =
  match response with
  | Protocol.Completed { query_generation; database_revision; payload } ->
    if
      Int64.compare query_generation state.query_generation < 0
      || Int64.compare database_revision state.latest_database_revision < 0
    then state
    else (
      let state =
        { state with latest_database_revision = database_revision; pending_label = None }
      in
      let state =
        match payload with
        | Protocol.Snapshot snapshot -> apply_snapshot state snapshot
        | Mutation _ ->
          { state with status = (if state.has_snapshot then `Ready else `Loading) }
        | File (File_written { total_bytes }) ->
          { state with
            status = (if state.has_snapshot then `Ready else `Loading)
          ; pending_file_request = None
          ; file_operation = None
          ; file_completed_bytes = total_bytes
          ; file_total_bytes = total_bytes
          ; file_checksum = None
          ; file_status = Some (Printf.sprintf "Wrote %d bytes" total_bytes)
          }
        | File (File_read { total_bytes; checksum }) ->
          { state with
            status = (if state.has_snapshot then `Ready else `Loading)
          ; pending_file_request = None
          ; file_operation = None
          ; file_completed_bytes = total_bytes
          ; file_total_bytes = total_bytes
          ; file_checksum = Some checksum
          ; file_status = Some (Printf.sprintf "Read %d bytes" total_bytes)
          }
      in
      state)
  | Protocol.Failed { error; _ } ->
    if is_pending_file state request_id
    then
      { state with
        pending_file_request = None
      ; file_operation = None
      ; file_status = Some (Protocol.error_to_string error)
      }
    else
      { state with
        status = `Error
      ; pending_label = None
      ; error_message = Some (Protocol.error_to_string error)
      }
;;

let apply_push state push_sequence payload =
  if ID.Worker.Push_sequence.compare push_sequence state.last_push_sequence <= 0
  then state
  else (
    let state = { state with last_push_sequence = push_sequence } in
    match payload with
    | Protocol.Ready { database_revision; sqlite_open_us; _ } ->
      { state with
        status = `Loading
      ; query_generation = Int64.succ state.query_generation
      ; latest_database_revision =
          Int64.max state.latest_database_revision database_revision
      ; sqlite_open_us = Some sqlite_open_us
      }
    | Store_changed snapshot ->
      if Int64.compare snapshot.database_revision state.latest_database_revision < 0
      then state
      else apply_snapshot state snapshot
    | Summary_changed summary ->
      if Int64.compare summary.database_revision state.latest_database_revision < 0
      then state
      else
        { state with
          open_count = summary.open_count
        ; completed_count = summary.completed_count
        ; latest_database_revision = summary.database_revision
        }
    | Startup_timing startup_timing ->
      { state with
        sqlite_open_us = Some startup_timing.sqlite_open_us
      ; startup_timing = Some startup_timing
      }
    | File_progress { operation; completed_bytes; total_bytes } ->
      if Option.is_none state.pending_file_request
      then state
      else
        { state with
          file_operation = Some operation
        ; file_completed_bytes = completed_bytes
        ; file_total_bytes = total_bytes
        }
    | Fatal error ->
      { state with
        status = `Error
      ; pending_label = None
      ; error_message = Some (Protocol.error_to_string error)
      })
;;

let apply_event state = function
  | Worker.Response { runtime_epoch; worker_generation; request_id; outcome }
    when matching_envelope state ~runtime_epoch ~worker_generation ->
    (match outcome with
     | Worker.Completed response -> apply_response state request_id response
     | Failed error ->
       if is_pending_file state request_id
       then
         { state with
           pending_file_request = None
         ; file_operation = None
         ; file_status = Some error
         }
       else
         { state with status = `Error; pending_label = None; error_message = Some error }
     | Cancelled when is_pending_file state request_id ->
       { state with
         pending_file_request = None
       ; file_operation = None
       ; file_status = Some "File operation cancelled"
       }
     | Cancelled | Shutdown -> { state with status = `Terminal; pending_label = None })
  | Push { runtime_epoch; worker_generation; push_sequence; payload; _ }
    when matching_envelope state ~runtime_epoch ~worker_generation ->
    apply_push state push_sequence payload
  | Terminal { runtime_epoch; worker_generation; error }
    when matching_envelope state ~runtime_epoch ~worker_generation ->
    { state with status = `Terminal; pending_label = None; error_message = Some error }
  | Response _ | Push _ | Terminal _ -> state
;;

let apply_send_result state = function
  | Worker.Accepted _ -> state
  | Full -> { state with status = `Busy; error_message = Some "Request queue is busy" }
  | Not_ready -> { state with status = `Busy; error_message = Some "Worker is not ready" }
  | Stopping ->
    { state with status = `Terminal; error_message = Some "Worker is stopping" }
;;

let refresh state =
  let query_generation = Int64.succ state.query_generation in
  ( { state with status = `Loading; query_generation; error_message = None }
  , Protocol.{ query_generation; operation = List_todos } )
;;

let send client set_state request =
  Bonsai.Effect.bind
    (Bonsai.Effect.of_thunk (fun () -> Worker.send client request))
    ~f:(fun result -> set_state (fun state -> apply_send_result state result))
;;

let send_file client set_state operation pending_label total_bytes request =
  Bonsai.Effect.bind
    (Bonsai.Effect.of_thunk (fun () -> Worker.send client request))
    ~f:(function
      | Worker.Accepted request_id ->
        set_state (fun state ->
          { state with
            pending_file_request = Some request_id
          ; file_operation = Some operation
          ; file_completed_bytes = 0
          ; file_total_bytes = total_bytes
          ; file_checksum = None
          ; file_status = Some pending_label
          })
      | result -> set_state (fun state -> apply_send_result state result))
;;

let mutation_id state kind =
  Printf.sprintf
    "%s-%Ld-%Ld-%s"
    state.mutation_namespace
    (ID.Runtime.Epoch.to_int64 state.runtime_epoch)
    state.next_mutation
    kind
;;

let text_value state =
  let cursor = Ui.Text_editing.Utf16.length state.title in
  let selection =
    Ui.Text_editing.Range.create ~text:state.title ~start_utf16:cursor ~end_utf16:cursor
  in
  Ui.Text_editing.Value.create ~text:state.title ~selection ()
;;

let status_text = function
  | `Booting -> "Booting"
  | `Loading -> "Loading"
  | `Ready -> "Ready"
  | `Busy -> "Busy"
  | `Error -> "Database error"
  | `Terminal -> "Terminal"
;;

let format_microseconds microseconds =
  Printf.sprintf "%.3f ms" (Int64.to_float microseconds /. 1_000.)
;;

let component client handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (initial_state client) graph in
  let registered = ref false in
  let event_subscription =
    Bonsai.Cont.map set_state ~f:(fun set_state ->
      if not !registered
      then (
        registered := true;
        Worker.on_event client (fun event ->
          match event with
          | Worker.Push { payload = Protocol.Ready _; _ } ->
            Bonsai.Effect.Many
              [ set_state (fun state -> apply_event state event)
              ; send
                  client
                  set_state
                  Protocol.{ query_generation = 1L; operation = List_todos }
              ]
          | Response _ | Push _ | Terminal _ ->
            set_state (fun state -> apply_event state event)));
      ())
  in
  let dependencies = Bonsai.Cont.both state set_state in
  let equal_dependencies (left_state, left_set) (right_state, right_set) =
    left_state = right_state && left_set == right_set
  in
  let edit =
    Driver.Handler.create
      handlers
      ~name:"sqlite-worker-edit-title"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (_state, set_state) -> function
      | Ui.Event.Payload.Text_edit edit ->
        set_state (fun state ->
          { state with
            title = edit.text
          ; title_document_revision =
              ID.Text_input.Document_revision.succ state.title_document_revision
          ; title_local_revision = edit.local_revision
          ; title_update_mode = Ui.Text_editing.Ack
          })
      | _ -> Bonsai.Effect.Ignore)
  in
  let no_op =
    Driver.Handler.create
      handlers
      ~name:"sqlite-worker-no-op"
      ~equal:Unit.equal
      (Bonsai.Cont.return ())
      ~f:(fun () _ -> Bonsai.Effect.Ignore)
  in
  let add =
    Driver.Handler.create
      handlers
      ~name:"sqlite-worker-add"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (state, set_state) _ ->
        if String.equal (String.trim state.title) ""
        then Bonsai.Effect.Ignore
        else (
          let request =
            Protocol.
              { query_generation = state.query_generation
              ; operation =
                  Create_todo
                    { mutation_id = mutation_id state "create"; title = state.title }
              }
          in
          Bonsai.Effect.Many
            [ set_state (fun current ->
                { current with
                  title = ""
                ; title_update_mode = Ui.Text_editing.Correction
                ; title_document_revision =
                    ID.Text_input.Document_revision.succ current.title_document_revision
                ; next_mutation = Int64.succ current.next_mutation
                ; pending_label = Some "Adding…"
                ; error_message = None
                })
            ; send client set_state request
            ]))
  in
  let refresh_handler =
    Driver.Handler.create
      handlers
      ~name:"sqlite-worker-refresh"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (state, set_state) _ ->
        let next, request = refresh state in
        Bonsai.Effect.Many
          [ set_state (fun _current -> next); send client set_state request ])
  in
  let write_file =
    Driver.Handler.create
      handlers
      ~name:"sqlite-worker-write-demo-file"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (state, set_state) _ ->
        if Option.is_some state.pending_file_request
        then Bonsai.Effect.Ignore
        else (
          let total_bytes = 4 * 1024 * 1024 in
          send_file
            client
            set_state
            Protocol.Writing
            "Writing demo file…"
            total_bytes
            Protocol.
              { query_generation = state.query_generation
              ; operation = Write_demo_file { total_bytes }
              }))
  in
  let read_file =
    Driver.Handler.create
      handlers
      ~name:"sqlite-worker-read-demo-file"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (state, set_state) _ ->
        if Option.is_some state.pending_file_request
        then Bonsai.Effect.Ignore
        else
          send_file
            client
            set_state
            Protocol.Reading
            "Reading demo file…"
            0
            Protocol.
              { query_generation = state.query_generation; operation = Read_demo_file })
  in
  let cancel_file =
    Driver.Handler.create
      handlers
      ~name:"sqlite-worker-cancel-demo-file"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (state, set_state) _ ->
        match state.pending_file_request with
        | None -> Bonsai.Effect.Ignore
        | Some request_id ->
          Bonsai.Effect.Many
            [ Bonsai.Effect.of_thunk (fun () -> Worker.cancel client ~request_id)
            ; set_state (fun current ->
                if is_pending_file current request_id
                then { current with file_status = Some "Cancelling file operation…" }
                else current)
            ])
  in
  let todos = Bonsai.Cont.map state ~f:(fun state -> state.todos) in
  let rows =
    Bonsai.Cont.assoc_list
      (module Core.Int64)
      todos
      ~get_key:(fun (todo : Protocol.todo) -> todo.id)
      ~f:(fun todo_id todo _graph ->
        let row_dependencies =
          Bonsai.Cont.map2 dependencies todo_id ~f:(fun dependencies todo_id ->
            dependencies, todo_id)
        in
        let equal_row_dependencies
              ((left_state, left_set), left_id)
              ((right_state, right_set), right_id)
          =
          left_state = right_state
          && left_set == right_set
          && Int64.equal left_id right_id
        in
        let toggle =
          Driver.Handler.create
            handlers
            ~name:"sqlite-worker-toggle"
            ~equal:equal_row_dependencies
            row_dependencies
            ~f:(fun ((state, set_state), todo_id) payload ->
              let completed =
                match payload with
                | Ui.Event.Payload.Bool completed -> Some completed
                | Unit ->
                  List.find_opt
                    (fun (todo : Protocol.todo) -> Int64.equal todo.id todo_id)
                    state.todos
                  |> Option.map (fun (todo : Protocol.todo) -> not todo.completed)
                | _ -> None
              in
              match completed with
              | Some completed ->
                let request =
                  Protocol.
                    { query_generation = state.query_generation
                    ; operation =
                        Set_completed
                          { mutation_id = mutation_id state "toggle"; todo_id; completed }
                    }
                in
                Bonsai.Effect.Many
                  [ set_state (fun current ->
                      { current with
                        next_mutation = Int64.succ current.next_mutation
                      ; pending_label = Some "Updating…"
                      ; error_message = None
                      })
                  ; send client set_state request
                  ]
              | None -> Bonsai.Effect.Ignore)
        in
        Bonsai.Cont.map2 todo toggle ~f:(fun todo toggle ->
          Ui.View.Weighted.row
            [ Ui.View.Weighted.fixed
                (Ui.View.button
                   ~on_press:toggle
                   ~child:(Ui.View.text (if todo.completed then "Reopen" else "Complete"))
                   ()
                 |> Ui.View.with_test_id
                      (Ui.Test_id.string (Printf.sprintf "todo-toggle-%Ld" todo.id)))
            ; Ui.View.Weighted.share (Ui.View.text todo.title)
            ]
          |> Ui.View.with_test_id
               (Ui.Test_id.string (Printf.sprintf "todo-row-%Ld" todo.id))))
      graph
  in
  let static =
    Bonsai.Cont.map3
      (Bonsai.Cont.both edit no_op)
      (Bonsai.Cont.both add refresh_handler)
      (Bonsai.Cont.map2
         write_file
         (Bonsai.Cont.both read_file cancel_file)
         ~f:(fun write_file (read_file, cancel_file) ->
           write_file, read_file, cancel_file))
      ~f:(fun (edit, no_op) (add, refresh_handler) handlers ->
        edit, no_op, add, refresh_handler, handlers)
  in
  let view =
    Bonsai.Cont.map2 state (Bonsai.Cont.both rows static) ~f:(fun state (rows, static) ->
      let edit, no_op, add, refresh_handler, (write_file, read_file, cancel_file) =
        static
      in
      let rows =
        match rows with
        | `Ok rows -> rows
        | `Duplicate_key todo_id ->
          invalid_arg (Printf.sprintf "Duplicate Todo ID %Ld" todo_id)
      in
      let status =
        Ui.View.text (status_text state.status)
        |> Ui.View.with_test_id (Ui.Test_id.string "worker-status")
      in
      let input =
        Ui.View.text_field
          ~label:"Todo title"
          ~session_id:(ID.Text_input.Session_id.of_int64 1L)
          ~document_revision:state.title_document_revision
          ~accepted_local_revision:state.title_local_revision
          ~update_mode:state.title_update_mode
          ~value:(text_value state)
          ~on_edit:edit
          ~on_submit:no_op
          ~on_focus_changed:no_op
          ()
        |> Ui.View.with_test_id (Ui.Test_id.string "todo-title-input")
      in
      let add =
        Ui.View.button
          ~style:Ui.View.Button_style.Prominent
          ~on_press:add
          ~child:(Ui.View.text "Add")
          ()
        |> Ui.View.with_test_id (Ui.Test_id.string "add-todo")
      in
      let refresh =
        Ui.View.button ~on_press:refresh_handler ~child:(Ui.View.text "Refresh") ()
        |> Ui.View.with_test_id (Ui.Test_id.string "refresh-todos")
      in
      let timing_value = function
        | None -> "pending"
        | Some value -> format_microseconds value
      in
      let timing_row label value =
        Ui.View.Weighted.row
          [ Ui.View.Weighted.share (Ui.View.text label)
          ; Ui.View.Weighted.fixed (Ui.View.text (timing_value value))
          ]
      in
      let initial_list_us, total_us =
        match state.startup_timing with
        | None -> None, None
        | Some timing -> Some timing.initial_list_us, Some timing.total_us
      in
      let startup_timing =
        Ui.View.column
          ~spacing:8.
          ~alignment:Ui.Layout.Horizontal_alignment.Leading
          [ Ui.View.text "Worker startup timings"
          ; timing_row "SQLite open + migrate" state.sqlite_open_us
          ; timing_row "Initial Todo query" initial_list_us
          ; timing_row "Worker service total" total_us
          ]
        |> Ui.View.with_test_id (Ui.Test_id.string "worker-startup-timing")
      in
      let file_pending = Option.is_some state.pending_file_request in
      let write_file =
        Ui.View.button
          ~style:Ui.View.Button_style.Prominent
          ~enabled:(not file_pending)
          ~on_press:write_file
          ~child:(Ui.View.text "Write 4 MiB demo file")
          ()
        |> Ui.View.with_test_id (Ui.Test_id.string "write-demo-file")
      in
      let read_file =
        Ui.View.button
          ~enabled:(not file_pending)
          ~on_press:read_file
          ~child:(Ui.View.text "Read demo file")
          ()
        |> Ui.View.with_test_id (Ui.Test_id.string "read-demo-file")
      in
      let cancel_file =
        Ui.View.button
          ~enabled:file_pending
          ~on_press:cancel_file
          ~child:(Ui.View.text "Cancel file operation")
          ()
        |> Ui.View.with_test_id (Ui.Test_id.string "cancel-file-operation")
      in
      let progress =
        if state.file_total_bytes <= 0
        then 0.
        else
          Float.min
            1.
            (Float.of_int state.file_completed_bytes
             /. Float.of_int state.file_total_bytes)
      in
      let checksum =
        match state.file_checksum with
        | None -> "Checksum: pending"
        | Some checksum -> Printf.sprintf "Checksum: %Ld" checksum
      in
      let operation =
        match state.file_operation with
        | None -> "Operation: idle"
        | Some Writing -> "Operation: writing"
        | Some Reading -> "Operation: reading"
      in
      let file_demo =
        Ui.View.column
          ~spacing:12.
          ~alignment:Ui.Layout.Horizontal_alignment.Leading
          [ Ui.View.text "Eio file demo"
          ; write_file
          ; read_file
          ; cancel_file
          ; Ui.View.progress ~style:Ui.View.Progress_style.Automatic ~value:progress ()
          ; Ui.View.text operation
          ; Ui.View.text
              (Printf.sprintf
                 "%d / %d bytes"
                 state.file_completed_bytes
                 state.file_total_bytes)
          ; Ui.View.text checksum
          ; Ui.View.text (Option.value state.file_status ~default:"No file operation yet")
          ]
        |> Ui.View.with_test_id (Ui.Test_id.string "file-demo-panel")
      in
      let messages =
        [ Option.map Ui.View.text state.pending_label
        ; Option.map Ui.View.text state.error_message
        ]
        |> List.filter_map (fun value -> value)
      in
      let panel title content =
        content
        |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 16.)
        |> Ui.View.background
             ~corner_radius:12.
             ~color:(Ui.Style.Color.argb ~alpha:18 ~red:128 ~green:128 ~blue:128)
        |> Ui.View.semantics
             ~properties:
               (Ui.Semantics.create
                  ~label:title
                  ~children:Ui.Semantics.Children.Contain
                  ())
      in
      let todos =
        Ui.View.column
          ~spacing:12.
          ~alignment:Ui.Layout.Horizontal_alignment.Leading
          ([ status
           ; Ui.View.text
               (Printf.sprintf
                  "%d open · %d completed"
                  state.open_count
                  state.completed_count)
           ; input
           ; Ui.View.row ~spacing:12. [ add; refresh ]
           ]
           @ messages
           @ rows)
        |> panel "Todos"
      in
      let content =
        Ui.View.column
          ~spacing:16.
          [ todos
          ; panel "Startup diagnostics" startup_timing
          ; panel "File operations" file_demo
          ]
        |> Ui.View.Scroll.vertical
        |> Ui.View.Viewport.Vertical.padding ~insets:(Ui.Layout.Edge_insets.all 16.)
        |> Ui.View.Viewport.Vertical.semantics
             ~properties:(Ui.Semantics.create ~children:Ui.Semantics.Children.Contain ())
      in
      Ui.View.Body.Vertical.create
        [ Ui.View.Body.Vertical.fixed
            (Ui.View.text
               ~style:
                 (Ui.Style.Text_style.create
                    ~font_size:24.
                    ~font_weight:Ui.Style.Font_weight.Bold
                    ())
               "SQLite Worker Todo"
             |> Ui.View.semantics ~properties:(Ui.Semantics.create ~heading_level:1 ())
             |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 16.))
        ; Ui.View.Body.Vertical.fill content
        ])
  in
  Bonsai.Cont.map2 event_subscription view ~f:(fun () view -> view)
;;

let create_app ~service =
  let theme = Ui.Theme.create ~tint:(Ui.Style.Color.rgb ~red:46 ~green:125 ~blue:50) () in
  App.create_with_worker
    ~name:"SQLite Worker Todo"
    ~decode_config:Sqlite_worker_config.decode
    ~service
    (fun client handlers graph ->
       Bonsai.Cont.map (component client handlers graph) ~f:(fun body ->
         App.View.create ~theme ~body))
;;

let app = create_app ~service:Sqlite_worker_service.service
