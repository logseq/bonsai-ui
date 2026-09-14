(** SwiftUI environment values shared by application roots and local scopes.
    System mode and absent tint/font inherit the native environment. *)
type mode =
  | System
  | Light
  | Dark

module Control_size : sig
  type t =
    | Mini
    | Small
    | Regular
    | Large
    | Extra_large
end

type t

val create
  :  ?mode:mode
  -> ?tint:Style.Color.t
  -> ?font_family:string
  -> ?control_size:Control_size.t
  -> unit
  -> t

module Private : sig
  type view =
    { mode : mode
    ; tint : int32 option
    ; font_family : string option
    ; control_size : Control_size.t
    }

  val view : t -> view
  val equal : t -> t -> bool
end
