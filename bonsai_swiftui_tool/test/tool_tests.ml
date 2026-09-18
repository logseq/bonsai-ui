open Bonsai_swiftui_tool

let valid_config =
  {|
(lang 4)

(app
 (name journal)
 (apple_root apple)
 (native_target app/native_embed.exe.o)
 (features network sqlite)
 (macos
  (bundle_identifier org.example.journal)
  (minimum_version 26.0)
  (architectures arm64))
 (ios
  (bundle_identifier org.example.journal.ios)
  (minimum_version 18.0)
  (architectures arm64)))
|}
;;

let get_ok = function
  | Ok value -> value
  | Error message -> Alcotest.fail message
;;

let contains source pattern =
  try
    ignore (Str.search_forward (Str.regexp_string pattern) source 0);
    true
  with
  | Not_found -> false
;;

let count_occurrences source pattern =
  let regexp = Str.regexp_string pattern in
  let rec loop count position =
    try
      let index = Str.search_forward regexp source position in
      loop (count + 1) (index + String.length pattern)
    with
    | Not_found -> count
  in
  loop 0 0
;;

let check_error_contains expected = function
  | Ok _ -> Alcotest.failf "expected an error containing %S" expected
  | Error message -> Alcotest.(check bool) message true (contains message expected)
;;

let replace_once source ~pattern ~replacement =
  let regexp = Str.regexp_string pattern in
  Str.replace_first regexp replacement source
;;

let read_file path =
  let channel = open_in_bin path in
  let contents = really_input_string channel (in_channel_length channel) in
  close_in channel;
  contents
;;

let write_file path contents =
  Scaffold.ensure_directory (Filename.dirname path);
  let channel = open_out_bin path in
  output_string channel contents;
  close_out channel
;;

let write_executable path contents =
  write_file path contents;
  Unix.chmod path 0o755
;;

let non_empty_lines source =
  source |> String.split_on_char '\n' |> List.filter (fun line -> line <> "")
;;

let with_environment bindings f =
  let previous = List.map (fun (name, _) -> name, Sys.getenv_opt name) bindings in
  List.iter (fun (name, value) -> Unix.putenv name value) bindings;
  Fun.protect
    ~finally:(fun () ->
      List.iter
        (fun (name, value) ->
           match value with
           | Some value -> Unix.putenv name value
           | None -> Unix.putenv name "")
        previous)
    f
;;

let command_logger program =
  Printf.sprintf
    {|#!/bin/sh
set -eu
{
  printf '%%s\t%%s' '%s' "$PWD"
  for argument in "$@"; do
    printf '\t%%s' "$argument"
  done
  printf '\n'
} >> "$COMMAND_LOG"
|}
    program
;;

