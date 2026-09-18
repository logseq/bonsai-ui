module ID = Bonsai_swiftui_spec.Id
module Ui = Bonsai_swiftui_ui

module Handler_map = Map.Make (struct
    type t = Handler_id.t

    let compare = Handler_id.compare
  end)

module Handler_set = Set.Make (struct
    type t = Handler_id.t

    let compare = Handler_id.compare
  end)

module Node_map = Map.Make (struct
    type t = Node_id.t

    let compare = Node_id.compare
  end)

module Frame = struct
  type entry =
    { node_id : Node_id.t
    ; event_tag : Ui.Event.Tag.t
    ; handler_id : Handler_id.t
    ; handler : Ui.Event.Handler.t
    }

  type t =
    { revision : ID.Runtime.renderer_revision
    ; entries : entry Handler_map.t
    ; list_scroll_entries : entry Node_map.t
    }

  let revision t = t.revision
  let find t handler_id = Handler_map.find_opt handler_id t.entries

  let find_list_scroll_completion t node_id =
    Node_map.find_opt node_id t.list_scroll_entries
  ;;

  let scroll_entries entries =
    Handler_map.fold
      (fun _ entry result ->
         if Ui.Event.Tag.equal entry.event_tag Ui.Event.Tag.List_scroll_completed
         then Node_map.add entry.node_id entry result
         else result)
      entries
      Node_map.empty
  ;;

  module Private = struct
    let create ~revision entries =
      let entries =
        List.fold_left
          (fun entries entry ->
             if Handler_map.mem entry.handler_id entries
             then invalid_arg "Handler_registry.Frame: duplicate handler ID";
             Handler_map.add entry.handler_id entry entries)
          Handler_map.empty
          entries
      in
      { revision; entries; list_scroll_entries = scroll_entries entries }
    ;;

    let empty ~revision =
      { revision; entries = Handler_map.empty; list_scroll_entries = Node_map.empty }
    ;;

    let derive ~revision ~base_revision ~base ~removals ~additions =
      if not (ID.Runtime.Renderer_revision.equal base.revision base_revision)
      then invalid_arg "Handler_registry.Frame: base revision mismatch";
      let entries, _ =
        List.fold_left
          (fun (entries, seen) handler_id ->
             if Handler_set.mem handler_id seen
             then invalid_arg "Handler_registry.Frame: duplicate handler removal";
             if not (Handler_map.mem handler_id entries)
             then invalid_arg "Handler_registry.Frame: missing handler removal";
             Handler_map.remove handler_id entries, Handler_set.add handler_id seen)
          (base.entries, Handler_set.empty)
          removals
      in
      let entries =
        List.fold_left
          (fun entries entry ->
             if Handler_map.mem entry.handler_id entries
             then invalid_arg "Handler_registry.Frame: duplicate handler ID";
             Handler_map.add entry.handler_id entry entries)
          entries
          additions
      in
      let list_scroll_entries =
        List.fold_left
          (fun index handler_id ->
             match Handler_map.find_opt handler_id base.entries with
             | Some entry
               when Ui.Event.Tag.equal entry.event_tag Ui.Event.Tag.List_scroll_completed
               -> Node_map.remove entry.node_id index
             | _ -> index)
          base.list_scroll_entries
          removals
      in
      let list_scroll_entries =
        List.fold_left
          (fun index (entry : entry) ->
             if Ui.Event.Tag.equal entry.event_tag Ui.Event.Tag.List_scroll_completed
             then Node_map.add entry.node_id entry index
             else index)
          list_scroll_entries
          additions
      in
      { revision; entries; list_scroll_entries }
    ;;
  end
end

type event =
  { runtime_epoch : ID.Runtime.epoch
  ; displayed_revision : ID.Runtime.renderer_revision
  ; node_id : Node_id.t
  ; event_tag : Ui.Event.Tag.t
  ; handler_id : Handler_id.t
  ; event_sequence : ID.Runtime.event_sequence
  ; payload : Ui.Event.Payload.t
  }

type list_scroll_owner =
  { mutable latest : int64
  ; callbacks : (int64, ID.Runtime.renderer_revision * Frame.entry) Hashtbl.t
  }

