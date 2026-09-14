module Ui = Bonsai_swiftui_ui
module V = Ui.View

type state =
  { initial : int
  ; count : int
  ; first : int
  ; last : int
  ; reported_first : int option
  }

let component ?(kind = 0) ?(horizontal = false) ?(initial = 0) handlers graph =
  let catalogs = Hashtbl.create 2 in
  let catalog count =
    match Hashtbl.find_opt catalogs count with
    | Some catalog -> catalog
    | None ->
      let catalog =
        V.Collection.Catalog.create
          ~keys:(List.init count Ui.Key.int)
          ~default_extent:40.
          ~overrides:[ { V.Collection.index = 2; extent = 80. } ]
          ~overscan:4
          ()
      in
      Hashtbl.add catalogs count catalog;
      catalog
  in
  let state, set_state =
    Bonsai_v017.state
      ~equal:( = )
      { initial
      ; count = (if kind = 2 then 10000 else 100)
      ; first = 0
      ; last = 0
      ; reported_first = None
      }
      graph
  in
  let bind name f =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_state
      ~f:(fun set_state payload ->
        match f payload with
        | None -> Bonsai.Effect.Ignore
        | Some update -> set_state update)
  in
  let change =
    bind "change-initial-scroll" (fun _ ->
      Some (fun state -> { state with initial = (if state.initial = 0 then 1 else 0) }))
  in
  let append =
    bind "append-initial-scroll" (fun _ ->
      Some (fun state -> { state with count = state.count + 20 }))
  in
  let range =
    bind "initial-scroll-window" (function
      | Ui.Event.Payload.Visible_range range ->
        Some
          (fun state ->
            let window =
              V.Collection.Window.create
                ~catalog:(catalog state.count)
                ~visible_first_index:(Int64.to_int range.first_index)
                ~visible_last_exclusive:(Int64.to_int range.last_exclusive)
            in
            { state with
              first = window.first_index
            ; last = window.last_exclusive
            ; reported_first =
                (match state.reported_first with
                 | Some _ as value -> value
                 | None -> Some (Int64.to_int range.first_index))
            })
      | _ -> None)
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.all [ change; append; range ])
    ~f:(fun state handlers ->
      let initial_anchor =
        if state.initial = 0 then V.Scroll_anchor.Start else V.Scroll_anchor.End
      in
      let initial_position =
        match state.initial with
        | 0 -> V.Collection.Initial_position.Start
        | 1 -> V.Collection.Initial_position.End
        | _ -> V.Collection.Initial_position.Item (Ui.Key.int 7500)
      in
      let row i =
        let extent = if kind = 2 && i = 2 then 80. else 40. in
        let view = V.text (Printf.sprintf "Item %d" i) in
        if horizontal
        then V.frame ~width:extent ~max_height:Ui.Layout.Frame_limit.Fill view
        else V.frame ~height:extent ~max_width:Ui.Layout.Frame_limit.Fill view
      in
      let keyed i = V.Keyed.create ~key:(Ui.Key.int i) (row i) in
      let rows () = List.init state.count row in
      let sections () =
        [ V.Scroll_sections.section
            ~key:(Ui.Key.string "rows")
            (List.init state.count keyed)
        ]
      in
      let items () =
        List.init (state.last - state.first) (fun i -> keyed (state.first + i))
      in
      let controls =
        V.column
          [ V.text (Printf.sprintf "Initial configuration: %d" state.initial)
          ; V.text
              ("First visible: "
               ^ Option.fold ~none:"None" ~some:string_of_int state.reported_first)
          ; V.button
              ~on_press:(List.nth handlers 0)
              ~child:(V.text "Change initial position")
              ()
          ; V.button ~on_press:(List.nth handlers 1) ~child:(V.text "Append content") ()
          ]
      in
      let on_visible_range = List.nth handlers 2 in
      if horizontal
      then (
        let viewport =
          match kind with
          | 0 -> V.Scroll.horizontal ~initial_anchor (V.row ~spacing:0. (rows ()))
          | 1 -> V.Scroll_sections.horizontal ~initial_anchor (sections ())
          | 2 ->
            V.Collection.horizontal
              ~initial_position
              ~catalog:(catalog state.count)
              ~first_index:state.first
              ~items:(items ())
              ~on_visible_range
              ()
          | _ -> invalid_arg "Initial scroll kind"
        in
        V.Body.Horizontal.create
          [ V.Body.Horizontal.fill viewport
          ; V.Body.Horizontal.fixed (V.frame ~width:200. controls)
          ])
      else (
        let viewport =
          match kind with
          | 0 -> V.Scroll.vertical ~initial_anchor (V.column ~spacing:0. (rows ()))
          | 1 -> V.Scroll_sections.vertical ~initial_anchor (sections ())
          | 2 ->
            V.Collection.vertical
              ~initial_position
              ~catalog:(catalog state.count)
              ~first_index:state.first
              ~items:(items ())
              ~on_visible_range
              ()
          | _ -> invalid_arg "Initial scroll kind"
        in
        V.Body.Vertical.create
          [ V.Body.Vertical.fill viewport; V.Body.Vertical.fixed controls ]))
;;