let test_schema_four_host_configuration () =
  let source =
    {|(lang 4)
(app (name acceptance) (apple_root apple) (native_target app/native_embed.exe.o)
 (features)
 (macos (bundle_identifier org.example.desktop) (minimum_version 26.0)
  (architectures arm64)
  (entitlements (debug config/debug.plist) (profile config/debug.plist)
   (release config/release.plist)))
 (ios (bundle_identifier org.example.phone) (minimum_version 18.0)
  (architectures arm64))
 (swift_packages
  (package (id swift-collections) (url https://github.com/apple/swift-collections.git)
   (requirement (exact 1.1.4))
   (products (product (name OrderedCollections) (platforms macos ios))))))|}
  in
  let duplicate =
    "(package (id swift-collections) (url https://example.com/another.git) (requirement \
     (exact 1.0.0)) (products (product (name Another) (platforms macos))))"
  in
  let collision =
    replace_once
      source
      ~pattern:"(swift_packages"
      ~replacement:("(swift_packages " ^ duplicate)
  in
  check_error_contains "Duplicate package identity" (Config.parse_string collision);
  let collision =
    replace_once collision ~pattern:"(id swift-collections)" ~replacement:"(id other)"
  in
  let collision =
    replace_once
      collision
      ~pattern:"https://example.com/another.git"
      ~replacement:"https://example.com/swift-collections.git"
  in
  check_error_contains "Duplicate remote package identity" (Config.parse_string collision);
  ignore (get_ok (Config.parse_string source));
  ignore
    (get_ok
       (Config.parse_string
          (replace_once
             source
             ~pattern:"(exact 1.1.4)"
             ~replacement:"(revision 0123456789abcdef0123456789abcdef01234567)")));
  List.iter
    (fun (pattern, replacement, diagnostic) ->
       check_error_contains
         diagnostic
         (Config.parse_string (replace_once source ~pattern ~replacement)))
    [ "(lang 4)", "(lang 3)", "Unsupported schema version"
    ; "org.example.phone", "invalid identity", "exactly one"
    ; "org.example.phone", "invalid", "Invalid bundle identifier"
    ; "org.example.phone", "org." ^ String.make 245 'a', "Invalid bundle identifier"
    ; "(bundle_identifier org.example.phone)", "", "Missing ios field"
    ; ( "(name acceptance)"
      , "(name acceptance) (bundle_identifier org.old)"
      , "Unknown app field" )
    ; "(release config/release.plist)", "", "Missing macos.entitlements field"
    ; ( "(debug config/debug.plist)"
      , "(debug config/debug.plist) (debug config/debug.plist)"
      , "Duplicate" )
    ; "config/debug.plist", "../debug.plist", "parent traversal"
    ; "config/debug.plist", "/tmp/debug.plist", "relative path"
    ; "(exact 1.1.4)", "(branch main)", "requirement"
    ; "(exact 1.1.4)", "(exact 1.1)", "version"
    ; "(exact 1.1.4)", "(revision abcdef)", "revision"
    ; "https://github.com", "http://github.com", "HTTPS"
    ; "https://github.com", "https://", "HTTPS"
    ; "(platforms macos ios)", "(platforms)", "platform"
    ; "(platforms macos ios)", "(platforms macos macos)", "Duplicate"
    ; "(platforms macos ios)", "(platforms tvos)", "platform"
    ; "(name OrderedCollections)", "(name BonsaiSwiftUI)", "reserved"
    ; "(id swift-collections)", "(id bonsaiswiftui)", "reserved"
    ; ( "(products (product (name OrderedCollections) (platforms macos ios)))"
      , "(products)"
      , "products" )
    ; ( "(products (product (name OrderedCollections) (platforms macos ios)))"
      , "(products (product (name OrderedCollections) (platforms macos)) (product (name \
         OrderedCollections) (platforms macos)))"
      , "Duplicate" )
    ; "(id swift-collections)", "(id swift-collections) (unexpected true)", "Unknown"
    ]
;;

let test_parse_valid_config () =
  let config = Config.parse_string valid_config |> get_ok in
  Alcotest.(check string) "name" "journal" config.name;
  Alcotest.(check string) "Apple root" "apple" config.apple_root;
  Alcotest.(check string) "native target" "app/native_embed.exe.o" config.native_target;
  Alcotest.(check (list string))
    "features"
    [ "core"; "network"; "sqlite" ]
    (List.map Config.Feature.to_string config.features);
  Alcotest.(check string) "macOS minimum" "26.0" config.macos.minimum_version;
  Alcotest.(check string) "iOS minimum" "18.0" config.ios.minimum_version;
  Alcotest.(check (list string)) "iOS architectures" [ "arm64" ] config.ios.architectures
;;

let test_application_ios_minimum () =
  let configured version =
    replace_once
      valid_config
      ~pattern:"(minimum_version 18.0)"
      ~replacement:("(minimum_version " ^ version ^ ")")
  in
  List.iter
    (fun version ->
       let config = Config.parse_string (configured version) |> get_ok in
       Alcotest.(check string)
         "application minimum retained"
         version
         config.ios.minimum_version)
    [ "18.0"; "26.0"; "26.1" ];
  List.iter
    (fun version ->
       match Config.parse_string (configured version) with
       | Error _ -> ()
       | Ok _ -> Alcotest.failf "invalid deployment minimum accepted: %s" version)
    [ "17.9"; "0.0"; "26"; "26.x"; "26.0.1"; "26.0beta"; "-26.0"; "026.0"; "26.00" ]
;;

let test_invalid_configs () =
  [ ( "unsupported schema"
    , replace_once valid_config ~pattern:"(lang 4)" ~replacement:"(lang 1)"
    , "Unsupported schema version" )
  ; ( "unknown field"
    , replace_once
        valid_config
        ~pattern:"(features network sqlite)"
        ~replacement:"(mystery true)"
    , "Unknown app field" )
  ; ( "duplicate field"
    , replace_once
        valid_config
        ~pattern:"(name journal)"
        ~replacement:"(name journal) (name other)"
    , "Duplicate app field" )
  ; ( "unsafe name"
    , replace_once valid_config ~pattern:"(name journal)" ~replacement:"(name ../journal)"
    , "Invalid application name" )
  ; ( "absolute native target"
    , replace_once
        valid_config
        ~pattern:"app/native_embed.exe.o"
        ~replacement:"/tmp/native_embed.exe.o"
    , "native_target must be a relative path" )
  ; ( "traversing native target"
    , replace_once
        valid_config
        ~pattern:"app/native_embed.exe.o"
        ~replacement:"../native_embed.exe.o"
    , "native_target must not contain parent traversal" )
  ; ( "unsupported macOS minimum"
    , replace_once valid_config ~pattern:"26.0" ~replacement:"13.0"
    , "Unsupported macOS minimum version" )
  ; ( "unsupported macOS architecture"
    , replace_once
        valid_config
        ~pattern:"(minimum_version 26.0)\n  (architectures arm64)"
        ~replacement:"(minimum_version 26.0)\n  (architectures x86_64)"
    , "Unsupported macOS architecture" )
  ; ( "duplicate macOS architecture"
    , replace_once
        valid_config
        ~pattern:"(minimum_version 26.0)\n  (architectures arm64)"
        ~replacement:"(minimum_version 26.0)\n  (architectures arm64 arm64)"
    , "Duplicate macOS architecture" )
  ; ( "empty macOS architecture"
    , replace_once
        valid_config
        ~pattern:"(minimum_version 26.0)\n  (architectures arm64)"
        ~replacement:"(minimum_version 26.0)\n  (architectures)"
    , "macos.architectures must not be empty" )
  ; ( "unsupported iOS architecture"
    , replace_once
        valid_config
        ~pattern:"(minimum_version 18.0)\n  (architectures arm64)"
        ~replacement:"(minimum_version 18.0)\n  (architectures x86_64)"
    , "Unsupported iOS architecture" )
  ; ( "duplicate feature"
    , replace_once
        valid_config
        ~pattern:"(features network sqlite)"
        ~replacement:"(features network network)"
    , "Duplicate feature" )
  ]
  |> List.iter (fun (name, input, expected) ->
    match Config.parse_string input with
    | Error message when String.length message >= String.length expected ->
      let found = ref false in
      for index = 0 to String.length message - String.length expected do
        if String.sub message index (String.length expected) = expected then found := true
      done;
      Alcotest.(check bool) name true !found
    | Error message -> Alcotest.failf "%s: unexpected error: %s" name message
    | Ok _ -> Alcotest.failf "%s: expected an error" name)
;;

let test_command_plans () =
  let config = Config.parse_string valid_config |> get_ok in
  let macos =
    Plan.native_build
      ~project_root:"/work/journal"
      ~config
      ~target:Plan.Macos
      ~profile:Plan.Debug
      ~toolchain_fingerprint:"host-abc"
      ~apple_sdk_root:"/Xcode/MacOSX.sdk"
      ~apple_sdk_version:None
    |> get_ok
  in
  Alcotest.(check string) "macOS executable" "opam" macos.command.program;
  Alcotest.(check (list string))
    "macOS args"
    [ "exec"
    ; "--"
    ; "dune"
    ; "build"
    ; "--root=/work/journal"
    ; "--build-dir=/work/journal/_build/bonsai-swiftui/dune/macos/host-abc/debug"
    ; "--profile=dev"
    ; "app/native_embed.exe.o"
    ]
    macos.command.arguments;
  Alcotest.(check bool)
    "no embedding gate"
    false
    (List.mem_assoc "BONSAI_SWIFTUI_EMBED_OCAML" macos.command.environment);
  Alcotest.(check string)
    "macOS deployment environment"
    "26.0"
    (List.assoc "MACOSX_DEPLOYMENT_TARGET" macos.command.environment);
  Alcotest.(check string)
    "macOS SDK root"
    "/Xcode/MacOSX.sdk"
    (List.assoc "BONSAI_SWIFTUI_APPLE_SDK_ROOT" macos.command.environment);
  Alcotest.(check string)
    "macOS source object"
    "/work/journal/_build/bonsai-swiftui/dune/macos/host-abc/debug/default/app/native_embed.exe.o"
    macos.source_object;
  Alcotest.(check string)
    "macOS staged object"
    "/work/journal/_build/bonsai-swiftui/artifacts/macos/arm64/debug/native_embed.exe.o"
    macos.staged_object;
  let ios =
    Plan.native_build
      ~project_root:"/work/journal"
      ~config
      ~target:Plan.Iphoneos
      ~profile:Plan.Release
      ~toolchain_fingerprint:"sdk-def"
      ~apple_sdk_root:"/Xcode/iPhoneOS.sdk"
      ~apple_sdk_version:(Some "26.0")
    |> get_ok
  in
  Alcotest.(check string) "iOS executable" "opam" ios.command.program;
  Alcotest.(check (list string))
    "iOS args"
    [ "exec"
    ; "--switch=bonsai-swiftui-ios"
    ; "--"
    ; "dune"
    ; "build"
    ; "--root=/work/journal"
    ; "--build-dir=/work/journal/_build/bonsai-swiftui/dune/iphoneos/sdk-def/release"
    ; "--profile=release"
    ; "-x"
    ; "ios"
    ; "app/native_embed.exe.o"
    ]
    ios.command.arguments;
  Alcotest.(check bool)
    "macOS environment is not leaked to iPhoneOS"
    false
    (List.mem_assoc "MACOSX_DEPLOYMENT_TARGET" ios.command.environment);
  Alcotest.(check string)
    "iOS SDK version"
    "26.0"
    (List.assoc "SDK" ios.command.environment);
  Alcotest.(check string)
    "iOS deployment target"
    "18.0"
    (List.assoc "VER" ios.command.environment);
  Alcotest.(check string)
    "iOS source object"
    "/work/journal/_build/bonsai-swiftui/dune/iphoneos/sdk-def/release/default.ios/app/native_embed.exe.o"
    ios.source_object;
  Alcotest.(check string)
    "iOS staged object"
    "/work/journal/_build/bonsai-swiftui/artifacts/ios/iphoneos/arm64/release/native_embed.exe.o"
    ios.staged_object;
  List.iter
    (fun path ->
       Alcotest.(check bool)
         ("project-local path: " ^ path)
         true
         (String.starts_with ~prefix:"/work/journal/_build/bonsai-swiftui/" path))
    [ ios.build_directory
    ; ios.source_object
    ; ios.staged_object
    ; ios.manifest
    ; ios.log
    ; ios.lock
    ];
  Plan.native_build
    ~project_root:"/work/journal"
    ~config
    ~target:Plan.Iphoneos
    ~profile:Plan.Debug
    ~toolchain_fingerprint:"../../../shared"
    ~apple_sdk_root:"/Xcode/iPhoneOS.sdk"
    ~apple_sdk_version:(Some "26.0")
  |> check_error_contains "Invalid toolchain fingerprint"
;;

let test_fixed_iphoneos_switch () =
  Alcotest.(check string) "fixed switch" "bonsai-swiftui-ios" Plan.iphoneos_switch;
  valid_config
  |> replace_once
       ~pattern:"(minimum_version 18.0)"
       ~replacement:"(minimum_version 18.0)\n  (switch local-ios)"
  |> Config.parse_string
  |> check_error_contains "Unknown ios field: switch"
;;

let valid_sdk_manifest =
  {|
(sdk
 (format_version 1)
 (bonsai_swiftui_version 0.1.0~dev)
 (bonsai_swiftui_source
  a51276a09eb1cdf9c87f07ac4c7558ed7c6b2d69
  sha256
  8ab6845bdda0b53c450a14c7c1382c652e5af0093c38ddad8e867db4c6a36f91)
 (abi_version 4)
 (ocaml_version 5.1.1)
 (dune_version_range 3.17 4.0)
 (cross_compiler ocaml-ios64 5.1.1)
 (findlib_toolchain ios)
 (architecture arm64)
 (platform iphoneos)
 (minimum_deployment_target 18.0)
 (package_universe_digest package-digest)
 (target_components_digest component-digest)
 (required_frameworks Foundation Security)
 (required_system_libraries sqlite3)
 (build_recipe_revision 5)
 (packages
  (base v0.17.0)
  (bonsai_swiftui 0.1.0~dev)
  (core v0.17.0))
 (libraries
  (base base v0.17.0 (base base.md5))
  (bonsai_swiftui.ui bonsai_swiftui 0.1.0~dev
   (bonsai_swiftui.driver bonsai_swiftui.ui))))
|}
;;

let parse_sdk_manifest source = Sdk.Manifest.parse source |> get_ok

let test_sdk_manifest_contract () =
  let validate_supported source =
    Sdk.Manifest.validate
      (parse_sdk_manifest source)
      ~bonsai_swiftui_version:Sdk.supported_bonsai_swiftui_version
      ~abi_version:Sdk.supported_abi_version
      ~minimum_deployment_target:Sdk.supported_minimum_deployment_target
  in
  valid_sdk_manifest |> validate_supported |> get_ok;
  valid_sdk_manifest
  |> replace_once ~pattern:"(abi_version 4)" ~replacement:"(abi_version 2)"
  |> validate_supported
  |> check_error_contains "SDK manifest is incompatible";
  let manifest = parse_sdk_manifest valid_sdk_manifest in
  Sdk.Manifest.validate
    manifest
    ~bonsai_swiftui_version:"0.1.0~dev"
    ~abi_version:"4"
    ~minimum_deployment_target:"18.0"
  |> get_ok;
  Sdk.Manifest.validate_packages
    manifest
    [ "bonsai_swiftui", "0.1.0~dev"; "base", "v0.17.0" ]
  |> get_ok;
  Sdk.Manifest.validate_packages manifest [ "missing", "1.0" ]
  |> check_error_contains
       "Package missing.1.0 is not in the fixed iPhoneOS SDK package universe";
  Sdk.Manifest.validate_packages manifest [ "base", "v0.18.0" ]
  |> check_error_contains
       "Package base.v0.18.0 conflicts with iPhoneOS SDK package base.v0.17.0";
  Sdk.Manifest.validate
    (valid_sdk_manifest
     |> replace_once ~pattern:"(platform iphoneos)" ~replacement:"(platform macos)"
     |> parse_sdk_manifest)
    ~bonsai_swiftui_version:"0.1.0~dev"
    ~abi_version:"4"
    ~minimum_deployment_target:"18.0"
  |> check_error_contains "expected Apple platform iphoneos";
  Sdk.Manifest.validate
    manifest
    ~bonsai_swiftui_version:"0.2.0"
    ~abi_version:"4"
    ~minimum_deployment_target:"18.0"
  |> check_error_contains
       "The iPhoneOS switch SDK manifest is incompatible with bonsai-swiftui 0.2.0";
  Sdk.Manifest.validate
    (valid_sdk_manifest
     |> replace_once
          ~pattern:"(build_recipe_revision 5)"
          ~replacement:"(build_recipe_revision 4)"
     |> parse_sdk_manifest)
    ~bonsai_swiftui_version:"0.1.0~dev"
    ~abi_version:"4"
    ~minimum_deployment_target:"18.0"
  |> check_error_contains
       "Run: bonsai-swiftui toolchain remove iphoneos; bonsai-swiftui toolchain install \
        iphoneos";
  Sdk.Manifest.validate
    manifest
    ~bonsai_swiftui_version:"0.1.0~dev"
    ~abi_version:"4"
    ~minimum_deployment_target:"14.0"
  |> check_error_contains "minimum deployment target 14.0 is unsupported";
  Sdk.Manifest.validate
    (valid_sdk_manifest
     |> replace_once ~pattern:"(abi_version 4)" ~replacement:"(abi_version 1)"
     |> parse_sdk_manifest)
    ~bonsai_swiftui_version:"0.1.0~dev"
    ~abi_version:"4"
    ~minimum_deployment_target:"18.0"
  |> check_error_contains
       "Run: bonsai-swiftui toolchain remove iphoneos; bonsai-swiftui toolchain install \
        iphoneos";
  valid_sdk_manifest
  |> replace_once
       ~pattern:" (target_components_digest component-digest)\n"
       ~replacement:""
  |> Sdk.Manifest.parse
  |> check_error_contains "Missing SDK manifest field: target_components_digest"
;;

let test_sdk_accepts_framework_source_drift () =
  let stale_manifest =
    valid_sdk_manifest
    |> replace_once
         ~pattern:"a51276a09eb1cdf9c87f07ac4c7558ed7c6b2d69"
         ~replacement:"ea5e96b4dd38795a901720c80e1ffc9eb684b86c"
    |> replace_once
         ~pattern:"8ab6845bdda0b53c450a14c7c1382c652e5af0093c38ddad8e867db4c6a36f91"
         ~replacement:"c20edc77779c24c411854a19d234887615a6ba0a352784d35a970fb0a7d148a5"
    |> parse_sdk_manifest
  in
  Sdk.Manifest.validate
    stale_manifest
    ~bonsai_swiftui_version:"0.1.0~dev"
    ~abi_version:"4"
    ~minimum_deployment_target:"18.0"
  |> get_ok
;;

let test_sdk_accepts_missing_framework_source_identity () =
  let legacy_manifest =
    valid_sdk_manifest
    |> replace_once
         ~pattern:
           " (bonsai_swiftui_source\n\
           \  a51276a09eb1cdf9c87f07ac4c7558ed7c6b2d69\n\
           \  sha256\n\
           \  8ab6845bdda0b53c450a14c7c1382c652e5af0093c38ddad8e867db4c6a36f91)\n"
         ~replacement:""
    |> replace_once ~pattern:"(abi_version 4)" ~replacement:"(abi_version 1)"
    |> parse_sdk_manifest
  in
  Sdk.Manifest.validate
    legacy_manifest
    ~bonsai_swiftui_version:"0.1.0~dev"
    ~abi_version:"1"
    ~minimum_deployment_target:"18.0"
  |> get_ok
;;

let application_lock =
  {|opam-version: "2.0"
name: "demo"
version: "0.1.0"
depends: [
  "base" {= "v0.17.0"}
  "bonsai_swiftui" {= "0.1.0~dev"}
  "unreachable" {= "99.0"}
]
|}
;;

let test_sdk_validates_only_reachable_application_lock_subset () =
  let root = Filename.temp_dir "bonsai-swiftui-tool" "application-lock" in
  let lock = Filename.concat root "demo.opam.locked" in
  write_file lock application_lock;
  let manifest = parse_sdk_manifest valid_sdk_manifest in
  Alcotest.(check (list (pair string string)))
    "reachable package subset"
    [ "base", "v0.17.0"; "bonsai_swiftui", "0.1.0~dev" ]
    (Sdk.validate_application_lock
       ~project_root:root
       ~application_name:"demo"
       ~reachable_libraries:[ "bonsai_swiftui.ui"; "base" ]
       manifest
     |> get_ok);
  Sdk.validate_application_lock
    ~project_root:root
    ~application_name:"demo"
    ~reachable_libraries:[ "unsupported.library" ]
    manifest
  |> check_error_contains
       "Findlib library unsupported.library is not provided by the iPhoneOS SDK";
  write_file
    lock
    (application_lock
     |> replace_once
          ~pattern:"\"base\" {= \"v0.17.0\"}"
          ~replacement:"\"base\" {= \"v0.18.0\"}");
  Sdk.validate_application_lock
    ~project_root:root
    ~application_name:"demo"
    ~reachable_libraries:[ "base" ]
    manifest
  |> check_error_contains
       "Package base.v0.18.0 conflicts with reachable SDK package base.v0.17.0";
  write_file
    lock
    (application_lock
     |> replace_once ~pattern:"  \"base\" {= \"v0.17.0\"}\n" ~replacement:"");
  Sdk.validate_application_lock
    ~project_root:root
    ~application_name:"demo"
    ~reachable_libraries:[ "base" ]
    manifest
  |> check_error_contains
       "Reachable SDK package base.v0.17.0 is missing from demo.opam.locked";
  write_file
    lock
    (application_lock
     |> replace_once
          ~pattern:"\"base\" {= \"v0.17.0\"}"
          ~replacement:"\"base\" {>= \"v0.17.0\"}");
  Sdk.validate_application_lock
    ~project_root:root
    ~application_name:"demo"
    ~reachable_libraries:[ "base" ]
    manifest
  |> check_error_contains "Dependency base in demo.opam.locked is not pinned exactly"
;;

let test_sdk_manifest_fingerprint_is_canonical () =
  let compact = parse_sdk_manifest valid_sdk_manifest in
  let expanded =
    valid_sdk_manifest
    |> replace_once
         ~pattern:"(architecture arm64)"
         ~replacement:"(architecture       arm64)"
    |> parse_sdk_manifest
  in
  let first = Sdk.Manifest.fingerprint compact in
  let second = Sdk.Manifest.fingerprint expanded in
  Alcotest.(check string) "whitespace independent" first second;
  Alcotest.(check int) "SHA-256 length" 64 (String.length first);
  let changed =
    valid_sdk_manifest
    |> replace_once ~pattern:"component-digest" ~replacement:"changed-digest"
    |> parse_sdk_manifest
    |> Sdk.Manifest.fingerprint
  in
  Alcotest.(check bool) "component changes identity" true (first <> changed)
;;

let test_sdk_preflight_is_read_only () =
  let root = Filename.temp_dir "bonsai-swiftui-tool" "sdk-preflight" |> Unix.realpath in
  let project_root = Filename.concat root "project" in
  let prefix = Filename.concat root "switch-prefix" in
  let bin = Filename.concat root "bin" in
  let command_log = Filename.concat root "commands.log" in
  Scaffold.ensure_directory project_root;
  [ "dune"; "ocamlc"; "ocamlfind" ]
  |> List.iter (fun program ->
    write_executable (Filename.concat prefix ("bin/" ^ program)) "#!/bin/sh\nexit 0\n");
  let manifest_path =
    Filename.concat prefix "share/bonsai_swiftui_ios_sdk/manifest.sexp"
  in
  write_file manifest_path valid_sdk_manifest;
  write_executable
    (Filename.concat bin "opam")
    (command_logger "opam"
     ^ Printf.sprintf
         {|if test "$1" = switch && test "$2" = show; then
  printf '%%s\n' 'bonsai-swiftui-ios'
elif test "$1" = var && test "$2" = --switch=bonsai-swiftui-ios; then
  printf '%%s\n' '%s'
elif test "$1" = exec && test "$4" = dune; then
  printf '%%s\n' '3.18.2'
elif test "$1" = exec && test "$4" = ocamlc; then
  printf '%%s\n' '5.1.1'
elif test "$1" = exec && test "$4" = ocamlfind; then
  printf '%%s\n' '%s/lib/ios'
else
  exit 64
fi
|}
         prefix
         prefix);
  let manifest_mtime = (Unix.stat manifest_path).st_mtime in
  with_environment
    [ "PATH", bin ^ ":" ^ Option.value ~default:"" (Sys.getenv_opt "PATH")
    ; "COMMAND_LOG", command_log
    ]
    (fun () ->
       let result =
         Sdk.preflight
           ~project_root
           ~bonsai_swiftui_version:"0.1.0~dev"
           ~abi_version:"4"
           ~minimum_deployment_target:"18.0"
           ~required_packages:[ "base", "v0.17.0" ]
         |> get_ok
       in
       Alcotest.(check string) "global switch prefix" prefix result.switch_prefix;
       Alcotest.(check string)
         "manifest fingerprint"
         (valid_sdk_manifest |> parse_sdk_manifest |> Sdk.Manifest.fingerprint)
         result.fingerprint);
  Alcotest.(check (float 0.))
    "manifest remains untouched"
    manifest_mtime
    (Unix.stat manifest_path).st_mtime;
  let commands = read_file command_log |> non_empty_lines in
  Alcotest.(check int) "five read-only opam calls" 5 (List.length commands);
  Alcotest.(check bool)
    "switch is selected explicitly"
    true
    (List.for_all
       (fun command -> contains command "--switch=bonsai-swiftui-ios")
       commands);
  Alcotest.(check bool)
    "no mutation command"
    false
    (List.exists
       (fun command ->
          contains command " install "
          || contains command " remove "
          || contains command " switch create ")
       commands)
;;

let test_sdk_preflight_reports_missing_switch () =
  let root = Filename.temp_dir "bonsai-swiftui-tool" "missing-switch" |> Unix.realpath in
  let bin = Filename.concat root "bin" in
  Scaffold.ensure_directory (Filename.concat root "project");
  write_executable (Filename.concat bin "opam") "#!/bin/sh\nexit 2\n";
  with_environment
    [ "PATH", bin ^ ":" ^ Option.value ~default:"" (Sys.getenv_opt "PATH") ]
    (fun () ->
       Sdk.preflight
         ~project_root:(Filename.concat root "project")
         ~bonsai_swiftui_version:"0.1.0~dev"
         ~abi_version:"4"
         ~minimum_deployment_target:"18.0"
         ~required_packages:[]
       |> check_error_contains
            "The global iPhoneOS switch \"bonsai-swiftui-ios\" is missing. Run: \
             bonsai-swiftui toolchain install iphoneos")
;;

let rec repository_files root relative =
  let path = Filename.concat root relative in
  match (Unix.lstat path).st_kind with
  | Unix.S_DIR ->
    Sys.readdir path
    |> Array.to_list
    |> List.sort String.compare
    |> List.concat_map (fun name ->
      repository_files
        root
        (if relative = "" then name else Filename.concat relative name))
  | Unix.S_REG -> if relative = "repository.sexp" then [] else [ relative ]
  | Unix.S_LNK | Unix.S_CHR | Unix.S_BLK | Unix.S_FIFO | Unix.S_SOCK ->
    Alcotest.failf "invalid repository entry: %s" path
;;

let repository_digest root =
  let canonical =
    repository_files root ""
    |> List.map (fun relative ->
      relative ^ "\000" ^ Artifact.digest (Filename.concat root relative))
    |> String.concat "\000"
  in
  let temporary = Filename.temp_file "bonsai-swiftui-repository" ".digest-input" in
  Fun.protect
    ~finally:(fun () -> Sys.remove temporary)
    (fun () ->
       write_file temporary canonical;
       Artifact.digest temporary)
;;

let repository_lock ~digest ~source_digest ~package_digest ~archive_digest =
  Printf.sprintf
    {|(repository
 (format_version 1)
 (repository_version 0.1.0)
 (repository_snapshot_sha256 %s)
 (source_lock vendor/opam-ios/runtime-closure.lock %s)
 (package_universe package-universe.lock %s)
 (source_archives source-archives.lock %s)
 (default_repository https://github.com/RCmerci/opam-repository.git c98b21e24c088665ccae4c3b53eadadd3b755b15)
 (cross_repository https://github.com/ocaml-cross/opam-cross-ios.git 8380b52b0154752c26c6e221c04fbced3320aa48)
 (compiler ocaml-base-compiler 5.1.1)
 (sdk_package bonsai_swiftui_ios_sdk 0.1.0~dev.3))
|}
    digest
    source_digest
    package_digest
    archive_digest
;;

let write_repository_fixture root =
  let framework_root =
    root |> Filename.dirname |> Filename.dirname |> Filename.dirname |> Filename.dirname
  in
  let source_lock =
    Filename.concat framework_root "vendor/opam-ios/runtime-closure.lock"
  in
  write_file
    source_lock
    "# \
     package|version|role|capability|build-mechanism|source|sha256|components|dependencies\n";
  write_file (Filename.concat root "repo") "opam-version: \"2.0\"\n";
  write_file
    (Filename.concat root "package-universe.lock")
    "# package|version|repository|metadata-sha256\n";
  write_file
    (Filename.concat root "source-archives.lock")
    "# package|version|source|algorithm|checksum\n";
  write_file
    (Filename.concat
       root
       "packages/bonsai_swiftui_ios_sdk/bonsai_swiftui_ios_sdk.0.1.0~dev.3/opam")
    {|opam-version: "2.0"
synopsis: "Bonsai SwiftUI iPhoneOS SDK"
maintainer: "bonsai_swiftui contributors"
depends: [
  "ocaml-base-compiler" {= "5.1.1"}
]
|};
  write_file
    (Filename.concat root "repository.sexp")
    (repository_lock
       ~digest:(repository_digest root)
       ~source_digest:(Artifact.digest source_lock)
       ~package_digest:(Artifact.digest (Filename.concat root "package-universe.lock"))
       ~archive_digest:(Artifact.digest (Filename.concat root "source-archives.lock")))
;;

type toolchain_fixture =
  { toolchain_root : string
  ; toolchain_bin : string
  ; toolchain_prefix : string
  ; toolchain_log : string
  ; toolchain_manifest : string
  }

let create_toolchain_fixture () =
  let toolchain_root =
    Filename.temp_dir "bonsai-swiftui-tool" "toolchain" |> Unix.realpath
  in
  let toolchain_bin = Filename.concat toolchain_root "bin" in
  let toolchain_prefix = Filename.concat toolchain_root "switch-prefix" in
  let toolchain_log = Filename.concat toolchain_root "commands.log" in
  let toolchain_manifest =
    Filename.concat toolchain_prefix "share/bonsai_swiftui_ios_sdk/manifest.sexp"
  in
  [ "dune"; "ocamlc"; "ocamlfind" ]
  |> List.iter (fun program ->
    write_executable
      (Filename.concat toolchain_prefix ("bin/" ^ program))
      "#!/bin/sh\nexit 0\n");
  write_file toolchain_manifest valid_sdk_manifest;
  write_executable
    (Filename.concat toolchain_bin "opam")
    (command_logger "opam"
     ^ Printf.sprintf
         {|case " $* " in
  *" switch show --switch=bonsai-swiftui-ios "*)
    printf '%%s\n' 'bonsai-swiftui-ios' ;;
  *" var --switch=bonsai-swiftui-ios prefix "*)
    printf '%%s\n' '%s' ;;
  *" exec --switch=bonsai-swiftui-ios -- dune --version "*)
    printf '%%s\n' '3.18.2' ;;
  *" exec --switch=bonsai-swiftui-ios -- ocamlc -version "*)
    printf '%%s\n' '5.1.1' ;;
  *" exec --switch=bonsai-swiftui-ios -- ocamlfind -toolchain ios printconf path "*)
    printf '%%s\n' '%s/lib/ios' ;;
  *" switch remove --yes bonsai-swiftui-ios "*)
    exit "${REMOVE_EXIT:-0}" ;;
  *) exit 64 ;;
