module Ui = Bonsai_swiftui_ui
module V = Ui.View

type state =
  { token : int64
  ; phase : V.Refresh.request_state
  ; show : int64 option
  ; requests : int
  ; first : int
  ; last : int
  ; position : int64 option
  }

let component ?(kind = 0) handlers graph =
  let catalog =
    V.Collection.Catalog.create ~keys:(List.init 100 Ui.Key.int) ~default_extent:40. ()
  in
  let state, set_state =
    Bonsai_v017.state
      ~equal:( = )
      { token = 1L
      ; phase = Ready
      ; show = None
      ; requests = 0
      ; first = 0
      ; last = 0
      ; position = Some 0L
      }
      graph
  in
  let bind name f =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_state
      ~f:(fun set_state payload -> set_state (f payload))
  in
  let request =
    bind "refresh-request" (fun payload state ->
      match payload with
      | Ui.Event.Payload.Int64 token when token = state.token && state.phase = Ready ->
        { state with phase = Pending; requests = state.requests + 1 }
      | _ -> state)
  in
  let complete =
    bind "refresh-complete" (fun _ state -> { state with phase = Completed })
  in
  let next =
    bind "refresh-next" (fun _ state ->
      { state with token = Int64.succ state.token; phase = Ready; show = None })
  in
  let show =
    bind "refresh-show" (fun _ state ->
      { state with show = Some (Int64.succ (Option.value state.show ~default:0L)) })
  in
  let range =
    bind "refresh-range" (fun payload state ->
      match V.Collection.visible_range_of_payload payload with
      | None -> state
      | Some range ->
        let window =
          V.Collection.Window.create
            ~catalog
            ~visible_first_index:(Int64.to_int range.first_index)
            ~visible_last_exclusive:(Int64.to_int range.last_exclusive)
        in
        { state with first = window.first_index; last = window.last_exclusive })
  in
  let position =
    bind "refresh-position" (fun payload state ->
      match payload with
      | Ui.Event.Payload.Int64 position -> { state with position = Some position }
      | _ -> state)
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.all [ request; complete; next; show; range; position ])
    ~f:(fun state bindings ->
      let row index =
        V.frame ~height:40. (V.text (Printf.sprintf "Refresh row %d" index))
      in
      let viewport =
        match kind with
        | 0 -> V.Scroll.vertical (V.column ~spacing:0. (List.init 100 row))
        | 1 ->
          V.Scroll_sections.vertical
            ~spacing:0.
            [ V.Scroll_sections.section
                ~key:(Ui.Key.int 0)
                (List.init 100 (fun index ->
                   V.Keyed.create ~key:(Ui.Key.int index) (row index)))
            ]
        | 2 ->
          V.Collection.vertical
            ~catalog
            ~first_index:state.first
            ~items:
              (List.init (state.last - state.first) (fun i ->
                 let index = state.first + i in
                 V.Keyed.create ~key:(Ui.Key.int index) (row index)))
            ~on_visible_range:(List.nth bindings 4)
            ()
        | _ ->
          V.Scroll_targets.vertical
            ~position:state.position
            ~on_position_changed:(List.nth bindings 5)
            (List.init 100 (fun index ->
               V.Scroll_targets.item ~id:(Int64.of_int index) (row index)))
      in
      let viewport =
        V.Refresh.vertical
          ~request_token:state.token
          ~request_state:state.phase
          ?show_token:state.show
          ~on_request:(List.nth bindings 0)
          viewport
      in
      let button name index =
        V.button ~on_press:(List.nth bindings index) ~child:(V.text name) ()
      in
      V.Body.Vertical.create
        [ V.Body.Vertical.fixed
            (V.column
               [ V.text (Printf.sprintf "Requests: %d" state.requests)
               ; V.text
                   ("State: "
                    ^
                    match state.phase with
                    | Ready -> "ready"
                    | Pending -> "pending"
                    | Completed -> "completed")
               ; button "Complete request" 1
               ; button "Next request" 2
               ; button "Programmatic refresh" 3
               ])
        ; V.Body.Vertical.fill viewport
        ])
;;
