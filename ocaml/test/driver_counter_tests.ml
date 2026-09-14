module Protocol = Bonsai_swiftui_protocol
module Runtime = Bonsai_swiftui_runtime
module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let require_substring output substring message =
  require (Core.String.is_substring output ~substring) message
;;

let require_no_substring output substring message =
  require (not (Core.String.is_substring output ~substring)) message
;;

let ok = function
  | Ok value -> value
  | Error error -> fail "unexpected driver error: %s" (Driver.error_to_string error)
;;

let next_monotonic_ns = ref 0L
let pending_presentations : (Driver.t, Driver.pump_result) Hashtbl.t = Hashtbl.create 8

let pump_result driver ?events () =
  let monotonic_now_ns = !next_monotonic_ns in
  next_monotonic_ns := Int64.succ monotonic_now_ns;
  match Driver.pump driver ~monotonic_now_ns ?events () with
  | Error _ as error -> error
  | Ok result ->
    Hashtbl.replace pending_presentations driver result;
    Ok result
;;

let pump driver ?events () =
  Result.map (fun result -> result.Driver.frame) (pump_result driver ?events ())
;;

let present driver ~revision =
  match Hashtbl.find_opt pending_presentations driver with
  | None -> Error (Driver.Invalid_state "test has no pending presentation")
  | Some result ->
    if not (ID.Runtime.Renderer_revision.equal revision result.renderer_revision)
    then Error (Driver.Invalid_state "test supplied the wrong renderer revision")
    else (
      Hashtbl.remove pending_presentations driver;
      Driver.presentation_succeeded
        driver
        ~presentation_id:result.presentation_id
        ~renderer_revision:result.renderer_revision
        ~monotonic_now_ns:!next_monotonic_ns)
;;

let decode_frame bytes =
  match Protocol.Binary_codec.decode bytes with
  | Ok frame -> frame
  | Error error -> fail "frame did not decode: %s" error.message
;;

let semantic_operations (frame : Protocol.Wire_frame.t) =
  let stats =
    List.filter_map
      (function
        | Protocol.Wire_frame.Runtime_stats stats -> Some stats
        | _ -> None)
      frame.operations
  in
  (match stats with
   | [ stats ] ->
     require (stats.patch_count = List.length frame.operations - 1) "invalid patch count";
     require (stats.patch_bytes > 0) "missing patch byte count"
   | _ -> fail "frame must contain exactly one runtime stats operation");
  List.filter
    (function
      | Protocol.Wire_frame.Runtime_stats _ -> false
      | Set_application_theme _ -> false
      | _ -> true)
    frame.operations
;;

let default_application_theme =
  Ui.Theme.create ~tint:(Ui.Style.Color.rgb ~red:103 ~green:80 ~blue:164) ()
;;

let create_driver ?trace ~runtime_epoch ~time_source component =
  Driver.create ?trace ~runtime_epoch ~time_source (fun handlers graph ->
    Bonsai.Cont.map (component handlers graph) ~f:(fun body ->
      Driver.View.create ~theme:default_application_theme ~body:(Ui.View.Body.static body)))
;;

let component ~activations ~after_displays handlers graph =
  let count, increment = Bonsai_v017.state ~equal:Int.equal 0 graph in
  let increment_handler =
    Driver.Handler.create
      handlers
      ~name:"increment"
      ~equal:( == )
      increment
      ~f:(fun increment -> function
      | Ui.Event.Payload.Unit -> increment (fun value -> value + 1)
      | _ -> increment Fun.id)
  in
  let on_activate =
    Bonsai.Cont.return (Bonsai.Effect.of_thunk (fun () -> Stdlib.incr activations))
  in
  let after_display =
    Bonsai.Cont.return (Bonsai.Effect.of_thunk (fun () -> Stdlib.incr after_displays))
  in
  Bonsai.Cont.Edge.lifecycle ~on_activate ~after_display graph;
  Bonsai.Cont.map2 count increment_handler ~f:(fun count increment_handler ->
    Ui.View.column
      [ Ui.View.text (Printf.sprintf "Count: %d" count)
      ; Ui.View.button ~on_press:increment_handler ~child:(Ui.View.text "Increment") ()
      ])
;;

let find_button_binding (frame : Protocol.Wire_frame.t) =
  List.find_map
    (function
      | Protocol.Wire_frame.Create_node
          { node_id; kind = Button; event_bindings = [ { event_tag; handler_id } ]; _ } ->
        Some (node_id, event_tag, handler_id)
      | _ -> None)
    frame.operations
  |> function
  | Some binding -> binding
  | None -> fail "initial frame has no Button press binding"
;;

