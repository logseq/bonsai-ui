let ( let* ) result f =
  match result with
  | Ok value -> f value
  | Error _ as error -> error
;;

let only_architecture = function
  | [ architecture ] -> architecture
  | _ -> invalid_arg "validated platform must contain exactly one architecture"
;;

let copy_file source destination =
  Scaffold.ensure_directory (Filename.dirname destination);
  let input_channel = open_in_bin source in
  let output_channel = open_out_bin destination in
  let buffer = Bytes.create 65536 in
  let rec copy () =
    match input input_channel buffer 0 (Bytes.length buffer) with
    | 0 -> ()
    | count ->
      output output_channel buffer 0 count;
      copy ()
  in
  Fun.protect
    ~finally:(fun () ->
      close_in_noerr input_channel;
      close_out_noerr output_channel)
    copy
;;

let files_equal left right =
  if not (Sys.file_exists right)
  then false
  else (
    let left_channel = open_in_bin left in
    let right_channel = open_in_bin right in
    let left_buffer = Bytes.create 65536 in
    let right_buffer = Bytes.create 65536 in
    let rec compare () =
      let left_count = input left_channel left_buffer 0 (Bytes.length left_buffer) in
      let right_count = input right_channel right_buffer 0 (Bytes.length right_buffer) in
      left_count = right_count
      && (left_count = 0
          || (Bytes.equal
                (Bytes.sub left_buffer 0 left_count)
                (Bytes.sub right_buffer 0 right_count)
              && compare ()))
    in
    Fun.protect
      ~finally:(fun () ->
        close_in_noerr left_channel;
        close_in_noerr right_channel)
      compare)
;;

let digest path =
  let channel = open_in_bin path in
  let buffer = Bytes.create 65536 in
  let rec consume context =
    match input channel buffer 0 (Bytes.length buffer) with
    | 0 -> context
    | count -> consume (Digestif.SHA256.feed_bytes context ~len:count buffer)
  in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () ->
       consume Digestif.SHA256.empty |> Digestif.SHA256.get |> Digestif.SHA256.to_hex)
;;

let temporary_sibling destination =
  let directory = Filename.dirname destination in
  let basename = Filename.basename destination in
  let rec choose attempt =
    let candidate =
      Filename.concat
        directory
        (Printf.sprintf ".%s.tmp.%d.%d" basename (Unix.getpid ()) attempt)
    in
    if Sys.file_exists candidate then choose (attempt + 1) else candidate
  in
  choose 0
;;

let contains ~needle haystack =
  let needle_length = String.length needle in
  let haystack_length = String.length haystack in
  let rec search index =
    index + needle_length <= haystack_length
    && (String.sub haystack index needle_length = needle || search (index + 1))
  in
  needle_length = 0 || search 0
;;

let embed_macos_network_gmp ~(build : Plan.native_build) ~config destination =
  let project_root = build.command.working_directory in
  let* libdir =
    Process_runner.capture
      ~working_directory:project_root
      ~environment:[]
      "pkg-config"
      [ "--variable=libdir"; "gmp" ]
  in
  let archive = Filename.concat libdir "libgmp.a" in
  if not (Sys.file_exists archive)
  then Error (Printf.sprintf "The static GMP archive is missing: %s" archive)
  else (
    let sdk_root =
      List.assoc_opt "BONSAI_SWIFTUI_APPLE_SDK_ROOT" build.command.environment
    in
    match sdk_root with
    | None -> Error "The macOS SDK root is missing from the native build plan"
    | Some sdk_root ->
      let architecture = only_architecture config.Config.macos.architectures in
      let minimum_version = config.macos.minimum_version in
      let command : Plan.command =
        { program = "clang"
        ; arguments =
            [ "-r"
            ; "-target"
            ; Printf.sprintf "%s-apple-macos%s" architecture minimum_version
            ; "-mmacosx-version-min=" ^ minimum_version
            ; "-isysroot"
            ; sdk_root
            ; build.source_object
            ; archive
            ; "-o"
            ; destination
            ]
        ; working_directory = project_root
        ; environment = []
        }
      in
      let* () = Process_runner.run command in
      let* undefined_symbols =
        Process_runner.capture
          ~working_directory:project_root
          ~environment:[]
          "nm"
          [ "-u"; destination ]
      in
      let undefined_symbols = String.lowercase_ascii undefined_symbols in
      if contains ~needle:"gmp" undefined_symbols
      then Error "The network complete object still contains unresolved GMP symbols"
      else Ok ())
;;

let prepare_source ~(build : Plan.native_build) ~config ~target destination =
  match target with
  | Plan.Macos
    when List.exists (Config.Feature.equal Config.Feature.Network) config.Config.features
    -> embed_macos_network_gmp ~build ~config destination
  | Plan.Macos | Plan.Iphoneos ->
    copy_file build.source_object destination;
    Ok ()
;;

let verify ~framework_root ~project_root ~config ~target path =
  let platform, minimum_version, architecture =
    match target with
    | Plan.Macos ->
      ( "MACOS"
      , config.Config.macos.minimum_version
      , only_architecture config.Config.macos.architectures )
    | Plan.Iphoneos ->
      ( "IOS"
      , config.Config.ios.minimum_version
      , only_architecture config.Config.ios.architectures )
  in
  let command : Plan.command =
    { program = Filename.concat framework_root "tool/ios/verify_complete_object.sh"
    ; arguments = [ path; platform; minimum_version; architecture ]
    ; working_directory = project_root
    ; environment = []
    }
  in
  Process_runner.run command
;;

let stage ~framework_root ~(build : Plan.native_build) ~config ~target =
  if not (Sys.file_exists build.source_object)
  then
    Error (Printf.sprintf "The native complete object is missing: %s" build.source_object)
  else (
    try
      Scaffold.ensure_directory (Filename.dirname build.staged_object);
      let temporary = temporary_sibling build.staged_object in
      Fun.protect
        ~finally:(fun () -> if Sys.file_exists temporary then Sys.remove temporary)
        (fun () ->
           let* () = prepare_source ~build ~config ~target temporary in
           let candidate =
             if files_equal temporary build.staged_object
             then build.staged_object
             else temporary
           in
           match
             verify
               ~framework_root
               ~project_root:build.command.working_directory
               ~config
               ~target
               candidate
           with
           | Error _ as error -> error
           | Ok () ->
             if String.equal candidate temporary
             then Unix.rename temporary build.staged_object;
             Ok build.staged_object)
    with
    | Sys_error message | Unix.Unix_error (_, _, message) -> Error message)
;;

let write_if_changed path contents =
  try
    let unchanged =
      if not (Sys.file_exists path)
      then false
      else (
        let channel = open_in_bin path in
        let existing = really_input_string channel (in_channel_length channel) in
        close_in channel;
        String.equal existing contents)
    in
    if not unchanged
    then (
      Scaffold.ensure_directory (Filename.dirname path);
      let temporary = temporary_sibling path in
      Fun.protect
        ~finally:(fun () -> if Sys.file_exists temporary then Sys.remove temporary)
        (fun () ->
           let channel = open_out_bin temporary in
           output_string channel contents;
           close_out channel;
           Unix.rename temporary path));
    Ok ()
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;
