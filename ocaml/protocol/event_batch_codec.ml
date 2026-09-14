module ID = Bonsai_swiftui_spec.Id

type error_code =
  | Invalid_magic
  | Unsupported_version
  | Invalid_header
  | Invalid_frame_kind
  | Invalid_payload_length
  | Too_many_events
  | Unknown_event_tag
  | Invalid_payload
  | Invalid_utf8
  | Truncated_input
  | Trailing_bytes
  | Application_payload_too_large

type error =
  { code : error_code
  ; message : string
  }

exception Decode_error of error

let fail code format =
  Printf.ksprintf (fun message -> raise (Decode_error { code; message })) format
;;

let maximum_application_error_bytes = 4096

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

  let u64_bits reader =
    let result = ref 0L in
    for shift = 0 to 7 do
      result
      := Int64.logor !result (Int64.shift_left (Int64.of_int (u8 reader)) (shift * 8))
    done;
    !result
  ;;

  let u64 reader =
    let result = u64_bits reader in
    if Int64.compare result 0L < 0
    then fail Invalid_payload "u64 exceeds the supported positive int64 range";
    result
  ;;

  let i64 = u64_bits
  let f64 reader = Int64.float_of_bits (u64_bits reader)

  let string reader length =
    require reader length;
    let value = Bytes.sub_string reader.bytes reader.position length in
    reader.position <- reader.position + length;
    value
  ;;

  let bytes reader length =
    require reader length;
    let value = Bytes.sub reader.bytes reader.position length in
    reader.position <- reader.position + length;
    value
  ;;

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
end

module Writer = struct
  let create () = Buffer.create 128
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
  then fail Invalid_payload "string is %d bytes" length;
  let value = Reader.string reader length in
  if not (validate_utf8 value) then fail Invalid_utf8 "string is not valid UTF-8";
  value
;;

let read_optional_string reader =
  match Reader.u8 reader with
  | 0 -> None
  | 1 -> Some (read_string reader)
  | value -> fail Invalid_payload "invalid optional string tag %d" value
;;

let require_empty reader =
  if Reader.remaining reader <> 0
  then fail Trailing_bytes "event has %d trailing bytes" (Reader.remaining reader)
;;

let read_bool reader =
  match Reader.u8 reader with
  | 0 -> false
  | 1 -> true
  | value -> fail Invalid_payload "invalid bool %d" value
;;

let valid_civil_date ~year ~month ~day =
  let leap = year mod 400 = 0 || (year mod 4 = 0 && year mod 100 <> 0) in
  let days =
    [| 31; (if leap then 29 else 28); 31; 30; 31; 30; 31; 31; 30; 31; 30; 31 |]
  in
  year >= 1
  && year <= 9999
  && month >= 1
  && month <= 12
  && day >= 1
  && day <= days.(month - 1)
;;

let read_finite_f64 reader =
  let value = Reader.f64 reader in
  if not (Float.is_finite value)
  then fail Invalid_payload "environment value must be finite";
  value
;;

let read_edge_insets reader =
  let left = read_finite_f64 reader in
  let top = read_finite_f64 reader in
  let right = read_finite_f64 reader in
  let bottom = read_finite_f64 reader in
  Inbound_event.{ left; top; right; bottom }
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
        let scalar = Uchar.utf_decode_uchar decoded in
        loop
          (byte_offset + Uchar.utf_decode_length decoded)
          (utf16_offset + if Uchar.to_int scalar > 0xffff then 2 else 1))
    in
    loop 0 0)
;;

let read_text_selection reader text =
  let start_utf16 = Reader.u32 reader in
  let end_utf16 = Reader.u32 reader in
  if start_utf16 > end_utf16 then fail Invalid_payload "text range is reversed";
  if not (is_utf16_boundary text start_utf16 && is_utf16_boundary text end_utf16)
  then fail Invalid_payload "text range is not on a UTF-16 boundary";
  Inbound_event.{ start_utf16; end_utf16 }
;;

let read_pointer_kind reader =
  match Reader.u8 reader with
  | 0 -> Inbound_event.Mouse
  | 1 -> Touch
  | 2 -> Stylus
  | 3 -> Inverted_stylus
  | 4 -> Trackpad
  | 5 -> Unknown_pointer
  | value -> fail Invalid_payload "invalid pointer kind %d" value
;;

let read_position reader =
  let local_x = Reader.f64 reader in
  let local_y = Reader.f64 reader in
  let global_x = Reader.f64 reader in
  let global_y = Reader.f64 reader in
  if not (List.for_all Float.is_finite [ local_x; local_y; global_x; global_y ])
  then fail Invalid_payload "pointer coordinates must be finite";
  local_x, local_y, global_x, global_y
;;

let validate_marked_selection (selection : Inbound_event.text_selection) composing =
  Option.iter
    (fun (marked : Inbound_event.text_selection) ->
       if
         marked.start_utf16 < marked.end_utf16
         && (selection.start_utf16 < marked.start_utf16
             || selection.end_utf16 > marked.end_utf16)
       then fail Invalid_payload "composing range must contain selection")
    composing
;;