esac
|}
         toolchain_prefix
         toolchain_prefix);
  { toolchain_root; toolchain_bin; toolchain_prefix; toolchain_log; toolchain_manifest }
;;

let with_toolchain_fixture ?(environment = []) fixture f =
  with_environment
    ([ ( "PATH"
       , fixture.toolchain_bin ^ ":" ^ Option.value ~default:"" (Sys.getenv_opt "PATH") )
     ; "COMMAND_LOG", fixture.toolchain_log
     ]
     @ environment)
    f
;;

let test_toolchain_show_and_verify_are_read_only () =
  let fixture = create_toolchain_fixture () in
  let manifest_mtime = (Unix.stat fixture.toolchain_manifest).st_mtime in
  let info =
    with_toolchain_fixture fixture (fun () ->
      Toolchain.show ~working_directory:fixture.toolchain_root |> get_ok)
  in
  Alcotest.(check string) "fixed switch" "bonsai-swiftui-ios" info.switch;
  Alcotest.(check string) "switch prefix" fixture.toolchain_prefix info.prefix;
  Alcotest.(check string) "SDK version" "0.1.0~dev" info.bonsai_swiftui_version;
  Alcotest.(check string) "target" "iphoneos/arm64" info.target;
  let verified =
    with_toolchain_fixture fixture (fun () ->
      Toolchain.verify ~working_directory:fixture.toolchain_root |> get_ok)
  in
  Alcotest.(check string)
    "show and verify fingerprint"
    info.fingerprint
    verified.fingerprint;
  Alcotest.(check (float 0.))
    "manifest remains untouched"
    manifest_mtime
    (Unix.stat fixture.toolchain_manifest).st_mtime;
  let commands = read_file fixture.toolchain_log |> non_empty_lines in
  Alcotest.(check bool)
    "show and verify never mutate opam"
    false
    (List.exists
       (fun command ->
          contains command "\tinstall\t"
          || contains command "\tremove\t"
          || contains command "\tcreate\t")
       commands)
