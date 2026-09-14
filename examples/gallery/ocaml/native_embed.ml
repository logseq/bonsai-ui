module Ui = Bonsai_swiftui_ui

let application_theme =
  Ui.Theme.create ~tint:(Ui.Style.Color.rgb ~red:32 ~green:96 ~blue:160) ()
;;

let application_component registry graph =
  Bonsai.Cont.map (Gallery.component registry graph) ~f:(fun body ->
    App.View.create ~theme:application_theme ~body)
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "gallery")
    (App.create ~name:"Bonsai SwiftUI Gallery" application_component)
;;
