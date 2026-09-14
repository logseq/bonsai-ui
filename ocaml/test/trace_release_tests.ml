let require condition message = if not condition then failwith message

let () =
  let called = ref false in
  Trace.trace (fun () -> called := true);
  require (not !called) "release trace executed its action";
  Trace.trace (fun () -> failwith "release trace action must not run")
;;
