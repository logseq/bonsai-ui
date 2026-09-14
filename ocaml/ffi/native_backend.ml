module Protocol = Bonsai_swiftui_protocol
module ID = Bonsai_swiftui_spec.Id

external ensure_native_bridge_linked : unit -> unit = "bs_native_embed_link_anchor"

let embed ~name app =
  Entrypoint.register ~name app;
  ensure_native_bridge_linked ()
;;

type status =
  | Ok
  | Recoverable_error
  | Fatal_error

type create_result =
  { status : status
  ; handle : ID.Runtime.handle
  ; error : string
  }

type output =
  { status : status
  ; bytes : bytes
  ; presentation_id : ID.Runtime.presentation_id
  ; revision : ID.Runtime.renderer_revision
  ; error_code : ID.Ffi.error_code
  ; error : string
  }

type active_runtime =
  { handle : ID.Runtime.handle
  ; driver : Driver.t
  }

type runtime_slot =
  | Empty
  | Creating
  | Active of active_runtime
  | Destroying of active_runtime
  | Finalized

type state_tag =
  | Empty_tag
  | Creating_tag
  | Active_tag
  | Destroying_tag
  | Finalized_tag

let runtime_slot = ref Empty
let next_handle = ref ID.Runtime.Handle.one
let recorded_state_history = ref []
let driver_creations = ref 0
let driver_shutdowns = ref 0
let active_drivers = ref 0
let peak_active_drivers = ref 0

let state_tag = function
  | Empty -> Empty_tag
  | Creating -> Creating_tag
  | Active _ -> Active_tag
  | Destroying _ -> Destroying_tag
  | Finalized -> Finalized_tag
;;

let transition state =
  runtime_slot := state;
  recorded_state_history := state_tag state :: !recorded_state_history
;;

let status_code = function
  | Ok -> 0
  | Recoverable_error -> 1
  | Fatal_error -> 2
;;

let create_error error = { status = Fatal_error; handle = ID.Runtime.Handle.zero; error }

let output
      ?(status = Ok)
      ?(bytes = Bytes.empty)
      ?(presentation_id = ID.Runtime.Presentation_id.zero)
      ?(revision = ID.Runtime.Renderer_revision.zero)
      ?(error_code = 0)
      ?(error = "")
      ()
  =
  { status
  ; bytes
  ; presentation_id
  ; revision
  ; error_code = ID.Ffi.Error_code.of_int error_code
  ; error
  }
;;

let fresh_handle () =
  let handle = !next_handle in
  if ID.Runtime.Handle.equal handle ID.Runtime.Handle.max_value
  then failwith "Runtime handle space is exhausted"
  else next_handle := ID.Runtime.Handle.succ handle;
  handle
;;

let exception_message exception_ =
  let message =
    match exception_ with
    | Failure message | Invalid_argument message -> message
    | _ -> Printexc.to_string exception_
  in
  let backtrace = Printexc.get_backtrace () in
  if String.length backtrace = 0 then message else message ^ "\n" ^ backtrace
;;

let () = Printexc.record_backtrace true

let shutdown_driver ?application_error runtime =
  Driver.shutdown ?application_error runtime.driver;
  incr driver_shutdowns;
  decr active_drivers
;;

let destroy_active ?application_error runtime =
  transition (Destroying runtime);
  shutdown_driver ?application_error runtime;
  transition Empty
;;