let read_payload reader event_tag =
  if
    event_tag = Generated_protocol.Event_tag.press
    || event_tag = Generated_protocol.Event_tag.long_press
    || event_tag = Generated_protocol.Event_tag.resync_requested
    || event_tag = Generated_protocol.Event_tag.text_limit_reached
  then Inbound_event.Unit
  else if
    event_tag = Generated_protocol.Event_tag.tap
    || event_tag = Generated_protocol.Event_tag.double_tap
  then (
    let local_x, local_y, global_x, global_y = read_position reader in
    let pointer_kind = read_pointer_kind reader in
    Tap { local_x; local_y; global_x; global_y; pointer_kind })
  else if
    event_tag = Generated_protocol.Event_tag.pointer_enter
    || event_tag = Generated_protocol.Event_tag.pointer_leave
    || event_tag = Generated_protocol.Event_tag.pointer_down
    || event_tag = Generated_protocol.Event_tag.pointer_up
  then (
    let pointer_id = Reader.u64 reader |> ID.Input.Pointer_id.of_int64 in
    let local_x, local_y, global_x, global_y = read_position reader in
    let pointer_kind = read_pointer_kind reader in
    let buttons = Reader.u32 reader in
    Pointer { pointer_id; local_x; local_y; global_x; global_y; pointer_kind; buttons })
  else if
    event_tag = Generated_protocol.Event_tag.focus_changed
    || event_tag = Generated_protocol.Event_tag.value_changed
  then Bool (read_bool reader)
  else if event_tag = Generated_protocol.Event_tag.text_edit
  then (
    let session_id = Reader.u64 reader |> ID.Text_input.Session_id.of_int64 in
    let local_revision = Reader.u64 reader |> ID.Text_input.Local_revision.of_int64 in
    let base_document_revision =
      Reader.u64 reader |> ID.Text_input.Document_revision.of_int64
    in
    let text = read_string reader in
    let selection = read_text_selection reader text in
    let composing =
      match Reader.u8 reader with
      | 0 -> None
      | 1 -> Some (read_text_selection reader text)
      | value -> fail Invalid_payload "invalid composing tag %d" value
    in
    validate_marked_selection selection composing;
    Text_edit
      { session_id; local_revision; base_document_revision; text; selection; composing })
  else if event_tag = Generated_protocol.Event_tag.text_submit
  then Text (read_string reader)
  else if event_tag = Generated_protocol.Event_tag.key
  then (
    let logical_key = Reader.u64 reader |> ID.Input.Logical_key.of_int64 in
    let physical_key = Reader.u64 reader |> ID.Input.Physical_key.of_int64 in
    let action =
      match Reader.u8 reader with
      | 0 -> Inbound_event.Key_down
      | 1 -> Key_up
      | 2 -> Key_repeat
      | value -> fail Invalid_payload "invalid key action %d" value
    in
    let modifiers = Reader.u32 reader in
    Key { logical_key; physical_key; action; modifiers })
  else if
    event_tag = Generated_protocol.Event_tag.animation_completed
    || event_tag = Generated_protocol.Event_tag.semantics_action
  then Int64 (Reader.u64 reader)
  else if
    event_tag = Generated_protocol.Event_tag.navigation_destination_selected
    || event_tag = Generated_protocol.Event_tag.radio_selected
    || event_tag = Generated_protocol.Event_tag.removal_completed
    || event_tag = Generated_protocol.Event_tag.refresh_request
    || event_tag = Generated_protocol.Event_tag.scroll_position_changed
    || event_tag = Generated_protocol.Event_tag.menu_action
    || event_tag = Generated_protocol.Event_tag.picker_selected
  then Int64 (Reader.i64 reader)
  else if
    event_tag = Generated_protocol.Event_tag.table_sort_requested
    || event_tag = Generated_protocol.Event_tag.table_row_selected
  then (
    let id = Reader.i64 reader in
    let value = read_bool reader in
    Int64_bool { id; value })
  else if event_tag = Generated_protocol.Event_tag.removal_requested
  then (
    let first = Reader.i64 reader in
    let second = Reader.i64 reader in
    Int64_pair { first; second })
  else if
    event_tag = Generated_protocol.Event_tag.slider_changed
    || event_tag = Generated_protocol.Event_tag.slider_change_end
  then (
    let value = Reader.f64 reader in
    if not (Float.is_finite value) then fail Invalid_payload "slider value must be finite";
    Float value)
  else if
    event_tag = Generated_protocol.Event_tag.range_slider_changed
    || event_tag = Generated_protocol.Event_tag.range_slider_change_end
  then (
    let start = Reader.f64 reader in
    let end_ = Reader.f64 reader in
    if not (Float.is_finite start && Float.is_finite end_)
    then fail Invalid_payload "range slider values must be finite";
    if Float.compare start end_ > 0
    then fail Invalid_payload "range slider values are reversed";
    Float_range { start; end_ })
  else if event_tag = Generated_protocol.Event_tag.civil_date_changed
  then (
    let year = Reader.u16 reader in
    let month = Reader.u8 reader in
    let day = Reader.u8 reader in
    if not (valid_civil_date ~year ~month ~day)
    then fail Invalid_payload "civil date is invalid";
    Civil_date { year; month; day })
  else if event_tag = Generated_protocol.Event_tag.civil_time_changed
  then (
    let hour = Reader.u8 reader in
    let minute = Reader.u8 reader in
    if hour > 23 || minute > 59 then fail Invalid_payload "civil time is invalid";
    Civil_time { hour; minute })
  else if event_tag = Generated_protocol.Event_tag.scroll_notification
  then (
    let pixels = Reader.f64 reader in
    let delta = Reader.f64 reader in
    if not (Float.is_finite pixels && Float.is_finite delta)
    then fail Invalid_payload "scroll values must be finite";
    Scroll { pixels; delta })
  else if event_tag = Generated_protocol.Event_tag.visible_range_changed
  then (
    let first_index = Reader.u64 reader in
    let last_exclusive = Reader.u64 reader in
    if Int64.compare last_exclusive first_index < 0
    then fail Invalid_payload "visible range is reversed";
    Visible_range { first_index; last_exclusive })
  else if event_tag = Generated_protocol.Event_tag.tab_selected
  then (
    let key = read_string reader in
    if String.length key = 0 then fail Invalid_payload "empty tab key";
    Tab_selected (ID.Navigation.Page_key.of_string key))
  else if event_tag = Generated_protocol.Event_tag.navigation_split_changed
  then (
    let visibility = Reader.u8 reader in
    let compact_column = Reader.u8 reader in
    let key = read_optional_string reader in
    if visibility > 3 || compact_column > 2 || key = Some ""
    then fail Invalid_payload "invalid split state";
    Navigation_split_changed
      { visibility
      ; compact_column
      ; selection_key = Option.map ID.Navigation.Page_key.of_string key
      })
  else if event_tag = Generated_protocol.Event_tag.navigation_path_changed
  then (
    let count = Reader.u32 reader in
    if count < 0 || count > 256 then fail Invalid_payload "navigation path exceeds limit";
    let seen = Hashtbl.create count in
    let keys =
      List.init count (fun _ ->
        let key = read_string reader in
        if String.length key = 0 || Hashtbl.mem seen key
        then fail Invalid_payload "empty or duplicate navigation key";
        Hashtbl.add seen key ();
        ID.Navigation.Page_key.of_string key)
    in
    Navigation_path_changed keys)
  else if event_tag = Generated_protocol.Event_tag.host_response
  then (
    let request_id = Reader.u64 reader |> ID.Host.Request_id.of_int64 in
    let status =
      match Reader.u8 reader with
      | 0 -> Inbound_event.Host_ok
      | 1 -> Host_error
      | 2 -> Host_cancelled
      | value -> fail Invalid_payload "invalid host response status %d" value
    in
    let value_length = Reader.u32 reader in
    if value_length < 0 then fail Truncated_input "negative host response length";
    let value = Reader.bytes reader value_length in
    Host_response { request_id; status; value })
  else if event_tag = Generated_protocol.Event_tag.application_response
  then (
    let request_id = Reader.u64 reader in
    if Int64.compare request_id 0L <= 0
    then fail Invalid_payload "application request ID must be positive";
    let payload_length = Reader.u32 reader in
    if payload_length > Generated_protocol.Limits.max_application_payload_bytes
    then
      fail Application_payload_too_large "application response is %d bytes" payload_length;
    Application_response { request_id; payload = Reader.bytes reader payload_length })
  else if event_tag = Generated_protocol.Event_tag.application_request_error
  then (
    let request_id = Reader.u64 reader in
    if Int64.compare request_id 0L <= 0
    then fail Invalid_payload "application request ID must be positive";
    let code =
      match Reader.u8 reader with
      | 1 -> Inbound_event.Unavailable
      | 2 -> Payload_too_large
      | 3 -> Handler_failed
      | 4 -> Cancelled
      | 5 -> Shutdown
      | 6 -> Runtime_replaced
      | 7 -> Invalid_response
      | value -> fail Invalid_payload "invalid application error code %d" value
    in
    let message_length = Reader.u32 reader in
    if message_length > maximum_application_error_bytes
    then fail Invalid_payload "application error is %d bytes" message_length;
    let message = Reader.string reader message_length in
    if not (validate_utf8 message)
    then fail Invalid_utf8 "application error is not valid UTF-8";
    Application_request_error { request_id; error = { code; message } })
  else if event_tag = Generated_protocol.Event_tag.application_event
  then (
    let payload_length = Reader.u32 reader in
    if payload_length > Generated_protocol.Limits.max_application_payload_bytes
    then fail Application_payload_too_large "application event is %d bytes" payload_length;
    Application_event (Reader.bytes reader payload_length))
  else if event_tag = Generated_protocol.Event_tag.environment_changed
  then (
    let viewport_width = read_finite_f64 reader in
    let viewport_height = read_finite_f64 reader in
    let device_pixel_ratio = read_finite_f64 reader in
    let text_scale = read_finite_f64 reader in
    if
      Float.compare viewport_width 0. < 0
      || Float.compare viewport_height 0. < 0
      || Float.compare device_pixel_ratio 0. <= 0
      || Float.compare text_scale 0. <= 0
    then fail Invalid_payload "environment dimensions and scales are invalid";
    let brightness =
      match Reader.u8 reader with
      | 0 -> Inbound_event.Environment_light
      | 1 -> Environment_dark
      | value -> fail Invalid_payload "invalid environment brightness %d" value
    in
    let platform = read_string reader in
    let locale = read_string reader in
    let safe_area = read_edge_insets reader in
    let keyboard_insets = read_edge_insets reader in
    let accessible_navigation = read_bool reader in
    let bold_text = read_bool reader in
    let invert_colors = read_bool reader in
    let disable_animations = read_bool reader in
    let reduced_motion = read_bool reader in
    let high_contrast = read_bool reader in
    let orientation =
      match Reader.u8 reader with
      | 0 -> Inbound_event.Portrait
      | 1 -> Landscape
      | value -> fail Invalid_payload "invalid orientation %d" value
    in
    let pointer_kinds = Reader.u32 reader in
    Environment_changed
      { viewport_width
      ; viewport_height
      ; device_pixel_ratio
      ; text_scale
      ; brightness
      ; platform
      ; locale
      ; safe_area
      ; keyboard_insets
      ; accessible_navigation
      ; bold_text
      ; invert_colors
      ; disable_animations
      ; reduced_motion
      ; high_contrast
      ; orientation
      ; pointer_kinds
      })
  else if event_tag = Generated_protocol.Event_tag.native_event
  then (
    let kind_id_value = Reader.u32 reader in
    let version = Reader.u16 reader in
    let event_id_value = Reader.u16 reader in
    if kind_id_value = 0 then fail Invalid_payload "native event kind ID must be positive";
    if version = 0 then fail Invalid_payload "native event version must be positive";
    if event_id_value = 0 then fail Invalid_payload "native event ID must be positive";
    let kind_id = ID.Native_widget.Kind_id.of_int kind_id_value in
    let event_id = ID.Native_widget.Event_id.of_int event_id_value in
    let payload_length = Reader.u32 reader in
    if payload_length < 0 then fail Truncated_input "negative native event payload length";
    Native_event
      { kind_id; version; event_id; payload = Reader.bytes reader payload_length })
  else
    fail
      Unknown_event_tag
      "unsupported event tag %d"
      (ID.Protocol.Event_tag.to_int event_tag)
