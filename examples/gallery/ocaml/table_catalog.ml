module Ui = Bonsai_swiftui_ui
module V = Ui.View

type item =
  { id : int64
  ; title : string
  ; rank : int
  ; eligible : bool
  }

let items =
  [ { id = -7L; title = "First item"; rank = 30; eligible = true }
  ; { id = 9L; title = "Second item"; rank = 10; eligible = true }
  ; { id = 13L; title = "Unavailable item"; rank = 20; eligible = false }
  ]
;;

type state =
  { items : item list
  ; selected : int64 list
  ; sort : (int64 * bool) option
  ; ignored : bool
  ; reversed_columns : bool
  ; opened : int64 option
  ; opened_count : int
  ; selection_requests : int
  ; sort_requests : int
  }

let initial =
  { items
  ; selected = []
  ; sort = None
  ; ignored = false
  ; reversed_columns = false
  ; opened = None
  ; opened_count = 0
  ; selection_requests = 0
  ; sort_requests = 0
  }
;;

let ids values =
  if values = [] then "None" else String.concat "," (List.map Int64.to_string values)
;;

let component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) initial graph in
  let bind name update =
    Driver.Handler.create
      handlers
      ~name:("table-" ^ name)
      ~equal:( == )
      set_state
      ~f:(fun set_state payload -> set_state (fun state -> update state payload))
  in
  let command name update = bind name (fun state _ -> update state) in
  let selection =
    bind "selection" (fun state -> function
      | Ui.Event.Payload.Int64_bool { id; value } ->
        let state = { state with selection_requests = state.selection_requests + 1 } in
        if
          state.ignored
          || not
               (List.exists
                  (fun (item : item) -> item.id = id && item.eligible)
                  state.items)
        then state
        else
          { state with
            selected =
              (List.filter (( <> ) id) state.selected
               |> fun rest -> if value then List.sort Int64.compare (id :: rest) else rest
              )
          }
      | _ -> state)
  in
  let sorting =
    bind "sort" (fun state -> function
      | Ui.Event.Payload.Int64_bool { id; value } ->
        let state = { state with sort_requests = state.sort_requests + 1 } in
        if state.ignored || not (List.mem id [ 1L; 2L ])
        then state
        else (
          let compare (a : item) (b : item) =
            let result =
              if id = 1L
              then String.compare a.title b.title
              else Int.compare a.rank b.rank
            in
            if value then result else -result
          in
          { state with
            sort = Some (id, value)
          ; items = List.stable_sort compare state.items
          })
      | _ -> state)
  in
  let commands =
    Bonsai.Cont.all
      [ command "reject" (fun state -> { state with ignored = not state.ignored })
      ; command "all" (fun state ->
          if state.ignored
          then state
          else
            { state with
              selected =
                List.filter_map
                  (fun (item : item) -> if item.eligible then Some item.id else None)
                  state.items
                |> List.sort Int64.compare
            })
      ; command "clear" (fun state ->
          if state.ignored then state else { state with selected = [] })
      ; command "remove" (fun state ->
          { state with
            items = List.filter (fun (item : item) -> item.id <> -7L) state.items
          ; selected = List.filter (( <> ) (-7L)) state.selected
          })
      ; command "columns" (fun state ->
          { state with reversed_columns = not state.reversed_columns })
      ; command "empty" (fun state -> { state with items = []; selected = [] })
      ; command "reset" (fun _ -> initial)
      ]
  in
  let actions =
    List.map
      (fun (item : item) ->
         command
           ("open-" ^ Int64.to_string item.id)
           (fun state ->
              if List.exists (fun (current : item) -> current.id = item.id) state.items
              then
                { state with
                  opened = Some item.id
                ; opened_count = state.opened_count + 1
                }
              else state))
      items
    |> Bonsai.Cont.all
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both
       (Bonsai.Cont.both selection sorting)
       (Bonsai.Cont.both commands actions))
    ~f:(fun state ((selection, sorting), (commands, actions)) ->
      let button index title =
        V.button
          ~key:(Ui.Key.string title)
          ~on_press:(List.nth commands index)
          ~child:(V.text title)
          ()
      in
      let columns =
        [ V.Table.column ~id:1L ~title:"Name" ~sortable:true ()
        ; V.Table.column
            ~id:2L
            ~title:"Rank"
            ~sortable:true
            ~numeric:true
            ~help:"Ranks are ordered by the OCaml application."
            ~details:
              (V.button ~on_press:(List.nth actions 0) ~child:(V.text "Explain ranks") ())
            ()
        ; V.Table.column ~id:3L ~title:"Action" ()
        ]
      in
      let rows =
        List.map
          (fun (item : item) ->
             let index = if item.id = -7L then 0 else if item.id = 9L then 1 else 2 in
             let cells =
               [ V.text item.title
               ; V.text (string_of_int item.rank)
               ; V.button
                   ~on_press:(List.nth actions index)
                   ~child:(V.text ("Open " ^ item.title))
                   ()
               ]
             in
             V.Table.row
               ~id:item.id
               ~selection_enabled:item.eligible
               (if state.reversed_columns then List.rev cells else cells))
          state.items
      in
      let table =
        V.Table.create
          ~key:(Ui.Key.string "controlled-table")
          ?sort_column_id:(Option.map fst state.sort)
          ~sort_ascending:(Option.fold ~none:true ~some:snd state.sort)
          ~selected_row_ids:state.selected
          ~on_sort:sorting
          ~on_row_selected:selection
          ~columns:(if state.reversed_columns then List.rev columns else columns)
          ~rows
          ()
      in
      V.column
        ~spacing:6.
        [ V.text ("Selected IDs: " ^ ids state.selected)
        ; V.text ("Order: " ^ ids (List.map (fun (item : item) -> item.id) state.items))
        ; V.text
            ("Opened ID: " ^ Option.fold ~none:"None" ~some:Int64.to_string state.opened)
        ; V.text (Printf.sprintf "Opened count: %d" state.opened_count)
        ; V.text (Printf.sprintf "Selection requests: %d" state.selection_requests)
        ; V.text (Printf.sprintf "Sort requests: %d" state.sort_requests)
        ; V.text (if state.ignored then "Changes rejected" else "Changes accepted")
        ; V.text
            (if state.reversed_columns then "Columns reversed" else "Columns original")
        ; V.row
            [ button
                0
                (if state.ignored then "Accept table changes" else "Reject table changes")
            ; button 1 "Select all table rows"
            ]
        ; V.row [ button 2 "Clear table selection"; button 3 "Remove first table row" ]
        ; V.row
            [ button 4 "Reorder table columns"
            ; button 5 "Clear table rows"
            ; button 6 "Reset table"
            ]
        ; V.Body.with_size ~width:380. ~height:420. table
        ])
;;
