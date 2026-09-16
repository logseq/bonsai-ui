(** Typed visual style values. *)

module Brightness : sig
  type t =
    | Light
    | Dark
end

module Color : sig
  type t

  val argb : alpha:int -> red:int -> green:int -> blue:int -> t
  val rgb : red:int -> green:int -> blue:int -> t

  module Private : sig
    val of_argb32 : int32 -> t
    val to_argb32 : t -> int32
  end
end

module Font_weight : sig
  type t =
    | Normal
    | Medium
    | Semi_bold
    | Bold
end

module Text_align : sig
  type t =
    | Start
    | Center
    | End
end

(** Native truncation position when text does not fit its available space. *)
module Text_truncation : sig
  type t =
    | Tail
    | Head
    | Middle
end

module Text_role : sig
  type t =
    | Body
    | Page_title
    | Sheet_title
    | Editor_title
    | Empty_title
    | Caption
    | Hint
    | Section_label

  module Private : sig
    val to_int : t -> int
  end
end

module Color_role : sig
  type t =
    | Primary
    | Secondary
    | Page
    | Card
    | Inset
    | Search
    | Border
    | Shadow
    | Material_tint

  module Private : sig
    val to_int : t -> int
  end
end

module Text_style : sig
  type t

  (** Optional font size is positive and finite. Line spacing is a finite,
      non-negative point distance between lines, not a line-height multiplier.
      Explicit attributes override the selected semantic role. Omitted role and italic
      inherit Theme. The library baseline selects Body; Hint and Section_label use
      secondary foreground. Line spacing inherits unless supplied. Native Dynamic Type and legibility settings remain active. *)
  val create
    :  ?font_size:float
    -> ?font_weight:Font_weight.t
    -> ?line_spacing:float
    -> ?color:Color.t
    -> ?role:Text_role.t
    -> ?foreground:Color_role.t
    -> ?italic:bool
    -> unit
    -> t

  module Private : sig
    type view =
      { font_size : float option
      ; font_weight : Font_weight.t option
      ; line_spacing : float option
      ; color : int32 option
      ; role : int
      ; foreground : int option
      ; italic : bool option
      }

    val view : t -> view
  end
end

(** A styled run in a single native attributed-text paragraph. Omitted font and
    color and italic attributes inherit the surrounding Theme/environment. Decoration flags add
    emphasis to this run. The optional point size must be finite and positive. *)
module Text_span : sig
  type t

  val create
    :  ?font_size:float
    -> ?font_weight:Font_weight.t
    -> ?color:Color.t
    -> ?italic:bool
    -> ?underline:bool
    -> ?strikethrough:bool
    -> string
    -> t

  module Private : sig
    type view =
      { value : string
      ; font_size : float option
      ; font_weight : Font_weight.t option
      ; color : int32 option
      ; italic : bool option
      ; underline : bool
      ; strikethrough : bool
      }

    val view : t -> view
  end
end

module Image_source : sig
  type t = private
    | Resource of string
    | Remote of string

  (** A file relative to the application's resource directory; traversal is invalid. *)
  val resource : string -> t

  (** An absolute HTTP(S) URL. The native host owns asynchronous loading. *)
  val remote : string -> t
end

module Image_sizing : sig
  type t =
    | Original
    | Stretch
    | Fit
    | Fill
end

(** Native SwiftUI plane projection. Transformations affect drawing rather than
    the parent layout measurement. *)
module Projection : sig
  type t

  val identity : t
  val scale : ?x:float -> ?y:float -> unit -> t
  val translate : ?x:float -> ?y:float -> unit -> t

  (** Copy nine finite coefficients in native field order:
      [m11; m12; m13; m21; m22; m23; m31; m32; m33]. *)
  val matrix3 : float array -> t

  module Private : sig
    val to_array : t -> float array
  end
end