let () =
  let runtime_epoch = ID.Runtime.Epoch.of_int64 21L in
  let activations = ref 0 in
  let after_displays = ref 0 in
  let trace_messages = ref [] in
  let trace message = trace_messages := message :: !trace_messages in
  let take_trace () =
    let output = List.rev !trace_messages |> String.concat "\n" in
    trace_messages := [];
    output
  in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver =
    create_driver
      ~trace
      ~runtime_epoch
      ~time_source
      (component ~activations ~after_displays)
  in
  let initial =
    match ok (pump driver ()) with
    | Some frame -> frame
    | None -> fail "initial pump must emit a full snapshot"
  in
  let initial_trace = take_trace () in
  require_substring
    initial_trace
    "[widget-diff] targetRevision=1 kind=full_snapshot"
    "initial trace did not identify the full widget diff";
  require_substring
    initial_trace
    "Text \"Count: 0\""
    "initial widget diff omitted the counter value";
  require_substring
    initial_trace
    "Text \"Increment\""
    "initial widget diff omitted the button label";
  require
    (Runtime.Frame_patch.kind initial.frame_patch = Full_snapshot)
    "initial pump must reconcile a full snapshot";
  let initial_wire =
    match Protocol.Binary_codec.decode initial.bytes with
    | Ok frame -> frame
    | Error error -> fail "initial frame did not decode: %s" error.message
  in
  let node_id, event_tag, handler_id = find_button_binding initial_wire in
  require
    (event_tag = Protocol.Generated_protocol.Event_tag.press)
    "Button must encode the press event tag";
  require
    (!activations = 0 && !after_displays = 0)
    "initial pump must not trigger presentation-gated lifecycle events";
  ok (present driver ~revision:initial.revision);
  ignore (take_trace ());
  require (!activations = 1) "initial presentation must trigger activation";
  require (!after_displays = 1) "initial presentation must trigger after-display";
  (match ok (pump driver ()) with
   | None -> ()
   | Some _ -> fail "unchanged pump unexpectedly emitted a frame");
  ok (present driver ~revision:initial.revision);
  let unchanged_trace = take_trace () in
  require_no_substring
    unchanged_trace
    "[widget-diff]"
    "unchanged pump emitted a widget diff";
  require_no_substring unchanged_trace "Count: 0" "unchanged pump printed the widget tree";
  let events =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = ID.Runtime.Event_sequence.of_int64 1L
            ; displayed_revision = initial.revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let updated =
    match ok (pump driver ~events ()) with
    | Some frame -> frame
    | None -> fail "Counter press must emit an incremental frame"
  in
  let updated_trace = take_trace () in
  require_substring
    updated_trace
    "[widget-diff] targetRevision=2 kind=incremental_frame"
    "incremental trace did not identify the widget diff";
  require_substring
    updated_trace
    "updateProps"
    "incremental widget diff omitted the operation";
  require_substring
    updated_trace
    "Text \"Count: 1\""
    "incremental widget diff omitted the changed counter";
  require_no_substring
    updated_trace
    "Text \"Increment\""
    "incremental widget diff included an unchanged child";
  let updated_wire =
    match Protocol.Binary_codec.decode updated.bytes with
    | Ok frame -> frame
    | Error error -> fail "incremental frame did not decode: %s" error.message
  in
  (match semantic_operations updated_wire with
   | [ Protocol.Wire_frame.Update_props
         { node_id = _; props = Text_props { value = "Count: 1"; _ } }
     ] -> ()
   | operations ->
     fail
       "Counter press must emit one text prop patch, got %d operations"
       (List.length operations));
  require
    (!after_displays = 2)
    "incremental pump must not run after-display before presentation";
  ok (present driver ~revision:updated.revision);
  require (!after_displays = 3) "incremental presentation must run after-display";
  let invalid_batch =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = ID.Runtime.Event_sequence.of_int64 2L
            ; displayed_revision = updated.revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ; { sequence = ID.Runtime.Event_sequence.of_int64 3L
            ; displayed_revision = updated.revision
            ; node_id
            ; handler_id =
                ID.Ui.Handler_id.of_int64
                  (Int64.add (ID.Ui.Handler_id.to_int64 handler_id) 1000L)
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let invalid_result = ok (pump_result driver ~events:invalid_batch ()) in
  (match invalid_result.recoverable_error with
   | Some (Driver.Event_error _) -> ()
   | Some error ->
     fail
       "invalid event batch returned the wrong diagnostic: %s"
       (Driver.error_to_string error)
   | None -> fail "invalid event batch lost its recoverable diagnostic");
  ok (present driver ~revision:invalid_result.renderer_revision);
  let valid_after_rejection =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = ID.Runtime.Event_sequence.of_int64 4L
            ; displayed_revision = updated.revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let after_rejection =
    match ok (pump driver ~events:valid_after_rejection ()) with
    | Some frame -> frame
    | None -> fail "valid event after rejected batch must emit a frame"
  in
  let after_rejection_wire =
    match Protocol.Binary_codec.decode after_rejection.bytes with
    | Ok frame -> frame
    | Error error -> fail "post-rejection frame did not decode: %s" error.message
  in
  (match semantic_operations after_rejection_wire with
   | [ Protocol.Wire_frame.Update_props
         { node_id = _; props = Text_props { value = "Count: 2"; _ } }
     ] -> ()
   | _ -> fail "rejected batch leaked a previously queued Bonsai effect");
  ok (present driver ~revision:after_rejection.revision);
  let resync_request =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = ID.Runtime.Event_sequence.of_int64 5L
            ; displayed_revision = after_rejection.revision
            ; node_id = ID.Ui.Node_id.zero
            ; handler_id = ID.Ui.Handler_id.zero
            ; event_tag = Protocol.Generated_protocol.Event_tag.resync_requested
            ; payload = Unit
            }
          ]
      }
  in
  let resync =
    match ok (pump driver ~events:resync_request ()) with
    | Some frame -> frame
    | None -> fail "resync request did not emit a full snapshot"
  in
  let resync_wire = decode_frame resync.bytes in
  require (resync_wire.kind = Full_snapshot) "resync was not a full snapshot";
  require
    (ID.Runtime.Renderer_revision.equal
       resync_wire.base_revision
       ID.Runtime.Renderer_revision.zero)
    "resync base revision was not zero";
  require (resync.stats.resync_count = 1) "resync instrumentation did not increment";
  ok (present driver ~revision:resync.revision);
  Driver.shutdown driver
;;

