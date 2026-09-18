module ID = Bonsai_swiftui_spec.Id

type error_code =
  | Invalid_magic
  | Unsupported_version
  | Invalid_header
  | Invalid_frame_kind
  | Invalid_flags
  | Invalid_payload_length
  | Frame_too_large
  | Too_many_operations
  | String_too_large
  | Unknown_operation
  | Unknown_node_kind
  | Invalid_props
  | Invalid_utf8
  | Invalid_operation_order
  | Truncated_input
  | Trailing_bytes
  | Application_payload_too_large

type error =
  { code : error_code
  ; message : string
  }

exception Codec_error of error

open Wire_frame

let fail code format =
  Printf.ksprintf (fun message -> raise (Codec_error { code; message })) format
;;

module Writer = struct
  let create () = Buffer.create 128
  let length = Buffer.length
  let u8 buffer value = Buffer.add_char buffer (Char.chr (value land 0xff))

  let u16 buffer value =
    u8 buffer value;
    u8 buffer (value lsr 8)
  ;;

  let u32 buffer value =
    u8 buffer value;
    u8 buffer (value lsr 8);
    u8 buffer (value lsr 16);
    u8 buffer (value lsr 24)
  ;;

  let u64 buffer value =
    for shift = 0 to 7 do
      Int64.(shift_right_logical value (shift * 8) |> to_int) |> u8 buffer
    done
  ;;

  let f64 buffer value = u64 buffer (Int64.bits_of_float value)
  let bytes buffer value = Buffer.add_bytes buffer value
  let string buffer value = Buffer.add_string buffer value
  let contents buffer = Buffer.to_bytes buffer
end

module Runtime_encoded_frame = struct
  type stats_offsets =
    { encode_ns : int
    ; patch_bytes : int
    }

  type t =
    { bytes : bytes
    ; stats_offsets : stats_offsets
    }

  let bytes t = t.bytes
end

let check_u16 label value =
  if value < 0 || value > 0xffff then fail Invalid_props "%s is outside u16" label
;;

let check_u32 label value =
  if value < 0 || Int64.compare (Int64.of_int value) 0xffffffffL > 0
  then fail Invalid_props "%s is outside u32" label
;;

let check_sheet_properties
      ~fullscreen
      ~detents
      ~initial
      ~interactive
      ~indicator
      ~sizing
      ~fraction
  =
  if
    detents < 1
    || detents > 7
    || initial < 0
    || initial > 2
    || detents land (1 lsl initial) = 0
    || (not (Float.is_finite fraction))
    || (if detents land 4 <> 0 then fraction <= 0. || fraction > 1. else fraction <> 0.)
    || sizing < 0
    || sizing > 3
    || (fullscreen
        && (detents <> 2 || initial <> 1 || interactive || indicator || sizing <> 0))
  then fail Invalid_props "invalid sheet configuration"
;;

let check_button_properties ~role ~style =
  if role < 0 || role > 2 then fail Invalid_props "invalid button role %d" role;
  if style < 0 || style > 3 then fail Invalid_props "invalid button style %d" style
;;

let check_symbol_properties ~name ~size ~rendering =
  if
    String.length name = 0
    || not
         (String.for_all
            (function
              | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '.' | '_' -> true
              | _ -> false)
            name)
  then fail Invalid_props "invalid SF Symbols system name";
  Option.iter
    (fun size ->
       if (not (Float.is_finite size)) || Float.compare size 0. <= 0
       then fail Invalid_props "symbol size must be finite and positive")
    size;
  if rendering < 0 || rendering > 3
  then fail Invalid_props "invalid symbol rendering mode"
;;

let check_u64 label value =
  if Int64.compare value 0L < 0 then fail Invalid_props "%s must be non-negative" label
;;

let validate_surface_dimension value =
  if (not (Float.is_finite value)) || Float.compare value 0. < 0
  then fail Invalid_props "surface dimension must be finite and non-negative"
;;

let validate_opacity value =
  if
    (not (Float.is_finite value))
    || Float.compare value 0. < 0
    || Float.compare value 1. > 0
  then fail Invalid_props "opacity must be finite and in 0..1"
;;

let validate_spacer_minimum =
  Option.iter (fun value ->
    if (not (Float.is_finite value)) || Float.compare value 0. < 0
    then fail Invalid_props "spacer minimum must be finite and non-negative")
;;

let validate_frame (frame : frame_props) =
  let validate_axis fixed minimum ideal maximum =
    let maximum_points =
      match maximum with
      | None | Some Fill_space -> None
      | Some (Points value) -> Some value
    in
    List.iter
      (Option.iter (fun value ->
         if (not (Float.is_finite value)) || Float.compare value 0. < 0
         then fail Invalid_props "frame dimensions must be finite and non-negative"))
      [ fixed; minimum; ideal; maximum_points ];
    if
      Option.is_some fixed
      && (Option.is_some minimum || Option.is_some ideal || Option.is_some maximum)
    then fail Invalid_props "fixed and flexible frame dimensions conflict";
    List.iter
      (function
        | Some lower, Some upper when Float.compare lower upper > 0 ->
          fail Invalid_props "frame minimum, ideal and maximum must be ordered"
        | _ -> ())
      [ minimum, ideal; minimum, maximum_points; ideal, maximum_points ]
  in
  validate_axis frame.width frame.min_width frame.ideal_width frame.max_width;
  validate_axis frame.height frame.min_height frame.ideal_height frame.max_height
;;

let write_string writer value =
  let length = String.length value in
  if length > Generated_protocol.Limits.max_string_bytes
  then fail String_too_large "string is %d bytes" length;
  Writer.u32 writer length;
  Writer.string writer value
;;

let write_bool writer value = Writer.u8 writer (if value then 1 else 0)

let write_optional_string writer = function
  | None -> Writer.u8 writer 0
  | Some value ->
    Writer.u8 writer 1;
    write_string writer value
;;

let write_optional_bool writer = function
  | None -> Writer.u8 writer 0
  | Some false -> Writer.u8 writer 1
  | Some true -> Writer.u8 writer 2
;;

let write_optional_f64 writer = function
  | None -> Writer.u8 writer 0
  | Some value ->
    Writer.u8 writer 1;
    Writer.f64 writer value
;;

let write_optional_u8 writer = function
  | None -> Writer.u8 writer 0
  | Some value ->
    check_u16 "optional u8" value;
    if value > 0xff then fail Invalid_props "optional u8 is outside u8";
    Writer.u8 writer 1;
    Writer.u8 writer value
;;

let write_optional_argb32 writer = function
  | None -> Writer.u8 writer 0
  | Some value ->
    Writer.u8 writer 1;
    Writer.u32 writer (Int32.to_int value)
;;

let text_font_weight_id = function
  | Wire_frame.Normal -> 0
  | Medium -> 1
  | Semi_bold -> 2
  | Bold -> 3
;;

let text_align_id = function
  | Wire_frame.Start -> 0
  | Center_text -> 1
  | End -> 2
;;

let text_truncation_id = function
  | Wire_frame.Tail -> 0
  | Head -> 1
  | Middle -> 2
;;

let write_text_style writer = function
  | None -> Writer.u8 writer 0
  | Some (style : Wire_frame.text_style) ->
    Option.iter
      (fun size ->
         if (not (Float.is_finite size)) || size <= 0.
         then fail Invalid_props "text font size must be finite and positive")
      style.font_size;
    Option.iter
      (fun spacing ->
         if (not (Float.is_finite spacing)) || spacing < 0.
         then fail Invalid_props "text line spacing must be finite and non-negative")
      style.line_spacing;
    Writer.u8 writer 1;
    write_optional_f64 writer style.font_size;
    (match style.font_weight with
     | None -> Writer.u8 writer 0
     | Some weight ->
       Writer.u8 writer 1;
       Writer.u8 writer (text_font_weight_id weight));
    write_optional_f64 writer style.line_spacing;
    write_optional_argb32 writer style.color;
    if style.role < 0 || style.role > 8 then fail Invalid_props "invalid text role";
    Writer.u8 writer style.role;
    (match style.foreground with
     | None -> Writer.u8 writer 0
     | Some role ->
       if role < 0 || role > 8 then fail Invalid_props "invalid foreground role";
       Writer.u8 writer 1;
       Writer.u8 writer role);
    Writer.u8
      writer
      (match style.italic with
       | None -> 2
       | Some true -> 1
       | Some false -> 0)
;;

let write_text_span writer (span : Wire_frame.text_span) =
  Option.iter
    (fun size ->
       if (not (Float.is_finite size)) || size <= 0.
       then fail Invalid_props "text span font size must be finite and positive")
    span.font_size;
  write_string writer span.value;
  write_optional_f64 writer span.font_size;
  (match span.font_weight with
   | None -> Writer.u8 writer 0
   | Some weight ->
     Writer.u8 writer 1;
     Writer.u8 writer (text_font_weight_id weight));
  write_optional_argb32 writer span.color;
  Writer.u8
    writer
    (match span.italic with
     | None -> 2
     | Some true -> 1
     | Some false -> 0);
  write_bool writer span.underline;
  write_bool writer span.strikethrough
;;

let require_theme_font_name label value =
  if String.length (String.trim value) = 0 || String.contains value '\000'
  then fail Invalid_props "%s must be non-empty and contain no NUL" label
;;

let validate_ui_defaults bytes =
  let position = ref 0 in
  let take n =
    if !position + n > Bytes.length bytes then fail Invalid_props "truncated UI defaults";
    let offset = !position in
    position := !position + n;
    offset
  in
  let byte () = Char.code (Bytes.get bytes (take 1)) in
  let choice limit =
    let value = byte () in
    if value > limit then fail Invalid_props "invalid UI defaults choice";
    value
  in
  let optional f = if choice 1 = 1 then f () in
  let number positive () =
    let value = Int64.float_of_bits (Bytes.get_int64_le bytes (take 8)) in
    if (not (Float.is_finite value)) || if positive then value <= 0. else value < 0.
    then fail Invalid_props "invalid UI defaults metric"
  in
  for i = 0 to 13 do
    optional (number (i = 0 || i = 2))
  done;
  for _ = 0 to 8 do
    optional (fun () -> ignore (take 4))
  done;
  for _ = 0 to 7 do
    optional (number true);
    optional (fun () -> ignore (choice 3))
  done;
  optional (fun () -> ignore (choice 8));
  let finite () =
    let value = Int64.float_of_bits (Bytes.get_int64_le bytes (take 8)) in
    if not (Float.is_finite value) then fail Invalid_props "nonfinite theme value";
    value
  in
  let opacity () =
    let value = finite () in
    if value < 0. || value > 1. then fail Invalid_props "invalid theme opacity"
  in
  optional (fun () -> ignore (finite ()));
  optional opacity;
  optional opacity;
  optional (fun () -> ignore (choice 2));
  optional (fun () -> ignore (choice 7));
  for _ = 0 to 7 do
    optional (fun () -> ignore (choice 8));
    optional (fun () -> ignore (choice 1))
  done;
  for _ = 0 to 6 do
    optional (fun () -> ignore (choice 3));
    optional (fun () -> ignore (choice 1));
    optional (fun () -> ignore (choice 8));
    optional opacity;
    optional opacity
  done;
  if !position <> Bytes.length bytes then fail Invalid_props "trailing UI defaults bytes"
;;

let write_theme writer (theme : Wire_frame.theme) =
  validate_ui_defaults theme.defaults;
  Option.iter (require_theme_font_name "theme font family") theme.font_family;
  if theme.control_size < 0 || theme.control_size > 5
  then fail Invalid_props "invalid control size %d" theme.control_size;
  Writer.u8
    writer
    (match theme.mode with
     | System -> 0
     | Light -> 1
     | Dark -> 2);
  write_optional_argb32 writer theme.tint;
  write_optional_string writer theme.font_family;
  Writer.u8 writer theme.control_size;
  Writer.u16 writer (Bytes.length theme.defaults);
  Writer.bytes writer theme.defaults
;;

let write_optional_u32 writer label = function
  | None -> Writer.u8 writer 0
  | Some value ->
    check_u32 label value;
    if value = 0 then fail Invalid_props "%s must be positive" label;
    Writer.u8 writer 1;
    Writer.u32 writer value
;;

let write_text_props
      writer
      ({ value; style; text_align; line_limit; truncation } : Wire_frame.text_props)
  =
  write_string writer value;
  write_text_style writer style;
  Writer.u8 writer (text_align_id text_align);
  write_optional_u32 writer "text line limit" line_limit;
  Writer.u8 writer (text_truncation_id truncation)
;;

let alignment_id (alignment : Wire_frame.alignment) =
  match alignment with
  | Wire_frame.Top_start -> 0
  | Top_center -> 1
  | Top_end -> 2
  | Center_start -> 3
  | Center -> 4
  | Center_end -> 5
  | Bottom_start -> 6
  | Bottom_center -> 7
  | Bottom_end -> 8
;;

let write_frame_limit writer = function
  | None -> Writer.u8 writer 0
  | Some (Points value) ->
    Writer.u8 writer 1;
    Writer.f64 writer value
  | Some Fill_space -> Writer.u8 writer 2
;;

let write_frame_props writer (frame : frame_props) =
  validate_frame frame;
  write_optional_f64 writer frame.width;
  write_optional_f64 writer frame.height;
  write_optional_f64 writer frame.min_width;
  write_optional_f64 writer frame.ideal_width;
  write_frame_limit writer frame.max_width;
  write_optional_f64 writer frame.min_height;
  write_optional_f64 writer frame.ideal_height;
  write_frame_limit writer frame.max_height;
  Writer.u8 writer (alignment_id frame.alignment)
;;

let check_image_source = function
  | Wire_frame.Resource name ->
    if
      String.contains name '\\'
      || String.contains name '\000'
      || List.exists
           (fun part -> part = "" || part = "." || part = "..")
           (String.split_on_char '/' name)
    then fail Invalid_props "invalid image resource path"
  | Remote value ->
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
    then fail Invalid_props "invalid image HTTP(S) URL"
;;

let write_image_props writer source sizing scale =
  check_image_source source;
  if (not (Float.is_finite scale)) || scale <= 0.
  then fail Invalid_props "invalid image scale";
  (match source with
   | Wire_frame.Resource name ->
     Writer.u8 writer 0;
     write_string writer name
   | Remote url ->
     Writer.u8 writer 1;
     write_string writer url);
  Writer.u8
    writer
    (match (sizing : Wire_frame.image_sizing) with
     | Original -> 0
     | Stretch -> 1
     | Fit -> 2
     | Fill -> 3);
  Writer.f64 writer scale
;;

let animation_curve_id = function
  | Wire_frame.Linear -> 0
  | Ease_in -> 1
  | Ease_out -> 2
  | Ease_in_out -> 3
;;

let write_animation writer { id; duration_ms; curve } =
  let id = ID.Ui.Animation_id.to_int64 id in
  check_u64 "animation id" id;
  check_u32 "animation duration" duration_ms;
  Writer.u64 writer id;
  Writer.u32 writer duration_ms;
  Writer.u8 writer (animation_curve_id curve)
;;

let semantics_role_id = function
  | Wire_frame.Generic -> 0
  | Semantics_button -> 1
  | Link -> 2
  | Image -> 3
  | Header -> 4
  | Semantics_toggle -> 5
  | Static_text -> 6
;;

let text_update_mode_id = function
  | Wire_frame.Ack -> 0
  | Correction -> 1
  | Force_replace -> 2
;;

let validate_slider ~value ~min ~max ~step =
  if
    not
      (Float.is_finite value
       && Float.is_finite min
       && Float.is_finite max
       && Float.is_finite (max -. min))
  then fail Invalid_props "slider domain must be finite";
  if min >= max || value < min || value > max
  then fail Invalid_props "invalid slider domain or value";
  match step with
  | Some step
    when (not (Float.is_finite step))
         || step <= 0.
         || step > max -. min
         || min +. step <= min
         || max -. step >= max -> fail Invalid_props "invalid slider step"
  | _ -> ()
;;

let write_slider_fields
      writer
      ~lower
      ~upper
      ~min
      ~max
      ~step
      ~enabled
      ~vertical
      ~has_on_change
      ~label
      ~upper_label
  =
  validate_slider ~value:lower ~min ~max ~step;
  Option.iter
    (fun upper ->
       validate_slider ~value:upper ~min ~max ~step;
       if lower > upper then fail Invalid_props "reversed slider interval")
    upper;
  if
    label = ""
    || upper_label = Some ""
    || Option.is_some upper <> Option.is_some upper_label
  then fail Invalid_props "invalid slider labels";
  Writer.f64 writer lower;
  Option.iter (Writer.f64 writer) upper;
  Writer.f64 writer min;
  Writer.f64 writer max;
  write_optional_f64 writer step;
  write_bool writer enabled;
  write_bool writer vertical;
  write_bool writer has_on_change;
  write_string writer label;
  Option.iter (write_string writer) upper_label
;;

let validate_progress_style value style =
  if style < 0 || style > 2 || (style = 0 && value = None) || (style = 1 && value <> None)
  then fail Invalid_props "unsupported system progress mode"
;;

let write_separator writer separator =
  if separator < 0 || separator > 2 then fail Invalid_props "invalid list separator";
  Writer.u8 writer separator
;;

let validate_progress_value = function
  | None -> ()
  | Some value
    when Float.is_finite value
         && Float.compare value 0. >= 0
         && Float.compare value 1. <= 0 -> ()
  | Some _ -> fail Invalid_props "progress value must be finite and in 0..1"
;;

let validate_picker ~selected_id ~label ~style options =
  if style < 0 || style > 3 then fail Invalid_props "invalid picker style";
  if String.trim label = "" then fail Invalid_props "picker label must not be empty";
  if List.length options > 256 then fail Invalid_props "picker option limit exceeded";
  let ids = Hashtbl.create (List.length options) in
  List.iter
    (fun (option : Wire_frame.picker_option) ->
       if Hashtbl.mem ids option.option_id
       then fail Invalid_props "picker option IDs must be unique";
       Hashtbl.add ids option.option_id ())
    options;
  match selected_id with
  | Some selected_id when not (Hashtbl.mem ids selected_id) ->
    fail Invalid_props "selected picker ID must be present in options"
  | None | Some _ -> ()
;;

let is_utf16_boundary text target =
  if target < 0
  then false
  else (
    let byte_length = String.length text in
    let rec loop byte_offset utf16_offset =
      if utf16_offset = target
      then true
      else if byte_offset = byte_length || utf16_offset > target
      then false
      else (
        let decoded = String.get_utf_8_uchar text byte_offset in
        if not (Uchar.utf_decode_is_valid decoded)
        then fail Invalid_utf8 "text is not valid UTF-8";
        let scalar = Uchar.utf_decode_uchar decoded in
        loop
          (byte_offset + Uchar.utf_decode_length decoded)
          (utf16_offset + if Uchar.to_int scalar > 0xffff then 2 else 1))
    in
    loop 0 0)
;;

let validate_text_range text (range : Wire_frame.text_range) =
  if range.start_utf16 > range.end_utf16 then fail Invalid_props "text range is reversed";
  if
    not
      (is_utf16_boundary text range.start_utf16 && is_utf16_boundary text range.end_utf16)
  then fail Invalid_props "text range is not on a UTF-16 boundary"
;;

let write_text_range writer text (range : Wire_frame.text_range) =
  check_u32 "text range start" range.start_utf16;
  check_u32 "text range end" range.end_utf16;
  validate_text_range text range;
  Writer.u32 writer range.start_utf16;
  Writer.u32 writer range.end_utf16
;;

let validate_marked_selection (selection : Wire_frame.text_range) composing =
  Option.iter
    (fun (marked : Wire_frame.text_range) ->
       if
         marked.start_utf16 < marked.end_utf16
         && (selection.start_utf16 < marked.start_utf16
             || selection.end_utf16 > marked.end_utf16)
       then fail Invalid_props "composing range must contain selection")
    composing
;;