type t =
  { runtime_epoch : ID.Runtime.epoch
  ; frames : (ID.Runtime.renderer_revision, Frame.t) Hashtbl.t
  ; list_scroll_owners : (Node_id.t, list_scroll_owner) Hashtbl.t
  ; mutable displayed_revision : ID.Runtime.renderer_revision option
  ; mutable last_event_sequence : ID.Runtime.event_sequence option
  }

let create ~runtime_epoch =
  { runtime_epoch
  ; frames = Hashtbl.create 4
  ; list_scroll_owners = Hashtbl.create 4
  ; displayed_revision = None
  ; last_event_sequence = None
  }
;;

let retain_list_scroll_completion t ~revision ~token (entry : Frame.entry) =
  if
    token <= 0L
    || not (Ui.Event.Tag.equal entry.event_tag Ui.Event.Tag.List_scroll_completed)
  then invalid_arg "Handler_registry: invalid List scroll completion snapshot";
  match Hashtbl.find_opt t.list_scroll_owners entry.node_id with
  | Some owner when token <= owner.latest -> ()
  | previous ->
    let owner =
      match previous with
      | Some owner -> owner
      | None ->
        let owner = { latest = token; callbacks = Hashtbl.create 2 } in
        Hashtbl.add t.list_scroll_owners entry.node_id owner;
        owner
    in
    owner.latest <- token;
    Hashtbl.add owner.callbacks token (revision, entry)
;;

let dispose_list_scroll_owner t node_id = Hashtbl.remove t.list_scroll_owners node_id
let clear_list_scroll_completions t = Hashtbl.clear t.list_scroll_owners

let terminal_token (event : event) =
  if Ui.Event.Tag.equal event.event_tag Ui.Event.Tag.List_scroll_completed
  then (
    match event.payload with
    | Ui.Event.Payload.Int64_pair { first; second }
      when first > 0L && second >= 0L && second <= 5L -> Some first
    | _ -> None)
  else None
;;

let terminal_entry t event =
  Option.bind (terminal_token event) (fun token ->
    Option.bind (Hashtbl.find_opt t.list_scroll_owners event.node_id) (fun owner ->
      Option.bind (Hashtbl.find_opt owner.callbacks token) (fun (revision, entry) ->
        if ID.Runtime.Renderer_revision.compare event.displayed_revision revision < 0
        then None
        else Some entry)))
;;

let install t frame =
  let revision = Frame.revision frame in
  if Hashtbl.mem t.frames revision
  then
    Error
      (Runtime_error.Invalid_patch
         (Printf.sprintf
            "handler frame %Ld is already installed"
            (ID.Runtime.Renderer_revision.to_int64 revision)))
  else (
    Hashtbl.add t.frames revision frame;
    Ok ())
;;

let mark_displayed_revision t ~revision =
  match Hashtbl.find_opt t.frames revision with
  | None -> Error (Runtime_error.Stale_event { revision })
  | Some _ ->
    (match t.displayed_revision with
     | Some current when ID.Runtime.Renderer_revision.compare revision current < 0 ->
       Error (Runtime_error.Revision_mismatch { expected = current; actual = revision })
     | None | Some _ ->
       t.displayed_revision <- Some revision;
       Ok ())
;;

let retire_before t ~revision =
  let retired =
    Hashtbl.to_seq_keys t.frames
    |> Seq.filter (fun candidate ->
      ID.Runtime.Renderer_revision.compare candidate revision < 0)
    |> List.of_seq
  in
  List.iter (Hashtbl.remove t.frames) retired
;;

let retire_superseded t ~displayed_revision =
  retire_before t ~revision:(ID.Runtime.Renderer_revision.pred displayed_revision)
;;

let commit_displayed_revision t ~revision =
  match mark_displayed_revision t ~revision with
  | Error _ as error -> error
  | Ok () ->
    retire_superseded t ~displayed_revision:revision;
    Ok ()
;;

let exception_message = function
  | Failure message | Invalid_argument message -> message
  | exception_ -> Printexc.to_string exception_
;;