;;

let check_u64 label value =
  if Int64.compare value 0L < 0 then fail Invalid_payload "%s must be non-negative" label
;;

let check_u32 label value =
  if value < 0 || Int64.compare (Int64.of_int value) 0xffff_ffffL > 0
  then fail Invalid_payload "%s must fit uint32" label
;;

let write_string writer value =
  let length = String.length value in
  if length > Generated_protocol.Limits.max_string_bytes
  then fail Invalid_payload "string is %d bytes" length;
  if not (validate_utf8 value) then fail Invalid_utf8 "string is not valid UTF-8";
  Writer.u32 writer length;
  Writer.string writer value
;;

let write_optional_string writer = function
  | None -> Writer.u8 writer 0
  | Some value ->
    Writer.u8 writer 1;
    write_string writer value
;;

let write_bool writer value = Writer.u8 writer (if value then 1 else 0)

let write_text_selection writer text (selection : Inbound_event.text_selection) =
  if selection.start_utf16 > selection.end_utf16
  then fail Invalid_payload "text range is reversed";
  if
    not
      (is_utf16_boundary text selection.start_utf16
       && is_utf16_boundary text selection.end_utf16)
  then fail Invalid_payload "text range is not on a UTF-16 boundary";
  Writer.u32 writer selection.start_utf16;
  Writer.u32 writer selection.end_utf16