let create_in_empty config =
  transition Creating;
  try
    match Entrypoint.Private.find config.Runtime_bootstrap_config.entrypoint with
    | None ->
      transition Empty;
      create_error
        ("Unknown OCaml entrypoint: "
         ^ ID.Application.Entrypoint_name.to_string config.entrypoint)
    | Some app ->
      let handle = fresh_handle () in
      let runtime_epoch =
        handle |> ID.Runtime.Handle.to_int64 |> ID.Runtime.Epoch.of_int64
      in
      (match
         App.Private.instantiate
           app
           ~runtime_epoch
           ~application_payload:config.application_payload
       with
       | Error error ->
         transition Empty;
         create_error error
       | Ok instance ->
         let time_source = Bonsai.Time_source.create ~start:(Core.Time_ns.now ()) in
         let driver =
           try
             Driver.create
               ?trace:(App.Private.trace app)
               ~before_flush:(App.Private.before_flush instance)
               ~before_shutdown:(fun () -> App.Private.shutdown instance)
               ?application_title:(App.name app)
               ~runtime_epoch
               ~time_source
               (App.Private.component instance)
           with
           | exception_ ->
             App.Private.shutdown instance;
             raise exception_
         in
         incr driver_creations;
         incr active_drivers;
         peak_active_drivers := Int.max !peak_active_drivers !active_drivers;
         transition (Active { handle; driver });
         { status = Ok; handle; error = "" })
  with
  | exception_ ->
    transition Empty;
    create_error (exception_message exception_)
;;

let create config =
  try
    match !runtime_slot with
    | Finalized -> create_error "Runtime_stopped"
    | Creating | Destroying _ -> create_error "Runtime_busy"
    | Empty | Active _ ->
      (match Runtime_bootstrap_config.decode config with
       | Error error -> create_error error
       | Ok config ->
         (match !runtime_slot, config.launch_policy with
          | Active _, Runtime_bootstrap_config.Fresh ->
            create_error "Runtime_already_active"
          | Active runtime, Replace_existing ->
            destroy_active
              ~application_error:Host_effect.Application_platform.Runtime_replaced
              runtime;
            create_in_empty config
          | Empty, _ -> create_in_empty config
          | Creating, _ | Destroying _, _ | Finalized, _ -> assert false))
  with
  | exception_ -> create_error (exception_message exception_)
;;

let driver_error_metadata error =
  let status, error_code =
    match error with
    | Driver.Event_error
        (Bonsai_swiftui_runtime.Event_dispatcher.Handler_error
           (Bonsai_swiftui_runtime.Runtime_error.Duplicate_key _))
    | Runtime_error (Bonsai_swiftui_runtime.Runtime_error.Duplicate_key _) ->
      Fatal_error, 3
    | Driver.Event_error
        (Bonsai_swiftui_runtime.Event_dispatcher.Handler_error runtime_error)
    | Runtime_error runtime_error ->
      let error_code =
        match runtime_error with
        | Bonsai_swiftui_runtime.Runtime_error.Duplicate_key _ -> 3
        | Revision_mismatch _ -> 2
        | Stale_event _ | Duplicate_or_out_of_order_event _ -> 7
        | Handler_missing _ | Handler_mismatch _ -> 6
        | Handler_exception _ -> 9
        | Invalid_patch _ | Wrong_runtime_epoch _ -> 1
      in
      Recoverable_error, error_code
    | Event_error (Invalid_event _) -> Recoverable_error, 1
    | Codec_error _ -> Fatal_error, 1
    | Unsupported_widget _ -> Fatal_error, 4
    | Invalid_state message ->
      if Core.String.is_substring message ~substring:"monotonic"
      then Recoverable_error, 14
      else if Core.String.is_substring message ~substring:"presentation"
      then Recoverable_error, 13
      else Fatal_error, 15
    | Lifecycle_error _ -> Fatal_error, 11
    | Host_response_error _ -> Fatal_error, 8
    | Application_platform_error _ -> Recoverable_error, 8
    | Shutdown -> Fatal_error, 9
  in
  status, error_code, Driver.error_to_string error
;;

let driver_error error =
  let status, error_code, error = driver_error_metadata error in
  output ~status ~error_code ~error ()
;;

let find_runtime handle =
  match !runtime_slot with
  | Active runtime when ID.Runtime.Handle.equal runtime.handle handle ->
    Result.Ok runtime.driver
  | Empty | Creating | Active _ | Destroying _ | Finalized ->
    Result.Error
      (output ~status:Fatal_error ~error_code:9 ~error:"Unknown native runtime handle" ())
