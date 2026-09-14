module Ui = Bonsai_swiftui_ui

let viewport = Ui.View.Scroll.vertical (Ui.View.text "Content")
let _ = Ui.View.Weighted.column [ Ui.View.Weighted.fixed viewport ]
