(** A renderer-independent Bonsai application.

    An [App.t] contains the OCaml application and can be started by the native runtime or
    by [bonsai_swiftui_test]. *)

module Context : sig
  type t = Driver.Handler.t

  val environment : t -> Environment.snapshot Bonsai.Cont.t
  val host_effects : t -> Host_effect.t
  val application_platform : t -> Host_effect.Application_platform.t

  val event_handler
    :  t
    -> ?name:string
    -> equal:('dependencies -> 'dependencies -> bool)
    -> 'dependencies Bonsai.Cont.t
    -> f:('dependencies -> Bonsai_swiftui_ui.Event.Payload.t -> unit Bonsai.Effect.t)
    -> Bonsai_swiftui_ui.Event.Handler.t Bonsai.Cont.t

  val native_event_handler
    :  t
    -> ?name:string
    -> ('props, 'event) Bonsai_swiftui_ui.Native_widget.Extension.t
    -> equal:('dependencies -> 'dependencies -> bool)
    -> 'dependencies Bonsai.Cont.t
    -> f:('dependencies -> 'event -> unit Bonsai.Effect.t)
    -> Bonsai_swiftui_ui.Event.Handler.t Bonsai.Cont.t
end

type t

module View = Driver.View

val create
  :  ?name:string
       (** [trace], when supplied, receives runtime diagnostic messages. Trace sink
      failures are ignored so diagnostics cannot interrupt rendering. *)
  -> ?trace:(string -> unit)
  -> (Context.t -> Bonsai.Cont.graph -> View.t Bonsai.Cont.t)
  -> t

(** Creates a runtime-scoped worker-backed application. [decode_config] runs
    on domain 0. Service callbacks and service state run only on the singleton
    OCaml Worker Domain, while [component] and event subscribers remain on
    domain 0. *)
val create_with_worker
  :  ?name:string
  -> ?trace:(string -> unit)
  -> decode_config:(bytes -> ('config, string) result)
  -> service:('config, 'request, 'response, 'push) Worker.Service.t
  -> (('request, 'response, 'push) Worker.client
      -> Context.t
      -> Bonsai.Cont.graph
      -> View.t Bonsai.Cont.t)
  -> t

val name : t -> string option

module Private : sig
  type instance

  val instantiate
    :  t
    -> runtime_epoch:Bonsai_swiftui_spec.Id.Runtime.epoch
    -> application_payload:bytes
    -> (instance, string) result

  val component
    :  instance
    -> Driver.Handler.t
    -> Bonsai.Cont.graph
    -> View.t Bonsai.Cont.t

  val trace : t -> (string -> unit) option
  val before_flush : instance -> schedule:(unit Bonsai.Effect.t -> unit) -> unit
  val shutdown : instance -> unit
end
