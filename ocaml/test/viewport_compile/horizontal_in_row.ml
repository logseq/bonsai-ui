module Ui = Bonsai_swiftui_ui

let viewport = Ui.View.Scroll.horizontal (Ui.View.text "Content")
let _ = Ui.View.row [ Ui.View.text "Leading"; viewport ]