;;

let test_toolchain_remove_uses_only_fixed_switch () =
  let fixture = create_toolchain_fixture () in
  with_toolchain_fixture fixture (fun () ->
    Toolchain.remove ~working_directory:fixture.toolchain_root |> get_ok);
  Alcotest.(check (list string))
    "fixed destructive command"
    [ String.concat
        "\t"
        [ "opam"
        ; fixture.toolchain_root
        ; "switch"
        ; "remove"
        ; "--yes"
        ; "bonsai-swiftui-ios"
        ]
    ]
    (read_file fixture.toolchain_log |> non_empty_lines);
  write_file fixture.toolchain_log "";
  with_toolchain_fixture
    ~environment:[ "REMOVE_EXIT", "31" ]
    fixture
    (fun () ->
       Toolchain.remove ~working_directory:fixture.toolchain_root
       |> check_error_contains "opam exited with status 31")
;;

let test_toolchain_install_uses_locked_repository_and_exact_sdk () =
  let fixture = create_toolchain_fixture () in
  let framework_root = Filename.concat fixture.toolchain_root "framework" in
  let repository = Filename.concat framework_root "tool/ios/opam-repository/0.1.0" in
  write_repository_fixture repository;
  write_file fixture.toolchain_log "";
  write_executable
    (Filename.concat fixture.toolchain_bin "opam")
    (command_logger "opam"
     ^ {|case " $* " in
  *" switch list --short "*)
    test -z "${SWITCH_EXISTS:-}" || printf '%s\n' 'bonsai-swiftui-ios' ;;
  *" switch create bonsai-swiftui-ios "*) exit 0 ;;
  *" install --switch=bonsai-swiftui-ios --yes bonsai_swiftui_ios_sdk.0.1.0~dev.3 "*)
    exit "${INSTALL_EXIT:-0}" ;;
  *) exit 64 ;;
esac
|}
    );
  with_toolchain_fixture fixture (fun () ->
    Toolchain.install ~framework_root ~working_directory:fixture.toolchain_root |> get_ok);
  let commands = read_file fixture.toolchain_log |> non_empty_lines in
  Alcotest.(check int) "one check, create, and install" 3 (List.length commands);
  let create = List.nth commands 1 in
  let repository_name =
    "bonsai-swiftui-ios-" ^ String.sub (repository_digest repository) 0 12
  in
  Alcotest.(check bool)
    "fixed switch creation"
    true
    (contains create "switch\tcreate\tbonsai-swiftui-ios\tocaml-base-compiler.5.1.1");
  Alcotest.(check bool)
    "snapshot-qualified local repository"
    true
    (contains create (repository_name ^ "=file://" ^ repository));
  Alcotest.(check bool)
    "locked default repository commit"
    true
    (contains
       create
       "bonsai-swiftui-default=git+https://github.com/RCmerci/opam-repository.git#c98b21e24c088665ccae4c3b53eadadd3b755b15");
  Alcotest.(check bool)
    "locked cross repository commit"
    true
    (contains
       create
       "bonsai-swiftui-ios-cross=git+https://github.com/ocaml-cross/opam-cross-ios.git#8380b52b0154752c26c6e221c04fbced3320aa48");
  Alcotest.(check bool)
    "exact SDK meta-package install"
    true
    (contains (List.nth commands 2) "bonsai_swiftui_ios_sdk.0.1.0~dev.3");
  Alcotest.(check bool)
    "non-interactive depext handling"
    true
    (contains (List.nth commands 2) "--assume-depexts")
;;

let test_toolchain_install_rejects_existing_switch_and_tampered_repository () =
  let fixture = create_toolchain_fixture () in
  let framework_root = Filename.concat fixture.toolchain_root "framework" in
  let repository = Filename.concat framework_root "tool/ios/opam-repository/0.1.0" in
  write_repository_fixture repository;
  write_file fixture.toolchain_log "";
  write_executable
    (Filename.concat fixture.toolchain_bin "opam")
    (command_logger "opam"
     ^ {|if test "$1" = switch && test "$2" = list; then
  test -z "${SWITCH_EXISTS:-}" || printf '%s\n' 'bonsai-swiftui-ios'
  exit 0
fi
exit 64
|}
    );
  with_toolchain_fixture
    ~environment:[ "SWITCH_EXISTS", "true" ]
    fixture
    (fun () ->
       Toolchain.install ~framework_root ~working_directory:fixture.toolchain_root
       |> check_error_contains "already exists");
  Alcotest.(check int)
    "existing switch stops after read-only check"
    1
    (read_file fixture.toolchain_log |> non_empty_lines |> List.length);
  write_file fixture.toolchain_log "";
  write_file (Filename.concat repository "repo") "opam-version: \"2.1\"\n";
  with_toolchain_fixture fixture (fun () ->
    Toolchain.install ~framework_root ~working_directory:fixture.toolchain_root
    |> check_error_contains "repository snapshot digest");
  Alcotest.(check string)
    "tampered repository stops before opam"
    ""
    (read_file fixture.toolchain_log);
  write_repository_fixture repository;
  write_file
    (Filename.concat repository "package-universe.lock")
    "tampered package lock\n";
  with_toolchain_fixture fixture (fun () ->
    Toolchain.install ~framework_root ~working_directory:fixture.toolchain_root
    |> check_error_contains "package universe digest");
  Alcotest.(check string)
    "tampered package universe stops before opam"
    ""
    (read_file fixture.toolchain_log);
  write_repository_fixture repository;
  write_file (Filename.concat repository "source-archives.lock") "tampered archives\n";
  with_toolchain_fixture fixture (fun () ->
    Toolchain.install ~framework_root ~working_directory:fixture.toolchain_root
    |> check_error_contains "source archive digest");
  Alcotest.(check string)
    "tampered source archives stop before opam"
    ""
    (read_file fixture.toolchain_log);
  write_repository_fixture repository;
  let source_lock =
    Filename.concat framework_root "vendor/opam-ios/runtime-closure.lock"
  in
  write_file source_lock "tampered source lock\n";
  with_toolchain_fixture fixture (fun () ->
    Toolchain.install ~framework_root ~working_directory:fixture.toolchain_root
    |> check_error_contains "source lock digest");
  Alcotest.(check string)
    "tampered source lock stops before opam"
    ""
    (read_file fixture.toolchain_log)
;;

let test_feature_validation () =
  let core = [ Config.Feature.Core ] in
  let network = [ Config.Feature.Core; Config.Feature.Network ] in
  let sqlite = [ Config.Feature.Core; Config.Feature.Sqlite ] in
  Feature.validate_packages
    ~target:Plan.Iphoneos
    ~features:network
    [ "tls"; "httpun-eio" ]
  |> get_ok
  |> ignore;
  Feature.validate_packages ~target:Plan.Iphoneos ~features:core [ "tls" ]
  |> check_error_contains "requires the network feature";
  Feature.validate_packages ~target:Plan.Iphoneos ~features:network [ "openssl" ]
  |> check_error_contains "prohibited TLS backend";
  Feature.validate_packages
    ~target:Plan.Iphoneos
    ~features:core
    [ "mirage-crypto-rng.unix" ]
  |> check_error_contains "requires the network feature for entropy";
  Feature.validate_packages ~target:Plan.Iphoneos ~features:core [ "eio_posix" ]
  |> get_ok
  |> ignore;
  Feature.validate_packages
    ~target:Plan.Iphoneos
    ~features:core
    [ "datascript-ocaml-native.sqlite" ]
  |> get_ok
  |> ignore;
  Feature.validate_packages ~target:Plan.Iphoneos ~features:sqlite [ "sqlite3" ]
  |> get_ok
  |> ignore;
  Feature.validate_packages ~target:Plan.Iphoneos ~features:core [ "sqlite3" ]
  |> check_error_contains "requires the sqlite feature";
  Feature.validate_packages
    ~target:Plan.Iphoneos
    ~features:core
    [ "astring"; "bigstringaf"; "cstruct"; "ptime" ]
  |> get_ok
  |> ignore
;;

let test_cache_keys () =
  let config = Config.parse_string valid_config |> get_ok in
  let key = Cache.application_key ~config ~target:Plan.Iphoneos ~profile:Plan.Release in
  let repeated =
    Cache.application_key ~config ~target:Plan.Iphoneos ~profile:Plan.Release
  in
  let macos = Cache.application_key ~config ~target:Plan.Macos ~profile:Plan.Release in
  Alcotest.(check string) "deterministic" key repeated;
  Alcotest.(check bool) "target-sensitive" false (String.equal key macos);
  Alcotest.(check int) "SHA-256 hex length" 64 (String.length key)
;;