let write_text_editing_value writer (value : Wire_frame.text_editing_value) =
  validate_marked_selection value.selection value.composing;
  write_string writer value.text;
  write_text_range writer value.text value.selection;
  match value.composing with
  | None -> Writer.u8 writer 0
  | Some composing ->
    Writer.u8 writer 1;
    write_text_range writer value.text composing
;;

let validate_collection_keys keys =
  if List.length keys > Generated_protocol.Limits.max_nodes
  then fail Invalid_props "too many collection keys";
  let seen = Hashtbl.create (List.length keys) in
  List.iter
    (fun key ->
       if String.length key = 0 || Hashtbl.mem seen key
       then fail Invalid_props "empty or duplicate collection key";
       Hashtbl.add seen key ())
    keys
;;

let validate_collection_catalog (fields : Wire_frame.collection_catalog) =
  validate_collection_keys fields.keys;
  (match fields.measurement_revision with
   | Some revision when revision < 0L ->
     fail Invalid_props "negative collection measurement revision"
   | None | Some _ -> ());
  (match fields.initial_anchor, fields.initial_key with
   | (0 | 1), None -> ()
   | 2, Some key when List.mem key fields.keys -> ()
   | _ -> fail Invalid_props "invalid initial collection position");
  let count = List.length fields.keys in
  let positive x = Float.is_finite x && x > 0. && x <= 9_007_199_254_740_992. in
  if not (positive fields.default_extent)
  then fail Invalid_props "invalid collection extent";
  check_u32 "collection overscan" fields.overscan;
  check_u32 "collection expand duration" fields.expand_duration_ms;
  check_u32 "collection collapse duration" fields.collapse_duration_ms;
  let previous = ref (-1)
  and adjustment = ref 0. in
  List.iter
    (fun (index, extent) ->
       if index <= !previous || index >= count || not (positive extent)
       then fail Invalid_props "invalid collection extent";
       previous := index;
       adjustment := !adjustment +. extent -. fields.default_extent)
    fields.overrides;
  let total = (float_of_int count *. fields.default_extent) +. !adjustment in
  if
    (not (Float.is_finite total))
    || total < 0.
    || total > 9_007_199_254_740_992.
    || (count > 0 && total = 0.)
  then fail Invalid_props "unrepresentable collection extent"
;;

let write_collection_keys writer keys =
  validate_collection_keys keys;
  Writer.u32 writer (List.length keys);
  List.iter (write_string writer) keys
;;

let write_collection_catalog writer (fields : Wire_frame.collection_catalog) =
  validate_collection_catalog fields;
  write_collection_keys writer fields.keys;
  Writer.f64 writer fields.default_extent;
  Writer.u32 writer (List.length fields.overrides);
  List.iter
    (fun (index, extent) ->
       Writer.u32 writer index;
       Writer.f64 writer extent)
    fields.overrides;
  Writer.u32 writer fields.overscan;
  Writer.u32 writer fields.expand_duration_ms;
  Writer.u32 writer fields.collapse_duration_ms;
  write_bool writer fields.vertical;
  Writer.u8 writer fields.initial_anchor;
  write_optional_string writer fields.initial_key;
  write_bool writer (Option.is_some fields.measurement_revision);
  Option.iter (Writer.u64 writer) fields.measurement_revision
;;

let write_collection_window writer (fields : Wire_frame.collection_window) =
  check_u32 "collection first index" fields.first_index;
  Writer.u32 writer fields.first_index;
  write_collection_keys writer fields.keys
;;

let write_text_editor writer (fields : Wire_frame.text_editor) =
  let session_id = ID.Text_input.Session_id.to_int64 fields.session_id in
  let document_revision =
    ID.Text_input.Document_revision.to_int64 fields.document_revision
  in
  let accepted = ID.Text_input.Local_revision.to_int64 fields.accepted_local_revision in
  List.iter (check_u64 "text editor revision") [ session_id; document_revision; accepted ];
  Option.iter
    (fun maximum ->
       if maximum <= 0 || maximum > Generated_protocol.Limits.max_string_bytes
       then fail Invalid_props "invalid editor byte limit")
    fields.max_utf8_bytes;
  Writer.u64 writer session_id;
  Writer.u64 writer document_revision;
  Writer.u64 writer accepted;
  Writer.u8 writer (text_update_mode_id fields.update_mode);
  write_text_editing_value writer fields.value;
  write_bool writer fields.enabled;
  write_bool writer fields.read_only;
  write_bool writer fields.submit_on_return;
  write_optional_u32 writer "editor byte limit" fields.max_utf8_bytes
;;

let write_text_field writer (fields : Wire_frame.text_field) =
  write_text_editor writer fields.editing;
  write_string writer fields.label;
  write_string writer fields.prompt;
  if
    fields.keyboard < 0
    || fields.keyboard > 4
    || fields.submit_label < 0
    || fields.submit_label > 5
    || fields.appearance < 0
    || fields.appearance > 1
  then fail Invalid_props "invalid field input traits";
  Writer.u8 writer fields.keyboard;
  Writer.u8 writer fields.submit_label;
  write_bool writer fields.autofocus;
  Writer.u8 writer fields.appearance
;;

let write_tab_key writer key =
  let key = ID.Navigation.Page_key.to_string key in
  if String.length key = 0 then fail Invalid_props "empty tab key";
  write_string writer key
;;

let validate_tab_metadata badge accessibility_label =
  List.iter
    (Option.iter (fun text ->
       if String.trim text = "" then fail Invalid_props "empty tab metadata"))
    [ badge; accessibility_label ]
;;

let write_tab_props writer key title symbol badge accessibility_label =
  write_tab_key writer key;
  if String.length symbol = 0 then fail Invalid_props "empty tab symbol";
  validate_tab_metadata badge accessibility_label;
  write_string writer title;
  write_string writer symbol;
  write_optional_string writer badge;
  write_optional_string writer accessibility_label
;;

let write_navigation_split_state writer (state : Wire_frame.navigation_split_state) =
  if
    state.visibility < 0
    || state.visibility > 3
    || state.compact_column < 0
    || state.compact_column > 2
  then fail Invalid_props "invalid split state";
  let selection_key = Option.map ID.Navigation.Page_key.to_string state.selection_key in
  if selection_key = Some "" then fail Invalid_props "empty split selection key";
  Writer.u8 writer state.visibility;
  Writer.u8 writer state.compact_column;
  write_optional_string writer selection_key
;;

let node_kind_id = function
  | Wire_frame.Empty -> Generated_protocol.Node_kind.empty
  | Spacer -> Generated_protocol.Node_kind.spacer
  | Text -> Generated_protocol.Node_kind.text
  | Rich_text -> Generated_protocol.Node_kind.rich_text
  | Symbol -> Generated_protocol.Node_kind.symbol
  | Image -> Generated_protocol.Node_kind.image
  | Collection_catalog -> Generated_protocol.Node_kind.collection_catalog
  | Collection_window -> Generated_protocol.Node_kind.collection_window
  | Removal -> Generated_protocol.Node_kind.removal
  | Native_list -> Generated_protocol.Node_kind.native_list
  | List_section -> Generated_protocol.Node_kind.list_section
  | List_row -> Generated_protocol.Node_kind.list_row
  | Refresh -> Generated_protocol.Node_kind.refresh
  | Scroll_targets -> Generated_protocol.Node_kind.scroll_targets
  | Scroll -> Generated_protocol.Node_kind.scroll
  | Text_editor -> Generated_protocol.Node_kind.text_editor
  | Text_field -> Generated_protocol.Node_kind.text_field
  | Secure_field -> Generated_protocol.Node_kind.secure_field
  | Flow -> Generated_protocol.Node_kind.flow
  | Row -> Generated_protocol.Node_kind.row
  | Weighted_row -> Generated_protocol.Node_kind.weighted_row
  | Weighted_column -> Generated_protocol.Node_kind.weighted_column
  | Column -> Generated_protocol.Node_kind.column
  | Stack -> Generated_protocol.Node_kind.stack
  | Layout_priority -> Generated_protocol.Node_kind.layout_priority
  | Offset -> Generated_protocol.Node_kind.offset
  | Padding -> Generated_protocol.Node_kind.padding
  | Frame -> Generated_protocol.Node_kind.frame
  | Background -> Generated_protocol.Node_kind.background
  | Clip -> Generated_protocol.Node_kind.clip
  | Opacity -> Generated_protocol.Node_kind.opacity
  | Animated_opacity -> Generated_protocol.Node_kind.animated_opacity
  | Projection_effect -> Generated_protocol.Node_kind.projection_effect
  | Gesture -> Generated_protocol.Node_kind.gesture
  | Focus_scope -> Generated_protocol.Node_kind.focus_scope
  | Hover_region -> Generated_protocol.Node_kind.hover_region
  | Keyboard_listener -> Generated_protocol.Node_kind.keyboard_listener
  | Button -> Generated_protocol.Node_kind.button
  | Semantics -> Generated_protocol.Node_kind.semantics
  | Theme -> Generated_protocol.Node_kind.theme
  | Date_picker -> Generated_protocol.Node_kind.date_picker
  | Time_picker -> Generated_protocol.Node_kind.time_picker
  | Menu -> Generated_protocol.Node_kind.menu
  | Picker -> Generated_protocol.Node_kind.picker
  | Slider -> Generated_protocol.Node_kind.slider
  | Range_slider -> Generated_protocol.Node_kind.range_slider
  | Table -> Generated_protocol.Node_kind.table
  | Divider -> Generated_protocol.Node_kind.divider
  | Label -> Generated_protocol.Node_kind.label
  | Badge -> Generated_protocol.Node_kind.badge
  | Sheet -> Generated_protocol.Node_kind.sheet
  | Popover -> Generated_protocol.Node_kind.popover
  | Scroll_sections -> Generated_protocol.Node_kind.scroll_sections
  | Scroll_section -> Generated_protocol.Node_kind.scroll_section
  | Toolbar -> Generated_protocol.Node_kind.toolbar
  | Help -> Generated_protocol.Node_kind.help
  | Group_box -> Generated_protocol.Node_kind.group_box
  | Progress -> Generated_protocol.Node_kind.progress
  | Overlay -> Generated_protocol.Node_kind.overlay
  | Disclosure_group -> Generated_protocol.Node_kind.disclosure_group
  | Toggle -> Generated_protocol.Node_kind.toggle
  | Swipe_actions -> Generated_protocol.Node_kind.swipe_actions
  | Swipe_action -> Generated_protocol.Node_kind.swipe_action
  | Morphing_surface -> Generated_protocol.Node_kind.morphing_surface
  | Tabs -> Generated_protocol.Node_kind.tabs
  | Tab -> Generated_protocol.Node_kind.tab
  | Navigation_split -> Generated_protocol.Node_kind.navigation_split
  | Navigation_stack -> Generated_protocol.Node_kind.navigation_stack
  | Navigation_destination -> Generated_protocol.Node_kind.navigation_destination
  | Ignores_safe_area -> Generated_protocol.Node_kind.ignores_safe_area
  | Safe_area_padding -> Generated_protocol.Node_kind.safe_area_padding
  | Control_size -> Generated_protocol.Node_kind.control_size
  | Native_widget -> Generated_protocol.Node_kind.native_widget
;;

let check_scroll_section ~has_header ~has_footer ~hero_height ~stretch =
  match hero_height with
  | Some height
    when Float.is_finite height && height > 0. && (not has_header) && not has_footer -> ()
  | None when not stretch -> ()
  | _ -> fail Invalid_props "invalid native scroll section"
;;

let write_scroll_sections
      writer
      ~vertical
      ~pin_headers
      ~pin_footers
      ~spacing
      ~shows_indicators
      ~initial_anchor
  =
  if (not (Float.is_finite spacing)) || spacing < 0.
  then fail Invalid_props "invalid section spacing";
  write_bool writer vertical;
  write_bool writer pin_headers;
  write_bool writer pin_footers;
  Writer.f64 writer spacing;
  write_bool writer shows_indicators;
  if initial_anchor < 0 || initial_anchor > 1
  then fail Invalid_props "invalid initial scroll anchor";
  Writer.u8 writer initial_anchor
;;

let write_scroll_section writer ~has_header ~has_footer ~hero_height ~stretch =
  check_scroll_section ~has_header ~has_footer ~hero_height ~stretch;
  write_bool writer has_header;
  write_bool writer has_footer;
  write_optional_f64 writer hero_height;
  write_bool writer stretch
;;

let check_toolbar placements =
  if
    List.length placements > 256
    || List.exists (fun p -> p < 0 || p > 8) placements
    || List.length (List.filter (Int.equal 1) placements) > 1
  then fail Invalid_props "invalid native toolbar placements"
;;

let write_toolbar writer placements =
  check_toolbar placements;
  Writer.u16 writer (List.length placements);
  List.iter (Writer.u8 writer) placements
;;

let write_i64_list writer label values =
  check_u16 (label ^ " count") (List.length values);
  Writer.u16 writer (List.length values);
  List.iter (Writer.u64 writer) values
;;

let check_scroll_targets ~ids ~position ~fraction ~spacing ~alignment =
  check_u16 "scroll target count" (List.length ids);
  let seen = Hashtbl.create (List.length ids) in
  List.iter
    (fun id ->
       if Hashtbl.mem seen id then fail Invalid_props "duplicate scroll target";
       Hashtbl.add seen id ())
    ids;
  if
    (not (Float.is_finite fraction))
    || fraction <= 0.
    || fraction > 1.
    || (not (Float.is_finite spacing))
    || spacing < 0.
    || alignment < 0
    || alignment > 2
  then fail Invalid_props "invalid scroll target layout";
  match ids, position with
  | [], None -> ()
  | _ :: _, Some id when Hashtbl.mem seen id -> ()
  | _ -> fail Invalid_props "scroll position must name a target"
;;

let write_removal
      writer
      ~request_token
      ~request_state
      ~vertical
      ~collapse_vertical
      ~title
      ~duration_ms
  =
  if request_state < 0 || request_state > 3 || String.trim title = ""
  then fail Invalid_props "invalid removal properties";
  check_u32 "removal duration" duration_ms;
  Writer.u64 writer request_token;
  Writer.u8 writer request_state;
  write_bool writer vertical;
  write_bool writer collapse_vertical;
  write_string writer title;
  Writer.u32 writer duration_ms
;;

let write_refresh writer ~request_token ~request_state ~show_token =
  if request_state < 0 || request_state > 2
  then fail Invalid_props "invalid refresh state";
  Writer.u64 writer request_token;
  Writer.u8 writer request_state;
  write_bool writer (Option.is_some show_token);
  Option.iter (Writer.u64 writer) show_token
;;

let write_scroll_targets
      writer
      ~vertical
      ~ids
      ~position
      ~fraction
      ~spacing
      ~alignment
      ~snapping
      ~enabled
      ~shows_indicators
  =
  check_scroll_targets ~ids ~position ~fraction ~spacing ~alignment;
  write_bool writer vertical;
  write_i64_list writer "scroll target" ids;
  write_bool writer (Option.is_some position);
  Option.iter (Writer.u64 writer) position;
  Writer.f64 writer fraction;
  Writer.f64 writer spacing;
  Writer.u8 writer alignment;
  write_bool writer snapping;
  write_bool writer enabled;
  write_bool writer shows_indicators
;;

let unique_i64_set label ids =
  let seen = Hashtbl.create (List.length ids) in
  List.iter
    (fun id ->
       if Hashtbl.mem seen id then fail Invalid_props "%s IDs must be unique" label;
       Hashtbl.add seen id ())
    ids;
  seen
;;

let validate_canonical_ids label known ids =
  let rec loop previous = function
    | [] -> ()
    | id :: rest ->
      if not (Hashtbl.mem known id) then fail Invalid_props "%s ID is absent" label;
      Option.iter
        (fun previous ->
           if Int64.compare previous id >= 0
           then fail Invalid_props "%s IDs must be sorted and unique" label)
        previous;
      loop (Some id) rest
  in
  loop None ids
;;

let validate_data_table ~columns ~rows ~sort_column_id ~selected_row_ids =
  if List.is_empty columns then fail Invalid_props "data table needs a column";
  let column_ids =
    unique_i64_set
      "data table column"
      (List.map (fun (column : Wire_frame.table_column) -> column.column_id) columns)
  in
  List.iter
    (fun (column : Wire_frame.table_column) ->
       if String.trim column.title = ""
       then fail Invalid_props "table title must not be empty";
       Option.iter
         (fun tooltip ->
            if String.length (String.trim tooltip) = 0
            then fail Invalid_props "data table tooltip must not be empty")
         column.tooltip)
    columns;
  let row_ids =
    unique_i64_set
      "data table row"
      (List.map (fun (row : Wire_frame.table_row) -> row.row_id) rows)
  in
  Option.iter
    (fun id ->
       if not (Hashtbl.mem column_ids id)
       then fail Invalid_props "data table sort column ID is absent";
       if
         not
           (List.exists
              (fun (column : Wire_frame.table_column) ->
                 column.column_id = id && column.sortable)
              columns)
       then fail Invalid_props "table sort column must be sortable")
    sort_column_id;
  validate_canonical_ids "data table selected row" row_ids selected_row_ids
;;

let write_table_props writer = function
  | Table_props fields ->
    validate_data_table
      ~columns:fields.columns
      ~rows:fields.rows
      ~sort_column_id:fields.sort_column_id
      ~selected_row_ids:fields.selected_row_ids;
    check_u16 "data table column count" (List.length fields.columns);
    Writer.u16 writer (List.length fields.columns);
    List.iter
      (fun (column : Wire_frame.table_column) ->
         Writer.u64 writer column.column_id;
         write_string writer column.title;
         write_bool writer column.has_details;
         write_optional_string writer column.tooltip;
         write_bool writer column.numeric;
         write_bool writer column.sortable)
      fields.columns;
    check_u16 "data table row count" (List.length fields.rows);
    Writer.u16 writer (List.length fields.rows);
    List.iter
      (fun (row : Wire_frame.table_row) ->
         Writer.u64 writer row.row_id;
         write_bool writer row.selection_enabled)
      fields.rows;
    (match fields.sort_column_id with
     | None -> Writer.u8 writer 0
     | Some id ->
       Writer.u8 writer 1;
       Writer.u64 writer id);
    write_bool writer fields.sort_ascending;
    write_i64_list writer "selected row" fields.selected_row_ids;
    List.iter (write_bool writer) [ fields.has_on_sort; fields.has_on_row_selected ]
  | _ -> invalid_arg "not a Table prop"
;;

let validate_layout_value value =
  if not (Float.is_finite value) then fail Invalid_props "layout value must be finite"
;;

let validate_badge count alignment =
  Option.iter
    (fun count ->
       if Int64.compare count 0L < 0 then fail Invalid_props "negative badge count")
    count;
  if alignment < 0 || alignment > 2 then fail Invalid_props "invalid badge alignment"
;;

let write_badge writer count alignment visible =
  validate_badge count alignment;
  write_bool writer (Option.is_some count);
  Option.iter (Writer.u64 writer) count;
  Writer.u8 writer alignment;
  write_bool writer visible
;;

let validate_stack_properties maximum spacing alignment =
  Option.iter validate_layout_value spacing;
  if alignment < 0 || alignment > maximum
  then fail Invalid_props "invalid stack alignment"
;;

let write_stack_properties writer maximum spacing alignment =
  validate_stack_properties maximum spacing alignment;
  write_optional_f64 writer spacing;
  Writer.u8 writer alignment
;;

let write_weighted_properties writer maximum spacing alignment items =
  write_stack_properties writer maximum spacing alignment;
  if List.length items > Generated_protocol.Limits.max_nodes
  then fail Invalid_props "too many weighted items";
  Writer.u32 writer (List.length items);
  List.iter
    (function
      | Wire_frame.Intrinsic -> Writer.u8 writer 0
      | Share { weight; fills } ->
        if (not (Float.is_finite weight)) || Float.compare weight 0. <= 0
        then fail Invalid_props "weight must be finite and positive";
        Writer.u8 writer 1;
        Writer.f64 writer weight;
        write_bool writer fills)
    items
