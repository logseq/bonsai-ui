module Protocol = Bonsai_swiftui_protocol
module Runtime = Bonsai_swiftui_runtime
module Ui = Bonsai_swiftui_ui
module ID = Bonsai_swiftui_spec.Id

type t =
  { driver : Driver.t
  ; runtime_epoch : ID.Runtime.epoch
  ; mutable sequence : ID.Runtime.event_sequence
  ; mutable last_frame : Driver.frame option
  ; mutable last_pump_result : Driver.pump_result option
  ; mutable next_monotonic_ns : int64
  ; mutable baseline : string
  ; pending_requests :
      (ID.Host.request_id, Protocol.Wire_frame.host_request_payload) Hashtbl.t
  }

let fail format = Printf.ksprintf failwith format

let driver_ok = function
  | Ok value -> value
  | Error error -> fail "headless driver error: %s" (Driver.error_to_string error)
;;

let record_frame t frame =
  t.last_frame <- Some frame;
  match Protocol.Binary_codec.decode frame.Driver.bytes with
  | Error error -> fail "headless frame did not decode: %s" error.message
  | Ok wire ->
    List.iter
      (function
        | Protocol.Wire_frame.Host_request { request_id; payload } ->
          Hashtbl.replace t.pending_requests request_id payload
        | Cancel_host_request { request_id } ->
          Hashtbl.remove t.pending_requests request_id
        | _ -> ())
      wire.operations
;;

let logical_pump t ?events () =
  let monotonic_now_ns = t.next_monotonic_ns in
  t.next_monotonic_ns <- Int64.succ monotonic_now_ns;
  let result = driver_ok (Driver.pump t.driver ~monotonic_now_ns ?events ()) in
  Option.iter (record_frame t) result.frame;
  t.last_pump_result <- Some result
;;

let pump_next = logical_pump

let snapshot t =
  match Driver.For_testing.snapshot t.driver with
  | Some snapshot -> snapshot
  | None -> fail "headless driver has no mounted tree"
;;

let ordered_nodes snapshot =
  let rec visit reversed node_id =
    match Runtime.Mounted_tree.Snapshot.find snapshot node_id with
    | None ->
      fail
        "mounted snapshot references missing node %Ld"
        (Runtime.Node_id.to_int64 node_id)
    | Some node ->
      let children =
        let (Av view) = Ui.View.Private.view node.widget in
        match view.node with
        | Ui.View.Private.Morphing_surface { expanded; _ }
          when Array.length node.children = 2 ->
          [| node.children.(if expanded then 1 else 0) |]
        | _ -> node.children
      in
      Array.fold_left visit (node :: reversed) children
  in
  match Runtime.Mounted_tree.Snapshot.root_id snapshot with
  | None -> []
  | Some root_id -> List.rev (visit [] root_id)
;;

let find_all t query =
  snapshot t |> ordered_nodes |> List.filter (Query.Private.matches query)
;;

let find t query = List.nth_opt (find_all t query) 0

let require_node t query =
  match find_all t query with
  | [ node ] -> node
  | [] -> fail "query did not match a mounted node"
  | nodes ->
    fail "query matched %d nodes; interaction queries must be unique" (List.length nodes)
;;

let unquote_debug_key key =
  let value = Ui.Key.to_debug_string key in
  let length = String.length value in
  if length >= 2 && value.[0] = '"' && value.[length - 1] = '"'
  then String.sub value 1 (length - 2)
  else value
;;

