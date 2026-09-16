let ( let* ) result f =
  match result with
  | Ok value -> f value
  | Error _ as error -> error
;;

let capture ~project_root program arguments =
  Process_runner.capture ~working_directory:project_root ~environment:[] program arguments
;;

let apple_sdk ~project_root target =
  let sdk =
    match target with
    | Plan.Macos -> "macosx"
    | Plan.Iphoneos -> "iphoneos"
  in
  let* root = capture ~project_root "xcrun" [ "--sdk"; sdk; "--show-sdk-path" ] in
  match target with
  | Plan.Macos -> Ok (root, None)
  | Plan.Iphoneos ->
    let* version = capture ~project_root "xcrun" [ "--sdk"; sdk; "--show-sdk-version" ] in
    Ok (root, Some version)
;;

let host_fingerprint ~project_root ~(config : Config.t) =
  let* dune_version =
    capture ~project_root "opam" [ "exec"; "--"; "dune"; "--version" ]
  in
  let* ocaml_version =
    capture ~project_root "opam" [ "exec"; "--"; "ocamlc"; "-version" ]
  in
  let* package_version =
    capture
      ~project_root
      "opam"
      [ "exec"; "--"; "ocamlfind"; "query"; "-format"; "%v"; "bonsai_swiftui" ]
  in
  let identity =
    String.concat
      "\000"
      [ "bonsai-swiftui-host-v1"
      ; dune_version
      ; ocaml_version
      ; package_version
      ; Sdk.supported_abi_version
      ; config.macos.minimum_version
      ; String.concat "," config.macos.architectures
      ]
  in
  Ok Digestif.SHA256.(to_hex (digest_string identity))
;;

let iphoneos_fingerprint ~(config : Config.t) sdk_fingerprint =
  String.concat
    "\000"
    [ "bonsai-swiftui-iphoneos-v1"
    ; sdk_fingerprint
    ; Sdk.supported_abi_version
    ; config.ios.minimum_version
    ; String.concat "," config.ios.architectures
    ]
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex
;;

let build_manifest ~(build : Plan.native_build) ~target ~profile ~fingerprint artifact =
  Printf.sprintf
    "(build\n\
    \ (format_version 1)\n\
    \ (target %s)\n\
    \ (profile %s)\n\
    \ (toolchain_fingerprint %s)\n\
    \ (source_digest %s)\n\
    \ (artifact_digest %s))\n"
    (Plan.target_name target)
    (Plan.profile_name profile)
    fingerprint
    (Artifact.digest build.source_object)
    (Artifact.digest artifact)
;;

let execute_native
      ~framework_root
      ~project_root
      ~config
      ~target
      ~profile
      ~toolchain_fingerprint
      ~apple_sdk_root
      ~apple_sdk_version
  =
  let* build =
    Plan.native_build
      ~project_root
      ~config
      ~target
      ~profile
      ~toolchain_fingerprint
      ~apple_sdk_root
      ~apple_sdk_version
  in
  Scaffold.ensure_directory (Filename.dirname build.build_directory);
  let* () = Process_runner.run build.command in
  Lock.with_lock build.lock (fun () ->
    let* artifact = Artifact.stage ~framework_root ~build ~config ~target in
    let manifest =
      build_manifest ~build ~target ~profile ~fingerprint:toolchain_fingerprint artifact
    in
    let* () = Artifact.write_if_changed build.manifest manifest in
    Ok artifact)
;;

let build_native ~framework_root ~project_root ~config ~target ~profile =
  let* apple_sdk_root, apple_sdk_version = apple_sdk ~project_root target in
  match target with
  | Plan.Macos ->
    let* toolchain_fingerprint = host_fingerprint ~project_root ~config in
    execute_native
      ~framework_root
      ~project_root
      ~config
      ~target
      ~profile
      ~toolchain_fingerprint
      ~apple_sdk_root
      ~apple_sdk_version
  | Plan.Iphoneos ->
    let* sdk =
      Sdk.preflight
        ~project_root
        ~bonsai_swiftui_version:Sdk.supported_bonsai_swiftui_version
        ~abi_version:Sdk.supported_abi_version
        ~minimum_deployment_target:config.Config.ios.minimum_version
        ~required_packages:[ "bonsai_swiftui", Sdk.supported_bonsai_swiftui_version ]
    in
    let closure_build_directory =
      Filename.concat
        project_root
        ("_build/bonsai-swiftui/dune/iphoneos/" ^ sdk.fingerprint ^ "/closure")
    in
    let* reachable_libraries =
      Dune_closure.resolve_project
        ~project_root
        ~target:config.native_target
        ~build_directory:closure_build_directory
    in
    let* _reachable_packages =
      Sdk.validate_application_lock
        ~project_root
        ~application_name:config.name
        ~reachable_libraries
        sdk.manifest
    in
    let toolchain_fingerprint = iphoneos_fingerprint ~config sdk.fingerprint in
    execute_native
      ~framework_root
      ~project_root
      ~config
      ~target
      ~profile
      ~toolchain_fingerprint
      ~apple_sdk_root
      ~apple_sdk_version
