module Ui = Bonsai_swiftui_ui

let application_theme =
  Ui.Theme.create ~tint:(Ui.Style.Color.rgb ~red:94 ~green:53 ~blue:177) ()
;;

let application_component handlers graph =
  Bonsai.Cont.map (Text_input_example.component handlers graph) ~f:(fun body ->
    App.View.create ~theme:application_theme ~body:(Ui.View.Body.static body))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "text_input")
    (App.create ~name:"Text Input" application_component)
;;
