module Ui = Bonsai_swiftui_ui
module V = Ui.View

type item =
  | Header
  | Fixed of int
  | Interlude
  | Varied of int
  | Footer

type state =
  { header : bool
  ; large : bool
  ; expanded : bool
  ; swapped : bool
  ; empty : bool
  ; first : int
  ; last : int
  ; actions : int
  }

let initial =
  { header = true
  ; large = false
  ; expanded = false
  ; swapped = false
  ; empty = false
  ; first = 0
  ; last = 0
  ; actions = 0
  }
;;

let key = function
  | Header -> Ui.Key.string "mixed-header"
  | Fixed index -> Ui.Key.string (Printf.sprintf "fixed:%d" index)
  | Interlude -> Ui.Key.string "mixed-interlude"
  | Varied index -> Ui.Key.string (Printf.sprintf "varied:%d" index)
  | Footer -> Ui.Key.string "mixed-footer"
;;

let label = function
  | Header -> "Mixed header"
  | Fixed index -> Printf.sprintf "Fixed %d" index
  | Interlude -> "Between groups"
  | Varied index -> Printf.sprintf "Varied %d" index
  | Footer -> "Mixed footer"
;;

let component ?(horizontal = false) handlers graph =
  let scale = if horizontal then 2. else 1. in
  let cached = ref None in
  let layout state =
    let signature =
      state.header, state.large, state.expanded, state.swapped, state.empty
    in
    match !cached with
    | Some (previous, result) when previous = signature -> result
    | _ ->
      let rows =
        if state.empty
        then []
        else (
          let fixed = List.init 3000 (fun index -> Fixed index) in
          let varied = List.init 7000 (fun index -> Varied index) in
          (if state.header then [ Header ] else [])
          @ (if state.swapped
             then varied @ (Interlude :: fixed)
             else fixed @ (Interlude :: varied))
          @ [ Footer ])
      in
      let extent = function
        | Header -> (if state.large then 200. else 120.) *. scale
        | Fixed _ -> 40. *. scale
        | Interlude -> 60. *. scale
        | Varied 10 when state.expanded -> 180. *. scale
        | Varied _ -> 60. *. scale
        | Footer -> 80. *. scale
      in
      let overrides =
        List.mapi (fun index item -> { V.Collection.index; extent = extent item }) rows
        |> List.filter (fun (value : V.Collection.extent) -> value.extent <> 40. *. scale)
      in
      let catalog =
        V.Collection.Catalog.create
          ~keys:(List.map key rows)
          ~default_extent:(40. *. scale)
          ~overrides
          ~overscan:3
          ~expand_duration_ms:180
          ~collapse_duration_ms:120
          ()
      in
      let rows = Array.of_list rows in
      let result = catalog, rows in
      cached := Some (signature, result);
      result
  in
  let relocate state update =
    let _, old_rows = layout state in
    let next = update state in
    let _, next_rows = layout next in
    let positions = Hashtbl.create (Array.length next_rows) in
    Array.iteri (fun index item -> Hashtbl.add positions (key item) index) next_rows;
    let first =
      if state.first < Array.length old_rows
      then
        Option.value (Hashtbl.find_opt positions (key old_rows.(state.first))) ~default:0
      else 0
    in
    { next with
      first
    ; last = min (Array.length next_rows) (first + state.last - state.first)
    }
  in
  let state, set_state = Bonsai_v017.state ~equal:( = ) initial graph in
  let command name update =
    Driver.Handler.create
      handlers
      ~name:("mixed-" ^ name)
      ~equal:( == )
      set_state
      ~f:(fun set_state _ -> set_state (fun state -> relocate state update))
  in
  let commands =
    Bonsai.Cont.all
      [ command "expand" (fun state -> { state with expanded = not state.expanded })
      ; command "resize" (fun state -> { state with large = not state.large })
      ; command "remove-header" (fun state -> { state with header = false })
      ; command "swap" (fun state -> { state with swapped = not state.swapped })
      ; command "clear" (fun state -> { state with empty = true })
      ; command "reset" (fun _ -> initial)
      ; command "header-action" (fun state -> { state with actions = state.actions + 1 })
      ; command "footer-action" (fun state ->
          { state with actions = state.actions + 100 })
      ]
  in
  let visible =
    Driver.Handler.create
      handlers
      ~name:"mixed-visible"
      ~equal:( == )
      set_state
      ~f:(fun set_state payload ->
        match V.Collection.visible_range_of_payload payload with
        | None -> Bonsai.Effect.Ignore
        | Some range ->
          set_state (fun state ->
            let _, rows = layout state in
            let bound value =
              Int64.to_int (Int64.min (Int64.of_int (Array.length rows)) value)
            in
            { state with
              first = bound range.first_index
            ; last = bound range.last_exclusive
            }))
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both commands visible)
    ~f:(fun state (commands, on_visible_range) ->
      let catalog, rows = layout state in
      let window =
        V.Collection.Window.create
          ~catalog
          ~visible_first_index:state.first
          ~visible_last_exclusive:state.last
      in
      let button index title =
        V.button
          ~key:(Ui.Key.string title)
          ~on_press:(List.nth commands index)
          ~child:(V.text title)
          ()
      in
      let controls =
        V.column
          ~spacing:8.
          [ V.text (Printf.sprintf "Mixed actions: %d" state.actions)
          ; button 0 "Expand mixed row"
          ; button 1 "Resize mixed header"
          ; button 2 "Remove mixed header"
          ; button 3 "Swap mixed groups"
          ; button 4 "Clear mixed content"
          ; button 5 "Reset mixed content"
          ]
      in
      let items =
        List.init (window.last_exclusive - window.first_index) (fun offset ->
          let item = rows.(window.first_index + offset) in
          let content =
            match item with
            | Header ->
              V.group_box ~label:(V.text (label item)) (button 6 "Header action")
            | Footer ->
              V.group_box ~label:(V.text (label item)) (button 7 "Footer action")
            | Interlude -> V.column [ V.divider (); V.text (label item) ]
            | Fixed _ | Varied _ -> V.text (label item)
          in
          V.padding ~insets:(Ui.Layout.Edge_insets.all 8.) content
          |> V.Keyed.create ~key:(key item))
      in
      if horizontal
      then (
        let viewport =
          V.Collection.horizontal
            ~key:(Ui.Key.string "mixed-collection")
            ~catalog
            ~first_index:window.first_index
            ~items
            ~on_visible_range
            ()
        in
        V.Body.Horizontal.create
          [ V.Body.Horizontal.fixed controls; V.Body.Horizontal.fill viewport ])
      else (
        let viewport =
          V.Collection.vertical
            ~key:(Ui.Key.string "mixed-collection")
            ~catalog
            ~first_index:window.first_index
            ~items
            ~on_visible_range
            ()
        in
        V.Body.Vertical.create
          [ V.Body.Vertical.fixed controls; V.Body.Vertical.fill viewport ]))
;;