;;

let forward_signal process signal =
  try Unix.kill process signal with
  | Unix.Unix_error ((Unix.ESRCH | Unix.EPERM), _, _) -> ()
;;

let with_forwarded_interrupts f =
  let child = ref None in
  let received_signal = ref None in
  let handle_signal signal =
    if Option.is_none !received_signal then received_signal := Some signal;
    Option.iter (fun process -> forward_signal process signal) !child
  in
  let signals = [ Sys.sigint; Sys.sigterm; Sys.sighup; Sys.sigquit ] in
  let previous_handlers =
    List.map
      (fun signal -> signal, Sys.signal signal (Sys.Signal_handle handle_signal))
      signals
  in
  Fun.protect
    ~finally:(fun () ->
      List.iter
        (fun (signal, handler) -> ignore (Sys.signal signal handler))
        previous_handlers)
    (fun () ->
       let on_spawn process =
         child := Some process;
         Option.iter (forward_signal process) !received_signal
       in
       f ~on_spawn ~received_signal:(fun () -> !received_signal))
;;

let selected_native ~framework_root ~project_root ~config ~target ~profile ~native_object =
  match native_object with
  | None -> build_native ~framework_root ~project_root ~config ~target ~profile
  | Some path ->
    let path =
      if Filename.is_relative path then Filename.concat project_root path else path
    in
    let* () = Artifact.verify ~framework_root ~project_root ~config ~target path in
    let* apple_sdk_root, apple_sdk_version = apple_sdk ~project_root target in
    let* build =
      Plan.native_build
        ~project_root
        ~config
        ~target
        ~profile
        ~toolchain_fingerprint:(Artifact.digest path)
        ~apple_sdk_root
        ~apple_sdk_version
    in
    Artifact.stage
      ~framework_root
      ~build:{ build with source_object = path }
      ~config
      ~target
;;

let stage_host_object ~project_root ~config ~target ~profile artifact =
  let sdk =
    match target with
    | Plan.Macos -> "macosx"
    | Plan.Iphoneos -> "iphoneos"
  in
  let path =
    Filename.concat
      (Plan.apple_host ~project_root config)
      (Printf.sprintf
         "Native/%s/%s/runtime.complete.o"
         sdk
         (Plan.ios_configuration_name profile))
  in
  try
    Scaffold.ensure_directory (Filename.dirname path);
    if not (Artifact.files_equal artifact path) then Artifact.copy_file artifact path;
    Ok ()
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;

let verify_app ~framework_root ~project_root ~config ~platform ~profile ~no_codesign =
  let bundle = Plan.app_bundle ~project_root ~config ~platform ~profile in
  let executable, target =
    match platform with
    | Plan.Macos_platform ->
      Filename.concat bundle ("Contents/MacOS/" ^ Plan.product_name config), Plan.Macos
    | Plan.Ios_platform ->
      Filename.concat bundle (Plan.product_name config), Plan.Iphoneos
  in
  let platform_name, minimum, plist =
    match target with
    | Plan.Macos ->
      ( "MACOS"
      , config.Config.macos.minimum_version
      , Filename.concat bundle "Contents/Info.plist" )
    | Plan.Iphoneos ->
      "IOS", config.Config.ios.minimum_version, Filename.concat bundle "Info.plist"
  in
  let* () =
    Process_runner.run
      { program = Filename.concat framework_root "tool/ios/verify_macho.sh"
      ; arguments = [ executable; platform_name; "arm64"; minimum ]
      ; working_directory = project_root
      ; environment = []
      }
  in
  let* identifier =
    capture
      ~project_root
      "plutil"
      [ "-extract"; "CFBundleIdentifier"; "raw"; "-o"; "-"; plist ]
  in
  let minimum_key =
    match target with
    | Plan.Macos -> "LSMinimumSystemVersion"
    | Plan.Iphoneos -> "MinimumOSVersion"
  in
  let* actual_minimum =
    capture ~project_root "plutil" [ "-extract"; minimum_key; "raw"; "-o"; "-"; plist ]
  in
  let* () =
    if
      (identifier
       =
       match target with
       | Plan.Macos -> config.macos.bundle_identifier
       | Plan.Iphoneos -> config.ios.bundle_identifier)
      && actual_minimum = minimum
    then Ok ()
    else Error "Built application metadata does not match its configuration"
  in
  if no_codesign
  then Ok bundle
  else
    let* () =
      Process_runner.run
        { program = "codesign"
        ; arguments = [ "--verify"; "--deep"; "--strict"; bundle ]
        ; working_directory = project_root
        ; environment = []
        }
    in
    Ok bundle
