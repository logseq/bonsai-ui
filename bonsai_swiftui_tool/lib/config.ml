module Feature = struct
  type t =
    | Core
    | Network
    | Sqlite

  let equal left right = left = right

  let to_string = function
    | Core -> "core"
    | Network -> "network"
    | Sqlite -> "sqlite"
  ;;

  let of_string = function
    | "core" -> Ok Core
    | "network" -> Ok Network
    | "sqlite" -> Ok Sqlite
    | value -> Error (Printf.sprintf "Unsupported feature: %s" value)
  ;;
end

type platform =
  { minimum_version : string
  ; architectures : string list
  }

type ios = platform

type t =
  { name : string
  ; apple_root : string
  ; bundle_identifier : string
  ; native_target : string
  ; features : Feature.t list
  ; macos : platform
  ; ios : ios
  }

exception Invalid of string

let invalid format = Printf.ksprintf (fun message -> raise (Invalid message)) format

let atom = function
  | Sexplib.Sexp.Atom value -> value
  | sexp -> invalid "Expected an atom, found %s" (Sexplib.Sexp.to_string_hum sexp)
;;

let named_fields ~scope fields =
  let add acc = function
    | Sexplib.Sexp.List (Sexplib.Sexp.Atom name :: values) ->
      if List.mem_assoc name acc then invalid "Duplicate %s field: %s" scope name;
      (name, values) :: acc
    | sexp -> invalid "Invalid %s field: %s" scope (Sexplib.Sexp.to_string_hum sexp)
  in
  List.fold_left add [] fields |> List.rev
;;

let take_field ~scope ~name fields =
  match List.assoc_opt name fields with
  | Some values -> values
  | None -> invalid "Missing %s field: %s" scope name
;;

let reject_unknown ~scope ~known fields =
  List.iter
    (fun (name, _) ->
       if not (List.mem name known) then invalid "Unknown %s field: %s" scope name)
    fields
;;

let single_atom ~scope ~name fields =
  match take_field ~scope ~name fields with
  | [ value ] -> atom value
  | _ -> invalid "%s.%s must contain exactly one value" scope name
;;

let validate_relative_path ~field value =
  if not (Filename.is_relative value) then invalid "%s must be a relative path" field;
  if value = "" then invalid "%s must not be empty" field;
  if List.mem ".." (String.split_on_char '/' value)
  then invalid "%s must not contain parent traversal" field
;;

let validate_name value =
  let valid_first = function
    | 'a' .. 'z' -> true
    | _ -> false
  in
  let valid_rest = function
    | 'a' .. 'z' | '0' .. '9' | '_' -> true
    | _ -> false
  in
  if
    String.length value = 0
    || (not (valid_first value.[0]))
    || not (String.for_all valid_rest value)
  then invalid "Invalid application name: %s" value
;;

let validate_bundle_identifier value =
  let valid_component part =
    part <> ""
    && String.for_all
         (function
           | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' -> true
           | _ -> false)
         part
  in
  let components = String.split_on_char '.' value in
  if
    String.length value > 255
    || List.length components < 2
    || not (List.for_all valid_component components)
  then invalid "Invalid bundle identifier: %s" value
;;

let parse_macos values =
  let scope = "macos" in
  let fields = named_fields ~scope values in
  reject_unknown ~scope ~known:[ "minimum_version"; "architectures" ] fields;
  let minimum_version = single_atom ~scope ~name:"minimum_version" fields in
  if not (String.equal minimum_version "26.0")
  then invalid "Unsupported macOS minimum version: %s; expected 26.0" minimum_version;
  let architectures = List.map atom (take_field ~scope ~name:"architectures" fields) in
  if architectures = [] then invalid "macos.architectures must not be empty";
  if
    List.length architectures <> List.length (List.sort_uniq String.compare architectures)
  then invalid "Duplicate macOS architecture";
  List.iter
    (fun architecture ->
       if architecture <> "arm64"
       then invalid "Unsupported macOS architecture: %s" architecture)
    architectures;
  { minimum_version; architectures }
;;

let parse_ios values =
  let scope = "ios" in
  let fields = named_fields ~scope values in
  reject_unknown ~scope ~known:[ "minimum_version"; "architectures" ] fields;
  let minimum_version = single_atom ~scope ~name:"minimum_version" fields in
  if minimum_version <> "18.0"
  then invalid "Unsupported iOS minimum version: %s; expected 18.0" minimum_version;
  let architectures = List.map atom (take_field ~scope ~name:"architectures" fields) in
  if architectures = [] then invalid "ios.architectures must not be empty";
  List.iter
    (fun architecture ->
       if architecture <> "arm64"
       then invalid "Unsupported iOS architecture: %s" architecture)
    architectures;
  if
    List.length architectures <> List.length (List.sort_uniq String.compare architectures)
  then invalid "Duplicate iOS architecture";
  { minimum_version; architectures }
;;

let parse_features values =
  let features = List.map (fun value -> Feature.of_string (atom value)) values in
  let features =
    List.map
      (function
        | Ok feature -> feature
        | Error message -> raise (Invalid message))
      features
  in
  if List.exists (Feature.equal Feature.Core) features
  then invalid "The core feature is implicit and must not be listed";
  let names = List.map Feature.to_string features in
  if List.length names <> List.length (List.sort_uniq String.compare names)
  then invalid "Duplicate feature";
  Feature.Core :: features
;;

let parse_app values =
  let scope = "app" in
  let fields = named_fields ~scope values in
  reject_unknown
    ~scope
    ~known:
      [ "name"
      ; "apple_root"
      ; "bundle_identifier"
      ; "native_target"
      ; "features"
      ; "macos"
      ; "ios"
      ]
    fields;
  let name = single_atom ~scope ~name:"name" fields in
  validate_name name;
  let apple_root = single_atom ~scope ~name:"apple_root" fields in
  validate_relative_path ~field:"apple_root" apple_root;
  let bundle_identifier = single_atom ~scope ~name:"bundle_identifier" fields in
  validate_bundle_identifier bundle_identifier;
  let native_target = single_atom ~scope ~name:"native_target" fields in
  validate_relative_path ~field:"native_target" native_target;
  if not (String.ends_with ~suffix:".exe.o" native_target)
  then invalid "native_target must end in .exe.o";
  let features = parse_features (take_field ~scope ~name:"features" fields) in
  let macos = parse_macos (take_field ~scope ~name:"macos" fields) in
  let ios = parse_ios (take_field ~scope ~name:"ios" fields) in
  { name; apple_root; bundle_identifier; native_target; features; macos; ios }
;;

let parse_string input =
  try
    match Sexplib.Sexp.of_string_many input with
    | [ Sexplib.Sexp.List [ Sexplib.Sexp.Atom "lang"; Sexplib.Sexp.Atom "3" ]
      ; Sexplib.Sexp.List (Sexplib.Sexp.Atom "app" :: values)
      ] -> Ok (parse_app values)
    | Sexplib.Sexp.List [ Sexplib.Sexp.Atom "lang"; Sexplib.Sexp.Atom version ] :: _ ->
      Error (Printf.sprintf "Unsupported schema version: %s" version)
    | _ -> Error "Expected exactly (lang 3) followed by one (app ...) form"
  with
  | Invalid message -> Error message
  | exn ->
    Error
      (Printf.sprintf "Invalid S-expression configuration: %s" (Printexc.to_string exn))
;;

let parse_file path =
  try
    let channel = open_in_bin path in
    let length = in_channel_length channel in
    let input = really_input_string channel length in
    close_in channel;
    parse_string input
  with
  | Sys_error message -> Error message
;;
