open Bonsai_swiftui_tool

let get_ok = function
  | Ok value -> value
  | Error message -> Alcotest.fail message
;;

let config native_target : Config.t =
  { name = "native_plan"
  ; apple_root = "apple"
  ; swift_packages = []
  ; native_target
  ; features = [ Config.Feature.Core ]
  ; macos =
      { bundle_identifier = "org.example.native-plan"
      ; entitlements = []
      ; minimum_version = "26.0"
      ; architectures = [ "arm64" ]
      }
  ; ios =
      { bundle_identifier = "org.example.native-plan.ios"
      ; entitlements = []
      ; minimum_version = "18.0"
      ; architectures = [ "arm64" ]
      }
  }
;;

let write path contents =
  Scaffold.ensure_directory (Filename.dirname path);
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out channel)
    (fun () -> output_string channel contents)
;;

let read path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel))
;;

let with_project f =
  let root = Filename.temp_dir "bonsai swiftui native " "project" |> Unix.realpath in
  Fun.protect
    ~finally:(fun () -> Clean.remove_tree root)
    (fun () ->
       write
         (Filename.concat root "dune-project")
         "(lang dune 3.17)\n(name native_plan)\n";
       f root)
;;

let plan ~root ~config ~profile =
  Plan.native_build
    ~project_root:root
    ~config
    ~target:Plan.Macos
    ~profile
    ~toolchain_fingerprint:"native-test"
    ~apple_sdk_root:"unused"
    ~apple_sdk_version:None
  |> get_ok
;;

let test_direct_complete_object () =
  with_project (fun root ->
    let config = config "app/native_embed.exe.o" in
    let dune =
      "(rule (target selected_profile.txt) (action (write-file %{target} %{profile})))\n\
       (executable (name native_embed) (modules native_embed)\n\
       (link_deps selected_profile.txt) (modes (native object)))\n"
    in
    let dune_path = Filename.concat root "app/dune" in
    let source = Filename.concat root "app/native_embed.ml" in
    write dune_path dune;
    write source "let () = print_endline \"first\"\n";
    List.iter
      (fun (profile, expected_profile) ->
         let build = plan ~root ~config ~profile in
         Scaffold.ensure_directory (Filename.dirname build.build_directory);
         Process_runner.run build.command |> get_ok;
         Alcotest.(check bool)
           "complete object exists"
           true
           (Sys.file_exists build.source_object);
         Alcotest.(check string)
           "actual Dune profile"
           expected_profile
           (read
              (Filename.concat build.build_directory "default/app/selected_profile.txt"));
         Alcotest.(check string)
           "Dune source remains application-owned"
           dune
           (read dune_path))
      [ Plan.Debug, "dev"; Plan.Profile, "release"; Plan.Release, "release" ];
    let build = plan ~root ~config ~profile:Plan.Debug in
    let original_mtime = (Unix.stat build.source_object).st_mtime in
    let original_digest = Digest.file build.source_object in
    Process_runner.run build.command |> get_ok;
    Alcotest.(check (float 0.))
      "incremental object is untouched"
      original_mtime
      (Unix.stat build.source_object).st_mtime;
    write source "let () = print_endline \"second\"\n";
    Process_runner.run build.command |> get_ok;
    Alcotest.(check bool)
      "OCaml edit rebuilds the complete object"
      true
      (original_digest <> Digest.file build.source_object))
;;

let test_native_build_without_managed_aliases () =
  let framework_root =
    Sys.executable_name
    |> Unix.realpath
    |> Filename.dirname
    |> Filename.dirname
    |> Filename.dirname
  in
  let source =
    Filename.concat framework_root "examples/counter/ocaml/native_embed.exe.o"
  in
  Alcotest.(check bool) "real Counter fixture exists" true (Sys.file_exists source);
  with_project (fun root ->
    let config = config "app/complete object.exe.o" in
    let dune =
      Printf.sprintf
        "(rule (target \"complete object.exe.o\") (deps %S) (action (copy %%{deps} \
         %%{target})))\n"
        source
    in
    let path = Filename.concat root "app/dune" in
    write path dune;
    let build () =
      Build_system.build_native
        ~framework_root
        ~project_root:root
        ~config
        ~target:Plan.Macos
        ~profile:Plan.Debug
      |> get_ok
    in
    let artifact = build () in
    Alcotest.(check string)
      "actual Counter object is staged"
      (Digest.file source)
      (Digest.file artifact);
    let timestamp = (Unix.stat artifact).st_mtime in
    Alcotest.(check string) "repeated build returns same artifact" artifact (build ());
    Alcotest.(check (float 0.))
      "unchanged verified artifact is not replaced"
      timestamp
      (Unix.stat artifact).st_mtime;
    Alcotest.(check string) "no Dune alias injection" dune (read path))
