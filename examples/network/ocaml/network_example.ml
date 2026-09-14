module ID = Bonsai_swiftui_spec.Id
module Policy = Network_policy
module Protocol = Network_protocol
module Ui = Bonsai_swiftui_ui

type https_status =
  | Https_idle
  | Https_pending
  | Https_cancelling
  | Https_succeeded
  | Https_cancelled
  | Https_failed

type state =
  { runtime_epoch : ID.Runtime.epoch
  ; worker_generation : ID.Worker.generation
  ; https_status : https_status
  ; next_https_request_id : int
  ; active_https_request_id : int option
  ; pending_https_worker_id : ID.Worker.request_id option
  ; https_summary : Protocol.https_summary option
  ; https_error : string option
  ; websocket_generation : int
  ; websocket_state : Protocol.websocket_state
  ; websocket_error : string option
  ; message : string
  ; message_document_revision : ID.Text_input.document_revision
  ; message_local_revision : ID.Text_input.local_revision
  ; transcript : Policy.transcript_entry list
  }

let initial_state client =
  { runtime_epoch = Worker.runtime_epoch client
  ; worker_generation = Worker.worker_generation client
  ; https_status = Https_idle
  ; next_https_request_id = 1
  ; active_https_request_id = None
  ; pending_https_worker_id = None
  ; https_summary = None
  ; https_error = None
  ; websocket_generation = 0
  ; websocket_state = Protocol.Idle
  ; websocket_error = None
  ; message = ""
  ; message_document_revision = ID.Text_input.Document_revision.zero
  ; message_local_revision = ID.Text_input.Local_revision.zero
  ; transcript = []
  }
;;

let matching_envelope state ~runtime_epoch ~worker_generation =
  ID.Runtime.Epoch.equal state.runtime_epoch runtime_epoch
  && ID.Worker.Generation.equal state.worker_generation worker_generation
;;

let is_pending_https state worker_request_id =
  match state.pending_https_worker_id with
  | Some pending -> ID.Worker.Request_id.equal pending worker_request_id
  | None -> false
;;

let add_transcript state generation text =
  { state with transcript = Policy.add_transcript state.transcript { generation; text } }
;;

let apply_https_result state result =
  if state.active_https_request_id <> Some result.Protocol.request_id
  then state
  else (
    match result.outcome with
    | Ok summary ->
      { state with
        https_status = Https_succeeded
      ; active_https_request_id = None
      ; pending_https_worker_id = None
      ; https_summary = Some summary
      ; https_error = None
      }
    | Error error ->
      { state with
        https_status = Https_failed
      ; active_https_request_id = None
      ; pending_https_worker_id = None
      ; https_summary = None
      ; https_error = Some (Protocol.error_to_string error)
      })
;;

let apply_websocket_command state (result : Protocol.websocket_command_result) =
  if
    not
      (Policy.is_current_generation
         ~active:state.websocket_generation
         ~event:result.generation)
  then state
  else (
    match result.outcome with
    | Error error ->
      { state with
        websocket_state = Failed
      ; websocket_error = Some (Protocol.error_to_string error)
      }
    | Ok Connected ->
      { state with websocket_state = Connected_state; websocket_error = None }
    | Ok Sent -> state
    | Ok Disconnected_command ->
      { state with websocket_state = Closed; websocket_error = None })
;;

let apply_response state worker_request_id = function
  | Protocol.Https_result result when is_pending_https state worker_request_id ->
    apply_https_result state result
  | Https_result _ -> state
  | Websocket_command_result result -> apply_websocket_command state result
;;

