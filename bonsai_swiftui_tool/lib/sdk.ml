let ( let* ) result f =
  match result with
  | Ok value -> f value
  | Error _ as error -> error
;;

let supported_bonsai_swiftui_version = "0.1.0~dev"
let supported_abi_version = "4"
let supported_build_recipe_revision = "5"
let supported_minimum_deployment_target = "26.0"

module Manifest = struct
  module String_map = Map.Make (String)

  type library =
    { package : string
    ; version : string
    ; components : string list
    }

  type t =
    { raw : Sexplib.Sexp.t
    ; format_version : string
    ; bonsai_swiftui_version : string
    ; abi_version : string
    ; ocaml_version : string
    ; dune_minimum_version : string
    ; dune_maximum_version : string
    ; cross_compiler_package : string
    ; cross_compiler_version : string
    ; findlib_toolchain : string
    ; architecture : string
    ; platform : string
    ; minimum_deployment_target : string
    ; package_universe_digest : string
    ; target_components_digest : string
    ; required_frameworks : string list
    ; required_system_libraries : string list
    ; build_recipe_revision : string
    ; packages : string String_map.t
    ; libraries : library String_map.t
    }

  let invalid format = Printf.ksprintf (fun message -> Error message) format

  let fields entries =
    let rec loop fields = function
      | [] -> Ok fields
      | Sexplib.Sexp.List (Sexplib.Sexp.Atom name :: values) :: rest ->
        if String_map.mem name fields
        then invalid "Duplicate SDK manifest field: %s" name
        else loop (String_map.add name values fields) rest
      | sexp :: _ ->
        invalid "Invalid SDK manifest field: %s" (Sexplib.Sexp.to_string_hum sexp)
    in
    loop String_map.empty entries
  ;;

  let required name fields =
    match String_map.find_opt name fields with
    | Some values -> Ok values
    | None -> invalid "Missing SDK manifest field: %s" name
  ;;

  let atom = function
    | Sexplib.Sexp.Atom value -> Ok value
    | sexp ->
      invalid "Expected SDK manifest atom, found %s" (Sexplib.Sexp.to_string_hum sexp)
  ;;

  let one name fields =
    let* values = required name fields in
    match values with
    | [ value ] -> atom value
    | _ -> invalid "SDK manifest field %s must contain exactly one value" name
  ;;

  let two name fields =
    let* values = required name fields in
    match values with
    | [ left; right ] ->
      let* left = atom left in
      let* right = atom right in
      Ok (left, right)
    | _ -> invalid "SDK manifest field %s must contain exactly two values" name
  ;;

  let atom_list name fields =
    let* values = required name fields in
    let rec loop reversed = function
      | [] -> Ok (List.rev reversed)
      | value :: rest ->
        let* value = atom value in
        loop (value :: reversed) rest
    in
    loop [] values
  ;;

  let package_map fields =
    let* values = required "packages" fields in
    let rec loop packages = function
      | [] -> Ok packages
      | Sexplib.Sexp.List [ Sexplib.Sexp.Atom name; Sexplib.Sexp.Atom version ] :: rest ->
        if String_map.mem name packages
        then invalid "Duplicate SDK package: %s" name
        else loop (String_map.add name version packages) rest
      | sexp :: _ ->
        invalid "Invalid SDK package entry: %s" (Sexplib.Sexp.to_string_hum sexp)
    in
    loop String_map.empty values
  ;;

  let library_map packages fields =
    let* values = required "libraries" fields in
    let rec loop libraries = function
      | [] -> Ok libraries
      | Sexplib.Sexp.List
          [ Sexplib.Sexp.Atom name
          ; Sexplib.Sexp.Atom package
          ; Sexplib.Sexp.Atom version
          ; Sexplib.Sexp.List raw_components
          ]
        :: rest ->
        if String_map.mem name libraries
        then invalid "Duplicate SDK findlib library: %s" name
        else
          let* components =
            let rec atoms reversed = function
              | [] -> Ok (List.rev reversed)
              | value :: values ->
                let* value = atom value in
                atoms (value :: reversed) values
            in
            atoms [] raw_components
          in
          if components = []
          then invalid "SDK findlib library %s has no components" name
          else if not (List.mem name components)
          then invalid "SDK findlib library %s is absent from its components" name
          else (
            match String_map.find_opt package packages with
            | None ->
              invalid "SDK findlib library %s references unknown package %s" name package
            | Some package_version when package_version <> version ->
              invalid
                "SDK findlib library %s version %s conflicts with package %s.%s"
                name
                version
                package
                package_version
            | Some _ ->
              loop (String_map.add name { package; version; components } libraries) rest)
      | sexp :: _ ->
        invalid "Invalid SDK findlib library entry: %s" (Sexplib.Sexp.to_string_hum sexp)
    in
    loop String_map.empty values
  ;;

  let parse source =
    try
      match Sexplib.Sexp.of_string source with
      | Sexplib.Sexp.List (Sexplib.Sexp.Atom "sdk" :: entries) as raw ->
        let* fields = fields entries in
        let known =
          [ "format_version"
          ; "bonsai_swiftui_version"
          ; "bonsai_swiftui_source"
          ; "abi_version"
          ; "ocaml_version"
          ; "dune_version_range"
          ; "cross_compiler"
          ; "findlib_toolchain"
          ; "architecture"
          ; "platform"
          ; "minimum_deployment_target"
          ; "package_universe_digest"
          ; "target_components_digest"
          ; "required_frameworks"
          ; "required_system_libraries"
          ; "build_recipe_revision"
          ; "packages"
          ; "libraries"
          ]
        in
        let unknown =
          String_map.fold
            (fun name _ unknown ->
               if List.mem name known then unknown else name :: unknown)
            fields
            []
        in
        (match unknown with
         | name :: _ -> invalid "Unknown SDK manifest field: %s" name
         | [] ->
           let* format_version = one "format_version" fields in
           let* bonsai_swiftui_version = one "bonsai_swiftui_version" fields in
           let* abi_version = one "abi_version" fields in
           let* ocaml_version = one "ocaml_version" fields in
           let* dune_minimum_version, dune_maximum_version =
             two "dune_version_range" fields
           in
           let* cross_compiler_package, cross_compiler_version =
             two "cross_compiler" fields
           in
           let* findlib_toolchain = one "findlib_toolchain" fields in
           let* architecture = one "architecture" fields in
           let* platform = one "platform" fields in
           let* minimum_deployment_target = one "minimum_deployment_target" fields in
           let* package_universe_digest = one "package_universe_digest" fields in
           let* target_components_digest = one "target_components_digest" fields in
           let* required_frameworks = atom_list "required_frameworks" fields in
           let* required_system_libraries =
             atom_list "required_system_libraries" fields
           in
           let* build_recipe_revision = one "build_recipe_revision" fields in
           let* packages = package_map fields in
           let* libraries = library_map packages fields in
           Ok
             { raw
             ; format_version
             ; bonsai_swiftui_version
             ; abi_version
             ; ocaml_version
             ; dune_minimum_version
             ; dune_maximum_version
             ; cross_compiler_package
             ; cross_compiler_version
             ; findlib_toolchain
             ; architecture
             ; platform
             ; minimum_deployment_target
             ; package_universe_digest
             ; target_components_digest
             ; required_frameworks
             ; required_system_libraries
             ; build_recipe_revision
             ; packages
             ; libraries
             })
      | sexp ->
        invalid
          "Expected one (sdk ...) manifest, found %s"
          (Sexplib.Sexp.to_string_hum sexp)
    with
    | Sexplib.Sexp.Parse_error _ as error ->
      Error (Printf.sprintf "Invalid SDK manifest: %s" (Printexc.to_string error))
  ;;

  let version_components value =
    let component part =
      try Some (int_of_string part) with
      | Failure _ -> None
    in
    let rec collect reversed = function
      | [] -> Some (List.rev reversed)
      | part :: rest ->
        (match component part with
         | Some value -> collect (value :: reversed) rest
         | None -> None)
    in
    collect [] (String.split_on_char '.' value)
  ;;

  let compare_versions left right =
    match version_components left, version_components right with
    | Some left, Some right -> Ok (Stdlib.compare left right)
    | _ -> invalid "Invalid numeric version comparison: %s and %s" left right
  ;;

  let platform_label = function
    | "iossimulator" -> "iOS Simulator"
    | _ -> "iPhoneOS"
  ;;

  let incompatible ~platform ~toolchain_target bonsai_swiftui_version =
    Error
      (Printf.sprintf
         "The %s switch SDK manifest is incompatible with bonsai-swiftui %s. Run: \
          bonsai-swiftui toolchain remove %s; bonsai-swiftui toolchain install %s"
         (platform_label platform)
         bonsai_swiftui_version
         toolchain_target
         toolchain_target)
  ;;

  let validate
        t
        ~platform
        ~toolchain_target
        ~bonsai_swiftui_version
        ~abi_version
        ~minimum_deployment_target
    =
    if
      t.format_version <> "1"
      || t.bonsai_swiftui_version <> bonsai_swiftui_version
      || t.abi_version <> abi_version
      || t.build_recipe_revision <> supported_build_recipe_revision
    then incompatible ~platform ~toolchain_target bonsai_swiftui_version
    else if t.findlib_toolchain <> "ios"
    then invalid "Invalid SDK findlib toolchain %s; expected ios" t.findlib_toolchain
    else if t.architecture <> "arm64"
    then invalid "Invalid SDK architecture %s; expected arm64" t.architecture
    else if t.platform <> platform
    then
      invalid
        "Invalid SDK manifest: expected Apple platform %s, found %s"
        platform
        t.platform
    else
      let* deployment_comparison =
        compare_versions minimum_deployment_target t.minimum_deployment_target
      in
      if deployment_comparison < 0
      then
        invalid
          "The configured %s minimum deployment target %s is unsupported; the SDK \
           requires %s or newer"
          (platform_label platform)
          minimum_deployment_target
          t.minimum_deployment_target
      else Ok ()
  ;;

  let validate_dune_version t version =
    let* minimum = compare_versions version t.dune_minimum_version in
    let* maximum = compare_versions version t.dune_maximum_version in
    if minimum >= 0 && maximum < 0
    then Ok ()
    else
      invalid
        "The iPhoneOS switch Dune version %s is outside the supported range [%s, %s)"
        version
        t.dune_minimum_version
        t.dune_maximum_version
  ;;

  let validate_packages t required_packages =
    let rec loop = function
      | [] -> Ok ()
      | (name, requested_version) :: rest ->
        (match String_map.find_opt name t.packages with
         | None ->
           invalid
             "Package %s.%s is not in the fixed iPhoneOS SDK package universe. Select a \
              dependency version provided by bonsai-swiftui-ios."
             name
             requested_version
         | Some installed_version when installed_version <> requested_version ->
           invalid
             "Package %s.%s conflicts with iPhoneOS SDK package %s.%s"
             name
             requested_version
             name
             installed_version
         | Some _ -> loop rest)
    in
    loop required_packages
  ;;

  let fingerprint t =
    Sexplib.Sexp.to_string t.raw
    |> Digestif.SHA256.digest_string
    |> Digestif.SHA256.to_hex
  ;;