let host_effect_component ?cancellation host_ref handlers graph =
  let text, set_text = Bonsai_v017.state ~equal:String.equal "Idle" graph in
  let host_effects = Driver.Handler.host_effects handlers in
  host_ref := Some host_effects;
  let request_clipboard =
    Driver.Handler.create
      handlers
      ~name:"clipboard-read"
      ~equal:( == )
      set_text
      ~f:(fun set_text _ ->
        Bonsai.Effect.bind
          (Host_effect.Clipboard.read ?cancellation host_effects ())
          ~f:(function
          | Ok clipboard -> set_text (fun _ -> clipboard)
          | Error _ -> set_text (fun _ -> "Host error")))
  in
  Bonsai.Cont.map2 text request_clipboard ~f:(fun text request_clipboard ->
    Ui.View.column
      [ Ui.View.text text
      ; Ui.View.button
          ~on_press:request_clipboard
          ~child:(Ui.View.text "Read clipboard")
          ()
      ])
;;

let test_host_effect_round_trip () =
  let runtime_epoch = ID.Runtime.Epoch.of_int64 81L in
  let host_ref = ref None in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver =
    create_driver ~runtime_epoch ~time_source (host_effect_component host_ref)
  in
  let initial =
    match ok (pump driver ()) with
    | Some frame -> frame
    | None -> fail "host-effect component did not mount"
  in
  let initial_wire = decode_frame initial.bytes in
  let node_id, event_tag, handler_id = find_button_binding initial_wire in
  ok (present driver ~revision:initial.revision);
  let press =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = ID.Runtime.Event_sequence.of_int64 1L
            ; displayed_revision = initial.revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let request_frame =
    match ok (pump driver ~events:press ()) with
    | Some frame -> frame
    | None -> fail "clipboard effect did not emit a host request"
  in
  let request_wire = decode_frame request_frame.bytes in
  let request_id =
    match semantic_operations request_wire with
    | [ Protocol.Wire_frame.Host_request { request_id; payload = Clipboard_read } ] ->
      request_id
    | operations ->
      fail "clipboard effect emitted %d unexpected operations" (List.length operations)
  in
  let host =
    match !host_ref with
    | Some host -> host
    | None -> fail "component did not expose its host-effect context"
  in
  require
    (Host_effect.Private.pending_count host = 1)
    "clipboard request was not retained while pending";
  ok (present driver ~revision:request_frame.revision);
  let response =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = ID.Runtime.Event_sequence.of_int64 2L
            ; displayed_revision = request_frame.revision
            ; node_id = ID.Ui.Node_id.zero
            ; handler_id = ID.Ui.Handler_id.zero
            ; event_tag = Protocol.Generated_protocol.Event_tag.host_response
            ; payload =
                Host_response
                  { request_id; status = Host_ok; value = Bytes.of_string "来自 SwiftUI" }
            }
          ]
      }
  in
  let response_frame =
    match ok (pump driver ~events:response ()) with
    | Some frame -> frame
    | None -> fail "host response did not resume the Bonsai effect"
  in
  let response_wire = decode_frame response_frame.bytes in
  (match semantic_operations response_wire with
   | [ Protocol.Wire_frame.Update_props
         { props = Text_props { value = "来自 SwiftUI"; _ }; _ }
     ] -> ()
   | _ -> fail "host response did not produce the expected text patch");
  require
    (Host_effect.Private.pending_count host = 0)
    "completed host request remained pending";
  ok (present driver ~revision:response_frame.revision);
  Driver.shutdown driver;
  require
    (Host_effect.Private.pending_count host = 0)
    "driver shutdown retained a host request"
;;

let () = test_host_effect_round_trip ()

let test_host_effect_cancellation () =
  let runtime_epoch = ID.Runtime.Epoch.of_int64 83L in
  let host_ref = ref None in
  let cancellation = Host_effect.Cancellation.create () in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver =
    create_driver
      ~runtime_epoch
      ~time_source
      (host_effect_component ~cancellation host_ref)
  in
  let initial =
    match ok (pump driver ()) with
    | Some frame -> frame
    | None -> fail "cancellation component did not mount"
  in
  let initial_wire = decode_frame initial.bytes in
  let node_id, event_tag, handler_id = find_button_binding initial_wire in
  ok (present driver ~revision:initial.revision);
  let press =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = ID.Runtime.Event_sequence.of_int64 1L
            ; displayed_revision = initial.revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let request_frame =
    match ok (pump driver ~events:press ()) with
    | Some frame -> frame
    | None -> fail "cancellable effect did not emit a host request"
  in
  let request_id =
    match semantic_operations (decode_frame request_frame.bytes) with
    | [ Protocol.Wire_frame.Host_request { request_id; _ } ] -> request_id
    | _ -> fail "cancellable effect emitted unexpected operations"
  in
  ok (present driver ~revision:request_frame.revision);
  Host_effect.Cancellation.cancel cancellation;
  let cancelled =
    match ok (pump driver ()) with
    | Some frame -> decode_frame frame.bytes
    | None -> fail "cancellation did not resume the effect"
  in
  require
    (List.exists
       (function
         | Protocol.Wire_frame.Cancel_host_request { request_id = cancelled_request_id }
           -> ID.Host.Request_id.equal request_id cancelled_request_id
         | _ -> false)
       cancelled.operations)
    "cancellation frame did not carry CancelHostRequest";
  let host =
    match !host_ref with
    | Some host -> host
    | None -> fail "cancellation component did not expose host effects"
  in
  require
    (Host_effect.Private.pending_count host = 0)
    "cancelled host effect remained pending";
  ok
    (present
       driver
       ~revision:
         (match Hashtbl.find_opt pending_presentations driver with
          | Some result -> result.renderer_revision
          | None -> fail "cancellation pump lost its presentation token"));
  Driver.shutdown driver
;;

let () = test_host_effect_cancellation ()

