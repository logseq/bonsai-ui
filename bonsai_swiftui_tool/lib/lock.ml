let with_lock path f =
  try
    Scaffold.ensure_directory (Filename.dirname path);
    let descriptor = Unix.openfile path [ Unix.O_CREAT; Unix.O_RDWR ] 0o600 in
    Fun.protect
      ~finally:(fun () -> Unix.close descriptor)
      (fun () ->
         Unix.lockf descriptor Unix.F_LOCK 0;
         f ())
  with
  | Sys_error message | Unix.Unix_error (_, _, message) -> Error message
;;