;;

let write_edge_insets writer (insets : Inbound_event.edge_insets) =
  let values = [ insets.left; insets.top; insets.right; insets.bottom ] in
  if List.exists (fun value -> not (Float.is_finite value)) values
  then fail Invalid_payload "environment insets must be finite";
  List.iter (Writer.f64 writer) values
;;

let write_pointer_kind writer = function
  | Inbound_event.Mouse -> Writer.u8 writer 0
  | Touch -> Writer.u8 writer 1
  | Stylus -> Writer.u8 writer 2
  | Inverted_stylus -> Writer.u8 writer 3
  | Trackpad -> Writer.u8 writer 4
  | Unknown_pointer -> Writer.u8 writer 5
;;

let write_position writer ~local_x ~local_y ~global_x ~global_y =
  let values = [ local_x; local_y; global_x; global_y ] in
  if not (List.for_all Float.is_finite values)
  then fail Invalid_payload "pointer coordinates must be finite";
  List.iter (Writer.f64 writer) values
;;

let write_payload writer event_tag payload =
  let open Inbound_event in
  match payload with
  | Unit ->
    if
      event_tag <> Generated_protocol.Event_tag.press
      && event_tag <> Generated_protocol.Event_tag.long_press
      && event_tag <> Generated_protocol.Event_tag.resync_requested
      && event_tag <> Generated_protocol.Event_tag.text_limit_reached
    then fail Invalid_payload "unit payload does not match event tag"
  | Bool value ->
    if
      event_tag <> Generated_protocol.Event_tag.focus_changed
      && event_tag <> Generated_protocol.Event_tag.value_changed
    then fail Invalid_payload "bool payload does not match event tag";
    write_bool writer value
  | Text value ->
    if event_tag <> Generated_protocol.Event_tag.text_submit
    then fail Invalid_payload "text payload does not match event tag";
    write_string writer value
  | Text_edit edit ->
    if event_tag <> Generated_protocol.Event_tag.text_edit
    then fail Invalid_payload "text edit payload does not match event tag";
    validate_marked_selection edit.selection edit.composing;
    let session_id = ID.Text_input.Session_id.to_int64 edit.session_id in
    let local_revision = ID.Text_input.Local_revision.to_int64 edit.local_revision in
    let base_document_revision =
      ID.Text_input.Document_revision.to_int64 edit.base_document_revision
    in
    check_u64 "session ID" session_id;
    check_u64 "local revision" local_revision;
    check_u64 "base document revision" base_document_revision;
    Writer.u64 writer session_id;
    Writer.u64 writer local_revision;
    Writer.u64 writer base_document_revision;
    write_string writer edit.text;
    write_text_selection writer edit.text edit.selection;
    (match edit.composing with
     | None -> Writer.u8 writer 0
     | Some composing ->
       Writer.u8 writer 1;
       write_text_selection writer edit.text composing)
  | Int64 value ->
    if
      event_tag <> Generated_protocol.Event_tag.animation_completed
      && event_tag <> Generated_protocol.Event_tag.semantics_action
      && event_tag <> Generated_protocol.Event_tag.navigation_destination_selected
      && event_tag <> Generated_protocol.Event_tag.radio_selected
      && event_tag <> Generated_protocol.Event_tag.removal_completed
      && event_tag <> Generated_protocol.Event_tag.refresh_request
      && event_tag <> Generated_protocol.Event_tag.scroll_position_changed
      && event_tag <> Generated_protocol.Event_tag.menu_action
      && event_tag <> Generated_protocol.Event_tag.picker_selected
    then fail Invalid_payload "int64 payload does not match event tag";
    if
      event_tag = Generated_protocol.Event_tag.animation_completed
      || event_tag = Generated_protocol.Event_tag.semantics_action
    then check_u64 "event int64" value;
    Writer.u64 writer value
  | Int64_bool { id; value } ->
    if
      event_tag <> Generated_protocol.Event_tag.table_sort_requested
      && event_tag <> Generated_protocol.Event_tag.table_row_selected
    then fail Invalid_payload "int64-bool payload does not match event tag";
    Writer.u64 writer id;
    Writer.u8 writer (if value then 1 else 0)
  | Int64_pair { first; second } ->
    if event_tag <> Generated_protocol.Event_tag.removal_requested
    then fail Invalid_payload "int64-pair payload does not match event tag";
    Writer.u64 writer first;
    Writer.u64 writer second
  | Float value ->
    if
      event_tag <> Generated_protocol.Event_tag.slider_changed
      && event_tag <> Generated_protocol.Event_tag.slider_change_end
    then fail Invalid_payload "float payload does not match event tag";
    if not (Float.is_finite value) then fail Invalid_payload "slider value must be finite";
    Writer.f64 writer value
  | Float_range { start; end_ } ->
    if
      event_tag <> Generated_protocol.Event_tag.range_slider_changed
      && event_tag <> Generated_protocol.Event_tag.range_slider_change_end
    then fail Invalid_payload "float range payload does not match event tag";
    if not (Float.is_finite start && Float.is_finite end_)
    then fail Invalid_payload "range slider values must be finite";
    if Float.compare start end_ > 0
    then fail Invalid_payload "range slider values are reversed";
    Writer.f64 writer start;
    Writer.f64 writer end_
  | Civil_date { year; month; day } ->
    if event_tag <> Generated_protocol.Event_tag.civil_date_changed
    then fail Invalid_payload "civil date payload does not match event tag";
    if not (valid_civil_date ~year ~month ~day)
    then fail Invalid_payload "civil date is invalid";
    Writer.u16 writer year;
    Writer.u8 writer month;
    Writer.u8 writer day
  | Civil_time { hour; minute } ->
    if event_tag <> Generated_protocol.Event_tag.civil_time_changed
    then fail Invalid_payload "civil time payload does not match event tag";
    if hour < 0 || hour > 23 || minute < 0 || minute > 59
    then fail Invalid_payload "civil time is invalid";
    Writer.u8 writer hour;
    Writer.u8 writer minute
  | Tap { local_x; local_y; global_x; global_y; pointer_kind } ->
    if
      event_tag <> Generated_protocol.Event_tag.tap
      && event_tag <> Generated_protocol.Event_tag.double_tap
    then fail Invalid_payload "tap payload does not match event tag";
    write_position writer ~local_x ~local_y ~global_x ~global_y;
    write_pointer_kind writer pointer_kind
  | Pointer { pointer_id; local_x; local_y; global_x; global_y; pointer_kind; buttons } ->
    if
      event_tag <> Generated_protocol.Event_tag.pointer_enter
      && event_tag <> Generated_protocol.Event_tag.pointer_leave
      && event_tag <> Generated_protocol.Event_tag.pointer_down
      && event_tag <> Generated_protocol.Event_tag.pointer_up
    then fail Invalid_payload "pointer payload does not match event tag";
    let pointer_id = ID.Input.Pointer_id.to_int64 pointer_id in
    check_u64 "pointer ID" pointer_id;
    check_u32 "pointer buttons" buttons;
    Writer.u64 writer pointer_id;
    write_position writer ~local_x ~local_y ~global_x ~global_y;
    write_pointer_kind writer pointer_kind;
    Writer.u32 writer buttons
  | Key { logical_key; physical_key; action; modifiers } ->
    if event_tag <> Generated_protocol.Event_tag.key
    then fail Invalid_payload "key payload does not match event tag";
    let logical_key = ID.Input.Logical_key.to_int64 logical_key in
    let physical_key = ID.Input.Physical_key.to_int64 physical_key in
    check_u64 "logical key" logical_key;
    check_u64 "physical key" physical_key;
    check_u32 "key modifiers" modifiers;
    Writer.u64 writer logical_key;
    Writer.u64 writer physical_key;
    Writer.u8
      writer
      (match action with
       | Key_down -> 0
       | Key_up -> 1
       | Key_repeat -> 2);
    Writer.u32 writer modifiers
  | Scroll { pixels; delta } ->
    if event_tag <> Generated_protocol.Event_tag.scroll_notification
    then fail Invalid_payload "scroll payload does not match event tag";
    if not (Float.is_finite pixels && Float.is_finite delta)
    then fail Invalid_payload "scroll values must be finite";
    Writer.f64 writer pixels;
    Writer.f64 writer delta
  | Visible_range { first_index; last_exclusive } ->
    if event_tag <> Generated_protocol.Event_tag.visible_range_changed
    then fail Invalid_payload "visible range payload does not match event tag";
    check_u64 "first visible index" first_index;
    check_u64 "last visible index" last_exclusive;
    if Int64.compare last_exclusive first_index < 0
    then fail Invalid_payload "visible range is reversed";
    Writer.u64 writer first_index;
    Writer.u64 writer last_exclusive
  | Tab_selected key ->
    if event_tag <> Generated_protocol.Event_tag.tab_selected
    then fail Invalid_payload "tab selection tag mismatch";
    let key = ID.Navigation.Page_key.to_string key in
    if String.length key = 0 then fail Invalid_payload "empty tab key";
    write_string writer key
  | Navigation_split_changed state ->
    if event_tag <> Generated_protocol.Event_tag.navigation_split_changed
    then fail Invalid_payload "split state tag mismatch";
    let key = Option.map ID.Navigation.Page_key.to_string state.selection_key in
    if
      state.visibility < 0
      || state.visibility > 3
      || state.compact_column < 0
      || state.compact_column > 2
      || key = Some ""
    then fail Invalid_payload "invalid split state";
    Writer.u8 writer state.visibility;
    Writer.u8 writer state.compact_column;
    write_optional_string writer key
  | Navigation_path_changed keys ->
    if event_tag <> Generated_protocol.Event_tag.navigation_path_changed
    then fail Invalid_payload "navigation path payload tag mismatch";
    if List.length keys > 256 then fail Invalid_payload "navigation path exceeds limit";
    Writer.u32 writer (List.length keys);
    let seen = Hashtbl.create (List.length keys) in
    List.iter
      (fun key ->
         let key = ID.Navigation.Page_key.to_string key in
         if String.length key = 0 || Hashtbl.mem seen key
         then fail Invalid_payload "empty or duplicate navigation key";
         Hashtbl.add seen key ();
         write_string writer key)
      keys
  | Host_response { request_id; status; value } ->
    if event_tag <> Generated_protocol.Event_tag.host_response
    then fail Invalid_payload "host response payload does not match event tag";
    let request_id = ID.Host.Request_id.to_int64 request_id in
    check_u64 "host request ID" request_id;
    Writer.u64 writer request_id;
    Writer.u8
      writer
      (match status with
       | Host_ok -> 0
       | Host_error -> 1
       | Host_cancelled -> 2);
    Writer.u32 writer (Bytes.length value);
    Writer.bytes writer value
  | Application_response { request_id; payload } ->
    if event_tag <> Generated_protocol.Event_tag.application_response
    then fail Invalid_payload "application response payload does not match event tag";
    if Int64.compare request_id 0L <= 0
    then fail Invalid_payload "application request ID must be positive";
    if Bytes.length payload > Generated_protocol.Limits.max_application_payload_bytes
    then
      fail
        Application_payload_too_large
        "application response is %d bytes"
        (Bytes.length payload);
    Writer.u64 writer request_id;
    Writer.u32 writer (Bytes.length payload);
    Writer.bytes writer payload
  | Application_request_error { request_id; error } ->
    if event_tag <> Generated_protocol.Event_tag.application_request_error
    then fail Invalid_payload "application error payload does not match event tag";
    if Int64.compare request_id 0L <= 0
    then fail Invalid_payload "application request ID must be positive";
    if String.length error.message > maximum_application_error_bytes
    then
      fail Invalid_payload "application error is %d bytes" (String.length error.message);
    if not (validate_utf8 error.message)
    then fail Invalid_utf8 "application error is not valid UTF-8";
    Writer.u64 writer request_id;
    Writer.u8
      writer
      (match error.code with
       | Unavailable -> 1
       | Payload_too_large -> 2
       | Handler_failed -> 3
       | Cancelled -> 4
       | Shutdown -> 5
       | Runtime_replaced -> 6
       | Invalid_response -> 7);
    Writer.u32 writer (String.length error.message);
    Writer.string writer error.message
  | Application_event payload ->
    if event_tag <> Generated_protocol.Event_tag.application_event
    then fail Invalid_payload "application event payload does not match event tag";
    if Bytes.length payload > Generated_protocol.Limits.max_application_payload_bytes
    then
      fail
        Application_payload_too_large
        "application event is %d bytes"
        (Bytes.length payload);
    Writer.u32 writer (Bytes.length payload);
    Writer.bytes writer payload
  | Environment_changed environment ->
    if event_tag <> Generated_protocol.Event_tag.environment_changed
    then fail Invalid_payload "environment payload does not match event tag";
    let values =
      [ environment.viewport_width
      ; environment.viewport_height
      ; environment.device_pixel_ratio
      ; environment.text_scale
      ]
    in
    if List.exists (fun value -> not (Float.is_finite value)) values
    then fail Invalid_payload "environment values must be finite";
    if
      Float.compare environment.viewport_width 0. < 0
      || Float.compare environment.viewport_height 0. < 0
      || Float.compare environment.device_pixel_ratio 0. <= 0
      || Float.compare environment.text_scale 0. <= 0
    then fail Invalid_payload "environment dimensions and scales are invalid";
    List.iter (Writer.f64 writer) values;
    Writer.u8
      writer
      (match environment.brightness with
       | Environment_light -> 0
       | Environment_dark -> 1);
    write_string writer environment.platform;
    write_string writer environment.locale;
    write_edge_insets writer environment.safe_area;
    write_edge_insets writer environment.keyboard_insets;
    write_bool writer environment.accessible_navigation;
    write_bool writer environment.bold_text;
    write_bool writer environment.invert_colors;
    write_bool writer environment.disable_animations;
    write_bool writer environment.reduced_motion;
    write_bool writer environment.high_contrast;
    Writer.u8
      writer
      (match environment.orientation with
       | Portrait -> 0
       | Landscape -> 1);
    Writer.u32 writer environment.pointer_kinds
  | Native_event { kind_id; version; event_id; payload } ->
    if event_tag <> Generated_protocol.Event_tag.native_event
    then fail Invalid_payload "native payload does not match event tag";
    let kind_id = ID.Native_widget.Kind_id.to_int kind_id in
    let event_id = ID.Native_widget.Event_id.to_int event_id in
    if kind_id <= 0 || kind_id > 0xffff
    then fail Invalid_payload "native event kind ID is outside 1..65535";
    if version <= 0 || version > 0xffff
    then fail Invalid_payload "native event version is outside 1..65535";
    if event_id <= 0 || event_id > 0xffff
    then fail Invalid_payload "native event ID is outside 1..65535";
    Writer.u32 writer kind_id;
    Writer.u16 writer version;
    Writer.u16 writer event_id;
    Writer.u32 writer (Bytes.length payload);
    Writer.bytes writer payload
