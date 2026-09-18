open Bonsai_swiftui_tool
open Cmdliner

let ( let* ) result f =
  match result with
  | Ok value -> f value
  | Error _ as error -> error
;;

let parse_features value =
  let names =
    String.split_on_char ',' value |> List.map String.trim |> List.filter (( <> ) "")
  in
  let rec parse acc = function
    | [] -> Ok (List.rev acc)
    | name :: rest ->
      let* feature = Config.Feature.of_string name in
      if feature = Config.Feature.Core
      then parse acc rest
      else parse (feature :: acc) rest
  in
  parse [ Config.Feature.Core ] names
;;

let init
      name
      macos_bundle_identifier
      ios_bundle_identifier
      features
      macos_minimum
      ios_minimum
      adopt
  =
  let project_root = Sys.getcwd () in
  let path = Filename.concat project_root "bonsai-swiftui.sexp" in
  if
    adopt
    && (Option.is_some name
        || Option.is_some macos_bundle_identifier
        || Option.is_some ios_bundle_identifier
        || features <> "")
  then
    Error "--adopt uses the existing configuration; do not supply new application options"
  else if (not adopt) && Sys.file_exists path
  then Error "bonsai-swiftui.sexp already exists; use init --adopt"
  else
    let* text =
      if adopt
      then (
        match Scaffold.read_file path with
        | Some value -> Ok value
        | None -> Error "--adopt requires bonsai-swiftui.sexp")
      else
        let* name =
          match name with
          | Some name -> Ok name
          | None -> Error "--name is required"
        in
        let default_identifier =
          "org.bonsai-swiftui."
          ^ String.map
              (function
                | '_' -> '-'
                | c -> c)
              name
        in
        let macos_bundle_identifier =
          Option.value macos_bundle_identifier ~default:default_identifier
        in
        let ios_bundle_identifier =
          Option.value ios_bundle_identifier ~default:default_identifier
        in
        let* features = parse_features features in
        Ok
          (Scaffold.configuration_text
             ~name
             ~macos_bundle_identifier
             ~ios_bundle_identifier
             ~features
             ~macos_minimum_version:macos_minimum
             ~ios_minimum_version:ios_minimum)
    in
    let* config = Config.parse_string text in
    let* framework_root = Assets.find_framework_root () in
    let* () =
      Host.sync
        ~framework_root
        ~project_root
        ~config
        ~mode:(if adopt then Host.Validate else Host.Inputs)
    in
    let* () =
      if adopt
      then Scaffold.adopt_workspace ~project_root ~config_text:text ~config
      else Scaffold.initialize_workspace ~project_root ~config_text:text ~config
    in
    Host.sync ~framework_root ~project_root ~config ~mode:Host.Write
;;

let load_project () =
  let* project_root = Project.find_root (Sys.getcwd ()) in
  let* config = Config.parse_file (Filename.concat project_root "bonsai-swiftui.sexp") in
  Ok (project_root, config)
;;

let doctor target =
  let* diagnostics = Doctor.run ~project_root:(Sys.getcwd ()) ~target in
  List.iter
    (fun (program, output) ->
       let first =
         match String.split_on_char '\n' output with
         | first :: _ -> first
         | [] -> output
       in
       Printf.printf "ok %-12s %s\n%!" program first)
    diagnostics;
  Ok ()
;;

let build_native target profile =
  let* project_root, config = load_project () in
  let* framework_root = Assets.find_framework_root () in
  let* () = Host.sync ~framework_root ~project_root ~config ~mode:Host.Inputs in
  let* artifact =
    Build_system.build_native ~framework_root ~project_root ~config ~target ~profile
  in
  Printf.printf "native artifact: %s\n%!" artifact;
  Ok ()
;;

let absolute_object =
  Option.map (fun path ->
    if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path)
;;

let build platform profile no_codesign development_team signing_identity native_object =
  let native_object = absolute_object native_object in
  let* project_root, config = load_project () in
  let* framework_root = Assets.find_framework_root () in
  let* bundle =
    Build_system.build_apple
      ~framework_root
      ~project_root
      ~config
      ~platform
      ~profile
      ~no_codesign
      ~development_team
      ~signing_identity
      ~native_object
  in
  Printf.printf "application: %s\n%!" bundle;
  Ok ()
;;

let run platform profile device development_team signing_identity native_object arguments =
  if platform = Plan.Ios_platform && Option.is_none device
  then Error "Running on iOS requires --device <physical-device-id>"
  else (
    let native_object = absolute_object native_object in
    let* project_root, config = load_project () in
    let* framework_root = Assets.find_framework_root () in
    Build_system.run_apple
      ~framework_root
      ~project_root
      ~config
      ~platform
      ~profile
      ~device
      ~development_team
      ~signing_identity
      ~native_object
      ~arguments)
;;