let render_tree t =
  let snapshot = snapshot t in
  let output = Buffer.create 256 in
  let rec write depth node_id =
    let node =
      match Runtime.Mounted_tree.Snapshot.find snapshot node_id with
      | Some node -> node
      | None ->
        fail
          "mounted snapshot references missing node %Ld"
          (Runtime.Node_id.to_int64 node_id)
    in
    if Buffer.length output > 0 then Buffer.add_char output '\n';
    Buffer.add_string output (String.make (depth * 2) ' ');
    Buffer.add_string output (Ui.View.Private.kind_tag_to_string node.node_tag);
    Option.iter
      (fun key -> Printf.bprintf output " key=%s" (unquote_debug_key key))
      node.key;
    Option.iter
      (fun test_id -> Printf.bprintf output " test_id=%s" (Ui.Test_id.to_string test_id))
      node.test_id;
    (let (Av view) = Ui.View.Private.view node.widget in
     match view.node with
     | Ui.View.Private.Text { value; _ } ->
       Buffer.add_char output ' ';
       Buffer.add_string output (Printf.sprintf "%S" value)
     | Native_widget { kind_id; version; _ } ->
       Printf.bprintf
         output
         " native_kind=%d version=%d"
         (ID.Native_widget.Kind_id.to_int kind_id)
         version
     | _ -> ());
    if Array.length node.event_bindings > 0
    then (
      Buffer.add_string output " events=[";
      Array.iteri
        (fun index (binding : Runtime.Mounted_tree.Mounted_binding.t) ->
           if index > 0 then Buffer.add_char output ',';
           Buffer.add_string output (Ui.Event.Tag.to_string binding.event_tag))
        node.event_bindings;
      Buffer.add_char output ']');
    Array.iter (write (depth + 1)) node.children
  in
  (match Runtime.Mounted_tree.Snapshot.root_id snapshot with
   | None -> ()
   | Some root_id -> write 0 root_id);
  Buffer.contents output
;;

let show t =
  let rendered = render_tree t in
  t.baseline <- rendered;
  rendered
;;

let lines value =
  if String.length value = 0
  then [||]
  else String.split_on_char '\n' value |> Array.of_list
;;

let show_diff t =
  let current = render_tree t in
  let before = lines t.baseline in
  let after = lines current in
  let output = Buffer.create 128 in
  let add_line prefix value =
    if Buffer.length output > 0 then Buffer.add_char output '\n';
    Buffer.add_string output prefix;
    Buffer.add_string output value
  in
  let count = max (Array.length before) (Array.length after) in
  for index = 0 to count - 1 do
    let left = if index < Array.length before then Some before.(index) else None in
    let right = if index < Array.length after then Some after.(index) else None in
    match left, right with
    | Some left, Some right when String.equal left right -> ()
    | Some left, Some right ->
      add_line "- " left;
      add_line "+ " right
    | Some left, None -> add_line "- " left
    | None, Some right -> add_line "+ " right
    | None, None -> ()
  done;
  t.baseline <- current;
  Buffer.contents output
;;

let protocol_tag =
  let module Tag = Protocol.Generated_protocol.Event_tag in
  function
  | Ui.Event.Tag.Press -> Tag.press
  | Long_press -> Tag.long_press
  | Tap -> Tag.tap
  | Double_tap -> Tag.double_tap
  | Pointer_enter -> Tag.pointer_enter
  | Pointer_leave -> Tag.pointer_leave
  | Pointer_down -> Tag.pointer_down
  | Pointer_up -> Tag.pointer_up
  | Key -> Tag.key
  | Focus_changed -> Tag.focus_changed
  | Text_edit -> Tag.text_edit
  | Text_submit -> Tag.text_submit
  | Text_limit_reached -> Tag.text_limit_reached
  | Scroll_notification -> Tag.scroll_notification
  | Visible_range_changed -> Tag.visible_range_changed
  | Animation_completed -> Tag.animation_completed
  | Tab_selected -> Tag.tab_selected
  | Navigation_split_changed -> Tag.navigation_split_changed
  | Navigation_path_changed -> Tag.navigation_path_changed
  | Layout_observed -> Tag.layout_observed
  | Value_changed -> Tag.value_changed
  | Native_event -> Tag.native_event
  | Semantics_action -> Tag.semantics_action
  | Navigation_destination_selected -> Tag.navigation_destination_selected
  | Radio_selected -> Tag.radio_selected
  | Removal_requested -> Tag.removal_requested
  | Removal_completed -> Tag.removal_completed
  | Refresh_request -> Tag.refresh_request
  | Scroll_position_changed -> Tag.scroll_position_changed
  | Menu_action -> Tag.menu_action
  | Picker_selected -> Tag.picker_selected
  | Slider_changed -> Tag.slider_changed
  | Slider_change_end -> Tag.slider_change_end
  | Range_slider_changed -> Tag.range_slider_changed
  | Range_slider_change_end -> Tag.range_slider_change_end
  | Table_sort_requested -> Tag.table_sort_requested
  | Table_row_selected -> Tag.table_row_selected
  | Civil_date_changed -> Tag.civil_date_changed
  | Civil_time_changed -> Tag.civil_time_changed
