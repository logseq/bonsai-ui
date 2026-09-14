let fold_utf8 text ~init ~f =
  let length = String.length text in
  let rec loop byte_offset state =
    if byte_offset = length
    then state
    else (
      let decoded = String.get_utf_8_uchar text byte_offset in
      if not (Uchar.utf_decode_is_valid decoded)
      then invalid_arg "Text_editing: text must be valid UTF-8";
      let scalar = Uchar.utf_decode_uchar decoded in
      let byte_length = Uchar.utf_decode_length decoded in
      loop (byte_offset + byte_length) (f state byte_offset byte_length scalar))
  in
  loop 0 init
;;

let utf16_width scalar = if Uchar.to_int scalar > 0xffff then 2 else 1

module Utf16 = struct
  let length text =
    fold_utf8 text ~init:0 ~f:(fun length _ _ scalar -> length + utf16_width scalar)
  ;;

  let to_utf8_byte_offset text target =
    if target < 0
    then None
    else (
      let byte_length = String.length text in
      let rec loop byte_offset utf16_offset =
        if utf16_offset = target
        then Some byte_offset
        else if byte_offset = byte_length
        then None
        else (
          let decoded = String.get_utf_8_uchar text byte_offset in
          if not (Uchar.utf_decode_is_valid decoded)
          then invalid_arg "Text_editing: text must be valid UTF-8";
          let scalar = Uchar.utf_decode_uchar decoded in
          let next_utf16 = utf16_offset + utf16_width scalar in
          if target < next_utf16
          then None
          else loop (byte_offset + Uchar.utf_decode_length decoded) next_utf16)
      in
      loop 0 0)
  ;;

  let of_utf8_byte_offset text target =
    if target < 0 || target > String.length text
    then None
    else (
      let byte_length = String.length text in
      let rec loop byte_offset utf16_offset =
        if byte_offset = target
        then Some utf16_offset
        else if byte_offset = byte_length
        then None
        else (
          let decoded = String.get_utf_8_uchar text byte_offset in
          if not (Uchar.utf_decode_is_valid decoded)
          then invalid_arg "Text_editing: text must be valid UTF-8";
          let next_byte = byte_offset + Uchar.utf_decode_length decoded in
          if target < next_byte
          then None
          else loop next_byte (utf16_offset + utf16_width (Uchar.utf_decode_uchar decoded)))
      in
      loop 0 0)
  ;;
end

module Range = struct
  type t =
    { start_utf16 : int
    ; end_utf16 : int
    }

  let create ~text ~start_utf16 ~end_utf16 =
    if start_utf16 > end_utf16
    then invalid_arg "Text_editing.Range.create: range is reversed";
    if
      Option.is_none (Utf16.to_utf8_byte_offset text start_utf16)
      || Option.is_none (Utf16.to_utf8_byte_offset text end_utf16)
    then invalid_arg "Text_editing.Range.create: offset is not a UTF-16 boundary";
    { start_utf16; end_utf16 }
  ;;

  let start_utf16 t = t.start_utf16
  let end_utf16 t = t.end_utf16
  let equal left right = left = right
end

module Value = struct
  type t =
    { text : string
    ; selection : Range.t
    ; composing : Range.t option
    }

  let validate_range text range =
    ignore
      (Range.create
         ~text
         ~start_utf16:(Range.start_utf16 range)
         ~end_utf16:(Range.end_utf16 range))
  ;;

  let create ~text ~selection ?composing () =
    validate_range text selection;
    Option.iter (validate_range text) composing;
    let composing =
      Option.bind composing (fun range ->
        if Range.start_utf16 range = Range.end_utf16 range then None else Some range)
    in
    Option.iter
      (fun marked ->
         if
           Range.start_utf16 selection < Range.start_utf16 marked
           || Range.end_utf16 selection > Range.end_utf16 marked
         then
           invalid_arg "Text_editing.Value.create: composing range must contain selection")
      composing;
    { text; selection; composing }
  ;;

  let text t = t.text
  let selection t = t.selection
  let composing t = t.composing

  let equal left right =
    String.equal left.text right.text
    && Range.equal left.selection right.selection
    && Option.equal Range.equal left.composing right.composing
  ;;
end

type update_mode =
  | Ack
  | Correction
  | Force_replace

module Keyboard = struct
  type t =
    | Text
    | Number
    | Email
    | Phone
    | Url
end

module Submit_label = struct
  type t =
    | Done
    | Next
    | Search
    | Send
    | Go
    | Continue
end
