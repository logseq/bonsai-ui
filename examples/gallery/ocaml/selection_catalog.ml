module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

type choice =
  { id : int64
  ; title : string
  ; icon : string
  ; enabled : bool
  }

let choices =
  [ { id = -7L; title = "Inbox"; icon = "tray"; enabled = true }
  ; { id = 9L; title = "Archive"; icon = "archivebox"; enabled = true }
  ; { id = 13L; title = "中文😀"; icon = "envelope"; enabled = true }
  ; { id = 11L; title = "Unavailable"; icon = "lock"; enabled = false }
  ]
;;

type content =
  | Ready
  | Loading
  | Empty
  | Failed

type presentation =
  | Wrapping
  | Scrolling
  | Menus

type state =
  { single : int64 option
  ; multiple : int64 list
  ; query : Ui.Text_editing.Value.t
  ; document_revision : ID.Text_input.document_revision
  ; accepted_local_revision : ID.Text_input.local_revision
  ; content : content
  ; presentation : presentation
  ; vertical : bool
  ; enabled : bool
  ; ignored : bool
  ; reversed : bool
  ; size : int
  ; actions : int
  ; last_action : string option
  }

let query_session = ID.Text_input.Session_id.of_int64 721L

let initial =
  { single = Some (-7L)
  ; multiple = [ -7L ]
  ; query =
      Ui.Text_editing.Value.create
        ~text:""
        ~selection:(Ui.Text_editing.Range.create ~text:"" ~start_utf16:0 ~end_utf16:0)
        ()
  ; document_revision = ID.Text_input.Document_revision.of_int64 1L
  ; accepted_local_revision = ID.Text_input.Local_revision.zero
  ; content = Ready
  ; presentation = Wrapping
  ; vertical = false
  ; enabled = true
  ; ignored = false
  ; reversed = false
  ; size = 2
  ; actions = 0
  ; last_action = None
  }
;;

let visible_choices state =
  let query =
    String.lowercase_ascii (String.trim (Ui.Text_editing.Value.text state.query))
  in
  let visible =
    List.filter
      (fun choice ->
         Base.String.is_substring (String.lowercase_ascii choice.title) ~substring:query)
      choices
  in
  if state.reversed then List.rev visible else visible
;;

let can_interact state id =
  state.enabled
  && state.content = Ready
  && List.exists (fun choice -> choice.id = id && choice.enabled) (visible_choices state)
;;

let set_multiple state id selected =
  if (not (can_interact state id)) || state.ignored
  then state
  else (
    let rest = List.filter (fun old -> old <> id) state.multiple in
    { state with
      multiple = (if selected then List.sort Int64.compare (id :: rest) else rest)
    })
;;

let invoke state id =
  if not (can_interact state id)
  then state
  else (
    let choice = List.find (fun choice -> choice.id = id) choices in
    { state with actions = state.actions + 1; last_action = Some choice.title })
;;

let label prefix choice =
  Ui.View.label
    ~title:(Ui.View.text (prefix ^ choice.title))
    ~icon:(Ui.View.symbol ~name:choice.icon ())
    ()
;;