;;

let dispatch t query tag payload =
  let node = require_node t query in
  let binding =
    Array.find_opt
      (fun binding ->
         Ui.Event.Tag.equal binding.Runtime.Mounted_tree.Mounted_binding.event_tag tag)
      node.event_bindings
    |> function
    | Some binding -> binding
    | None ->
      fail
        "node %Ld does not bind event %s"
        (Runtime.Node_id.to_int64 node.node_id)
        (Ui.Event.Tag.to_string tag)
  in
  t.sequence <- ID.Runtime.Event_sequence.succ t.sequence;
  let event =
    Protocol.Inbound_event.
      { sequence = t.sequence
      ; displayed_revision = Driver.For_testing.revision t.driver
      ; node_id = node.node_id
      ; handler_id = binding.handler_id
      ; event_tag = protocol_tag tag
      ; payload
      }
  in
  logical_pump
    t
    ~events:Protocol.Inbound_event.{ runtime_epoch = t.runtime_epoch; events = [ event ] }
    ()
;;

let click t query =
  let node = require_node t query in
  let binds tag =
    Array.exists
      (fun binding ->
         Ui.Event.Tag.equal binding.Runtime.Mounted_tree.Mounted_binding.event_tag tag)
      node.event_bindings
  in
  if binds Ui.Event.Tag.Press
  then dispatch t query Ui.Event.Tag.Press Protocol.Inbound_event.Unit
  else if binds Ui.Event.Tag.Tap
  then
    dispatch
      t
      query
      Ui.Event.Tag.Tap
      (Protocol.Inbound_event.Tap
         { local_x = 0.
         ; local_y = 0.
         ; global_x = 0.
         ; global_y = 0.
         ; pointer_kind = Mouse
         })
  else fail "matched node does not bind a press or tap event"
;;

let long_press t query =
  dispatch t query Ui.Event.Tag.Long_press Protocol.Inbound_event.Unit
;;

let tab_selected t query ~page_key =
  dispatch
    t
    query
    Ui.Event.Tag.Tab_selected
    (Protocol.Inbound_event.Tab_selected page_key)
;;

let navigation_split_changed t query ~state =
  let visibility, compact_column, selection_key =
    Ui.Navigation.Split_state.Private.to_codes state
  in
  dispatch
    t
    query
    Ui.Event.Tag.Navigation_split_changed
    (Protocol.Inbound_event.Navigation_split_changed
       { visibility; compact_column; selection_key })
;;

let native_event t query ~kind_id ~version ~event_id ~payload =
  dispatch
    t
    query
    Ui.Event.Tag.Native_event
    (Protocol.Inbound_event.Native_event { kind_id; version; event_id; payload })
;;

let visible_range t query ~first_index ~last_exclusive =
  dispatch
    t
    query
    Ui.Event.Tag.Visible_range_changed
    (Protocol.Inbound_event.Visible_range { first_index; last_exclusive })
;;

let apply_text_edit
      t
      query
      ~local_revision
      ~base_document_revision
      ~text
      ~selection_start
      ~selection_end
      ?composing_start
      ?composing_end
      ()
  =
  let node = require_node t query in
  let session_id =
    let (Av view) = Ui.View.Private.view node.widget in
    match view.node with
    | Ui.View.Private.Text_field { session_id; _ } -> session_id
    | Ui.View.Private.Text_editor { session_id; _ } -> session_id
    | _ -> fail "text edit query did not match a native text input node"
  in
  let selection =
    Protocol.Inbound_event.{ start_utf16 = selection_start; end_utf16 = selection_end }
  in
  let composing =
    match composing_start, composing_end with
    | None, None -> None
    | Some start_utf16, Some end_utf16 ->
      Some Protocol.Inbound_event.{ start_utf16; end_utf16 }
    | None, Some _ | Some _, None ->
      invalid_arg "Handle.apply_text_edit: composing bounds must be supplied together"
  in
  dispatch
    t
    query
    Ui.Event.Tag.Text_edit
    (Protocol.Inbound_event.Text_edit
       { session_id; local_revision; base_document_revision; text; selection; composing })