;;

let write_event event =
  let body = Writer.create () in
  let sequence = ID.Runtime.Event_sequence.to_int64 event.Inbound_event.sequence in
  let displayed_revision =
    ID.Runtime.Renderer_revision.to_int64 event.displayed_revision
  in
  let node_id = ID.Ui.Node_id.to_int64 event.node_id in
  let handler_id = ID.Ui.Handler_id.to_int64 event.handler_id in
  let event_tag = ID.Protocol.Event_tag.to_int event.event_tag in
  check_u64 "event sequence" sequence;
  check_u64 "displayed revision" displayed_revision;
  check_u64 "node ID" node_id;
  check_u64 "handler ID" handler_id;
  if event_tag < 0 || event_tag > 0xffff
  then fail Invalid_payload "event tag is outside u16";
  Writer.u64 body sequence;
  Writer.u64 body displayed_revision;
  Writer.u64 body node_id;
  Writer.u64 body handler_id;
  Writer.u16 body event_tag;
  write_payload body event.event_tag event.payload;
  Writer.contents body
;;

let encode batch =
  try
    let runtime_epoch = ID.Runtime.Epoch.to_int64 batch.Inbound_event.runtime_epoch in
    check_u64 "runtime epoch" runtime_epoch;
    if List.length batch.events > Generated_protocol.Limits.max_operations
    then fail Too_many_events "event count exceeds the limit";
    let payload = Writer.create () in
    Writer.u32 payload (List.length batch.events);
    let previous_sequence = ref None in
    List.iter
      (fun event ->
         if
           match !previous_sequence with
           | None -> false
           | Some previous ->
             ID.Runtime.Event_sequence.compare event.Inbound_event.sequence previous <= 0
         then fail Invalid_payload "event sequences must be strictly increasing";
         previous_sequence := Some event.sequence;
         let body = write_event event in
         Writer.u32 payload (Bytes.length body);
         Writer.bytes payload body)
      batch.events;
    let payload = Writer.contents payload in
    let base_revision, target_sequence =
      match batch.events with
      | [] -> 0L, 0L
      | first :: _ ->
        let last = List.hd (List.rev batch.events) in
        ( ID.Runtime.Renderer_revision.to_int64 first.displayed_revision
        , ID.Runtime.Event_sequence.to_int64 last.sequence )
    in
    let output = Writer.create () in
    Writer.string output "BSFR";
    Writer.u16 output Generated_protocol.protocol_major;
    Writer.u16 output Generated_protocol.protocol_minor;
    Writer.u16 output Generated_protocol.Limits.header_bytes;
    Writer.u8
      output
      (ID.Protocol.Frame_kind.to_int Generated_protocol.Frame_kind.event_batch);
    Writer.u8 output 0;
    Writer.u64 output runtime_epoch;
    Writer.u64 output base_revision;
    Writer.u64 output target_sequence;
    Writer.u32 output (Bytes.length payload);
    Writer.u32 output 0;
    Writer.u32 output 0;
    Writer.bytes output payload;
    let bytes = Writer.contents output in
    if Bytes.length bytes > Generated_protocol.Limits.max_frame_bytes
    then fail Invalid_payload_length "event batch exceeds the frame limit";
    Ok bytes
  with
  | Decode_error error -> Error error
