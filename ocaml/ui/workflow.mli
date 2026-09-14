(** Controlled multi-step flows composed from native controls and retained content.
    This is a workflow, not a numeric increment/decrement control. *)
type layout =
  | Vertical
  | Horizontal

type state =
  | Pending
  | Editing
  | Complete
  | Disabled
  | Error

type step

(** Step IDs are stable among siblings. A disabled step cannot be selected.
    [on_select] is a normal Press handler owned by the application. *)
val step
  :  id:int64
  -> title:View.t
  -> content:View.t
  -> ?subtitle:View.t
  -> ?label:View.t
  -> ?state:state
  -> ?on_select:Event.Handler.t
  -> unit
  -> step

(** [current_step_id] must name one of the nonempty, uniquely identified steps.
    Horizontal headers wrap to the available width. Inactive bodies remain
    mounted but cannot receive input or accessibility actions. Reordering within
    a layout retains keyed headers and bodies. Changing layout changes structure.
    Missing Continue/Back handlers render those actions disabled. Labels can be
    localized independently of the application-owned step titles and content. *)
val create
  :  ?key:Key.t
  -> ?layout:layout
  -> current_step_id:int64
  -> ?on_continue:Event.Handler.t
  -> ?on_back:Event.Handler.t
  -> ?continue_label:string
  -> ?back_label:string
  -> step list
  -> unit
  -> View.t