;;

let input_text t query text =
  let node = require_node t query in
  let document_revision, accepted_local_revision =
    let (Av view) = Ui.View.Private.view node.widget in
    match view.node with
    | Ui.View.Private.Text_field { document_revision; accepted_local_revision; _ } ->
      document_revision, accepted_local_revision
    | Ui.View.Private.Text_editor { document_revision; accepted_local_revision; _ } ->
      document_revision, accepted_local_revision
    | _ -> fail "input_text query did not match a native text input node"
  in
  let cursor = Ui.Text_editing.Utf16.length text in
  apply_text_edit
    t
    query
    ~local_revision:(ID.Text_input.Local_revision.succ accepted_local_revision)
    ~base_document_revision:document_revision
    ~text
    ~selection_start:cursor
    ~selection_end:cursor
    ()
;;

let key_down t query ~logical_key =
  dispatch
    t
    query
    Ui.Event.Tag.Key
    (Protocol.Inbound_event.Key
       { logical_key
       ; physical_key = ID.Input.Physical_key.zero
       ; action = Key_down
       ; modifiers = 0
       })
;;

let focus t query =
  dispatch t query Ui.Event.Tag.Focus_changed (Protocol.Inbound_event.Bool true)
;;

let blur t query =
  dispatch t query Ui.Event.Tag.Focus_changed (Protocol.Inbound_event.Bool false)
;;

let protocol_environment (environment : Environment.snapshot) =
  let insets (value : Environment.edge_insets) =
    Protocol.Inbound_event.
      { left = value.left; top = value.top; right = value.right; bottom = value.bottom }
  in
  Protocol.Inbound_event.
    { viewport_width = environment.viewport_width
    ; viewport_height = environment.viewport_height
    ; device_pixel_ratio = environment.device_pixel_ratio
    ; text_scale = environment.text_scale
    ; brightness =
        (match environment.brightness with
         | Environment.Light -> Environment_light
         | Dark -> Environment_dark)
    ; platform = environment.platform
    ; locale = environment.locale
    ; safe_area = insets environment.safe_area
    ; keyboard_insets = insets environment.keyboard_insets
    ; accessible_navigation = environment.accessible_navigation
    ; bold_text = environment.bold_text
    ; invert_colors = environment.invert_colors
    ; disable_animations = environment.disable_animations
    ; reduced_motion = environment.reduced_motion
    ; high_contrast = environment.high_contrast
    ; orientation =
        (match environment.orientation with
         | Environment.Portrait -> Portrait
         | Landscape -> Landscape)
    ; pointer_kinds = environment.pointer_kinds
    }
;;

let set_environment t environment =
  t.sequence <- ID.Runtime.Event_sequence.succ t.sequence;
  let event =
    Protocol.Inbound_event.
      { sequence = t.sequence
      ; displayed_revision = Driver.For_testing.revision t.driver
      ; node_id = ID.Ui.Node_id.zero
      ; handler_id = ID.Ui.Handler_id.zero
      ; event_tag = Protocol.Generated_protocol.Event_tag.environment_changed
      ; payload = Environment_changed (protocol_environment environment)
      }
  in
  logical_pump
    t
    ~events:Protocol.Inbound_event.{ runtime_epoch = t.runtime_epoch; events = [ event ] }
    ()
;;

let resize t ~width ~height =
  let environment = Driver.For_testing.environment t.driver in
  set_environment t { environment with viewport_width = width; viewport_height = height }
;;

let only_pending_request t =
  match
    Hashtbl.to_seq_keys t.pending_requests
    |> List.of_seq
    |> List.sort ID.Host.Request_id.compare
  with
  | [ request_id ] -> request_id
  | [] -> fail "no host effect is pending"
  | requests ->
    fail "%d host effects are pending; pass request_id explicitly" (List.length requests)
;;

