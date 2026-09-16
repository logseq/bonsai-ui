type target =
  | Macos
  | Iphoneos

type profile =
  | Debug
  | Profile
  | Release

type action =
  | Run
  | Build

type platform =
  | Macos_platform
  | Ios_platform

type command =
  { program : string
  ; arguments : string list
  ; working_directory : string
  ; environment : (string * string) list
  }

type native_build =
  { command : command
  ; build_directory : string
  ; source_object : string
  ; staged_object : string
  ; manifest : string
  ; log : string
  ; lock : string
  }

let iphoneos_switch = "bonsai-swiftui-ios"

let target_name = function
  | Macos -> "macos"
  | Iphoneos -> "iphoneos"
;;

let profile_name = function
  | Debug -> "debug"
  | Profile -> "profile"
  | Release -> "release"
;;

let ios_configuration_name = function
  | Debug -> "Debug"
  | Profile -> "Profile"
  | Release -> "Release"
;;

let dune_profile = function
  | Debug -> "dev"
  | Profile | Release -> "release"
;;

let product_name (config : Config.t) =
  "Bonsai"
  ^ (String.split_on_char '_' config.name
     |> List.map String.capitalize_ascii
     |> String.concat "")
;;

let apple_host ~project_root (config : Config.t) =
  Filename.concat project_root config.apple_root
;;

let app_bundle ~project_root ~config ~platform ~profile =
  let configuration =
    ios_configuration_name profile
    ^
    match platform with
    | Macos_platform -> ""
    | Ios_platform -> "-iphoneos"
  in
  Filename.concat
    (apple_host ~project_root config)
    (Printf.sprintf
       "DerivedData/Build/Products/%s/%s.app"
       configuration
       (product_name config))
;;

let ios_app_bundle ~project_root ~config ~profile =
  app_bundle ~project_root ~config ~platform:Ios_platform ~profile
;;

let apple_build
      ~project_root
      ~config
      ~platform
      ~profile
      ~no_codesign
      ~development_team
      ~signing_identity
  =
  let host = apple_host ~project_root config in
  let product = product_name config in
  let platform_name, destination =
    match platform with
    | Macos_platform -> "macOS", "platform=macOS,arch=arm64"
    | Ios_platform -> "iOS", "generic/platform=iOS"
  in
  { program = "xcodebuild"
  ; arguments =
      [ "-project"
      ; Filename.concat host (product ^ ".xcodeproj")
      ; "-scheme"
      ; product ^ "-" ^ platform_name
      ; "-configuration"
      ; ios_configuration_name profile
      ; "-destination"
      ; destination
      ; "-derivedDataPath"
      ; Filename.concat host "DerivedData"
      ]
      @ (if config.Config.swift_packages = []
         then []
         else
           [ "-disableAutomaticPackageResolution"
           ; "-onlyUsePackageVersionsFromResolvedFile"
           ; "-skipPackageUpdates"
           ])
      @ (match development_team with
         | None -> []
         | Some team -> [ "DEVELOPMENT_TEAM=" ^ team ])
      @ (match signing_identity with
         | None -> []
         | Some identity -> [ "CODE_SIGN_IDENTITY=" ^ identity ])
      @ (if no_codesign then [ "CODE_SIGNING_ALLOWED=NO" ] else [])
      @ [ "build" ]
  ; working_directory = project_root
  ; environment = []
  }
;;

let ios_bundle_identifier ~project_root ~app_bundle =
  { program = "plutil"
  ; arguments =
      [ "-extract"
      ; "CFBundleIdentifier"
      ; "raw"
      ; "-o"
      ; "-"
      ; Filename.concat app_bundle "Info.plist"
      ]
  ; working_directory = project_root
  ; environment = []
  }
;;

let ios_device_install ~project_root ~device ~app_bundle =
  { program = "xcrun"
  ; arguments =
      [ "devicectl"; "device"; "install"; "app"; "--device"; device; app_bundle ]
  ; working_directory = project_root
  ; environment = []
  }
;;

let ios_device_launch ~project_root ~device ~bundle_identifier =
  { program = "xcrun"
  ; arguments =
      [ "devicectl"
      ; "device"
      ; "process"
      ; "launch"
      ; "--device"
      ; device
      ; "--terminate-existing"
      ; bundle_identifier
      ]
  ; working_directory = project_root
  ; environment = []
  }