let apply_push state = function
  | Protocol.Websocket_state_changed event ->
    if
      not
        (Policy.is_current_generation
           ~active:state.websocket_generation
           ~event:event.generation)
    then state
    else (
      let state =
        { state with
          websocket_state = event.state
        ; websocket_error = Option.map Protocol.error_to_string event.error
        }
      in
      let label =
        match event.state with
        | Idle -> "Idle"
        | Connecting -> "Connecting"
        | Connected_state -> "Connected"
        | Disconnecting -> "Disconnecting"
        | Closed -> "Closed"
        | Failed -> "Failed"
      in
      add_transcript state event.generation ("State: " ^ label))
  | Websocket_message_received event ->
    if
      not
        (Policy.is_current_generation
           ~active:state.websocket_generation
           ~event:event.generation)
    then state
    else (
      let text =
        match event.kind, event.message with
        | Text, Some message -> "Message: " ^ message
        | Text, None -> "Message: empty"
        | Unsupported_binary, _ -> "Unsupported binary message"
        | Unsupported_text, _ -> "Unsupported text message"
      in
      add_transcript state event.generation text)
;;

let internal_worker_error = "Network worker failed"

let apply_event state = function
  | Worker.Response { runtime_epoch; worker_generation; request_id; outcome }
    when matching_envelope state ~runtime_epoch ~worker_generation ->
    (match outcome with
     | Worker.Completed response -> apply_response state request_id response
     | Failed _ when is_pending_https state request_id ->
       { state with
         https_status = Https_failed
       ; active_https_request_id = None
       ; pending_https_worker_id = None
       ; https_summary = None
       ; https_error = Some internal_worker_error
       }
     | Cancelled when is_pending_https state request_id ->
       { state with
         https_status = Https_cancelled
       ; active_https_request_id = None
       ; pending_https_worker_id = None
       ; https_summary = None
       ; https_error = None
       }
     | Failed _ ->
       { state with
         websocket_state = Failed
       ; websocket_error = Some internal_worker_error
       }
     | Cancelled ->
       { state with
         websocket_state = Failed
       ; websocket_error = Some (Protocol.error_to_string Protocol.Cancelled)
       }
     | Shutdown ->
       { state with
         pending_https_worker_id = None
       ; websocket_state = Failed
       ; websocket_error = Some (Protocol.error_to_string Protocol.Shutting_down)
       })
  | Push { runtime_epoch; worker_generation; payload; _ }
    when matching_envelope state ~runtime_epoch ~worker_generation ->
    apply_push state payload
  | Terminal { runtime_epoch; worker_generation; error = _ }
    when matching_envelope state ~runtime_epoch ~worker_generation ->
    { state with
      pending_https_worker_id = None
    ; websocket_state = Failed
    ; websocket_error = Some internal_worker_error
    }
  | Response _ | Push _ | Terminal _ -> state
;;

let https_status_text = function
  | Https_idle -> "HTTPS: Idle"
  | Https_pending -> "HTTPS: Running"
  | Https_cancelling -> "HTTPS: Cancelling"
  | Https_succeeded -> "HTTPS: Complete"
  | Https_cancelled -> "HTTPS: Cancelled"
  | Https_failed -> "HTTPS: Failed"
;;

let websocket_status_text = function
  | Protocol.Idle -> "WebSocket: Idle"
  | Connecting -> "WebSocket: Connecting"
  | Connected_state -> "WebSocket: Connected"
  | Disconnecting -> "WebSocket: Disconnecting"
  | Closed -> "WebSocket: Closed"
  | Failed -> "WebSocket: Failed"
;;

let text_value state =
  let cursor = Ui.Text_editing.Utf16.length state.message in
  let selection =
    Ui.Text_editing.Range.create ~text:state.message ~start_utf16:cursor ~end_utf16:cursor
  in
  Ui.Text_editing.Value.create ~text:state.message ~selection ()
;;

let apply_https_send_result state application_request_id = function
  | Worker.Accepted worker_request_id ->
    { state with
      https_status = Https_pending
    ; next_https_request_id = application_request_id + 1
    ; active_https_request_id = Some application_request_id
    ; pending_https_worker_id = Some worker_request_id
    ; https_summary = None
    ; https_error = None
    }
  | Full ->
    { state with https_status = Https_failed; https_error = Some "Request queue is busy" }
  | Not_ready ->
    { state with https_status = Https_failed; https_error = Some "Worker is not ready" }
  | Stopping ->
    { state with https_status = Https_failed; https_error = Some "Worker is stopping" }
