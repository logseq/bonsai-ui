module Ui = Bonsai_swiftui_ui

let handler = Ui.Event.Handler.create (fun _ -> ())

let catalog =
  Ui.View.Collection.Catalog.create ~keys:[ Ui.Key.string "row" ] ~default_extent:48. ()
;;

let viewport =
  Ui.View.Collection.vertical
    ~catalog
    ~first_index:0
    ~items:[ Ui.View.Keyed.create ~key:(Ui.Key.string "row") (Ui.View.text "Row") ]
    ~on_visible_range:handler
    ()
;;

let _ = Ui.View.column [ Ui.View.text "Search"; viewport ]
