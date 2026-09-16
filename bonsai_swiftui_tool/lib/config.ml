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

type requirement =
  | Exact of string
  | Revision of string

type product =
  { name : string
  ; platforms : string list
  }

type swift_package =
  { id : string
  ; url : string
  ; requirement : requirement
  ; products : product list
  }

type platform =
  { bundle_identifier : string
  ; entitlements : (string * string) list
  ; minimum_version : string
  ; architectures : string list
  }

type ios = platform

type t =
  { name : string
  ; apple_root : string
  ; swift_packages : swift_package list
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

let unique ~scope values =
  if List.length values <> List.length (List.sort_uniq String.compare values)
  then invalid "Duplicate %s" scope
;;

let parse_platform scope minimum values =
  let fields = named_fields ~scope values in
  reject_unknown
    ~scope
    ~known:[ "bundle_identifier"; "minimum_version"; "architectures"; "entitlements" ]
    fields;
  let bundle_identifier = single_atom ~scope ~name:"bundle_identifier" fields in
  List.iter
    (fun suffix -> validate_bundle_identifier (bundle_identifier ^ suffix))
    [ ""; ".test-host"; ".tests"; ".ui-tests" ];
  let minimum_version = single_atom ~scope ~name:"minimum_version" fields in
  let label = if scope = "macos" then "macOS" else "iOS" in
  if minimum_version <> minimum
  then
    invalid
      "Unsupported %s minimum version: %s; expected %s"
      label
      minimum_version
      minimum;
  let architectures = List.map atom (take_field ~scope ~name:"architectures" fields) in
  if architectures = [] then invalid "%s.architectures must not be empty" scope;
  unique ~scope:(label ^ " architecture") architectures;
  List.iter
    (fun value ->
       if value <> "arm64" then invalid "Unsupported %s architecture: %s" label value)
    architectures;
  let entitlements =
    match List.assoc_opt "entitlements" fields with
    | None -> []
    | Some values ->
      let scope = scope ^ ".entitlements" in
      let fields = named_fields ~scope values in
      let profiles = [ "debug"; "profile"; "release" ] in
      reject_unknown ~scope ~known:profiles fields;
      List.map
        (fun name ->
           let path = single_atom ~scope ~name fields in
           validate_relative_path ~field:(scope ^ "." ^ name) path;
           name, path)
        profiles
  in
  { bundle_identifier; minimum_version; architectures; entitlements }
;;

let parse_macos = parse_platform "macos" "26.0"
let parse_ios = parse_platform "ios" "18.0"

let valid_digits value =
  value <> ""
  && String.for_all
       (function
         | '0' .. '9' -> true
         | _ -> false)
       value
;;

let parse_packages values =
  let packages =
    List.map
      (function
        | Sexplib.Sexp.List (Sexplib.Sexp.Atom "package" :: values) ->
          let scope = "swift_packages.package" in
          let fields = named_fields ~scope values in
          reject_unknown ~scope ~known:[ "id"; "url"; "requirement"; "products" ] fields;
          let id = single_atom ~scope ~name:"id" fields in
          if
            id = ""
            || not
                 (String.for_all
                    (function
                      | 'a' .. 'z' | '0' .. '9' | '-' | '_' -> true
                      | _ -> false)
                    id)
          then invalid "Invalid package id: %s" id;
          if List.mem id [ "bonsaiswiftui"; "bonsai-swiftui"; "bonsai_swiftui" ]
          then invalid "Package id is reserved: %s" id;
          let url = single_atom ~scope ~name:"url" fields in
          if
            (not (String.starts_with ~prefix:"https://" url))
            || String.length url <= 8
            || String.exists
                 (fun c -> Char.code c <= 32 || List.mem c [ '?'; '#'; '@' ])
                 url
          then invalid "Package URL must be a remote HTTPS Git URL: %s" url;
          let remote_path =
            String.sub url 8 (String.length url - 8) |> String.split_on_char '/'
          in
          (match remote_path with
           | authority :: path
             when authority <> "" && path <> [] && List.exists (( <> ) "") path -> ()
           | _ -> invalid "Package URL must be a remote HTTPS Git URL: %s" url);
          let requirement =
            match take_field ~scope ~name:"requirement" fields with
            | [ Sexplib.Sexp.List [ Sexplib.Sexp.Atom "exact"; Sexplib.Sexp.Atom version ]
              ] ->
              let parts = String.split_on_char '.' version in
              if
                List.length parts <> 3
                || not
                     (List.for_all
                        (fun p -> valid_digits p && (p = "0" || p.[0] <> '0'))
                        parts)
              then invalid "Invalid exact version: %s; expected X.Y.Z" version;
              Exact version
            | [ Sexplib.Sexp.List
                  [ Sexplib.Sexp.Atom "revision"; Sexplib.Sexp.Atom revision ]
              ] ->
              if
                String.length revision <> 40
                || not
                     (String.for_all
                        (function
                          | '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true
                          | _ -> false)
                        revision)
              then invalid "Invalid full revision: %s" revision;
              Revision (String.lowercase_ascii revision)
            | _ ->
              invalid "Package requirement must be one exact version or full revision"
          in
          let products =
            List.map
              (function
                | Sexplib.Sexp.List (Sexplib.Sexp.Atom "product" :: values) ->
                  let scope = scope ^ ".product" in
                  let fields = named_fields ~scope values in
                  reject_unknown ~scope ~known:[ "name"; "platforms" ] fields;
                  let name = single_atom ~scope ~name:"name" fields in
                  if name = "" then invalid "Product name must not be empty";
                  if String.lowercase_ascii name = "bonsaiswiftui"
                  then invalid "Product name is reserved: %s" name;
                  let platforms =
                    List.map atom (take_field ~scope ~name:"platforms" fields)
                  in
                  if platforms = [] then invalid "Product platforms must not be empty";
                  unique ~scope:"product platform" platforms;
                  List.iter
                    (fun p ->
                       if not (List.mem p [ "macos"; "ios" ])
                       then invalid "Unsupported product platform: %s" p)
                    platforms;
                  { name; platforms = List.sort String.compare platforms }
                | _ -> invalid "Expected a Swift package product")
              (take_field ~scope ~name:"products" fields)
          in
          if products = [] then invalid "Package products must not be empty";
          { id
          ; url
          ; requirement
          ; products =
              List.sort
                (fun (a : product) (b : product) -> String.compare a.name b.name)
                products
          }
        | _ -> invalid "Expected a Swift package declaration")
      values
  in
  unique ~scope:"package identity" (List.map (fun p -> p.id) packages);
  let normalized_url url =
    let url = String.lowercase_ascii url in
    let url =
      if String.ends_with ~suffix:"/" url
      then String.sub url 0 (String.length url - 1)
      else url
    in
    if String.ends_with ~suffix:".git" url
    then String.sub url 0 (String.length url - 4)
    else url
  in
  unique ~scope:"package URL" (List.map (fun p -> normalized_url p.url) packages);
  unique
    ~scope:"remote package identity"
    (List.map (fun p -> Filename.basename (normalized_url p.url)) packages);
  let links =
    List.concat_map
      (fun p ->
         List.concat_map
           (fun (product : product) ->
              List.map (fun platform -> platform ^ "/" ^ product.name) product.platforms)
           p.products)
      packages
  in
  unique ~scope:"product on application target" links;
  List.sort (fun a b -> String.compare a.id b.id) packages
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
      ; "swift_packages"
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
  let native_target = single_atom ~scope ~name:"native_target" fields in
  validate_relative_path ~field:"native_target" native_target;
  if not (String.ends_with ~suffix:".exe.o" native_target)
  then invalid "native_target must end in .exe.o";
  let features = parse_features (take_field ~scope ~name:"features" fields) in
  let macos = parse_macos (take_field ~scope ~name:"macos" fields) in
  let ios = parse_ios (take_field ~scope ~name:"ios" fields) in
  let swift_packages =
    parse_packages (Option.value (List.assoc_opt "swift_packages" fields) ~default:[])
  in
  { name; apple_root; swift_packages; native_target; features; macos; ios }
;;

let parse_string input =
  try
    match Sexplib.Sexp.of_string_many input with
    | [ Sexplib.Sexp.List [ Sexplib.Sexp.Atom "lang"; Sexplib.Sexp.Atom "4" ]
      ; Sexplib.Sexp.List (Sexplib.Sexp.Atom "app" :: values)
      ] -> Ok (parse_app values)
    | Sexplib.Sexp.List [ Sexplib.Sexp.Atom "lang"; Sexplib.Sexp.Atom version ] :: _ ->
      Error
        (Printf.sprintf
           "Unsupported schema version: %s; expected (lang 4) with platform bundle \
            identifiers"
           version)
    | _ -> Error "Expected exactly (lang 4) followed by one (app ...) form"
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