let test_scaffold_preserves_user_source () =
  let root = Filename.temp_dir "bonsai-swiftui-tool" "preserve" in
  let app_dir = Filename.concat root "app" in
  Unix.mkdir app_dir 0o755;
  let app_ml = Filename.concat app_dir "application.ml" in
  let channel = open_out app_ml in
  output_string channel "let user_owned = true\n";
  close_out channel;
  let config = Config.parse_string valid_config |> get_ok in
  Scaffold.initialize ~project_root:root ~config |> get_ok;
  let channel = open_in app_ml in
  let preserved = input_line channel in
  close_in channel;
  Alcotest.(check string) "existing app source" "let user_owned = true" preserved;
  Alcotest.(check bool)
    "missing native embed created"
    true
    (Sys.file_exists (Filename.concat app_dir "native_embed.ml"));
  let source_path = Filename.concat root "swift/App.swift" in
  Alcotest.(check bool) "Swift App source is generated" true (Sys.file_exists source_path);
  let application_owned = "// Application-owned Swift source\n" in
  write_file source_path application_owned;
  Scaffold.initialize ~project_root:root ~config |> get_ok;
  Alcotest.(check string)
    "Swift source is preserved"
    application_owned
    (read_file source_path)
;;

let test_scaffold_adopts_existing_layout_without_default_app () =
  let root = Filename.temp_dir "bonsai-swiftui-tool" "adopt-layout" in
  write_file (Filename.concat root "ocaml/native_embed.ml") "let () = ()\n";
  write_file
    (Filename.concat root "ocaml/dune")
    "(executable (name native_embed) (modules native_embed) (modes (native object)))\n";
  write_file (Filename.concat root "swift/App.swift") "// Application-owned Swift App\n";
  let custom_config =
    replace_once
      valid_config
      ~pattern:"app/native_embed.exe.o"
      ~replacement:"ocaml/native_embed.exe.o"
  in
  let config = Config.parse_string custom_config |> get_ok in
  Scaffold.adopt_workspace ~project_root:root ~config_text:custom_config ~config |> get_ok;
  Alcotest.(check bool)
    "default app directory is absent"
    false
    (Sys.file_exists (Filename.concat root "app"));
  Alcotest.(check bool)
    "consumer OCaml entrypoint is preserved"
    true
    (Sys.file_exists (Filename.concat root "ocaml/native_embed.ml"))
;;

let test_scaffold_adoption_rejects_conflicting_config () =
  let root = Filename.temp_dir "bonsai-swiftui-tool" "adopt-conflict" in
  write_file (Filename.concat root "bonsai-swiftui.sexp") valid_config;
  write_file (Filename.concat root "ocaml/dune") "(executable (name native_embed))\n";
  let custom_config =
    replace_once
      valid_config
      ~pattern:"app/native_embed.exe.o"
      ~replacement:"ocaml/native_embed.exe.o"
  in
  let config = Config.parse_string custom_config |> get_ok in
  Scaffold.adopt_workspace ~project_root:root ~config_text:custom_config ~config
  |> check_error_contains "bonsai-swiftui.sexp conflicts"
;;

let test_scaffold_generates_and_preserves_application_lock () =
  let root = Filename.temp_dir "bonsai-swiftui-tool" "application-lock" in
  let config = Config.parse_string valid_config |> get_ok in
  Scaffold.initialize_workspace ~project_root:root ~config_text:valid_config ~config
  |> get_ok;
  let lock = Filename.concat root "journal.opam.locked" in
  Alcotest.(check bool) "application lock exists" true (Sys.file_exists lock);
  let contents = read_file lock in
  [ "\"base\" {= \"v0.17.3\"}"
  ; "\"bonsai\" {= \"v0.17.0\"}"
  ; "\"bonsai_swiftui\" {= \"0.1.0~dev\"}"
  ; "\"incr_dom\" {= \"v0.17.0\"}"
  ; "\"ocaml-ios64\" {= \"5.1.1\"}"
  ; "\"virtual_dom\" {= \"v0.17.0\"}"
  ]
  |> List.iter (fun dependency ->
    Alcotest.(check bool) dependency true (contains contents dependency));
  let application_owned = "application-owned lock\n" in
  write_file lock application_owned;
  Scaffold.initialize_workspace ~project_root:root ~config_text:valid_config ~config
  |> get_ok;
  Alcotest.(check string) "existing application lock" application_owned (read_file lock)
;;

let test_scaffold_preserves_native_dune () =
  let root = Filename.temp_dir "bonsai-swiftui-tool" "native-dune" in
  let config = Config.parse_string valid_config |> get_ok in
  Scaffold.initialize ~project_root:root ~config |> get_ok;
  let path = Filename.concat root "app/dune" in
  let dune = read_file path in
  Alcotest.(check bool)
    "complete object executable"
    true
    (contains dune "(name native_embed)");
  List.iter
    (fun obsolete ->
       Alcotest.(check bool) ("removed " ^ obsolete) false (contains dune obsolete))
    [ "(alias"; "EMBED_OCAML" ];
  let owned = "(executable (name user_owned) (modules user_owned))\n" in
  write_file path owned;
  Scaffold.initialize ~project_root:root ~config |> get_ok;
  Alcotest.(check string) "existing Dune is never rewritten" owned (read_file path)
;;

let test_project_root_discovery () =
  let root = Filename.temp_dir "bonsai-swiftui-tool" "root" in
  let config_path = Filename.concat root "bonsai-swiftui.sexp" in
  let channel = open_out config_path in
  output_string channel valid_config;
  close_out channel;
  let nested = Filename.concat root "one/two" in
  Scaffold.ensure_directory nested;
  Alcotest.(check (result string string))
    "walks to configuration"
    (Ok (Unix.realpath root))
    (Project.find_root nested)
;;

let test_project_lock_serializes_processes () =
  let root = Filename.temp_dir "bonsai-swiftui-tool" "lock" in
  let lock_path = Filename.concat root "_build/bonsai-swiftui/locks/test.lock" in
  let read_end, write_end = Unix.pipe () in
  let child = ref None in
  Lock.with_lock lock_path (fun () ->
    match Unix.fork () with
    | 0 ->
      Unix.close read_end;
      let status =
        match
          Lock.with_lock lock_path (fun () ->
            ignore (Unix.write_substring write_end "1" 0 1);
            Ok ())
        with
        | Ok () -> 0
        | Error _ -> 1
      in
      Unix.close write_end;
      Unix._exit status
    | pid ->
      child := Some pid;
      Unix.close write_end;
      let ready, _, _ = Unix.select [ read_end ] [] [] 0.2 in
      Alcotest.(check int) "child waits while locked" 0 (List.length ready);
      Ok ())
  |> get_ok;
  let ready, _, _ = Unix.select [ read_end ] [] [] 2.0 in
  Alcotest.(check int) "child acquires after release" 1 (List.length ready);
  let byte = Bytes.create 1 in
  Alcotest.(check int) "child notification" 1 (Unix.read read_end byte 0 1);
  Unix.close read_end;
  (match !child with
   | None -> Alcotest.fail "child process was not created"
   | Some pid ->
     let _, status = Unix.waitpid [] pid in
     Alcotest.(check int)
       "child exit"
       0
       (match status with
        | Unix.WEXITED code -> code
        | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> 1));
  Alcotest.(check bool) "project-local lock file" true (Sys.file_exists lock_path)
;;

let test_clean_removes_only_selected_platform () =
  let project_root = Filename.temp_dir "bonsai-swiftui-tool" "clean-platform" in
  let build_root = Filename.concat project_root "_build/bonsai-swiftui" in
  let files =
    [ "dune/macos/host/debug/object", "macos"
    ; "artifacts/macos/arm64/debug/native_embed.exe.o", "macos"
    ; "state/macos/debug/build-manifest.sexp", "macos"
    ; "logs/macos/debug.log", "macos"
    ; "locks/macos/debug.lock", "macos"
    ; "dune/iphoneos/sdk/release/object", "iphoneos"
    ; "artifacts/ios/iphoneos/arm64/release/native_embed.exe.o", "iphoneos"
    ; "state/iphoneos/release/build-manifest.sexp", "iphoneos"
    ; "logs/iphoneos/release.log", "iphoneos"
    ; "locks/iphoneos/release.lock", "iphoneos"
    ; "dependencies/probes/macos/debug/DerivedData/object", "macos"
    ; "dependencies/validation/macos/debug.json", "macos"
    ; "dependencies/probes/ios/release/DerivedData/object", "iphoneos"
    ; "dependencies/validation/ios/release.json", "iphoneos"
    ; "dependencies/packages/checkouts/package/source", "shared"
    ; "unrelated/keep", "unrelated"
    ]
  in
  List.iter
    (fun (path, contents) -> write_file (Filename.concat build_root path) contents)
    files;
  Clean.run ~project_root ~config:(Config.parse_string valid_config |> get_ok) Clean.Macos
  |> get_ok;
  files
  |> List.iter (fun (path, platform) ->
    Alcotest.(check bool)
      path
      (platform <> "macos")
      (Sys.file_exists (Filename.concat build_root path)));
  Clean.run ~project_root ~config:(Config.parse_string valid_config |> get_ok) Clean.Macos
  |> get_ok
;;

let test_clean_all_does_not_follow_symlinks () =
  let root = Filename.temp_dir "bonsai-swiftui-tool" "clean-symlink" in
  let project_root = Filename.concat root "project" in
  let build_root = Filename.concat project_root "_build/bonsai-swiftui" in
  let external_root = Filename.concat root "global-switch" in
  let external_sentinel = Filename.concat external_root "manifest.sexp" in
  write_file external_sentinel "immutable global state";
  write_file (Filename.concat build_root "state/macos/debug/build-manifest.sexp") "state";
  Unix.symlink external_root (Filename.concat build_root "linked-global-state");
  Clean.run ~project_root ~config:(Config.parse_string valid_config |> get_ok) Clean.All
  |> get_ok;
  Alcotest.(check bool) "project build root removed" false (Sys.file_exists build_root);
  Alcotest.(check string)
    "symlink target remains untouched"
    "immutable global state"
    (read_file external_sentinel);
  Clean.run ~project_root ~config:(Config.parse_string valid_config |> get_ok) Clean.All
  |> get_ok
;;

type native_build_fixture =
  { native_project_root : string
  ; native_framework_root : string
  ; native_switch_prefix : string
  ; native_bin : string
  ; native_command_log : string
  ; native_config : Config.t
  ; native_alias_path : string
  }

let rec file_snapshot root path =
  let absolute = Filename.concat root path in
  if Sys.is_directory absolute
  then
    Sys.readdir absolute
    |> Array.to_list
    |> List.sort String.compare
    |> List.concat_map (fun name ->
      file_snapshot root (if path = "" then name else Filename.concat path name))
  else [ path, Digest.file absolute ]
;;

