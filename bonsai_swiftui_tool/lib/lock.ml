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

let apple_path project_root =
  Filename.concat project_root "_build/.bonsai-swiftui-apple.lock"
;;

let with_apple_lock ~project_root f =
  let path = apple_path project_root in
  let check path =
    try
      if (Unix.lstat path).st_kind = Unix.S_LNK
      then Error ("Refusing Apple build lock through symlink: " ^ path)
      else Ok ()
    with
    | Unix.Unix_error (Unix.ENOENT, _, _) -> Ok ()
  in
  match check (Filename.dirname path), check path with
  | Error message, _ | _, Error message -> Error message
  | Ok (), Ok () -> with_lock path f
;;
