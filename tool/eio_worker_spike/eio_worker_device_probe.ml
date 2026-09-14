module Backend = Eio_worker_backend_spike
module Provider = Eio_worker_provider_spike

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let rec wait_until ~deadline predicate =
  if predicate ()
  then ()
  else if Unix.gettimeofday () >= deadline
  then fail "timed out waiting for the Eio Worker backend"
  else (
    Unix.sleepf 0.001;
    wait_until ~deadline predicate)
;;

let verify_backend () =
  let domain0 = Domain.self () in
  let backend = Backend.create ~request_capacity:2 in
  require
    (Backend.try_enqueue_request backend 41 = `Ok)
    "request could not be queued before backend startup";
  (match Backend.start backend with
   | Ok () -> ()
   | Error message -> fail "backend did not start: %s" message);
  (match Backend.start backend with
   | Error _ -> ()
   | Ok () -> fail "backend started more than once");
  Backend.attach backend 7;
  let deadline = Unix.gettimeofday () +. 3.0 in
  wait_until ~deadline (fun () ->
    let diagnostics = Backend.diagnostics backend in
    diagnostics.processed_requests = [ 41 ]
    && diagnostics.attached_session = Some 7
    && diagnostics.idle_wait_count > 0);
  Backend.detach backend;
  Backend.final_shutdown backend;
  Backend.final_shutdown backend;
  let diagnostics = Backend.diagnostics backend in
  require (diagnostics.backend_run_count = 1) "backend loop did not run exactly once";
  require
    (diagnostics.worker_domain_id <> Some domain0)
    "backend loop ran on OCaml domain 0";
  require (diagnostics.join_count = 1) "backend Domain was not joined exactly once";
  diagnostics
;;

let verify_provider directory =
  let payload_bytes = (2 * Provider.chunk_size) + 17 in
  let report = Provider.run ~directory ~payload_bytes in
  require report.timer_peer_ran "timer sleep blocked its peer fiber";
  require
    (report.timer_elapsed_seconds >= 0.005 && report.timer_elapsed_seconds < 1.0)
    "timer duration was outside the bounded range";
  require
    (report.socketpair_payload = "socketpair-ready")
    "socketpair payload was incorrect";
  require (report.file_bytes = payload_bytes) "chunked file length was incorrect";
  require (report.write_chunks = 3) "chunked write count was incorrect";
  require
    report.atomic_replace_removed_stale_contents
    "atomic rename did not replace stale contents";
  require report.directory_escape_rejected "confined directory allowed parent traversal";
  require (report.dns_address_count > 0) "localhost DNS lookup returned no addresses";
  require (report.tcp_payload = "tcp-loopback-ready") "TCP loopback payload was incorrect";
  require report.waiting_socket_cancelled "waiting socket request was not cancelled";
  require report.waiting_socket_closed "cancelled waiting socket remained open";
  require
    (report.after_cancellation_payload = "session-still-usable")
    "provider was unusable after request cancellation";
  report
;;

let run_checks ~directory =
  let domain0 = Domain.self () in
  let backend = verify_backend () in
  let provider = verify_provider directory in
  require
    (provider.worker_domain_id <> domain0)
    "provider operations ran on OCaml domain 0";
  Printf.sprintf
    "OK backend_runs=%d joins=%d file_bytes=%d chunks=%d dns=%d"
    backend.backend_run_count
    backend.join_count
    provider.file_bytes
    provider.write_chunks
    provider.dns_address_count
;;

let run ~directory =
  match run_checks ~directory with
  | result -> result
  | exception exn -> "FAIL " ^ Printexc.to_string exn
;;

let () = Callback.register "bonsai_swiftui.eio_worker_device_probe" run
