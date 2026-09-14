module Edge = struct
  type t =
    | Leading
    | Top
    | Trailing
    | Bottom
end

module Axis = struct
  type t =
    | Horizontal
    | Vertical
end

module Alignment = struct
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

module Horizontal_alignment = struct
  type t =
    | Leading
    | Center
    | Trailing
end

module Vertical_alignment = struct
  type t =
    | Top
    | Center
    | Bottom
    | First_text_baseline
    | Last_text_baseline
end

module Frame_limit = struct
  type t =
    | Points of float
    | Fill
end

module Edge_insets = struct
  type t =
    { leading : float
    ; top : float
    ; trailing : float
    ; bottom : float
    }

  let validate label value =
    match Float.classify_float value with
    | FP_normal | FP_subnormal | FP_zero -> value
    | FP_infinite | FP_nan ->
      invalid_arg (Printf.sprintf "Layout.Edge_insets.%s must be finite" label)
  ;;

  let only ?(leading = 0.) ?(top = 0.) ?(trailing = 0.) ?(bottom = 0.) () =
    { leading = validate "leading" leading
    ; top = validate "top" top
    ; trailing = validate "trailing" trailing
    ; bottom = validate "bottom" bottom
    }
  ;;

  let all value = only ~leading:value ~top:value ~trailing:value ~bottom:value ()

  let symmetric ?(horizontal = 0.) ?(vertical = 0.) () =
    only ~leading:horizontal ~top:vertical ~trailing:horizontal ~bottom:vertical ()
  ;;

  module Private = struct
    let to_sides t = t.leading, t.top, t.trailing, t.bottom
  end
end