let create_native_build_fixture () =
  let native_root =
    Filename.temp_dir "bonsai-swiftui-tool" "native-build" |> Unix.realpath
  in
  let native_project_root = Filename.concat native_root "project" in
  let native_framework_root = Filename.concat native_root "installed-tool-assets" in
  let native_switch_prefix = Filename.concat native_root "global-switch-prefix" in
  let native_bin = Filename.concat native_root "bin" in
  let native_command_log =
    Filename.concat native_project_root "_build/bonsai-swiftui/logs/test-commands.log"
  in
  Scaffold.ensure_directory (Filename.dirname native_command_log);
  let native_config = Config.parse_string valid_config |> get_ok in
  let native_alias_path = Filename.concat native_project_root "app/dune" in
  write_file
    native_alias_path
    {|(executable
 (name native_embed)
 (modules native_embed)
 (modes (native object)))
|};
  write_file
    (Filename.concat native_project_root "journal.opam.locked")
    {|opam-version: "2.0"
name: "journal"
version: "0.1.0"
depends: [
  "base" {= "v0.17.0"}
  "bonsai_swiftui" {= "0.1.0~dev"}
]
|};
  [ "dune"; "ocamlc"; "ocamlfind" ]
  |> List.iter (fun program ->
    write_executable
      (Filename.concat native_switch_prefix ("bin/" ^ program))
      "#!/bin/sh\nexit 0\n");
  write_file
    (Filename.concat native_switch_prefix "share/bonsai_swiftui_ios_sdk/manifest.sexp")
    valid_sdk_manifest;
  write_executable
    (Filename.concat native_framework_root "tool/ios/verify_complete_object.sh")
    (command_logger "verify_complete_object"
     ^ {|exit "${VERIFY_EXIT:-0}"
|}
    );
  write_executable
    (Filename.concat native_bin "xcrun")
    (command_logger "xcrun"
     ^ {|case "$*" in
  *"macosx --show-sdk-path"*) printf '%s\n' '/Xcode/MacOSX.sdk' ;;
  *"iphoneos --show-sdk-path"*) printf '%s\n' '/Xcode/iPhoneOS.sdk' ;;
  *"iphoneos --show-sdk-version"*) printf '%s\n' '26.0' ;;
  *"iphoneos clang -r "*) shift 2; exec "$@" ;;
  *) exit 64 ;;
esac
|}
    );
  write_executable
    (Filename.concat native_bin "opam")
    (command_logger "opam"
     ^ Printf.sprintf
         {|case " $* " in
  *" switch show --switch=bonsai-swiftui-ios "*)
    printf '%%s\n' 'bonsai-swiftui-ios' ;;
  *" var --switch=bonsai-swiftui-ios prefix "*)
    printf '%%s\n' '%s' ;;
  *" exec --switch=bonsai-swiftui-ios -- dune --version "*|*" exec -- dune --version "*)
    printf '%%s\n' '3.18.2' ;;
  *" exec --switch=bonsai-swiftui-ios -- dune describe external-lib-deps "*)
    build_directory=''
    for argument in "$@"; do
      case "$argument" in
        --build-dir=*) build_directory="${argument#--build-dir=}" ;;
      esac
    done
    test -n "$build_directory"
    test -d "$(dirname "$build_directory")"
    printf '%%s\n' '(11:default.ios((11:executables((5:names(12:native_embed))(10:extensions(6:.exe.o))(7:package())(10:source_dir3:app)(13:external_deps((4:base8:required)(17:bonsai_swiftui.ui8:required)))(13:internal_deps())))))' ;;
  *" exec --switch=bonsai-swiftui-ios -- ocamlc -version "*|*" exec -- ocamlc -version "*)
    printf '%%s\n' '5.1.1' ;;
  *" exec --switch=bonsai-swiftui-ios -- ocamlfind -toolchain ios printconf path "*)
    printf '%%s\n' '%s/lib/ios' ;;
  *" exec -- ocamlfind query -format %%v bonsai_swiftui "*)
    printf '%%s\n' '0.1.0~dev' ;;
  *" dune build "*)
    build_directory=''
    context='default'
    for argument in "$@"; do
      case "$argument" in
        --build-dir=*) build_directory="${argument#--build-dir=}" ;;
        ios) context='default.ios' ;;
      esac
    done
    test -n "$build_directory"
    object="$build_directory/$context/app/native_embed.exe.o"
    mkdir -p "$(dirname "$object")"
    if test ! -f "$object" || test "${REWRITE_OBJECT:-false}" = true; then
      printf '%%s' "${OBJECT_CONTENT:-complete-object}" > "$object"
    fi ;;
  *) exit 64 ;;
esac
|}
         native_switch_prefix
         native_switch_prefix);
  let gmp_directory = Filename.concat native_root "static-gmp" in
  write_file (Filename.concat gmp_directory "libgmp.a") "static-gmp";
  write_executable
    (Filename.concat native_bin "pkg-config")
    (command_logger "pkg-config" ^ Printf.sprintf "printf '%%s\\n' '%s'\n" gmp_directory);
  write_executable
    (Filename.concat native_bin "clang")
    (command_logger "clang"
     ^ {|source=''
output=''
previous=''
for argument in "$@"; do
  if test "$previous" = -o; then output=$argument; fi
  case "$argument" in
    *.exe.o) if test -z "$source"; then source=$argument; fi ;;
  esac
  previous=$argument
done
test -n "$source"
test -n "$output"
cp "$source" "$output"
|}
    );
  write_executable (Filename.concat native_bin "nm") (command_logger "nm" ^ "exit 0\n");
  { native_project_root
  ; native_framework_root
  ; native_switch_prefix
  ; native_bin
  ; native_command_log
  ; native_config
  ; native_alias_path
  }
;;

let with_native_build_fixture ?(environment = []) fixture f =
  with_environment
    ([ "PATH", fixture.native_bin ^ ":" ^ Option.value ~default:"" (Sys.getenv_opt "PATH")
     ; "COMMAND_LOG", fixture.native_command_log
     ]
     @ environment)
    f
;;

let run_native_build fixture target profile =
  Build_system.build_native
    ~framework_root:fixture.native_framework_root
    ~project_root:fixture.native_project_root
    ~config:fixture.native_config
    ~target
    ~profile
;;

let test_native_builds_use_project_local_dune_workspaces () =
  [ Plan.Macos, Plan.Debug; Plan.Iphoneos, Plan.Release ]
  |> List.iter (fun (target, profile) ->
    let fixture = create_native_build_fixture () in
    let installed_tool_before = file_snapshot fixture.native_framework_root "" in
    let global_switch_before = file_snapshot fixture.native_switch_prefix "" in
    let alias_before = read_file fixture.native_alias_path in
    let artifact =
      with_native_build_fixture fixture (fun () ->
        run_native_build fixture target profile |> get_ok)
    in
    Alcotest.(check bool)
      "staged artifact is project-local"
      true
      (String.starts_with
         ~prefix:(fixture.native_project_root ^ "/_build/bonsai-swiftui/artifacts/")
         artifact);
    Alcotest.(check string) "staged content" "complete-object" (read_file artifact);
    Alcotest.(check string)
      "normal build does not synchronize Dune files"
      alias_before
      (read_file fixture.native_alias_path);
    Alcotest.(check bool)
      "installed tool assets are read-only inputs"
      true
      (installed_tool_before = file_snapshot fixture.native_framework_root "");
    Alcotest.(check bool)
      "global switch is a read-only input"
      true
      (global_switch_before = file_snapshot fixture.native_switch_prefix "");
    let commands = read_file fixture.native_command_log |> non_empty_lines in
    let dune_builds =
      List.filter (fun command -> contains command "\tdune\tbuild\t") commands
    in
    Alcotest.(check int) "exactly one Dune build" 1 (List.length dune_builds);
    (match target with
     | Plan.Macos -> ()
     | Plan.Iphoneos ->
       let closure_queries =
         List.filter
           (fun command -> contains command "\tdune\tdescribe\texternal-lib-deps\t")
           commands
       in
       Alcotest.(check int) "one reachable closure query" 1 (List.length closure_queries);
       let closure_query = List.hd closure_queries in
       Alcotest.(check bool)
         "iOS closure context"
         true
         (contains closure_query "--context=default.ios"
          && contains closure_query "\t-x\tios"
          && contains closure_query ("--root=" ^ fixture.native_project_root)
          && contains
               closure_query
               (fixture.native_project_root ^ "/_build/bonsai-swiftui/dune/iphoneos/")));
    let dune_build = List.hd dune_builds in
    Alcotest.(check bool)
      "application is the Dune root"
      true
      (contains dune_build ("--root=" ^ fixture.native_project_root));
    Alcotest.(check bool)
      "physical build directory is project-local"
      true
      (contains
         dune_build
         ("--build-dir=" ^ fixture.native_project_root ^ "/_build/bonsai-swiftui/dune/"));
    Alcotest.(check bool)
      "removed shared workspace paths are absent"
      false
      (contains dune_build "external_apps"
       || contains dune_build "sdk-cache"
       || contains dune_build fixture.native_framework_root))
;;

let test_iphoneos_build_requires_committed_application_lock () =
  let fixture = create_native_build_fixture () in
  Sys.remove (Filename.concat fixture.native_project_root "journal.opam.locked");
  with_native_build_fixture fixture (fun () ->
    run_native_build fixture Plan.Iphoneos Plan.Release
    |> check_error_contains "Application opam lock is missing");
  let commands = read_file fixture.native_command_log |> non_empty_lines in
  Alcotest.(check bool)
    "closure is resolved before subset validation"
    true
    (List.exists
       (fun command -> contains command "\tdune\tdescribe\texternal-lib-deps\t")
       commands);
  Alcotest.(check bool)
    "missing lock stops before Dune build"
    false
    (List.exists (fun command -> contains command "\tdune\tbuild\t") commands)
;;

let test_unchanged_native_build_preserves_outputs () =
  let fixture = create_native_build_fixture () in
  let artifact =
    with_native_build_fixture fixture (fun () ->
      run_native_build fixture Plan.Iphoneos Plan.Release |> get_ok)
  in
  let manifest =
    Filename.concat
      fixture.native_project_root
      "_build/bonsai-swiftui/state/iphoneos/release/build-manifest.sexp"
  in
  Alcotest.(check bool) "build manifest exists" true (Sys.file_exists manifest);
  Alcotest.(check bool)
    "manifest records artifact digest"
    true
    (contains (read_file manifest) "(artifact_digest ");
  Unix.utimes artifact 100.0 100.0;
  Unix.utimes manifest 100.0 100.0;
  with_native_build_fixture fixture (fun () ->
    run_native_build fixture Plan.Iphoneos Plan.Release |> get_ok |> ignore);
  Alcotest.(check (float 0.))
    "unchanged staged artifact is untouched"
    100.0
    (Unix.stat artifact).st_mtime;
  Alcotest.(check (float 0.))
    "unchanged build manifest is untouched"
    100.0
    (Unix.stat manifest).st_mtime
;;

let test_ios_app_bundle_paths () =
  let config = Config.parse_string valid_config |> get_ok in
  [ Plan.Debug, "Debug-iphoneos"
  ; Plan.Profile, "Profile-iphoneos"
  ; Plan.Release, "Release-iphoneos"
  ]
  |> List.iter (fun (profile, configuration) ->
    Alcotest.(check string)
      (Plan.profile_name profile)
      ("/work/journal/apple/DerivedData/Build/Products/"
       ^ configuration
       ^ "/BonsaiJournal.app")
      (Plan.ios_app_bundle ~project_root:"/work/journal" ~config ~profile))
;;

