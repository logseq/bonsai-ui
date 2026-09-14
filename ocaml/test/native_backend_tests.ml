module ID = Bonsai_swiftui_spec.Id
module Protocol = Bonsai_swiftui_protocol
module Ui = Bonsai_swiftui_ui

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let require_substring output substring message =
  require (Core.String.is_substring output ~substring) message
;;

let require_no_substring output substring message =
  require (not (Core.String.is_substring output ~substring)) message
;;

let application_theme =
  Ui.Theme.create ~tint:(Ui.Style.Color.rgb ~red:103 ~green:80 ~blue:164) ()
;;

let application_component component handlers graph =
  Bonsai.Cont.map (component handlers graph) ~f:(fun body ->
    App.View.create ~theme:application_theme ~body:(Ui.View.Body.static body))
;;

let set_u16_le bytes offset value =
  Bytes.set_uint8 bytes offset (value land 0xff);
  Bytes.set_uint8 bytes (offset + 1) ((value lsr 8) land 0xff)
;;

let set_u32_le bytes offset value =
  for index = 0 to 3 do
    Bytes.set_uint8 bytes (offset + index) ((value lsr (index * 8)) land 0xff)
  done
;;

let startup_config ~policy ~entrypoint =
  let entrypoint = Bytes.of_string entrypoint in
  let config = Bytes.create (20 + Bytes.length entrypoint) in
  Bytes.blit_string "BSR1" 0 config 0 4;
  set_u16_le config 4 1;
  set_u16_le config 6 0;
  Bytes.set_uint8 config 8 policy;
  Bytes.fill config 9 3 '\000';
  set_u32_le config 12 (Bytes.length entrypoint);
  set_u32_le config 16 0;
  Bytes.blit entrypoint 0 config 20 (Bytes.length entrypoint);
  config
;;

let capture_stderr run =
  let path = Filename.temp_file "bonsai_swiftui_native_trace" ".log" in
  let saved_stderr = Unix.dup Unix.stderr in
  let output = open_out_bin path in
  flush stderr;
  Unix.dup2 (Unix.descr_of_out_channel output) Unix.stderr;
  Fun.protect
    ~finally:(fun () ->
      flush stderr;
      Unix.dup2 saved_stderr Unix.stderr;
      Unix.close saved_stderr;
      close_out_noerr output)
    run;
  let input = open_in_bin path in
  let contents =
    Fun.protect
      ~finally:(fun () ->
        close_in_noerr input;
        Sys.remove path)
      (fun () -> really_input_string input (in_channel_length input))
  in
  contents
;;

let counter handlers graph =
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
  Bonsai.Cont.map2 count increment_handler ~f:(fun count increment_handler ->
    Ui.View.column
      [ Ui.View.text (Printf.sprintf "Count: %d" count)
      ; Ui.View.button ~on_press:increment_handler ~child:(Ui.View.text "Increment") ()
      ])
;;

let trace_fixture _handlers _graph =
  Bonsai.Cont.return
    (Ui.View.column
       [ Ui.View.text "First item"
         |> Ui.View.with_test_id (Ui.Test_id.string "trace-item-1")
       ; Ui.View.text "Second item"
         |> Ui.View.with_test_id (Ui.Test_id.string "trace-item-2")
       ]
     |> Ui.View.with_test_id (Ui.Test_id.string "trace-root"))
;;

let broken_component _handlers _graph = failwith "intentional startup failure"

let duplicate_key_component _handlers _graph =
  let duplicate = Ui.Key.string "journal-row-focus:duplicate" in
  Bonsai.Cont.return
    (Ui.View.column
       ~key:(Ui.Key.string "runtime-root")
       [ Ui.View.frame
           ~max_width:Ui.Layout.Frame_limit.Fill
           ~max_height:Ui.Layout.Frame_limit.Fill
           (Ui.View.row
              ~key:(Ui.Key.string "runtime-parent")
              [ Ui.View.text "before"
              ; Ui.View.text ~key:duplicate "first"
              ; Ui.View.empty ~key:duplicate ()
              ])
       ])
