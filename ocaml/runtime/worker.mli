(** Typed domain-0 client and Worker Domain service contract. *)

type mono_clock = Eio.Time.Mono.ty Eio.Resource.t
type net = [ `Generic ] Eio.Net.ty Eio.Resource.t
type data_dir = Eio.Fs.dir_ty Eio.Path.t
type environment = Worker_eio_backend.environment

module Session_context : sig
  type 'push t

  val switch : 'push t -> Eio.Switch.t
  val environment : 'push t -> environment
  val clock : 'push t -> mono_clock
  val net : 'push t -> net
  val data_dir : 'push t -> data_dir option
  val emit : 'push t -> topic:Bonsai_swiftui_spec.Id.Worker.push_topic -> 'push -> unit
  val fork_daemon : 'push t -> name:string -> (unit -> unit) -> unit
end

module Request_context : sig
  type 'push t

  val request_id : 'push t -> Bonsai_swiftui_spec.Id.Worker.request_id
  val switch : 'push t -> Eio.Switch.t
  val environment : 'push t -> environment
  val clock : 'push t -> mono_clock
  val net : 'push t -> net
  val data_dir : 'push t -> data_dir option
  val emit : 'push t -> topic:Bonsai_swiftui_spec.Id.Worker.push_topic -> 'push -> unit
end

type 'response outcome =
  | Completed of 'response
  | Failed of string
  | Cancelled
  | Shutdown

type ('response, 'push) event =
  | Response of
      { runtime_epoch : Bonsai_swiftui_spec.Id.Runtime.epoch
      ; worker_generation : Bonsai_swiftui_spec.Id.Worker.generation
      ; request_id : Bonsai_swiftui_spec.Id.Worker.request_id
      ; outcome : 'response outcome
      }
  | Push of
      { runtime_epoch : Bonsai_swiftui_spec.Id.Runtime.epoch
      ; worker_generation : Bonsai_swiftui_spec.Id.Worker.generation
      ; push_sequence : Bonsai_swiftui_spec.Id.Worker.push_sequence
      ; topic : Bonsai_swiftui_spec.Id.Worker.push_topic
      ; payload : 'push
      }
  | Terminal of
      { runtime_epoch : Bonsai_swiftui_spec.Id.Runtime.epoch
      ; worker_generation : Bonsai_swiftui_spec.Id.Worker.generation
      ; error : string
      }

type send_result =
  | Accepted of Bonsai_swiftui_spec.Id.Worker.request_id
  | Full
  | Not_ready
  | Stopping

type ('request, 'response, 'push) client

module Service : sig
  type concurrency =
    | Serial
    | Concurrent of { max_in_flight : int }

  type ('config, 'request, 'response, 'push) t

  val create
    :  push_topic_count:int
    -> concurrency:concurrency
    -> ?data_directory:('config -> (string, string) result)
    -> init:('push Session_context.t -> 'config -> ('state, string) result)
    -> handle:
         ('push Request_context.t -> 'state -> 'request -> ('response, string) result)
    -> shutdown:('state -> unit)
    -> unit
    -> ('config, 'request, 'response, 'push) t
end

(** Non-blocking domain-0 request enqueue. *)
val send : ('request, 'response, 'push) client -> 'request -> send_result

(** Requests cooperative cancellation without entering the bounded request
    lane. *)
val cancel
  :  ('request, 'response, 'push) client
  -> request_id:Bonsai_swiftui_spec.Id.Worker.request_id
  -> unit

(** Registers a domain-0-only effect handler. The handler is invoked only by a
    later accepted Driver pump. *)
val on_event
  :  ('request, 'response, 'push) client
  -> (('response, 'push) event -> unit Bonsai.Effect.t)
  -> unit

val runtime_epoch
  :  ('request, 'response, 'push) client
  -> Bonsai_swiftui_spec.Id.Runtime.epoch

val worker_generation
  :  ('request, 'response, 'push) client
  -> Bonsai_swiftui_spec.Id.Worker.generation

module Private : sig
  type packed_startup
  type packed_client

  type metrics =
    { configured_concurrency_limit : int
    ; queued_requests : int
    ; active_request_fibers : int
    ; waiting_request_fibers : int
    ; active_handlers : int
    ; peak_active_handlers : int
    ; active_background_fibers : int
    ; peak_active_background_fibers : int
    ; request_queue_wait_count : int
    ; max_request_queue_wait_ns : int64
    ; handler_wall_count : int
    ; max_handler_wall_ns : int64
    ; cancellation_unwind_count : int
    ; max_cancellation_unwind_ns : int64
    ; session_cancellation_duration_ns : int64 option
    ; shutdown_duration_ns : int64 option
    }

  type run_result =
    | Session_stopped
    | Session_startup_failed of string
    | Session_callback_failed of string

  val prepare
    :  runtime_epoch:Bonsai_swiftui_spec.Id.Runtime.epoch
    -> worker_generation:Bonsai_swiftui_spec.Id.Worker.generation
    -> ('config, 'request, 'response, 'push) Service.t
    -> 'config
    -> ('request, 'response, 'push) client * packed_startup

  val run_session
    :  packed_startup
    -> environment:Worker_eio_backend.environment
    -> session_switch:Eio.Switch.t
    -> on_startup:((unit, string) result -> unit)
    -> on_idle_wait:(unit -> unit)
    -> on_yield:(unit -> unit)
    -> run_result

  val pack_client : ('request, 'response, 'push) client -> packed_client
  val metrics : packed_client -> metrics
  val request_stop : ('request, 'response, 'push) client -> unit
  val request_stop_packed : packed_client -> unit
  val await_stopped : ('request, 'response, 'push) client -> unit
  val await_stopped_packed : packed_client -> unit
  val fail_unrecoverable : packed_client -> string -> unit

  val drain_to_effects
    :  ('request, 'response, 'push) client
    -> max_events:int
    -> schedule:(unit Bonsai.Effect.t -> unit)
    -> unit
end

module For_testing : sig
  val drain_events
    :  ('request, 'response, 'push) client
    -> max_events:int
    -> ('response, 'push) event list

  val await_output : ('request, 'response, 'push) client -> unit
  val pending_output_count : ('request, 'response, 'push) client -> int
  val is_stopping : ('request, 'response, 'push) client -> bool

  val inject_push
    :  ('request, 'response, 'push) client
    -> runtime_epoch:Bonsai_swiftui_spec.Id.Runtime.epoch
    -> worker_generation:Bonsai_swiftui_spec.Id.Worker.generation
    -> push_sequence:Bonsai_swiftui_spec.Id.Worker.push_sequence
    -> topic:Bonsai_swiftui_spec.Id.Worker.push_topic
    -> 'push
    -> unit
end