let test_ios_device_command_plans () =
  let config = Config.parse_string valid_config |> get_ok in
  let app_bundle =
    Plan.ios_app_bundle ~project_root:"/work/journal" ~config ~profile:Plan.Release
  in
  let bundle_identifier =
    Plan.ios_bundle_identifier ~project_root:"/work/journal" ~app_bundle
  in
  Alcotest.(check string) "bundle identifier program" "plutil" bundle_identifier.program;
  Alcotest.(check (list string))
    "bundle identifier arguments"
    [ "-extract"
    ; "CFBundleIdentifier"
    ; "raw"
    ; "-o"
    ; "-"
    ; Filename.concat app_bundle "Info.plist"
    ]
    bundle_identifier.arguments;
  let install =
    Plan.ios_device_install
      ~project_root:"/work/journal"
      ~device:"00008110-000A71C414BB801E"
      ~app_bundle
  in
  Alcotest.(check string) "install program" "xcrun" install.program;
  Alcotest.(check string) "install cwd" "/work/journal" install.working_directory;
  Alcotest.(check (list string))
    "install arguments"
    [ "devicectl"
    ; "device"
    ; "install"
    ; "app"
    ; "--device"
    ; "00008110-000A71C414BB801E"
    ; app_bundle
    ]
    install.arguments;
  let launch =
    Plan.ios_device_launch
      ~project_root:"/work/journal"
      ~device:"00008110-000A71C414BB801E"
      ~bundle_identifier:"com.example.journal"
  in
  Alcotest.(check string) "launch program" "xcrun" launch.program;
  Alcotest.(check (list string))
    "launch arguments"
    [ "devicectl"
    ; "device"
    ; "process"
    ; "launch"
    ; "--device"
    ; "00008110-000A71C414BB801E"
    ; "--terminate-existing"
    ; "com.example.journal"
    ]
    launch.arguments
;;

let test_artifact_layout () =
  let config = Config.parse_string valid_config |> get_ok in
  let build =
    Plan.native_build
      ~project_root:"/work/journal"
      ~config
      ~target:Plan.Iphoneos
      ~profile:Plan.Release
      ~toolchain_fingerprint:"sdk-fingerprint"
      ~apple_sdk_root:"/Xcode/iPhoneOS.sdk"
      ~apple_sdk_version:(Some "26.0")
    |> get_ok
  in
  Alcotest.(check string)
    "source follows custom Dune build directory"
    "/work/journal/_build/bonsai-swiftui/dune/iphoneos/sdk-fingerprint/release/default.ios/app/native_embed.exe.o"
    build.source_object;
  Alcotest.(check string)
    "staged artifact includes profile"
    "/work/journal/_build/bonsai-swiftui/artifacts/ios/iphoneos/arm64/release/native_embed.exe.o"
    build.staged_object
;;

let test_macos_artifact_staging_contract () =
  let fixture = create_native_build_fixture () in
  let destination =
    with_native_build_fixture fixture (fun () ->
      run_native_build fixture Plan.Macos Plan.Release |> get_ok)
  in
  let verifier_commands =
    read_file fixture.native_command_log
    |> non_empty_lines
    |> List.filter (fun command -> contains command "verify_complete_object")
  in
  Alcotest.(check bool)
    "verifier receives staged sibling and platform contract"
    true
    (List.exists
       (fun command ->
          contains command "\tMACOS\t26.0\tarm64"
          && not (contains command ("\t" ^ destination ^ "\t")))
       verifier_commands);
  with_native_build_fixture
    ~environment:
      [ "OBJECT_CONTENT", "rejected-complete-object"
      ; "REWRITE_OBJECT", "true"
      ; "VERIFY_EXIT", "9"
      ]
    fixture
    (fun () ->
       run_native_build fixture Plan.Macos Plan.Release
       |> check_error_contains "exited with status 9");
  Alcotest.(check string)
    "failed verification preserves previous artifact"
    "complete-object"
    (read_file destination);
  let siblings = Sys.readdir (Filename.dirname destination) |> Array.to_list in
  Alcotest.(check bool)
    "failed staging removes temporary sibling"
    false
    (List.exists
       (fun name -> String.starts_with ~prefix:".native_embed.exe.o.tmp" name)
       siblings)
;;

let test_macos_network_artifact_embeds_static_gmp () =
  let fixture = create_native_build_fixture () in
  let config =
    { fixture.native_config with
      features = [ Config.Feature.Core; Config.Feature.Network ]
    }
  in
  let gmp_directory = Filename.concat fixture.native_project_root "static-gmp" in
  let gmp_archive = Filename.concat gmp_directory "libgmp.a" in
  write_file gmp_archive "static-gmp";
  write_executable
    (Filename.concat fixture.native_bin "pkg-config")
    (command_logger "pkg-config" ^ Printf.sprintf "printf '%%s\\n' '%s'\n" gmp_directory);
  write_executable
    (Filename.concat fixture.native_bin "clang")
    (command_logger "clang"
     ^ {|output=''
previous=''
for argument in "$@"; do
  if test "$previous" = -o; then output=$argument; fi
  previous=$argument
done
test -n "$output"
printf '%s' 'complete-object-with-static-gmp' > "$output"
|}
    );
  write_executable
    (Filename.concat fixture.native_bin "nm")
    (command_logger "nm" ^ "exit 0\n");
  let destination =
    with_native_build_fixture fixture (fun () ->
      Build_system.build_native
        ~framework_root:fixture.native_framework_root
        ~project_root:fixture.native_project_root
        ~config
        ~target:Plan.Macos
        ~profile:Plan.Release
      |> get_ok)
  in
  Alcotest.(check string)
    "staged network object contains static GMP"
    "complete-object-with-static-gmp"
    (read_file destination);
  let commands = read_file fixture.native_command_log |> non_empty_lines in
  Alcotest.(check bool)
    "GMP archive is resolved with pkg-config"
    true
    (List.exists
       (fun command ->
          contains command "pkg-config" && contains command "\t--variable=libdir\tgmp")
       commands);
  Alcotest.(check bool)
    "network object is relocatably linked with static GMP"
    true
    (List.exists
       (fun command ->
          contains command "clang"
          && contains command "\t-r\t-target\tarm64-apple-macos26.0"
          && contains command gmp_archive)
       commands)
;;

let dune_description source =
  let length = String.length source in
  let buffer = Buffer.create length in
  let rec loop index =
    if index = length
    then Buffer.contents buffer
    else (
      match source.[index] with
      | ' ' | '\n' | '\r' | '\t' -> loop (index + 1)
      | ('(' | ')') as delimiter ->
        Buffer.add_char buffer delimiter;
        loop (index + 1)
      | _ ->
        let stop = ref index in
        while
          !stop < length
          && not (List.mem source.[!stop] [ ' '; '\n'; '\r'; '\t'; '('; ')' ])
        do
          incr stop
        done;
        let atom = String.sub source index (!stop - index) in
        Buffer.add_string buffer (string_of_int (String.length atom));
        Buffer.add_char buffer ':';
        Buffer.add_string buffer atom;
        loop !stop)
  in
  loop 0
;;

let resolve_dune_closure ?(target = "app/native_embed.exe.o") source =
  Dune_closure.resolve_csexp ~target (dune_description source)
;;

let check_dune_closure expected source =
  Alcotest.(check (result (list string) string))
    "external dependency closure"
    (Ok expected)
    (resolve_dune_closure source)
;;

let test_dune_closure_follows_local_app () =
  check_dune_closure
    [ "datascript-ocaml-native" ]
    {|
      (default
       ((library
         ((names (app))
          (extensions ())
          (package ())
          (source_dir app)
          (external_deps ((datascript-ocaml-native required)))
          (internal_deps ())))
        (executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ())
          (internal_deps ((app required)))))))
    |}
;;

let test_dune_closure_follows_arbitrary_local_library () =
  check_dune_closure
    [ "base" ]
    {|
      (default
       ((executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ())
          (internal_deps ((journal_core required)))))
        (library
         ((names (journal_core))
          (extensions ())
          (package ())
          (source_dir journal)
          (external_deps ((base required)))
          (internal_deps ())))))
    |}
;;

let test_dune_closure_excludes_local_component_roots () =
  check_dune_closure
    [ "datascript-ocaml-native.sqlite" ]
    {|
      (default
       ((library
         ((names (journal_core))
          (extensions ())
          (package ())
          (source_dir lib)
          (external_deps ((datascript-ocaml-native.sqlite required)))
          (internal_deps ())))
        (executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ((datascript-ocaml-native.sqlite required)))
          (internal_deps ((journal_core required)))))))
    |}
;;

let test_dune_closure_follows_transitive_local_chain () =
  check_dune_closure
    [ "uutf" ]
    {|
      (default
       ((library
         ((names (domain))
          (extensions ())
          (package ())
          (source_dir domain)
          (external_deps ((uutf required)))
          (internal_deps ())))
        (executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ())
          (internal_deps ((application required)))))
        (library
         ((names (application))
          (extensions ())
          (package ())
          (source_dir application)
          (external_deps ())
          (internal_deps ((domain required)))))))
    |}
;;

let test_dune_closure_ignores_unreachable_stanzas () =
  check_dune_closure
    [ "base" ]
    {|
      (default
       ((tests
         ((names (application_test))
          (extensions (.exe))
          (package ())
          (source_dir test)
          (external_deps ((alcotest required) (ppx_expect required)))
          (internal_deps ((application required)))))
        (executables
         ((names (benchmark))
          (extensions (.exe))
          (package ())
          (source_dir bench)
          (external_deps ((core_bench required)))
          (internal_deps ((application required)))))
        (library
         ((names (application))
          (extensions ())
          (package ())
          (source_dir app)
          (external_deps ((base required)))
          (internal_deps ())))
        (executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ())
          (internal_deps ((application required)))))))
    |}
;;

let test_dune_closure_combines_direct_and_indirect_external_dependencies () =
  check_dune_closure
    [ "bonsai_swiftui.driver"; "core"; "uucp" ]
    {|
      (default
       ((executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ((core required) (bonsai_swiftui.driver required)))
          (internal_deps ((application required)))))
        (library
         ((names (application))
          (extensions ())
          (package ())
          (source_dir app)
          (external_deps ((uucp required) (core required)))
          (internal_deps ())))))
    |}
;;

let test_dune_closure_keeps_ppx_only_stanzas_host_only () =
  check_dune_closure
    [ "base" ]
    {|
      (default
       ((tests
         ((names (ppx_test))
          (extensions (.exe))
          (package ())
          (source_dir test)
          (external_deps ((ppx_expect required)))
          (internal_deps ())))
        (executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ((base required)))
          (internal_deps ())))))
    |}
;;

let test_dune_closure_accepts_omitted_dependency_free_local_leaf () =
  check_dune_closure
    []
    {|
      (default
       ((executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ())
          (internal_deps ((dependency_free_leaf required)))))))
    |}
;;

let test_dune_closure_ignores_omitted_leaf_and_keeps_external_dependencies () =
  check_dune_closure
    [ "bonsai_swiftui.ui"; "uutf" ]
    {|
      (default
       ((executables
         ((names (native_embed))
          (extensions (.exe.o))
          (package ())
          (source_dir app)
          (external_deps ((bonsai_swiftui.ui required)))
          (internal_deps
           ((application required)
            (dependency_free_leaf required)))))
        (library
         ((names (application))
          (extensions ())
          (package ())
          (source_dir app)
          (external_deps ((uutf required)))
          (internal_deps ())))))
    |}
;;

let test_dune_closure_accepts_real_dune_omitted_local_leaf () =
  let project_root = Filename.temp_dir "bonsai-swiftui-tool" "dune-closure" in
  write_file (Filename.concat project_root "dune-project") "(lang dune 3.23)\n";
  write_file
    (Filename.concat project_root "dune")
    {|(library
 (name dependency_free_leaf)
 (modules dependency_free_leaf))

(executable
 (name native_embed)
 (modules native_embed)
 (libraries dependency_free_leaf))
|};
  write_file (Filename.concat project_root "dependency_free_leaf.ml") "";
  write_file (Filename.concat project_root "native_embed.ml") "";
  let description =
    Process_runner.capture
      ~working_directory:project_root
      ~environment:[]
      "dune"
      [ "describe"; "external-lib-deps"; "--format=csexp" ]
    |> get_ok
  in
  let dependency_name = "20:dependency_free_leaf" in
  Alcotest.(check int)
    "Dune reports only the internal dependency reference"
    1
    (count_occurrences description dependency_name);
  Alcotest.(check (result (list string) string))
    "real Dune external dependency closure"
    (Ok [])
    (Dune_closure.resolve_csexp ~target:"native_embed.exe" description)
