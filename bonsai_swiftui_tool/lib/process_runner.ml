let merge_environment additions =
  let additions_names = List.map fst additions in
  let inherited =
    Unix.environment ()
    |> Array.to_list
    |> List.filter (fun binding ->
      match String.index_opt binding '=' with
      | None -> true
      | Some index ->
        let name = String.sub binding 0 index in
        not (List.mem name additions_names))
  in
  inherited @ List.map (fun (name, value) -> name ^ "=" ^ value) additions
  |> Array.of_list
;;

let with_working_directory directory f =
  let previous = Sys.getcwd () in
  Unix.chdir directory;
  Fun.protect ~finally:(fun () -> Unix.chdir previous) f
;;

let status_error program = function
  | Unix.WEXITED code -> Printf.sprintf "%s exited with status %d" program code
  | Unix.WSIGNALED signal -> Printf.sprintf "%s was killed by signal %d" program signal
  | Unix.WSTOPPED signal -> Printf.sprintf "%s was stopped by signal %d" program signal
;;

let spawn (command : Plan.command) =
  let environment = merge_environment command.environment in
  let arguments = Array.of_list (command.program :: command.arguments) in
  with_working_directory command.working_directory (fun () ->
    Unix.create_process_env
      command.program
      arguments
      environment
      Unix.stdin
      Unix.stdout
      Unix.stderr)
;;

let rec waitpid process =
  try snd (Unix.waitpid [] process) with
  | Unix.Unix_error (Unix.EINTR, _, _) -> waitpid process
;;

let run (command : Plan.command) =
  try
    let status = spawn command |> waitpid in
    match status with
    | Unix.WEXITED 0 -> Ok ()
    | status -> Error (status_error command.program status)
  with
  | Unix.Unix_error (error, function_name, argument) ->
    Error
      (Printf.sprintf
         "%s failed for %s: %s"
         function_name
         argument
         (Unix.error_message error))
;;

let signal_exit_code signal =
  let number =
    if signal = Sys.sighup
    then 1
    else if signal = Sys.sigint
    then 2
    else if signal = Sys.sigquit
    then 3
    else if signal = Sys.sigkill
    then 9
    else if signal = Sys.sigterm
    then 15
    else Int.abs signal
  in
  128 + number
;;

let exit_code = function
  | Unix.WEXITED code -> code
  | Unix.WSIGNALED signal | Unix.WSTOPPED signal -> signal_exit_code signal
;;

let run_status ?(on_spawn = fun _ -> ()) (command : Plan.command) =
  try
    let process = spawn command in
    on_spawn process;
    Ok (waitpid process |> exit_code)
  with
  | Unix.Unix_error (error, function_name, argument) ->
    Error
      (Printf.sprintf
         "%s failed for %s: %s"
         function_name
         argument
         (Unix.error_message error))
;;

let capture ~working_directory ~environment program arguments =
  try
    let input, output = Unix.pipe ~cloexec:true () in
    let child_environment = merge_environment environment in
    let argv = Array.of_list (program :: arguments) in
    let process =
      with_working_directory working_directory (fun () ->
        Unix.create_process_env
          program
          argv
          child_environment
          Unix.stdin
          output
          Unix.stderr)
    in
    Unix.close output;
    let channel = Unix.in_channel_of_descr input in
    let buffer = Buffer.create 128 in
    (try
       while true do
         Buffer.add_channel buffer channel 4096
       done
     with
     | End_of_file -> ());
    close_in channel;
    let _, status = Unix.waitpid [] process in
    match status with
    | Unix.WEXITED 0 -> Ok (String.trim (Buffer.contents buffer))
    | status -> Error (status_error program status)
  with
  | Unix.Unix_error (error, function_name, argument) ->
    Error
      (Printf.sprintf
         "%s failed for %s: %s"
         function_name
         argument
         (Unix.error_message error))
;;