;;

let apply_websocket_send_result state generation pending_state = function
  | Worker.Accepted _ ->
    { state with
      websocket_generation = generation
    ; websocket_state = pending_state
    ; websocket_error = None
    }
  | Full ->
    { state with
      websocket_state = Failed
    ; websocket_error = Some "Request queue is busy"
    }
  | Not_ready ->
    { state with websocket_state = Failed; websocket_error = Some "Worker is not ready" }
  | Stopping ->
    { state with websocket_state = Failed; websocket_error = Some "Worker is stopping" }
;;

let component ~https_endpoint ~websocket_endpoint client handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (initial_state client) graph in
  let registered = ref false in
  let event_subscription =
    Bonsai.Cont.map set_state ~f:(fun set_state ->
      if not !registered
      then (
        registered := true;
        Worker.on_event client (fun event ->
          set_state (fun state -> apply_event state event)));
      ())
  in
  let dependencies = Bonsai.Cont.both state set_state in
  let equal_dependencies (left_state, left_set) (right_state, right_set) =
    left_state = right_state && left_set == right_set
  in
  let no_op =
    Driver.Handler.create
      handlers
      ~name:"network-no-op"
      ~equal:Unit.equal
      (Bonsai.Cont.return ())
      ~f:(fun () _ -> Bonsai.Effect.Ignore)
  in
  let run_https =
    Driver.Handler.create
      handlers
      ~name:"network-run-https"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (state, set_state) _ ->
        if Option.is_some state.pending_https_worker_id
        then Bonsai.Effect.Ignore
        else (
          let request_id = state.next_https_request_id in
          Bonsai.Effect.bind
            (Bonsai.Effect.of_thunk (fun () ->
               Worker.send
                 client
                 (Protocol.Https_get { request_id; uri = https_endpoint })))
            ~f:(fun result ->
              set_state (fun state -> apply_https_send_result state request_id result))))
  in
  let cancel_https =
    Driver.Handler.create
      handlers
      ~name:"network-cancel-https"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (state, set_state) _ ->
        match state.pending_https_worker_id with
        | None -> Bonsai.Effect.Ignore
        | Some request_id ->
          Bonsai.Effect.Many
            [ Bonsai.Effect.of_thunk (fun () -> Worker.cancel client ~request_id)
            ; set_state (fun state ->
                if is_pending_https state request_id
                then { state with https_status = Https_cancelling }
                else state)
            ])
  in
  let connect_websocket =
    Driver.Handler.create
      handlers
      ~name:"network-connect-websocket"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (state, set_state) _ ->
        match state.websocket_state with
        | Connecting | Connected_state | Disconnecting -> Bonsai.Effect.Ignore
        | Idle | Closed | Failed ->
          (match Policy.next_generation state.websocket_generation with
           | Error error ->
             set_state (fun state ->
               { state with
                 websocket_state = Failed
               ; websocket_error = Some (Protocol.error_to_string error)
               })
           | Ok generation ->
             Bonsai.Effect.bind
               (Bonsai.Effect.of_thunk (fun () ->
                  Worker.send
                    client
                    (Protocol.Websocket_connect { generation; uri = websocket_endpoint })))
               ~f:(fun result ->
                 set_state (fun state ->
                   apply_websocket_send_result state generation Connecting result))))
  in
  let send_websocket =
    Driver.Handler.create
      handlers
      ~name:"network-send-websocket"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (state, set_state) _ ->
        if state.websocket_state <> Connected_state || String.equal state.message ""
        then Bonsai.Effect.Ignore
        else
          Bonsai.Effect.bind
            (Bonsai.Effect.of_thunk (fun () ->
               Worker.send
                 client
                 (Protocol.Websocket_send
                    { generation = state.websocket_generation; message = state.message })))
            ~f:(function
              | Worker.Accepted _ -> Bonsai.Effect.return ()
              | Full ->
                set_state (fun state ->
                  { state with websocket_error = Some "Request queue is busy" })
              | Not_ready ->
                set_state (fun state ->
                  { state with websocket_error = Some "Worker is not ready" })
              | Stopping ->
                set_state (fun state ->
                  { state with websocket_error = Some "Worker is stopping" })))
  in
  let disconnect_websocket =
    Driver.Handler.create
      handlers
      ~name:"network-disconnect-websocket"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (state, set_state) _ ->
        if state.websocket_state <> Connected_state
        then Bonsai.Effect.Ignore
        else
          Bonsai.Effect.bind
            (Bonsai.Effect.of_thunk (fun () ->
               Worker.send
                 client
                 (Protocol.Websocket_disconnect
                    { generation = state.websocket_generation })))
            ~f:(fun result ->
              set_state (fun state ->
                apply_websocket_send_result
                  state
                  state.websocket_generation
                  Disconnecting
                  result)))
  in
  let edit_message =
    Driver.Handler.create
      handlers
      ~name:"network-edit-websocket-message"
      ~equal:equal_dependencies
      dependencies
      ~f:(fun (_state, set_state) -> function
      | Ui.Event.Payload.Text_edit edit ->
        set_state (fun state ->
          { state with
            message = edit.text
          ; message_document_revision =
              ID.Text_input.Document_revision.succ state.message_document_revision
          ; message_local_revision = edit.local_revision
          })
      | _ -> Bonsai.Effect.Ignore)
  in
  let handlers =
    Bonsai.Cont.map3
      (Bonsai.Cont.both run_https cancel_https)
      (Bonsai.Cont.both connect_websocket disconnect_websocket)
      (Bonsai.Cont.map2
         send_websocket
         (Bonsai.Cont.both edit_message no_op)
         ~f:(fun send_websocket (edit_message, no_op) ->
           send_websocket, edit_message, no_op))
      ~f:(fun https websocket message -> https, websocket, message)
  in
  let view =
    Bonsai.Cont.map2 state handlers ~f:(fun state handlers ->
      let ( (run_https, cancel_https)
          , (connect_websocket, disconnect_websocket)
          , (send_websocket, edit_message, no_op) )
        =
        handlers
      in
      let https_pending = Option.is_some state.pending_https_worker_id in
      let https_details =
        match state.https_summary with
        | None -> []
        | Some summary ->
          [ Ui.View.text (Printf.sprintf "Status: %d" summary.status_code)
          ; Ui.View.text
              ("Content-Type: "
               ^ Option.value summary.content_type ~default:"not provided")
          ; Ui.View.text (Printf.sprintf "Body: %d bytes" summary.body_bytes)
          ; Ui.View.text summary.preview
          ]
      in
      let heading text =
        Ui.View.text
          ~style:
            (Ui.Style.Text_style.create
               ~font_size:18.
               ~font_weight:Ui.Style.Font_weight.Semi_bold
               ())
          text
        |> Ui.View.semantics ~properties:(Ui.Semantics.create ~heading_level:2 ())
      in
      let panel label body =
        body
        |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 16.)
        |> Ui.View.background
             ~corner_radius:12.
             ~color:(Ui.Style.Color.argb ~alpha:18 ~red:128 ~green:128 ~blue:128)
        |> Ui.View.semantics
             ~properties:
               (Ui.Semantics.create ~label ~children:Ui.Semantics.Children.Contain ())
      in
      let https_panel =
        Ui.View.column
          ~spacing:12.
          ~alignment:Ui.Layout.Horizontal_alignment.Leading
          ([ heading "HTTPS GET"
           ; Ui.View.text https_endpoint
           ; Ui.View.text (https_status_text state.https_status)
           ; Ui.View.row
               ~spacing:12.
               [ Ui.View.button
                   ~style:Ui.View.Button_style.Prominent
                   ~enabled:(not https_pending)
                   ~on_press:run_https
                   ~child:(Ui.View.text "Run HTTPS GET")
                   ()
                 |> Ui.View.with_test_id (Ui.Test_id.string "https-run")
               ; Ui.View.button
                   ~enabled:https_pending
                   ~on_press:cancel_https
                   ~child:(Ui.View.text "Cancel")
                   ()
                 |> Ui.View.with_test_id (Ui.Test_id.string "https-cancel")
               ]
           ]
           @ https_details
           @ List.filter_map (Option.map Ui.View.text) [ state.https_error ])
        |> panel "HTTPS panel"
        |> Ui.View.with_test_id (Ui.Test_id.string "https-panel")
      in
      let connected = state.websocket_state = Connected_state in
      let message_input =
        Ui.View.text_field
          ~label:"WebSocket message"
          ~enabled:connected
          ~session_id:(ID.Text_input.Session_id.of_int64 1L)
          ~document_revision:state.message_document_revision
          ~accepted_local_revision:state.message_local_revision
          ~update_mode:Ui.Text_editing.Ack
          ~value:(text_value state)
          ~on_edit:edit_message
          ~on_submit:no_op
          ~on_focus_changed:no_op
          ()
        |> Ui.View.with_test_id (Ui.Test_id.string "websocket-message-input")
      in
      let connection_control =
        if connected
        then
          Ui.View.button
            ~on_press:disconnect_websocket
            ~child:(Ui.View.text "Disconnect")
            ()
          |> Ui.View.with_test_id (Ui.Test_id.string "websocket-disconnect")
        else
          Ui.View.button
            ~style:Ui.View.Button_style.Prominent
            ~enabled:
              (state.websocket_state <> Connecting
               && state.websocket_state <> Disconnecting)
            ~on_press:connect_websocket
            ~child:(Ui.View.text "Connect")
            ()
          |> Ui.View.with_test_id (Ui.Test_id.string "websocket-connect")
      in
      let transcript =
        List.map
          (fun (entry : Policy.transcript_entry) ->
             Ui.View.text entry.text
             |> Ui.View.with_test_id (Ui.Test_id.string "transcript-entry"))
          state.transcript
      in
      let websocket_panel =
        Ui.View.column
          ~spacing:12.
          ~alignment:Ui.Layout.Horizontal_alignment.Leading
          ([ heading "Secure WebSocket"
           ; Ui.View.text websocket_endpoint
           ; Ui.View.text (websocket_status_text state.websocket_state)
           ; connection_control
           ; message_input
           ; Ui.View.button
               ~style:Ui.View.Button_style.Prominent
               ~enabled:(connected && not (String.equal state.message ""))
               ~on_press:send_websocket
               ~child:(Ui.View.text "Send")
               ()
             |> Ui.View.with_test_id (Ui.Test_id.string "websocket-send")
           ]
           @ List.filter_map (Option.map Ui.View.text) [ state.websocket_error ]
           @ transcript)
        |> panel "WebSocket panel"
        |> Ui.View.with_test_id (Ui.Test_id.string "websocket-panel")
      in
      let content =
        Ui.View.column ~spacing:16. [ https_panel; websocket_panel ]
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
               "Secure Network Lab"
             |> Ui.View.semantics ~properties:(Ui.Semantics.create ~heading_level:1 ())
             |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 16.))
        ; Ui.View.Body.Vertical.fill content
        ])
  in
  Bonsai.Cont.map2 event_subscription view ~f:(fun () view -> view)
;;

let create ~https_endpoint ~websocket_endpoint ~service () =
  let theme = Ui.Theme.create ~tint:(Ui.Style.Color.rgb ~red:0 ~green:96 ~blue:100) () in
  App.create_with_worker
    ~name:"Secure Network Lab"
    ~decode_config:(fun _payload -> Ok ())
    ~service
    (fun client handlers graph ->
       Bonsai.Cont.map
         (component ~https_endpoint ~websocket_endpoint client handlers graph)
         ~f:(fun body -> App.View.create ~theme ~body))
;;

let app =
  create
    ~https_endpoint:"https://example.com/"
    ~websocket_endpoint:"wss://echo.websocket.org"
    ~service:Network_service.service
    ()
;;
