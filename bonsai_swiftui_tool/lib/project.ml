let find_root start =
  let rec walk directory =
    if Sys.file_exists (Filename.concat directory "bonsai-swiftui.sexp")
    then Ok directory
    else (
      let parent = Filename.dirname directory in
      if String.equal parent directory
      then Error (Printf.sprintf "No bonsai-swiftui.sexp was found at or above %s" start)
      else walk parent)
  in
  try walk (Unix.realpath start) with
  | Unix.Unix_error (_, _, message) -> Error message
;;
