open Protocol_generator

let fail format = Printf.ksprintf failwith format

let expect condition format =
  Printf.ksprintf (fun message -> if not condition then failwith message) format
;;

let expect_contains text fragment =
  let text_length = String.length text in
  let fragment_length = String.length fragment in
  let rec loop index =
    if index + fragment_length > text_length
    then false
    else if String.sub text index fragment_length = fragment
    then true
    else loop (index + 1)
  in
  expect (loop 0) "generated output is missing %S" fragment
;;

let test_duplicate_ids_are_rejected () =
  let duplicate_schema =
    "((protocol (major 1) (minor 0) (header_bytes 48) (max_frame_bytes 1) \
     (max_string_bytes 1) (max_application_payload_bytes 1) (max_operations 1) \
     (max_nodes 1)) (frame_kinds ((a 1) (b 1))) (operations ()) (node_kinds ()) \
     (event_tags ()) (host_requests ()) (runtime_errors ()))"
  in
  match Schema.parse duplicate_schema with
  | Ok _ -> fail "duplicate IDs unexpectedly parsed"
  | Error message -> expect_contains message "duplicate ID"
;;

let () =
  test_duplicate_ids_are_rejected ();
  print_endline "generator tests passed"
;;