;;

let read_event reader =
  let sequence = Reader.u64 reader |> ID.Runtime.Event_sequence.of_int64 in
  let displayed_revision = Reader.u64 reader |> ID.Runtime.Renderer_revision.of_int64 in
  let node_id = Reader.u64 reader |> ID.Ui.Node_id.of_int64 in
  let handler_id = Reader.u64 reader |> ID.Ui.Handler_id.of_int64 in
  let event_tag = Reader.u16 reader |> ID.Protocol.Event_tag.of_int in
  let payload = read_payload reader event_tag in
  require_empty reader;
  Inbound_event.{ sequence; displayed_revision; node_id; handler_id; event_tag; payload }
;;

let decode bytes =
  try
    if Bytes.length bytes > Generated_protocol.Limits.max_frame_bytes
    then fail Invalid_payload_length "event batch exceeds the frame limit";
    if Bytes.length bytes < Generated_protocol.Limits.header_bytes
    then fail Truncated_input "event batch is shorter than the fixed header";
    let reader = Reader.create bytes in
    if not (String.equal (Reader.string reader 4) "BSFR")
    then fail Invalid_magic "invalid frame magic";
    let major = Reader.u16 reader in
    let minor = Reader.u16 reader in
    if
      major <> Generated_protocol.protocol_major
      || minor <> Generated_protocol.protocol_minor
    then fail Unsupported_version "unsupported protocol version %d.%d" major minor;
    if Reader.u16 reader <> Generated_protocol.Limits.header_bytes
    then fail Invalid_header "invalid header size";
    if
      Reader.u8 reader
      <> ID.Protocol.Frame_kind.to_int Generated_protocol.Frame_kind.event_batch
    then fail Invalid_frame_kind "expected an event-batch frame";
    if Reader.u8 reader <> 0 then fail Invalid_header "unsupported frame flags";
    let runtime_epoch = Reader.u64 reader |> ID.Runtime.Epoch.of_int64 in
    let base_revision = Reader.u64 reader in
    let target_sequence = Reader.u64 reader in
    let payload_length = Reader.u32 reader in
    if Reader.u32 reader <> 0 || Reader.u32 reader <> 0
    then fail Invalid_header "reserved header fields must be zero";
    if payload_length < 0 || payload_length <> Reader.remaining reader
    then fail Invalid_payload_length "payload length does not match the event batch";
    let payload = Reader.sub_reader reader payload_length in
    let count = Reader.u32 payload in
    if count < 0 || count > Generated_protocol.Limits.max_operations
    then fail Too_many_events "event count exceeds the limit";
    let previous_sequence = ref None in
    let events =
      List.init count (fun _ ->
        let body_length = Reader.u32 payload in
        if body_length < 0 then fail Truncated_input "negative event body length";
        let event = read_event (Reader.sub_reader payload body_length) in
        if
          match !previous_sequence with
          | None -> false
          | Some previous ->
            ID.Runtime.Event_sequence.compare event.sequence previous <= 0
        then fail Invalid_payload "event sequences must be strictly increasing";
        previous_sequence := Some event.sequence;
        event)
    in
    require_empty payload;
    (match events with
     | [] ->
       if base_revision <> 0L || target_sequence <> 0L
       then fail Invalid_header "empty event batch has nonzero metadata"
     | first :: _ ->
       let last = List.hd (List.rev events) in
       if
         base_revision <> ID.Runtime.Renderer_revision.to_int64 first.displayed_revision
         || target_sequence <> ID.Runtime.Event_sequence.to_int64 last.sequence
       then fail Invalid_header "header event metadata does not match the payload");
    Ok Inbound_event.{ runtime_epoch; events }
  with
  | Decode_error error -> Error error
;;