;;

let build_apple
      ~framework_root
      ~project_root
      ~config
      ~platform
      ~profile
      ~no_codesign
      ~development_team
      ~signing_identity
      ~native_object
  =
  let target =
    match platform with
    | Plan.Macos_platform -> Plan.Macos
    | Plan.Ios_platform -> Plan.Iphoneos
  in
  let* () = Host.sync ~framework_root ~project_root ~config ~mode:Host.Locked in
  Lock.with_lock
    (Filename.concat project_root "_build/bonsai-swiftui/locks/apple.lock")
    (fun () ->
       let* artifact =
         selected_native
           ~framework_root
           ~project_root
           ~config
           ~target
           ~profile
           ~native_object
       in
       let* () = Host.sync ~framework_root ~project_root ~config ~mode:Host.Write in
       let* () = stage_host_object ~project_root ~config ~target ~profile artifact in
       let* () =
         Process_runner.run
           (Plan.apple_build
              ~project_root
              ~config
              ~platform
              ~profile
              ~no_codesign
              ~development_team
              ~signing_identity)
       in
       verify_app ~framework_root ~project_root ~config ~platform ~profile ~no_codesign)
;;

let run_apple
      ~framework_root
      ~project_root
      ~config
      ~platform
      ~profile
      ~device
      ~development_team
      ~signing_identity
      ~native_object
      ~arguments
  =
  if platform = Plan.Ios_platform && Option.is_none device
  then Error "Running on iOS requires --device <physical-device-id>"
  else
    let* bundle =
      build_apple
        ~framework_root
        ~project_root
        ~config
        ~platform
        ~profile
        ~no_codesign:false
        ~development_team
        ~signing_identity
        ~native_object
    in
    match platform with
    | Plan.Ios_platform ->
      let device = Option.get device in
      let* () =
        Plan.ios_device_install ~project_root ~device ~app_bundle:bundle
        |> Process_runner.run
      in
      let command =
        Plan.ios_device_launch
          ~project_root
          ~device
          ~bundle_identifier:config.Config.ios.bundle_identifier
      in
      Process_runner.run { command with arguments = command.arguments @ arguments }
    | Plan.Macos_platform ->
      let command : Plan.command =
        { program = Filename.concat bundle ("Contents/MacOS/" ^ Plan.product_name config)
        ; arguments
        ; working_directory = project_root
        ; environment = []
        }
      in
      with_forwarded_interrupts (fun ~on_spawn ~received_signal ->
        match Process_runner.run_status ~on_spawn command, received_signal () with
        | Ok 0, None -> Ok ()
        | Ok status, None ->
          Error (Printf.sprintf "Application exited with status %d" status)
        | Ok _, Some signal ->
          Error (Printf.sprintf "Application interrupted (%d)" signal)
        | (Error _ as error), _ -> error)
;;

let exec
      ~framework_root
      ~project_root
      ~config
      ~profile
      ~native_object
      ~working_directory
      ~command
  =
  match command with
  | [] -> Error "A command is required after --"
  | program :: arguments ->
    let* () = Host.sync ~framework_root ~project_root ~config ~mode:Host.Validate in
    Lock.with_lock
      (Filename.concat project_root "_build/bonsai-swiftui/locks/apple.lock")
      (fun () ->
         let* artifact =
           selected_native
             ~framework_root
             ~project_root
             ~config
             ~target:Plan.Macos
             ~profile
             ~native_object
         in
         let* () = Host.sync ~framework_root ~project_root ~config ~mode:Host.Write in
         let* () =
           stage_host_object ~project_root ~config ~target:Plan.Macos ~profile artifact
         in
         with_forwarded_interrupts (fun ~on_spawn ~received_signal ->
           let command : Plan.command =
             { program
             ; arguments
             ; working_directory
             ; environment =
                 [ "BONSAI_SWIFTUI_NATIVE_OBJECT", artifact
                 ; "BONSAI_SWIFTUI_CONFIGURATION", Plan.ios_configuration_name profile
                 ]
             }
           in
           let result =
             match received_signal () with
             | Some signal -> Ok (Process_runner.signal_exit_code signal)
             | None -> Process_runner.run_status ~on_spawn command
           in
           match result, received_signal () with
           | Ok _, Some signal -> Ok (Process_runner.signal_exit_code signal)
           | result, None -> result
           | (Error _ as error), Some _ -> error))
;;
