module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

let component handlers graph =
  let state, set_state = Bonsai_v017.state ~equal:( = ) (0, false, false) graph in
  let bind name update =
    Driver.Handler.create
      handlers
      ~name
      ~equal:( == )
      set_state
      ~f:(fun set_state payload -> set_state (fun state -> update state payload))
  in
  let action = bind "app-bar-action" (fun (n, open_, large) _ -> n + 1, open_, large) in
  let open_details = bind "app-bar-open" (fun (n, _, large) _ -> n, true, large) in
  let close_details =
    bind "app-bar-close" (fun ((n, _, large) as state) -> function
      | Ui.Event.Payload.Unit | Navigation_path_changed [] -> n, false, large
      | _ -> state)
  in
  let resize = bind "app-bar-resize" (fun (n, open_, large) _ -> n, open_, not large) in
  Bonsai.Cont.map2
    state
    (Bonsai.Cont.all [ action; open_details; close_details; resize ])
    ~f:(fun (count, details_open, large) bindings ->
      let action = List.nth bindings 0 in
      let open_details = List.nth bindings 1 in
      let close_details = List.nth bindings 2 in
      let resize = List.nth bindings 3 in
      let button title handler =
        Ui.View.button
          ~key:(Ui.Key.string title)
          ~on_press:handler
          ~child:(Ui.View.text title)
          ()
      in
      let item key placement view =
        Ui.View.Toolbar.item ~key:(Ui.Key.string key) ~placement view
      in
      let status () = Ui.View.text (Printf.sprintf "Bar actions: %d" count) in
      let root_scroll =
        Ui.View.Scroll.vertical
          ~key:(Ui.Key.string "app-bars-root-scroll")
          (Ui.View.column
             (List.init 50 (fun index ->
                Ui.View.text (Printf.sprintf "Root row %d" index)
                |> Ui.View.frame ~height:36.)))
      in
      let compose =
        Ui.View.button
          ~on_press:action
          ~child:
            (Ui.View.symbol ~name:"plus" ()
             |> Ui.View.semantics
                  ~properties:(Ui.Semantics.create ~label:"Compose action" ()))
          ()
        |> Ui.View.help ~message:"Compose action"
      in
      let bottom =
        Ui.View.column
          ~spacing:2.
          [ status ()
          ; Ui.View.row
              ~spacing:8.
              [ button "Bottom action" action
              ; compose
              ; button "Resize bottom content" resize
              ]
          ; Ui.View.text (if large then "Bottom height: 100" else "Bottom height: 60")
          ]
        |> Ui.View.frame ~height:(if large then 100. else 60.)
      in
      let root =
        Ui.View.Body.Vertical.create
          [ Ui.View.Body.Vertical.fill root_scroll; Ui.View.Body.Vertical.fixed bottom ]
        |> Ui.View.Body.toolbar
             ~items:
               [ item "leading" Navigation (button "Leading action" action)
               ; item "top" Primary_action (button "Top action" action)
               ; item "details" Primary_action (button "Open bar details" open_details)
               ]
      in
      let path =
        if details_open
        then
          [ Ui.View.Navigation_stack.destination
              ~page_key:(ID.Navigation.Page_key.of_string "bar-details")
              ~title:"Bar details"
              (Ui.View.Body.Vertical.create
                 [ Ui.View.Body.Vertical.fill
                     (Ui.View.Scroll.vertical
                        ~key:(Ui.Key.string "app-bars-detail-scroll")
                        (Ui.View.column
                           (List.init 30 (fun index ->
                              Ui.View.text (Printf.sprintf "Detail row %d" index)
                              |> Ui.View.frame ~height:36.))))
                 ; Ui.View.Body.Vertical.fixed
                     (Ui.View.column
                        [ status (); button "Close bar details" close_details ])
                 ]
               |> Ui.View.Body.toolbar
                    ~items:
                      [ item "detail" Primary_action (button "Detail action" action) ])
          ]
        else []
      in
      Ui.View.Navigation_stack.create
        ~title:"Native app bars"
        ~on_path_change:close_details
        ~path
        root)
;;
