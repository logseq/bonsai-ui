module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

let details_page_key = ID.Navigation.Page_key.of_string "details"

let component handlers graph =
  let details_open, set_details_open = Bonsai_v017.state ~equal:Bool.equal false graph in
  let open_details =
    Driver.Handler.create
      handlers
      ~name:"navigation-open"
      ~equal:( == )
      set_details_open
      ~f:(fun set_open _ -> set_open (fun _ -> true))
  in
  let close_details =
    Driver.Handler.create
      handlers
      ~name:"navigation-close"
      ~equal:( == )
      set_details_open
      ~f:(fun set_open -> function
      | Ui.Event.Payload.Navigation_path_changed [] | Ui.Event.Payload.Unit ->
        set_open (fun _ -> false)
      | _ -> Bonsai.Effect.Ignore)
  in
  let controls =
    Bonsai.Cont.map2 open_details close_details ~f:(fun open_details close_details ->
      open_details, close_details)
  in
  Bonsai.Cont.map2
    details_open
    controls
    ~f:(fun details_open (open_details, close_details) ->
      let button title handler =
        Ui.View.button
          ~style:Ui.View.Button_style.Prominent
          ~on_press:handler
          ~child:(Ui.View.text title)
          ()
        |> Ui.View.frame
             ~max_width:Ui.Layout.Frame_limit.Fill
             ~max_height:Ui.Layout.Frame_limit.Fill
      in
      let home = Ui.View.Body.static (button "Open details" open_details) in
      let path =
        if details_open
        then
          [ Ui.View.Navigation_stack.destination
              ~page_key:details_page_key
              ~title:"Details"
              (Ui.View.Body.static (button "Close details" close_details))
          ]
        else []
      in
      Ui.View.Navigation_stack.create
        ~title:"Navigation"
        ~on_path_change:close_details
        ~path
        home)
;;
