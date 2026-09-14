module Ui = Bonsai_swiftui_ui

let viewport = Ui.View.Scroll.horizontal (Ui.View.text "Content")
let _ = Ui.View.Body.Vertical.create [ Ui.View.Body.Vertical.fill viewport ]