let exec profile native_object command =
  let working_directory = Sys.getcwd () in
  let native_object = absolute_object native_object in
  let* project_root, config = load_project () in
  let* framework_root = Assets.find_framework_root () in
  match
    Build_system.exec
      ~framework_root
      ~project_root
      ~config
      ~profile
      ~native_object
      ~working_directory
      ~command
  with
  | Error _ as error -> error
  | Ok 0 -> Ok ()
  | Ok status -> exit status
;;

let sync_host check =
  let* project_root, config = load_project () in
  let* framework_root = Assets.find_framework_root () in
  Host.sync
    ~framework_root
    ~project_root
    ~config
    ~mode:(if check then Host.Check else Host.Write)
;;

let resolve_packages () =
  let* project_root, config = load_project () in
  let* framework_root = Assets.find_framework_root () in
  Host.sync ~framework_root ~project_root ~config ~mode:Host.Resolve
;;

let clean platform all_project_builds =
  let* project_root, config = load_project () in
  match platform, all_project_builds with
  | Some _, true -> Error "Select a platform or --all-project-builds, not both"
  | None, false -> Error "Select macos, iphoneos, or --all-project-builds"
  | Some target, false -> Clean.run ~project_root ~config target
  | None, true -> Clean.run ~project_root ~config Clean.All
;;

let toolchain_show () =
  let* info = Toolchain.show ~working_directory:(Sys.getcwd ()) in
  Printf.printf
    "switch: %s\n\
     prefix: %s\n\
     manifest: %s\n\
     fingerprint: %s\n\
     bonsai_swiftui: %s\n\
     ocaml: %s\n\
     target: %s\n\
     %!"
    info.switch
    info.prefix
    info.manifest_path
    info.fingerprint
    info.bonsai_swiftui_version
    info.ocaml_version
    info.target;
  Ok ()
;;

let toolchain_verify () =
  let* verified = Toolchain.verify ~working_directory:(Sys.getcwd ()) in
  Printf.printf "verified iPhoneOS toolchain: %s\n%!" verified.fingerprint;
  Ok ()
;;

let toolchain_remove () = Toolchain.remove ~working_directory:(Sys.getcwd ())

let toolchain_install () =
  let* framework_root = Assets.find_framework_root () in
  Toolchain.install ~framework_root ~working_directory:(Sys.getcwd ())
;;

let resolve_dune_closure project_root target =
  let target_key = Digest.string target |> Digest.to_hex in
  let build_directory =
    Filename.concat
      project_root
      ("_build/bonsai-swiftui/dune/internal-closure/" ^ target_key)
  in
  let* dependencies =
    Dune_closure.resolve_project ~project_root ~target ~build_directory
  in
  List.iter print_endline dependencies;
  Ok ()
;;

let target =
  Arg.(
    required
    & opt (some (enum [ "macos", Plan.Macos; "iphoneos", Plan.Iphoneos ])) None
    & info [ "target" ] ~docv:"TARGET")
;;

let profile =
  Arg.(
    value
    & opt
        (enum [ "debug", Plan.Debug; "profile", Plan.Profile; "release", Plan.Release ])
        Plan.Debug
    & info [ "profile" ] ~docv:"PROFILE")
;;

let platform =
  Arg.(
    required
    & pos 0 (some (enum [ "macos", Plan.Macos_platform; "ios", Plan.Ios_platform ])) None
    & info [] ~docv:"PLATFORM")
;;

let native_object =
  Arg.(
    value
    & opt (some string) None
    & info
        [ "native-object" ]
        ~docv:"PATH"
        ~doc:"Use an explicitly selected, verified OCaml complete object.")
;;

let development_team =
  Arg.(
    value
    & opt (some string) None
    & info
        [ "development-team" ]
        ~docv:"TEAM"
        ~doc:"Apple development team for application signing.")
;;

let signing_identity =
  Arg.(
    value
    & opt (some string) None
    & info
        [ "signing-identity" ]
        ~docv:"IDENTITY"
        ~doc:
          "Explicit code signing certificate identity supplied by the application owner.")
;;

let init_command =
  let name = Arg.(value & opt (some string) None & info [ "name" ] ~docv:"NAME") in
  let macos_bundle =
    Arg.(value & opt (some string) None & info [ "macos-bundle-identifier" ] ~docv:"ID")
  in
  let ios_bundle =
    Arg.(value & opt (some string) None & info [ "ios-bundle-identifier" ] ~docv:"ID")
  in
  let features = Arg.(value & opt string "" & info [ "features" ] ~docv:"FEATURES") in
  let macos =
    Arg.(value & opt string "26.0" & info [ "macos-minimum-version" ] ~docv:"VERSION")
  in
  let ios =
    Arg.(value & opt string "26.0" & info [ "ios-deployment-target" ] ~docv:"VERSION")
  in
  let adopt =
    Arg.(
      value
      & flag
      & info
          [ "adopt" ]
          ~doc:"Adopt existing application-owned sources and configuration.")
  in
  Cmd.v
    (Cmd.info "init" ~doc:"Initialize an OCaml and SwiftUI application.")
    Term.(const init $ name $ macos_bundle $ ios_bundle $ features $ macos $ ios $ adopt)