;;

let valid_path_component value =
  value <> ""
  && value <> "."
  && value <> ".."
  && String.for_all
       (function
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' -> true
         | _ -> false)
       value
;;

let only_architecture = function
  | [ architecture ] -> architecture
  | _ -> invalid_arg "validated platform must contain exactly one architecture"
;;

let native_build
      ~project_root
      ~(config : Config.t)
      ~target
      ~profile
      ~toolchain_fingerprint
      ~apple_sdk_root
      ~apple_sdk_version
  =
  if Filename.is_relative project_root
  then Error "The project root must be absolute"
  else if
    config.native_target = ""
    || (not (Filename.is_relative config.native_target))
    || List.mem ".." (String.split_on_char '/' config.native_target)
    || config.native_target.[0] = '-'
    || config.native_target.[0] = '@'
    || not (String.ends_with ~suffix:".exe.o" config.native_target)
  then Error "The native target must be a project-relative complete-object path"
  else if not (valid_path_component toolchain_fingerprint)
  then Error (Printf.sprintf "Invalid toolchain fingerprint: %s" toolchain_fingerprint)
  else (
    let platform, context, architecture, deployment_environment =
      match target with
      | Macos ->
        ( "macos"
        , "default"
        , only_architecture config.macos.architectures
        , [ "MACOSX_DEPLOYMENT_TARGET", config.macos.minimum_version ] )
      | Iphoneos ->
        ( "iphoneos"
        , "default.ios"
        , only_architecture config.ios.architectures
        , [ "VER", config.ios.minimum_version ] )
    in
    let dune_profile = dune_profile profile in
    let profile_name = profile_name profile in
    let build_directory =
      Filename.concat
        project_root
        (Printf.sprintf
           "_build/bonsai-swiftui/dune/%s/%s/%s"
           platform
           toolchain_fingerprint
           profile_name)
    in
    let dune_arguments =
      [ "dune"
      ; "build"
      ; "--root=" ^ project_root
      ; "--build-dir=" ^ build_directory
      ; "--profile=" ^ dune_profile
      ]
      @ (match target with
         | Macos -> []
         | Iphoneos -> [ "-x"; "ios" ])
      @ [ Sexplib.Sexp.to_string (Sexplib.Sexp.Atom config.native_target) ]
    in
    let arguments =
      match target with
      | Macos -> [ "exec"; "--" ] @ dune_arguments
      | Iphoneos -> [ "exec"; "--switch=" ^ iphoneos_switch; "--" ] @ dune_arguments
    in
    let sdk_environment =
      match target, apple_sdk_version with
      | Macos, _ -> Ok []
      | Iphoneos, Some version -> Ok [ "SDK", version ]
      | Iphoneos, None -> Error "The iPhoneOS SDK version is required"
    in
    match sdk_environment with
    | Error _ as error -> error
    | Ok sdk_environment ->
      let artifact_platform =
        match target with
        | Macos -> "macos/" ^ architecture
        | Iphoneos -> "ios/iphoneos/" ^ architecture
      in
      let state_platform =
        match target with
        | Macos -> "macos"
        | Iphoneos -> "iphoneos"
      in
      let build_root = Filename.concat project_root "_build/bonsai-swiftui" in
      Ok
        { command =
            { program = "opam"
            ; arguments
            ; working_directory = project_root
            ; environment =
                [ "BONSAI_SWIFTUI_APPLE_SDK_ROOT", apple_sdk_root
                ; "BUILD_PATH_PREFIX_MAP", project_root ^ "=."
                ]
                @ deployment_environment
                @ sdk_environment
            }
        ; build_directory
        ; source_object =
            Filename.concat build_directory (Filename.concat context config.native_target)
        ; staged_object =
            Filename.concat
              build_root
              (Printf.sprintf
                 "artifacts/%s/%s/%s"
                 artifact_platform
                 profile_name
                 (Filename.basename config.native_target))
        ; manifest =
            Filename.concat
              build_root
              (Printf.sprintf
                 "state/%s/%s/build-manifest.sexp"
                 state_platform
                 profile_name)
        ; log =
            Filename.concat
              build_root
              (Printf.sprintf "logs/%s/%s.log" state_platform profile_name)
        ; lock =
            Filename.concat
              build_root
              (Printf.sprintf "locks/%s/%s.lock" state_platform profile_name)
        })
;;
