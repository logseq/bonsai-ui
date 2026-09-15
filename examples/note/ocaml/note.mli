(** A deterministic, in-memory document capability demonstration. *)
val component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val app : App.t
