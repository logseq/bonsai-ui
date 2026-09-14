type progress =
  { completed_bytes : int
  ; total_bytes : int
  }

type read_result =
  { total_bytes : int
  ; checksum : int64
  }

let file_name = "eio-worker-demo.bin"
let chunk_size = 64 * 1024
let max_file_size = 16 * 1024 * 1024

exception File_limit of string

let validate_size total_bytes =
  if total_bytes <= 0
  then Error "Demo file size must be positive"
  else if total_bytes > max_file_size
  then Error "Demo file size exceeds the 16 MiB limit"
  else Ok ()
;;

let make_chunk ~offset length =
  let bytes = Bytes.create length in
  for index = 0 to length - 1 do
    Bytes.set bytes index (Char.chr ((offset + index) land 0xff))
  done;
  Cstruct.of_bytes bytes
;;

let write_chunks ?(after_chunk = fun _ -> ()) sink ~total_bytes ~progress =
  let rec loop offset chunk =
    if offset < total_bytes
    then (
      let length = Int.min chunk_size (total_bytes - offset) in
      Eio.Flow.write sink [ make_chunk ~offset length ];
      let completed_bytes = offset + length in
      progress { completed_bytes; total_bytes };
      after_chunk chunk;
      Eio.Fiber.yield ();
      loop completed_bytes (chunk + 1))
  in
  loop 0 1
;;

let update_checksum checksum buffer length =
  let checksum = ref checksum in
  for index = 0 to length - 1 do
    checksum
    := Int64.add
         (Int64.mul !checksum 1_099_511_628_211L)
         (Int64.of_int (Cstruct.get_uint8 buffer index))
  done;
  !checksum
;;

let read_chunks source ~declared_total ~progress =
  if declared_total < 0 || declared_total > max_file_size
  then raise (File_limit "Demo file exceeds the 16 MiB read limit");
  let buffer = Cstruct.create chunk_size in
  let rec loop completed_bytes checksum =
    if completed_bytes = declared_total
    then { total_bytes = completed_bytes; checksum }
    else (
      let requested = Int.min chunk_size (declared_total - completed_bytes) in
      match Eio.Flow.single_read source (Cstruct.sub buffer 0 requested) with
      | read ->
        let completed_bytes = completed_bytes + read in
        let checksum = update_checksum checksum buffer read in
        progress { completed_bytes; total_bytes = declared_total };
        Eio.Fiber.yield ();
        loop completed_bytes checksum
      | exception End_of_file -> { total_bytes = completed_bytes; checksum })
  in
  loop 0 0L
;;

let remove_if_present path =
  Eio.Cancel.protect (fun () ->
    match Eio.Path.kind ~follow:false path with
    | `Not_found -> ()
    | _ -> Eio.Path.unlink path)
;;

let error_message exception_ =
  match exception_ with
  | Failure message | Invalid_argument message | File_limit message -> message
  | _ -> Printexc.to_string exception_
;;

let write_with_hook ~after_chunk ~sw:_ ~directory ~request_id ~total_bytes ~progress =
  match validate_size total_bytes with
  | Error _ as error -> error
  | Ok () ->
    let temporary_name =
      Printf.sprintf
        "eio-worker-demo.%Ld.tmp"
        (Bonsai_swiftui_spec.Id.Worker.Request_id.to_int64 request_id)
    in
    let temporary_path = Eio.Path.(directory / temporary_name) in
    let final_path = Eio.Path.(directory / file_name) in
    let renamed = ref false in
    (try
       Fun.protect
         ~finally:(fun () -> if not !renamed then remove_if_present temporary_path)
         (fun () ->
            Eio.Path.with_open_out
              ~create:(`Or_truncate 0o600)
              temporary_path
              (fun sink -> write_chunks ~after_chunk sink ~total_bytes ~progress);
            Eio.Path.rename temporary_path final_path;
            renamed := true);
       Ok ()
     with
     | Eio.Cancel.Cancelled _ as cancelled -> raise cancelled
     | exception_ -> Error (error_message exception_))
;;

let write = write_with_hook ~after_chunk:(fun _ -> ())

let read ~sw:_ ~directory ~progress =
  let path = Eio.Path.(directory / file_name) in
  try
    Eio.Path.with_open_in path (fun source ->
      let size = Eio.File.size source |> Optint.Int63.to_int64 in
      if Int64.compare size (Int64.of_int max_file_size) > 0
      then Error "Demo file exceeds the 16 MiB read limit"
      else (
        let declared_total = Int64.to_int size in
        Ok (read_chunks source ~declared_total ~progress)))
  with
  | Eio.Cancel.Cancelled _ as cancelled -> raise cancelled
  | exception_ -> Error (error_message exception_)
;;

module For_testing = struct
  let write_chunks sink ~total_bytes ~progress = write_chunks sink ~total_bytes ~progress

  let read_chunks source ~declared_total ~progress =
    read_chunks source ~declared_total ~progress
  ;;

  let write = write_with_hook
end