let environment_component handlers _graph =
  Environment.value (Driver.Handler.environment handlers)
  |> Bonsai.Cont.map ~f:(fun (environment : Environment.snapshot) ->
    Ui.View.text
      (Printf.sprintf
         "%.0fx%.0f %s"
         environment.viewport_width
         environment.viewport_height
         environment.locale))
;;

let test_environment_is_dynamic_input () =
  let runtime_epoch = ID.Runtime.Epoch.of_int64 82L in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver = create_driver ~runtime_epoch ~time_source environment_component in
  let initial =
    match ok (pump driver ()) with
    | Some frame -> frame
    | None -> fail "environment component did not mount"
  in
  ok (present driver ~revision:initial.revision);
  let insets = Protocol.Inbound_event.{ left = 0.; top = 0.; right = 0.; bottom = 0. } in
  let environment =
    Protocol.Inbound_event.
      { viewport_width = 1440.
      ; viewport_height = 900.
      ; device_pixel_ratio = 2.
      ; text_scale = 1.
      ; brightness = Environment_dark
      ; platform = "macos"
      ; locale = "zh-CN"
      ; safe_area = insets
      ; keyboard_insets = insets
      ; accessible_navigation = false
      ; bold_text = false
      ; invert_colors = false
      ; disable_animations = false
      ; reduced_motion = false
      ; high_contrast = false
      ; orientation = Landscape
      ; pointer_kinds = 10
      }
  in
  let batch =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = ID.Runtime.Event_sequence.of_int64 1L
            ; displayed_revision = initial.revision
            ; node_id = ID.Ui.Node_id.zero
            ; handler_id = ID.Ui.Handler_id.zero
            ; event_tag = Protocol.Generated_protocol.Event_tag.environment_changed
            ; payload = Environment_changed environment
            }
          ]
      }
  in
  let updated_frame =
    match ok (pump driver ~events:batch ()) with
    | Some frame -> frame
    | None -> fail "environment change did not invalidate Bonsai"
  in
  let updated = decode_frame updated_frame.bytes in
  (match semantic_operations updated with
   | [ Protocol.Wire_frame.Update_props
         { props = Text_props { value = "1440x900 zh-CN"; _ }; _ }
     ] -> ()
   | _ -> fail "environment change did not produce the expected text patch");
  ok (present driver ~revision:updated_frame.revision);
  let unchanged =
    Protocol.Inbound_event.
      { batch with
        events =
          [ { sequence = ID.Runtime.Event_sequence.of_int64 2L
            ; displayed_revision = updated_frame.revision
            ; node_id = ID.Ui.Node_id.zero
            ; handler_id = ID.Ui.Handler_id.zero
            ; event_tag = Protocol.Generated_protocol.Event_tag.environment_changed
            ; payload = Environment_changed environment
            }
          ]
      }
  in
  require
    (ok (pump driver ~events:unchanged ()) = None)
    "unchanged environment unexpectedly produced a frame";
  ok (present driver ~revision:updated_frame.revision);
  Driver.shutdown driver
;;

let () = test_environment_is_dynamic_input ()

type handler_dependency_model =
  { mode : bool
  ; observed_mode : bool option
  }

let equal_handler_dependency_model left right =
  Bool.equal left.mode right.mode
  && Option.equal Bool.equal left.observed_mode right.observed_mode
;;

let handler_dependency_component handlers graph =
  let model, set_model =
    Bonsai_v017.state
      ~equal:equal_handler_dependency_model
      { mode = false; observed_mode = None }
      graph
  in
  let toggle_mode =
    Driver.Handler.create
      handlers
      ~name:"toggle-mode"
      ~equal:( == )
      set_model
      ~f:(fun set_model _ ->
        set_model (fun model -> { model with mode = not model.mode }))
  in
  let action_dependencies =
    Bonsai.Cont.both set_model (Bonsai.Cont.map model ~f:(fun model -> model.mode))
  in
  let observe_mode =
    Driver.Handler.create
      handlers
      ~name:"observe-mode"
      ~equal:(fun (left_set_model, left_mode) (right_set_model, right_mode) ->
        left_set_model == right_set_model && Bool.equal left_mode right_mode)
      action_dependencies
      ~f:(fun (set_model, mode) _ ->
        set_model (fun model -> { model with observed_mode = Some mode }))
  in
  Bonsai.Cont.map2
    model
    (Bonsai.Cont.both toggle_mode observe_mode)
    ~f:(fun model handlers ->
      let toggle_mode, observe_mode = handlers in
      let observed_mode =
        match model.observed_mode with
        | None -> "none"
        | Some value -> Bool.to_string value
      in
      Ui.View.column
        [ Ui.View.text ("Observed: " ^ observed_mode)
        ; Ui.View.button ~on_press:toggle_mode ~child:(Ui.View.text "Toggle mode") ()
        ; Ui.View.button
            ~style:Ui.View.Button_style.Plain
            ~on_press:observe_mode
            ~child:(Ui.View.text "Observe mode")
            ()
        ])
;;

let find_labeled_button_binding (frame : Protocol.Wire_frame.t) label =
  let open Protocol.Wire_frame in
  let labels =
    List.filter_map
      (function
        | Create_node { node_id; props = Text_props { value; _ }; _ }
          when String.equal value label -> Some node_id
        | _ -> None)
      frame.operations
  in
  let parents =
    List.filter_map
      (function
        | Set_children { node_id; children = [ child ] } when List.mem child labels ->
          Some node_id
        | _ -> None)
      frame.operations
  in
  List.filter_map
    (function
      | Create_node { node_id; kind = Button; event_bindings = [ binding ]; _ }
        when List.mem node_id parents -> Some (node_id, binding)
      | _ -> None)
    frame.operations
  |> function
  | [ binding ] -> binding
  | bindings -> fail "expected one button labeled %S, got %d" label (List.length bindings)