;;

let test_dune_closure_accepts_selected_ios_context () =
  let description =
    dune_description
      {|
        (default.ios
         ((executables
           ((names (native_embed))
            (extensions (.exe.o))
            (package ())
            (source_dir app)
            (external_deps ((bonsai_swiftui.ui required)))
            (internal_deps ())))))
      |}
  in
  Alcotest.(check (result (list string) string))
    "iOS context dependency closure"
    (Ok [ "bonsai_swiftui.ui" ])
    (Dune_closure.resolve_csexp
       ~context:"default.ios"
       ~target:"app/native_embed.exe.o"
       description)
;;

let test_dune_closure_rejects_invalid_semantic_output () =
  let expected = Error "Malformed Dune external dependency description" in
  Alcotest.(check (result (list string) string))
    "malformed output"
    expected
    (Dune_closure.resolve_csexp ~target:"app/native_embed.exe.o" "(4:atom");
  let unsupported = dune_description "(future ())" in
  Alcotest.(check (result (list string) string))
    "unsupported output"
    (Error "Unsupported Dune external dependency description")
    (Dune_closure.resolve_csexp ~target:"app/native_embed.exe.o" unsupported)
;;

let test_dune_closure_output_is_deterministic () =
  let first =
    {|
      (default
       ((library
         ((names (application)) (extensions ()) (package ()) (source_dir app)
          (external_deps ((uutf required) (base required))) (internal_deps ())))
        (executables
         ((names (native_embed)) (extensions (.exe.o)) (package ()) (source_dir app)
          (external_deps ((core required)))
          (internal_deps ((application required)))))))
    |}
  in
  let second =
    {|
      (default
       ((executables
         ((internal_deps ((application required)))
          (external_deps ((core required))) (source_dir app) (package ())
          (extensions (.exe.o)) (names (native_embed))))
        (library
         ((internal_deps ()) (external_deps ((base required) (uutf required)))
          (source_dir app) (package ()) (extensions ()) (names (application))))))
    |}
  in
  Alcotest.(check (result (list string) string))
    "ordering independent"
    (resolve_dune_closure first)
    (resolve_dune_closure second);
  Alcotest.(check (result (list string) string))
    "canonical ordering"
    (Ok [ "base"; "core"; "uutf" ])
    (resolve_dune_closure first)
;;

let native_framework_files =
  [ "Package.swift"
  ; "native/src/module.modulemap"
  ; "native/src/bonsai_swiftui_native.h"
  ; "native/src/bonsai_swiftui_native.c"
  ; "native/src/bonsai_swiftui_ocaml_bridge.c"
  ; "swift/BonsaiSwiftUI/Sources/BonsaiApplicationView.swift"
  ; "tool/ios/toolchain.lock"
  ; "tool/ios/verify_complete_object.sh"
  ; "tool/swiftui_xcode_host.py"
  ]
;;

let native_framework_fixture () =
  let root = Filename.temp_dir "bonsai-swiftui-assets" "framework" in
  List.iter
    (fun path -> write_file (Filename.concat root path) "asset\n")
    native_framework_files;
  root
;;

let test_native_framework_discovery () =
  let root = native_framework_fixture () in
  Alcotest.(check bool)
    "native-only framework is usable"
    true
    (Assets.framework_marker root);
  with_environment
    [ "BONSAI_SWIFTUI_SOURCE_ROOT", root ]
    (fun () ->
       Alcotest.(check string)
         "explicit native source root"
         root
         (get_ok (Assets.find_framework_root ())));
  List.iter
    (fun path ->
       let path = Filename.concat root path in
       Sys.remove path;
       Alcotest.(check bool)
         "incomplete framework rejected"
         false
         (Assets.framework_marker root);
       Unix.mkdir path 0o755;
       Alcotest.(check bool)
         "directory cannot substitute for asset"
         false
         (Assets.framework_marker root);
       Unix.rmdir path;
       write_file path "asset\n")
    native_framework_files
;;

let test_invalid_native_framework_override () =
  List.iter
    (fun root ->
       with_environment
         [ "BONSAI_SWIFTUI_SOURCE_ROOT", root ]
         (fun () ->
            check_error_contains
              "BONSAI_SWIFTUI_SOURCE_ROOT is invalid"
              (Assets.find_framework_root ())))
    [ ""; Filename.temp_dir "bonsai-swiftui-assets" "empty" ]
;;

let () =
  Alcotest.run
    "bonsai_swiftui_tool"
    [ ( "core"
      , [ Alcotest.test_case
            "schema four host configuration"
            `Quick
            test_schema_four_host_configuration
        ; Alcotest.test_case "parse valid config" `Quick test_parse_valid_config
        ; Alcotest.test_case "application iOS minimum" `Quick test_application_ios_minimum
        ; Alcotest.test_case "invalid configs" `Quick test_invalid_configs
        ; Alcotest.test_case "command plans" `Quick test_command_plans
        ; Alcotest.test_case "fixed iphoneos switch" `Quick test_fixed_iphoneos_switch
        ; Alcotest.test_case "sdk manifest contract" `Quick test_sdk_manifest_contract
        ; Alcotest.test_case
            "sdk accepts framework source drift"
            `Quick
            test_sdk_accepts_framework_source_drift
        ; Alcotest.test_case
            "sdk accepts missing framework source identity"
            `Quick
            test_sdk_accepts_missing_framework_source_identity
        ; Alcotest.test_case
            "sdk validates only reachable application lock subset"
            `Quick
            test_sdk_validates_only_reachable_application_lock_subset
        ; Alcotest.test_case
            "sdk manifest fingerprint is canonical"
            `Quick
            test_sdk_manifest_fingerprint_is_canonical
        ; Alcotest.test_case
            "sdk preflight is read only"
            `Quick
            test_sdk_preflight_is_read_only
        ; Alcotest.test_case
            "sdk preflight reports missing switch"
            `Quick
            test_sdk_preflight_reports_missing_switch
        ; Alcotest.test_case
            "toolchain show and verify are read only"
            `Quick
            test_toolchain_show_and_verify_are_read_only
        ; Alcotest.test_case
            "toolchain remove uses only fixed switch"
            `Quick
            test_toolchain_remove_uses_only_fixed_switch
        ; Alcotest.test_case
            "toolchain install uses locked repository and exact sdk"
            `Quick
            test_toolchain_install_uses_locked_repository_and_exact_sdk
        ; Alcotest.test_case
            "toolchain install rejects existing switch and tampered repository"
            `Quick
            test_toolchain_install_rejects_existing_switch_and_tampered_repository
        ; Alcotest.test_case "feature validation" `Quick test_feature_validation
        ; Alcotest.test_case "cache keys" `Quick test_cache_keys
        ; Alcotest.test_case
            "scaffold preserves user source"
            `Quick
            test_scaffold_preserves_user_source
        ; Alcotest.test_case
            "scaffold adopts existing layout without default app"
            `Quick
            test_scaffold_adopts_existing_layout_without_default_app
        ; Alcotest.test_case
            "scaffold adoption rejects conflicting config"
            `Quick
            test_scaffold_adoption_rejects_conflicting_config
        ; Alcotest.test_case
            "scaffold generates and preserves application lock"
            `Quick
            test_scaffold_generates_and_preserves_application_lock
        ; Alcotest.test_case
            "scaffold preserves native dune"
            `Quick
            test_scaffold_preserves_native_dune
        ; Alcotest.test_case "project root discovery" `Quick test_project_root_discovery
        ; Alcotest.test_case
            "project lock serializes processes"
            `Quick
            test_project_lock_serializes_processes
        ; Alcotest.test_case
            "clean removes only selected platform"
            `Quick
            test_clean_removes_only_selected_platform
        ; Alcotest.test_case
            "clean all does not follow symlinks"
            `Quick
            test_clean_all_does_not_follow_symlinks
        ; Alcotest.test_case
            "native builds use project local dune workspaces"
            `Quick
            test_native_builds_use_project_local_dune_workspaces
        ; Alcotest.test_case
            "iphoneos build requires committed application lock"
            `Quick
            test_iphoneos_build_requires_committed_application_lock
        ; Alcotest.test_case
            "unchanged native build preserves outputs"
            `Quick
            test_unchanged_native_build_preserves_outputs
        ; Alcotest.test_case "ios app bundle paths" `Quick test_ios_app_bundle_paths
        ; Alcotest.test_case
            "ios device command plans"
            `Quick
            test_ios_device_command_plans
        ; Alcotest.test_case "artifact layout" `Quick test_artifact_layout
        ; Alcotest.test_case
            "macos artifact staging contract"
            `Quick
            test_macos_artifact_staging_contract
        ; Alcotest.test_case
            "macos network artifact embeds static gmp"
            `Quick
            test_macos_network_artifact_embeds_static_gmp
        ; Alcotest.test_case
            "dune closure follows local app"
            `Quick
            test_dune_closure_follows_local_app
        ; Alcotest.test_case
            "dune closure follows arbitrary local library"
            `Quick
            test_dune_closure_follows_arbitrary_local_library
        ; Alcotest.test_case
            "dune closure excludes local component roots"
            `Quick
            test_dune_closure_excludes_local_component_roots
        ; Alcotest.test_case
            "dune closure follows transitive local chain"
            `Quick
            test_dune_closure_follows_transitive_local_chain
        ; Alcotest.test_case
            "dune closure ignores unreachable stanzas"
            `Quick
            test_dune_closure_ignores_unreachable_stanzas
        ; Alcotest.test_case
            "dune closure combines direct and indirect external dependencies"
            `Quick
            test_dune_closure_combines_direct_and_indirect_external_dependencies
        ; Alcotest.test_case
            "dune closure keeps ppx only stanzas host only"
            `Quick
            test_dune_closure_keeps_ppx_only_stanzas_host_only
        ; Alcotest.test_case
            "dune closure accepts omitted dependency free local leaf"
            `Quick
            test_dune_closure_accepts_omitted_dependency_free_local_leaf
        ; Alcotest.test_case
            "dune closure ignores omitted leaf and keeps external dependencies"
            `Quick
            test_dune_closure_ignores_omitted_leaf_and_keeps_external_dependencies
        ; Alcotest.test_case
            "dune closure accepts real dune omitted local leaf"
            `Quick
            test_dune_closure_accepts_real_dune_omitted_local_leaf
        ; Alcotest.test_case
            "dune closure accepts selected ios context"
            `Quick
            test_dune_closure_accepts_selected_ios_context
        ; Alcotest.test_case
            "dune closure rejects invalid semantic output"
            `Quick
            test_dune_closure_rejects_invalid_semantic_output
        ; Alcotest.test_case
            "dune closure output is deterministic"
            `Quick
            test_dune_closure_output_is_deterministic
        ; Alcotest.test_case
            "native framework discovery"
            `Quick
            test_native_framework_discovery
        ; Alcotest.test_case
            "invalid native framework override"
            `Quick
            test_invalid_native_framework_override
        ] )
    ]
;;
