module Ui = Bonsai_swiftui_ui

let component ?(horizontal = false) handlers graph =
  let state, set_state =
    Bonsai_v017.state ~equal:( = ) (0, false, true, true, false, true) graph
  in
  let bind name update =
    Driver.Handler.create handlers ~name ~equal:( == ) set_state ~f:(fun set_state _ ->
      set_state update)
  in
  let bindings =
    [ bind "section-action" (fun (n, r, p, v, h, s) -> n + 1, r, p, v, h, s)
    ; bind "section-reverse" (fun (n, r, p, v, h, s) -> n, not r, p, v, h, s)
    ; bind "section-pin" (fun (n, r, p, v, h, s) -> n, r, not p, v, h, s)
    ; bind "section-header" (fun (n, r, p, v, h, s) -> n, r, p, not v, h, s)
    ; bind "section-height" (fun (n, r, p, v, h, s) -> n, r, p, v, not h, s)
    ; bind "section-stretch" (fun (n, r, p, v, h, s) -> n, r, p, v, h, not s)
    ]
  in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.all bindings)
    ~f:(fun (count, reversed, pinned, visible, large, stretch) bindings ->
      let button ?(transform = Fun.id) label index =
        Ui.View.button
          ~key:(Ui.Key.string label)
          ~style:Ui.View.Button_style.Plain
          ~on_press:(List.nth bindings index)
          ~child:(transform (Ui.View.text label))
          ()
      in
      let sized extent view =
        if horizontal
        then Ui.View.frame ~width:extent ~max_height:Ui.Layout.Frame_limit.Fill view
        else Ui.View.frame ~height:extent ~max_width:Ui.Layout.Frame_limit.Fill view
      in
      let bar extent view =
        sized extent view
        |> Ui.View.background ~color:(Ui.Style.Color.rgb ~red:235 ~green:238 ~blue:244)
      in
      let section name =
        let items =
          List.init 20 (fun i ->
            let label = Printf.sprintf "%s row %d" name i in
            Ui.View.Keyed.create
              ~key:(Ui.Key.string label)
              (Ui.View.text label |> sized (if horizontal then 120. else 36.)))
        in
        Ui.View.Scroll_sections.section
          ~key:(Ui.Key.string name)
          ?header:
            (if visible
             then
               Some
                 (button
                    ~transform:(bar (if horizontal then 96. else 48.))
                    ("Header " ^ name)
                    0)
             else None)
          ~footer:
            (button
               ~transform:(bar (if horizontal then 80. else 40.))
               ("Footer " ^ name)
               0)
          (if reversed then List.rev items else items)
      in
      let sections = [ section "A"; section "B" ] in
      let controls =
        Ui.View.column
          ([ Ui.View.text (Printf.sprintf "Section actions: %d" count)
           ; Ui.View.text ("Stretch: " ^ if stretch then "on" else "off")
           ; button "Reverse rows" 1
           ; button "Toggle pinning" 2
           ; button (if visible then "Hide headers" else "Show headers") 3
           ]
           @
           if horizontal
           then []
           else [ button "Resize hero" 4; button "Toggle stretch" 5 ])
      in
      if horizontal
      then
        Ui.View.Body.Horizontal.create
          [ Ui.View.Body.Horizontal.fill
              (Ui.View.Scroll_sections.horizontal
                 ~pin_headers:pinned
                 ~pin_footers:pinned
                 sections)
          ; Ui.View.Body.Horizontal.fixed controls
          ]
      else (
        let hero =
          Ui.View.Scroll_sections.hero
            ~key:(Ui.Key.string "hero")
            ~height:(if large then 200. else 160.)
            ~stretch
            (button
               ~transform:(fun view ->
                 Ui.View.frame
                   ~max_width:Ui.Layout.Frame_limit.Fill
                   ~max_height:Ui.Layout.Frame_limit.Fill
                   view
                 |> Ui.View.background
                      ~color:(Ui.Style.Color.rgb ~red:225 ~green:232 ~blue:244))
               "Hero action"
               0)
        in
        Ui.View.Body.Vertical.create
          [ Ui.View.Body.Vertical.fill
              (Ui.View.Scroll_sections.vertical
                 ~pin_headers:pinned
                 ~pin_footers:pinned
                 (hero :: sections))
          ; Ui.View.Body.Vertical.fixed controls
          ]))
;;
