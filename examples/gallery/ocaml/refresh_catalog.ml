module Ui = Bonsai_swiftui_ui
module V = Ui.View

type state =
  { token : int64
  ; phase : V.Refresh.request_state
  ; show : int64 option
  ; requests : int
  }

let component handlers graph =
  let state, set_state =
    Bonsai_v017.state
      ~equal:( = )
      { token = 1L; phase = Ready; show = None; requests = 0 }
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
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.all [ request; complete; next; show ])
    ~f:(fun state bindings ->
      let row index =
        V.frame ~height:40. (V.text (Printf.sprintf "Refresh row %d" index))
      in
      let viewport =
        V.Native_list.vertical
          [ V.Native_list.section
              ~key:(Ui.Key.string "refresh-rows")
              (List.init 100 (fun index ->
                 V.Native_list.row ~key:(Ui.Key.int index) (row index)))
          ]
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
