module Ui = Bonsai_swiftui_ui
module V = Ui.View
module ID = Bonsai_swiftui_spec.Id

type suggestion =
  { id : int64
  ; title : string
  ; enabled : bool
  }

let suggestions =
  [ { id = -7L; title = "Inbox"; enabled = true }
  ; { id = 9L; title = "Archive"; enabled = true }
  ; { id = 13L; title = "中文😀"; enabled = true }
  ; { id = 17L; title = "Unavailable"; enabled = false }
  ]
;;

let empty =
  Ui.Text_editing.Value.create
    ~text:""
    ~selection:(Ui.Text_editing.Range.create ~text:"" ~start_utf16:0 ~end_utf16:0)
    ()
;;

type state =
  { query : Ui.Text_editing.Value.t
  ; revision : ID.Text_input.document_revision
  ; accepted : ID.Text_input.local_revision
  ; update_mode : Ui.Text_editing.update_mode
  ; shown : bool
  ; enabled : bool
  ; read_only : bool
  ; reject_close : bool
  ; opened : int
  ; closed : int
  ; close_requests : int
  ; limits : int
  ; selected : int64 option
  ; submitted : string
  }

let initial =
  { query = empty
  ; revision = ID.Text_input.Document_revision.of_int64 1L
  ; accepted = ID.Text_input.Local_revision.zero
  ; update_mode = Ui.Text_editing.Ack
  ; shown = false
  ; enabled = true
  ; read_only = false
  ; reject_close = false
  ; opened = 0
  ; closed = 0
  ; close_requests = 0
  ; limits = 0
  ; selected = None
  ; submitted = ""
  }
;;

let visible state =
  let query =
    String.lowercase_ascii (String.trim (Ui.Text_editing.Value.text state.query))
  in
  List.filter
    (fun (item : suggestion) ->
       Base.String.is_substring (String.lowercase_ascii item.title) ~substring:query)
    suggestions
;;

let close state =
  if not state.shown
  then state
  else
    { state with
      close_requests = state.close_requests + 1
    ; shown = state.reject_close
    ; closed = (state.closed + if state.reject_close then 0 else 1)
    }
;;

