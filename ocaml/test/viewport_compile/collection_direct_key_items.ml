module Ui = Bonsai_swiftui_ui

let handler = Ui.Event.Handler.create (fun _ -> ())

let catalog =
  Ui.View.Collection.Catalog.create ~keys:[ Ui.Key.string "row" ] ~default_extent:48. ()
;;

let _ =
  Ui.View.Collection.vertical
    ~catalog
    ~first_index:0
    ~items:[ Ui.View.text ~key:(Ui.Key.string "row") "Direct key" ]
    ~on_visible_range:handler
    ()
;;