;;

let event_batch ~runtime_epoch ~sequence ~revision ~node_id binding =
  Protocol.Inbound_event.
    { runtime_epoch
    ; events =
        [ { sequence
          ; displayed_revision = revision
          ; node_id
          ; handler_id = binding.Protocol.Wire_frame.handler_id
          ; event_tag = binding.event_tag
          ; payload = Unit
          }
        ]
    }
;;

let test_handler_dependencies_control_identity () =
  let runtime_epoch = ID.Runtime.Epoch.of_int64 84L in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver = create_driver ~runtime_epoch ~time_source handler_dependency_component in
  let initial =
    match ok (pump driver ()) with
    | Some frame -> frame
    | None -> fail "handler dependency component did not mount"
  in
  let initial_wire = decode_frame initial.bytes in
  let toggle_node, toggle_binding =
    find_labeled_button_binding initial_wire "Toggle mode"
  in
  let observe_node, initial_observe_binding =
    find_labeled_button_binding initial_wire "Observe mode"
  in
  ok (present driver ~revision:initial.revision);
  let changed_dependency =
    match
      ok
        (pump
           driver
           ~events:
             (event_batch
                ~runtime_epoch
                ~sequence:(ID.Runtime.Event_sequence.of_int64 1L)
                ~revision:initial.revision
                ~node_id:toggle_node
                toggle_binding)
           ())
    with
    | Some frame -> frame
    | None -> fail "changing handler dependencies did not emit a frame"
  in
  let changed_dependency_operations =
    semantic_operations (decode_frame changed_dependency.bytes)
  in
  let current_observe_binding =
    match changed_dependency_operations with
    | [ Protocol.Wire_frame.Update_event_bindings
          { node_id; event_bindings = [ binding ] }
      ]
      when ID.Ui.Node_id.equal node_id observe_node -> binding
    | operations ->
      fail
        "dependency change must emit one binding update, got %d operations"
        (List.length operations)
  in
  require
    (not
       (ID.Ui.Handler_id.equal
          initial_observe_binding.handler_id
          current_observe_binding.handler_id))
    "dependency change reused the previous handler ID";
  ok (present driver ~revision:changed_dependency.revision);
  let unchanged_dependency =
    match
      ok
        (pump
           driver
           ~events:
             (event_batch
                ~runtime_epoch
                ~sequence:(ID.Runtime.Event_sequence.of_int64 2L)
                ~revision:changed_dependency.revision
                ~node_id:observe_node
                current_observe_binding)
           ())
    with
    | Some frame -> frame
    | None -> fail "handler did not observe its updated dependency"
  in
  (match semantic_operations (decode_frame unchanged_dependency.bytes) with
   | [ Protocol.Wire_frame.Update_props
         { props = Text_props { value = "Observed: true"; _ }; _ }
     ] -> ()
   | operations ->
     fail
       "unchanged dependencies must retain the binding and update only text, got %d \
        operations"
       (List.length operations));
  Driver.shutdown driver
;;

let () = test_handler_dependencies_control_identity ()

let application_platform_component
      ~platform_ref
      ~first_cancellation
      ~request_results
      ~application_events
      handlers
      _graph
  =
  let platform = Driver.Handler.application_platform handlers in
  platform_ref := Some platform;
  Host_effect.Application_platform.on_event platform (fun payload ->
    Bonsai.Effect.of_thunk (fun () ->
      application_events := !application_events @ [ Bytes.copy payload ]));
  let request ?cancellation label payload =
    Driver.Handler.create
      handlers
      ~name:("application-request-" ^ label)
      ~equal:( == )
      (Bonsai.Cont.return ())
      ~f:(fun () _ ->
        Bonsai.Effect.bind
          (Host_effect.Application_platform.request ?cancellation platform payload)
          ~f:(fun result ->
            Bonsai.Effect.of_thunk (fun () ->
              request_results := !request_results @ [ label, result ])))
  in
  let first =
    request ~cancellation:first_cancellation "first" (Bytes.of_string "\000one\255")
  in
  let second = request "second" (Bytes.of_string "\128two\000") in
  Bonsai.Cont.map2 first second ~f:(fun first second ->
    Ui.View.column
      [ Ui.View.button ~on_press:first ~child:(Ui.View.text "First") ()
      ; Ui.View.button
          ~style:Ui.View.Button_style.Plain
          ~on_press:second
          ~child:(Ui.View.text "Second")
          ()
      ])
;;

let application_control_event ~sequence ~revision ~event_tag payload =
  Protocol.Inbound_event.
    { sequence
    ; displayed_revision = revision
    ; node_id = ID.Ui.Node_id.zero
    ; handler_id = ID.Ui.Handler_id.zero
    ; event_tag
    ; payload
    }
;;

