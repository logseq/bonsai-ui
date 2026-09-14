module Ui = Bonsai_swiftui_ui

let component handlers graph =
  let state, set_state =
    Bonsai_v017.state ~equal:( = ) (0, false, false, true, true, false) graph
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
    [ bind "toolbar-action" (fun _ (n, r, m, e, v, p) -> n + 1, r, m, e, v, p)
    ; bind "toolbar-reverse" (fun _ (n, r, m, e, v, p) -> n, not r, m, e, v, p)
    ; bind "toolbar-move" (fun _ (n, r, m, e, v, p) -> n, r, not m, e, v, p)
    ; bind "toolbar-enabled" (fun _ (n, r, m, e, v, p) -> n, r, m, not e, v, p)
    ; bind "toolbar-visible" (fun _ (n, r, m, e, v, p) -> n, r, m, e, not v, p)
    ; bind "toolbar-pin" (fun payload (n, r, m, e, v, p) ->
        let p =
          match payload with
          | Ui.Event.Payload.Bool value -> value
          | _ -> p
        in
        n, r, m, e, v, p)
    ; bind "toolbar-path" (fun _ state -> state)
    ]
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.all bindings)
    ~f:(fun (count, reversed, moved, enabled, visible, pinned) bindings ->
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
        Ui.View.Toolbar.item ~key:(Ui.Key.string key) ~placement content
      in
      let items =
        [ item "title" Principal (Ui.View.text "Native toolbar")
        ; item
            "action"
            (if moved then Navigation else Primary_action)
            (button ~enabled "Toolbar action" action)
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
