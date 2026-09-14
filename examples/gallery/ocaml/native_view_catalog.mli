type event = Activate

val card : (string, event) Bonsai_swiftui_ui.Native_widget.Extension.t

val component
  :  ?nested:int
  -> Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t