let test_application_platform_requests_events_and_cancellation () =
  let runtime_epoch = ID.Runtime.Epoch.of_int64 97L in
  let platform_ref = ref None in
  let request_results = ref [] in
  let application_events = ref [] in
  let cancellation = Host_effect.Application_platform.Cancellation.create () in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver =
    create_driver
      ~runtime_epoch
      ~time_source
      (application_platform_component
         ~platform_ref
         ~first_cancellation:cancellation
         ~request_results
         ~application_events)
  in
  let initial =
    match ok (pump driver ()) with
    | Some frame -> frame
    | None -> fail "application platform component did not mount"
  in
  let initial_wire = decode_frame initial.bytes in
  let first_node, first_binding = find_labeled_button_binding initial_wire "First" in
  let second_node, second_binding = find_labeled_button_binding initial_wire "Second" in
  ok (present driver ~revision:initial.revision);
  let presses =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = ID.Runtime.Event_sequence.of_int64 1L
            ; displayed_revision = initial.revision
            ; node_id = first_node
            ; handler_id = first_binding.Protocol.Wire_frame.handler_id
            ; event_tag = first_binding.event_tag
            ; payload = Unit
            }
          ; { sequence = ID.Runtime.Event_sequence.of_int64 2L
            ; displayed_revision = initial.revision
            ; node_id = second_node
            ; handler_id = second_binding.Protocol.Wire_frame.handler_id
            ; event_tag = second_binding.event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let requests =
    match ok (pump driver ~events:presses ()) with
    | Some frame -> frame
    | None -> fail "concurrent application requests emitted no frame"
  in
  let request_operations = semantic_operations (decode_frame requests.bytes) in
  let first_request_id, second_request_id =
    match request_operations with
    | [ Protocol.Wire_frame.Application_request first
      ; Protocol.Wire_frame.Application_request second
      ] ->
      require
        (Bytes.equal first.payload (Bytes.of_string "\000one\255"))
        "first application request bytes changed";
      require
        (Bytes.equal second.payload (Bytes.of_string "\128two\000"))
        "second application request bytes changed";
      first.request_id, second.request_id
    | operations ->
      fail "expected two application requests, got %d operations" (List.length operations)
  in
  let platform =
    match !platform_ref with
    | Some platform -> platform
    | None -> fail "component did not expose the application platform"
  in
  require
    (Host_effect.Application_platform.Private.pending_count platform = 2)
    "concurrent application requests were not retained";
  ok (present driver ~revision:requests.revision);
  let response_two = Bytes.of_string "two-response\255" in
  let response_one = Bytes.of_string "one-response\000" in
  let inbound =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ application_control_event
              ~sequence:(ID.Runtime.Event_sequence.of_int64 3L)
              ~revision:requests.revision
              ~event_tag:Protocol.Generated_protocol.Event_tag.application_response
              (Application_response
                 { request_id = second_request_id; payload = response_two })
          ; application_control_event
              ~sequence:(ID.Runtime.Event_sequence.of_int64 4L)
              ~revision:requests.revision
              ~event_tag:Protocol.Generated_protocol.Event_tag.application_response
              (Application_response
                 { request_id = first_request_id; payload = response_one })
          ; application_control_event
              ~sequence:(ID.Runtime.Event_sequence.of_int64 5L)
              ~revision:requests.revision
              ~event_tag:Protocol.Generated_protocol.Event_tag.application_event
              (Application_event (Bytes.of_string "event-1"))
          ; application_control_event
              ~sequence:(ID.Runtime.Event_sequence.of_int64 6L)
              ~revision:requests.revision
              ~event_tag:Protocol.Generated_protocol.Event_tag.application_event
              (Application_event (Bytes.of_string "event-2"))
          ]
      }
  in
  let response_result = ok (pump_result driver ~events:inbound ()) in
  Bytes.fill response_one 0 (Bytes.length response_one) '\000';
  Bytes.fill response_two 0 (Bytes.length response_two) '\000';
  (match !request_results with
   | [ ("second", Ok second); ("first", Ok first) ] ->
     require
       (Bytes.equal second (Bytes.of_string "two-response\255"))
       "second response cross-correlated or aliased";
     require
       (Bytes.equal first (Bytes.of_string "one-response\000"))
       "first response cross-correlated or aliased"
   | _ -> fail "concurrent application responses were not correlated");
  require
    (!application_events = [ Bytes.of_string "event-1"; Bytes.of_string "event-2" ])
    "application events were reordered";
  require
    (Host_effect.Application_platform.Private.pending_count platform = 0)
    "completed application requests remained pending";
  ok (present driver ~revision:response_result.renderer_revision);
  let third_press =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = ID.Runtime.Event_sequence.of_int64 7L
            ; displayed_revision = response_result.renderer_revision
            ; node_id = first_node
            ; handler_id = first_binding.handler_id
            ; event_tag = first_binding.event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let cancelled_request =
    match ok (pump driver ~events:third_press ()) with
    | Some frame -> frame
    | None -> fail "cancellable application request emitted no frame"
  in
  ok (present driver ~revision:cancelled_request.revision);
  Host_effect.Application_platform.Cancellation.cancel cancellation;
  let cancelled_result = ok (pump_result driver ()) in
  (match List.rev !request_results with
   | ("first", Error Host_effect.Application_platform.Cancelled) :: _ -> ()
   | _ -> fail "application request cancellation returned the wrong result");
  require
    (Host_effect.Application_platform.Private.pending_count platform = 0)
    "cancelled application request remained pending";
  ok (present driver ~revision:cancelled_result.renderer_revision);
  Driver.shutdown driver
;;

let () = test_application_platform_requests_events_and_cancellation ()

let single_application_request_component ~platform_ref ~payload ~results handlers _graph =
  let platform = Driver.Handler.application_platform handlers in
  platform_ref := Some platform;
  Driver.Handler.create
    handlers
    ~name:"single-application-request"
    ~equal:( == )
    (Bonsai.Cont.return ())
    ~f:(fun () _ ->
      Bonsai.Effect.bind
        (Host_effect.Application_platform.request platform payload)
        ~f:(fun result ->
          Bonsai.Effect.of_thunk (fun () -> results := !results @ [ result ])))
  |> Bonsai.Cont.map ~f:(fun handler ->
    Ui.View.button ~on_press:handler ~child:(Ui.View.text "Request") ())
;;

let start_single_application_request driver runtime_epoch =
  let initial =
    match ok (pump driver ()) with
    | Some frame -> frame
    | None -> fail "single application request component did not mount"
  in
  let node_id, event_tag, handler_id = find_button_binding (decode_frame initial.bytes) in
  ok (present driver ~revision:initial.revision);
  let press =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = ID.Runtime.Event_sequence.of_int64 1L
            ; displayed_revision = initial.revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  initial, ok (pump_result driver ~events:press ())