;;

let write_flow_properties writer spacing line_spacing alignment =
  List.iter
    (fun value ->
       validate_layout_value value;
       if value < 0. then fail Invalid_props "negative flow spacing")
    [ spacing; line_spacing ];
  if alignment < 0 || alignment > 2 then fail Invalid_props "invalid flow alignment";
  Writer.f64 writer spacing;
  Writer.f64 writer line_spacing;
  Writer.u8 writer alignment
;;

let write_civil_date writer (date : Wire_frame.civil_date) =
  check_u16 "civil date year" date.year;
  if date.month < 0 || date.month > 0xff
  then fail Invalid_props "civil date month is outside u8";
  if date.day < 0 || date.day > 0xff
  then fail Invalid_props "civil date day is outside u8";
  Writer.u16 writer date.year;
  Writer.u8 writer date.month;
  Writer.u8 writer date.day
;;

let write_civil_time writer (time : Wire_frame.civil_time) =
  if time.hour < 0 || time.hour > 0xff
  then fail Invalid_props "civil time hour is outside u8";
  if time.minute < 0 || time.minute > 0xff
  then fail Invalid_props "civil time minute is outside u8";
  Writer.u8 writer time.hour;
  Writer.u8 writer time.minute
;;

let compare_civil_date (a : Wire_frame.civil_date) (b : Wire_frame.civil_date) =
  compare (a.year, a.month, a.day) (b.year, b.month, b.day)
;;

let valid_civil_date (date : Wire_frame.civil_date) =
  let leap = date.year mod 400 = 0 || (date.year mod 4 = 0 && date.year mod 100 <> 0) in
  let days =
    [| 31; (if leap then 29 else 28); 31; 30; 31; 30; 31; 31; 30; 31; 30; 31 |]
  in
  date.year >= 1
  && date.year <= 9999
  && date.month >= 1
  && date.month <= 12
  && date.day >= 1
  && date.day <= days.(date.month - 1)
;;

let validate_date_picker ~selected ~first ~last ~label =
  let bounded date =
    valid_civil_date date
    && compare_civil_date first date <= 0
    && compare_civil_date date last <= 0
  in
  if
    String.trim label = ""
    || (not (valid_civil_date first && valid_civil_date last))
    || compare_civil_date first { year = 1582; month = 10; day = 15 } < 0
    || compare_civil_date first last > 0
    || not (bounded selected)
  then fail Invalid_props "invalid date picker selection or domain"
;;

let validate_time_picker ~(value : Wire_frame.civil_time) ~format ~label =
  if
    value.hour < 0
    || value.hour > 23
    || value.minute < 0
    || value.minute > 59
    || format < 0
    || format > 2
    || String.trim label = ""
  then fail Invalid_props "invalid time picker value or configuration"
;;

let write_date_picker writer ~selected ~first ~last ~label ~enabled =
  validate_date_picker ~selected ~first ~last ~label;
  write_civil_date writer selected;
  write_civil_date writer first;
  write_civil_date writer last;
  write_string writer label;
  write_bool writer enabled
;;

let write_time_picker writer ~value ~format ~label ~enabled =
  validate_time_picker ~value ~format ~label;
  write_civil_time writer value;
  Writer.u8 writer format;
  write_string writer label;
  write_bool writer enabled
;;

let validate_menu items =
  let count = List.length items in
  if count = 0 || count > 1024 then fail Invalid_props "menu requires 1..1024 entries";
  let ids = Hashtbl.create count in
  List.iter
    (fun (item : Wire_frame.menu_item) ->
       if Hashtbl.mem ids item.menu_id then fail Invalid_props "duplicate menu ID";
       Hashtbl.add ids item.menu_id ();
       if
         item.kind < 0
         || item.kind > 4
         || item.role < 0
         || item.role > 2
         || (item.role <> 0 && item.kind <> 0)
         || (item.selected && item.kind <> 1)
         || (item.kind = 2 && (item.enabled || item.has_label))
         || (item.kind = 3 && not item.enabled)
         || (List.mem item.kind [ 0; 1; 4 ] && not item.has_label)
         || (item.kind < 3 && item.child_count <> 0)
         || (item.kind >= 3 && item.child_count <= 0)
       then fail Invalid_props "invalid menu item";
       check_u16 "menu child count" item.child_count)
    items;
  let rec consume depth count rest =
    if count = 0
    then rest
    else if depth > 32
    then fail Invalid_props "menu nesting exceeds 32 levels"
    else (
      match rest with
      | [] -> fail Invalid_props "menu children exceed item count"
      | (item : Wire_frame.menu_item) :: rest ->
        let rest = consume (depth + 1) item.child_count rest in
        consume depth (count - 1) rest)
  in
  let rec roots = function
    | [] -> ()
    | rest -> roots (consume 1 1 rest)
  in
  roots items
;;

let write_menu writer ~items ~enabled =
  validate_menu items;
  Writer.u16 writer (List.length items);
  List.iter
    (fun (item : Wire_frame.menu_item) ->
       Writer.u64 writer item.menu_id;
       Writer.u8 writer item.kind;
       write_bool writer item.enabled;
       write_bool writer item.selected;
       Writer.u8 writer item.role;
       write_bool writer item.has_label;
       Writer.u16 writer item.child_count)
    items;
  write_bool writer enabled
;;

let write_props writer kind props =
  match kind, props with
  | Wire_frame.Empty, Empty_props -> ()
  | Weighted_row, Weighted_row_props { spacing; alignment; items } ->
    write_weighted_properties writer 4 spacing alignment items
  | Weighted_column, Weighted_column_props { spacing; alignment; items } ->
    write_weighted_properties writer 2 spacing alignment items
  | Flow, Flow_props { spacing; line_spacing; alignment } ->
    write_flow_properties writer spacing line_spacing alignment
  | Row, Row_props { spacing; alignment } ->
    write_stack_properties writer 4 spacing alignment
  | Column, Column_props { spacing; alignment } ->
    write_stack_properties writer 2 spacing alignment
  | Stack, Stack_props { alignment } -> Writer.u8 writer (alignment_id alignment)
  | Layout_priority, Layout_priority_props { priority } ->
    validate_layout_value priority;
    Writer.f64 writer priority
  | Offset, Offset_props { x; y } ->
    validate_layout_value x;
    validate_layout_value y;
    Writer.f64 writer x;
    Writer.f64 writer y
  | Text, Text_props props -> write_text_props writer props
  | Rich_text, Rich_text_props { spans } ->
    check_u16 "rich text span count" (List.length spans);
    Writer.u16 writer (List.length spans);
    List.iter (write_text_span writer) spans
  | Symbol, Symbol_props { name; size; color; rendering } ->
    check_symbol_properties ~name ~size ~rendering;
    write_string writer name;
    write_optional_f64 writer size;
    write_optional_argb32 writer color;
    Writer.u8 writer rendering
  | ( Removal
    , Removal_props
        { request_token; request_state; vertical; collapse_vertical; title; duration_ms }
    ) ->
    write_removal
      writer
      ~request_token
      ~request_state
      ~vertical
      ~collapse_vertical
      ~title
      ~duration_ms
  | Native_list, Native_list_props -> ()
  | List_section, List_section_props { has_header; has_footer; separator } ->
    write_bool writer has_header;
    write_bool writer has_footer;
    write_separator writer separator
  | List_row, List_row_props { separator } -> write_separator writer separator
  | Refresh, Refresh_props { request_token; request_state; show_token } ->
    write_refresh writer ~request_token ~request_state ~show_token
  | ( Scroll_targets
    , Scroll_targets_props
        { vertical
        ; ids
        ; position
        ; fraction
        ; spacing
        ; alignment
        ; snapping
        ; enabled
        ; shows_indicators
        } ) ->
    write_scroll_targets
      writer
      ~vertical
      ~ids
      ~position
      ~fraction
      ~spacing
      ~alignment
      ~snapping
      ~enabled
      ~shows_indicators
  | Scroll, Scroll_props { vertical; shows_indicators; fill_viewport; initial_anchor } ->
    write_bool writer vertical;
    write_bool writer shows_indicators;
    write_bool writer fill_viewport;
    if initial_anchor < 0 || initial_anchor > 1
    then fail Invalid_props "invalid initial scroll anchor";
    Writer.u8 writer initial_anchor
  | Collection_catalog, Collection_catalog_props fields ->
    write_collection_catalog writer fields
  | Collection_window, Collection_window_props fields ->
    write_collection_window writer fields
  | Text_field, Text_field_props fields when not fields.secure ->
    write_text_field writer fields
  | Secure_field, Text_field_props fields when fields.secure ->
    write_text_field writer fields
  | Text_editor, Text_editor_props fields ->
    write_text_editor writer fields.editing;
    write_bool writer fields.autofocus
  | Image, Image_props { source; sizing; scale } ->
    write_image_props writer source sizing scale
  | Button, Button_props { enabled; role; style; autofocus } ->
    check_button_properties ~role ~style;
    write_bool writer enabled;
    Writer.u8 writer role;
    Writer.u8 writer style;
    write_bool writer autofocus
  | Padding, Padding_props { leading; top; trailing; bottom } ->
    List.iter validate_layout_value [ leading; top; trailing; bottom ];
    Writer.f64 writer leading;
    Writer.f64 writer top;
    Writer.f64 writer trailing;
    Writer.f64 writer bottom
  | Spacer, Spacer_props { min_length } ->
    validate_spacer_minimum min_length;
    write_optional_f64 writer min_length
  | Frame, Frame_props props -> write_frame_props writer props
  | Background, Background_props { color; corner_radius } ->
    validate_surface_dimension corner_radius;
    Writer.u32 writer (Int64.to_int (Int64.logand (Int64.of_int32 color) 0xffff_ffffL));
    Writer.f64 writer corner_radius
  | Clip, Clip_props { corner_radius; antialiased } ->
    validate_surface_dimension corner_radius;
    Writer.f64 writer corner_radius;
    write_bool writer antialiased
  | Opacity, Opacity_props { opacity } ->
    validate_opacity opacity;
    Writer.f64 writer opacity
  | Animated_opacity, Animated_opacity_props { opacity; animation } ->
    Writer.f64 writer opacity;
    write_animation writer animation
  | Projection_effect, Projection_effect_props { matrix3 } ->
    if Array.length matrix3 <> 9
    then fail Invalid_props "projection matrix must contain 9 values";
    Array.iter
      (fun value ->
         validate_layout_value value;
         Writer.f64 writer value)
      matrix3
  | Gesture, Gesture_props -> ()
  | Focus_scope, Focus_scope_props { autofocus } -> write_bool writer autofocus
  | Hover_region, Hover_region_props { blocks_behind } -> write_bool writer blocks_behind
  | Keyboard_listener, Keyboard_listener_props { autofocus; key_policy } ->
    write_bool writer autofocus;
    Writer.u8
      writer
      (match key_policy with
       | Handled -> 0
       | Ignored -> 1)
  | ( Semantics
    , Semantics_props
        { label
        ; hint
        ; value
        ; role
        ; selected
        ; children
        ; hidden
        ; live_region
        ; heading_level
        ; sort_priority
        ; identifier
        ; actions
        } ) ->
    write_optional_string writer label;
    write_optional_string writer hint;
    write_optional_string writer value;
    Writer.u8 writer (semantics_role_id role);
    write_optional_bool writer selected;
    if children < 0 || children > 2 then fail Invalid_props "invalid semantics children";
    Writer.u8 writer children;
    write_bool writer hidden;
    write_bool writer live_region;
    write_optional_u8 writer heading_level;
    write_optional_f64 writer sort_priority;
    write_optional_string writer identifier;
    if List.length actions > 1024 then fail Invalid_props "too many semantics actions";
    Writer.u16 writer (List.length actions);
    let ids = Hashtbl.create (List.length actions) in
    List.iter
      (fun (id, label) ->
         if id <= 0L || label = "" || Hashtbl.mem ids id
         then fail Invalid_props "invalid semantics action";
         Hashtbl.add ids id ();
         Writer.u64 writer id;
         write_string writer label)
      actions
  | Theme, Theme_props data -> write_theme writer data
  | Date_picker, Date_picker_props { selected; first; last; label; enabled } ->
    write_date_picker writer ~selected ~first ~last ~label ~enabled
  | Time_picker, Time_picker_props { value; format; label; enabled } ->
    write_time_picker writer ~value ~format ~label ~enabled
  | Menu, Menu_props { items; enabled } -> write_menu writer ~items ~enabled
  | Picker, Picker_props { selected_id; options; label; style; enabled } ->
    validate_picker ~selected_id ~label ~style options;
    (match selected_id with
     | None -> Writer.u8 writer 0
     | Some selected_id ->
       Writer.u8 writer 1;
       Writer.u64 writer selected_id);
    check_u16 "picker option count" (List.length options);
    Writer.u16 writer (List.length options);
    List.iter
      (fun (option : Wire_frame.picker_option) ->
         Writer.u64 writer option.option_id;
         write_bool writer option.enabled;
         write_bool writer option.has_label)
      options;
    write_string writer label;
    Writer.u8 writer style;
    write_bool writer enabled
  | ( Slider
    , Slider_props { value; min; max; step; label; enabled; vertical; has_on_change } ) ->
    write_slider_fields
      writer
      ~lower:value
      ~upper:None
      ~min
      ~max
      ~step
      ~enabled
      ~vertical
      ~has_on_change
      ~label
      ~upper_label:None
  | ( Range_slider
    , Range_slider_props
        { start
        ; end_
        ; min
        ; max
        ; step
        ; label_start
        ; label_end
        ; enabled
        ; vertical
        ; has_on_change
        } ) ->
    write_slider_fields
      writer
      ~lower:start
      ~upper:(Some end_)
      ~min
      ~max
      ~step
      ~enabled
      ~vertical
      ~has_on_change
      ~label:label_start
      ~upper_label:(Some label_end)
  | Table, (Table_props _ as props) -> write_table_props writer props
  | Divider, Divider_props -> ()
  | Label, Label_props -> ()
  | Badge, Badge_props { count; alignment; visible } ->
    write_badge writer count alignment visible
  | ( Sheet
    , Sheet_props
        { presented
        ; fullscreen
        ; detents
        ; initial
        ; interactive
        ; indicator
        ; sizing
        ; fraction
        } ) ->
    check_sheet_properties
      ~fullscreen
      ~detents
      ~initial
      ~interactive
      ~indicator
      ~sizing
      ~fraction;
    write_bool writer presented;
    write_bool writer fullscreen;
    Writer.u8 writer detents;
    Writer.u8 writer initial;
    write_bool writer interactive;
    write_bool writer indicator;
    Writer.u8 writer sizing;
    Writer.f64 writer fraction
  | Popover, Popover_props { presented; edge } ->
    if edge < 0 || edge > 4 then fail Invalid_props "invalid popover edge";
    write_bool writer presented;
    Writer.u8 writer edge
  | ( Scroll_sections
    , Scroll_sections_props
        { vertical; pin_headers; pin_footers; spacing; shows_indicators; initial_anchor }
    ) ->
    write_scroll_sections
      writer
      ~vertical
      ~pin_headers
      ~pin_footers
      ~spacing
      ~shows_indicators
      ~initial_anchor
  | Scroll_section, Scroll_section_props { has_header; has_footer; hero_height; stretch }
    -> write_scroll_section writer ~has_header ~has_footer ~hero_height ~stretch
  | Toolbar, Toolbar_props { placements } -> write_toolbar writer placements
  | Help, Help_props { message } ->
    if String.trim message = "" then fail Invalid_props "help message must not be empty";
    write_string writer message
  | Group_box, Group_box_props { has_label } -> write_bool writer has_label
  | Progress, Progress_props { value; style } ->
    validate_progress_value value;
    write_optional_f64 writer value;
    validate_progress_style value style;
    Writer.u8 writer style
  | Overlay, Overlay_props { alignment } -> Writer.u8 writer (alignment_id alignment)
  | Disclosure_group, Disclosure_group_props { expanded; enabled } ->
    write_bool writer expanded;
    write_bool writer enabled
  | Toggle, Toggle_props { value; enabled; style } ->
    if style < 0 || style > 3 then fail Invalid_props "invalid toggle style";
    write_bool writer value;
    write_bool writer enabled;
    Writer.u8 writer style
  | Swipe_actions, Swipe_actions_props { enabled; allows_full_swipe } ->
    write_bool writer enabled;
    write_bool writer allows_full_swipe
  | Swipe_action, Swipe_action_props { title; side; enabled; role; background; symbol } ->
    if
      String.trim title = ""
      || side < 0
      || side > 1
      || role < 0
      || role > 2
      || symbol = Some ""
    then fail Invalid_props "invalid swipe action";
    write_string writer title;
    Writer.u8 writer side;
    write_bool writer enabled;
    Writer.u8 writer role;
    Writer.u32 writer background;
    write_optional_string writer symbol
  | ( Morphing_surface
    , Morphing_surface_props { expanded; expand_duration_ms; collapse_duration_ms } ) ->
    check_u32 "morph expand duration" expand_duration_ms;
    check_u32 "morph collapse duration" collapse_duration_ms;
    write_bool writer expanded;
    Writer.u32 writer expand_duration_ms;
    Writer.u32 writer collapse_duration_ms
  | Tabs, Tabs_props { selection } -> write_tab_key writer selection
  | Tab, Tab_props { page_key; title; symbol; badge; accessibility_label } ->
    write_tab_props writer page_key title symbol badge accessibility_label
  | ( Navigation_split
    , Navigation_split_props { state; sidebar_title; content_title; detail_title } ) ->
    if Option.is_none content_title && state.compact_column = 1
    then fail Invalid_props "two-column split cannot prefer Content";
    write_navigation_split_state writer state;
    write_string writer sidebar_title;
    write_optional_string writer content_title;
    write_string writer detail_title
  | Navigation_stack, Navigation_stack_props { title } -> write_string writer title
  | Navigation_destination, Navigation_destination_props { page_key; title; can_pop } ->
    let key = ID.Navigation.Page_key.to_string page_key in
    if String.length key = 0 then fail Invalid_props "empty navigation destination key";
    write_string writer key;
    write_string writer title;
    write_bool writer can_pop
  | Control_size, Control_size_props { size } ->
    if size < 0 || size > 4 then fail Invalid_props "invalid control size";
    Writer.u8 writer size
  | Ignores_safe_area, Ignores_safe_area_props { regions; edges } ->
    if regions < 0 || regions > 2 || edges < 0 || edges > 15
    then fail Invalid_props "invalid safe area regions or edges";
    Writer.u8 writer regions;
    Writer.u8 writer edges
  | Safe_area_padding, Safe_area_padding_props { leading; top; trailing; bottom } ->
    List.iter
      (fun value ->
         if not (Float.is_finite value)
         then fail Invalid_props "non-finite safe area inset")
      [ leading; top; trailing; bottom ];
    List.iter (Writer.f64 writer) [ leading; top; trailing; bottom ]
  | Native_widget, Native_widget_props { kind_id; version; capabilities; payload } ->
    let kind_id = ID.Native_widget.Kind_id.to_int kind_id in
    check_u32 "native widget kind ID" kind_id;
    check_u16 "native widget version" version;
    check_u32 "native widget payload length" (Bytes.length payload);
    Writer.u32 writer kind_id;
    Writer.u16 writer version;
    Writer.u64 writer capabilities;
    Writer.u32 writer (Bytes.length payload);
    Writer.bytes writer payload
  | _ -> fail Invalid_props "props do not match the node kind"
;;

