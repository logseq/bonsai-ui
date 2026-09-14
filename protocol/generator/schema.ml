type entry =
  { name : string
  ; id : int
  }

type property =
  { name : string
  ; id : int
  ; encoding : string
  }

type property_group =
  { name : string
  ; properties : property list
  }

type limits =
  { header_bytes : int
  ; max_frame_bytes : int
  ; max_string_bytes : int
  ; max_application_payload_bytes : int
  ; max_operations : int
  ; max_nodes : int
  }

type t =
  { major : int
  ; minor : int
  ; limits : limits
  ; frame_kinds : entry list
  ; operations : entry list
  ; node_kinds : entry list
  ; event_tags : entry list
  ; host_requests : entry list
  ; runtime_errors : entry list
  ; common_props : property list
  ; kind_props : property_group list
  }

type sexp =
  | Atom of string
  | List of sexp list

exception Parse_error of string

let error format = Printf.ksprintf (fun message -> raise (Parse_error message)) format

let parse_sexps text =
  let length = String.length text in
  let position = ref 0 in
  let rec skip_space () =
    while
      !position < length
      &&
      match text.[!position] with
      | ' ' | '\t' | '\r' | '\n' -> true
      | _ -> false
    do
      incr position
    done
  and parse_atom () =
    let start = !position in
    while
      !position < length
      &&
      match text.[!position] with
      | ' ' | '\t' | '\r' | '\n' | '(' | ')' -> false
      | _ -> true
    do
      incr position
    done;
    if start = !position then error "expected atom at byte %d" !position;
    Atom (String.sub text start (!position - start))
  and parse_list () =
    incr position;
    let rec items reversed =
      skip_space ();
      if !position >= length
      then error "unterminated list"
      else if Char.equal text.[!position] ')'
      then (
        incr position;
        List (List.rev reversed))
      else items (parse_one () :: reversed)
    in
    items []
  and parse_one () =
    skip_space ();
    if !position >= length
    then error "unexpected end of input"
    else (
      match text.[!position] with
      | '(' -> parse_list ()
      | ')' -> error "unexpected ')' at byte %d" !position
      | _ -> parse_atom ())
  in
  let rec all reversed =
    skip_space ();
    if !position = length then List.rev reversed else all (parse_one () :: reversed)
  in
  all []
;;

let section name sections =
  match
    List.find_opt
      (function
        | List (Atom candidate :: _) -> String.equal name candidate
        | _ -> false)
      sections
  with
  | Some (List (_ :: values)) -> values
  | Some (Atom _ | List []) -> error "invalid %s section" name
  | None -> error "missing %s section" name
;;

let optional_section name sections =
  match
    List.find_opt
      (function
        | List (Atom candidate :: _) -> String.equal name candidate
        | _ -> false)
      sections
  with
  | Some (List (_ :: values)) -> values
  | Some (Atom _ | List []) -> error "invalid %s section" name
  | None -> []
;;

let int_field name fields =
  match
    List.find_opt
      (function
        | List [ Atom candidate; Atom _ ] -> String.equal name candidate
        | _ -> false)
      fields
  with
  | Some (List [ _; Atom value ]) ->
    (match int_of_string_opt value with
     | Some value -> value
     | None -> error "%s is not an integer" name)
  | _ -> error "missing integer field %s" name
;;

let validate_entries section_name (entries : entry list) =
  let ids = Hashtbl.create (List.length entries) in
  let names = Hashtbl.create (List.length entries) in
  List.iter
    (fun (entry : entry) ->
       if entry.id < 0 || entry.id > 0xffff
       then error "%s ID %d is outside u16" section_name entry.id;
       (match Hashtbl.find_opt ids entry.id with
        | Some previous ->
          error
            "%s has duplicate ID %d for %s and %s"
            section_name
            entry.id
            previous
            entry.name
        | None -> Hashtbl.add ids entry.id entry.name);
       if Hashtbl.mem names entry.name
       then error "%s has duplicate name %s" section_name entry.name;
       Hashtbl.add names entry.name ())
    entries;
  entries
;;

let entries section_name sections : entry list =
  let values =
    match section section_name sections with
    | [ List values ] -> values
    | _ -> error "invalid %s table" section_name
  in
  values
  |> List.map (function
    | List (Atom name :: Atom id :: _) ->
      (match int_of_string_opt id with
       | Some id -> { name; id }
       | None -> error "%s ID for %s is not an integer" section_name name)
    | _ -> error "invalid entry in %s" section_name)
  |> validate_entries section_name
;;

let properties table_name values =
  let entries =
    List.map
      (function
        | List [ Atom name; Atom id; Atom encoding ] ->
          (match int_of_string_opt id with
           | Some id -> { name; id; encoding }
           | None -> error "%s ID for %s is not an integer" table_name name)
        | _ -> error "invalid property in %s" table_name)
      values
  in
  ignore
    (validate_entries
       table_name
       (List.map
          (fun (property : property) -> { name = property.name; id = property.id })
          entries));
  entries
;;

let common_props sections =
  match optional_section "common_props" sections with
  | [] -> []
  | [ List values ] -> properties "common_props" values
  | _ -> error "invalid common_props table"
;;

let kind_props sections =
  let values =
    match optional_section "kind_props" sections with
    | [] -> []
    | [ List values ] -> values
    | _ -> error "invalid kind_props table"
  in
  let names = Hashtbl.create (List.length values) in
  List.map
    (function
      | List [ Atom name; List values ] ->
        if Hashtbl.mem names name then error "kind_props has duplicate group %s" name;
        Hashtbl.add names name ();
        { name; properties = properties (name ^ " properties") values }
      | _ -> error "invalid kind_props group")
    values
;;

let parse text =
  try
    let sections =
      match parse_sexps text with
      | [ List sections ] -> sections
      | _ -> error "schema must contain one top-level list"
    in
    let protocol = section "protocol" sections in
    let limits =
      { header_bytes = int_field "header_bytes" protocol
      ; max_frame_bytes = int_field "max_frame_bytes" protocol
      ; max_string_bytes = int_field "max_string_bytes" protocol
      ; max_application_payload_bytes = int_field "max_application_payload_bytes" protocol
      ; max_operations = int_field "max_operations" protocol
      ; max_nodes = int_field "max_nodes" protocol
      }
    in
    Ok
      { major = int_field "major" protocol
      ; minor = int_field "minor" protocol
      ; limits
      ; frame_kinds = entries "frame_kinds" sections
      ; operations = entries "operations" sections
      ; node_kinds = entries "node_kinds" sections
      ; event_tags = entries "event_tags" sections
      ; host_requests = entries "host_requests" sections
      ; runtime_errors = entries "runtime_errors" sections
      ; common_props = common_props sections
      ; kind_props = kind_props sections
      }
  with
  | Parse_error message -> Error message
;;

let load path =
  try
    let channel = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in channel)
      (fun () -> really_input_string channel (in_channel_length channel) |> parse)
  with
  | Sys_error message -> Error message
;;
