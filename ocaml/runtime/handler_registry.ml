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
    }

  let revision t = t.revision
  let find t handler_id = Handler_map.find_opt handler_id t.entries

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
      { revision; entries }
    ;;

    let empty ~revision = { revision; entries = Handler_map.empty }

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
      { revision; entries }
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

type t =
  { runtime_epoch : ID.Runtime.epoch
  ; frames : (ID.Runtime.renderer_revision, Frame.t) Hashtbl.t
  ; mutable displayed_revision : ID.Runtime.renderer_revision option
  ; mutable last_event_sequence : ID.Runtime.event_sequence option
  }

let create ~runtime_epoch =
  { runtime_epoch
  ; frames = Hashtbl.create 4
  ; displayed_revision = None
  ; last_event_sequence = None
  }
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
            (match Frame.find frame event.handler_id with
             | None ->
               Error (Runtime_error.Handler_missing { handler_id = event.handler_id })
             | Some entry ->
               if
                 (not (Node_id.equal entry.node_id event.node_id))
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
  let rec validate reversed last_event_sequence = function
    | [] -> Ok Validated_batch.{ events = List.rev reversed; last_event_sequence }
    | event :: rest ->
      (match validate_event t ~last_event_sequence event with
       | Error _ as error -> error
       | Ok validated -> validate (validated :: reversed) (Some event.event_sequence) rest)
  in
  validate [] t.last_event_sequence events
;;

let dispatch_validated t (validated : Validated_batch.t) =
  let rec invoke = function
    | [] ->
      t.last_event_sequence <- validated.last_event_sequence;
      Ok ()
    | (event, entry) :: rest ->
      (try
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
  t.displayed_revision <- None;
  t.last_event_sequence <- None
;;
