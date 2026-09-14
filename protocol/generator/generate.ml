open Protocol_generator

let targets root (outputs : Render.outputs) =
  [ Filename.concat root "ocaml/protocol/generated_protocol.mli", outputs.ocaml_interface
  ; ( Filename.concat root "ocaml/protocol/generated_protocol.ml"
    , outputs.ocaml_implementation )
  ; ( Filename.concat root "swift/BonsaiSwiftUI/Sources/GeneratedProtocol.swift"
    , outputs.swift )
  ; Filename.concat root "protocol/generated/protocol-ids.md", outputs.markdown
  ]
;;

let read path =
  try
    let channel = open_in_bin path in
    Some
      (Fun.protect
         ~finally:(fun () -> close_in channel)
         (fun () -> really_input_string channel (in_channel_length channel)))
  with
  | Sys_error _ -> None
;;

let write path contents =
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out channel)
    (fun () -> output_string channel contents)
;;

let () =
  let check = Array.to_list Sys.argv |> List.exists (String.equal "--check") in
  let root = Sys.getcwd () in
  let schema_path = Filename.concat root "protocol/schema.sexp" in
  let schema =
    match Schema.load schema_path with
    | Ok schema -> schema
    | Error message ->
      prerr_endline ("Protocol schema error: " ^ message);
      exit 2
  in
  let stale = ref [] in
  targets root (Render.all schema)
  |> List.iter (fun (path, expected) ->
    if check
    then (if read path <> Some expected then stale := path :: !stale)
    else write path expected);
  match List.rev !stale with
  | [] -> ()
  | paths ->
    List.iter (fun path -> prerr_endline ("Generated file is stale: " ^ path)) paths;
    exit 1
;;
