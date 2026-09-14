val component
  :  ?kind:int
  -> ?horizontal:bool
  -> Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.Body.t Bonsai.Cont.t

val nested_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.Body.t Bonsai.Cont.t
