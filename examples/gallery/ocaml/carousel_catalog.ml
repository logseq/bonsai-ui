module Ui = Bonsai_swiftui_ui
module S = Ui.View.Scroll_targets

type state =
  { position : int64 option
  ; updates : int
  ; opened : int64 option
  ; actions : int
  ; vertical : bool
  ; fraction : float
  ; alignment : S.alignment
  ; snapping : bool
  ; enabled : bool
  ; ignored : bool
  ; reversed : bool
  ; removed : bool
  ; empty : bool
  ; replacement : bool
  }

let initial =
  { position = Some (-7L)
  ; updates = 0
  ; opened = None
  ; actions = 0
  ; vertical = false
  ; fraction = 1.
  ; alignment = S.Start
  ; snapping = true
  ; enabled = true
  ; ignored = false
  ; reversed = false
  ; removed = false
  ; empty = false
  ; replacement = false
  }
;;

let ids state =
  let ids =
    if state.empty then [] else if state.removed then [ -7L; 9L ] else [ -7L; 9L; 13L ]
  in
  if state.reversed then List.rev ids else ids
;;

let component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) initial graph in
  let action name update =
    Driver.Handler.create
      handlers
      ~name:("carousel-" ^ name)
      ~equal:( == )
      set_state
      ~f:(fun set_state _ -> set_state update)
  in
  let owner =
    Bonsai.Cont.map2 set_state state ~f:(fun setter state -> setter, state.replacement)
  in
  let scroll =
    Driver.Handler.create
      handlers
      ~name:"carousel-position"
      ~equal:(fun (left, a) (right, b) -> left == right && a = b)
      owner
      ~f:(fun (set_state, _) -> function
        | Ui.Event.Payload.Int64 id ->
          set_state (fun state ->
            if state.enabled && (not state.ignored) && List.mem id (ids state)
            then { state with position = Some id; updates = state.updates + 1 }
            else state)
        | _ -> Bonsai.Effect.Ignore)
  in
  let cards =
    List.map
      (fun (id, title, color) ->
         Bonsai.Cont.map
           (action
              ("open-" ^ Int64.to_string id)
              (fun state ->
                 if List.mem id (ids state)
                 then { state with opened = Some id; actions = state.actions + 1 }
                 else state))
           ~f:(fun handler -> id, title, color, handler))
      [ -7L, "Open first", (235, 242, 255)
      ; 9L, "Open second", (238, 248, 239)
      ; 13L, "Open third", (255, 242, 231)
      ]
  in
  let collect values =
    List.fold_right
      (fun value rest -> Bonsai.Cont.map2 value rest ~f:(fun value rest -> value :: rest))
      values
      (Bonsai.Cont.return [])
  in
  let cards = collect cards in
  let controls =
    [ ("axis", fun state -> { state with vertical = not state.vertical })
    ; ( "fraction"
      , fun state -> { state with fraction = (if state.fraction = 1. then 0.65 else 1.) }
      )
    ; ("start", fun state -> { state with alignment = S.Start })
    ; ("center", fun state -> { state with alignment = S.Center })
    ; ("end", fun state -> { state with alignment = S.End })
    ; ("snap", fun state -> { state with snapping = not state.snapping })
    ; ("enabled", fun state -> { state with enabled = not state.enabled })
    ; ("ignore", fun state -> { state with ignored = not state.ignored })
    ; ("reverse", fun state -> { state with reversed = not state.reversed })
    ; ( "remove"
      , fun state ->
          { state with
            removed = not state.removed
          ; position =
              (if (not state.removed) && state.position = Some 13L
               then Some (-7L)
               else state.position)
          } )
    ; ( "empty"
      , fun state ->
          { state with
            empty = not state.empty
          ; position = (if state.empty then Some (-7L) else None)
          } )
    ; ( "last"
      , fun state ->
          { state with
            position =
              (if state.empty then None else Some (if state.removed then 9L else 13L))
          } )
    ; ("replace", fun state -> { state with replacement = not state.replacement })
    ]
    |> List.map (fun (name, update) ->
      Bonsai.Cont.map (action name update) ~f:(fun handler -> name, handler))
    |> collect
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both scroll (Bonsai.Cont.both cards controls))
    ~f:(fun state (on_position_changed, (cards, controls)) ->
      let button title name =
        Ui.View.button ~on_press:(List.assoc name controls) ~child:(Ui.View.text title) ()
      in
      let cards =
        List.map
          (fun id ->
             let _, title, (red, green, blue), on_press =
               List.find (fun (candidate, _, _, _) -> candidate = id) cards
             in
             S.item
               ~id
               (Ui.View.button
                  ~style:Ui.View.Button_style.Plain
                  ~on_press
                  ~child:
                    (Ui.View.text title
                     |> Ui.View.frame
                          ~max_width:Ui.Layout.Frame_limit.Fill
                          ~max_height:Ui.Layout.Frame_limit.Fill
                     |> Ui.View.background
                          ~color:(Ui.Style.Color.rgb ~red ~green ~blue)
                          ~corner_radius:12.)
                  ()))
          (ids state)
      in
      let content =
        if state.vertical
        then
          S.vertical
            ~fraction:state.fraction
            ~spacing:12.
            ~alignment:state.alignment
            ~snapping:state.snapping
            ~enabled:state.enabled
            ~position:state.position
            ~on_position_changed
            cards
          |> Ui.View.Viewport.Vertical.with_height ~height:200.
          |> Ui.View.frame ~width:280.
        else
          S.horizontal
            ~fraction:state.fraction
            ~spacing:12.
            ~alignment:state.alignment
            ~snapping:state.snapping
            ~enabled:state.enabled
            ~position:state.position
            ~on_position_changed
            cards
          |> Ui.View.Viewport.Horizontal.with_width ~width:280.
          |> Ui.View.frame ~height:200.
      in
      Ui.View.column
        ~spacing:10.
        [ Ui.View.text "Carousel through native scroll targets"
        ; content
        ; Ui.View.text
            ("Position: " ^ Option.fold ~none:"None" ~some:Int64.to_string state.position)
        ; Ui.View.text (Printf.sprintf "Position updates: %d" state.updates)
        ; Ui.View.text
            (Printf.sprintf
               "Opened: %s (%d actions)"
               (Option.fold ~none:"None" ~some:Int64.to_string state.opened)
               state.actions)
        ; Ui.View.text ("Axis: " ^ if state.vertical then "Vertical" else "Horizontal")
        ; Ui.View.flow
            ~spacing:8.
            ~line_spacing:8.
            [ button
                (if state.vertical then "Use horizontal layout" else "Use vertical layout")
                "axis"
            ; button
                (if state.fraction = 1. then "Use preview cards" else "Use full cards")
                "fraction"
            ; button
                (if state.snapping then "Disable snapping" else "Enable snapping")
                "snap"
            ]
        ; Ui.View.flow
            ~spacing:8.
            ~line_spacing:8.
            [ button "Align start" "start"
            ; button "Align center" "center"
            ; button "Align end" "end"
            ]
        ; Ui.View.flow
            ~spacing:8.
            ~line_spacing:8.
            [ button
                (if state.enabled then "Disable scrolling" else "Enable scrolling")
                "enabled"
            ; button
                (if state.ignored
                 then "Accept scroll changes"
                 else "Ignore scroll changes")
                "ignore"
            ; button "Go to last card" "last"
            ]
        ; Ui.View.flow
            ~spacing:8.
            ~line_spacing:8.
            [ button "Reverse cards" "reverse"
            ; button
                (if state.removed then "Restore last card" else "Remove last card")
                "remove"
            ; button (if state.empty then "Restore cards" else "Empty cards") "empty"
            ; button "Replace scroll handler" "replace"
            ]
        ])
;;