let component ?(presentation = 0) handlers graph =
  let session_id =
    ID.Text_input.Session_id.of_int64 (Int64.of_int (930 + presentation))
  in
  let state, set_state = Bonsai_v017.state ~equal:( = ) initial graph in
  let bind name update =
    Driver.Handler.create
      handlers
      ~name:(Printf.sprintf "search-%d-%s" presentation name)
      ~equal:( == )
      set_state
      ~f:(fun set_state payload -> set_state (fun state -> update state payload))
  in
  let action name update = bind name (fun state _ -> update state) in
  let edits =
    bind "edit" (fun state -> function
      | Ui.Event.Payload.Text_edit edit
        when state.shown
             && state.enabled
             && (not state.read_only)
             && ID.Text_input.Session_id.equal edit.session_id session_id
             && ID.Text_input.Local_revision.compare edit.local_revision state.accepted
                > 0 ->
        let range (r : Ui.Event.Payload.text_selection) =
          Ui.Text_editing.Range.create
            ~text:edit.text
            ~start_utf16:r.start_utf16
            ~end_utf16:r.end_utf16
        in
        { state with
          query =
            Ui.Text_editing.Value.create
              ~text:edit.text
              ~selection:(range edit.selection)
              ?composing:(Option.map range edit.composing)
              ()
        ; revision = ID.Text_input.Document_revision.succ state.revision
        ; accepted = edit.local_revision
        ; update_mode = Ui.Text_editing.Ack
        }
      | _ -> state)
  in
  let submit =
    bind "submit" (fun state -> function
      | Ui.Event.Payload.Text text
        when state.shown && state.enabled && not state.read_only ->
        { state with submitted = text }
      | _ -> state)
  in
  let lifecycle = bind "focus" (fun state _ -> state) in
  let limit =
    action "limit" (fun state ->
      if state.shown && state.enabled
      then { state with limits = state.limits + 1 }
      else state)
  in
  let dismiss =
    bind "dismiss" (fun state -> function
      | Ui.Event.Payload.Bool false -> close state
      | _ -> state)
  in
  let commands =
    [ action "open" (fun state ->
        if state.shown || not state.enabled
        then state
        else { state with shown = true; opened = state.opened + 1 })
    ; action "close" close
    ; action "clear" (fun state ->
        if (not state.shown) || (not state.enabled) || state.read_only
        then state
        else
          { state with
            query = empty
          ; revision = ID.Text_input.Document_revision.succ state.revision
          ; update_mode = Ui.Text_editing.Force_replace
          })
    ; action "read-only" (fun state -> { state with read_only = not state.read_only })
    ; action "enabled" (fun state -> { state with enabled = not state.enabled })
    ; action "reject-close" (fun state ->
        { state with reject_close = not state.reject_close })
    ; action "path" (fun state -> state)
    ]
    |> Bonsai.Cont.all
  in
  let choices =
    List.map
      (fun (item : suggestion) ->
         action
           ("choice-" ^ Int64.to_string item.id)
           (fun state ->
              if
                state.shown
                && state.enabled
                && item.enabled
                && List.mem item (visible state)
              then
                { state with
                  selected = Some item.id
                ; shown = false
                ; closed = state.closed + 1
                }
              else state))
      suggestions
    |> Bonsai.Cont.all
  in
  let controls = Bonsai.Cont.all [ edits; submit; lifecycle; limit; dismiss ] in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both controls (Bonsai.Cont.both commands choices))
    ~f:(fun state (controls, (commands, choices)) ->
      let button ?(enabled = true) title index =
        V.button
          ~key:(Ui.Key.string title)
          ~enabled
          ~on_press:(List.nth commands index)
          ~child:(V.text title)
          ()
      in
      let status =
        V.column
          [ V.text (if state.shown then "Search: Open" else "Search: Closed")
          ; V.text (Printf.sprintf "Opened: %d" state.opened)
          ; V.text (Printf.sprintf "Closed: %d" state.closed)
          ; V.text (Printf.sprintf "Close requests: %d" state.close_requests)
          ; V.text (Printf.sprintf "Limits: %d" state.limits)
          ; V.text
              ("Selected: "
               ^ Option.fold ~none:"None" ~some:Int64.to_string state.selected)
          ; V.text ("Query: " ^ Ui.Text_editing.Value.text state.query)
          ; V.text ("Submitted: " ^ state.submitted)
          ]
      in
      let field =
        V.text_field
          ~key:(Ui.Key.string "query")
          ~label:"Search query"
          ~prompt:"Search mailboxes"
          ~submit_label:Ui.Text_editing.Submit_label.Search
          ~enabled:state.enabled
          ~read_only:state.read_only
          ~max_utf8_bytes:16
          ~session_id
          ~document_revision:state.revision
          ~accepted_local_revision:state.accepted
          ~update_mode:state.update_mode
          ~value:state.query
          ~on_edit:(List.nth controls 0)
          ~on_submit:(List.nth controls 1)
          ~on_focus_changed:(List.nth controls 2)
          ~on_limit_reached:(List.nth controls 3)
          ()
      in
      let choice_by_id =
        List.map2
          (fun (item : suggestion) handler -> item.id, handler)
          suggestions
          choices
      in
      let matches = visible state in
      let results =
        if matches = []
        then V.text "No search results"
        else
          V.column
            (List.map
               (fun (item : suggestion) ->
                  V.button
                    ~key:(Ui.Key.int64 item.id)
                    ~enabled:(state.enabled && item.enabled)
                    ~on_press:(List.assoc item.id choice_by_id)
                    ~child:(V.text ("Choose " ^ item.title))
                    ())
               matches)
      in
      let content =
        V.frame
          ~width:360.
          ~height:560.
          (V.column
             [ V.row
                 [ V.symbol ~name:"magnifyingglass" ()
                 ; V.frame ~width:220. field
                 ; button ~enabled:(state.enabled && not state.read_only) "Clear query" 2
                 ]
             ; results
             ; button "Close search" 1
             ; button
                 (if state.read_only
                  then "Make search editable"
                  else "Make search read-only")
                 3
             ; V.text
                 (if state.read_only then "Search is read-only" else "Search is editable")
             ; button
                 (if state.enabled then "Disable search input" else "Enable search input")
                 4
             ; V.text
                 (if state.enabled
                  then "Search input enabled"
                  else "Search input disabled")
             ; button
                 (if state.reject_close
                  then "Accept search close"
                  else "Reject search close")
                 5
             ; V.text
                 (if state.reject_close
                  then "Close rejection enabled"
                  else "Close rejection disabled")
             ])
      in
      let open_button = button ~enabled:state.enabled "Open search" 0 in
      let body =
        match presentation with
        | 0 ->
          V.column [ open_button; (if state.shown then content else V.empty ()); status ]
        | 1 ->
          V.column
            [ V.Popover.create
                ~presented:state.shown
                ~content
                ~on_presented_changed:(List.nth controls 4)
                open_button
            ; status
            ]
        | _ ->
          V.Sheet.full_screen
            ~presented:state.shown
            ~content
            ~on_presented_changed:(List.nth controls 4)
            (V.Toolbar.create
               ~items:
                 [ V.Toolbar.item
                     ~key:(Ui.Key.string "search-command")
                     ~placement:Primary_action
                     open_button
                 ]
               status)
      in
      V.Navigation_stack.create
        ~title:"Search catalog"
        ~path:[]
        ~on_path_change:(List.nth commands 6)
        (V.Body.static body))
;;
