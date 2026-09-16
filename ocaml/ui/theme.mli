(** SwiftUI environment values shared by application roots and local scopes.
    System mode and absent tint, font and control size inherit the native environment. *)
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

module Symbol_rendering : sig
  type t =
    | Monochrome
    | Hierarchical
    | Multicolor
end

module Surface_role : sig
  type t =
    | Unstyled
    | Plain
    | Material_action_group
    | Content_card
    | Inset_section
    | Translucent_sheet
    | Search
end

module Material : sig
  type t =
    | Solid
    | Thin
    | Regular
    | Ultra_thin
end

module Surface_shape : sig
  type t =
    | Rounded
    | Capsule
end

(** Sparse overrides. Unspecified values inherit the nearest scope. Colors are
    explicit application colors; omitted roles resolve to native semantic colors.
    Alpha/opacity values must be finite and in [0, 1]. Shadow X may be negative.
    Repeated role entries are rejected. Explicit widget properties win over Theme. *)
module Defaults : sig
  module Values : sig
    val symbol_size : float
    val column_spacing : float
    val interactive_minimum : float
    val content_inset : float
    val action_spacing : float
    val action_inset_horizontal : float
    val action_inset_vertical : float
    val small_corner : float
    val search_corner : float
    val card_corner : float
    val sheet_corner : float
    val border_width : float
    val shadow_radius : float
    val shadow_y : float

    module Spacing : sig
      val xs : float
      val small : float
      val medium : float
      val regular : float
      val large : float
      val xl : float
    end
  end

  type t

  val create
    :  ?symbol_size:float
    -> ?column_spacing:float
    -> ?interactive_minimum:float
    -> ?content_inset:float
    -> ?action_spacing:float
    -> ?action_inset_horizontal:float
    -> ?action_inset_vertical:float
    -> ?small_corner:float
    -> ?search_corner:float
    -> ?card_corner:float
    -> ?sheet_corner:float
    -> ?border_width:float
    -> ?shadow_radius:float
    -> ?shadow_y:float
    -> ?colors:(Style.Color_role.t * Style.Color.t) list
    -> ?text_sizes:(Style.Text_role.t * float) list
    -> ?text_weights:(Style.Text_role.t * Style.Font_weight.t) list
    -> ?foreground:Style.Color_role.t
    -> ?shadow_x:float
    -> ?shadow_alpha:float
    -> ?material_alpha:float
    -> ?symbol_rendering:Symbol_rendering.t
    -> ?text_role:Style.Text_role.t
    -> ?text_foregrounds:(Style.Text_role.t * Style.Color_role.t) list
    -> ?text_italics:(Style.Text_role.t * bool) list
    -> ?surface_materials:(Surface_role.t * Material.t) list
    -> ?surface_shapes:(Surface_role.t * Surface_shape.t) list
    -> ?surface_backgrounds:(Surface_role.t * Style.Color_role.t) list
    -> ?surface_opacities:(Surface_role.t * float) list
    -> ?surface_tint_alphas:(Surface_role.t * float) list
    -> unit
    -> t

  (* Explicit library values for constructing a baseline Theme. *)
  val standard : t
end

type t

val create
  :  ?mode:mode
  -> ?tint:Style.Color.t
  -> ?font_family:string
  -> ?control_size:Control_size.t
  -> ?defaults:Defaults.t
  -> unit
  -> t

module Private : sig
  type view =
    { mode : mode
    ; tint : int32 option
    ; font_family : string option
    ; control_size : Control_size.t option
    ; defaults : bytes
    }

  val view : t -> view
  val equal : t -> t -> bool
end