let props_kind_id = function
  | Wire_frame.Empty_props -> Generated_protocol.Node_kind.empty
  | Text_props _ -> Generated_protocol.Node_kind.text
  | Rich_text_props _ -> Generated_protocol.Node_kind.rich_text
  | Symbol_props _ -> Generated_protocol.Node_kind.symbol
  | Image_props _ -> Generated_protocol.Node_kind.image
  | Collection_catalog_props _ -> Generated_protocol.Node_kind.collection_catalog
  | Collection_window_props _ -> Generated_protocol.Node_kind.collection_window
  | Removal_props _ -> Generated_protocol.Node_kind.removal
  | Native_list_props -> Generated_protocol.Node_kind.native_list
  | List_section_props _ -> Generated_protocol.Node_kind.list_section
  | List_row_props _ -> Generated_protocol.Node_kind.list_row
  | Refresh_props _ -> Generated_protocol.Node_kind.refresh
  | Scroll_targets_props _ -> Generated_protocol.Node_kind.scroll_targets
  | Scroll_props _ -> Generated_protocol.Node_kind.scroll
  | Text_field_props fields ->
    if fields.secure
    then Generated_protocol.Node_kind.secure_field
    else Generated_protocol.Node_kind.text_field
  | Text_editor_props _ -> Generated_protocol.Node_kind.text_editor
  | Flow_props _ -> Generated_protocol.Node_kind.flow
  | Row_props _ -> Generated_protocol.Node_kind.row
  | Weighted_row_props _ -> Generated_protocol.Node_kind.weighted_row
  | Weighted_column_props _ -> Generated_protocol.Node_kind.weighted_column
  | Column_props _ -> Generated_protocol.Node_kind.column
  | Stack_props _ -> Generated_protocol.Node_kind.stack
  | Layout_priority_props _ -> Generated_protocol.Node_kind.layout_priority
  | Offset_props _ -> Generated_protocol.Node_kind.offset
  | Button_props _ -> Generated_protocol.Node_kind.button
  | Padding_props _ -> Generated_protocol.Node_kind.padding
  | Spacer_props _ -> Generated_protocol.Node_kind.spacer
  | Frame_props _ -> Generated_protocol.Node_kind.frame
  | Background_props _ -> Generated_protocol.Node_kind.background
  | Clip_props _ -> Generated_protocol.Node_kind.clip
  | Opacity_props _ -> Generated_protocol.Node_kind.opacity
  | Animated_opacity_props _ -> Generated_protocol.Node_kind.animated_opacity
  | Projection_effect_props _ -> Generated_protocol.Node_kind.projection_effect
  | Gesture_props -> Generated_protocol.Node_kind.gesture
  | Focus_scope_props _ -> Generated_protocol.Node_kind.focus_scope
  | Hover_region_props _ -> Generated_protocol.Node_kind.hover_region
  | Keyboard_listener_props _ -> Generated_protocol.Node_kind.keyboard_listener
  | Semantics_props _ -> Generated_protocol.Node_kind.semantics
  | Theme_props _ -> Generated_protocol.Node_kind.theme
  | Date_picker_props _ -> Generated_protocol.Node_kind.date_picker
  | Time_picker_props _ -> Generated_protocol.Node_kind.time_picker
  | Menu_props _ -> Generated_protocol.Node_kind.menu
  | Picker_props _ -> Generated_protocol.Node_kind.picker
  | Slider_props _ -> Generated_protocol.Node_kind.slider
  | Range_slider_props _ -> Generated_protocol.Node_kind.range_slider
  | Table_props _ -> Generated_protocol.Node_kind.table
  | Divider_props -> Generated_protocol.Node_kind.divider
  | Label_props -> Generated_protocol.Node_kind.label
  | Badge_props _ -> Generated_protocol.Node_kind.badge
  | Sheet_props _ -> Generated_protocol.Node_kind.sheet
  | Popover_props _ -> Generated_protocol.Node_kind.popover
  | Scroll_sections_props _ -> Generated_protocol.Node_kind.scroll_sections
  | Scroll_section_props _ -> Generated_protocol.Node_kind.scroll_section
  | Toolbar_props _ -> Generated_protocol.Node_kind.toolbar
  | Help_props _ -> Generated_protocol.Node_kind.help
  | Group_box_props _ -> Generated_protocol.Node_kind.group_box
  | Progress_props _ -> Generated_protocol.Node_kind.progress
  | Overlay_props _ -> Generated_protocol.Node_kind.overlay
  | Disclosure_group_props _ -> Generated_protocol.Node_kind.disclosure_group
  | Toggle_props _ -> Generated_protocol.Node_kind.toggle
  | Swipe_actions_props _ -> Generated_protocol.Node_kind.swipe_actions
  | Swipe_action_props _ -> Generated_protocol.Node_kind.swipe_action
  | Morphing_surface_props _ -> Generated_protocol.Node_kind.morphing_surface
  | Tabs_props _ -> Generated_protocol.Node_kind.tabs
  | Tab_props _ -> Generated_protocol.Node_kind.tab
  | Navigation_split_props _ -> Generated_protocol.Node_kind.navigation_split
  | Navigation_stack_props _ -> Generated_protocol.Node_kind.navigation_stack
  | Navigation_destination_props _ -> Generated_protocol.Node_kind.navigation_destination
  | Ignores_safe_area_props _ -> Generated_protocol.Node_kind.ignores_safe_area
  | Safe_area_padding_props _ -> Generated_protocol.Node_kind.safe_area_padding
  | Control_size_props _ -> Generated_protocol.Node_kind.control_size
  | Native_widget_props _ -> Generated_protocol.Node_kind.native_widget
;;

let field_mask id =
  let id = ID.Protocol.Property.to_int id in
  Int64.shift_left 1L (id - 1)
;;

let changed_fields = function
  | Wire_frame.Empty_props | Gesture_props -> 0L
  | Weighted_row_props _ ->
    List.fold_left
      Int64.logor
      0L
      (List.map
         field_mask
         [ Generated_protocol.Weighted_row_prop.spacing
         ; Generated_protocol.Weighted_row_prop.alignment
         ; Generated_protocol.Weighted_row_prop.items
         ])
  | Weighted_column_props _ ->
    List.fold_left
      Int64.logor
      0L
      (List.map
         field_mask
         [ Generated_protocol.Weighted_column_prop.spacing
         ; Generated_protocol.Weighted_column_prop.alignment
         ; Generated_protocol.Weighted_column_prop.items
         ])
  | Flow_props _ ->
    List.fold_left
      Int64.logor
      0L
      (List.map
         field_mask
         [ Generated_protocol.Flow_prop.spacing
         ; Generated_protocol.Flow_prop.line_spacing
         ; Generated_protocol.Flow_prop.alignment
         ])
  | Row_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Row_prop.spacing)
      (field_mask Generated_protocol.Row_prop.alignment)
  | Column_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Column_prop.spacing)
      (field_mask Generated_protocol.Column_prop.alignment)
  | Stack_props _ -> field_mask Generated_protocol.Stack_prop.alignment
  | Layout_priority_props _ -> field_mask Generated_protocol.Layout_priority_prop.priority
  | Offset_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Offset_prop.x)
      (field_mask Generated_protocol.Offset_prop.y)
  | Text_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Text_prop.value
      ; field_mask Generated_protocol.Text_prop.text_style
      ; field_mask Generated_protocol.Text_prop.text_align
      ; field_mask Generated_protocol.Text_prop.line_limit
      ; field_mask Generated_protocol.Text_prop.truncation
      ]
  | Rich_text_props _ -> field_mask Generated_protocol.Rich_text_prop.spans
  | Symbol_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Symbol_prop.name
      ; field_mask Generated_protocol.Symbol_prop.size
      ; field_mask Generated_protocol.Symbol_prop.color
      ; field_mask Generated_protocol.Symbol_prop.rendering
      ]
  | Collection_catalog_props _ -> 1023L
  | Collection_window_props _ -> 3L
  | Removal_props _ -> 63L
  | Native_list_props -> 0L
  | List_section_props _ -> 7L
  | List_row_props _ -> 1L
  | Refresh_props _ -> 7L
  | Scroll_targets_props _ -> 511L
  | Scroll_props _ -> 15L
  | Text_field_props _ -> 32767L
  | Text_editor_props _ -> 1023L
  | Image_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Image_prop.source
      ; field_mask Generated_protocol.Image_prop.sizing
      ; field_mask Generated_protocol.Image_prop.scale
      ]
  | Button_props _ ->
    List.fold_left
      Int64.logor
      0L
      (List.map
         field_mask
         [ Generated_protocol.Button_prop.enabled
         ; Generated_protocol.Button_prop.role
         ; Generated_protocol.Button_prop.style
         ; Generated_protocol.Button_prop.autofocus
         ])
  | Padding_props _ -> field_mask Generated_protocol.Padding_prop.insets
  | Spacer_props _ -> field_mask Generated_protocol.Spacer_prop.min_length
  | Frame_props _ ->
    List.fold_left
      Int64.logor
      0L
      (List.map
         field_mask
         [ Generated_protocol.Frame_prop.width
         ; Generated_protocol.Frame_prop.height
         ; Generated_protocol.Frame_prop.min_width
         ; Generated_protocol.Frame_prop.ideal_width
         ; Generated_protocol.Frame_prop.max_width
         ; Generated_protocol.Frame_prop.min_height
         ; Generated_protocol.Frame_prop.ideal_height
         ; Generated_protocol.Frame_prop.max_height
         ; Generated_protocol.Frame_prop.alignment
         ])
  | Background_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Background_prop.color)
      (field_mask Generated_protocol.Background_prop.corner_radius)
  | Clip_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Clip_prop.corner_radius)
      (field_mask Generated_protocol.Clip_prop.antialiased)
  | Opacity_props _ -> field_mask Generated_protocol.Opacity_prop.opacity
  | Animated_opacity_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Animated_opacity_prop.opacity
      ; field_mask Generated_protocol.Animated_opacity_prop.animation_id
      ; field_mask Generated_protocol.Animated_opacity_prop.duration_ms
      ; field_mask Generated_protocol.Animated_opacity_prop.curve
      ]
  | Projection_effect_props _ ->
    field_mask Generated_protocol.Projection_effect_prop.matrix3
  | Focus_scope_props _ -> field_mask Generated_protocol.Focus_scope_prop.autofocus
  | Hover_region_props _ -> field_mask Generated_protocol.Hover_region_prop.blocks_behind
  | Keyboard_listener_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Keyboard_listener_prop.autofocus)
      (field_mask Generated_protocol.Keyboard_listener_prop.key_policy)
  | Semantics_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Semantics_prop.label
      ; field_mask Generated_protocol.Semantics_prop.hint
      ; field_mask Generated_protocol.Semantics_prop.value
      ; field_mask Generated_protocol.Semantics_prop.role
      ; field_mask Generated_protocol.Semantics_prop.selected
      ; field_mask Generated_protocol.Semantics_prop.children
      ; field_mask Generated_protocol.Semantics_prop.hidden
      ; field_mask Generated_protocol.Semantics_prop.live_region
      ; field_mask Generated_protocol.Semantics_prop.heading_level
      ; field_mask Generated_protocol.Semantics_prop.sort_priority
      ; field_mask Generated_protocol.Semantics_prop.identifier
      ; field_mask Generated_protocol.Semantics_prop.actions
      ]
  | Theme_props _ -> field_mask Generated_protocol.Theme_prop.data
  | Date_picker_props _ -> 31L
  | Time_picker_props _ -> 15L
  | Menu_props _ -> 3L
  | Picker_props _ -> 31L
  | Slider_props _ -> 255L
  | Range_slider_props _ -> 1023L
  | Table_props _ ->
    List.fold_left Int64.logor 0L (List.init 7 (fun index -> Int64.shift_left 1L index))
  | Divider_props -> 0L
  | Label_props -> 0L
  | Badge_props _ -> 7L
  | Sheet_props _ -> 255L
  | Popover_props _ -> 3L
  | Scroll_sections_props _ -> 63L
  | Scroll_section_props _ -> 15L
  | Toolbar_props _ -> 1L
  | Help_props _ -> field_mask Generated_protocol.Help_prop.message
  | Group_box_props _ -> field_mask Generated_protocol.Group_box_prop.has_label
  | Progress_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Progress_prop.value)
      (field_mask Generated_protocol.Progress_prop.style)
  | Overlay_props _ -> field_mask Generated_protocol.Overlay_prop.alignment
  | Disclosure_group_props _ -> 3L
  | Toggle_props _ -> 7L
  | Swipe_actions_props _ -> 3L
  | Swipe_action_props _ -> 63L
  | Morphing_surface_props _ -> 7L
  | Tabs_props _ -> 1L
  | Tab_props _ -> 31L
  | Navigation_split_props _ -> 63L
  | Navigation_stack_props _ -> 1L
  | Navigation_destination_props _ -> 7L
  | Control_size_props _ -> 1L
  | Ignores_safe_area_props _ ->
    Int64.logor
      (field_mask Generated_protocol.Ignores_safe_area_prop.regions)
      (field_mask Generated_protocol.Ignores_safe_area_prop.edges)
  | Safe_area_padding_props _ ->
    field_mask Generated_protocol.Safe_area_padding_prop.insets
  | Native_widget_props _ ->
    List.fold_left
      Int64.logor
      0L
      [ field_mask Generated_protocol.Native_widget_prop.kind_id
      ; field_mask Generated_protocol.Native_widget_prop.version
      ; field_mask Generated_protocol.Native_widget_prop.capabilities
      ; field_mask Generated_protocol.Native_widget_prop.payload
      ]
;;

let write_update_props writer props =
  Writer.u16 writer (ID.Protocol.Node_kind.to_int (props_kind_id props));
  Writer.u64 writer (changed_fields props);
  match props with
  | Wire_frame.Empty_props | Gesture_props -> ()
  | Weighted_row_props { spacing; alignment; items } ->
    write_weighted_properties writer 4 spacing alignment items
  | Weighted_column_props { spacing; alignment; items } ->
    write_weighted_properties writer 2 spacing alignment items
  | Flow_props { spacing; line_spacing; alignment } ->
    write_flow_properties writer spacing line_spacing alignment
  | Row_props { spacing; alignment } -> write_stack_properties writer 4 spacing alignment
  | Column_props { spacing; alignment } ->
    write_stack_properties writer 2 spacing alignment
  | Stack_props { alignment } -> Writer.u8 writer (alignment_id alignment)
  | Layout_priority_props { priority } ->
    validate_layout_value priority;
    Writer.f64 writer priority
  | Offset_props { x; y } ->
    validate_layout_value x;
    validate_layout_value y;
    Writer.f64 writer x;
    Writer.f64 writer y
  | Text_props props -> write_text_props writer props
  | Rich_text_props { spans } ->
    check_u16 "rich text span count" (List.length spans);
    Writer.u16 writer (List.length spans);
    List.iter (write_text_span writer) spans
  | Symbol_props { name; size; color; rendering } ->
    check_symbol_properties ~name ~size ~rendering;
    write_string writer name;
    write_optional_f64 writer size;
    write_optional_argb32 writer color;
    Writer.u8 writer rendering
  | Image_props { source; sizing; scale } -> write_image_props writer source sizing scale
  | Removal_props
      { request_token; request_state; vertical; collapse_vertical; title; duration_ms } ->
    write_removal
      writer
      ~request_token
      ~request_state
      ~vertical
      ~collapse_vertical
      ~title
      ~duration_ms
  | Native_list_props -> ()
  | List_section_props { has_header; has_footer; separator } ->
    write_bool writer has_header;
    write_bool writer has_footer;
    write_separator writer separator
  | List_row_props { separator } -> write_separator writer separator
  | Refresh_props { request_token; request_state; show_token } ->
    write_refresh writer ~request_token ~request_state ~show_token
  | Scroll_targets_props
      { vertical
      ; ids
      ; position
      ; fraction
      ; spacing
      ; alignment
      ; snapping
      ; enabled
      ; shows_indicators
      } ->
    write_scroll_targets
      writer
      ~vertical
      ~ids
      ~position
      ~fraction
      ~spacing
      ~alignment
      ~snapping
      ~enabled
      ~shows_indicators
  | Scroll_props { vertical; shows_indicators; fill_viewport; initial_anchor } ->
    write_bool writer vertical;
    write_bool writer shows_indicators;
    write_bool writer fill_viewport;
    if initial_anchor < 0 || initial_anchor > 1
    then fail Invalid_props "invalid initial scroll anchor";
    Writer.u8 writer initial_anchor
  | Collection_catalog_props fields -> write_collection_catalog writer fields
  | Collection_window_props fields -> write_collection_window writer fields
  | Text_field_props fields -> write_text_field writer fields
  | Text_editor_props fields ->
    write_text_editor writer fields.editing;
    write_bool writer fields.autofocus
  | Button_props { enabled; role; style; autofocus } ->
    check_button_properties ~role ~style;
    write_bool writer enabled;
    Writer.u8 writer role;
    Writer.u8 writer style;
    write_bool writer autofocus
  | Padding_props { leading; top; trailing; bottom } ->
    List.iter validate_layout_value [ leading; top; trailing; bottom ];
    Writer.f64 writer leading;
    Writer.f64 writer top;
    Writer.f64 writer trailing;
    Writer.f64 writer bottom
  | Spacer_props { min_length } ->
    validate_spacer_minimum min_length;
    write_optional_f64 writer min_length
  | Frame_props props -> write_frame_props writer props
  | Background_props { color; corner_radius } ->
    validate_surface_dimension corner_radius;
    Writer.u32 writer (Int64.to_int (Int64.logand (Int64.of_int32 color) 0xffff_ffffL));
    Writer.f64 writer corner_radius
  | Clip_props { corner_radius; antialiased } ->
    validate_surface_dimension corner_radius;
    Writer.f64 writer corner_radius;
    write_bool writer antialiased
  | Opacity_props { opacity } ->
    validate_opacity opacity;
    Writer.f64 writer opacity
  | Animated_opacity_props { opacity; animation } ->
    Writer.f64 writer opacity;
    write_animation writer animation
  | Projection_effect_props { matrix3 } ->
    if Array.length matrix3 <> 9
    then fail Invalid_props "projection matrix must contain 9 values";
    Array.iter
      (fun value ->
         validate_layout_value value;
         Writer.f64 writer value)
      matrix3
  | Focus_scope_props { autofocus } -> write_bool writer autofocus
  | Hover_region_props { blocks_behind } -> write_bool writer blocks_behind
  | Keyboard_listener_props { autofocus; key_policy } ->
    write_bool writer autofocus;
    Writer.u8
      writer
      (match key_policy with
       | Handled -> 0
       | Ignored -> 1)
  | Semantics_props
      { label
      ; hint
      ; value
      ; role
      ; selected
      ; children
      ; hidden
      ; live_region
      ; heading_level
      ; sort_priority
      ; identifier
      ; actions
      } ->
    write_optional_string writer label;
    write_optional_string writer hint;
    write_optional_string writer value;
    Writer.u8 writer (semantics_role_id role);
    write_optional_bool writer selected;
    if children < 0 || children > 2 then fail Invalid_props "invalid semantics children";
    Writer.u8 writer children;
    write_bool writer hidden;
    write_bool writer live_region;
    write_optional_u8 writer heading_level;
    write_optional_f64 writer sort_priority;
    write_optional_string writer identifier;
    if List.length actions > 1024 then fail Invalid_props "too many semantics actions";
    Writer.u16 writer (List.length actions);
    let ids = Hashtbl.create (List.length actions) in
    List.iter
      (fun (id, label) ->
         if id <= 0L || label = "" || Hashtbl.mem ids id
         then fail Invalid_props "invalid semantics action";
         Hashtbl.add ids id ();
         Writer.u64 writer id;
         write_string writer label)
      actions
  | Theme_props data -> write_theme writer data
  | Date_picker_props { selected; first; last; label; enabled } ->
    write_date_picker writer ~selected ~first ~last ~label ~enabled
  | Time_picker_props { value; format; label; enabled } ->
    write_time_picker writer ~value ~format ~label ~enabled
  | Menu_props { items; enabled } -> write_menu writer ~items ~enabled
  | Picker_props { selected_id; options; label; style; enabled } ->
    validate_picker ~selected_id ~label ~style options;
    (match selected_id with
     | None -> Writer.u8 writer 0
     | Some selected_id ->
       Writer.u8 writer 1;
       Writer.u64 writer selected_id);
    Writer.u16 writer (List.length options);
    List.iter
      (fun (option : Wire_frame.picker_option) ->
         Writer.u64 writer option.option_id;
         write_bool writer option.enabled;
         write_bool writer option.has_label)
      options;
    write_string writer label;
    Writer.u8 writer style;
    write_bool writer enabled
  | Slider_props { value; min; max; step; label; enabled; vertical; has_on_change } ->
    write_slider_fields
      writer
      ~lower:value
      ~upper:None
      ~min
      ~max
      ~step
      ~enabled
      ~vertical
      ~has_on_change
      ~label
      ~upper_label:None
  | Range_slider_props
      { start
      ; end_
      ; min
      ; max
      ; step
      ; label_start
      ; label_end
      ; enabled
      ; vertical
      ; has_on_change
      } ->
    write_slider_fields
      writer
      ~lower:start
      ~upper:(Some end_)
      ~min
      ~max
      ~step
      ~enabled
      ~vertical
      ~has_on_change
      ~label:label_start
      ~upper_label:(Some label_end)
  | Table_props _ as props -> write_table_props writer props
  | Divider_props -> ()
  | Label_props -> ()
  | Badge_props { count; alignment; visible } ->
    write_badge writer count alignment visible
  | Sheet_props
      { presented
      ; fullscreen
      ; detents
      ; initial
      ; interactive
      ; indicator
      ; sizing
      ; fraction
      } ->
    check_sheet_properties
      ~fullscreen
      ~detents
      ~initial
      ~interactive
      ~indicator
      ~sizing
      ~fraction;
    write_bool writer presented;
    write_bool writer fullscreen;
    Writer.u8 writer detents;
    Writer.u8 writer initial;
    write_bool writer interactive;
    write_bool writer indicator;
    Writer.u8 writer sizing;
    Writer.f64 writer fraction
  | Popover_props { presented; edge } ->
    if edge < 0 || edge > 4 then fail Invalid_props "invalid popover edge";
    write_bool writer presented;
    Writer.u8 writer edge
  | Scroll_sections_props
      { vertical; pin_headers; pin_footers; spacing; shows_indicators; initial_anchor } ->
    write_scroll_sections
      writer
      ~vertical
      ~pin_headers
      ~pin_footers
      ~spacing
      ~shows_indicators
      ~initial_anchor
  | Scroll_section_props { has_header; has_footer; hero_height; stretch } ->
    write_scroll_section writer ~has_header ~has_footer ~hero_height ~stretch
  | Toolbar_props { placements } -> write_toolbar writer placements
  | Help_props { message } ->
    if String.trim message = "" then fail Invalid_props "help message must not be empty";
    write_string writer message
  | Group_box_props { has_label } -> write_bool writer has_label
  | Progress_props { value; style } ->
    validate_progress_value value;
    write_optional_f64 writer value;
    validate_progress_style value style;
    Writer.u8 writer style
  | Overlay_props { alignment } -> Writer.u8 writer (alignment_id alignment)
  | Disclosure_group_props { expanded; enabled } ->
    write_bool writer expanded;
    write_bool writer enabled
  | Toggle_props { value; enabled; style } ->
    if style < 0 || style > 3 then fail Invalid_props "invalid toggle style";
    write_bool writer value;
    write_bool writer enabled;
    Writer.u8 writer style
  | Swipe_actions_props { enabled; allows_full_swipe } ->
    write_bool writer enabled;
    write_bool writer allows_full_swipe
  | Swipe_action_props { title; side; enabled; role; background; symbol } ->
    if
      String.trim title = ""
      || side < 0
      || side > 1
      || role < 0
      || role > 2
      || symbol = Some ""
    then fail Invalid_props "invalid swipe action";
    write_string writer title;
    Writer.u8 writer side;
    write_bool writer enabled;
    Writer.u8 writer role;
    Writer.u32 writer background;
    write_optional_string writer symbol
  | Morphing_surface_props { expanded; expand_duration_ms; collapse_duration_ms } ->
    check_u32 "morph expand duration" expand_duration_ms;
    check_u32 "morph collapse duration" collapse_duration_ms;
    write_bool writer expanded;
    Writer.u32 writer expand_duration_ms;
    Writer.u32 writer collapse_duration_ms
  | Tabs_props { selection } -> write_tab_key writer selection
  | Tab_props { page_key; title; symbol; badge; accessibility_label } ->
    write_tab_props writer page_key title symbol badge accessibility_label
  | Navigation_split_props { state; sidebar_title; content_title; detail_title } ->
    if Option.is_none content_title && state.compact_column = 1
    then fail Invalid_props "two-column split cannot prefer Content";
    write_navigation_split_state writer state;
    write_string writer sidebar_title;
    write_optional_string writer content_title;
    write_string writer detail_title
  | Navigation_stack_props { title } -> write_string writer title
  | Navigation_destination_props { page_key; title; can_pop } ->
    let key = ID.Navigation.Page_key.to_string page_key in
    if String.length key = 0 then fail Invalid_props "empty navigation destination key";
    write_string writer key;
    write_string writer title;
    write_bool writer can_pop
  | Control_size_props { size } ->
    if size < 0 || size > 4 then fail Invalid_props "invalid control size";
    Writer.u8 writer size
  | Ignores_safe_area_props { regions; edges } ->
    if regions < 0 || regions > 2 || edges < 0 || edges > 15
    then fail Invalid_props "invalid safe area regions or edges";
    Writer.u8 writer regions;
    Writer.u8 writer edges
  | Safe_area_padding_props { leading; top; trailing; bottom } ->
    List.iter
      (fun value ->
         if not (Float.is_finite value)
         then fail Invalid_props "non-finite safe area inset")
      [ leading; top; trailing; bottom ];
    List.iter (Writer.f64 writer) [ leading; top; trailing; bottom ]
  | Native_widget_props { kind_id; version; capabilities; payload } ->
    let kind_id = ID.Native_widget.Kind_id.to_int kind_id in
    check_u32 "native widget kind ID" kind_id;
    check_u16 "native widget version" version;
    Writer.u32 writer kind_id;
    Writer.u16 writer version;
    Writer.u64 writer capabilities;
    check_u32 "native widget payload length" (Bytes.length payload);
    Writer.u32 writer (Bytes.length payload);
    Writer.bytes writer payload
