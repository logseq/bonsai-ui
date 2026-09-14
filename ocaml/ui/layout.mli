module Edge : sig
  type t =
    | Leading
    | Top
    | Trailing
    | Bottom
end

(** Typed layout values shared by logical widgets. *)

module Axis : sig
  type t =
    | Horizontal
    | Vertical
end

module Alignment : sig
  type t =
    | Top_start
    | Top_center
    | Top_end
    | Center_start
    | Center
    | Center_end
    | Bottom_start
    | Bottom_center
    | Bottom_end
end

module Horizontal_alignment : sig
  type t =
    | Leading
    | Center
    | Trailing
end

module Vertical_alignment : sig
  type t =
    | Top
    | Center
    | Bottom
    | First_text_baseline
    | Last_text_baseline
end

module Frame_limit : sig
  type t =
    | Points of float
    | Fill
end

(** Signed finite point distances. Leading and trailing follow the
    native layout direction; [to_sides] returns leading, top, trailing, bottom. *)
module Edge_insets : sig
  type t

  val all : float -> t
  val symmetric : ?horizontal:float -> ?vertical:float -> unit -> t
  val only : ?leading:float -> ?top:float -> ?trailing:float -> ?bottom:float -> unit -> t

  module Private : sig
    val to_sides : t -> float * float * float * float
  end
end