end

module Application_lock = struct
  module String_map = Map.Make (String)

  type constraint_ =
    | Exact of string
    | Not_exact

  let parse_dependency line =
    let line = String.trim line in
    if line = "" || line.[0] <> '"'
    then Error (Printf.sprintf "Invalid dependency in application opam lock: %s" line)
    else (
      match String.index_from_opt line 1 '"' with
      | None ->
        Error (Printf.sprintf "Invalid dependency in application opam lock: %s" line)
      | Some closing_quote ->
        let name = String.sub line 1 (closing_quote - 1) in
        let suffix =
          String.sub line (closing_quote + 1) (String.length line - closing_quote - 1)
          |> String.trim
        in
        let prefix = "{= \"" in
        if String.starts_with ~prefix suffix && String.ends_with ~suffix:"\"}" suffix
        then (
          let version =
            String.sub
              suffix
              (String.length prefix)
              (String.length suffix - String.length prefix - 2)
          in
          Ok (name, Exact version))
        else Ok (name, Not_exact))
  ;;

  let depends_block source =
    let marker = "depends: [" in
    let marker_length = String.length marker in
    let rec find i =
      if i + marker_length > String.length source
      then None
      else if String.sub source i marker_length = marker
      then Some i
      else find (i + 1)
    in
    match find 0 with
    | None -> Ok None
    | Some start ->
      let region_start = start + marker_length in
      (match
         try Some (String.index_from source region_start ']') with
         | Not_found -> None
       with
       | None ->
         Error "Unterminated depends: [ block in application opam lock"
       | Some stop -> Ok (Some (region_start, stop)))
  ;;

  let scan_dependencies region =
    let length = String.length region in
    let whitespace = function
      | ' ' | '\t' | '\n' | '\r' -> true
      | _ -> false
    in
    let rec skip i = if i < length && whitespace region.[i] then skip (i + 1) else i in
    let invalid i =
      Error
        (Printf.sprintf
           "Invalid dependency in application opam lock: %s"
           (String.sub region i (length - i)))
    in
    let add name constraint_ dependencies =
      if String_map.mem name dependencies
      then
        Error
          (Printf.sprintf "Duplicate dependency %s in application opam lock" name)
      else Ok (String_map.add name constraint_ dependencies)
    in
    let rec entries i dependencies =
      match skip i with
      | i when i >= length -> Ok dependencies
      | i when region.[i] <> '"' -> invalid i
      | i ->
        (match
           try Some (String.index_from region (i + 1) '"') with
           | Not_found -> None
         with
         | None -> invalid i
         | Some name_end ->
           let name = String.sub region (i + 1) (name_end - i - 1) in
           let suffix_start = skip (name_end + 1) in
           (match suffix_start < length && region.[suffix_start] = '{' with
            | false ->
              let* dependencies = add name Not_exact dependencies in
              entries suffix_start dependencies
            | true ->
              (match
                 try Some (String.index_from region suffix_start '}') with
                 | Not_found -> None
               with
               | None -> invalid i
               | Some suffix_end ->
                 let* name, constraint_ =
                   parse_dependency (String.sub region i (suffix_end - i + 1))
                 in
                 let* dependencies = add name constraint_ dependencies in
                 entries (suffix_end + 1) dependencies)))
    in
    entries 0 String_map.empty
  ;;

  let parse source =
    let* block = depends_block source in
    match block with
    | None -> Ok String_map.empty
    | Some (region_start, region_stop) ->
      scan_dependencies
        (String.sub source region_start (region_stop - region_start))
  ;;