;;

let write_bytes writer value =
  let length = Bytes.length value in
  check_u32 "byte payload length" length;
  Writer.u32 writer length;
  Writer.bytes writer value
;;

let write_string_list writer values =
  check_u16 "string list length" (List.length values);
  Writer.u16 writer (List.length values);
  List.iter (write_string writer) values
;;

let write_optional_civil_date writer = function
  | None -> Writer.u8 writer 0
  | Some date ->
    Writer.u8 writer 1;
    write_civil_date writer date
;;

let write_civil_date_range writer (range : Wire_frame.civil_date_range) =
  write_civil_date writer range.start;
  write_civil_date writer range.end_
;;

let write_optional_civil_date_range writer = function
  | None -> Writer.u8 writer 0
  | Some range ->
    Writer.u8 writer 1;
    write_civil_date_range writer range
;;

let validate_host_date_bounds ~initial ~first ~last =
  validate_date_picker
    ~selected:(Option.value initial ~default:first)
    ~first
    ~last
    ~label:"Date"
;;

let validate_host_date_range ~initial ~first ~last =
  validate_host_date_bounds ~initial:None ~first ~last;
  Option.iter
    (fun (range : Wire_frame.civil_date_range) ->
       validate_host_date_bounds ~initial:(Some range.start) ~first ~last;
       validate_host_date_bounds ~initial:(Some range.end_) ~first ~last;
       if compare_civil_date range.start range.end_ > 0
       then fail Invalid_props "date range is reversed")
    initial
;;

let write_host_request body request_id payload =
  let request_id = ID.Host.Request_id.to_int64 request_id in
  check_u64 "host request ID" request_id;
  Writer.u64 body request_id;
  let request_kind, write_payload =
    match payload with
    | Wire_frame.Clipboard_read ->
      Generated_protocol.Host_request.clipboard_read, fun () -> ()
    | Clipboard_write { text } ->
      Generated_protocol.Host_request.clipboard_write, fun () -> write_string body text
    | Open_url { uri } ->
      Generated_protocol.Host_request.open_url, fun () -> write_string body uri
    | Pick_files { allowed_extensions; allow_multiple } ->
      ( Generated_protocol.Host_request.pick_files
      , fun () ->
          write_string_list body allowed_extensions;
          write_bool body allow_multiple )
    | Save_file { suggested_name; data } ->
      ( Generated_protocol.Host_request.save_file
      , fun () ->
          write_optional_string body suggested_name;
          write_bytes body data )
    | Request_focus { node_id } ->
      ( Generated_protocol.Host_request.request_focus
      , fun () ->
          let node_id = ID.Ui.Node_id.to_int64 node_id in
          check_u64 "focus node ID" node_id;
          Writer.u64 body node_id )
    | Clear_focus -> Generated_protocol.Host_request.clear_focus, fun () -> ()
    | Scroll_to { node_id; alignment; animated } ->
      ( Generated_protocol.Host_request.scroll_to
      , fun () ->
          let node_id = ID.Ui.Node_id.to_int64 node_id in
          check_u64 "scroll node ID" node_id;
          if not (Float.is_finite alignment)
          then fail Invalid_props "scroll alignment must be finite";
          Writer.u64 body node_id;
          Writer.f64 body alignment;
          write_bool body animated )
    | Set_window_title { title } ->
      Generated_protocol.Host_request.set_window_title, fun () -> write_string body title
    | Set_window_size { width; height } ->
      ( Generated_protocol.Host_request.set_window_size
      , fun () ->
          if
            not
              (Float.is_finite width
               && Float.is_finite height
               && Float.compare width 0. > 0
               && Float.compare height 0. > 0)
          then fail Invalid_props "window size must be finite and positive";
          Writer.f64 body width;
          Writer.f64 body height )
    | Show_native_menu { items } ->
      ( Generated_protocol.Host_request.show_native_menu
      , fun () ->
          (match Wire_frame.validate_native_menu_items items with
           | Ok () -> ()
           | Error message -> fail Invalid_props "%s" message);
          Writer.u16 body (List.length items);
          List.iter
            (fun (item : Wire_frame.native_menu_item) ->
               write_string body (ID.Host.Native_menu_item_id.to_string item.item_id);
               write_string body item.label;
               write_bool body item.enabled)
            items )
    | Haptic_feedback kind ->
      ( Generated_protocol.Host_request.haptic_feedback
      , fun () ->
          Writer.u8
            body
            (match kind with
             | Wire_frame.Haptic_light -> 0
             | Haptic_medium -> 1
             | Haptic_heavy -> 2
             | Haptic_selection -> 3) )
    | Platform_information ->
      Generated_protocol.Host_request.platform_information, fun () -> ()
    | Measure_layout { node_id } ->
      ( Generated_protocol.Host_request.measure_layout
      , fun () ->
          let node_id = ID.Ui.Node_id.to_int64 node_id in
          check_u64 "layout node ID" node_id;
          Writer.u64 body node_id )
    | Show_notice { message; action_label; duration_ms } ->
      ( Generated_protocol.Host_request.show_notice
      , fun () ->
          if String.length (String.trim message) = 0
          then fail Invalid_props "notification message must not be empty";
          (match action_label with
           | Some label when String.length (String.trim label) = 0 ->
             fail Invalid_props "notification action label must not be empty"
           | None | Some _ -> ());
          if duration_ms <= 0
          then fail Invalid_props "notification duration must be positive";
          check_u32 "notification duration" duration_ms;
          write_string body message;
          write_optional_string body action_label;
          Writer.u32 body duration_ms )
    | Pick_date { initial; first; last } ->
      ( Generated_protocol.Host_request.pick_date
      , fun () ->
          validate_host_date_bounds ~initial ~first ~last;
          write_optional_civil_date body initial;
          write_civil_date body first;
          write_civil_date body last )
    | Pick_date_range { initial; first; last } ->
      ( Generated_protocol.Host_request.pick_date_range
      , fun () ->
          validate_host_date_range ~initial ~first ~last;
          write_optional_civil_date_range body initial;
          write_civil_date body first;
          write_civil_date body last )
    | Pick_time { initial; format } ->
      ( Generated_protocol.Host_request.pick_time
      , fun () ->
          validate_time_picker ~value:initial ~format ~label:"Time";
          write_civil_time body initial;
          Writer.u8 body format )
  in
  Writer.u16 body (ID.Protocol.Host_request_kind.to_int request_kind);
  write_payload ()
;;

let write_bindings writer bindings =
  let count = List.length bindings in
  check_u16 "event binding count" count;
  Writer.u16 writer count;
  List.iter
    (fun (binding : Wire_frame.event_binding) ->
       let event_tag = ID.Protocol.Event_tag.to_int binding.event_tag in
       let handler_id = ID.Ui.Handler_id.to_int64 binding.handler_id in
       check_u16 "event tag" event_tag;
       check_u64 "handler ID" handler_id;
       Writer.u16 writer event_tag;
       Writer.u64 writer handler_id)
    bindings
;;

let envelope payload opcode body =
  let bytes = Writer.contents body in
  Writer.u8 payload (ID.Protocol.Operation.to_int opcode);
  Writer.u32 payload (Bytes.length bytes);
  Writer.bytes payload bytes
;;

let write_empty_envelope payload opcode =
  Writer.u8 payload (ID.Protocol.Operation.to_int opcode);
  Writer.u32 payload 0
;;

let write_operation ?(record_runtime_stats_offsets = fun _ -> ()) payload = function
  | Wire_frame.Create_node { node_id; kind; props; event_bindings } ->
    let node_id = ID.Ui.Node_id.to_int64 node_id in
    check_u64 "node ID" node_id;
    let body = Writer.create () in
    Writer.u64 body node_id;
    Writer.u16 body (ID.Protocol.Node_kind.to_int (node_kind_id kind));
    write_props body kind props;
    write_bindings body event_bindings;
    envelope payload Generated_protocol.Operation.create_node body
  | Update_props { node_id; props } ->
    let node_id = ID.Ui.Node_id.to_int64 node_id in
    check_u64 "node ID" node_id;
    let body = Writer.create () in
    Writer.u64 body node_id;
    write_update_props body props;
    envelope payload Generated_protocol.Operation.update_props body
  | Update_event_bindings { node_id; event_bindings } ->
    let node_id = ID.Ui.Node_id.to_int64 node_id in
    check_u64 "node ID" node_id;
    let body = Writer.create () in
    Writer.u64 body node_id;
    write_bindings body event_bindings;
    envelope payload Generated_protocol.Operation.update_event_bindings body
  | Set_children { node_id; children } ->
    let node_id = ID.Ui.Node_id.to_int64 node_id in
    check_u64 "node ID" node_id;
    if List.length children > Generated_protocol.Limits.max_nodes
    then fail Invalid_props "child count exceeds the node limit";
    let body = Writer.create () in
    Writer.u64 body node_id;
    Writer.u32 body (List.length children);
    List.iter
      (fun child ->
         let child = ID.Ui.Node_id.to_int64 child in
         check_u64 "child node ID" child;
         Writer.u64 body child)
      children;
    envelope payload Generated_protocol.Operation.set_children body
  | Set_root node_id ->
    let node_id = ID.Ui.Node_id.to_int64 node_id in
    check_u64 "root node ID" node_id;
    let body = Writer.create () in
    Writer.u64 body node_id;
    envelope payload Generated_protocol.Operation.set_root body
  | Set_application_theme { title; theme } ->
    let body = Writer.create () in
    Option.iter (require_theme_font_name "application title") title;
    write_optional_string body title;
    write_theme body theme;
    envelope payload Generated_protocol.Operation.set_application_theme body
  | Drop_node node_id ->
    let node_id = ID.Ui.Node_id.to_int64 node_id in
    check_u64 "node ID" node_id;
    let body = Writer.create () in
    Writer.u64 body node_id;
    envelope payload Generated_protocol.Operation.drop_node body
  | Host_request { request_id; payload = request } ->
    let body = Writer.create () in
    write_host_request body request_id request;
    envelope payload Generated_protocol.Operation.host_request body
  | Cancel_host_request { request_id } ->
    let request_id = ID.Host.Request_id.to_int64 request_id in
    check_u64 "host request ID" request_id;
    let body = Writer.create () in
    Writer.u64 body request_id;
    Writer.u16 body 0;
    envelope payload Generated_protocol.Operation.host_request body
  | Application_request { request_id; payload = application_payload } ->
    if Int64.compare request_id 0L <= 0
    then fail Invalid_props "application request ID must be positive";
    let payload_length = Bytes.length application_payload in
    if payload_length > Generated_protocol.Limits.max_application_payload_bytes
    then
      fail
        Application_payload_too_large
        "application request payload is %d bytes"
        payload_length;
    let body = Writer.create () in
    Writer.u64 body request_id;
    Writer.u32 body payload_length;
    Writer.bytes body application_payload;
    envelope payload Generated_protocol.Operation.application_request body
  | Runtime_stats stats ->
    let body = Writer.create () in
    check_u32 "event batch size" stats.event_batch_size;
    check_u64 "Bonsai flush duration" stats.bonsai_flush_ns;
    check_u64 "result read duration" stats.result_read_ns;
    check_u64 "reconcile duration" stats.reconcile_ns;
    check_u64 "encode duration" stats.encode_ns;
    check_u32 "patch count" stats.patch_count;
    check_u32 "patch bytes" stats.patch_bytes;
    check_u64 "lifecycle duration" stats.lifecycle_ns;
    check_u32 "full snapshot count" stats.full_snapshot_count;
    check_u32 "resync count" stats.resync_count;
    Writer.u32 body stats.event_batch_size;
    Writer.u64 body stats.bonsai_flush_ns;
    Writer.u64 body stats.result_read_ns;
    Writer.u64 body stats.reconcile_ns;
    let encode_ns = Writer.length body in
    Writer.u64 body stats.encode_ns;
    Writer.u32 body stats.patch_count;
    let patch_bytes = Writer.length body in
    Writer.u32 body stats.patch_bytes;
    Writer.u64 body stats.lifecycle_ns;
    Writer.u32 body stats.full_snapshot_count;
    Writer.u32 body stats.resync_count;
    let body_start = Writer.length payload + 5 in
    envelope payload Generated_protocol.Operation.runtime_notification body;
    record_runtime_stats_offsets
      Runtime_encoded_frame.
        { encode_ns = body_start + encode_ns; patch_bytes = body_start + patch_bytes }
;;

let encode_bytes frame ~record_runtime_stats_offsets =
  let operation_count = List.length frame.Wire_frame.operations + 2 in
  if operation_count > Generated_protocol.Limits.max_operations
  then fail Too_many_operations "frame has %d operations" operation_count;
  let runtime_epoch = ID.Runtime.Epoch.to_int64 frame.runtime_epoch in
  let base_revision = ID.Runtime.Renderer_revision.to_int64 frame.base_revision in
  let target_revision = ID.Runtime.Renderer_revision.to_int64 frame.target_revision in
  check_u64 "runtime epoch" runtime_epoch;
  check_u64 "base revision" base_revision;
  check_u64 "target revision" target_revision;
  let payload = Writer.create () in
  write_empty_envelope payload Generated_protocol.Operation.begin_frame;
  List.iter (write_operation ~record_runtime_stats_offsets payload) frame.operations;
  write_empty_envelope payload Generated_protocol.Operation.end_frame;
  let payload = Writer.contents payload in
  let total_length = Generated_protocol.Limits.header_bytes + Bytes.length payload in
  if total_length > Generated_protocol.Limits.max_frame_bytes
  then fail Frame_too_large "encoded frame is %d bytes" total_length;
  let output = Writer.create () in
  Writer.string output "BSFR";
  Writer.u16 output Generated_protocol.protocol_major;
  Writer.u16 output Generated_protocol.protocol_minor;
  Writer.u16 output Generated_protocol.Limits.header_bytes;
  Writer.u8
    output
    (ID.Protocol.Frame_kind.to_int
       (match frame.kind with
        | Wire_frame.Full_snapshot -> Generated_protocol.Frame_kind.full_snapshot
        | Incremental_frame -> Generated_protocol.Frame_kind.incremental_frame));
  Writer.u8 output 0;
  Writer.u64 output runtime_epoch;
  Writer.u64 output base_revision;
  Writer.u64 output target_revision;
  Writer.u32 output (Bytes.length payload);
  Writer.u32 output 0;
  Writer.u32 output 0;
  Writer.bytes output payload;
  Writer.contents output
