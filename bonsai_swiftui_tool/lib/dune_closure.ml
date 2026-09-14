type csexp =
  | Atom of string
  | List of csexp list

type stanza =
  { id : int
  ; kind : string
  ; names : string list
  ; extensions : string list
  ; source_dir : string
  ; external_deps : string list
  ; internal_deps : string list
  }

module String_map = Map.Make (String)
module String_set = Set.Make (String)
module Int_set = Set.Make (Int)

let ( let* ) result f =
  match result with
  | Ok value -> f value
  | Error _ as error -> error
;;

let malformed = Error "Malformed Dune external dependency description"
let unsupported = Error "Unsupported Dune external dependency description"

let parse_csexp input =
  let input_length = String.length input in
  let rec parse index =
    if index >= input_length
    then malformed
    else (
      match input.[index] with
      | '(' -> parse_list (index + 1) []
      | '0' .. '9' -> parse_atom_length index 0
      | _ -> malformed)
  and parse_list index reversed =
    if index >= input_length
    then malformed
    else if Char.equal input.[index] ')'
    then Ok (List (List.rev reversed), index + 1)
    else
      let* value, next = parse index in
      parse_list next (value :: reversed)
  and parse_atom_length index length =
    if index >= input_length
    then malformed
    else (
      match input.[index] with
      | ':' ->
        if length > input_length - index - 1
        then malformed
        else (
          let atom = String.sub input (index + 1) length in
          Ok (Atom atom, index + 1 + length))
      | '0' .. '9' as digit ->
        let digit = Char.code digit - Char.code '0' in
        if length > (max_int - digit) / 10
        then malformed
        else parse_atom_length (index + 1) ((length * 10) + digit)
      | _ -> malformed)
  in
  let* value, next = parse 0 in
  if next = input_length then Ok value else malformed
;;

let atom = function
  | Atom value -> Ok value
  | List _ -> unsupported
;;

let atom_list = function
  | List values ->
    let rec loop reversed = function
      | [] -> Ok (List.rev reversed)
      | value :: rest ->
        let* value = atom value in
        loop (value :: reversed) rest
    in
    loop [] values
  | Atom _ -> unsupported
;;

let dependency_list = function
  | List dependencies ->
    let rec loop reversed = function
      | [] -> Ok (List.rev reversed)
      | List [ Atom name; Atom ("required" | "optional") ] :: rest ->
        loop (name :: reversed) rest
      | _ -> unsupported
    in
    loop [] dependencies
  | Atom _ -> unsupported
;;

let fields = function
  | List entries ->
    let add map = function
      | List [ Atom name; value ] ->
        if String_map.mem name map
        then unsupported
        else Ok (String_map.add name value map)
      | _ -> unsupported
    in
    let rec loop map = function
      | [] -> Ok map
      | entry :: rest ->
        let* map = add map entry in
        loop map rest
    in
    loop String_map.empty entries
  | Atom _ -> unsupported
;;

let required_field name values =
  match String_map.find_opt name values with
  | Some value -> Ok value
  | None -> unsupported
;;

let parse_stanza id = function
  | List [ Atom kind; raw_fields ]
    when List.mem kind [ "library"; "executables"; "tests" ] ->
    let* values = fields raw_fields in
    let allowed_fields =
      String_set.of_list
        [ "names"
        ; "extensions"
        ; "package"
        ; "source_dir"
        ; "external_deps"
        ; "internal_deps"
        ]
    in
    let actual_fields =
      String_map.fold
        (fun name _ names -> String_set.add name names)
        values
        String_set.empty
    in
    if not (String_set.subset actual_fields allowed_fields)
    then unsupported
    else
      let* names = required_field "names" values in
      let* names = atom_list names in
      let* extensions = required_field "extensions" values in
      let* extensions = atom_list extensions in
      let* source_dir = required_field "source_dir" values in
      let* source_dir = atom source_dir in
      let* external_deps = required_field "external_deps" values in
      let* external_deps = dependency_list external_deps in
      let* internal_deps = required_field "internal_deps" values in
      let* internal_deps = dependency_list internal_deps in
      Ok { id; kind; names; extensions; source_dir; external_deps; internal_deps }
  | _ -> unsupported
