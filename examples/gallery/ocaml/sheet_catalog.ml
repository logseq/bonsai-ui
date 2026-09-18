module Ui = Bonsai_swiftui_ui

type state =
  { shown : bool
  ; variant : int
  ; count : int
  ; selected : int64 option
  ; reject : bool
  ; interactive : bool
  ; requests : int
  ; replacement : bool
  ; hint : bool
  }

let component handlers graph =
  let state, set_state =
    Bonsai_v017.state
      ~equal:( = )
      { shown = false
      ; variant = 0
      ; count = 0
      ; selected = None
      ; reject = false
      ; interactive = true
      ; requests = 0
      ; replacement = false
      ; hint = false
      }
      graph
  in
  let bind name f =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state f)
  in
  let show = bind "sheet-show" (fun s -> { s with shown = true }) in
  let hide = bind "sheet-hide" (fun s -> { s with shown = false; hint = false }) in
  let next =
    bind "sheet-next" (fun s ->
      if s.shown then s else { s with variant = (s.variant + 1) mod 5 })
  in
  let action =
    bind "sheet-action" (fun s -> if s.shown then { s with count = s.count + 1 } else s)
  in
  let background = bind "sheet-background" (fun s -> { s with count = s.count + 100 }) in
  let reject = bind "sheet-reject" (fun s -> { s with reject = not s.reject }) in
  let interactive =
    bind "sheet-interactive" (fun s -> { s with interactive = not s.interactive })
  in
  let replace =
    bind "sheet-replace" (fun s -> { s with replacement = not s.replacement })
  in
  let hint = bind "sheet-hint" (fun s -> { s with hint = not s.hint }) in
  let hint_dismiss = bind "sheet-hint-dismiss" (fun s -> { s with hint = false }) in
  let choice id =
    bind
      ("sheet-choice-" ^ Int64.to_string id)
      (fun s ->
         if s.shown && id <> 9L
         then { s with selected = Some id; count = s.count + 1 }
         else s)
  in
  let owner =
    Bonsai.Cont.map2 set_state state ~f:(fun set_state s -> set_state, s.replacement)
  in
  let dismiss =
    Driver.Handler.create
      handlers
      ~name:"sheet-dismiss"
      ~equal:(fun (a, x) (b, y) -> a == b && x = y)
      owner
      ~f:(fun (set_state, _) -> function
        | Ui.Event.Payload.Bool false ->
          set_state (fun s ->
            if s.interactive && s.variant <> 4
            then { s with shown = s.reject; hint = false; requests = s.requests + 1 }
            else s)
        | _ -> Bonsai.Effect.Ignore)
  in
  let pairs = Bonsai.Cont.both in
  Bonsai.Cont.map2
    state
    (pairs
       show
       (pairs
          hide
          (pairs
             next
             (pairs
                action
                (pairs
                   background
                   (pairs
                      reject
                      (pairs
                         interactive
                         (pairs
                            replace
                            (pairs
                               hint
                               (pairs
                                  hint_dismiss
                                  (pairs
                                     dismiss
                                     (pairs
                                        (choice (-7L))
                                        (pairs (choice 9L) (choice 13L))))))))))))))
    ~f:
      (fun
        s
        ( show
        , ( hide
          , ( next
            , ( action
              , ( background
                , ( reject
                  , ( interactive
                    , ( replace
                      , (hint, (hint_dismiss, (dismiss, (personal, (unavailable, work)))))
                      ) ) ) ) ) ) ) ) ->
      let button ?(enabled = true) title on_press =
        Ui.View.button
          ~key:(Ui.Key.string title)
          ~enabled
          ~on_press
          ~child:(Ui.View.text title)
          ()
      in
      let title =
        List.nth
          [ "Alert details"
          ; "Choose an account"
          ; "Bottom sheet content"
          ; "Inspector content"
          ; "Fullscreen content"
          ]
          s.variant
      in
      let content =
        Ui.View.column
          ([ Ui.View.symbol ~name:"info.circle" ()
           ; Ui.View.text title
           ; Ui.View.divider ()
           ; Ui.View.text "Review the details before continuing."
           ; Ui.View.Context_menu.attach
               (Ui.View.Context_menu.create
                  ~actions:
                    [ Ui.View.Context_menu.action
                        ~key:(Ui.Key.string "sheet-action")
                        ~title:"Sheet context action"
                        ~on_press:action
                        ()
                    ]
                  ())
               (button "Sheet action" action)
           ]
           @ (if s.variant = 1
              then
                [ button "Personal" personal
                ; button ~enabled:false "Unavailable" unavailable
                ; button "Work" work
                ]
              else [])
           @ [ Ui.View.Popover.create
                 ~presented:s.hint
                 ~on_presented_changed:hint_dismiss
                 ~content:
                   (Ui.View.column
                      [ Ui.View.text "Nested help"; button "Hint action" action ]
                    |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 12.))
                 (button "Show hint" hint)
             ; button "Close sheet" hide
             ; button (if s.reject then "Accept dismissal" else "Reject dismissal") reject
             ; button "Replace sheet handler" replace
             ]
           @
           if s.variant = 4
           then []
           else
             [ button
                 (if s.interactive then "Lock dismissal" else "Unlock dismissal")
                 interactive
             ])
        |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 16.)
        |> Ui.View.frame
             ~min_width:320.
             ~ideal_width:360.
             ~max_width:Ui.Layout.Frame_limit.Fill
             ~min_height:360.
             ~ideal_height:420.
             ~max_height:Ui.Layout.Frame_limit.Fill
      in
      let background_view =
        Ui.View.column
          [ button "Open sheet" show
          ; button "Next presentation" next
          ; button "Background action" background
          ; Ui.View.text (Printf.sprintf "Sheet variant: %d" s.variant)
          ; Ui.View.text (if s.shown then "Sheet: Open" else "Sheet: Closed")
          ; Ui.View.text (Printf.sprintf "Sheet actions: %d" s.count)
          ; Ui.View.text (Printf.sprintf "Sheet dismissals: %d" s.requests)
          ; Ui.View.text
              ("Selected account: "
               ^ Option.fold ~none:"None" ~some:Int64.to_string s.selected)
          ]
      in
      let presentation =
        if s.variant = 4
        then
          Ui.View.Sheet.full_screen
            ~presented:s.shown
            ~on_presented_changed:dismiss
            ~content
            background_view
        else
          Ui.View.Sheet.create
            ~sizing:
              (match s.variant with
               | 0 -> Ui.View.Sheet.Fitted
               | 1 -> Form
               | 2 -> Page
               | _ -> Automatic)
            ~detents:[ Ui.View.Sheet.Medium; Large ]
            ~initial_detent:Ui.View.Sheet.Medium
            ~interactive_dismiss:s.interactive
            ~shows_drag_indicator:(s.variant = 2)
            ~presented:s.shown
            ~on_presented_changed:dismiss
            ~content
            background_view
      in
      Ui.View.column [ presentation; button "Sibling action" background ])
;;
