let ( let* ) result f =
  match result with
  | Ok value -> f value
  | Error _ as error -> error
;;

type info =
  { switch : string
  ; prefix : string
  ; manifest_path : string
  ; fingerprint : string
  ; bonsai_swiftui_version : string
  ; ocaml_version : string
  ; target : string
  }

module Repository = struct
  type t =
    { root : string
    ; version : string
    ; snapshot_sha256 : string
    ; source_lock_path : string
    ; source_lock_sha256 : string
    ; package_universe_path : string
    ; package_universe_sha256 : string
    ; source_archives_path : string
    ; source_archives_sha256 : string
    ; default_url : string
    ; default_commit : string
    ; cross_url : string
    ; cross_commit : string
    ; compiler_package : string
    ; compiler_version : string
    ; sdk_package : string
    ; sdk_version : string
    }

  let version = "0.1.0"

  let read_file path =
    let channel = open_in_bin path in
    Fun.protect
      ~finally:(fun () -> close_in_noerr channel)
      (fun () -> really_input_string channel (in_channel_length channel))
  ;;

  let rec files root relative =
    let path = Filename.concat root relative in
    match (Unix.lstat path).st_kind with
    | Unix.S_DIR ->
      Sys.readdir path
      |> Array.to_list
      |> List.sort String.compare
      |> List.concat_map (fun name ->
        files root (if relative = "" then name else Filename.concat relative name))
    | Unix.S_REG -> if relative = "repository.sexp" then [] else [ relative ]
    | Unix.S_LNK ->
      raise (Sys_error (Printf.sprintf "iOS opam repository contains a symlink: %s" path))
    | Unix.S_CHR | Unix.S_BLK | Unix.S_FIFO | Unix.S_SOCK ->
      raise
        (Sys_error (Printf.sprintf "iOS opam repository contains a special file: %s" path))
  ;;

  let digest root =
    files root ""
    |> List.map (fun relative ->
      relative ^ "\000" ^ Artifact.digest (Filename.concat root relative))
    |> String.concat "\000"
    |> Digestif.SHA256.digest_string
    |> Digestif.SHA256.to_hex
  ;;

  let atom = function
    | Sexplib.Sexp.Atom value -> Ok value
    | sexp ->
      Error
        (Printf.sprintf
           "Invalid iOS repository lock atom: %s"
           (Sexplib.Sexp.to_string_hum sexp))
  ;;

  let parse root source =
    let invalid detail = Error ("Invalid iOS repository lock: " ^ detail) in
    try
      match Sexplib.Sexp.of_string source with
      | Sexplib.Sexp.List (Sexplib.Sexp.Atom "repository" :: entries) ->
        let find name =
          entries
          |> List.filter_map (function
            | Sexplib.Sexp.List (Sexplib.Sexp.Atom actual :: values) when actual = name ->
              Some values
            | _ -> None)
          |> function
          | [ values ] -> Ok values
          | [] -> invalid ("missing field " ^ name)
          | _ -> invalid ("duplicate field " ^ name)
        in
        let one name =
          let* values = find name in
          match values with
          | [ value ] -> atom value
          | _ -> invalid (name ^ " must contain one value")
        in
        let two name =
          let* values = find name in
          match values with
          | [ left; right ] ->
            let* left = atom left in
            let* right = atom right in
            Ok (left, right)
          | _ -> invalid (name ^ " must contain two values")
        in
        let* format_version = one "format_version" in
        let* repository_version = one "repository_version" in
        let* snapshot_sha256 = one "repository_snapshot_sha256" in
        let* source_lock_path, source_lock_sha256 = two "source_lock" in
        let* package_universe_path, package_universe_sha256 = two "package_universe" in
        let* source_archives_path, source_archives_sha256 = two "source_archives" in
        let* default_url, default_commit = two "default_repository" in
        let* cross_url, cross_commit = two "cross_repository" in
        let* compiler_package, compiler_version = two "compiler" in
        let* sdk_package, sdk_version = two "sdk_package" in
        if format_version <> "1"
        then invalid ("unsupported format version " ^ format_version)
        else if repository_version <> version
        then invalid ("unsupported repository version " ^ repository_version)
        else
          Ok
            { root
            ; version = repository_version
            ; snapshot_sha256
            ; source_lock_path
            ; source_lock_sha256
            ; package_universe_path
            ; package_universe_sha256
            ; source_archives_path
            ; source_archives_sha256
            ; default_url
            ; default_commit
            ; cross_url
            ; cross_commit
            ; compiler_package
            ; compiler_version
            ; sdk_package
            ; sdk_version
            }
      | _ -> invalid "expected one repository form"
    with
    | Sexplib.Sexp.Parse_error _ -> invalid "invalid S-expression"
  ;;

  let load ~framework_root =
    let root = Filename.concat framework_root ("tool/ios/opam-repository/" ^ version) in
    try
      let lock = Filename.concat root "repository.sexp" in
      let* repository = parse root (read_file lock) in
      let repository_file_digest ~label path expected =
        if
          Filename.is_relative path
          && not
               (path
                |> String.split_on_char '/'
                |> List.exists (fun component -> component = ".."))
        then (
          let actual = Artifact.digest (Filename.concat root path) in
          if actual = expected
          then Ok ()
          else
            Error
              (Printf.sprintf
                 "The iOS SDK %s digest is invalid: expected %s, found %s"
                 label
                 expected
                 actual))
        else
          Error (Printf.sprintf "The iOS SDK %s path must be repository-relative" label)
      in
      let* () =
        repository_file_digest
          ~label:"package universe"
          repository.package_universe_path
          repository.package_universe_sha256
      in
      let* () =
        repository_file_digest
          ~label:"source archive"
          repository.source_archives_path
          repository.source_archives_sha256
      in
      let actual = digest root in
      if actual <> repository.snapshot_sha256
      then
        Error
          (Printf.sprintf
             "The iOS opam repository snapshot digest is invalid: expected %s, found %s"
             repository.snapshot_sha256
             actual)
      else if
        Filename.is_relative repository.source_lock_path
        && not
             (repository.source_lock_path
              |> String.split_on_char '/'
              |> List.exists (fun component -> component = ".."))
      then (
        let source_lock = Filename.concat framework_root repository.source_lock_path in
        let actual_source_digest = Artifact.digest source_lock in
        if actual_source_digest <> repository.source_lock_sha256
        then
          Error
            (Printf.sprintf
               "The iOS SDK source lock digest is invalid: expected %s, found %s"
               repository.source_lock_sha256
               actual_source_digest)
        else Ok repository)
      else Error "The iOS SDK source lock path must be framework-relative"
    with
    | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
  ;;
