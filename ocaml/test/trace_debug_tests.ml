let require condition message = if not condition then failwith message

let () =
  let calls = ref 0 in
  Trace.trace (fun () -> calls := !calls + 1);
  require (!calls = 1) "debug trace did not execute its action exactly once";
  let raised =
    try
      Trace.trace (fun () -> failwith "debug trace failure");
      false
    with
    | Failure message -> String.equal message "debug trace failure"
    | _ -> false
  in
  require raised "debug trace did not propagate its action failure"
;;