;;

let parse_description ~context = function
  | List [ Atom actual_context; List raw_stanzas ] when actual_context = context ->
    let rec loop id reversed = function
      | [] -> Ok (List.rev reversed)
      | raw_stanza :: rest ->
        let* stanza = parse_stanza id raw_stanza in
        loop (id + 1) (stanza :: reversed) rest
    in
    loop 0 [] raw_stanzas
  | _ -> unsupported
;;

let normalize_path path =
  path
  |> String.split_on_char '/'
  |> List.filter (fun component -> component <> "" && component <> ".")
  |> String.concat "/"
;;

let stanza_builds_target stanza target =
  let target = normalize_path target in
  List.exists
    (fun name ->
       List.exists
         (fun extension ->
            normalize_path (Filename.concat stanza.source_dir (name ^ extension)) = target)
         stanza.extensions)
    stanza.names
;;

let library_index stanzas =
  let add_name stanza index name =
    match String_map.find_opt name index with
    | None -> Ok (String_map.add name stanza index)
    | Some existing when existing.id = stanza.id -> Ok index
    | Some _ ->
      Error (Printf.sprintf "Dune workspace defines local library %s more than once" name)
  in
  let rec add_names stanza index = function
    | [] -> Ok index
    | name :: rest ->
      let* index = add_name stanza index name in
      add_names stanza index rest
  in
  let rec loop index = function
    | [] -> Ok index
    | stanza :: rest when String.equal stanza.kind "library" ->
      let* index = add_names stanza index stanza.names in
      loop index rest
    | _ :: rest -> loop index rest
  in
  loop String_map.empty stanzas
;;

let target_stanza ~target stanzas =
  match List.filter (fun stanza -> stanza_builds_target stanza target) stanzas with
  | [ stanza ] -> Ok stanza
  | [] -> Error (Printf.sprintf "Dune target stanza was not found: %s" target)
  | _ -> Error (Printf.sprintf "Dune target stanza is ambiguous: %s" target)
;;

let external_closure ~target stanzas =
  let* libraries = library_index stanzas in
  let* root = target_stanza ~target stanzas in
  let rec visit visited dependencies = function
    | [] -> Ok dependencies
    | stanza :: rest when Int_set.mem stanza.id visited -> visit visited dependencies rest
    | stanza :: rest ->
      let visited = Int_set.add stanza.id visited in
      let dependencies =
        List.fold_left
          (fun dependencies dependency -> String_set.add dependency dependencies)
          dependencies
          stanza.external_deps
      in
      let rec local_stanzas reversed = function
        | [] -> Ok (List.rev reversed)
        | dependency :: dependencies ->
          (match String_map.find_opt dependency libraries with
           | Some stanza -> local_stanzas (stanza :: reversed) dependencies
           (* Dune omits dependency-free local leaves from [external-lib-deps]. *)
           | None -> local_stanzas reversed dependencies)
      in
      let* reachable = local_stanzas [] stanza.internal_deps in
      visit visited dependencies (reachable @ rest)
  in
  let* dependencies = visit Int_set.empty String_set.empty [ root ] in
  Ok (String_set.elements dependencies)
;;

let resolve_csexp ?(context = "default") ~target input =
  let* description = parse_csexp input in
  let* stanzas = parse_description ~context description in
  external_closure ~target stanzas
;;

let resolve_project ~project_root ~target ~build_directory =
  Scaffold.ensure_directory (Filename.dirname build_directory);
  let* description =
    Process_runner.capture
      ~working_directory:project_root
      ~environment:[]
      "opam"
      [ "exec"
      ; "--switch=" ^ Plan.iphoneos_switch
      ; "--"
      ; "dune"
      ; "describe"
      ; "external-lib-deps"
      ; "--format=csexp"
      ; "--context=default.ios"
      ; "--root=" ^ project_root
      ; "--build-dir=" ^ build_directory
      ; "-x"
      ; "ios"
      ]
  in
  resolve_csexp ~context:"default.ios" ~target description
;;
