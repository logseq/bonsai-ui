type control_message =
  | Attach of int
  | Detach

type next_action =
  | Control of control_message
  | Request of int
  | Final_stop

type diagnostics =
  { backend_run_count : int
  ; worker_domain_id : Domain.id option
  ; processed_requests : int list
  ; attached_session : int option
  ; session_attach_count : int
  ; idle_wait_count : int
  ; join_count : int
  }

type t =
  { requests : int Bounded_mailbox.Fifo.t
  ; wake : Eio.Condition.t
  ; final_stop : bool Atomic.t
  ; mutex : Mutex.t
  ; controls : control_message Queue.t
  ; mutable domain_handle : unit Domain.t option
  ; mutable started : bool
  ; mutable join_claimed : bool
  ; mutable backend_run_count : int
  ; mutable worker_domain_id : Domain.id option
  ; mutable processed_requests_reversed : int list
  ; mutable attached_session : int option
  ; mutable session_attach_count : int
  ; mutable idle_wait_count : int
  ; mutable join_count : int
  }

let create ~request_capacity =
  { requests = Bounded_mailbox.Fifo.create ~capacity:request_capacity
  ; wake = Eio.Condition.create ()
  ; final_stop = Atomic.make false
  ; mutex = Mutex.create ()
  ; controls = Queue.create ()
  ; domain_handle = None
  ; started = false
  ; join_claimed = false
  ; backend_run_count = 0
  ; worker_domain_id = None
  ; processed_requests_reversed = []
  ; attached_session = None
  ; session_attach_count = 0
  ; idle_wait_count = 0
  ; join_count = 0
  }
;;

let with_lock t run =
  Mutex.lock t.mutex;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.mutex) run
;;

let diagnostics t =
  with_lock t (fun () ->
    { backend_run_count = t.backend_run_count
    ; worker_domain_id = t.worker_domain_id
    ; processed_requests = List.rev t.processed_requests_reversed
    ; attached_session = t.attached_session
    ; session_attach_count = t.session_attach_count
    ; idle_wait_count = t.idle_wait_count
    ; join_count = t.join_count
    })
;;

let publish_control t message =
  with_lock t (fun () -> Queue.add message t.controls);
  Eio.Condition.broadcast t.wake
;;

let attach t session_id = publish_control t (Attach session_id)
let detach t = publish_control t Detach

let try_enqueue_request t request =
  let result = Bounded_mailbox.Fifo.try_push t.requests request in
  (match result with
   | `Ok -> Eio.Condition.broadcast t.wake
   | `Full | `Closed -> ());
  result
;;

let take_control t =
  with_lock t (fun () ->
    if Queue.is_empty t.controls then None else Some (Queue.take t.controls))
;;

let await_next t =
  Eio.Condition.loop_no_mutex t.wake (fun () ->
    if Atomic.get t.final_stop
    then Some Final_stop
    else (
      match take_control t with
      | Some control -> Some (Control control)
      | None ->
        (match Bounded_mailbox.Fifo.pop t.requests with
         | Some request -> Some (Request request)
         | None ->
           with_lock t (fun () -> t.idle_wait_count <- t.idle_wait_count + 1);
           None)))
;;

let record_control t = function
  | Attach session_id ->
    with_lock t (fun () ->
      t.attached_session <- Some session_id;
      t.session_attach_count <- t.session_attach_count + 1)
  | Detach -> with_lock t (fun () -> t.attached_session <- None)
;;

let record_request t request =
  with_lock t (fun () ->
    t.processed_requests_reversed <- request :: t.processed_requests_reversed)
;;

let run_supervisor t =
  let rec loop () =
    match await_next t with
    | Final_stop -> ()
    | Control control ->
      record_control t control;
      loop ()
    | Request request ->
      record_request t request;
      loop ()
  in
  loop ()
;;

let worker_entrypoint t =
  Eio_posix.run (fun _environment ->
    with_lock t (fun () ->
      t.backend_run_count <- t.backend_run_count + 1;
      t.worker_domain_id <- Some (Domain.self ()));
    run_supervisor t)
;;

let start t =
  with_lock t (fun () ->
    if Atomic.get t.final_stop
    then Error "Eio Worker backend is stopped"
    else if t.started
    then Error "Eio Worker backend is already started"
    else (
      let domain = Domain.spawn (fun () -> worker_entrypoint t) in
      t.domain_handle <- Some domain;
      t.started <- true;
      Ok ()))
;;

let final_shutdown t =
  Atomic.set t.final_stop true;
  Eio.Condition.broadcast t.wake;
  let domain =
    with_lock t (fun () ->
      if t.join_claimed
      then None
      else (
        t.join_claimed <- true;
        let domain = t.domain_handle in
        t.domain_handle <- None;
        domain))
  in
  Option.iter
    (fun domain ->
       Domain.join domain;
       with_lock t (fun () -> t.join_count <- t.join_count + 1))
    domain
;;
