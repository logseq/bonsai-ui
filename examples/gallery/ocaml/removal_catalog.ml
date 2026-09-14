module Ui = Bonsai_swiftui_ui
module V = Ui.View

type item =
  { id : int
  ; token : int64
  ; phase : V.Removal.request_state
  }

type state =
  { items : item list
  ; requests : int
  ; removed : int
  ; pending : int option
  ; direction : int option
  }

let component ?(vertical = false) handlers graph =
  let state, set_state =
    Bonsai_v017.state
      ~equal:( = )
      { items = List.init 2 (fun index -> { id = index + 1; token = 1L; phase = Ready })
      ; requests = 0
      ; removed = 0
      ; pending = None
      ; direction = None
      }
      graph
  in
  let bind name update =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_state
      ~f:(fun set_state payload -> set_state (update payload))
  in
  let request id =
    bind (Printf.sprintf "removal-request-%d" id) (fun payload state ->
      match V.Removal.request_of_payload payload with
      | Some (token, direction)
        when List.exists
               (fun item ->
                  item.id = id
                  && item.token = token
                  && (item.phase = Ready || item.phase = Rejected))
               state.items ->
        { state with
          requests = state.requests + 1
        ; pending = Some id
        ; direction =
            Some
              (match direction with
               | Start_to_end -> 0
               | End_to_start -> 1
               | Up -> 2
               | Down -> 3)
        ; items =
            List.map
              (fun item -> if item.id = id then { item with phase = Pending } else item)
              state.items
        }
      | _ -> state)
  in
  let removed id =
    bind (Printf.sprintf "removal-complete-%d" id) (fun payload state ->
      match payload with
      | Ui.Event.Payload.Int64 token
        when List.exists
               (fun item -> item.id = id && item.token = token && item.phase = Accepted)
               state.items ->
        { state with
          removed = state.removed + 1
        ; pending = None
        ; items = List.filter (fun item -> item.id <> id) state.items
        }
      | _ -> state)
  in
  let resolve phase =
    bind
      (if phase = V.Removal.Accepted then "removal-accept" else "removal-reject")
      (fun _ state ->
         { state with
           items =
             List.map
               (fun item ->
                  if Some item.id = state.pending then { item with phase } else item)
               state.items
         })
  in
  let next name =
    bind name (fun _ state ->
      { state with
        pending = None
      ; items =
          List.map
            (fun item -> { item with token = Int64.succ item.token; phase = Ready })
            state.items
      })
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.all
       [ request 1
       ; removed 1
       ; request 2
       ; removed 2
       ; resolve Rejected
       ; resolve Accepted
       ; next "removal-next"
       ; next "removal-replace"
       ])
    ~f:(fun state bindings ->
      let button title index =
        V.button ~on_press:(List.nth bindings index) ~child:(V.text title) ()
      in
      V.Body.static
        (V.column
           ~spacing:0.
           ([ V.text (Printf.sprintf "Requests: %d" state.requests)
            ; V.text
                (Printf.sprintf
                   "Direction: %d"
                   (Option.value state.direction ~default:(-1)))
            ; V.text (Printf.sprintf "Removed: %d" state.removed)
            ; V.text
                (Printf.sprintf "Pending: %d" (Option.value state.pending ~default:0))
            ; button "Reject request" 4
            ; button "Accept request" 5
            ; button "Next request" 6
            ; button "Replace pending request" 7
            ]
            @ List.map
                (fun item ->
                   V.Removal.create
                     ~key:(Ui.Key.int item.id)
                     ~axis:(if vertical then Ui.Layout.Axis.Vertical else Horizontal)
                     ~title:(Printf.sprintf "Delete %d" item.id)
                     ~request_token:item.token
                     ~request_state:item.phase
                     ~on_request:(List.nth bindings ((item.id - 1) * 2))
                     ~on_removed:(List.nth bindings (((item.id - 1) * 2) + 1))
                     (V.frame
                        ~width:500.
                        ~height:120.
                        (V.text (Printf.sprintf "Item %d" item.id))))
                state.items)))
;;