end

type preflight =
  { switch_prefix : string
  ; manifest : Manifest.t
  ; fingerprint : string
  }

let read_manifest path =
  try
    let channel = open_in_bin path in
    let source = really_input_string channel (in_channel_length channel) in
    close_in channel;
    Manifest.parse source
  with
  | Sys_error message -> Error message
;;

let validate_application_lock
      ~project_root
      ~application_name
      ~reachable_libraries
      (manifest : Manifest.t)
  =
  let module String_map = Manifest.String_map in
  let* lock_name =
    let manifests =
      Sys.readdir project_root
      |> Array.to_list
      |> List.filter (fun name -> String.ends_with ~suffix:".opam" name)
      |> List.sort String.compare
    in
    let preferred = application_name ^ ".opam" in
    match
      if List.mem preferred manifests
      then Some preferred
      else (
        match manifests with
        | [ only ] -> Some only
        | _ -> None)
    with
    | Some manifest ->
      Ok
        (String.sub manifest 0 (String.length manifest - String.length ".opam")
         ^ ".opam.locked")
    | None -> Ok (application_name ^ ".opam.locked")
  in
  let lock_path = Filename.concat project_root lock_name in
  try
    let channel = open_in_bin lock_path in
    let source = really_input_string channel (in_channel_length channel) in
    close_in channel;
    let* locked = Application_lock.parse source in
    let rec packages selected = function
      | [] -> Ok selected
      | library :: libraries ->
        (match String_map.find_opt library manifest.libraries with
         | None ->
           Error
             (Printf.sprintf
                "Findlib library %s is not provided by the iPhoneOS SDK"
                library)
         | Some mapping ->
           let selected = String_map.add mapping.package mapping.version selected in
           packages selected libraries)
    in
    let* selected = packages String_map.empty reachable_libraries in
    let selected = String_map.bindings selected in
    let rec validate = function
      | [] -> Ok selected
      | (package, sdk_version) :: packages ->
        (match Application_lock.String_map.find_opt package locked with
         | None ->
           Error
             (Printf.sprintf
                "Reachable SDK package %s.%s is missing from %s"
                package
                sdk_version
                lock_name)
         | Some Application_lock.Not_exact ->
           Error
             (Printf.sprintf
                "Dependency %s in %s is not pinned exactly"
                package
                lock_name)
         | Some (Application_lock.Exact locked_version) when locked_version <> sdk_version
           ->
           Error
             (Printf.sprintf
                "Package %s.%s conflicts with reachable SDK package %s.%s"
                package
                locked_version
                package
                sdk_version)
         | Some (Application_lock.Exact _) -> validate packages)
    in
    validate selected
  with
  | Sys_error _ -> Error (Printf.sprintf "Application opam lock is missing: %s" lock_path)
