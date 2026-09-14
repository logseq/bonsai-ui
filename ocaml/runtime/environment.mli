(** Dynamic native host environment exposed as a Bonsai input. *)

type edge_insets =
  { left : float
  ; top : float
  ; right : float
  ; bottom : float
  }

type brightness =
  | Light
  | Dark

type orientation =
  | Portrait
  | Landscape

type snapshot =
  { viewport_width : float
  ; viewport_height : float
  ; device_pixel_ratio : float
  ; text_scale : float
  ; brightness : brightness
  ; platform : string
  ; locale : string
  ; safe_area : edge_insets
  ; keyboard_insets : edge_insets
  ; accessible_navigation : bool
  ; bold_text : bool
  ; invert_colors : bool
  ; disable_animations : bool
  ; reduced_motion : bool
  ; high_contrast : bool
  ; orientation : orientation
  ; pointer_kinds : int
  }

type t

val value : t -> snapshot Bonsai.Cont.t

module Private : sig
  val create : unit -> t
  val update : t -> snapshot -> bool
  val current : t -> snapshot
end