;;

let encode frame =
  try Ok (encode_bytes frame ~record_runtime_stats_offsets:(fun _ -> ())) with
  | Codec_error error -> Error error
;;

let encode_runtime_frame frame =
  try
    let discovered_offsets = ref [] in
    let encoded_bytes =
      encode_bytes frame ~record_runtime_stats_offsets:(fun offsets ->
        discovered_offsets := offsets :: !discovered_offsets)
    in
    match !discovered_offsets with
    | [ payload_offsets ] ->
      let translate offset = Generated_protocol.Limits.header_bytes + offset in
      let stats_offsets =
        Runtime_encoded_frame.
          { encode_ns = translate payload_offsets.encode_ns
          ; patch_bytes = translate payload_offsets.patch_bytes
          }
      in
      Ok Runtime_encoded_frame.{ bytes = encoded_bytes; stats_offsets }
    | [] ->
      fail
        Invalid_operation_order
        "runtime frame must contain exactly one runtime stats operation"
    | _ ->
      fail
        Invalid_operation_order
        "runtime frame must contain exactly one runtime stats operation"
  with
  | Codec_error error -> Error error
;;

let require_patch_range bytes ~offset ~width ~label =
  if offset < 0 || offset > Bytes.length bytes - width
  then fail Invalid_props "%s patch offset is outside the encoded frame" label
;;

let patch_u32 bytes offset value =
  for shift = 0 to 3 do
    Bytes.set bytes (offset + shift) (Char.chr ((value lsr (shift * 8)) land 0xff))
  done
;;

let patch_u64 bytes offset value =
  for shift = 0 to 7 do
    let byte = Int64.(shift_right_logical value (shift * 8) |> to_int) land 0xff in
    Bytes.set bytes (offset + shift) (Char.chr byte)
  done
;;

let patch_runtime_stats encoded ~encode_ns ~patch_bytes =
  try
    check_u64 "encode duration" encode_ns;
    check_u32 "patch bytes" patch_bytes;
    let bytes = Runtime_encoded_frame.bytes encoded in
    let offsets = encoded.Runtime_encoded_frame.stats_offsets in
    require_patch_range bytes ~offset:offsets.encode_ns ~width:8 ~label:"encode duration";
    require_patch_range bytes ~offset:offsets.patch_bytes ~width:4 ~label:"patch bytes";
    patch_u64 bytes offsets.encode_ns encode_ns;
    patch_u32 bytes offsets.patch_bytes patch_bytes;
    Ok ()
  with
  | Codec_error error -> Error error
;;

module Reader = struct
  type t =
    { bytes : bytes
    ; mutable position : int
    ; limit : int
    }

  let create ?limit bytes =
    { bytes; position = 0; limit = Option.value limit ~default:(Bytes.length bytes) }
  ;;

  let remaining reader = reader.limit - reader.position

  let require reader count =
    if count < 0 || count > remaining reader
    then fail Truncated_input "need %d bytes, only %d remain" count (remaining reader)
  ;;

  let u8 reader =
    require reader 1;
    let value = Char.code (Bytes.get reader.bytes reader.position) in
    reader.position <- reader.position + 1;
    value
  ;;

  let u16 reader =
    let byte0 = u8 reader in
    let byte1 = u8 reader in
    byte0 lor (byte1 lsl 8)
  ;;

  let u32 reader =
    let byte0 = u8 reader in
    let byte1 = u8 reader in
    let byte2 = u8 reader in
    let byte3 = u8 reader in
    byte0 lor (byte1 lsl 8) lor (byte2 lsl 16) lor (byte3 lsl 24)
  ;;

  let u64 reader =
    let result = ref 0L in
    for shift = 0 to 7 do
      result
      := Int64.logor !result (Int64.shift_left (Int64.of_int (u8 reader)) (shift * 8))
    done;
    !result
  ;;

  let f64 reader = Int64.float_of_bits (u64 reader)

  let sub_reader reader length =
    require reader length;
    let result =
      { bytes = reader.bytes
      ; position = reader.position
      ; limit = reader.position + length
      }
    in
    reader.position <- reader.position + length;
    result
  ;;

  let string reader length =
    require reader length;
    let result = Bytes.sub_string reader.bytes reader.position length in
    reader.position <- reader.position + length;
    result
  ;;

  let bytes reader length =
    require reader length;
    let result = Bytes.sub reader.bytes reader.position length in
    reader.position <- reader.position + length;
    result
  ;;
end

let validate_utf8 value =
  let length = String.length value in
  let continuation index =
    index < length
    &&
    let byte = Char.code value.[index] in
    byte land 0xc0 = 0x80
  in
  let rec loop index =
    if index = length
    then true
    else (
      let byte = Char.code value.[index] in
      if byte <= 0x7f
      then loop (index + 1)
      else if byte >= 0xc2 && byte <= 0xdf
      then continuation (index + 1) && loop (index + 2)
      else if byte = 0xe0
      then
        index + 2 < length
        && Char.code value.[index + 1] >= 0xa0
        && Char.code value.[index + 1] <= 0xbf
        && continuation (index + 2)
        && loop (index + 3)
      else if (byte >= 0xe1 && byte <= 0xec) || (byte >= 0xee && byte <= 0xef)
      then continuation (index + 1) && continuation (index + 2) && loop (index + 3)
      else if byte = 0xed
      then
        index + 2 < length
        && Char.code value.[index + 1] >= 0x80
        && Char.code value.[index + 1] <= 0x9f
        && continuation (index + 2)
        && loop (index + 3)
      else if byte = 0xf0
      then
        index + 3 < length
        && Char.code value.[index + 1] >= 0x90
        && Char.code value.[index + 1] <= 0xbf
        && continuation (index + 2)
        && continuation (index + 3)
        && loop (index + 4)
      else if byte >= 0xf1 && byte <= 0xf3
      then
        continuation (index + 1)
        && continuation (index + 2)
        && continuation (index + 3)
        && loop (index + 4)
      else if byte = 0xf4
      then
        index + 3 < length
        && Char.code value.[index + 1] >= 0x80
        && Char.code value.[index + 1] <= 0x8f
        && continuation (index + 2)
        && continuation (index + 3)
        && loop (index + 4)
      else false)
  in
  loop 0
;;

let read_string reader =
  let length = Reader.u32 reader in
  if length < 0 then fail Truncated_input "negative string length";
  if length > Generated_protocol.Limits.max_string_bytes
  then fail String_too_large "string is %d bytes" length;
  let value = Reader.string reader length in
  if not (validate_utf8 value) then fail Invalid_utf8 "string is not valid UTF-8";
  value
;;

let read_bool reader =
  match Reader.u8 reader with
  | 0 -> false
  | 1 -> true
  | value -> fail Invalid_props "invalid bool %d" value
;;

let read_optional_string reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some (read_string reader)
  | value -> fail Invalid_props "invalid optional string tag %d" value
;;

let read_optional_bool reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some false
  | 2 -> Some true
  | value -> fail Invalid_props "invalid optional bool tag %d" value
;;

let read_finite_f64 reader =
  let value = Reader.f64 reader in
  match Float.classify_float value with
  | FP_normal | FP_subnormal | FP_zero -> value
  | FP_infinite | FP_nan -> fail Invalid_props "float property must be finite"
;;

let read_optional_f64 reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some (read_finite_f64 reader)
  | value ->
    fail
      Invalid_props
      "invalid optional float tag %d at byte %d"
      value
      (reader.Reader.position - 1)
;;

let read_optional_u8 reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some (Reader.u8 reader)
  | value -> fail Invalid_props "invalid optional u8 tag %d" value
;;

let read_optional_argb32 reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some (Int32.of_int (Reader.u32 reader))
  | value -> fail Invalid_props "invalid optional ARGB tag %d" value
;;

let read_positive_optional_f64 reader label =
  match read_optional_f64 reader with
  | None -> None
  | Some value ->
    if Float.compare value 0. <= 0 then fail Invalid_props "%s must be positive" label;
    Some value
;;

let read_text_style reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 ->
    let font_size = read_positive_optional_f64 reader "text font size" in
    let font_weight =
      match Reader.u8 reader with
      | 0 -> None
      | 1 ->
        Some
          (match Reader.u8 reader with
           | 0 -> Wire_frame.Normal
           | 1 -> Medium
           | 2 -> Semi_bold
           | 3 -> Bold
           | value -> fail Invalid_props "invalid text font weight %d" value)
      | value -> fail Invalid_props "invalid optional text font weight tag %d" value
    in
    let line_spacing = read_optional_f64 reader in
    Option.iter
      (fun spacing ->
         if spacing < 0. then fail Invalid_props "text line spacing must be non-negative")
      line_spacing;
    let color = read_optional_argb32 reader in
    let role = Reader.u8 reader in
    if role > 8 then fail Invalid_props "invalid text role";
    let foreground =
      match Reader.u8 reader with
      | 0 -> None
      | 1 ->
        let value = Reader.u8 reader in
        if value > 8 then fail Invalid_props "invalid foreground role";
        Some value
      | _ -> fail Invalid_props "invalid foreground role flag"
    in
    let italic =
      match Reader.u8 reader with
      | 0 -> Some false
      | 1 -> Some true
      | 2 -> None
      | _ -> fail Invalid_props "invalid italic flag"
    in
    Some
      Wire_frame.{ font_size; font_weight; line_spacing; color; role; foreground; italic }
  | value -> fail Invalid_props "invalid optional text style tag %d" value
;;

let read_text_span reader : Wire_frame.text_span =
  let value = read_string reader in
  let font_size = read_positive_optional_f64 reader "text span font size" in
  let font_weight =
    match Reader.u8 reader with
    | 0 -> None
    | 1 ->
      Some
        (match Reader.u8 reader with
         | 0 -> Wire_frame.Normal
         | 1 -> Medium
         | 2 -> Semi_bold
         | 3 -> Bold
         | value -> fail Invalid_props "invalid text span weight %d" value)
    | value -> fail Invalid_props "invalid optional text span weight tag %d" value
  in
  let color = read_optional_argb32 reader in
  let italic =
    match Reader.u8 reader with
    | 0 -> Some false
    | 1 -> Some true
    | 2 -> None
    | _ -> fail Invalid_props "invalid span italic flag"
  in
  let underline = read_bool reader in
  let strikethrough = read_bool reader in
  { value; font_size; font_weight; color; italic; underline; strikethrough }
;;

let read_theme reader : Wire_frame.theme =
  let mode =
    match Reader.u8 reader with
    | 0 -> Wire_frame.System
    | 1 -> Light
    | 2 -> Dark
    | value -> fail Invalid_props "invalid color scheme %d" value
  in
  let tint = read_optional_argb32 reader in
  let font_family = read_optional_string reader in
  Option.iter (require_theme_font_name "theme font family") font_family;
  let control_size = Reader.u8 reader in
  if control_size > 5 then fail Invalid_props "invalid control size %d" control_size;
  let count = Reader.u16 reader in
  let defaults = Reader.bytes reader count in
  validate_ui_defaults defaults;
  { mode; tint; font_family; control_size; defaults }
;;

let read_text_align reader =
  match Reader.u8 reader with
  | 0 -> Wire_frame.Start
  | 1 -> Center_text
  | 2 -> End
  | value -> fail Invalid_props "invalid text alignment %d" value
;;

let read_optional_positive_u32 reader label =
  match Reader.u8 reader with
  | 0 -> None
  | 1 ->
    let value = Reader.u32 reader in
    if value = 0 then fail Invalid_props "%s must be positive" label;
    Some value
  | value -> fail Invalid_props "invalid optional u32 tag %d" value
;;

let read_text_truncation reader =
  match Reader.u8 reader with
  | 0 -> Wire_frame.Tail
  | 1 -> Head
  | 2 -> Middle
  | value -> fail Invalid_props "invalid text truncation %d" value
;;

let read_text_props reader =
  let value = read_string reader in
  let style = read_text_style reader in
  let text_align = read_text_align reader in
  let line_limit = read_optional_positive_u32 reader "text line limit" in
  let truncation = read_text_truncation reader in
  Wire_frame.{ value; style; text_align; line_limit; truncation }
;;

let read_animation reader =
  let id_value = Reader.u64 reader in
  if Int64.compare id_value 0L < 0
  then fail Invalid_props "animation id must be non-negative";
  let id = ID.Ui.Animation_id.of_int64 id_value in
  let duration_ms = Reader.u32 reader in
  let curve =
    match Reader.u8 reader with
    | 0 -> Wire_frame.Linear
    | 1 -> Ease_in
    | 2 -> Ease_out
    | 3 -> Ease_in_out
    | value -> fail Invalid_props "invalid animation curve %d" value
  in
  { id; duration_ms; curve }
;;

let read_semantics_role reader =
  match Reader.u8 reader with
  | 0 -> Wire_frame.Generic
  | 1 -> Semantics_button
  | 2 -> Link
  | 3 -> Image
  | 4 -> Header
  | 5 -> Semantics_toggle
  | 6 -> Static_text
  | value -> fail Invalid_props "invalid semantics role %d" value
;;

let read_node_kind reader =
  match Reader.u16 reader |> ID.Protocol.Node_kind.of_int with
  | value when value = Generated_protocol.Node_kind.empty -> Wire_frame.Empty
  | value when value = Generated_protocol.Node_kind.text -> Text
  | value when value = Generated_protocol.Node_kind.rich_text -> Rich_text
  | value when value = Generated_protocol.Node_kind.symbol -> Symbol
  | value when value = Generated_protocol.Node_kind.image -> Image
  | value when value = Generated_protocol.Node_kind.collection_catalog ->
    Collection_catalog
  | value when value = Generated_protocol.Node_kind.collection_window -> Collection_window
  | value when value = Generated_protocol.Node_kind.removal -> Removal
  | value when value = Generated_protocol.Node_kind.native_list -> Native_list
  | value when value = Generated_protocol.Node_kind.list_section -> List_section
  | value when value = Generated_protocol.Node_kind.list_row -> List_row
  | value when value = Generated_protocol.Node_kind.refresh -> Refresh
  | value when value = Generated_protocol.Node_kind.scroll_targets -> Scroll_targets
  | value when value = Generated_protocol.Node_kind.scroll -> Scroll
  | value when value = Generated_protocol.Node_kind.text_field -> Text_field
  | value when value = Generated_protocol.Node_kind.secure_field -> Secure_field
  | value when value = Generated_protocol.Node_kind.text_editor -> Text_editor
  | value when value = Generated_protocol.Node_kind.flow -> Flow
  | value when value = Generated_protocol.Node_kind.row -> Row
  | value when value = Generated_protocol.Node_kind.weighted_row -> Weighted_row
  | value when value = Generated_protocol.Node_kind.weighted_column -> Weighted_column
  | value when value = Generated_protocol.Node_kind.column -> Column
  | value when value = Generated_protocol.Node_kind.stack -> Stack
  | value when value = Generated_protocol.Node_kind.layout_priority -> Layout_priority
  | value when value = Generated_protocol.Node_kind.offset -> Offset
  | value when value = Generated_protocol.Node_kind.padding -> Padding
  | value when value = Generated_protocol.Node_kind.spacer -> Spacer
  | value when value = Generated_protocol.Node_kind.frame -> Frame
  | value when value = Generated_protocol.Node_kind.background -> Background
  | value when value = Generated_protocol.Node_kind.clip -> Clip
  | value when value = Generated_protocol.Node_kind.opacity -> Opacity
  | value when value = Generated_protocol.Node_kind.animated_opacity -> Animated_opacity
  | value when value = Generated_protocol.Node_kind.projection_effect -> Projection_effect
  | value when value = Generated_protocol.Node_kind.gesture -> Gesture
  | value when value = Generated_protocol.Node_kind.focus_scope -> Focus_scope
  | value when value = Generated_protocol.Node_kind.hover_region -> Hover_region
  | value when value = Generated_protocol.Node_kind.keyboard_listener -> Keyboard_listener
  | value when value = Generated_protocol.Node_kind.button -> Button
  | value when value = Generated_protocol.Node_kind.semantics -> Semantics
  | value when value = Generated_protocol.Node_kind.theme -> Theme
  | value when value = Generated_protocol.Node_kind.date_picker -> Date_picker
  | value when value = Generated_protocol.Node_kind.time_picker -> Time_picker
  | value when value = Generated_protocol.Node_kind.menu -> Menu
  | value when value = Generated_protocol.Node_kind.picker -> Picker
  | value when value = Generated_protocol.Node_kind.slider -> Slider
  | value when value = Generated_protocol.Node_kind.range_slider -> Range_slider
  | value when value = Generated_protocol.Node_kind.table -> Table
  | value when value = Generated_protocol.Node_kind.divider -> Divider
  | value when value = Generated_protocol.Node_kind.label -> Label
  | value when value = Generated_protocol.Node_kind.badge -> Badge
  | value when value = Generated_protocol.Node_kind.sheet -> Sheet
  | value when value = Generated_protocol.Node_kind.popover -> Popover
  | value when value = Generated_protocol.Node_kind.scroll_sections -> Scroll_sections
  | value when value = Generated_protocol.Node_kind.scroll_section -> Scroll_section
  | value when value = Generated_protocol.Node_kind.toolbar -> Toolbar
  | value when value = Generated_protocol.Node_kind.help -> Help
  | value when value = Generated_protocol.Node_kind.group_box -> Group_box
  | value when value = Generated_protocol.Node_kind.progress -> Progress
  | value when value = Generated_protocol.Node_kind.overlay -> Overlay
  | value when value = Generated_protocol.Node_kind.disclosure_group -> Disclosure_group
  | value when value = Generated_protocol.Node_kind.toggle -> Toggle
  | value when value = Generated_protocol.Node_kind.swipe_actions -> Swipe_actions
  | value when value = Generated_protocol.Node_kind.swipe_action -> Swipe_action
  | value when value = Generated_protocol.Node_kind.morphing_surface -> Morphing_surface
  | value when value = Generated_protocol.Node_kind.tabs -> Tabs
  | value when value = Generated_protocol.Node_kind.tab -> Tab
  | value when value = Generated_protocol.Node_kind.navigation_split -> Navigation_split
  | value when value = Generated_protocol.Node_kind.navigation_stack -> Navigation_stack
  | value when value = Generated_protocol.Node_kind.navigation_destination ->
    Navigation_destination
  | value when value = Generated_protocol.Node_kind.ignores_safe_area -> Ignores_safe_area
  | value when value = Generated_protocol.Node_kind.safe_area_padding -> Safe_area_padding
  | value when value = Generated_protocol.Node_kind.control_size -> Control_size
  | value when value = Generated_protocol.Node_kind.native_widget -> Native_widget
  | value ->
    fail Unknown_node_kind "unknown node kind %d" (ID.Protocol.Node_kind.to_int value)
;;