;;

let pump handle monotonic_now_ns input =
  try
    match find_runtime handle with
    | Result.Error output -> output
    | Result.Ok driver ->
      let decoded_events, decode_error =
        if Bytes.length input = 0
        then None, None
        else (
          match Protocol.Event_batch_codec.decode input with
          | Result.Ok events -> Some events, None
          | Result.Error error ->
            ( None
            , Some
                (Driver.Event_error
                   (Bonsai_swiftui_runtime.Event_dispatcher.Invalid_event error.message))
            ))
      in
      let result =
        match decoded_events with
        | None -> Driver.pump driver ~monotonic_now_ns ()
        | Some events -> Driver.pump driver ~monotonic_now_ns ~events ()
      in
      (match result with
       | Result.Error error -> driver_error error
       | Result.Ok result ->
         let recoverable_error =
           match decode_error with
           | Some error -> Some error
           | None -> result.recoverable_error
         in
         let bytes =
           match result.frame with
           | None -> Bytes.empty
           | Some frame -> frame.bytes
         in
         (match recoverable_error with
          | None ->
            output
              ~bytes
              ~presentation_id:result.presentation_id
              ~revision:result.renderer_revision
              ()
          | Some error ->
            let _, error_code, error = driver_error_metadata error in
            output
              ~status:Recoverable_error
              ~bytes
              ~presentation_id:result.presentation_id
              ~revision:result.renderer_revision
              ~error_code
              ~error
              ()))
  with
  | exception_ ->
    output ~status:Fatal_error ~error_code:9 ~error:(exception_message exception_) ()
;;

let presentation_succeeded handle presentation_id revision monotonic_now_ns =
  try
    match find_runtime handle with
    | Result.Error output -> output
    | Result.Ok driver ->
      (match
         Driver.presentation_succeeded
           driver
           ~presentation_id
           ~renderer_revision:revision
           ~monotonic_now_ns
       with
       | Result.Ok () -> output ()
       | Result.Error error -> driver_error error)
  with
  | exception_ ->
    output ~status:Fatal_error ~error_code:9 ~error:(exception_message exception_) ()
;;

let rejection_reason = function
  | 0 -> Result.Ok Driver.Decode_failed
  | 1 -> Result.Ok Driver.Frame_validation_failed
  | 2 -> Result.Ok Driver.Renderer_epoch_mismatch
  | 3 -> Result.Ok Driver.Renderer_revision_mismatch
  | _ -> Result.Error "Unknown presentation rejection reason"
;;

let presentation_rejected handle presentation_id revision reason =
  try
    match find_runtime handle with
    | Result.Error output -> output
    | Result.Ok driver ->
      (match rejection_reason reason with
       | Result.Error error -> output ~status:Recoverable_error ~error_code:13 ~error ()
       | Result.Ok reason ->
         (match
            Driver.presentation_rejected
              driver
              ~presentation_id
              ~renderer_revision:revision
              ~reason
          with
          | Result.Ok () -> output ()
          | Result.Error error -> driver_error error))
  with
  | exception_ ->
    output ~status:Fatal_error ~error_code:9 ~error:(exception_message exception_) ()
;;

let destroy handle =
  match !runtime_slot with
  | Active runtime when ID.Runtime.Handle.equal runtime.handle handle ->
    destroy_active runtime
  | Empty | Creating | Active _ | Destroying _ | Finalized -> ()
;;

