let framework_marker root =
  root <> ""
  && List.for_all
       (fun path ->
          try (Unix.stat (Filename.concat root path)).st_kind = Unix.S_REG with
          | Unix.Unix_error _ -> false)
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

let find_framework_root () =
  match Sys.getenv_opt "BONSAI_SWIFTUI_SOURCE_ROOT" with
  | Some root when framework_marker root -> Ok root
  | Some root -> Error (Printf.sprintf "BONSAI_SWIFTUI_SOURCE_ROOT is invalid: %s" root)
  | None ->
    let executable =
      try Unix.realpath Sys.executable_name with
      | Unix.Unix_error _ -> Sys.executable_name
    in
    let prefix = Filename.dirname (Filename.dirname executable) in
    let installed = Filename.concat prefix "share/bonsai_swiftui_tool/framework" in
    if framework_marker installed
    then Ok installed
    else (
      let rec walk directory =
        if framework_marker directory
        then Some directory
        else (
          let parent = Filename.dirname directory in
          if String.equal parent directory then None else walk parent)
      in
      match walk (Sys.getcwd ()) with
      | Some root -> Ok root
      | None ->
        Error
          "The Bonsai SwiftUI framework assets are unavailable; reinstall \
           bonsai_swiftui_tool")
;;
