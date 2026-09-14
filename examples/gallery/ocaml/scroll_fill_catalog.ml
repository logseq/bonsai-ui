module Ui = Bonsai_swiftui_ui
module V = Ui.View

let component ?(horizontal = false) handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (true, false, 0) graph in
  let action name update =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state update)
  in
  let bindings =
    [ action "scroll-fill-action" (fun (fill, long, count) -> fill, long, count + 1)
    ; action "scroll-fill-length" (fun (fill, long, count) -> fill, not long, count)
    ; action "scroll-fill-enabled" (fun (fill, long, count) -> not fill, long, count)
    ]
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.all bindings)
    ~f:(fun (fill_viewport, long, count) handlers ->
      let color = Ui.Style.Color.rgb ~red:226 ~green:236 ~blue:250 in
      let button label index child =
        V.button
          ~key:(Ui.Key.string label)
          ~style:V.Button_style.Plain
          ~on_press:(List.nth handlers index)
          ~child
          ()
      in
      let sized extent label =
        let view = V.text label in
        if horizontal
        then V.frame ~width:extent ~max_height:Ui.Layout.Frame_limit.Fill view
        else V.frame ~height:extent ~max_width:Ui.Layout.Frame_limit.Fill view
      in
      let fill =
        let minimum = if long then 900. else if horizontal then 120. else 60. in
        let text = V.text "Fill content" in
        let child =
          if horizontal
          then
            V.frame
              ~min_width:minimum
              ~max_width:Ui.Layout.Frame_limit.Fill
              ~max_height:Ui.Layout.Frame_limit.Fill
              text
          else
            V.frame
              ~min_height:minimum
              ~max_height:Ui.Layout.Frame_limit.Fill
              ~max_width:Ui.Layout.Frame_limit.Fill
              text
        in
        button "Fill content" 0 (V.background ~color child)
      in
      let items =
        [ V.Weighted.fixed (sized 80. "Header")
        ; V.Weighted.share fill
        ; V.Weighted.fixed (sized 40. "Footer")
        ]
      in
      let controls =
        V.column
          [ V.text (Printf.sprintf "Actions: %d" count)
          ; button "Toggle long content" 1 (V.text "Toggle long content")
          ; button "Toggle filling" 2 (V.text "Toggle filling")
          ]
      in
      if horizontal
      then
        V.Body.Horizontal.create
          [ V.Body.Horizontal.fill
              (V.Scroll.horizontal ~fill_viewport (V.Weighted.row ~spacing:0. items))
          ; V.Body.Horizontal.fixed (V.frame ~width:200. controls)
          ]
      else
        V.Body.Vertical.create
          [ V.Body.Vertical.fill
              (V.Scroll.vertical ~fill_viewport (V.Weighted.column ~spacing:0. items))
          ; V.Body.Vertical.fixed controls
          ])
;;
