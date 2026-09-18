module Ui = Bonsai_swiftui_ui

let component handlers graph =
  let state, set_state =
    Bonsai_v017.state ~equal:( = ) (0, false, false, true, true, false, false) graph
  in
  let bind name update =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_state
      ~f:(fun set_state payload -> set_state (update payload))
  in
  let bindings =
    [ bind "toolbar-action" (fun _ (n, r, m, e, v, p, foreign) ->
        n + 1, r, m, e, v, p, foreign)
    ; bind "toolbar-reverse" (fun _ (n, r, m, e, v, p, foreign) ->
        n, not r, m, e, v, p, foreign)
    ; bind "toolbar-move" (fun _ (n, r, m, e, v, p, foreign) ->
        n, r, not m, e, v, p, foreign)
    ; bind "toolbar-enabled" (fun _ (n, r, m, e, v, p, foreign) ->
        n, r, m, not e, v, p, foreign)
    ; bind "toolbar-visible" (fun _ (n, r, m, e, v, p, foreign) ->
        n, r, m, e, not v, p, foreign)
    ; bind "toolbar-pin" (fun payload (n, r, m, e, v, p, foreign) ->
        let p =
          match payload with
          | Ui.Event.Payload.Bool value -> value
          | _ -> p
        in
        n, r, m, e, v, p, foreign)
    ; bind "toolbar-path" (fun _ state -> state)
    ; bind "toolbar-reparent" (fun _ (n, r, m, e, v, p, foreign) ->
        n, r, m, e, v, p, not foreign)
    ]
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.all bindings)
    ~f:(fun (count, reversed, moved, enabled, visible, pinned, foreign) bindings ->
      let action = List.nth bindings 0 in
      let button ?(enabled = true) title handler =
        Ui.View.button
          ~key:(Ui.Key.string title)
          ~enabled
          ~on_press:handler
          ~child:(Ui.View.text title)
          ()
      in
      let item key placement content =
        Ui.View.Toolbar.group
          ~key:(Ui.Key.string key)
          ~placement
          [ Ui.View.Toolbar.child ~key:(Ui.Key.string "control") content ]
      in
      let items =
        [ Ui.View.Toolbar.item
            ~key:(Ui.Key.string "title")
            ~placement:Principal
            (Ui.View.text "Native toolbar")
        ; Ui.View.Toolbar.spacer
            ~key:(Ui.Key.string "command-gap")
            ~placement:Primary_action
            Fixed
        ; Ui.View.Toolbar.group
            ~key:(Ui.Key.string "action")
            ~placement:(if moved then Navigation else Primary_action)
            (if foreign
             then []
             else
               [ Ui.View.Toolbar.child
                   ~key:(Ui.Key.string "control")
                   (button ~enabled "Toolbar action" action)
               ])
        ; Ui.View.Toolbar.group
            ~key:(Ui.Key.string "other-action")
            ~placement:Primary_action
            (if foreign
             then
               [ Ui.View.Toolbar.child
                   ~key:(Ui.Key.string "control")
                   (button ~enabled "Toolbar action" action)
               ]
             else [])
        ; item
            "pin"
            Primary_action
            (Ui.View.toggle
               ~value:pinned
               ~style:Ui.View.Toggle_style.Button
               ~on_changed:(List.nth bindings 5)
               ~label:(Ui.View.text "Pin toolbar")
               ())
        ; item
            "more"
            Secondary_action
            (Ui.View.Menu.create
               ~on_select:action
               ~label:
                 (Ui.View.label
                    ~title:(Ui.View.text "More toolbar actions")
                    ~icon:(Ui.View.symbol ~name:"ellipsis" ())
                    ())
               [ Ui.View.Menu.action
                   ~id:(-7L)
                   ~label:(Ui.View.text "Additional action")
                   ()
               ; Ui.View.Menu.action
                   ~id:9L
                   ~enabled:false
                   ~label:(Ui.View.text "Unavailable action")
                   ()
               ])
        ]
      in
      let items =
        if not visible then [] else if reversed then List.rev items else items
      in
      let content =
        Ui.View.column
          [ Ui.View.text (Printf.sprintf "Toolbar actions: %d" count)
          ; Ui.View.text
              (if reversed then "Toolbar order: reversed" else "Toolbar order: original")
          ; Ui.View.text (if pinned then "Toolbar pinned" else "Toolbar unpinned")
          ; button "Reverse toolbar" (List.nth bindings 1)
          ; button "Move toolbar action" (List.nth bindings 2)
          ; button "Reparent toolbar action" (List.nth bindings 7)
          ; button
              (if enabled then "Disable toolbar action" else "Enable toolbar action")
              (List.nth bindings 3)
          ; button
              (if visible then "Hide toolbar" else "Show toolbar")
              (List.nth bindings 4)
          ]
      in
      Ui.View.Navigation_stack.create
        ~title:"Toolbar catalog"
        ~path:[]
        ~on_path_change:(List.nth bindings 6)
        (Ui.View.Body.static
           (Ui.View.Toolbar.create ~key:(Ui.Key.string "toolbar") ~items content)))
;;