let read_weighted_properties reader maximum =
  let spacing = read_optional_f64 reader in
  let alignment = Reader.u8 reader in
  validate_stack_properties maximum spacing alignment;
  let count = Reader.u32 reader in
  if count > Generated_protocol.Limits.max_nodes
  then fail Invalid_props "too many weighted items";
  let items =
    List.init count (fun _ ->
      match Reader.u8 reader with
      | 0 -> Wire_frame.Intrinsic
      | 1 ->
        let weight = read_finite_f64 reader in
        if Float.compare weight 0. <= 0 then fail Invalid_props "weight must be positive";
        let fills = read_bool reader in
        Share { weight; fills }
      | _ -> fail Invalid_props "invalid weighted sizing tag")
  in
  spacing, alignment, items
;;

let read_collection_keys reader =
  let count = Reader.u32 reader in
  if count > Generated_protocol.Limits.max_nodes
  then fail Invalid_props "too many collection keys";
  let keys = List.init count (fun _ -> read_string reader) in
  validate_collection_keys keys;
  keys
;;

let read_navigation_split_state reader =
  let visibility = Reader.u8 reader in
  let compact_column = Reader.u8 reader in
  let selection_key = read_optional_string reader in
  if visibility > 3 || compact_column > 2 || selection_key = Some ""
  then fail Invalid_props "invalid split state";
  { Wire_frame.visibility
  ; compact_column
  ; selection_key = Option.map ID.Navigation.Page_key.of_string selection_key
  }
;;

let read_civil_date reader =
  let year = Reader.u16 reader in
  let month = Reader.u8 reader in
  let day = Reader.u8 reader in
  Wire_frame.{ year; month; day }
;;

let read_civil_time reader =
  let hour = Reader.u8 reader in
  let minute = Reader.u8 reader in
  Wire_frame.{ hour; minute }
;;

let read_props reader kind =
  match kind with
  | Wire_frame.Empty -> Empty_props
  | Stack ->
    let alignment : Wire_frame.alignment =
      match Reader.u8 reader with
      | 0 -> Top_start
      | 1 -> Top_center
      | 2 -> Top_end
      | 3 -> Center_start
      | 4 -> Center
      | 5 -> Center_end
      | 6 -> Bottom_start
      | 7 -> Bottom_center
      | 8 -> Bottom_end
      | _ -> fail Invalid_props "invalid stack alignment"
    in
    Stack_props { alignment }
  | Layout_priority ->
    let priority = read_finite_f64 reader in
    Layout_priority_props { priority }
  | Offset ->
    let x = read_finite_f64 reader in
    let y = read_finite_f64 reader in
    Offset_props { x; y }
  | Text -> Text_props (read_text_props reader)
  | Rich_text ->
    Rich_text_props
      { spans = List.init (Reader.u16 reader) (fun _ -> read_text_span reader) }
  | Symbol ->
    let name = read_string reader in
    let size = read_optional_f64 reader in
    let color = read_optional_argb32 reader in
    let rendering = Reader.u8 reader in
    check_symbol_properties ~name ~size ~rendering;
    Symbol_props { name; size; color; rendering }
  | Removal ->
    let request_token = Reader.u64 reader in
    let request_state = Reader.u8 reader in
    let vertical = read_bool reader in
    let collapse_vertical = read_bool reader in
    let title = read_string reader in
    let duration_ms = Reader.u32 reader in
    if request_state > 3 || String.trim title = ""
    then fail Invalid_props "invalid removal properties";
    Removal_props
      { request_token; request_state; vertical; collapse_vertical; title; duration_ms }
  | Native_list -> Native_list_props
  | List_section ->
    let has_header = read_bool reader in
    let has_footer = read_bool reader in
    let separator = Reader.u8 reader in
    if separator > 2 then fail Invalid_props "invalid list separator";
    List_section_props { has_header; has_footer; separator }
  | List_row ->
    let separator = Reader.u8 reader in
    if separator > 2 then fail Invalid_props "invalid list separator";
    List_row_props { separator }
  | Refresh ->
    let request_token = Reader.u64 reader in
    let request_state = Reader.u8 reader in
    if request_state > 2 then fail Invalid_props "invalid refresh state";
    let show_token = if read_bool reader then Some (Reader.u64 reader) else None in
    Refresh_props { request_token; request_state; show_token }
  | Scroll_targets ->
    let vertical = read_bool reader in
    let ids = List.init (Reader.u16 reader) (fun _ -> Reader.u64 reader) in
    let position = if read_bool reader then Some (Reader.u64 reader) else None in
    let fraction = Reader.f64 reader in
    let spacing = Reader.f64 reader in
    let alignment = Reader.u8 reader in
    let snapping = read_bool reader in
    let enabled = read_bool reader in
    let shows_indicators = read_bool reader in
    check_scroll_targets ~ids ~position ~fraction ~spacing ~alignment;
    Scroll_targets_props
      { vertical
      ; ids
      ; position
      ; fraction
      ; spacing
      ; alignment
      ; snapping
      ; enabled
      ; shows_indicators
      }
  | Scroll ->
    let vertical = read_bool reader in
    let shows_indicators = read_bool reader in
    let fill_viewport = read_bool reader in
    let initial_anchor = Reader.u8 reader in
    if initial_anchor > 1 then fail Invalid_props "invalid initial scroll anchor";
    Scroll_props { vertical; shows_indicators; fill_viewport; initial_anchor }
  | Collection_catalog ->
    let keys = read_collection_keys reader in
    let default_extent = Reader.f64 reader in
    let count = Reader.u32 reader in
    if count > List.length keys then fail Invalid_props "too many collection extents";
    let overrides =
      List.init count (fun _ ->
        let index = Reader.u32 reader in
        let extent = Reader.f64 reader in
        index, extent)
    in
    let overscan = Reader.u32 reader in
    let expand_duration_ms = Reader.u32 reader in
    let collapse_duration_ms = Reader.u32 reader in
    let vertical = read_bool reader in
    let initial_anchor = Reader.u8 reader in
    let initial_key = read_optional_string reader in
    let measurement_revision =
      if read_bool reader then Some (Reader.u64 reader) else None
    in
    let fields =
      Wire_frame.
        { keys
        ; default_extent
        ; overrides
        ; overscan
        ; expand_duration_ms
        ; collapse_duration_ms
        ; vertical
        ; initial_anchor
        ; initial_key
        ; measurement_revision
        }
    in
    validate_collection_catalog fields;
    Collection_catalog_props fields
  | Collection_window ->
    let first_index = Reader.u32 reader in
    let keys = read_collection_keys reader in
    Collection_window_props { first_index; keys }
  | (Text_editor | Text_field | Secure_field) as kind ->
    let session_id = Reader.u64 reader in
    let document_revision = Reader.u64 reader in
    let accepted = Reader.u64 reader in
    List.iter
      (check_u64 "text editor revision")
      [ session_id; document_revision; accepted ];
    let update_mode =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Ack
      | 1 -> Correction
      | 2 -> Force_replace
      | _ -> fail Invalid_props "invalid editor update mode"
    in
    let text = read_string reader in
    let range () =
      let start_utf16 = Reader.u32 reader in
      let end_utf16 = Reader.u32 reader in
      let range = Wire_frame.{ start_utf16; end_utf16 } in
      validate_text_range text range;
      range
    in
    let selection = range () in
    let composing =
      match Reader.u8 reader with
      | 0 -> None
      | 1 -> Some (range ())
      | _ -> fail Invalid_props "invalid editor composing flag"
    in
    validate_marked_selection selection composing;
    let enabled = read_bool reader in
    let read_only = read_bool reader in
    let submit_on_return = read_bool reader in
    let max_utf8_bytes = read_optional_positive_u32 reader "editor byte limit" in
    Option.iter
      (fun maximum ->
         if maximum > Generated_protocol.Limits.max_string_bytes
         then fail Invalid_props "invalid editor byte limit")
      max_utf8_bytes;
    let editing =
      { Wire_frame.session_id = ID.Text_input.Session_id.of_int64 session_id
      ; document_revision = ID.Text_input.Document_revision.of_int64 document_revision
      ; accepted_local_revision = ID.Text_input.Local_revision.of_int64 accepted
      ; update_mode
      ; value = { text; selection; composing }
      ; enabled
      ; read_only
      ; submit_on_return
      ; max_utf8_bytes
      }
    in
    if kind = Text_editor
    then Text_editor_props { editing; autofocus = read_bool reader }
    else (
      let label = read_string reader in
      let prompt = read_string reader in
      let keyboard = Reader.u8 reader in
      let submit_label = Reader.u8 reader in
      if keyboard > 4 || submit_label > 5
      then fail Invalid_props "invalid field input traits";
      let autofocus = read_bool reader in
      let appearance = Reader.u8 reader in
      if appearance > 1 then fail Invalid_props "invalid field appearance";
      Text_field_props
        { editing
        ; label
        ; prompt
        ; secure = kind = Secure_field
        ; keyboard
        ; submit_label
        ; appearance
        ; autofocus
        })
  | Image ->
    let source =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Resource (read_string reader)
      | 1 -> Remote (read_string reader)
      | value -> fail Invalid_props "invalid image source %d" value
    in
    check_image_source source;
    let sizing =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Original
      | 1 -> Stretch
      | 2 -> Fit
      | 3 -> Fill
      | value -> fail Invalid_props "invalid image sizing %d" value
    in
    let scale = read_finite_f64 reader in
    if scale <= 0. then fail Invalid_props "invalid image scale";
    Image_props { source; sizing; scale }
  | Weighted_row ->
    let spacing, alignment, items = read_weighted_properties reader 4 in
    Weighted_row_props { spacing; alignment; items }
  | Weighted_column ->
    let spacing, alignment, items = read_weighted_properties reader 2 in
    Weighted_column_props { spacing; alignment; items }
  | Flow ->
    let spacing = read_finite_f64 reader in
    let line_spacing = read_finite_f64 reader in
    let alignment = Reader.u8 reader in
    if spacing < 0. || line_spacing < 0. || alignment > 2
    then fail Invalid_props "invalid flow properties";
    Flow_props { spacing; line_spacing; alignment }
  | Row ->
    let spacing = read_optional_f64 reader in
    let alignment = Reader.u8 reader in
    validate_stack_properties 4 spacing alignment;
    Row_props { spacing; alignment }
  | Column ->
    let spacing = read_optional_f64 reader in
    let alignment = Reader.u8 reader in
    validate_stack_properties 2 spacing alignment;
    Column_props { spacing; alignment }
  | Button ->
    let enabled = read_bool reader in
    let role = Reader.u8 reader in
    let style = Reader.u8 reader in
    let autofocus = read_bool reader in
    check_button_properties ~role ~style;
    Button_props { enabled; role; style; autofocus }
  | Padding ->
    let leading = read_finite_f64 reader in
    let top = read_finite_f64 reader in
    let trailing = read_finite_f64 reader in
    let bottom = read_finite_f64 reader in
    List.iter validate_layout_value [ leading; top; trailing; bottom ];
    Padding_props { leading; top; trailing; bottom }
  | Spacer ->
    let min_length = read_optional_f64 reader in
    validate_spacer_minimum min_length;
    Spacer_props { min_length }
  | Frame ->
    let read_limit reader =
      match Reader.u8 reader with
      | 0 -> None
      | 1 -> Some (Points (read_finite_f64 reader))
      | 2 -> Some Fill_space
      | value -> fail Invalid_props "invalid frame limit %d" value
    in
    let width = read_optional_f64 reader in
    let height = read_optional_f64 reader in
    let min_width = read_optional_f64 reader in
    let ideal_width = read_optional_f64 reader in
    let max_width = read_limit reader in
    let min_height = read_optional_f64 reader in
    let ideal_height = read_optional_f64 reader in
    let max_height = read_limit reader in
    let alignment : Wire_frame.alignment =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Top_start
      | 1 -> Top_center
      | 2 -> Top_end
      | 3 -> Center_start
      | 4 -> Center
      | 5 -> Center_end
      | 6 -> Bottom_start
      | 7 -> Bottom_center
      | 8 -> Bottom_end
      | value -> fail Invalid_props "invalid frame alignment %d" value
    in
    let props =
      { width
      ; height
      ; min_width
      ; ideal_width
      ; max_width
      ; min_height
      ; ideal_height
      ; max_height
      ; alignment
      }
    in
    validate_frame props;
    Frame_props props
  | Background ->
    let color = Int32.of_int (Reader.u32 reader) in
    let corner_radius = read_finite_f64 reader in
    validate_surface_dimension corner_radius;
    Background_props { color; corner_radius }
  | Clip ->
    let corner_radius = read_finite_f64 reader in
    validate_surface_dimension corner_radius;
    let antialiased = read_bool reader in
    Clip_props { corner_radius; antialiased }
  | Opacity ->
    let opacity = read_finite_f64 reader in
    if Float.compare opacity 0. < 0 || Float.compare opacity 1. > 0
    then fail Invalid_props "opacity must be in 0..1";
    Opacity_props { opacity }
  | Animated_opacity ->
    let opacity = read_finite_f64 reader in
    if Float.compare opacity 0. < 0 || Float.compare opacity 1. > 0
    then fail Invalid_props "animated opacity must be in 0..1";
    Animated_opacity_props { opacity; animation = read_animation reader }
  | Projection_effect ->
    Projection_effect_props { matrix3 = Array.init 9 (fun _ -> read_finite_f64 reader) }
  | Gesture -> Gesture_props
  | Focus_scope -> Focus_scope_props { autofocus = read_bool reader }
  | Hover_region -> Hover_region_props { blocks_behind = read_bool reader }
  | Keyboard_listener ->
    let autofocus = read_bool reader in
    let key_policy =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Handled
      | 1 -> Ignored
      | value -> fail Invalid_props "invalid key policy %d" value
    in
    Keyboard_listener_props { autofocus; key_policy }
  | Semantics ->
    let label = read_optional_string reader in
    let hint = read_optional_string reader in
    let value = read_optional_string reader in
    let role = read_semantics_role reader in
    let selected = read_optional_bool reader in
    let children = Reader.u8 reader in
    if children > 2 then fail Invalid_props "invalid semantics children";
    let hidden = read_bool reader in
    let live_region = read_bool reader in
    let heading_level = read_optional_u8 reader in
    Option.iter
      (fun level ->
         if level < 1 || level > 6
         then fail Invalid_props "invalid semantics heading level")
      heading_level;
    let sort_priority = read_optional_f64 reader in
    Option.iter
      (fun value ->
         if not (Float.is_finite value)
         then fail Invalid_props "invalid semantics sort priority")
      sort_priority;
    let identifier = read_optional_string reader in
    let count = Reader.u16 reader in
    if count > 1024 then fail Invalid_props "too many semantics actions";
    let ids = Hashtbl.create count in
    let actions =
      List.init count (fun _ ->
        let id = Reader.u64 reader in
        let label = read_string reader in
        if id <= 0L || label = "" || Hashtbl.mem ids id
        then fail Invalid_props "invalid semantics action";
        Hashtbl.add ids id ();
        id, label)
    in
    Semantics_props
      { label
      ; hint
      ; value
      ; role
      ; selected
      ; children
      ; hidden
      ; live_region
      ; heading_level
      ; sort_priority
      ; identifier
      ; actions
      }
  | Theme -> Theme_props (read_theme reader)
  | Date_picker ->
    let selected = read_civil_date reader in
    let first = read_civil_date reader in
    let last = read_civil_date reader in
    let label = read_string reader in
    let enabled = read_bool reader in
    validate_date_picker ~selected ~first ~last ~label;
    Date_picker_props { selected; first; last; label; enabled }
  | Time_picker ->
    let value = read_civil_time reader in
    let format = Reader.u8 reader in
    let label = read_string reader in
    let enabled = read_bool reader in
    validate_time_picker ~value ~format ~label;
    Time_picker_props { value; format; label; enabled }
  | Menu ->
    let count = Reader.u16 reader in
    if count = 0 || count > 1024 then fail Invalid_props "menu requires 1..1024 entries";
    let items =
      List.init count (fun _ ->
        let menu_id = Reader.u64 reader in
        let kind = Reader.u8 reader in
        let enabled = read_bool reader in
        let selected = read_bool reader in
        let role = Reader.u8 reader in
        let has_label = read_bool reader in
        let child_count = Reader.u16 reader in
        Wire_frame.{ menu_id; kind; enabled; selected; role; has_label; child_count })
    in
    let enabled = read_bool reader in
    validate_menu items;
    Menu_props { items; enabled }
  | Picker ->
    let selected_id =
      match Reader.u8 reader with
      | 0 -> None
      | 1 -> Some (Reader.u64 reader)
      | value -> fail Invalid_props "invalid optional picker selected ID tag %d" value
    in
    let options =
      List.init (Reader.u16 reader) (fun _ ->
        let option_id = Reader.u64 reader in
        let enabled = read_bool reader in
        let has_label = read_bool reader in
        Wire_frame.{ option_id; enabled; has_label })
    in
    let label = read_string reader in
    let style = Reader.u8 reader in
    let enabled = read_bool reader in
    validate_picker ~selected_id ~label ~style options;
    Picker_props { selected_id; options; label; style; enabled }
  | Slider ->
    let value = Reader.f64 reader in
    let min = Reader.f64 reader in
    let max = Reader.f64 reader in
    let step = read_optional_f64 reader in
    let enabled = read_bool reader in
    let vertical = read_bool reader in
    let has_on_change = read_bool reader in
    let label = read_string reader in
    validate_slider ~value ~min ~max ~step;
    if label = "" then fail Invalid_props "empty slider label";
    Slider_props { value; min; max; step; enabled; vertical; has_on_change; label }
  | Range_slider ->
    let start = Reader.f64 reader in
    let end_ = Reader.f64 reader in
    let min = Reader.f64 reader in
    let max = Reader.f64 reader in
    let step = read_optional_f64 reader in
    let enabled = read_bool reader in
    let vertical = read_bool reader in
    let has_on_change = read_bool reader in
    let label_start = read_string reader in
    let label_end = read_string reader in
    validate_slider ~value:start ~min ~max ~step;
    validate_slider ~value:end_ ~min ~max ~step;
    if start > end_ || label_start = "" || label_end = ""
    then fail Invalid_props "invalid slider interval";
    Range_slider_props
      { start
      ; end_
      ; min
      ; max
      ; step
      ; enabled
      ; vertical
      ; has_on_change
      ; label_start
      ; label_end
      }
  | Table ->
    let columns =
      List.init (Reader.u16 reader) (fun _ ->
        let column_id = Reader.u64 reader in
        let title = read_string reader in
        let has_details = read_bool reader in
        let tooltip = read_optional_string reader in
        let numeric = read_bool reader in
        let sortable = read_bool reader in
        Wire_frame.{ column_id; title; has_details; tooltip; numeric; sortable })
    in
    let rows =
      List.init (Reader.u16 reader) (fun _ ->
        let row_id = Reader.u64 reader in
        let selection_enabled = read_bool reader in
        Wire_frame.{ row_id; selection_enabled })
    in
    let sort_column_id =
      match Reader.u8 reader with
      | 0 -> None
      | 1 -> Some (Reader.u64 reader)
      | value -> fail Invalid_props "invalid optional sort ID tag %d" value
    in
    let sort_ascending = read_bool reader in
    let selected_row_ids = List.init (Reader.u16 reader) (fun _ -> Reader.u64 reader) in
    validate_data_table ~columns ~rows ~sort_column_id ~selected_row_ids;
    let has_on_sort = read_bool reader in
    let has_on_row_selected = read_bool reader in
    Table_props
      { columns
      ; rows
      ; sort_column_id
      ; sort_ascending
      ; selected_row_ids
      ; has_on_sort
      ; has_on_row_selected
      }
  | Divider -> Divider_props
  | Label -> Label_props
  | Badge ->
    let count = if read_bool reader then Some (Reader.u64 reader) else None in
    let alignment = Reader.u8 reader in
    let visible = read_bool reader in
    validate_badge count alignment;
    Badge_props { count; alignment; visible }
  | Sheet ->
    let presented = read_bool reader in
    let fullscreen = read_bool reader in
    let detents = Reader.u8 reader in
    let initial = Reader.u8 reader in
    let interactive = read_bool reader in
    let indicator = read_bool reader in
    let sizing = Reader.u8 reader in
    let fraction = Reader.f64 reader in
    check_sheet_properties
      ~fullscreen
      ~detents
      ~initial
      ~interactive
      ~indicator
      ~sizing
      ~fraction;
    Sheet_props
      { presented
      ; fullscreen
      ; detents
      ; initial
      ; interactive
      ; indicator
      ; sizing
      ; fraction
      }
  | Popover ->
    let presented = read_bool reader in
    let edge = Reader.u8 reader in
    if edge > 4 then fail Invalid_props "invalid popover edge";
    Popover_props { presented; edge }
  | Scroll_sections ->
    let vertical = read_bool reader in
    let pin_headers = read_bool reader in
    let pin_footers = read_bool reader in
    let spacing = read_finite_f64 reader in
    if spacing < 0. then fail Invalid_props "invalid section spacing";
    let shows_indicators = read_bool reader in
    let initial_anchor = Reader.u8 reader in
    if initial_anchor > 1 then fail Invalid_props "invalid initial scroll anchor";
    Scroll_sections_props
      { vertical; pin_headers; pin_footers; spacing; shows_indicators; initial_anchor }
  | Scroll_section ->
    let has_header = read_bool reader in
    let has_footer = read_bool reader in
    let hero_height = read_optional_f64 reader in
    let stretch = read_bool reader in
    check_scroll_section ~has_header ~has_footer ~hero_height ~stretch;
    Scroll_section_props { has_header; has_footer; hero_height; stretch }
  | Toolbar ->
    let count = Reader.u16 reader in
    if count > 256 then fail Invalid_props "too many native toolbar items";
    let placements = List.init count (fun _ -> Reader.u8 reader) in
    check_toolbar placements;
    Toolbar_props { placements }
  | Help ->
    let message = read_string reader in
    if String.trim message = "" then fail Invalid_props "help message must not be empty";
    Help_props { message }
  | Group_box -> Group_box_props { has_label = read_bool reader }
  | Progress ->
    let value = read_optional_f64 reader in
    validate_progress_value value;
    let style = Reader.u8 reader in
    validate_progress_style value style;
    Progress_props { value; style }
  | Overlay ->
    let alignment =
      match Reader.u8 reader with
      | 0 -> Wire_frame.Top_start
      | 1 -> Top_center
      | 2 -> Top_end
      | 3 -> Center_start
      | 4 -> Center
      | 5 -> Center_end
      | 6 -> Bottom_start
      | 7 -> Bottom_center
      | 8 -> Bottom_end
      | value -> fail Invalid_props "invalid overlay alignment %d" value
    in
    Overlay_props { alignment }
  | Disclosure_group ->
    let expanded = read_bool reader in
    let enabled = read_bool reader in
    Disclosure_group_props { expanded; enabled }
  | Toggle ->
    let value = read_bool reader in
    let enabled = read_bool reader in
    let style = Reader.u8 reader in
    if style > 3 then fail Invalid_props "invalid toggle style";
    Toggle_props { value; enabled; style }
  | Swipe_actions ->
    let enabled = read_bool reader in
    let allows_full_swipe = read_bool reader in
    Swipe_actions_props { enabled; allows_full_swipe }
  | Swipe_action ->
    let title = read_string reader in
    let side = Reader.u8 reader in
    let enabled = read_bool reader in
    let role = Reader.u8 reader in
    let background = Reader.u32 reader in
    let symbol = read_optional_string reader in
    if String.trim title = "" || side > 1 || role > 2 || symbol = Some ""
    then fail Invalid_props "invalid swipe action";
    Swipe_action_props { title; side; enabled; role; background; symbol }
  | Morphing_surface ->
    let expanded = read_bool reader in
    let expand_duration_ms = Reader.u32 reader in
    let collapse_duration_ms = Reader.u32 reader in
    Morphing_surface_props { expanded; expand_duration_ms; collapse_duration_ms }
  | Tabs ->
    let key = read_string reader in
    if String.length key = 0 then fail Invalid_props "empty tab key";
    Tabs_props { selection = ID.Navigation.Page_key.of_string key }
  | Tab ->
    let key = read_string reader in
    if String.length key = 0 then fail Invalid_props "empty tab key";
    let title = read_string reader in
    let symbol = read_string reader in
    if String.length symbol = 0 then fail Invalid_props "empty tab symbol";
    let badge = read_optional_string reader in
    let accessibility_label = read_optional_string reader in
    validate_tab_metadata badge accessibility_label;
    Tab_props
      { page_key = ID.Navigation.Page_key.of_string key
      ; title
      ; symbol
      ; badge
      ; accessibility_label
      }
  | Navigation_split ->
    let state = read_navigation_split_state reader in
    let sidebar_title = read_string reader in
    let content_title = read_optional_string reader in
    if Option.is_none content_title && state.compact_column = 1
    then fail Invalid_props "two-column split cannot prefer Content";
    let detail_title = read_string reader in
    Navigation_split_props { state; sidebar_title; content_title; detail_title }
  | Navigation_stack -> Navigation_stack_props { title = read_string reader }
  | Navigation_destination ->
    let key = read_string reader in
    if String.length key = 0 then fail Invalid_props "empty navigation destination key";
    let title = read_string reader in
    let can_pop = read_bool reader in
    Navigation_destination_props
      { page_key = ID.Navigation.Page_key.of_string key; title; can_pop }
  | Ignores_safe_area ->
    let regions = Reader.u8 reader in
    let edges = Reader.u8 reader in
    if regions > 2 || edges > 15
    then fail Invalid_props "invalid safe area regions or edges";
    Ignores_safe_area_props { regions; edges }
  | Control_size ->
    let size = Reader.u8 reader in
    if size > 4 then fail Invalid_props "invalid control size";
    Control_size_props { size }
  | Safe_area_padding ->
    let leading = read_finite_f64 reader in
    let top = read_finite_f64 reader in
    let trailing = read_finite_f64 reader in
    let bottom = read_finite_f64 reader in
    Safe_area_padding_props { leading; top; trailing; bottom }
  | Native_widget ->
    let kind_id_value = Reader.u32 reader in
    let version = Reader.u16 reader in
    if kind_id_value = 0 then fail Invalid_props "native widget kind ID must be positive";
    if version = 0 then fail Invalid_props "native widget version must be positive";
    let capabilities = Reader.u64 reader in
    let payload_length = Reader.u32 reader in
    if payload_length < 0
    then fail Truncated_input "negative native widget payload length";
    let payload = Reader.bytes reader payload_length in
    let kind_id = ID.Native_widget.Kind_id.of_int kind_id_value in
    Native_widget_props { kind_id; version; capabilities; payload }