;;

let test_application_platform_bounds_errors_and_recoverable_traffic () =
  let runtime_epoch = ID.Runtime.Epoch.of_int64 98L in
  let platform_ref = ref None in
  let results = ref [] in
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  let driver =
    create_driver
      ~runtime_epoch
      ~time_source
      (single_application_request_component
         ~platform_ref
         ~payload:(Bytes.of_string "request")
         ~results)
  in
  let _, request_result = start_single_application_request driver runtime_epoch in
  let request_frame =
    match request_result.frame with
    | Some frame -> frame
    | None -> fail "single application request emitted no frame"
  in
  let request_id =
    match semantic_operations (decode_frame request_frame.bytes) with
    | [ Protocol.Wire_frame.Application_request request ] -> request.request_id
    | _ -> fail "single application request emitted unexpected operations"
  in
  ok (present driver ~revision:request_result.renderer_revision);
  let unavailable =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ application_control_event
              ~sequence:(ID.Runtime.Event_sequence.of_int64 2L)
              ~revision:request_result.renderer_revision
              ~event_tag:Protocol.Generated_protocol.Event_tag.application_request_error
              (Application_request_error
                 { request_id; error = { code = Unavailable; message = "" } })
          ]
      }
  in
  let unavailable_result = ok (pump_result driver ~events:unavailable ()) in
  (match !results with
   | [ Error Host_effect.Application_platform.Unavailable ] -> ()
   | _ -> fail "unavailable bridge returned the wrong typed error");
  ok (present driver ~revision:unavailable_result.renderer_revision);
  let unknown =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ application_control_event
              ~sequence:(ID.Runtime.Event_sequence.of_int64 3L)
              ~revision:unavailable_result.renderer_revision
              ~event_tag:Protocol.Generated_protocol.Event_tag.application_response
              (Application_response
                 { request_id = Int64.succ request_id; payload = Bytes.empty })
          ]
      }
  in
  let unknown_result = ok (pump_result driver ~events:unknown ()) in
  require
    (Option.is_some unknown_result.recoverable_error)
    "unknown application response was not recoverable";
  ok (present driver ~revision:unknown_result.renderer_revision);
  let stale =
    Protocol.Inbound_event.
      { runtime_epoch = ID.Runtime.Epoch.of_int64 981L
      ; events =
          [ application_control_event
              ~sequence:(ID.Runtime.Event_sequence.of_int64 4L)
              ~revision:unknown_result.renderer_revision
              ~event_tag:Protocol.Generated_protocol.Event_tag.application_event
              (Application_event (Bytes.of_string "stale"))
          ]
      }
  in
  let stale_result = ok (pump_result driver ~events:stale ()) in
  (match stale_result.recoverable_error with
   | Some (Driver.Application_platform_error _) -> ()
   | _ -> fail "stale application event was not a recoverable bridge error");
  ok (present driver ~revision:stale_result.renderer_revision);
  let clean_result = ok (pump_result driver ()) in
  require
    (Option.is_none clean_result.recoverable_error)
    "malformed application traffic terminated the driver";
  ok (present driver ~revision:clean_result.renderer_revision);
  Driver.shutdown driver;
  let oversized_results = ref [] in
  let oversized_platform = ref None in
  let oversized_driver =
    create_driver
      ~runtime_epoch:(ID.Runtime.Epoch.of_int64 99L)
      ~time_source:(Bonsai.Time_source.create ~start:Core.Time_ns.epoch)
      (single_application_request_component
         ~platform_ref:oversized_platform
         ~payload:
           (Bytes.make
              (Host_effect.Application_platform.maximum_payload_bytes + 1)
              '\000')
         ~results:oversized_results)
  in
  let _, oversized_result =
    start_single_application_request oversized_driver (ID.Runtime.Epoch.of_int64 99L)
  in
  require (Option.is_none oversized_result.frame) "oversized request emitted bytes";
  (match !oversized_results with
   | [ Error Host_effect.Application_platform.Payload_too_large ] -> ()
   | _ -> fail "oversized request returned the wrong typed error");
  ok (present oversized_driver ~revision:oversized_result.renderer_revision);
  Driver.shutdown oversized_driver
;;

let test_application_platform_runtime_replacement_resolves_pending () =
  let runtime_epoch = ID.Runtime.Epoch.of_int64 100L in
  let platform_ref = ref None in
  let results = ref [] in
  let driver =
    create_driver
      ~runtime_epoch
      ~time_source:(Bonsai.Time_source.create ~start:Core.Time_ns.epoch)
      (single_application_request_component
         ~platform_ref
         ~payload:(Bytes.of_string "pending")
         ~results)
  in
  let _, request_result = start_single_application_request driver runtime_epoch in
  let platform = Option.get !platform_ref in
  ok (present driver ~revision:request_result.renderer_revision);
  Host_effect.Application_platform.Private.shutdown
    platform
    Host_effect.Application_platform.Runtime_replaced;
  let replacement_result = ok (pump_result driver ()) in
  (match !results with
   | [ Error Host_effect.Application_platform.Runtime_replaced ] -> ()
   | _ -> fail "runtime replacement did not resolve the pending request");
  require
    (Host_effect.Application_platform.Private.pending_count platform = 0)
    "runtime replacement retained pending requests";
  ok (present driver ~revision:replacement_result.renderer_revision);
  Driver.shutdown driver
;;

