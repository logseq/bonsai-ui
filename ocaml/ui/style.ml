module Brightness = struct
  type t =
    | Light
    | Dark
end

module Color = struct
  type t = int32

  let component label value =
    if value < 0 || value > 255
    then invalid_arg (Printf.sprintf "Style.Color.%s must be between 0 and 255" label);
    value
  ;;

  let argb ~alpha ~red ~green ~blue =
    let alpha = component "alpha" alpha in
    let red = component "red" red in
    let green = component "green" green in
    let blue = component "blue" blue in
    Int32.(
      logor
        (shift_left (of_int alpha) 24)
        (logor
           (shift_left (of_int red) 16)
           (logor (shift_left (of_int green) 8) (of_int blue))))
  ;;

  let rgb ~red ~green ~blue = argb ~alpha:255 ~red ~green ~blue

  module Private = struct
    let of_argb32 value = value
    let to_argb32 t = t
  end
end

module Font_weight = struct
  type t =
    | Normal
    | Medium
    | Semi_bold
    | Bold
end

module Text_align = struct
  type t =
    | Start
    | Center
    | End
end

module Text_truncation = struct
  type t =
    | Tail
    | Head
    | Middle
end

module Text_style = struct
  type t =
    { font_size : float option
    ; font_weight : Font_weight.t option
    ; line_spacing : float option
    ; color : Color.t option
    }

  let positive_finite label = function
    | None -> None
    | Some value ->
      if (not (Float.is_finite value)) || Float.compare value 0. <= 0
      then
        invalid_arg
          (Printf.sprintf "Style.Text_style.%s must be finite and positive" label);
      Some value
  ;;

  let nonnegative_finite label = function
    | None -> None
    | Some value ->
      if (not (Float.is_finite value)) || value < 0.
      then
        invalid_arg
          (Printf.sprintf "Style.Text_style.%s must be finite and non-negative" label);
      Some value
  ;;

  let create ?font_size ?font_weight ?line_spacing ?color () =
    { font_size = positive_finite "font_size" font_size
    ; font_weight
    ; line_spacing = nonnegative_finite "line_spacing" line_spacing
    ; color
    }
  ;;

  module Private = struct
    type view =
      { font_size : float option
      ; font_weight : Font_weight.t option
      ; line_spacing : float option
      ; color : int32 option
      }

    let view (t : t) : view =
      { font_size = t.font_size
      ; font_weight = t.font_weight
      ; line_spacing = t.line_spacing
      ; color = Option.map Color.Private.to_argb32 t.color
      }
    ;;
  end
end

module Text_span = struct
  type t =
    { value : string
    ; font_size : float option
    ; font_weight : Font_weight.t option
    ; color : Color.t option
    ; italic : bool
    ; underline : bool
    ; strikethrough : bool
    }

  let create
        ?font_size
        ?font_weight
        ?color
        ?(italic = false)
        ?(underline = false)
        ?(strikethrough = false)
        value
    =
    Option.iter
      (fun size ->
         if (not (Float.is_finite size)) || size <= 0.
         then invalid_arg "Style.Text_span.font_size must be finite and positive")
      font_size;
    { value; font_size; font_weight; color; italic; underline; strikethrough }
  ;;

  module Private = struct
    type view =
      { value : string
      ; font_size : float option
      ; font_weight : Font_weight.t option
      ; color : int32 option
      ; italic : bool
      ; underline : bool
      ; strikethrough : bool
      }

    let view (t : t) : view =
      { value = t.value
      ; font_size = t.font_size
      ; font_weight = t.font_weight
      ; color = Option.map Color.Private.to_argb32 t.color
      ; italic = t.italic
      ; underline = t.underline
      ; strikethrough = t.strikethrough
      }
    ;;
  end
end

module Image_source = struct
  type t =
    | Resource of string
    | Remote of string

  let resource name =
    let parts = String.split_on_char '/' name in
    if
      String.contains name '\\'
      || String.contains name '\000'
      || List.exists (fun part -> part = "" || part = "." || part = "..") parts
    then invalid_arg "Style.Image_source.resource requires a relative resource path";
    Resource name
  ;;

  let remote value =
    let uri = Uri.of_string value in
    let valid_scheme =
      match Uri.scheme uri with
      | Some scheme -> List.mem (String.lowercase_ascii scheme) [ "http"; "https" ]
      | None -> false
    in
    if
      (not valid_scheme)
      || Option.fold ~none:true ~some:(( = ) "") (Uri.host uri)
      || String.exists (fun c -> Char.code c <= 32 || Char.code c = 127) value
    then invalid_arg "Style.Image_source.remote requires an absolute HTTP(S) URL";
    Remote value
  ;;
end

module Image_sizing = struct
  type t =
    | Original
    | Stretch
    | Fit
    | Fill
end

module Projection = struct
  type t = float array

  let matrix3 values =
    if Array.length values <> 9
    then invalid_arg "Style.Projection.matrix3 requires exactly 9 values";
    Array.iter
      (fun value ->
         if not (Float.is_finite value)
         then invalid_arg "Style.Projection.matrix3 values must be finite")
      values;
    Array.copy values
  ;;

  let identity = matrix3 [| 1.; 0.; 0.; 0.; 1.; 0.; 0.; 0.; 1. |]
  let scale ?(x = 1.) ?(y = 1.) () = matrix3 [| x; 0.; 0.; 0.; y; 0.; 0.; 0.; 1. |]
  let translate ?(x = 0.) ?(y = 0.) () = matrix3 [| 1.; 0.; 0.; 0.; 1.; 0.; x; y; 1. |]

  module Private = struct
    let to_array = Array.copy
  end
end
