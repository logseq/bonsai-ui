open Eio.Std

exception Request_cancelled

let chunk_size = 64 * 1024
let final_name = "eio-worker-demo.bin"

type report =
  { worker_domain_id : Domain.id
  ; timer_elapsed_seconds : float
  ; timer_peer_ran : bool
  ; socketpair_payload : string
  ; file_bytes : int
  ; write_chunks : int
  ; atomic_replace_removed_stale_contents : bool
  ; directory_escape_rejected : bool
  ; dns_address_count : int
  ; tcp_payload : string
  ; waiting_socket_cancelled : bool
  ; waiting_socket_closed : bool
  ; after_cancellation_payload : string
  }

let read_exact_string source length =
  let buffer = Cstruct.create length in
  Eio.Flow.read_exact source buffer;
  Cstruct.to_string buffer
;;

let socketpair_round_trip ~sw payload =
  let client, server = Eio_unix.Net.socketpair_stream ~sw () in
  let received = ref None in
  Eio.Fiber.both
    (fun () ->
       Eio.Flow.copy_string payload client;
       Eio.Flow.shutdown client `Send)
    (fun () -> received := Some (read_exact_string server (String.length payload)));
  Option.get !received
;;

let run_timer clock =
  let peer_ran = ref false in
  let started_at = Unix.gettimeofday () in
  Eio.Fiber.both (fun () -> Eio.Time.Mono.sleep clock 0.01) (fun () -> peer_ran := true);
  Unix.gettimeofday () -. started_at, !peer_ran
;;

let payload_chunk ~offset length =
  String.init length (fun index -> Char.chr ((offset + index) mod 251))
;;

let write_chunked sink payload_bytes =
  let rec loop offset chunks =
    if offset = payload_bytes
    then chunks
    else (
      let length = Int.min chunk_size (payload_bytes - offset) in
      Eio.Flow.copy_string (payload_chunk ~offset length) sink;
      Eio.Fiber.yield ();
      loop (offset + length) (chunks + 1))
  in
  loop 0 0
;;

let read_chunked source =
  let buffer = Cstruct.create chunk_size in
  let rec loop total =
    match Eio.Flow.single_read source buffer with
    | bytes ->
      Eio.Fiber.yield ();
      loop (total + bytes)
    | exception End_of_file -> total
  in
  loop 0
;;

let directory_escape_rejected directory =
  let outside = Eio.Path.(directory / "../outside-sentinel") in
  match Eio.Path.load outside with
  | _ -> false
  | (exception Eio.Io _) | (exception Invalid_argument _) -> true
;;

let run_file_operations fs ~directory ~payload_bytes =
  let root = Eio.Path.(fs / directory) in
  Eio.Path.with_open_dir root (fun confined ->
    let final = Eio.Path.(confined / final_name) in
    let temporary = Eio.Path.(confined / "eio-worker-demo.request.tmp") in
    Eio.Path.save ~create:(`Or_truncate 0o600) final "stale";
    let write_chunks =
      Eio.Path.with_open_out ~create:(`Or_truncate 0o600) temporary (fun sink ->
        write_chunked sink payload_bytes)
    in
    Eio.Path.rename temporary final;
    let file_bytes = Eio.Path.with_open_in final read_chunked in
    let replaced = Eio.Path.load final <> "stale" in
    file_bytes, write_chunks, replaced, directory_escape_rejected confined)
;;

let run_tcp net =
  Eio.Switch.run (fun sw ->
    let listener =
      Eio.Net.listen
        ~reuse_addr:true
        ~backlog:1
        ~sw
        net
        (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
    in
    let address = Eio.Net.listening_addr listener in
    let request = "tcp-loopback-request" in
    let response = "tcp-loopback-ready" in
    let server_request, client_response =
      Eio.Fiber.pair
        (fun () ->
           let connection, _client_address = Eio.Net.accept ~sw listener in
           let received = read_exact_string connection (String.length request) in
           Eio.Flow.copy_string response connection;
           Eio.Flow.shutdown connection `Send;
           received)
        (fun () ->
           let connection = Eio.Net.connect ~sw net address in
           Eio.Flow.copy_string request connection;
           Eio.Flow.shutdown connection `Send;
           read_exact_string connection (String.length response))
    in
    if server_request <> request
    then failwith "loopback TCP server received an unexpected request";
    client_response)
;;

let cancel_waiting_socket clock =
  let waiting_fd = ref None in
  let cancelled =
    try
      Eio.Time.Timeout.run_exn (Eio.Time.Timeout.seconds clock 0.5) (fun () ->
        Eio.Switch.run (fun request_switch ->
          let waiting_socket, _peer =
            Eio_unix.Net.socketpair_stream ~sw:request_switch ()
          in
          waiting_fd := Some (Eio_unix.Resource.fd waiting_socket);
          let waiting_started, resolve_waiting_started = Eio.Promise.create () in
          Eio.Fiber.fork ~sw:request_switch (fun () ->
            Eio.Promise.resolve resolve_waiting_started ();
            ignore (read_exact_string waiting_socket 1 : string));
          Eio.Promise.await waiting_started;
          Eio.Fiber.yield ();
          Eio.Switch.fail request_switch Request_cancelled));
      false
    with
    | Request_cancelled -> true
  in
  let closed =
    match !waiting_fd with
    | None -> false
    | Some fd -> not (Eio_unix.Fd.is_open fd)
  in
  cancelled, closed
;;

let run_on_worker_domain ~directory ~payload_bytes () =
  Eio_posix.run (fun environment ->
    let timer_elapsed_seconds, timer_peer_ran = run_timer environment#mono_clock in
    let socketpair_payload =
      Eio.Switch.run (fun sw -> socketpair_round_trip ~sw "socketpair-ready")
    in
    let file_bytes, write_chunks, replaced, escape_rejected =
      run_file_operations environment#fs ~directory ~payload_bytes
    in
    let dns_address_count =
      Eio.Net.getaddrinfo_stream ~service:"80" environment#net "localhost" |> List.length
    in
    let tcp_payload = run_tcp environment#net in
    let waiting_socket_cancelled, waiting_socket_closed =
      cancel_waiting_socket environment#mono_clock
    in
    let after_cancellation_payload =
      Eio.Switch.run (fun sw -> socketpair_round_trip ~sw "session-still-usable")
    in
    { worker_domain_id = Domain.self ()
    ; timer_elapsed_seconds
    ; timer_peer_ran
    ; socketpair_payload
    ; file_bytes
    ; write_chunks
    ; atomic_replace_removed_stale_contents = replaced
    ; directory_escape_rejected = escape_rejected
    ; dns_address_count
    ; tcp_payload
    ; waiting_socket_cancelled
    ; waiting_socket_closed
    ; after_cancellation_payload
    })
;;

let run ~directory ~payload_bytes =
  Domain.spawn (run_on_worker_domain ~directory ~payload_bytes) |> Domain.join
;;
