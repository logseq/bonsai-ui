type mode =
  | System
  | Light
  | Dark

module Control_size = struct
  type t =
    | Mini
    | Small
    | Regular
    | Large
    | Extra_large
end

type t =
  { mode : mode
  ; tint : int32 option
  ; font_family : string option
  ; control_size : Control_size.t
  }

let create ?(mode = System) ?tint ?font_family ?(control_size = Control_size.Regular) () =
  Option.iter
    (fun value ->
       if String.trim value = "" || String.contains value '\000'
       then invalid_arg "Theme.create: font family must be non-empty and contain no NUL")
    font_family;
  { mode
  ; tint = Option.map Style.Color.Private.to_argb32 tint
  ; font_family
  ; control_size
  }
;;

module Private = struct
  type view = t =
    { mode : mode
    ; tint : int32 option
    ; font_family : string option
    ; control_size : Control_size.t
    }

  let view t = t
  let equal = ( = )
end