end

let capture ~working_directory arguments =
  Process_runner.capture ~working_directory ~environment:[] "opam" arguments
;;

let show ~working_directory =
  let switch_argument = "--switch=" ^ Plan.iphoneos_switch in
  match capture ~working_directory [ "switch"; "show"; switch_argument ] with
  | Error _ ->
    Error
      (Printf.sprintf
         "The global iPhoneOS switch \"%s\" is missing. Run: bonsai-swiftui toolchain \
          install iphoneos"
         Plan.iphoneos_switch)
  | Ok selected when selected <> Plan.iphoneos_switch ->
    Error
      (Printf.sprintf
         "opam resolved iPhoneOS switch %s instead of %s"
         selected
         Plan.iphoneos_switch)
  | Ok _ ->
    let* prefix = capture ~working_directory [ "var"; switch_argument; "prefix" ] in
    let manifest_path =
      Filename.concat prefix "share/bonsai_swiftui_ios_sdk/manifest.sexp"
    in
    let* manifest = Sdk.read_manifest manifest_path in
    Ok
      { switch = Plan.iphoneos_switch
      ; prefix
      ; manifest_path
      ; fingerprint = Sdk.Manifest.fingerprint manifest
      ; bonsai_swiftui_version = manifest.bonsai_swiftui_version
      ; ocaml_version = manifest.ocaml_version
      ; target = manifest.platform ^ "/" ^ manifest.architecture
      }
;;

let verify ~working_directory =
  Sdk.preflight
    ~project_root:working_directory
    ~bonsai_swiftui_version:Sdk.supported_bonsai_swiftui_version
    ~abi_version:Sdk.supported_abi_version
    ~minimum_deployment_target:Sdk.supported_minimum_deployment_target
    ~required_packages:[ "bonsai_swiftui", Sdk.supported_bonsai_swiftui_version ]
;;

let remove ~working_directory =
  let command : Plan.command =
    { program = "opam"
    ; arguments = [ "switch"; "remove"; "--yes"; Plan.iphoneos_switch ]
    ; working_directory
    ; environment = []
    }
  in
  Process_runner.run command
;;

let install ~framework_root ~working_directory =
  let* repository = Repository.load ~framework_root in
  let* switches = capture ~working_directory [ "switch"; "list"; "--short" ] in
  let switch_exists =
    switches
    |> String.split_on_char '\n'
    |> List.exists (String.equal Plan.iphoneos_switch)
  in
  if switch_exists
  then
    Error
      (Printf.sprintf
         "The global iPhoneOS switch \"%s\" already exists. Run: bonsai-swiftui \
          toolchain verify iphoneos"
         Plan.iphoneos_switch)
  else (
    let local_repository_name =
      "bonsai-swiftui-ios-" ^ String.sub repository.snapshot_sha256 0 12
    in
    let repositories =
      String.concat
        ","
        [ local_repository_name ^ "=file://" ^ repository.root
        ; "bonsai-swiftui-ios-cross=git+"
          ^ repository.cross_url
          ^ "#"
          ^ repository.cross_commit
        ; "bonsai-swiftui-default=git+"
          ^ repository.default_url
          ^ "#"
          ^ repository.default_commit
        ]
    in
    let create : Plan.command =
      { program = "opam"
      ; arguments =
          [ "switch"
          ; "create"
          ; Plan.iphoneos_switch
          ; repository.compiler_package ^ "." ^ repository.compiler_version
          ; "--no-switch"
          ; "--yes"
          ; "--repositories=" ^ repositories
          ]
      ; working_directory
      ; environment = []
      }
    in
    let* () = Process_runner.run create in
    let install : Plan.command =
      { program = "opam"
      ; arguments =
          [ "install"
          ; "--switch=" ^ Plan.iphoneos_switch
          ; "--yes"
          ; repository.sdk_package ^ "." ^ repository.sdk_version
          ; "--assume-depexts"
          ]
      ; working_directory
      ; environment = []
      }
    in
    Process_runner.run install)
;;