;;

let test_direct_target_validation () =
  with_project (fun root ->
    List.iter
      (fun target ->
         match
           Plan.native_build
             ~project_root:root
             ~config:(config target)
             ~target:Plan.Macos
             ~profile:Plan.Debug
             ~toolchain_fingerprint:"native-test"
             ~apple_sdk_root:"unused"
             ~apple_sdk_version:None
         with
         | Error _ -> ()
         | Ok _ -> Alcotest.failf "unsafe direct target was admitted: %S" target)
      [ "../outside.exe.o"; "/tmp/outside.exe.o"; "@alias"; "-invalid.exe.o" ];
    let build =
      plan ~root ~config:(config "app/complete object.exe.o") ~profile:Plan.Debug
    in
    Alcotest.(check bool)
      "no embedding gate"
      false
      (List.mem_assoc "BONSAI_SWIFTUI_EMBED_OCAML" build.command.environment))
;;

let test_iphoneos_artifact_minimum () =
  with_project (fun root ->
    let original = config "app/native_embed.exe.o" in
    let config = { original with ios = { original.ios with minimum_version = "26.0" } } in
    let sdk_root =
      Process_runner.capture
        ~working_directory:root
        ~environment:[]
        "xcrun"
        [ "--sdk"; "iphoneos"; "--show-sdk-path" ]
      |> get_ok
    in
    let sdk_version =
      Process_runner.capture
        ~working_directory:root
        ~environment:[]
        "xcrun"
        [ "--sdk"; "iphoneos"; "--show-sdk-version" ]
      |> get_ok
    in
    let build =
      Plan.native_build
        ~project_root:root
        ~config
        ~target:Plan.Iphoneos
        ~profile:Plan.Release
        ~toolchain_fingerprint:"ios-floor-test"
        ~apple_sdk_root:sdk_root
        ~apple_sdk_version:(Some sdk_version)
      |> get_ok
    in
    Scaffold.ensure_directory (Filename.dirname build.source_object);
    let source = Filename.concat root "answer.c" in
    write source "int retained_answer(void) { return 42; }\n";
    Process_runner.run
      { program = "xcrun"
      ; arguments =
          [ "--sdk"
          ; "iphoneos"
          ; "clang"
          ; "-target"
          ; "arm64-apple-ios18.0"
          ; "-isysroot"
          ; sdk_root
          ; "-c"
          ; source
          ; "-o"
          ; build.source_object
          ]
      ; working_directory = root
      ; environment = []
      }
    |> get_ok;
    let input_digest = Digest.file build.source_object in
    let destination = Filename.concat root "application.o" in
    Artifact.prepare_source ~build ~config ~target:Plan.Iphoneos destination |> get_ok;
    let metadata =
      Process_runner.capture
        ~working_directory:root
        ~environment:[]
        "xcrun"
        [ "vtool"; "-show-build"; destination ]
      |> get_ok
    in
    Alcotest.(check bool)
      "application minimum is adopted"
      true
      (Artifact.contains ~needle:"minos 26.0" metadata);
    Alcotest.(check bool)
      "SDK-floor input is not rewritten"
      true
      (input_digest = Digest.file build.source_object);
    let symbols =
      Process_runner.capture
        ~working_directory:root
        ~environment:[]
        "nm"
        [ "-g"; destination ]
      |> get_ok
    in
    Alcotest.(check bool)
      "relocation retains input code"
      true
      (Artifact.contains ~needle:"_retained_answer" symbols))
;;

let () =
  Alcotest.run
    "SwiftUI native build"
    [ ( "native"
      , [ Alcotest.test_case
            "direct object, profiles, incremental source"
            `Quick
            test_direct_complete_object
        ; Alcotest.test_case
            "actual Counter staging without aliases"
            `Quick
            test_native_build_without_managed_aliases
        ; Alcotest.test_case
            "iPhoneOS application deployment target"
            `Quick
            test_iphoneos_artifact_minimum
        ; Alcotest.test_case
            "direct target validation"
            `Quick
            test_direct_target_validation
        ] )
    ]
;;
