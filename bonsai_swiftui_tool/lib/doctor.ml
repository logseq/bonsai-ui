let command_version ~working_directory program arguments =
  match Process_runner.capture ~working_directory ~environment:[] program arguments with
  | Ok output -> Ok (program, output)
  | Error message -> Error (Printf.sprintf "%s is unavailable: %s" program message)
;;

let run ~project_root ~target =
  let sdk =
    match target with
    | None | Some Plan.Macos -> "macosx"
    | Some Plan.Iphoneos -> "iphoneos"
    | Some Plan.Iossimulator -> "iphonesimulator"
  in
  let commands =
    [ ( "python3"
      , [ "-c"
        ; "import sys; sys.version_info >= (3, 9) or sys.exit('Python 3.9 or newer is \
           required'); print(sys.version.split()[0])"
        ] )
    ; "opam", [ "--version" ]
    ; "dune", [ "--version" ]
    ; "xcodebuild", [ "-version" ]
    ; "xcrun", [ "--sdk"; sdk; "--show-sdk-path" ]
    ; "xcrun", [ "--sdk"; sdk; "swiftc"; "--version" ]
    ]
  in
  let rec check acc = function
    | [] -> Ok (List.rev acc)
    | (program, arguments) :: rest ->
      (match command_version ~working_directory:project_root program arguments with
       | Ok diagnostic -> check (diagnostic :: acc) rest
       | Error _ as error -> error)
  in
  check [] commands
;;
