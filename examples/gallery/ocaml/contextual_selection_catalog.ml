module Ui = Bonsai_swiftui_ui
module V = Ui.View

type item =
  { id : int64
  ; title : string
  ; enabled : bool
  }

let items =
  [ { id = -7L; title = "First item"; enabled = true }
  ; { id = 9L; title = "Second item"; enabled = true }
  ; { id = 13L; title = "Unavailable item"; enabled = false }
  ]
;;

type state =
  { items : item list
  ; selected : int64 list
  ; archived : int64 list
  ; enabled : bool
  ; ignored : bool
  }

let initial = { items; selected = []; archived = []; enabled = true; ignored = false }

let eligible state id =
  state.enabled
  && List.exists (fun (item : item) -> item.id = id && item.enabled) state.items
;;

let selected state id value =
  if state.ignored || not (eligible state id)
  then state
  else (
    let remaining = List.filter (( <> ) id) state.selected in
    { state with
      selected = (if value then List.sort Int64.compare (id :: remaining) else remaining)
    })
;;

let ids values =
  if values = [] then "None" else String.concat "," (List.map Int64.to_string values)
;;

let component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) initial graph in
  let bind name update =
    Driver.Handler.create
      handlers
      ~name:("contextual-selection-" ^ name)
      ~equal:( == )
      set_state
      ~f:(fun set_state payload -> set_state (fun state -> update state payload))
  in
  let action name update = bind name (fun state _ -> update state) in
  let toggles =
    List.map
      (fun (item : item) ->
         bind (Int64.to_string item.id) (fun state -> function
           | Ui.Event.Payload.Bool value -> selected state item.id value
           | _ -> state))
      items
    |> Bonsai.Cont.all
  in
  let commands =
    [ action "all" (fun state ->
        if (not state.enabled) || state.ignored
        then state
        else
          { state with
            selected =
              List.filter_map
                (fun (item : item) -> if item.enabled then Some item.id else None)
                state.items
              |> List.sort Int64.compare
          })
    ; action "clear" (fun state ->
        if (not state.enabled) || state.ignored
        then state
        else { state with selected = [] })
    ; action "archive" (fun state ->
        if (not state.enabled) || state.selected = []
        then state
        else
          { state with
            items =
              List.filter
                (fun (item : item) -> not (List.mem item.id state.selected))
                state.items
          ; archived = state.selected
          ; selected = []
          })
    ; action "reverse" (fun state -> { state with items = List.rev state.items })
    ; action "ignore" (fun state -> { state with ignored = not state.ignored })
    ; action "enable" (fun state -> { state with enabled = not state.enabled })
    ; action "remove" (fun state ->
        { state with
          items = List.filter (fun (item : item) -> item.id <> -7L) state.items
        ; selected = List.filter (( <> ) (-7L)) state.selected
        })
    ; action "reset" (fun _ -> initial)
    ; action "path" (fun state -> state)
    ]
    |> Bonsai.Cont.all
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both toggles commands)
    ~f:(fun state (toggles, commands) ->
      let button ?(enabled = true) title index =
        V.button
          ~key:(Ui.Key.string title)
          ~enabled
          ~on_press:(List.nth commands index)
          ~child:(V.text title)
          ()
      in
      let title =
        if state.selected = []
        then "Choose items"
        else Printf.sprintf "%d selected" (List.length state.selected)
      in
      let toolbar_item key placement content =
        V.Toolbar.item ~key:(Ui.Key.string key) ~placement content
      in
      let toolbar =
        toolbar_item "selection-status" Principal (V.text title)
        ::
        (if state.selected = []
         then []
         else
           [ toolbar_item
               "selection-all"
               Primary_action
               (button ~enabled:state.enabled "Select all items" 0)
           ; toolbar_item
               "selection-clear"
               Cancellation_action
               (button ~enabled:state.enabled "Clear selection" 1)
           ; toolbar_item
               "selection-archive"
               Primary_action
               (button ~enabled:state.enabled "Archive selected" 2)
           ])
      in
      let toggle_by_id =
        List.map2 (fun (item : item) handler -> item.id, handler) items toggles
      in
      let rows =
        List.map
          (fun (item : item) ->
             let checked = List.mem item.id state.selected in
             V.toggle
               ~key:(Ui.Key.int64 item.id)
               ~value:checked
               ~enabled:(eligible state item.id)
               ~style:V.Toggle_style.Button
               ~on_changed:(List.assoc item.id toggle_by_id)
               ~label:
                 (V.label
                    ~title:(V.text item.title)
                    ~icon:
                      (V.symbol
                         ~name:(if checked then "checkmark.circle.fill" else "circle")
                         ())
                    ())
               ())
          state.items
      in
      V.Navigation_stack.create
        ~title:"Selection catalog"
        ~path:[]
        ~on_path_change:(List.nth commands 8)
        (V.Body.static
           (V.Toolbar.create
              ~key:(Ui.Key.string "contextual-toolbar")
              ~items:toolbar
              (V.column
                 [ V.text ("Selected IDs: " ^ ids state.selected)
                 ; V.text ("Archived IDs: " ^ ids state.archived)
                 ; V.column ~key:(Ui.Key.string "items") rows
                 ; button "Reverse items" 3
                 ; button
                     (if state.ignored
                      then "Accept selection changes"
                      else "Reject selection changes")
                     4
                 ; button
                     (if state.enabled then "Disable selection" else "Enable selection")
                     5
                 ; button "Remove first item" 6
                 ; button "Reset items" 7
                 ]))))
;;
