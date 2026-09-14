module Ui = Bonsai_swiftui_ui

let application_theme =
  Ui.Theme.create ~tint:(Ui.Style.Color.rgb ~red:63 ~green:81 ~blue:181) ()
;;

let application_component handlers graph =
  Bonsai.Cont.map (Navigation.component handlers graph) ~f:(fun body ->
    App.View.create ~theme:application_theme ~body:(Ui.View.Body.static body))
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "navigation")
    (App.create ~name:"Navigation" application_component)
;;
