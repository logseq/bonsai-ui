let ( let* ) result f =
  match result with
  | Ok value -> f value
  | Error _ as error -> error
;;

let rec ensure_directory path =
  if path = "" || path = Filename.dirname path || Sys.file_exists path
  then ()
  else (
    ensure_directory (Filename.dirname path);
    Unix.mkdir path 0o755)
;;

let write_if_missing path contents =
  if not (Sys.file_exists path)
  then (
    ensure_directory (Filename.dirname path);
    let channel = open_out_bin path in
    output_string channel contents;
    close_out channel)
;;

let read_file path =
  if not (Sys.file_exists path)
  then None
  else (
    let channel = open_in_bin path in
    let contents = really_input_string channel (in_channel_length channel) in
    close_in channel;
    Some contents)
;;

let write_if_changed path contents =
  if read_file path <> Some contents
  then (
    ensure_directory (Filename.dirname path);
    let channel = open_out_bin path in
    output_string channel contents;
    close_out channel)
;;

let generated_app_ml name =
  Printf.sprintf
    {|module Ui = Bonsai_swiftui_ui

let component handlers graph =
  let count, set_count = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let increment =
    Driver.Handler.create handlers ~name:"increment" ~equal:( == ) set_count
      ~f:(fun set_count -> function
        | Ui.Event.Payload.Unit -> set_count (fun count -> count + 1)
        | _ -> Bonsai.Effect.Ignore)
  in
  Bonsai.Cont.map2 count increment ~f:(fun count increment ->
    App.View.create ~theme:(Ui.Theme.create ())
      ~body:(Ui.View.Body.static
        (Ui.View.column
          [ Ui.View.text "%s"
          ; Ui.View.text (Printf.sprintf "Count: %%d" count)
          ; Ui.View.button ~style:Ui.View.Button_style.Prominent
              ~on_press:increment ~child:(Ui.View.text "Increment") ()
          ])))
;;

let app = App.create ~name:"%s" component
|}
    name
    name
;;

let swift_application name =
  Printf.sprintf
    {|import BonsaiSwiftUI
import SwiftUI

@main struct ApplicationHost: App {
  var body: some Scene {
    WindowGroup {
      BonsaiApplicationView(entrypoint: "%s")
        .frame(minWidth: 320, minHeight: 240)
    }
  }
}
|}
    name
;;

let native_embed name =
  Printf.sprintf
    {|let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "%s")
    Application.app
;;
|}
    name
;;

let app_dune =
  {|(library
 (name app)
 (wrapped false)
 (modules application)
 (libraries
  bonsai_swiftui.spec_impl
  base
  bonsai
  bonsai_swiftui.ui
  bonsai_swiftui.driver
  incr_dom.ui_incr
  virtual_dom.ui_effect))

(executable
 (name native_embed)
 (modules native_embed)
 (libraries
  bonsai_swiftui.spec_impl
  app
  bonsai_swiftui.driver
  bonsai_swiftui.native_backend)
 (modes
  (native object)))
|}
;;

let configuration_text
      ~name
      ~macos_bundle_identifier
      ~ios_bundle_identifier
      ~features
      ~macos_minimum_version
      ~ios_minimum_version
  =
  let explicit_features =
    features
    |> List.filter (fun feature -> not (Config.Feature.equal feature Config.Feature.Core))
    |> List.map Config.Feature.to_string
  in
  let feature_line =
    match explicit_features with
    | [] -> " (features)"
    | features -> " (features " ^ String.concat " " features ^ ")"
  in
  Printf.sprintf
    {|(lang 4)

(app
 (name %s)
 (apple_root apple)
 (native_target app/native_embed.exe.o)
%s
 (macos
  (bundle_identifier %s)
  (minimum_version %s)
  (architectures arm64))
 (ios
  (bundle_identifier %s)
  (minimum_version %s)
  (architectures arm64)))
|}
    name
    feature_line
    macos_bundle_identifier
    macos_minimum_version
    ios_bundle_identifier
    ios_minimum_version
;;

let dune_project name =
  Printf.sprintf
    {|(lang dune 3.17)
(name %s)
(generate_opam_files false)
(license MIT)

(package
 (name %s)
 (allow_empty)
 (depends
  (ocaml (= 5.1.1))
  (dune (>= 3.17))
  (bonsai_swiftui (= 0.1.0~dev))
  (bonsai_swiftui_tool (= 0.1.0~dev))
  (base (and (>= v0.17) (< v0.18~)))
  (bonsai (and (>= v0.17) (< v0.18~)))
  (core (and (>= v0.17) (< v0.18~)))
  (incr_dom (and (>= v0.17) (< v0.18~)))
  (virtual_dom (and (>= v0.17) (< v0.18~)))))
|}
    name
    name
