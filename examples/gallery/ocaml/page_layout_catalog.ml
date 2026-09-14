module Ui = Bonsai_swiftui_ui

let component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (0, false) graph in
  let bind name update =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state update)
  in
  let action = bind "page-layout-action" (fun (n, expanded) -> n + 1, expanded) in
  let expand = bind "page-layout-expand" (fun (n, expanded) -> n, not expanded) in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.both action expand)
    ~f:(fun (count, expanded) (action, expand) ->
      let button title handler =
        Ui.View.button
          ~key:(Ui.Key.string title)
          ~on_press:handler
          ~child:(Ui.View.text title)
          ()
      in
      let header =
        Ui.View.row [ button "Header action" action; button "Resize footer" expand ]
      in
      let footer =
        Ui.View.column
          [ button "Footer action" action
          ; Ui.View.text (Printf.sprintf "Page actions: %d" count)
          ]
        |> Ui.View.frame ~height:(if expanded then 100. else 60.)
      in
      let content =
        Ui.View.Scroll.vertical
          ~key:(Ui.Key.string "page-layout-scroll")
          (Ui.View.column
             (List.init 50 (fun index ->
                button (Printf.sprintf "Row %d" index) action |> Ui.View.frame ~height:36.)))
        |> Ui.View.Viewport.Vertical.overlay
             ~alignment:Ui.Layout.Alignment.Bottom_end
             ~overlay:
               (button "Floating action" action
                |> Ui.View.padding
                     ~insets:(Ui.Layout.Edge_insets.only ~trailing:16. ~bottom:16. ()))
      in
      Ui.View.Body.Vertical.create
        [ Ui.View.Body.Vertical.fixed header
        ; Ui.View.Body.Vertical.fill content
        ; Ui.View.Body.Vertical.fixed footer
        ])
;;
