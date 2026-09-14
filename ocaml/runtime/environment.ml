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

type t = snapshot Bonsai.Cont.Expert.Var.t

let zero_insets = { left = 0.; top = 0.; right = 0.; bottom = 0. }

let default =
  { viewport_width = 0.
  ; viewport_height = 0.
  ; device_pixel_ratio = 1.
  ; text_scale = 1.
  ; brightness = Light
  ; platform = "unknown"
  ; locale = "und"
  ; safe_area = zero_insets
  ; keyboard_insets = zero_insets
  ; accessible_navigation = false
  ; bold_text = false
  ; invert_colors = false
  ; disable_animations = false
  ; reduced_motion = false
  ; high_contrast = false
  ; orientation = Portrait
  ; pointer_kinds = 0
  }
;;

let value t = Bonsai.Cont.Expert.Var.value t

module Private = struct
  let create () = Bonsai.Cont.Expert.Var.create default

  let update t snapshot =
    if Bonsai.Cont.Expert.Var.get t = snapshot
    then false
    else (
      Bonsai.Cont.Expert.Var.set t snapshot;
      true)
  ;;

  let current = Bonsai.Cont.Expert.Var.get
end