;;

let opam_manifest name =
  Printf.sprintf
    {|opam-version: "2.0"
name: "%s"
version: "0.1.0"
synopsis: "%s Bonsai SwiftUI application"
maintainer: "application authors"
authors: ["application authors"]
license: "MIT"
depends: [
  "ocaml" {= "5.1.1"}
  "dune" {>= "3.17"}
  "bonsai_swiftui" {= "0.1.0~dev"}
  "bonsai_swiftui_tool" {= "0.1.0~dev"}
  "base" {>= "v0.17" & < "v0.18~"}
  "bonsai" {>= "v0.17" & < "v0.18~"}
  "core" {>= "v0.17" & < "v0.18~"}
  "incr_dom" {>= "v0.17" & < "v0.18~"}
  "virtual_dom" {>= "v0.17" & < "v0.18~"}
]
build: [
  ["dune" "build" "-p" name "-j" jobs]
]
|}
    name
    name
;;

let opam_locked_manifest name =
  Printf.sprintf
    {|opam-version: "2.0"
name: "%s"
version: "0.1.0"
synopsis: "%s Bonsai SwiftUI application lock"
maintainer: "application authors"
authors: ["application authors"]
license: "MIT"
depends: [
  "ocaml" {= "5.1.1"}
  "ocaml-ios64" {= "5.1.1"}
  "dune" {= "3.23.1"}
  "bonsai_swiftui" {= "0.1.0~dev"}
  "bonsai_swiftui_tool" {= "0.1.0~dev"}
  "base" {= "v0.17.3"}
  "bonsai" {= "v0.17.0"}
  "core" {= "v0.17.2"}
  "incr_dom" {= "v0.17.0"}
  "virtual_dom" {= "v0.17.0"}
]
|}
    name
    name
;;

let initialize ~project_root ~config =
  try
    let app_directory = Filename.concat project_root "app" in
    write_if_missing
      (Filename.concat app_directory "application.ml")
      (generated_app_ml config.Config.name);
    write_if_missing (Filename.concat app_directory "application.mli") "val app : App.t\n";
    write_if_missing
      (Filename.concat app_directory "native_embed.ml")
      (native_embed config.name);
    write_if_missing (Filename.concat app_directory "dune") app_dune;
    write_if_missing
      (Filename.concat project_root "swift/App.swift")
      (swift_application config.name);
    Ok ()
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;

let ensure_configuration ~project_root ~config_text =
  let path = Filename.concat project_root "bonsai-swiftui.sexp" in
  match read_file path with
  | None ->
    write_if_missing path config_text;
    Ok ()
  | Some existing when String.equal existing config_text -> Ok ()
  | Some _ -> Error (Printf.sprintf "bonsai-swiftui.sexp conflicts with %s" path)
;;

let initialize_metadata ~project_root ~config_text ~config =
  let* () = ensure_configuration ~project_root ~config_text in
  write_if_missing
    (Filename.concat project_root ".ocamlformat")
    "version=0.29.0\nprofile=janestreet\n";
  write_if_missing
    (Filename.concat project_root "dune-project")
    (dune_project config.Config.name);
  let existing_manifests =
    Sys.readdir project_root
    |> Array.to_list
    |> List.filter (fun name -> String.ends_with ~suffix:".opam" name)
  in
  if existing_manifests = []
  then (
    write_if_missing
      (Filename.concat project_root (config.name ^ ".opam"))
      (opam_manifest config.name);
    write_if_missing
      (Filename.concat project_root (config.name ^ ".opam.locked"))
      (opam_locked_manifest config.name));
  Ok ()
;;

let initialize_workspace ~project_root ~config_text ~config =
  try
    let* () = initialize_metadata ~project_root ~config_text ~config in
    initialize ~project_root ~config
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;

let adopt_workspace ~project_root ~config_text ~config =
  try
    let dune_path =
      Filename.concat
        project_root
        (Filename.concat (Filename.dirname config.Config.native_target) "dune")
    in
    if not (Sys.file_exists dune_path)
    then
      Error
        (Printf.sprintf "Cannot adopt: native target Dune file is missing: %s" dune_path)
    else initialize_metadata ~project_root ~config_text ~config
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;
