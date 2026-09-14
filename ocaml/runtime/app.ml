module Context = struct
  type t = Driver.Handler.t

  let environment context = Driver.Handler.environment context |> Environment.value
  let host_effects = Driver.Handler.host_effects
  let application_platform = Driver.Handler.application_platform
  let event_handler = Driver.Handler.create
  let native_event_handler = Driver.Handler.create_native
end

module View = Driver.View

type component = Context.t -> Bonsai.Cont.graph -> View.t Bonsai.Cont.t

type t =
  | Ui_only of
      { name : string option
      ; trace : (string -> unit) option
      ; component : component
      }
  | Worker_backed :
      { name : string option
      ; trace : (string -> unit) option
      ; decode_config : bytes -> ('config, string) result
      ; service : ('config, 'request, 'response, 'push) Worker.Service.t
      ; component :
          ('request, 'response, 'push) Worker.client
          -> Context.t
          -> Bonsai.Cont.graph
          -> View.t Bonsai.Cont.t
      }
      -> t

let validate_name = function
  | None -> ()
  | Some name ->
    if String.length name = 0 then invalid_arg "App.create: name must not be empty";
    if String.contains name '\000'
    then invalid_arg "App.create: name must not contain NUL"
;;

let create ?name ?trace component =
  validate_name name;
  Ui_only { name; trace; component }
;;

let create_with_worker ?name ?trace ~decode_config ~service component =
  validate_name name;
  Worker_backed { name; trace; decode_config; service; component }
;;

let name = function
  | Ui_only app -> app.name
  | Worker_backed app -> app.name
;;

module Private = struct
  type instance =
    { component : component
    ; before_flush : schedule:(unit Bonsai.Effect.t -> unit) -> unit
    ; shutdown : unit -> unit
    }

  let trace = function
    | Ui_only app -> app.trace
    | Worker_backed app -> app.trace
  ;;

  let instantiate t ~runtime_epoch ~application_payload =
    match t with
    | Ui_only app ->
      Ok
        { component = app.component
        ; before_flush = (fun ~schedule:_ -> ())
        ; shutdown = (fun () -> ())
        }
    | Worker_backed app ->
      (match app.decode_config application_payload with
       | Error _ as error -> error
       | Ok config ->
         (match Worker_runtime.start ~runtime_epoch app.service config with
          | Error _ as error -> error
          | Ok client ->
            Ok
              { component = app.component client
              ; before_flush =
                  (fun ~schedule ->
                    Worker.Private.drain_to_effects client ~max_events:64 ~schedule)
              ; shutdown = (fun () -> Worker_runtime.stop client)
              }))
  ;;

  let component instance = instance.component
  let before_flush instance = instance.before_flush
  let shutdown instance = instance.shutdown ()
end
