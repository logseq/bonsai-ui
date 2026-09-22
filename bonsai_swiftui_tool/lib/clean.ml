type target =
  | Macos
  | Iphoneos
  | Iossimulator
  | All

let rec remove_tree path =
  try
    match (Unix.lstat path).st_kind with
    | Unix.S_DIR ->
      Sys.readdir path |> Array.iter (fun name -> remove_tree (Filename.concat path name));
      Unix.rmdir path
    | Unix.S_REG | Unix.S_LNK | Unix.S_CHR | Unix.S_BLK | Unix.S_FIFO | Unix.S_SOCK ->
      Unix.unlink path
  with
  | Unix.Unix_error (Unix.ENOENT, _, _) -> ()
;;

let platform_paths = function
  | Macos ->
    [ "dune/macos"
    ; "artifacts/macos"
    ; "state/macos"
    ; "logs/macos"
    ; "locks/macos"
    ; "dependencies/probes/macos"
    ; "dependencies/validation/macos"
    ]
  | Iphoneos ->
    [ "dune/iphoneos"
    ; "artifacts/ios/iphoneos"
    ; "state/iphoneos"
    ; "logs/iphoneos"
    ; "locks/iphoneos"
    ; "dependencies/probes/ios"
    ; "dependencies/validation/ios"
    ]
  | Iossimulator ->
    [ "dune/iossimulator"
    ; "artifacts/ios/iossimulator"
    ; "state/iossimulator"
    ; "logs/iossimulator"
    ; "locks/iossimulator"
    ]
  | All -> []
;;

let ( let* ) result f =
  match result with
  | Ok value -> f value
  | Error _ as error -> error
;;

let validate_parents ~project_root relative =
  let components =
    String.split_on_char '/' relative
    |> List.filter (fun part -> part <> "" && part <> ".")
  in
  let rec walk directory = function
    | [] | [ _ ] -> Ok ()
    | component :: rest ->
      let path = Filename.concat directory component in
      (try
         match (Unix.lstat path).st_kind with
         | Unix.S_DIR -> walk path rest
         | Unix.S_LNK ->
           Error (Printf.sprintf "Refusing to clean through symlink parent: %s" path)
         | _ -> Error (Printf.sprintf "Build-output parent is not a directory: %s" path)
       with
       | Unix.Unix_error (Unix.ENOENT, _, _) -> Ok ())
  in
  walk project_root components
;;

let run ~project_root ~(config : Config.t) target =
  try
    if Filename.is_relative project_root
    then Error "The project root must be absolute"
    else (
      let project_root = Unix.realpath project_root in
      if project_root = Filename.dir_sep
      then Error "Refusing to clean from the filesystem root"
      else (
        Config.validate_relative_path ~field:"apple_root" config.apple_root;
        let native_root = "_build/bonsai-swiftui" in
        let native_paths =
          match target with
          | All -> [ native_root ]
          | Macos | Iphoneos | Iossimulator ->
            List.map (Filename.concat native_root) (platform_paths target)
        in
        let apple_paths =
          match target with
          | All -> [ "Native"; "DerivedData" ]
          | Macos | Iphoneos | Iossimulator ->
            let sdk, suffix =
              match target with
              | Macos -> "macosx", ""
              | Iphoneos -> "iphoneos", "-iphoneos"
              | Iossimulator -> "iphonesimulator", "-iphonesimulator"
              | All -> assert false
            in
            ("Native/" ^ sdk)
            :: List.map
                 (fun configuration ->
                    "DerivedData/Build/Products/" ^ configuration ^ suffix)
                 [ "Debug"; "Profile"; "Release" ]
        in
        let paths =
          native_paths @ List.map (Filename.concat config.apple_root) apple_paths
        in
        let rec validate = function
          | [] -> Ok ()
          | path :: rest ->
            let* () = validate_parents ~project_root path in
            validate rest
        in
        let* () = validate paths in
        Lock.with_apple_lock ~project_root (fun () ->
          let* () = validate paths in
          List.iter (fun path -> remove_tree (Filename.concat project_root path)) paths;
          Ok ())))
  with
  | Config.Invalid message | Sys_error message | Unix.Unix_error (_, _, message) ->
    Error message
;;
