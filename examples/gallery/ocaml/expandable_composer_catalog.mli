val component
  :  ?duration:int
  -> ?curve:Bonsai_swiftui_ui.Animation.Curve.t
  -> Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t
