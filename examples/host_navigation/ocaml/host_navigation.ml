module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

let settings_page_key = ID.Navigation.Page_key.of_string "settings"

let clipboard_preview text =
  let maximum_bytes = 4096 in
  if String.length text <= maximum_bytes
  then text
  else (
    let boundary = ref maximum_bytes in
    while !boundary > 0 && Char.code text.[!boundary] land 0xc0 = 0x80 do
      decr boundary
    done;
    String.sub text 0 !boundary ^ "…")
;;

let component handlers graph =
  let settings_open, set_settings_open =
    Bonsai_v017.state ~equal:Bool.equal false graph
  in
  let clipboard, set_clipboard =
    Bonsai_v017.state ~equal:String.equal "Clipboard not read" graph
  in
  let open_settings =
    Driver.Handler.create
      handlers
      ~name:"open-settings"
      ~equal:( == )
      set_settings_open
      ~f:(fun set_settings_open _ -> set_settings_open (fun _ -> true))
  in
  let close_settings =
    Driver.Handler.create
      handlers
      ~name:"close-settings"
      ~equal:( == )
      set_settings_open
      ~f:(fun set_settings_open -> function
      | Ui.Event.Payload.Navigation_path_changed [] | Ui.Event.Payload.Unit ->
        set_settings_open (fun _ -> false)
      | _ -> Bonsai.Effect.Ignore)
  in
  let host_effects = Driver.Handler.host_effects handlers in
  let read_clipboard =
    Driver.Handler.create
      handlers
      ~name:"read-clipboard"
      ~equal:( == )
      set_clipboard
      ~f:(fun set_clipboard _ ->
        Bonsai.Effect.bind (Host_effect.Clipboard.read host_effects ()) ~f:(function
          | Ok text -> set_clipboard (fun _ -> clipboard_preview text)
          | Error _ -> set_clipboard (fun _ -> "Clipboard request failed")))
  in
  let state =
    Bonsai.Cont.map2 settings_open clipboard ~f:(fun settings_open clipboard ->
      settings_open, clipboard)
  in
  let navigation_handlers =
    Bonsai.Cont.map2 open_settings close_settings ~f:(fun open_settings close_settings ->
      open_settings, close_settings)
  in
  let handlers =
    Bonsai.Cont.map2
      navigation_handlers
      read_clipboard
      ~f:(fun (open_settings, close_settings) read_clipboard ->
        open_settings, close_settings, read_clipboard)
  in
  Bonsai.Cont.map2
    state
    handlers
    ~f:(fun (settings_open, clipboard) (open_settings, close_settings, read_clipboard) ->
      let button label on_press =
        Ui.View.button
          ~style:Ui.View.Button_style.Prominent
          ~on_press
          ~child:(Ui.View.text label)
          ()
      in
      let content children =
        Ui.View.column
          ~spacing:16.
          ~alignment:Ui.Layout.Horizontal_alignment.Leading
          children
        |> Ui.View.padding ~insets:(Ui.Layout.Edge_insets.all 24.)
        |> Ui.View.frame
             ~max_width:Ui.Layout.Frame_limit.Fill
             ~max_height:Ui.Layout.Frame_limit.Fill
             ~alignment:Ui.Layout.Alignment.Top_start
        |> Ui.View.Body.static
      in
      let home =
        content
          [ Ui.View.text "Host effects and navigation"
          ; Ui.View.text ~line_limit:8 clipboard
          ; button "Read clipboard" read_clipboard
          ; button "Open settings" open_settings
          ]
      in
      let path =
        if settings_open
        then
          [ Ui.View.Navigation_stack.destination
              ~page_key:settings_page_key
              ~title:"Settings"
              (content
                 [ Ui.View.stack [ Ui.View.text "Overlay owned by OCaml" ]
                 ; Ui.View.column
                     ~spacing:12.
                     ~alignment:Ui.Layout.Horizontal_alignment.Leading
                     [ Ui.View.text "Settings"
                     ; Ui.View.divider ()
                     ; Ui.View.text "Settings content owned by OCaml"
                     ]
                 ; button "Close settings" close_settings
                 ])
          ]
        else []
      in
      Ui.View.Navigation_stack.create
        ~title:"Host Navigation"
        ~on_path_change:close_settings
        ~path
        home)
;;

let app =
  let theme = Ui.Theme.create ~tint:(Ui.Style.Color.rgb ~red:0 ~green:121 ~blue:107) () in
  App.create ~name:"Host Navigation" (fun handlers graph ->
    Bonsai.Cont.map (component handlers graph) ~f:(fun body ->
      App.View.create ~theme ~body:(Ui.View.Body.static body)))
;;