let respond_to_host_effect t ?request_id ?(status = Protocol.Inbound_event.Host_ok) value =
  let request_id =
    match request_id with
    | Some request_id -> request_id
    | None -> only_pending_request t
  in
  if not (Hashtbl.mem t.pending_requests request_id)
  then fail "host request %Ld is not pending" (ID.Host.Request_id.to_int64 request_id);
  t.sequence <- ID.Runtime.Event_sequence.succ t.sequence;
  let event =
    Protocol.Inbound_event.
      { sequence = t.sequence
      ; displayed_revision = Driver.For_testing.revision t.driver
      ; node_id = ID.Ui.Node_id.zero
      ; handler_id = ID.Ui.Handler_id.zero
      ; event_tag = Protocol.Generated_protocol.Event_tag.host_response
      ; payload = Host_response { request_id; status; value }
      }
  in
  logical_pump
    t
    ~events:Protocol.Inbound_event.{ runtime_epoch = t.runtime_epoch; events = [ event ] }
    ();
  Hashtbl.remove t.pending_requests request_id
;;

let present t =
  match t.last_pump_result with
  | None -> ()
  | Some result ->
    let monotonic_now_ns = t.next_monotonic_ns in
    driver_ok
      (Driver.presentation_succeeded
         t.driver
         ~presentation_id:result.presentation_id
         ~renderer_revision:result.renderer_revision
         ~monotonic_now_ns);
    t.last_pump_result <- None
;;

let pump t ~monotonic_now_ns ?events () =
  let result = driver_ok (Driver.pump t.driver ~monotonic_now_ns ?events ()) in
  Option.iter (record_frame t) result.frame;
  t.last_pump_result <- Some result;
  t.next_monotonic_ns <- Int64.succ monotonic_now_ns;
  result
;;

let unresolved_presentation t =
  match t.last_pump_result with
  | Some result -> result
  | None -> fail "headless driver has no unresolved presentation"
;;

let presentation_succeeded t ~monotonic_now_ns =
  let result = unresolved_presentation t in
  driver_ok
    (Driver.presentation_succeeded
       t.driver
       ~presentation_id:result.presentation_id
       ~renderer_revision:result.renderer_revision
       ~monotonic_now_ns);
  t.last_pump_result <- None
;;

let presentation_rejected t ~reason =
  let result = unresolved_presentation t in
  driver_ok
    (Driver.presentation_rejected
       t.driver
       ~presentation_id:result.presentation_id
       ~renderer_revision:result.renderer_revision
       ~reason);
  t.last_pump_result <- None
;;

let unresolved_presentation_id t =
  Option.map (fun result -> result.Driver.presentation_id) t.last_pump_result
;;

let last_frame t = t.last_frame
let revision t = Driver.For_testing.revision t.driver
let pending_host_effect_count t = Driver.For_testing.pending_host_effect_count t.driver
let shutdown t = Driver.shutdown t.driver

let create_from_driver ~runtime_epoch driver =
  let t =
    { driver
    ; runtime_epoch
    ; sequence = ID.Runtime.Event_sequence.zero
    ; last_frame = None
    ; last_pump_result = None
    ; next_monotonic_ns = 0L
    ; baseline = ""
    ; pending_requests = Hashtbl.create 4
    }
  in
  logical_pump t ();
  (match t.last_pump_result with
   | Some { frame = Some _; _ } -> ()
   | None | Some { frame = None; _ } ->
     fail "initial headless pump did not emit a full snapshot");
  t.baseline <- render_tree t;
  t
;;

let create ~runtime_epoch ~time_source component =
  let theme = Bonsai_swiftui_ui.Theme.create () in
  Driver.create ~runtime_epoch ~time_source (fun handlers graph ->
    Bonsai.Cont.map (component handlers graph) ~f:(fun body ->
      Driver.View.create ~theme ~body:(Ui.View.Body.static body)))
  |> create_from_driver ~runtime_epoch
;;

let create_app ~runtime_epoch ~time_source app ~application_payload =
  match App.Private.instantiate app ~runtime_epoch ~application_payload with
  | Error error -> fail "headless App initialization failed: %s" error
  | Ok instance ->
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
    create_from_driver ~runtime_epoch driver
;;