;;

let read_update_props reader =
  let kind = read_node_kind reader in
  let changed = Reader.u64 reader in
  let props = read_props reader kind in
  let expected = changed_fields props in
  if changed <> expected then fail Invalid_props "unsupported changed-field bitset";
  props
;;

let read_bindings reader =
  let count = Reader.u16 reader in
  List.init count (fun _ ->
    let event_tag = Reader.u16 reader |> ID.Protocol.Event_tag.of_int in
    let handler_id = Reader.u64 reader |> ID.Ui.Handler_id.of_int64 in
    Wire_frame.{ event_tag; handler_id })
;;

let read_bytes reader =
  let length = Reader.u32 reader in
  if length < 0 then fail Truncated_input "negative byte payload length";
  Reader.bytes reader length
;;

let read_string_list reader =
  let count = Reader.u16 reader in
  List.init count (fun _ -> read_string reader)
;;

let read_optional_civil_date reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some (read_civil_date reader)
  | value -> fail Invalid_props "invalid optional civil date tag %d" value
;;

let read_civil_date_range reader =
  let start = read_civil_date reader in
  let end_ = read_civil_date reader in
  Wire_frame.{ start; end_ }
;;

let read_optional_civil_date_range reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some (read_civil_date_range reader)
  | value -> fail Invalid_props "invalid optional civil date range tag %d" value
;;

let read_host_request body request_id request_kind =
  let open Wire_frame in
  let payload =
    if request_kind = Generated_protocol.Host_request.clipboard_read
    then Clipboard_read
    else if request_kind = Generated_protocol.Host_request.clipboard_write
    then Clipboard_write { text = read_string body }
    else if request_kind = Generated_protocol.Host_request.open_url
    then Open_url { uri = read_string body }
    else if request_kind = Generated_protocol.Host_request.pick_files
    then (
      let allowed_extensions = read_string_list body in
      let allow_multiple = read_bool body in
      Pick_files { allowed_extensions; allow_multiple })
    else if request_kind = Generated_protocol.Host_request.save_file
    then (
      let suggested_name = read_optional_string body in
      let data = read_bytes body in
      Save_file { suggested_name; data })
    else if request_kind = Generated_protocol.Host_request.request_focus
    then Request_focus { node_id = Reader.u64 body |> ID.Ui.Node_id.of_int64 }
    else if request_kind = Generated_protocol.Host_request.clear_focus
    then Clear_focus
    else if request_kind = Generated_protocol.Host_request.scroll_to
    then (
      let node_id = Reader.u64 body |> ID.Ui.Node_id.of_int64 in
      let alignment = read_finite_f64 body in
      let animated = read_bool body in
      Scroll_to { node_id; alignment; animated })
    else if request_kind = Generated_protocol.Host_request.set_window_title
    then Set_window_title { title = read_string body }
    else if request_kind = Generated_protocol.Host_request.set_window_size
    then (
      let width = read_finite_f64 body in
      let height = read_finite_f64 body in
      Set_window_size { width; height })
    else if request_kind = Generated_protocol.Host_request.show_native_menu
    then (
      let count = Reader.u16 body in
      let items =
        List.init count (fun _ ->
          let item_id = read_string body |> ID.Host.Native_menu_item_id.of_string in
          let label = read_string body in
          let enabled = read_bool body in
          { Wire_frame.item_id; label; enabled })
      in
      match Wire_frame.validate_native_menu_items items with
      | Ok () -> Show_native_menu { items }
      | Error message -> fail Invalid_props "%s" message)
    else if request_kind = Generated_protocol.Host_request.haptic_feedback
    then
      Haptic_feedback
        (match Reader.u8 body with
         | 0 -> Haptic_light
         | 1 -> Haptic_medium
         | 2 -> Haptic_heavy
         | 3 -> Haptic_selection
         | value -> fail Invalid_props "invalid haptic kind %d" value)
    else if request_kind = Generated_protocol.Host_request.platform_information
    then Platform_information
    else if request_kind = Generated_protocol.Host_request.measure_layout
    then Measure_layout { node_id = Reader.u64 body |> ID.Ui.Node_id.of_int64 }
    else if request_kind = Generated_protocol.Host_request.show_notice
    then (
      let message = read_string body in
      let action_label = read_optional_string body in
      let duration_ms = Reader.u32 body in
      if String.length (String.trim message) = 0
      then fail Invalid_props "notification message must not be empty";
      (match action_label with
       | Some label when String.length (String.trim label) = 0 ->
         fail Invalid_props "notification action label must not be empty"
       | None | Some _ -> ());
      if duration_ms <= 0 then fail Invalid_props "notification duration must be positive";
      Show_notice { message; action_label; duration_ms })
    else if request_kind = Generated_protocol.Host_request.pick_date
    then (
      let initial = read_optional_civil_date body in
      let first = read_civil_date body in
      let last = read_civil_date body in
      validate_host_date_bounds ~initial ~first ~last;
      Pick_date { initial; first; last })
    else if request_kind = Generated_protocol.Host_request.pick_date_range
    then (
      let initial = read_optional_civil_date_range body in
      let first = read_civil_date body in
      let last = read_civil_date body in
      validate_host_date_range ~initial ~first ~last;
      Pick_date_range { initial; first; last })
    else if request_kind = Generated_protocol.Host_request.pick_time
    then (
      let initial = read_civil_time body in
      let format = Reader.u8 body in
      validate_time_picker ~value:initial ~format ~label:"Time";
      Pick_time { initial; format })
    else
      fail
        Invalid_props
        "unknown host request kind %d"
        (ID.Protocol.Host_request_kind.to_int request_kind)
  in
  Host_request { request_id; payload }
;;

let require_empty reader =
  if Reader.remaining reader <> 0
  then
    fail Trailing_bytes "operation body has %d trailing bytes" (Reader.remaining reader)
;;

let read_operation opcode body =
  let open Wire_frame in
  let operation =
    if opcode = Generated_protocol.Operation.create_node
    then (
      let node_id = Reader.u64 body |> ID.Ui.Node_id.of_int64 in
      let kind = read_node_kind body in
      let props =
        try read_props body kind with
        | Codec_error error ->
          fail
            error.code
            "node %Ld kind %d: %s"
            (ID.Ui.Node_id.to_int64 node_id)
            (ID.Protocol.Node_kind.to_int (node_kind_id kind))
            error.message
      in
      let event_bindings = read_bindings body in
      Create_node { node_id; kind; props; event_bindings })
    else if opcode = Generated_protocol.Operation.update_props
    then (
      let node_id = Reader.u64 body |> ID.Ui.Node_id.of_int64 in
      let props = read_update_props body in
      Update_props { node_id; props })
    else if opcode = Generated_protocol.Operation.update_event_bindings
    then (
      let node_id = Reader.u64 body |> ID.Ui.Node_id.of_int64 in
      let event_bindings = read_bindings body in
      Update_event_bindings { node_id; event_bindings })
    else if opcode = Generated_protocol.Operation.set_children
    then (
      let node_id = Reader.u64 body |> ID.Ui.Node_id.of_int64 in
      let count = Reader.u32 body in
      if count < 0 || count > Generated_protocol.Limits.max_nodes
      then fail Invalid_props "invalid child count";
      let children =
        List.init count (fun _ -> Reader.u64 body |> ID.Ui.Node_id.of_int64)
      in
      Set_children { node_id; children })
    else if opcode = Generated_protocol.Operation.set_root
    then Set_root (Reader.u64 body |> ID.Ui.Node_id.of_int64)
    else if opcode = Generated_protocol.Operation.set_application_theme
    then (
      let title = read_optional_string body in
      Option.iter (require_theme_font_name "application title") title;
      Set_application_theme { title; theme = read_theme body })
    else if opcode = Generated_protocol.Operation.drop_node
    then Drop_node (Reader.u64 body |> ID.Ui.Node_id.of_int64)
    else if opcode = Generated_protocol.Operation.host_request
    then (
      let request_id = Reader.u64 body |> ID.Host.Request_id.of_int64 in
      let request_kind = Reader.u16 body in
      if request_kind = 0
      then Cancel_host_request { request_id }
      else
        read_host_request
          body
          request_id
          (ID.Protocol.Host_request_kind.of_int request_kind))
    else if opcode = Generated_protocol.Operation.runtime_notification
    then (
      let event_batch_size = Reader.u32 body in
      let bonsai_flush_ns = Reader.u64 body in
      let result_read_ns = Reader.u64 body in
      let reconcile_ns = Reader.u64 body in
      let encode_ns = Reader.u64 body in
      let patch_count = Reader.u32 body in
      let patch_bytes = Reader.u32 body in
      let lifecycle_ns = Reader.u64 body in
      let full_snapshot_count = Reader.u32 body in
      let resync_count = Reader.u32 body in
      Runtime_stats
        { event_batch_size
        ; bonsai_flush_ns
        ; result_read_ns
        ; reconcile_ns
        ; encode_ns
        ; patch_count
        ; patch_bytes
        ; lifecycle_ns
        ; full_snapshot_count
        ; resync_count
        })
    else if opcode = Generated_protocol.Operation.application_request
    then (
      let request_id = Reader.u64 body in
      if Int64.compare request_id 0L <= 0
      then fail Invalid_props "application request ID must be positive";
      let payload_length = Reader.u32 body in
      if payload_length > Generated_protocol.Limits.max_application_payload_bytes
      then
        fail
          Application_payload_too_large
          "application request payload is %d bytes"
          payload_length;
      Application_request { request_id; payload = Reader.bytes body payload_length })
    else
      fail Unknown_operation "unknown operation %d" (ID.Protocol.Operation.to_int opcode)
  in
  require_empty body;
  operation
;;

let decode bytes =
  try
    if Bytes.length bytes > Generated_protocol.Limits.max_frame_bytes
    then fail Frame_too_large "frame is %d bytes" (Bytes.length bytes);
    if Bytes.length bytes < Generated_protocol.Limits.header_bytes
    then fail Truncated_input "frame is shorter than the fixed header";
    let reader = Reader.create bytes in
    let magic = Reader.string reader 4 in
    if not (String.equal magic "BSFR") then fail Invalid_magic "invalid frame magic";
    let major = Reader.u16 reader in
    let minor = Reader.u16 reader in
    if
      major <> Generated_protocol.protocol_major
      || minor <> Generated_protocol.protocol_minor
    then fail Unsupported_version "unsupported protocol version %d.%d" major minor;
    let header_bytes = Reader.u16 reader in
    if header_bytes <> Generated_protocol.Limits.header_bytes
    then fail Invalid_header "invalid header size %d" header_bytes;
    let kind =
      match Reader.u8 reader with
      | value
        when value
             = ID.Protocol.Frame_kind.to_int Generated_protocol.Frame_kind.full_snapshot
        -> Wire_frame.Full_snapshot
      | value
        when value
             = ID.Protocol.Frame_kind.to_int
                 Generated_protocol.Frame_kind.incremental_frame -> Incremental_frame
      | value -> fail Invalid_frame_kind "invalid frame kind %d" value
    in
    let flags = Reader.u8 reader in
    if flags <> 0 then fail Invalid_flags "unsupported flags 0x%x" flags;
    let runtime_epoch = Reader.u64 reader |> ID.Runtime.Epoch.of_int64 in
    let base_revision = Reader.u64 reader |> ID.Runtime.Renderer_revision.of_int64 in
    let target_revision = Reader.u64 reader |> ID.Runtime.Renderer_revision.of_int64 in
    let payload_length = Reader.u32 reader in
    let checksum = Reader.u32 reader in
    let reserved = Reader.u32 reader in
    if checksum <> 0 || reserved <> 0
    then fail Invalid_header "reserved header fields are nonzero";
    if payload_length < 0 || payload_length <> Reader.remaining reader
    then fail Invalid_payload_length "payload length does not match the frame";
    let payload = Reader.sub_reader reader payload_length in
    let operation_count = ref 0 in
    let operations = ref [] in
    let saw_begin = ref false in
    let saw_end = ref false in
    while Reader.remaining payload > 0 do
      incr operation_count;
      if !operation_count > Generated_protocol.Limits.max_operations
      then fail Too_many_operations "operation limit exceeded";
      let opcode = Reader.u8 payload |> ID.Protocol.Operation.of_int in
      let body_length = Reader.u32 payload in
      if body_length < 0 then fail Truncated_input "negative operation body length";
      let body = Reader.sub_reader payload body_length in
      if opcode = Generated_protocol.Operation.begin_frame
      then (
        if !operation_count <> 1 || !saw_begin
        then fail Invalid_operation_order "BeginFrame must be first";
        require_empty body;
        saw_begin := true)
      else if opcode = Generated_protocol.Operation.end_frame
      then (
        if (not !saw_begin) || !saw_end
        then fail Invalid_operation_order "invalid EndFrame";
        require_empty body;
        saw_end := true;
        if Reader.remaining payload <> 0
        then fail Invalid_operation_order "EndFrame must be last")
      else (
        if (not !saw_begin) || !saw_end
        then fail Invalid_operation_order "operation is outside BeginFrame/EndFrame";
        operations := read_operation opcode body :: !operations)
    done;
    if (not !saw_begin) || not !saw_end
    then fail Invalid_operation_order "frame is missing BeginFrame or EndFrame";
    Ok
      Wire_frame.
        { runtime_epoch
        ; base_revision
        ; target_revision
        ; kind
        ; operations = List.rev !operations
        }
  with
  | Codec_error error -> Error error
;;
