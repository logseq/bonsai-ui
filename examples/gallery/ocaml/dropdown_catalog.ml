module Ui = Bonsai_swiftui_ui
module V = Ui.View
module ID = Bonsai_swiftui_spec.Id

type choice =
  { id : int64
  ; title : string
  ; enabled : bool
  }

let choices =
  [ { id = -7L; title = "Inbox"; enabled = true }
  ; { id = 9L; title = "Archive"; enabled = true }
  ; { id = 13L; title = "中文😀"; enabled = true }
  ; { id = 17L; title = "Unavailable"; enabled = false }
  ]
;;

type content =
  | Items
  | Loading
  | Empty
  | Error

let empty_query =
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
  ; content : content
  ; multiple : bool
  ; single : int64 option
  ; selected : int64 list
  ; enabled : bool
  ; reject : bool
  }

let initial =
  { query = empty_query
  ; revision = ID.Text_input.Document_revision.of_int64 1L
  ; accepted = ID.Text_input.Local_revision.zero
  ; update_mode = Ui.Text_editing.Ack
  ; content = Items
  ; multiple = false
  ; single = None
  ; selected = []
  ; enabled = true
  ; reject = false
  }
;;

let visible state (choice : choice) =
  let query =
    String.lowercase_ascii (String.trim (Ui.Text_editing.Value.text state.query))
  in
  Base.String.is_substring (String.lowercase_ascii choice.title) ~substring:query
;;

let eligible state (choice : choice) =
  state.enabled
  && (not state.reject)
  && state.content = Items
  && choice.enabled
  && visible state choice
;;

let component handlers graph =
  let session_id = ID.Text_input.Session_id.of_int64 1937L in
  let state, set_state = Bonsai_v017.state ~equal:( = ) initial graph in
  let bind name update =
    Driver.Handler.create
      handlers
      ~name:("dropdown-" ^ name)
      ~equal:( == )
      set_state
      ~f:(fun set_state payload -> set_state (fun state -> update state payload))
  in
  let action name update = bind name (fun state _ -> update state) in
  let edit =
    bind "edit" (fun state -> function
      | Ui.Event.Payload.Text_edit edit
        when state.enabled
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
  let select =
    bind "single" (fun state -> function
      | Ui.Event.Payload.Int64 id when not state.multiple ->
        if List.exists (fun choice -> choice.id = id && eligible state choice) choices
        then { state with single = Some id }
        else state
      | _ -> state)
  in
  let memberships =
    List.map
      (fun choice ->
         bind
           ("member-" ^ Int64.to_string choice.id)
           (fun state -> function
             | Ui.Event.Payload.Bool value when state.multiple && eligible state choice ->
               let selected = List.filter (fun id -> id <> choice.id) state.selected in
               let selected = if value then choice.id :: selected else selected in
               { state with selected = List.sort_uniq Int64.compare selected }
             | _ -> state))
      choices
    |> Bonsai.Cont.all
  in
  let commands =
    [ action "single-mode" (fun state -> { state with multiple = false })
    ; action "multiple-mode" (fun state -> { state with multiple = true })
    ; action "loading" (fun state -> { state with content = Loading })
    ; action "items" (fun state -> { state with content = Items })
    ; action "empty" (fun state -> { state with content = Empty })
    ; action "error" (fun state -> { state with content = Error })
    ; action "clear-query" (fun state ->
        if not state.enabled
        then state
        else
          { state with
            query = empty_query
          ; revision = ID.Text_input.Document_revision.succ state.revision
          ; update_mode = Ui.Text_editing.Force_replace
          })
    ; action "reject" (fun state -> { state with reject = not state.reject })
    ; action "enabled" (fun state -> { state with enabled = not state.enabled })
    ; action "focus" (fun state -> state)
    ; action "submit" (fun state -> state)
    ]
    |> Bonsai.Cont.all
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both
       (Bonsai.Cont.both edit select)
       (Bonsai.Cont.both memberships commands))
    ~f:(fun state ((edit, select), (memberships, commands)) ->
      let button ?(enabled = true) index title =
        V.button
          ~key:(Ui.Key.string title)
          ~enabled
          ~on_press:(List.nth commands index)
          ~child:(V.text title)
          ()
      in
      let matches = List.filter (visible state) choices in
      let content =
        match state.content with
        | Loading -> V.column [ V.progress (); V.text "Loading choices" ]
        | Empty -> V.text "No choices available"
        | Error ->
          V.column [ V.text "Choices could not be loaded"; button 3 "Retry choices" ]
        | Items when matches = [] -> V.text "No matching choices"
        | Items when state.multiple ->
          List.map2 (fun choice on_changed -> choice, on_changed) choices memberships
          |> List.filter (fun (choice, _) -> visible state choice)
          |> List.map (fun (choice, on_changed) ->
            V.toggle
              ~key:(Ui.Key.string ("dropdown-choice-" ^ Int64.to_string choice.id))
              ~style:V.Toggle_style.Checkbox
              ~enabled:(state.enabled && choice.enabled)
              ~value:(List.mem choice.id state.selected)
              ~on_changed
              ~label:(V.text choice.title)
              ())
          |> V.column ~spacing:8.
        | Items ->
          let selected_id =
            Option.bind state.single (fun id ->
              if List.exists (fun choice -> choice.id = id) matches then Some id else None)
          in
          V.Picker.create
            ~key:(Ui.Key.string "dropdown-single")
            ~label:"Single dropdown"
            ~style:V.Picker.Menu
            ~enabled:state.enabled
            ~selected_id
            ~on_select:select
            (List.map
               (fun choice ->
                  V.Picker.option
                    ~id:choice.id
                    ~enabled:choice.enabled
                    ~label:(V.text choice.title)
                    ())
               matches)
            ()
      in
      V.column
        ~spacing:10.
        [ V.text "Searchable native choices"
        ; V.row [ button 0 "Use single selection"; button 1 "Use multiple selection" ]
        ; V.text_field
            ~key:(Ui.Key.string "dropdown-query")
            ~label:"Filter choices"
            ~prompt:"Search choices"
            ~submit_label:Ui.Text_editing.Submit_label.Search
            ~enabled:state.enabled
            ~session_id
            ~document_revision:state.revision
            ~accepted_local_revision:state.accepted
            ~update_mode:state.update_mode
            ~value:state.query
            ~on_edit:edit
            ~on_submit:(List.nth commands 10)
            ~on_focus_changed:(List.nth commands 9)
            ()
        ; button ~enabled:state.enabled 6 "Clear query"
        ; V.text ("Query: " ^ Ui.Text_editing.Value.text state.query)
        ; V.text ("Single: " ^ Option.fold ~none:"none" ~some:Int64.to_string state.single)
        ; V.text
            ("Multiple: "
             ^
             if state.selected = []
             then "none"
             else String.concat "," (List.map Int64.to_string state.selected))
        ; content
        ; V.row [ button 3 "Show items"; button 2 "Show loading" ]
        ; V.row [ button 4 "Show empty"; button 5 "Show error" ]
        ; button
            7
            (if state.reject
             then "Accept selection changes"
             else "Reject selection changes")
        ; button 8 (if state.enabled then "Disable choices" else "Enable choices")
        ]
      |> V.padding ~insets:(Ui.Layout.Edge_insets.all 12.))
;;