;;

let doctor_command =
  let target =
    Arg.(
      value
      & opt (some (enum [ "macos", Plan.Macos; "iphoneos", Plan.Iphoneos ])) None
      & info [ "target" ] ~docv:"TARGET")
  in
  Cmd.v
    (Cmd.info "doctor" ~doc:"Check native Apple development tools.")
    Term.(const doctor $ target)
;;

let build_native_command =
  Cmd.v
    (Cmd.info "build-native" ~doc:"Build and verify the OCaml complete object.")
    Term.(const build_native $ target $ profile)
;;

let build_command =
  let no_codesign =
    Arg.(
      value
      & flag
      & info
          [ "no-codesign" ]
          ~doc:"Build without signing; installation remains unavailable.")
  in
  Cmd.v
    (Cmd.info "build" ~doc:"Build the complete SwiftUI application with Xcode.")
    Term.(
      const build
      $ platform
      $ profile
      $ no_codesign
      $ development_team
      $ signing_identity
      $ native_object)
;;

let run_command =
  let device =
    Arg.(value & opt (some string) None & info [ "device" ] ~docv:"DEVICE_ID")
  in
  let arguments =
    Arg.(value & pos_right 0 string [] & info [] ~docv:"APPLICATION_ARGUMENT")
  in
  Cmd.v
    (Cmd.info "run" ~doc:"Build and launch a native macOS or physical-iOS application.")
    Term.(
      const run
      $ platform
      $ profile
      $ device
      $ development_team
      $ signing_identity
      $ native_object
      $ arguments)
;;

let exec_command =
  let program = Arg.(required & pos 0 (some string) None & info [] ~docv:"COMMAND") in
  let arguments = Arg.(value & pos_right 0 string [] & info [] ~docv:"ARGUMENT") in
  Cmd.v
    (Cmd.info
       "exec"
       ~doc:
         "Prepare native artifacts and execute a command with their paths in the \
          environment.")
    Term.(
      const (fun profile native_object program arguments ->
        exec profile native_object (program :: arguments))
      $ profile
      $ native_object
      $ program
      $ arguments)
;;

let sync_host_command =
  let check =
    Arg.(
      value & flag & info [ "check" ] ~doc:"Check generated Xcode files without writing.")
  in
  Cmd.v
    (Cmd.info
       "sync-host"
       ~doc:
         "Generate or check the Xcode host; application Swift sources remain owned by \
          the application.")
    Term.(const sync_host $ check)
;;

let resolve_packages_command =
  Cmd.v
    (Cmd.info
       "resolve-packages"
       ~doc:"Resolve and lock application Swift packages in staging.")
    Term.(const resolve_packages $ const ())
;;

let clean_command =
  let target =
    Arg.(
      value
      & pos 0 (some (enum [ "macos", Clean.Macos; "iphoneos", Clean.Iphoneos ])) None
      & info [] ~docv:"PLATFORM")
  in
  let all = Arg.(value & flag & info [ "all-project-builds" ]) in
  Cmd.v
    (Cmd.info "clean" ~doc:"Remove project-local native build output.")
    Term.(const clean $ target $ all)
;;

let resolve_dune_closure_command =
  let root =
    Arg.(required & opt (some string) None & info [ "project-root" ] ~docv:"PATH")
  in
  let target =
    Arg.(required & opt (some string) None & info [ "target" ] ~docv:"TARGET")
  in
  Cmd.v
    (Cmd.info
       "internal-resolve-dune-closure"
       ~doc:"Resolve one application's external Dune dependencies.")
    Term.(const resolve_dune_closure $ root $ target)
;;

let toolchain_command =
  let iphoneos =
    Arg.(required & pos 0 (some (enum [ "iphoneos", () ])) None & info [] ~docv:"TARGET")
  in
  let subcommand name doc action =
    Cmd.v (Cmd.info name ~doc) Term.(const (fun () -> action ()) $ iphoneos)
  in
  Cmd.group
    (Cmd.info
       "toolchain"
       ~doc:"Install, inspect, or remove the global iPhoneOS toolchain.")
    [ subcommand "install" "Install the locked global iPhoneOS SDK." toolchain_install
    ; subcommand "show" "Show the installed iPhoneOS SDK manifest." toolchain_show
    ; subcommand "verify" "Verify the installed iPhoneOS SDK." toolchain_verify
    ; subcommand "remove" "Remove the fixed global iPhoneOS switch." toolchain_remove
    ]
;;

let command =
  Cmd.group
    (Cmd.info
       "bonsai-swiftui"
       ~version:"0.1.0~dev"
       ~doc:"OCaml-first tooling for native SwiftUI applications.")
    [ init_command
    ; doctor_command
    ; build_native_command
    ; build_command
    ; run_command
    ; exec_command
    ; resolve_packages_command
    ; sync_host_command
    ; clean_command
    ; toolchain_command
    ; resolve_dune_closure_command
    ]
;;

let () = exit (Cmd.eval_result command)
