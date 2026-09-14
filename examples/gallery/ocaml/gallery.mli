val theme_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val slider_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val toggle_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val swipe_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val morph_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val tabs_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val split_component
  :  ?two_columns:bool
  -> Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val safe_area_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val progress_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val semantics_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val scroll_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val collection_component
  :  ?horizontal:bool
  -> ?measured:bool
  -> Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val dividers_section : unit -> Bonsai_swiftui_ui.View.t
val images_section : unit -> Bonsai_swiftui_ui.View.t
val text_section : unit -> Bonsai_swiftui_ui.View.t
val rich_text_section : unit -> Bonsai_swiftui_ui.View.t
val symbols_section : unit -> Bonsai_swiftui_ui.View.t
val frames_section : unit -> Bonsai_swiftui_ui.View.t
val modifiers_section : unit -> Bonsai_swiftui_ui.View.t
val stacks_section : unit -> Bonsai_swiftui_ui.View.t
val overlays_section : unit -> Bonsai_swiftui_ui.View.t
val weights_section : unit -> Bonsai_swiftui_ui.View.t

val component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.Body.t Bonsai.Cont.t

val picker_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val multiple_selection_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val tag_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val button_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val projection_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val opacity_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val workflow_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val disclosure_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val group_box_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val label_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val badge_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val hover_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val civil_picker_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val menu_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val help_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t

val popover_component
  :  Driver.Handler.t
  -> Bonsai.Cont.graph
  -> Bonsai_swiftui_ui.View.t Bonsai.Cont.t