let component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) initial graph in
  let bind name update =
    Driver.Handler.create
      handlers
      ~name:("selection-catalog-" ^ name)
      ~equal:( == )
      set_state
      ~f:(fun set_state payload -> set_state (fun state -> update state payload))
  in
  let action name update = bind name (fun state _ -> update state) in
  let single =
    bind "single" (fun state -> function
      | Ui.Event.Payload.Int64 id when can_interact state id && not state.ignored ->
        { state with single = Some id }
      | _ -> state)
  in
  let multiple =
    bind "multiple-menu" (fun state -> function
      | Ui.Event.Payload.Int64 id ->
        set_multiple state id (not (List.mem id state.multiple))
      | _ -> state)
  in
  let actions =
    bind "actions-menu" (fun state -> function
      | Ui.Event.Payload.Int64 id -> invoke state id
      | _ -> state)
  in
  let per_choice =
    List.map
      (fun choice ->
         let toggle =
           bind
             ("multiple-" ^ Int64.to_string choice.id)
             (fun state -> function
               | Ui.Event.Payload.Bool selected -> set_multiple state choice.id selected
               | _ -> state)
         in
         let press =
           action
             ("action-" ^ Int64.to_string choice.id)
             (fun state -> invoke state choice.id)
         in
         Bonsai.Cont.map2 toggle press ~f:(fun toggle press -> choice, toggle, press))
      choices
  in
  let per_choice =
    List.fold_right
      (fun choice rest ->
         Bonsai.Cont.map2 choice rest ~f:(fun choice rest -> choice :: rest))
      per_choice
      (Bonsai.Cont.return [])
  in
  let query =
    bind "query" (fun state -> function
      | Ui.Event.Payload.Text_edit edit
        when state.enabled
             && ID.Text_input.Session_id.equal edit.session_id query_session
             && ID.Text_input.Local_revision.compare
                  edit.local_revision
                  state.accepted_local_revision
                > 0 ->
        let range (value : Ui.Event.Payload.text_selection) =
          Ui.Text_editing.Range.create
            ~text:edit.text
            ~start_utf16:value.start_utf16
            ~end_utf16:value.end_utf16
        in
        { state with
          query =
            Ui.Text_editing.Value.create
              ~text:edit.text
              ~selection:(range edit.selection)
              ?composing:(Option.map range edit.composing)
              ()
        ; document_revision = ID.Text_input.Document_revision.succ state.document_revision
        ; accepted_local_revision = edit.local_revision
        }
      | _ -> state)
  in
  let noop = bind "field-lifecycle" (fun state _ -> state) in
  let controls =
    [ ("Show choices", fun state -> { state with content = Ready })
    ; ("Show loading", fun state -> { state with content = Loading })
    ; ("Show empty", fun state -> { state with content = Empty })
    ; ("Show error", fun state -> { state with content = Failed })
    ; ("Retry choices", fun state -> { state with content = Ready })
    ; ("Use wrapping", fun state -> { state with presentation = Wrapping })
    ; ("Use scrolling", fun state -> { state with presentation = Scrolling })
    ; ("Use menus", fun state -> { state with presentation = Menus })
    ; ("Enable", fun state -> { state with enabled = not state.enabled })
    ; ("Ignore", fun state -> { state with ignored = not state.ignored })
    ; ("Axis", fun state -> { state with vertical = not state.vertical })
    ; ("Reverse choices", fun state -> { state with reversed = not state.reversed })
    ; ("Clear selections", fun state -> { state with single = None; multiple = [] })
    ; ("Change control size", fun state -> { state with size = (state.size + 1) mod 5 })
    ]
    |> List.map (fun (title, update) ->
      Bonsai.Cont.map (action title update) ~f:(fun handler -> title, handler))
  in
  let controls =
    List.fold_right
      (fun control rest ->
         Bonsai.Cont.map2 control rest ~f:(fun control rest -> control :: rest))
      controls
      (Bonsai.Cont.return [])
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both
       per_choice
       (Bonsai.Cont.both
          controls
          (Bonsai.Cont.both
             single
             (Bonsai.Cont.both
                multiple
                (Bonsai.Cont.both actions (Bonsai.Cont.both query noop))))))
    ~f:
      (fun
        state (per_choice, (controls, (single, (multiple, (actions, (query, noop)))))) ->
      let control title = List.assoc title controls in
      let button title handler =
        Ui.View.button
          ~key:(Ui.Key.string title)
          ~on_press:handler
          ~child:(Ui.View.text title)
          ()
      in
      let visible = visible_choices state in
      let selected_names ids =
        let names =
          List.filter_map
            (fun choice -> if List.mem choice.id ids then Some choice.title else None)
            choices
        in
        if names = [] then "None" else String.concat ", " names
      in
      let sizes = [| Ui.View.Control_size.Mini; Small; Regular; Large; Extra_large |] in
      let size_names = [| "Mini"; "Small"; "Regular"; "Large"; "Extra large" |] in
      let group key children =
        let content =
          if state.vertical
          then Ui.View.column ~spacing:6. children
          else Ui.View.row ~spacing:6. children
        in
        match state.presentation, state.vertical with
        | Wrapping, false ->
          Ui.View.flow ~key:(Ui.Key.string key) ~spacing:8. ~line_spacing:8. children
        | Wrapping, true -> Ui.View.column ~key:(Ui.Key.string key) ~spacing:6. children
        | Scrolling, false ->
          Ui.View.Scroll.horizontal ~key:(Ui.Key.string key) content
          |> Ui.View.Viewport.Horizontal.with_width ~width:300.
          |> Ui.View.frame ~height:52.
        | Scrolling, true ->
          Ui.View.Scroll.vertical ~key:(Ui.Key.string key) content
          |> Ui.View.Viewport.Vertical.with_height ~height:150.
        | Menus, _ -> invalid_arg "menu presentation must use native Menu"
      in
      let content =
        match state.content with
        | Loading ->
          Ui.View.column [ Ui.View.progress (); Ui.View.text "Loading choices" ]
        | Empty -> Ui.View.text "No choices available"
        | Failed ->
          Ui.View.column
            [ Ui.View.text "Choices could not be loaded"
            ; button "Retry choices" (control "Retry choices")
            ]
        | Ready when visible = [] -> Ui.View.text "No matching choices"
        | Ready ->
          let selected_id =
            match state.single with
            | Some id when List.exists (fun choice -> choice.id = id) visible -> Some id
            | None | Some _ -> None
          in
          let picker =
            Ui.View.Picker.create
              ~key:(Ui.Key.string "single-picker")
              ~label:"Single choice"
              ~enabled:state.enabled
              ~selected_id
              ~on_select:single
              ~style:
                (if state.presentation = Menus
                 then Ui.View.Picker.Menu
                 else if state.vertical
                 then Ui.View.Picker.Inline
                 else Ui.View.Picker.Segmented)
              (List.map
                 (fun choice ->
                    Ui.View.Picker.option
                      ~id:choice.id
                      ~enabled:choice.enabled
                      ~label:(label "Single " choice)
                      ())
                 visible)
              ()
          in
          let per_choice =
            List.map
              (fun choice ->
                 List.find (fun (candidate, _, _) -> candidate.id = choice.id) per_choice)
              visible
          in
          let multiple =
            if state.presentation = Menus
            then
              Ui.View.Menu.create
                ~key:(Ui.Key.string "multiple-menu")
                ~enabled:state.enabled
                ~label:(Ui.View.text "Multiple choices")
                ~on_select:multiple
                (List.map
                   (fun choice ->
                      Ui.View.Menu.choice
                        ~id:choice.id
                        ~enabled:choice.enabled
                        ~label:(label "Multiple " choice)
                        ~selected:(List.mem choice.id state.multiple)
                        ())
                   visible)
            else
              group
                "multiple-group"
                (List.map
                   (fun (choice, on_changed, _) ->
                      Ui.View.toggle
                        ~key:(Ui.Key.int64 choice.id)
                        ~style:Ui.View.Toggle_style.Button
                        ~enabled:(state.enabled && choice.enabled)
                        ~value:(List.mem choice.id state.multiple)
                        ~label:(label "Multiple " choice)
                        ~on_changed
                        ())
                   per_choice)
          in
          let actions =
            if state.presentation = Menus
            then
              Ui.View.Menu.create
                ~key:(Ui.Key.string "actions-menu")
                ~enabled:state.enabled
                ~label:(Ui.View.text "Actions")
                ~on_select:actions
                (List.map
                   (fun choice ->
                      Ui.View.Menu.action
                        ~id:choice.id
                        ~enabled:choice.enabled
                        ~label:(label "Open " choice)
                        ())
                   visible)
            else
              group
                "action-group"
                (List.map
                   (fun (choice, _, on_press) ->
                      Ui.View.button
                        ~key:(Ui.Key.int64 choice.id)
                        ~style:Ui.View.Button_style.Bordered
                        ~enabled:(state.enabled && choice.enabled)
                        ~child:(label "Open " choice)
                        ~on_press
                        ())
                   per_choice)
          in
          Ui.View.column ~spacing:10. [ picker; multiple; actions ]
      in
      Ui.View.column
        ~spacing:10.
        ~alignment:Ui.Layout.Horizontal_alignment.Leading
        [ Ui.View.text "Searchable choices and action groups"
        ; Ui.View.text_field
            ~key:(Ui.Key.string "selection-query")
            ~label:"Find choices"
            ~prompt:"Search choices"
            ~submit_label:Ui.Text_editing.Submit_label.Search
            ~enabled:state.enabled
            ~session_id:query_session
            ~document_revision:state.document_revision
            ~accepted_local_revision:state.accepted_local_revision
            ~update_mode:Ui.Text_editing.Ack
            ~value:state.query
            ~on_edit:query
            ~on_submit:noop
            ~on_focus_changed:noop
            ()
        ; Ui.View.control_size ~size:sizes.(state.size) content
        ; Ui.View.text ("Selected single: " ^ selected_names (Option.to_list state.single))
        ; Ui.View.text ("Selected multiple: " ^ selected_names state.multiple)
        ; Ui.View.text
            (Printf.sprintf
               "Actions: %d (%s)"
               state.actions
               (Option.value state.last_action ~default:"None"))
        ; Ui.View.text ("Layout: " ^ if state.vertical then "Vertical" else "Horizontal")
        ; Ui.View.text ("Control size: " ^ size_names.(state.size))
        ; Ui.View.flow
            ~spacing:8.
            ~line_spacing:8.
            (List.map
               (fun title -> button title (control title))
               [ "Show choices"; "Show loading"; "Show empty"; "Show error" ])
        ; Ui.View.flow
            ~spacing:8.
            ~line_spacing:8.
            (List.map
               (fun title -> button title (control title))
               [ "Use wrapping"; "Use scrolling"; "Use menus" ])
        ; Ui.View.flow
            ~spacing:8.
            ~line_spacing:8.
            [ button
                (if state.enabled then "Disable catalog" else "Enable catalog")
                (control "Enable")
            ; button
                (if state.ignored
                 then "Accept selection changes"
                 else "Ignore selection changes")
                (control "Ignore")
            ; button
                (if state.vertical then "Use horizontal layout" else "Use vertical layout")
                (control "Axis")
            ]
        ; Ui.View.flow
            ~spacing:8.
            ~line_spacing:8.
            (List.map
               (fun title -> button title (control title))
               [ "Reverse choices"; "Clear selections"; "Change control size" ])
        ])
;;
