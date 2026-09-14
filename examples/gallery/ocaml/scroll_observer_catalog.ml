module Ui = Bonsai_swiftui_ui
module V = Ui.View

type state =
  { enabled : bool
  ; pixels : float
  ; travel : float
  ; position : int64 option
  ; first : int
  ; last : int
  }

let component ?(kind = 0) ?(horizontal = false) handlers graph =
  let catalog =
    V.Collection.Catalog.create
      ~keys:(List.init 100 Ui.Key.int)
      ~default_extent:40.
      ~overscan:4
      ()
  in
  let state, set_state =
    Bonsai_v017.state
      ~equal:( = )
      { enabled = true
      ; pixels = 0.
      ; travel = 0.
      ; position = Some 0L
      ; first = 0
      ; last = 0
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
  let scroll =
    bind "observe-scroll" (function
      | Ui.Event.Payload.Scroll { pixels; delta } ->
        Some (fun state -> { state with pixels; travel = state.travel +. delta })
      | _ -> None)
  in
  let toggle =
    bind "toggle-scroll-observer" (fun _ ->
      Some (fun state -> { state with enabled = not state.enabled }))
  in
  let position =
    bind "observe-scroll-position" (function
      | Ui.Event.Payload.Int64 position ->
        Some (fun state -> { state with position = Some position })
      | _ -> None)
  in
  let range =
    bind "observe-scroll-window" (function
      | Ui.Event.Payload.Visible_range range ->
        let window =
          V.Collection.Window.create
            ~catalog
            ~visible_first_index:(Int64.to_int range.first_index)
            ~visible_last_exclusive:(Int64.to_int range.last_exclusive)
        in
        Some
          (fun state ->
            { state with first = window.first_index; last = window.last_exclusive })
      | _ -> None)
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.all [ scroll; toggle; position; range ])
    ~f:(fun state bindings ->
      let on_scroll = if state.enabled then Some (List.nth bindings 0) else None in
      let on_position_changed = List.nth bindings 2 in
      let on_visible_range = List.nth bindings 3 in
      let row i =
        let view = V.text (Printf.sprintf "Item %d" i) in
        if horizontal
        then V.frame ~width:40. ~max_height:Ui.Layout.Frame_limit.Fill view
        else V.frame ~height:40. ~max_width:Ui.Layout.Frame_limit.Fill view
      in
      let keyed i = V.Keyed.create ~key:(Ui.Key.int i) (row i) in
      let controls =
        V.column
          [ V.text
              (Printf.sprintf "Observed: %.0f; travel: %.0f" state.pixels state.travel)
          ; V.button
              ~on_press:(List.nth bindings 1)
              ~child:
                (V.text
                   (if state.enabled
                    then "Disable notifications"
                    else "Enable notifications"))
              ()
          ]
      in
      let items = List.init 100 Fun.id in
      let sections () =
        [ V.Scroll_sections.section ~key:(Ui.Key.string "items") (List.map keyed items) ]
      in
      let targets () =
        List.map (fun i -> V.Scroll_targets.item ~id:(Int64.of_int i) (row i)) items
      in
      let window () =
        List.init (state.last - state.first) (fun i -> keyed (state.first + i))
      in
      if horizontal
      then (
        let viewport =
          match kind with
          | 0 -> V.Scroll.horizontal ?on_scroll (V.row ~spacing:0. (List.map row items))
          | 1 -> V.Scroll_sections.horizontal ?on_scroll (sections ())
          | 2 ->
            V.Collection.horizontal
              ?on_scroll
              ~catalog
              ~first_index:state.first
              ~items:(window ())
              ~on_visible_range
              ()
          | 3 ->
            V.Scroll_targets.horizontal
              ?on_scroll
              ~fraction:0.1
              ~snapping:false
              ~position:state.position
              ~on_position_changed
              (targets ())
          | _ -> invalid_arg "Scroll observer kind"
        in
        V.Body.Horizontal.create
          [ V.Body.Horizontal.fill viewport
          ; V.Body.Horizontal.fixed (V.frame ~width:240. controls)
          ])
      else (
        let viewport =
          match kind with
          | 0 -> V.Scroll.vertical ?on_scroll (V.column ~spacing:0. (List.map row items))
          | 1 -> V.Scroll_sections.vertical ?on_scroll (sections ())
          | 2 ->
            V.Collection.vertical
              ?on_scroll
              ~catalog
              ~first_index:state.first
              ~items:(window ())
              ~on_visible_range
              ()
          | 3 ->
            V.Scroll_targets.vertical
              ?on_scroll
              ~fraction:0.1
              ~snapping:false
              ~position:state.position
              ~on_position_changed
              (targets ())
          | _ -> invalid_arg "Scroll observer kind"
        in
        V.Body.Vertical.create
          [ V.Body.Vertical.fill viewport; V.Body.Vertical.fixed controls ]))
;;

let nested_component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (0., 0.) graph in
  let scroll =
    Driver.Handler.create
      handlers
      ~name:"observe-outer-scroll"
      ~equal:( == )
      set_state
      ~f:(fun set_state -> function
      | Ui.Event.Payload.Scroll { pixels; delta } ->
        set_state (fun (_, travel) -> pixels, travel +. delta)
      | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2
    (Bonsai.Cont.both state scroll)
    (component ~horizontal:true handlers graph)
    ~f:(fun ((pixels, travel), on_scroll) inner ->
      V.Body.Vertical.create
        [ V.Body.Vertical.fill
            (V.Scroll.vertical
               ~on_scroll
               (V.column
                  ~spacing:0.
                  [ V.Body.with_size ~width:600. ~height:180. inner
                  ; V.frame ~height:1200. (V.text "Outer content")
                  ]))
        ; V.Body.Vertical.fixed
            (V.text (Printf.sprintf "Outer: %.0f; travel: %.0f" pixels travel))
        ])
;;