let test_application_platform_shutdown_resolves_pending () =
  let runtime_epoch = ID.Runtime.Epoch.of_int64 101L in
  let platform_ref = ref None in
  let results = ref [] in
  let driver =
    create_driver
      ~runtime_epoch
      ~time_source:(Bonsai.Time_source.create ~start:Core.Time_ns.epoch)
      (single_application_request_component
         ~platform_ref
         ~payload:(Bytes.of_string "pending-at-shutdown")
         ~results)
  in
  let _, request_result = start_single_application_request driver runtime_epoch in
  ok (present driver ~revision:request_result.renderer_revision);
  Driver.shutdown driver;
  (match !results with
   | [ Error Host_effect.Application_platform.Shutdown ] -> ()
   | _ -> fail "shutdown did not resolve the pending application request");
  require
    (Driver.For_testing.pending_application_request_count driver = 0)
    "shutdown retained pending application requests"
;;

let test_application_theme_is_atomic_and_diffed_independently () =
  let component handlers graph =
    let dark, set_dark = Bonsai_v017.state ~equal:Bool.equal false graph in
    let toggle =
      Driver.Handler.create handlers ~equal:( == ) set_dark ~f:(fun set_dark _ ->
        set_dark not)
    in
    Bonsai.Cont.map2 dark toggle ~f:(fun dark toggle ->
      let mode = if dark then Ui.Theme.Dark else Ui.Theme.Light in
      Driver.View.create
        ~theme:(Ui.Theme.create ~mode ())
        ~body:
          (Ui.View.Body.static
             (Ui.View.button ~on_press:toggle ~child:(Ui.View.text "Theme body") ())))
  in
  let runtime_epoch = ID.Runtime.Epoch.of_int64 102L in
  let driver =
    Driver.create
      ~application_title:"Theme driver"
      ~runtime_epoch
      ~time_source:(Bonsai.Time_source.create ~start:Core.Time_ns.epoch)
      component
  in
  let initial = Option.get (ok (pump driver ())) in
  let initial_wire = decode_frame initial.bytes in
  let initial_operations =
    List.filter
      (function
        | Protocol.Wire_frame.Runtime_stats _ -> false
        | _ -> true)
      initial_wire.operations
  in
  require
    (List.exists
       (function
         | Protocol.Wire_frame.Set_application_theme
             { title = Some "Theme driver"; theme = { mode = Light; _ } } -> true
         | _ -> false)
       initial_operations)
    "full snapshot omitted the application theme";
  let node_id, event_tag, handler_id = find_button_binding initial_wire in
  ok (present driver ~revision:initial.revision);
  let events =
    Protocol.Inbound_event.
      { runtime_epoch
      ; events =
          [ { sequence = ID.Runtime.Event_sequence.of_int64 1L
            ; displayed_revision = initial.revision
            ; node_id
            ; handler_id
            ; event_tag
            ; payload = Unit
            }
          ]
      }
  in
  let update = Option.get (ok (pump driver ~events ())) in
  (match
     List.filter
       (function
         | Protocol.Wire_frame.Runtime_stats _ -> false
         | _ -> true)
       (decode_frame update.bytes).operations
   with
   | [ Protocol.Wire_frame.Set_application_theme { theme = { mode = Dark; _ }; _ } ] -> ()
   | _ -> fail "theme-only state change emitted widget operations or omitted theme update");
  ok (present driver ~revision:update.revision);
  (match ok (pump driver ()) with
   | None -> ()
   | Some _ -> fail "unchanged application theme emitted a frame");
  Driver.shutdown driver
;;

let () =
  test_application_theme_is_atomic_and_diffed_independently ();
  test_application_platform_bounds_errors_and_recoverable_traffic ();
  test_application_platform_runtime_replacement_resolves_pending ();
  test_application_platform_shutdown_resolves_pending ()
;;

let () =
  let host = Host_effect.Private.create ~schedule:(fun _ -> ()) in
  let item id label : Host_effect.native_menu_item =
    { item_id = ID.Host.Native_menu_item_id.of_string id; label; enabled = true }
  in
  List.iter
    (fun items ->
       match Host_effect.show_native_menu host items with
       | exception Invalid_argument _ -> ()
       | _ -> fail "invalid action menu reached host dispatch")
    [ [ item
          (String.make (Protocol.Generated_protocol.Limits.max_string_bytes - 4) 'x')
          "Oversized response"
      ]
    ; []
    ; [ item "" "Action" ]
    ; [ item "a" " \n\t" ]
    ; [ item "a" "A"; item "a" "B" ]
    ; List.init 1025 (fun i -> item (string_of_int i) "Action")
    ];
  require (Host_effect.Private.pending_count host = 0) "invalid menu retained a request";
  Host_effect.Private.shutdown host
;;

let () =
  let host = Host_effect.Private.create ~schedule:(fun _ -> ()) in
  let date year month day : Host_effect.civil_date = { year; month; day } in
  let first = date 2024 1 1 in
  let last = date 2025 12 31 in
  let rejects run =
    match run () with
    | exception Invalid_argument _ -> ()
    | _ -> fail "invalid civil picker request reached dispatch"
  in
  List.iter
    rejects
    [ (fun () -> ignore (Host_effect.pick_date ~first:(date 0 1 1) ~last host ()))
    ; (fun () ->
        ignore (Host_effect.pick_date ~initial:(date 2024 2 30) ~first ~last host ()))
    ; (fun () ->
        ignore
          (Host_effect.pick_date_range
             ~initial:{ start = last; end_ = first }
             ~first
             ~last
             host
             ()))
    ; (fun () ->
        ignore (Host_effect.pick_time ~initial:{ hour = 24; minute = 0 } host ()))
    ];
  require (Host_effect.Private.pending_count host = 0) "invalid picker retained a request";
  Host_effect.Private.shutdown host
;;