let validate_event t ~last_event_sequence (event : event) =
  if not (ID.Runtime.Epoch.equal event.runtime_epoch t.runtime_epoch)
  then
    Error
      (Runtime_error.Wrong_runtime_epoch
         { expected = t.runtime_epoch; actual = event.runtime_epoch })
  else (
    match last_event_sequence with
    | Some last when ID.Runtime.Event_sequence.compare event.event_sequence last <= 0 ->
      Error
        (Runtime_error.Duplicate_or_out_of_order_event { sequence = event.event_sequence })
    | None | Some _ ->
      (match t.displayed_revision with
       | None -> Error (Runtime_error.Stale_event { revision = event.displayed_revision })
       | Some displayed
         when ID.Runtime.Renderer_revision.compare event.displayed_revision displayed > 0
         -> Error (Runtime_error.Stale_event { revision = event.displayed_revision })
       | Some _ ->
         (match Hashtbl.find_opt t.frames event.displayed_revision with
          | None ->
            Error (Runtime_error.Stale_event { revision = event.displayed_revision })
          | Some frame ->
            (match
               if Ui.Event.Tag.equal event.event_tag Ui.Event.Tag.List_scroll_completed
               then terminal_entry t event
               else Frame.find frame event.handler_id
             with
             | None ->
               Error (Runtime_error.Handler_missing { handler_id = event.handler_id })
             | Some entry ->
               if
                 (not (Handler_id.equal entry.handler_id event.handler_id))
                 || (not (Node_id.equal entry.node_id event.node_id))
                 || not (Ui.Event.Tag.equal entry.event_tag event.event_tag)
               then
                 Error
                   (Runtime_error.Handler_mismatch
                      { handler_id = event.handler_id
                      ; node_id = event.node_id
                      ; event_tag = event.event_tag
                      })
               else Ok (event, entry)))))
;;

module Validated_batch = struct
  type validated_event = event * Frame.entry

  type t =
    { events : validated_event list
    ; last_event_sequence : ID.Runtime.event_sequence option
    }
end

let validate_batch t events =
  let terminal_seen = Hashtbl.create 4 in
  let rec validate reversed last_event_sequence = function
    | [] -> Ok Validated_batch.{ events = List.rev reversed; last_event_sequence }
    | event :: rest ->
      (match validate_event t ~last_event_sequence event with
       | Error _ as error -> error
       | Ok validated ->
         let duplicate =
           match terminal_token event with
           | None -> false
           | Some token ->
             let key = event.node_id, token in
             let present = Hashtbl.mem terminal_seen key in
             Hashtbl.replace terminal_seen key ();
             present
         in
         if duplicate
         then Error (Runtime_error.Handler_missing { handler_id = event.handler_id })
         else validate (validated :: reversed) (Some event.event_sequence) rest)
  in
  validate [] t.last_event_sequence events
;;

let dispatch_validated t (validated : Validated_batch.t) =
  let rec invoke = function
    | [] ->
      t.last_event_sequence <- validated.last_event_sequence;
      Ok ()
    | (event, _) :: _
      when Ui.Event.Tag.equal event.event_tag Ui.Event.Tag.List_scroll_completed
           && Option.is_none (terminal_entry t event) ->
      Error (Runtime_error.Handler_missing { handler_id = event.handler_id })
    | (event, entry) :: rest ->
      (try
         (match terminal_token event with
          | None -> ()
          | Some token ->
            Option.iter
              (fun owner -> Hashtbl.remove owner.callbacks token)
              (Hashtbl.find_opt t.list_scroll_owners event.node_id));
         Ui.Event.Handler.Private.invoke entry.Frame.handler event.payload;
         invoke rest
       with
       | exception_ ->
         let backtrace = Printexc.get_raw_backtrace () in
         Error
           (Runtime_error.Handler_exception
              { handler_id = event.handler_id
              ; message = exception_message exception_
              ; backtrace = Printexc.raw_backtrace_to_string backtrace
              }))
  in
  invoke validated.events
;;

let dispatch_batch t events =
  match validate_batch t events with
  | Error _ as error -> error
  | Ok validated -> dispatch_validated t validated
;;

let dispatch t event = dispatch_batch t [ event ]
let retained_frame_count t = Hashtbl.length t.frames

let clear t =
  Hashtbl.clear t.frames;
  clear_list_scroll_completions t;
  t.displayed_revision <- None;
  t.last_event_sequence <- None
;;