;;

let () =
  Entrypoint.For_testing.clear ();
  Entrypoint.register
    ~name:(ID.Application.Entrypoint_name.of_string "counter")
    (App.create (application_component counter));
  Entrypoint.register
    ~name:(ID.Application.Entrypoint_name.of_string "broken")
    (App.create (application_component broken_component));
  Entrypoint.register
    ~name:(ID.Application.Entrypoint_name.of_string "duplicate-key")
    (App.create (application_component duplicate_key_component));
  let created = Native_backend.create (startup_config ~policy:0 ~entrypoint:"counter") in
  require (created.status = Native_backend.Ok) "registered entrypoint did not create";
  require
    (ID.Runtime.Handle.compare created.handle ID.Runtime.Handle.zero > 0)
    "native handle must be positive";
  let initial = Native_backend.pump created.handle 0L Bytes.empty in
  require (initial.status = Native_backend.Ok) "initial native pump failed";
  require (Bytes.length initial.bytes > 0) "initial native pump returned no frame";
  require
    (ID.Runtime.Presentation_id.equal
       initial.presentation_id
       ID.Runtime.Presentation_id.one)
    "initial presentation ID must be one";
  require
    (ID.Runtime.Renderer_revision.equal initial.revision ID.Runtime.Renderer_revision.one)
    "initial native revision must be one";
  (match Protocol.Binary_codec.decode initial.bytes with
   | Ok { kind = Full_snapshot; _ } -> ()
   | Ok _ -> fail "initial native frame was not a full snapshot"
   | Error error -> fail "initial native frame did not decode: %s" error.message);
  let presented =
    Native_backend.presentation_succeeded
      created.handle
      initial.presentation_id
      initial.revision
      0L
  in
  require (presented.status = Native_backend.Ok) "frame presentation failed";
  Native_backend.destroy created.handle;
  Native_backend.destroy created.handle;
  let after_destroy = Native_backend.pump created.handle 1L Bytes.empty in
  require
    (after_destroy.status = Native_backend.Fatal_error)
    "destroyed native handle accepted a pump";
  require
    (String.length after_destroy.error > 0)
    "destroyed native handle returned no diagnostic";
  require
    (ID.Ffi.Error_code.equal after_destroy.error_code (ID.Ffi.Error_code.of_int 9))
    "destroyed handle error was not structured";
  for _iteration = 1 to 100 do
    let runtime =
      Native_backend.create (startup_config ~policy:0 ~entrypoint:"counter")
    in
    require (runtime.status = Native_backend.Ok) "soak runtime did not create";
    ignore (Native_backend.pump runtime.handle 0L Bytes.empty);
    Native_backend.destroy runtime.handle
  done;
  require
    (Native_backend.For_testing.runtime_count () = 0)
    "runtime destroy retained native backend handles";
  Native_backend.For_testing.reset_observations ();
  let fresh_config = startup_config ~policy:0 ~entrypoint:"counter" in
  let replace_config = startup_config ~policy:1 ~entrypoint:"counter" in
  let first = Native_backend.create fresh_config in
  require (first.status = Native_backend.Ok) "Fresh runtime did not create";
  let before_rejected_create = Native_backend.For_testing.observations () in
  let duplicate = Native_backend.create fresh_config in
  require
    (duplicate.status = Native_backend.Fatal_error)
    "second Fresh runtime was accepted";
  require_substring
    duplicate.error
    "Runtime_already_active"
    "second Fresh failure did not identify the occupied singleton";
  let after_rejected_create = Native_backend.For_testing.observations () in
  require
    (after_rejected_create.driver_creations = before_rejected_create.driver_creations)
    "second Fresh create allocated another Driver";
  require
    (after_rejected_create.active_drivers = 1)
    "second Fresh create changed the active Driver count";
  require
    (after_rejected_create.peak_active_drivers = 1)
    "second Fresh create overlapped Drivers";
  require
    (Native_backend.For_testing.state () = Native_backend.For_testing.Active)
    "singleton slot did not remain Active after rejected Fresh create";
  Native_backend.For_testing.clear_state_history ();
  let replacement = Native_backend.create replace_config in
  require (replacement.status = Native_backend.Ok) "replacement runtime did not create";
  require
    (Native_backend.For_testing.state_history ()
     = [ Native_backend.For_testing.Destroying
       ; Native_backend.For_testing.Empty
       ; Native_backend.For_testing.Creating
       ; Native_backend.For_testing.Active
       ])
    "replacement did not follow Destroying -> Empty -> Creating -> Active";
  let replacement_observations = Native_backend.For_testing.observations () in
  require
    (replacement_observations.driver_shutdowns = 1)
    "replacement did not shut down the old Driver";
  require
    (replacement_observations.active_drivers = 1)
    "replacement did not leave exactly one active Driver";
  require
    (replacement_observations.peak_active_drivers = 1)
    "replacement overlapped old and new Drivers";
  let stale_pump = Native_backend.pump first.handle 0L Bytes.empty in
  require
    (stale_pump.status = Native_backend.Fatal_error)
    "tombstoned runtime accepted a stale pump";
  let stale_presentation =
    Native_backend.presentation_succeeded
      first.handle
      ID.Runtime.Presentation_id.one
      ID.Runtime.Renderer_revision.one
      0L
  in
  require
    (stale_presentation.status = Native_backend.Fatal_error)
    "tombstoned runtime accepted a stale presentation";
  Native_backend.destroy first.handle;
  let live_after_stale_destroy = Native_backend.pump replacement.handle 0L Bytes.empty in
  require
    (live_after_stale_destroy.status = Native_backend.Ok)
    "stale destroy affected the replacement runtime";
  Native_backend.destroy replacement.handle;
  let live = Native_backend.create fresh_config in
  require (live.status = Native_backend.Ok) "Fresh runtime before invalid startup failed";
  let rejected_legacy = Native_backend.create (Bytes.of_string "counter") in
  require
    (rejected_legacy.status = Native_backend.Fatal_error)
    "legacy raw configuration was accepted";
  let preserved = Native_backend.pump live.handle 0L Bytes.empty in
  require
    (preserved.status = Native_backend.Ok)
    "rejected legacy startup displaced the live runtime";
  Native_backend.destroy live.handle;
  Native_backend.For_testing.clear_state_history ();
  let failed = Native_backend.create (startup_config ~policy:0 ~entrypoint:"broken") in
  require (failed.status = Native_backend.Fatal_error) "failed startup was accepted";
  require_substring
    failed.error
    "intentional startup failure"
    "failed startup lost its original error";
  require
    (Native_backend.For_testing.state () = Native_backend.For_testing.Empty)
    "failed startup did not restore the singleton slot to Empty";
  require
    (Native_backend.For_testing.state_history ()
     = [ Native_backend.For_testing.Creating; Native_backend.For_testing.Empty ])
    "failed startup did not roll Creating back to Empty";
  let after_failure = Native_backend.create fresh_config in
  require
    (after_failure.status = Native_backend.Ok)
    "failed startup left the singleton slot unusable";
  Native_backend.destroy after_failure.handle;
  let missing = Native_backend.create (startup_config ~policy:0 ~entrypoint:"missing") in
  require (missing.status = Native_backend.Fatal_error) "unknown entrypoint was accepted";
  let trace_message message = Printf.eprintf "[Trace Fixture][ocaml]%s\n%!" message in
  Entrypoint.register
    ~name:(ID.Application.Entrypoint_name.of_string "trace-fixture")
    (App.create
       ~name:"Trace Fixture"
       ~trace:trace_message
       (application_component trace_fixture));
  let trace =
    capture_stderr (fun () ->
      let runtime =
        Native_backend.create (startup_config ~policy:0 ~entrypoint:"trace-fixture")
      in
      require (runtime.status = Native_backend.Ok) "traced runtime did not create";
      let initial = Native_backend.pump runtime.handle 0L Bytes.empty in
      require (initial.status = Native_backend.Ok) "traced initial pump failed";
      let presented =
        Native_backend.presentation_succeeded
          runtime.handle
          initial.presentation_id
          initial.revision
          0L
      in
      require (presented.status = Native_backend.Ok) "traced presentation failed";
      let idle = Native_backend.pump runtime.handle 1L Bytes.empty in
      require (idle.status = Native_backend.Ok) "traced idle pump failed";
      require (Bytes.length idle.bytes = 0) "traced idle pump emitted a frame";
      require
        (ID.Runtime.Presentation_id.compare
           idle.presentation_id
           ID.Runtime.Presentation_id.zero
         > 0)
        "successful no-diff pump returned no presentation token";
      let idle_presented =
        Native_backend.presentation_succeeded
          runtime.handle
          idle.presentation_id
          idle.revision
          1L
      in
      require
        (idle_presented.status = Native_backend.Ok)
        "traced idle presentation failed";
      let resync =
        Protocol.Inbound_event.
          { runtime_epoch =
              runtime.handle |> ID.Runtime.Handle.to_int64 |> ID.Runtime.Epoch.of_int64
          ; events =
              [ { sequence = ID.Runtime.Event_sequence.of_int64 1L
                ; displayed_revision = initial.revision
                ; node_id = ID.Ui.Node_id.zero
                ; handler_id = ID.Ui.Handler_id.zero
                ; event_tag = Protocol.Generated_protocol.Event_tag.resync_requested
                ; payload = Unit
                }
              ]
          }
      in
      let encoded_resync =
        match Protocol.Event_batch_codec.encode resync with
        | Ok bytes -> bytes
        | Error error -> fail "resync batch did not encode: %s" error.message
      in
      let resynced = Native_backend.pump runtime.handle 1L encoded_resync in
      require (resynced.status = Native_backend.Ok) "traced resync failed";
      Native_backend.destroy runtime.handle)
  in
  require_substring
    trace
    "[Trace Fixture][ocaml][widget-diff] targetRevision=1 kind=full_snapshot"
    "trace did not include the logical widget tree";
  require_substring trace "Column" "trace did not include the widget root";
  require_substring trace "test_id=trace-root" "trace omitted the fixture root";
  require_substring trace "test_id=trace-item-1" "trace omitted the first fixture item";
  require_substring
    trace
    "[Trace Fixture][ocaml][outbound-frame]"
    "trace did not include the outbound frame";
  require_substring
    trace
    "kind=full_snapshot baseRevision=0 targetRevision=1"
    "trace omitted outbound frame revisions";
  require_substring
    trace
    "[Trace Fixture][ocaml][presentation-ack] presentationId=1 revision=1"
    "trace did not include the presentation acknowledgment";
  require_no_substring
    trace
    "[Trace Fixture][ocaml][outbound-no-frame]"
    "trace included an idle no-frame message";
  require_no_substring
    trace
    "[Trace Fixture][ocaml][presentation-ack] presentationId=2 revision=1"
    "trace included an idle presentation acknowledgment";
  require_substring
    trace
    "[Trace Fixture][ocaml][inbound-event-batch]"
    "trace did not include the inbound event batch";
  require_substring
    trace
    "sequence=1 displayedRevision=1 node=0 handler=0 tag=resync_requested payload=unit"
    "trace omitted inbound event metadata";
  require
    (Native_backend.For_testing.runtime_count () = 0)
    "traced runtime destroy retained native backend handles";
  let recoverable_runtime =
    Native_backend.create (startup_config ~policy:0 ~entrypoint:"counter")
  in
  require
    (recoverable_runtime.status = Native_backend.Ok)
    "recoverable classification runtime did not create";
  let recoverable_initial =
    Native_backend.pump recoverable_runtime.handle 0L Bytes.empty
  in
  require
    (recoverable_initial.status = Native_backend.Ok)
    "recoverable classification initial pump failed";
  let recoverable_presented =
    Native_backend.presentation_succeeded
      recoverable_runtime.handle
      recoverable_initial.presentation_id
      recoverable_initial.revision
      0L
  in
  require
    (recoverable_presented.status = Native_backend.Ok)
    "recoverable classification initial presentation failed";
  let recoverable =
    Native_backend.pump recoverable_runtime.handle 1L (Bytes.of_string "\255")
  in
  require
    (recoverable.status = Native_backend.Recoverable_error)
    "malformed input no longer retained its recoverable classification";
  require
    (ID.Ffi.Error_code.equal recoverable.error_code (ID.Ffi.Error_code.of_int 1))
    "malformed input changed its existing error code";
  require
    (ID.Runtime.Presentation_id.compare
       recoverable.presentation_id
       ID.Runtime.Presentation_id.zero
     > 0)
    "recoverable dropped-input pump returned no presentation token";
  Native_backend.destroy recoverable_runtime.handle;
  let duplicate_runtime =
    Native_backend.create (startup_config ~policy:0 ~entrypoint:"duplicate-key")
  in
  require
    (duplicate_runtime.status = Native_backend.Ok)
    "duplicate-key runtime did not create";
  let duplicate = Native_backend.pump duplicate_runtime.handle 0L Bytes.empty in
  require
    (duplicate.status = Native_backend.Fatal_error)
    "Duplicate_key pump was not classified as fatal";
  require
    (ID.Ffi.Error_code.equal duplicate.error_code (ID.Ffi.Error_code.of_int 3))
    "Duplicate_key changed its existing error code";
  require
    (ID.Runtime.Presentation_id.equal
       duplicate.presentation_id
       ID.Runtime.Presentation_id.zero)
    "fatal Duplicate_key pump returned a presentation token";
  require
    (ID.Runtime.Renderer_revision.equal
       duplicate.revision
       ID.Runtime.Renderer_revision.zero)
    "fatal Duplicate_key pump returned a renderer revision";
  require (Bytes.length duplicate.bytes = 0) "fatal Duplicate_key pump returned bytes";
  require_substring
    duplicate.error
    "journal-row-focus:duplicate"
    "fatal Duplicate_key diagnostic omitted the duplicate key";
  require_substring
    duplicate.error
    "in candidate children"
    "fatal Duplicate_key diagnostic omitted the candidate side";
  require_substring
    duplicate.error
    "Column[key=\"runtime-root\"]"
    "fatal Duplicate_key diagnostic omitted the root path";
  require_substring
    duplicate.error
    "> Frame"
    "fatal Duplicate_key diagnostic omitted the unkeyed ancestor";
  require_substring
    duplicate.error
    "> Row[key=\"runtime-parent\"]"
    "fatal Duplicate_key diagnostic omitted the duplicate parent";
  require_substring
    duplicate.error
    "child[1]: Text"
    "fatal Duplicate_key diagnostic omitted the first occurrence";
  require_substring
    duplicate.error
    "child[2]: Empty"
    "fatal Duplicate_key diagnostic omitted the second occurrence";
  require_no_substring
    duplicate.error
    "OCaml pump returned no presentation token"
    "fatal Duplicate_key diagnostic was replaced by the token invariant error";
  Native_backend.destroy duplicate_runtime.handle;
  Native_backend.For_testing.final_shutdown ();
  Native_backend.For_testing.final_shutdown ();
  require
    (Native_backend.For_testing.state () = Native_backend.For_testing.Finalized)
    "final shutdown did not enter the absorbing Finalized state";
  let stopped = Native_backend.create fresh_config in
  require (stopped.status = Native_backend.Fatal_error) "create after Finalized succeeded";
  require_substring
    stopped.error
    "Runtime_stopped"
    "create after Finalized returned the wrong error"
;;