;;

let opam_capture ~project_root arguments =
  Process_runner.capture ~working_directory:project_root ~environment:[] "opam" arguments
;;

let preflight
      ~project_root
      ~simulator
      ~bonsai_swiftui_version
      ~abi_version
      ~minimum_deployment_target
      ~required_packages
  =
  let switch, toolchain_target, platform, sdk_share =
    if simulator
    then
      ( Plan.iossimulator_switch
      , "iossimulator"
      , "iossimulator"
      , "bonsai_swiftui_ios_simulator_sdk" )
    else Plan.iphoneos_switch, "iphoneos", "iphoneos", "bonsai_swiftui_ios_sdk"
  in
  let switch_argument = "--switch=" ^ switch in
  match opam_capture ~project_root [ "switch"; "show"; switch_argument ] with
  | Error _ ->
    Error
      (Printf.sprintf
         "The global %s switch \"%s\" is missing. Run: bonsai-swiftui toolchain install \
          %s"
         (Manifest.platform_label platform)
         switch
         toolchain_target)
  | Ok selected when selected <> switch ->
    Error (Printf.sprintf "opam resolved iOS switch %s instead of %s" selected switch)
  | Ok _ ->
    let* switch_prefix =
      opam_capture ~project_root [ "var"; switch_argument; "prefix" ]
    in
    let required_executables = [ "dune"; "ocamlc"; "ocamlfind" ] in
    let missing_executable =
      List.find_opt
        (fun executable ->
           not (Sys.file_exists (Filename.concat switch_prefix ("bin/" ^ executable))))
        required_executables
    in
    (match missing_executable with
     | Some executable ->
       Error
         (Printf.sprintf
            "The %s switch %s is incomplete: missing %s. Run: bonsai-swiftui toolchain \
             remove %s; bonsai-swiftui toolchain install %s"
            (Manifest.platform_label platform)
            switch
            executable
            toolchain_target
            toolchain_target)
     | None ->
       let manifest_path =
         Filename.concat switch_prefix ("share/" ^ sdk_share ^ "/manifest.sexp")
       in
       let* manifest = read_manifest manifest_path in
       let* () =
         Manifest.validate
           manifest
           ~platform
           ~toolchain_target
           ~bonsai_swiftui_version
           ~abi_version
           ~minimum_deployment_target
       in
       let* () = Manifest.validate_packages manifest required_packages in
       let* dune_version =
         opam_capture ~project_root [ "exec"; switch_argument; "--"; "dune"; "--version" ]
       in
       let* () = Manifest.validate_dune_version manifest dune_version in
       let* ocaml_version =
         opam_capture
           ~project_root
           [ "exec"; switch_argument; "--"; "ocamlc"; "-version" ]
       in
       if ocaml_version <> manifest.ocaml_version
       then
         Error
           (Printf.sprintf
              "The %s switch OCaml version %s does not match SDK manifest %s"
              (Manifest.platform_label platform)
              ocaml_version
              manifest.ocaml_version)
       else
         let* findlib_path =
           opam_capture
             ~project_root
             [ "exec"
             ; switch_argument
             ; "--"
             ; "ocamlfind"
             ; "-toolchain"
             ; "ios"
             ; "printconf"
             ; "path"
             ]
         in
         if findlib_path = ""
         then
           Error
             (Printf.sprintf
                "The %s switch does not expose the ios findlib toolchain"
                (Manifest.platform_label platform))
         else Ok { switch_prefix; manifest; fingerprint = Manifest.fingerprint manifest })
;;
