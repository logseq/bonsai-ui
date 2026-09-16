type mode =
  | System
  | Light
  | Dark

module Symbol_rendering = struct
  type t =
    | Monochrome
    | Hierarchical
    | Multicolor

  let to_int = function
    | Monochrome -> 0
    | Hierarchical -> 1
    | Multicolor -> 2
  ;;
end

module Surface_role = struct
  type t =
    | Unstyled
    | Plain
    | Material_action_group
    | Content_card
    | Inset_section
    | Translucent_sheet
    | Search

  let to_int = function
    | Unstyled -> 0
    | Plain -> 1
    | Material_action_group -> 2
    | Content_card -> 3
    | Inset_section -> 4
    | Translucent_sheet -> 5
    | Search -> 6
  ;;
end

module Material = struct
  type t =
    | Solid
    | Thin
    | Regular
    | Ultra_thin

  let to_int = function
    | Solid -> 0
    | Thin -> 1
    | Regular -> 2
    | Ultra_thin -> 3
  ;;
end

module Surface_shape = struct
  type t =
    | Rounded
    | Capsule

  let to_int = function
    | Rounded -> 0
    | Capsule -> 1
  ;;
end

module Defaults = struct
  (* BEGIN OCAML THEME DEFAULT VALUES *)
  module Values = struct
    let symbol_size = 19.
    let column_spacing = 16.
    let interactive_minimum = 44.
    let content_inset = 16.
    let action_spacing = 2.
    let action_inset_horizontal = 6.
    let action_inset_vertical = 2.
    let small_corner = 8.
    let search_corner = 10.
    let card_corner = 20.
    let sheet_corner = 28.
    let border_width = 0.7
    let shadow_radius = 14.
    let shadow_y = 6.

    let metrics =
      [| symbol_size
       ; column_spacing
       ; interactive_minimum
       ; content_inset
       ; action_spacing
       ; action_inset_horizontal
       ; action_inset_vertical
       ; small_corner
       ; search_corner
       ; card_corner
       ; sheet_corner
       ; border_width
       ; shadow_radius
       ; shadow_y
      |]
    ;;

    let shadow_x = 0.
    let shadow_alpha = 0.16
    let material_alpha = 0.12
    let extra_metrics = [| shadow_x; shadow_alpha; material_alpha |]
    let text_sizes = [| 17.; 24.; 19.; 22.; 20.; 14.; 13.; 12. |]
    let text_weights = [| 0; 3; 1; 3; 3; 0; 0; 0 |]

    (* -1 inherits the scope foreground. *)
    let text_foregrounds = [| -1; -1; -1; -1; -1; -1; 1; 1 |]
    let text_italics = [| 0; 0; 0; 0; 0; 0; 0; 0 |]
    let foreground = 0
    let text_role = 0
    let symbol_rendering = 0

    (* Unstyled, Plain, Material_action_group, Content_card, Inset_section,
       Translucent_sheet, Search. Background 9 denotes transparent paint. *)
    let surface_materials = [| 0; 0; 1; 0; 0; 3; 0 |]
    let surface_shapes = [| 0; 0; 1; 0; 0; 0; 0 |]
    let surface_backgrounds = [| 9; 2; 8; 3; 4; 8; 5 |]
    let surface_tint_alphas = [| -1.; -1.; -1.; -1.; -1.; 0.; -1. |]
    let surface_opacities = [| 1.; 1.; 1.; 1.; 1.; 0.4; 1. |]

    module Spacing = struct
      let xs = 4.
      let small = 8.
      let medium = 12.
      let regular = 16.
      let large = 24.
      let xl = 32.
    end
  end

  (* END OCAML THEME DEFAULT VALUES *)
  type t = bytes

  let create
        ?symbol_size
        ?column_spacing
        ?interactive_minimum
        ?content_inset
        ?action_spacing
        ?action_inset_horizontal
        ?action_inset_vertical
        ?small_corner
        ?search_corner
        ?card_corner
        ?sheet_corner
        ?border_width
        ?shadow_radius
        ?shadow_y
        ?(colors = [])
        ?(text_sizes = [])
        ?(text_weights = [])
        ?foreground
        ?shadow_x
        ?shadow_alpha
        ?material_alpha
        ?symbol_rendering
        ?text_role
        ?(text_foregrounds = [])
        ?(text_italics = [])
        ?(surface_materials = [])
        ?(surface_shapes = [])
        ?(surface_backgrounds = [])
        ?(surface_opacities = [])
        ?(surface_tint_alphas = [])
        ()
    =
    let buffer = Buffer.create 128 in
    let byte n = Buffer.add_char buffer (Char.chr n) in
    let optional write = function
      | None -> byte 0
      | Some v ->
        byte 1;
        write v
    in
    let floating v =
      let b = Bytes.create 8 in
      Bytes.set_int64_le b 0 (Int64.bits_of_float v);
      Buffer.add_bytes buffer b
    in
    let numeric positive v =
      Option.iter
        (fun v ->
           if (not (Float.is_finite v)) || if positive then v <= 0. else v < 0.
           then invalid_arg "Theme.Defaults: invalid metric")
        v;
      optional floating v
    in
    List.iteri
      (fun i v -> numeric (i = 0 || i = 2) v)
      [ symbol_size
      ; column_spacing
      ; interactive_minimum
      ; content_inset
      ; action_spacing
      ; action_inset_horizontal
      ; action_inset_vertical
      ; small_corner
      ; search_corner
      ; card_corner
      ; sheet_corner
      ; border_width
      ; shadow_radius
      ; shadow_y
      ];
    let unique convert values =
      let ids = List.map (fun (role, _) -> convert role) values in
      if List.length (List.sort_uniq Int.compare ids) <> List.length ids
      then invalid_arg "Theme.Defaults: duplicate role";
      List.map (fun (role, value) -> convert role, value) values
    in
    let colors = unique Style.Color_role.Private.to_int colors in
    for i = 0 to 8 do
      optional
        (fun c ->
           let b = Bytes.create 4 in
           Bytes.set_int32_le b 0 (Style.Color.Private.to_argb32 c);
           Buffer.add_bytes buffer b)
        (List.assoc_opt i colors)
    done;
    let sizes = unique Style.Text_role.Private.to_int text_sizes in
    let weights = unique Style.Text_role.Private.to_int text_weights in
    for i = 0 to 7 do
      numeric true (List.assoc_opt i sizes);
      optional
        (fun w ->
           byte
             (match w with
              | Style.Font_weight.Normal -> 0
              | Medium -> 1
              | Semi_bold -> 2
              | Bold -> 3))
        (List.assoc_opt i weights)
    done;
    optional (fun role -> byte (Style.Color_role.Private.to_int role)) foreground;
    let opacity value =
      Option.iter
        (fun v ->
           if (not (Float.is_finite v)) || v < 0. || v > 1.
           then invalid_arg "Theme.Defaults: opacity must be finite and in [0, 1]")
        value;
      optional floating value
    in
    Option.iter
      (fun v ->
         if not (Float.is_finite v) then invalid_arg "Theme.Defaults: nonfinite shadow X")
      shadow_x;
    optional floating shadow_x;
    opacity shadow_alpha;
    opacity material_alpha;
    optional (fun v -> byte (Symbol_rendering.to_int v)) symbol_rendering;
    optional (fun v -> byte (Style.Text_role.Private.to_int v)) text_role;
    let text_foregrounds = unique Style.Text_role.Private.to_int text_foregrounds in
    let text_italics = unique Style.Text_role.Private.to_int text_italics in
    for i = 0 to 7 do
      optional
        (fun v -> byte (Style.Color_role.Private.to_int v))
        (List.assoc_opt i text_foregrounds);
      optional (fun v -> byte (if v then 1 else 0)) (List.assoc_opt i text_italics)
    done;
    let materials = unique Surface_role.to_int surface_materials in
    let shapes = unique Surface_role.to_int surface_shapes in
    let backgrounds = unique Surface_role.to_int surface_backgrounds in
    let opacities = unique Surface_role.to_int surface_opacities in
    let tint_alphas = unique Surface_role.to_int surface_tint_alphas in
    for i = 0 to 6 do
      optional (fun v -> byte (Material.to_int v)) (List.assoc_opt i materials);
      optional (fun v -> byte (Surface_shape.to_int v)) (List.assoc_opt i shapes);
      optional
        (fun v -> byte (Style.Color_role.Private.to_int v))
        (List.assoc_opt i backgrounds);
      opacity (List.assoc_opt i opacities);
      opacity (List.assoc_opt i tint_alphas)
    done;
    Bytes.of_string (Buffer.contents buffer)
  ;;

  let standard =
    let text_roles =
      [| Style.Text_role.Body
       ; Page_title
       ; Sheet_title
       ; Editor_title
       ; Empty_title
       ; Caption
       ; Hint
       ; Section_label
      |]
    in
    let color_roles =
      [| Style.Color_role.Primary
       ; Secondary
       ; Page
       ; Card
       ; Inset
       ; Search
       ; Border
       ; Shadow
       ; Material_tint
      |]
    in
    let surfaces =
      [| Surface_role.Unstyled
       ; Plain
       ; Material_action_group
       ; Content_card
       ; Inset_section
       ; Translucent_sheet
       ; Search
      |]
    in
    let entries roles values f =
      Array.to_list (Array.mapi (fun i value -> roles.(i), f value) values)
    in
    let optional_entries roles values =
      Array.to_list
        (Array.mapi
           (fun i value ->
              if value < 0 || value >= Array.length color_roles
              then None
              else Some (roles.(i), color_roles.(value)))
           values)
      |> List.filter_map Fun.id
    in
    create
      ~symbol_size:Values.metrics.(0)
      ~column_spacing:Values.metrics.(1)
      ~interactive_minimum:Values.metrics.(2)
      ~content_inset:Values.metrics.(3)
      ~action_spacing:Values.metrics.(4)
      ~action_inset_horizontal:Values.metrics.(5)
      ~action_inset_vertical:Values.metrics.(6)
      ~small_corner:Values.metrics.(7)
      ~search_corner:Values.metrics.(8)
      ~card_corner:Values.metrics.(9)
      ~sheet_corner:Values.metrics.(10)
      ~border_width:Values.metrics.(11)
      ~shadow_radius:Values.metrics.(12)
      ~shadow_y:Values.metrics.(13)
      ~shadow_x:Values.extra_metrics.(0)
      ~shadow_alpha:Values.extra_metrics.(1)
      ~material_alpha:Values.extra_metrics.(2)
      ~symbol_rendering:
        [| Symbol_rendering.Monochrome; Hierarchical; Multicolor |].(Values
                                                                     .symbol_rendering)
      ~foreground:color_roles.(Values.foreground)
      ~text_role:text_roles.(Values.text_role)
      ~text_sizes:(entries text_roles Values.text_sizes Fun.id)
      ~text_weights:
        (entries text_roles Values.text_weights (fun i ->
           [| Style.Font_weight.Normal; Medium; Semi_bold; Bold |].(i)))
      ~text_foregrounds:(optional_entries text_roles Values.text_foregrounds)
      ~text_italics:(entries text_roles Values.text_italics (( = ) 1))
      ~surface_materials:
        (entries surfaces Values.surface_materials (fun i ->
           [| Material.Solid; Thin; Regular; Ultra_thin |].(i)))
      ~surface_shapes:
        (entries surfaces Values.surface_shapes (fun i ->
           if i = 1 then Surface_shape.Capsule else Rounded))
      ~surface_backgrounds:(optional_entries surfaces Values.surface_backgrounds)
      ~surface_opacities:(entries surfaces Values.surface_opacities Fun.id)
      ~surface_tint_alphas:
        (entries surfaces Values.surface_tint_alphas Fun.id
         |> List.filter (fun (_, v) -> v >= 0.))
      ()
  ;;
end

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
  ; control_size : Control_size.t option
  ; defaults : bytes
  }

let create
      ?(mode = System)
      ?tint
      ?font_family
      ?control_size
      ?(defaults = Defaults.create ())
      ()
  =
  Option.iter
    (fun value ->
       if String.trim value = "" || String.contains value '\000'
       then invalid_arg "Theme.create: font family must be non-empty and contain no NUL")
    font_family;
  { mode
  ; tint = Option.map Style.Color.Private.to_argb32 tint
  ; font_family
  ; control_size
  ; defaults = Bytes.copy defaults
  }
;;

module Private = struct
  type view = t =
    { mode : mode
    ; tint : int32 option
    ; font_family : string option
    ; control_size : Control_size.t option
    ; defaults : bytes
    }

  let view t = t
  let equal = ( = )
end