module For_testing = struct
  type runtime_state =
    | Empty
    | Creating
    | Active
    | Destroying
    | Finalized

  type observations =
    { driver_creations : int
    ; driver_shutdowns : int
    ; active_drivers : int
    ; peak_active_drivers : int
    }

  let runtime_state = function
    | Empty_tag -> Empty
    | Creating_tag -> Creating
    | Active_tag -> Active
    | Destroying_tag -> Destroying
    | Finalized_tag -> Finalized
  ;;

  let state () = state_tag !runtime_slot |> runtime_state
  let state_history () = List.rev_map runtime_state !recorded_state_history

  let runtime_count () =
    match !runtime_slot with
    | Active _ | Destroying _ -> 1
    | Empty | Creating | Finalized -> 0
  ;;

  let observations () =
    { driver_creations = !driver_creations
    ; driver_shutdowns = !driver_shutdowns
    ; active_drivers = !active_drivers
    ; peak_active_drivers = !peak_active_drivers
    }
  ;;

  let reset_observations () =
    let current_active_drivers =
      match !runtime_slot with
      | Active _ | Destroying _ -> 1
      | Empty | Creating | Finalized -> 0
    in
    driver_creations := 0;
    driver_shutdowns := 0;
    active_drivers := current_active_drivers;
    peak_active_drivers := current_active_drivers
  ;;

  let clear_state_history () = recorded_state_history := []

  let final_shutdown () =
    match !runtime_slot with
    | Finalized -> ()
    | Creating | Destroying _ -> failwith "Runtime_busy"
    | Active runtime ->
      destroy_active runtime;
      transition Finalized;
      Worker_runtime.For_testing.final_shutdown ()
    | Empty ->
      transition Finalized;
      Worker_runtime.For_testing.final_shutdown ()
  ;;
end

let callback_create config =
  let result = create (Bytes.of_string config) in
  status_code result.status, ID.Runtime.Handle.to_int64 result.handle, result.error
;;

let callback_pump handle monotonic_now_ns input =
  let result =
    pump (ID.Runtime.Handle.of_int64 handle) monotonic_now_ns (Bytes.of_string input)
  in
  ( status_code result.status
  , Bytes.to_string result.bytes
  , ID.Runtime.Presentation_id.to_int64 result.presentation_id
  , ID.Runtime.Renderer_revision.to_int64 result.revision
  , ID.Ffi.Error_code.to_int result.error_code
  , result.error )
;;

let callback_presentation_succeeded handle presentation_id revision monotonic_now_ns =
  let result =
    presentation_succeeded
      (ID.Runtime.Handle.of_int64 handle)
      (ID.Runtime.Presentation_id.of_int64 presentation_id)
      (ID.Runtime.Renderer_revision.of_int64 revision)
      monotonic_now_ns
  in
  ( status_code result.status
  , Bytes.to_string result.bytes
  , ID.Runtime.Presentation_id.to_int64 result.presentation_id
  , ID.Runtime.Renderer_revision.to_int64 result.revision
  , ID.Ffi.Error_code.to_int result.error_code
  , result.error )
;;

let callback_presentation_rejected handle presentation_id revision reason =
  let result =
    presentation_rejected
      (ID.Runtime.Handle.of_int64 handle)
      (ID.Runtime.Presentation_id.of_int64 presentation_id)
      (ID.Runtime.Renderer_revision.of_int64 revision)
      reason
  in
  ( status_code result.status
  , Bytes.to_string result.bytes
  , ID.Runtime.Presentation_id.to_int64 result.presentation_id
  , ID.Runtime.Renderer_revision.to_int64 result.revision
  , ID.Ffi.Error_code.to_int result.error_code
  , result.error )
;;

let callback_destroy handle = destroy (ID.Runtime.Handle.of_int64 handle)

let () =
  Callback.register "bonsai_swiftui.create" callback_create;
  Callback.register "bonsai_swiftui.pump" callback_pump;
  Callback.register
    "bonsai_swiftui.presentation_succeeded"
    callback_presentation_succeeded;
  Callback.register "bonsai_swiftui.presentation_rejected" callback_presentation_rejected;
  Callback.register "bonsai_swiftui.destroy" callback_destroy
;;
