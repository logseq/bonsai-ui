module ID = Bonsai_swiftui_spec.Id
module Ui = Bonsai_swiftui_ui
module View = Ui.View

module Key_table = Hashtbl.Make (struct
    type t = Ui.Key.t

    let equal = Ui.Key.equal
    let hash = Ui.Key.hash
  end)

type t =
  { runtime_epoch : ID.Runtime.epoch
  ; mutable next_node_id : ID.Ui.node_id
  ; mutable next_handler_id : ID.Ui.handler_id
  }

type output =
  { mounted_tree : Mounted_tree.t
  ; frame_patch : Frame_patch.t
  ; handler_frame : Handler_registry.Frame.t
  }

let create ~runtime_epoch =
  { runtime_epoch
  ; next_node_id = ID.Ui.Node_id.one
  ; next_handler_id = ID.Ui.Handler_id.one
  }
;;

let allocate_node_id t =
  let allocated = t.next_node_id in
  t.next_node_id <- ID.Ui.Node_id.succ allocated;
  allocated
;;

let allocate_handler_id t =
  let allocated = t.next_handler_id in
  t.next_handler_id <- ID.Ui.Handler_id.succ allocated;
  allocated
;;

let validate_unique_keys root =
  let rec validate reversed_parent_path widget =
    let (Av view) = View.Private.view widget in
    let reversed_parent_path =
      { Runtime_error.kind = View.Private.node_kind_tag view.node; key = view.key }
      :: reversed_parent_path
    in
    match Array.length view.children with
    | 0 -> Ok ()
    | 1 -> validate reversed_parent_path view.children.(0)
    | _ -> validate_children reversed_parent_path widget
  and validate_children reversed_parent_path widget =
    let (Av view) = View.Private.view widget in
    let keys = ref None in
    let observe_key index child_kind key =
      match !keys with
      | None ->
        let table = Key_table.create (Array.length view.children) in
        Key_table.add table key (index, child_kind);
        keys := Some table;
        Ok ()
      | Some table ->
        (match Key_table.find_opt table key with
         | Some (first_index, first_kind) ->
           Error
             (Runtime_error.Duplicate_key
                { key
                ; side = Runtime_error.Candidate
                ; parent_path = List.rev reversed_parent_path
                ; first = { child_index = first_index; kind = first_kind }
                ; second = { child_index = index; kind = child_kind }
                })
         | None ->
           Key_table.add table key (index, child_kind);
           Ok ())
    in
    let rec check_children index =
      if index = Array.length view.children
      then Ok ()
      else (
        let child = view.children.(index) in
        let child_kind = View.Private.kind_tag_of_widget child in
        let (Av child_view) = View.Private.view child in
        match child_view.key with
        | None ->
          (match validate reversed_parent_path child with
           | Error _ as error -> error
           | Ok () -> check_children (index + 1))
        | Some key ->
          (match observe_key index child_kind key with
           | Error _ as error -> error
           | Ok () ->
             (match validate reversed_parent_path child with
              | Error _ as error -> error
              | Ok () -> check_children (index + 1))))
    in
    check_children 0
  in
  validate [] root
;;

let binding_equal
      (left : Mounted_tree.Mounted_binding.t)
      (right : Mounted_tree.Mounted_binding.t)
  =
  Ui.Event.Tag.equal left.event_tag right.event_tag
  && Handler_id.equal left.handler_id right.handler_id
;;

let binding_arrays_equal left right =
  Array.length left = Array.length right && Array.for_all2 binding_equal left right
;;

let child_ids_equal old_children new_children =
  Array.length old_children = Array.length new_children
  &&
  let rec loop index =
    index = Array.length old_children
    || (Node_id.equal
          old_children.(index).Mounted_tree.Private.node_id
          new_children.(index).Mounted_tree.Private.node_id
        && loop (index + 1))
  in
  loop 0
;;

let key_options_equal = Option.equal Ui.Key.equal

let reconcile t ~base_revision ~target_revision ~old ~base_handler_frame new_widget =
  if ID.Runtime.Renderer_revision.compare target_revision base_revision <= 0
  then
    Error
      (Runtime_error.Invalid_patch "target revision must be greater than base revision")
  else (
    let handler_base =
      match old, base_handler_frame with
      | None, None -> Ok (Handler_registry.Frame.Private.empty ~revision:base_revision)
      | Some _, Some frame
        when ID.Runtime.Renderer_revision.equal
               (Handler_registry.Frame.revision frame)
               base_revision -> Ok frame
      | Some _, Some frame ->
        Error
          (Runtime_error.Invalid_patch
             (Printf.sprintf
                "handler base revision %Ld does not match tree base revision %Ld"
                (ID.Runtime.Renderer_revision.to_int64
                   (Handler_registry.Frame.revision frame))
                (ID.Runtime.Renderer_revision.to_int64 base_revision)))
      | Some _, None ->
        Error
          (Runtime_error.Invalid_patch "incremental reconcile requires a handler base")
      | None, Some _ ->
        Error
          (Runtime_error.Invalid_patch
             "full snapshot reconcile requires an empty handler base")
    in
    match handler_base with
    | Error _ as error -> error
    | Ok handler_base ->
      let validation =
        match old with
        | Some tree when (Mounted_tree.Private.root tree).source_widget == new_widget ->
          (* Mounted roots have already passed validation and widgets are immutable. *)
          Ok ()
        | None | Some _ -> validate_unique_keys new_widget
      in
      (match validation with
       | Error _ as error -> error
       | Ok () ->
         let operations_reversed = ref [] in
         let drops_reversed = ref [] in
         let handler_additions_reversed = ref [] in
         let handler_removals_reversed = ref [] in
         let emit operation = operations_reversed := operation :: !operations_reversed in
         let add_handler node_id (binding : Mounted_tree.Mounted_binding.t) handler =
           handler_additions_reversed
           := { Handler_registry.Frame.node_id
              ; event_tag = binding.event_tag
              ; handler_id = binding.handler_id
              ; handler
              }
              :: !handler_additions_reversed
         in
         let remove_handler handler_id =
           handler_removals_reversed := handler_id :: !handler_removals_reversed
         in
         let rec queue_drop (node : Mounted_tree.Private.node) =
           Array.iter
             (fun (binding : Mounted_tree.Mounted_binding.t) ->
                remove_handler binding.handler_id)
             node.event_bindings;
           Array.iter queue_drop node.children;
           drops_reversed
           := Frame_patch.Operation.Drop_node node.node_id :: !drops_reversed
         in
         let create_bindings ~node_id event_bindings =
           let mounted_bindings =
             Array.map
               (fun (binding : View.Private.event_binding) ->
                  let mounted =
                    { Mounted_tree.Mounted_binding.event_tag = binding.tag
                    ; handler_id = allocate_handler_id t
                    }
                  in
                  add_handler node_id mounted binding.handler;
                  mounted)
               event_bindings
           in
           let handlers =
             Array.map
               (fun (binding : View.Private.event_binding) -> binding.handler)
               event_bindings
           in
           mounted_bindings, handlers
         in
         let rec mount widget =
           let (Av view) = View.Private.view widget in
           let node_id = allocate_node_id t in
           let event_bindings, handlers = create_bindings ~node_id view.event_bindings in
           emit
             (Frame_patch.Operation.Create_node
                { node_id
                ; key = view.key
                ; test_id = view.test_id
                ; node_tag = View.Private.kind_tag_of_widget widget
                ; widget
                ; event_bindings
                });
           let children = Array.map (fun (child : View.t) -> mount child) view.children in
           if Array.length children > 0
           then
             emit
               (Frame_patch.Operation.Set_children
                  { node_id
                  ; children =
                      Array.map (fun child -> child.Mounted_tree.Private.node_id) children
                  });
           { Mounted_tree.Private.node_id
           ; key = view.key
           ; test_id = view.test_id
           ; node_tag = View.Private.kind_tag_of_widget widget
           ; event_bindings
           ; handlers
           ; children
           ; source_widget = widget
           }
         and reconcile_bindings old_node widget_bindings =
           let find_old tag =
             let rec loop index =
               if index = Array.length old_node.Mounted_tree.Private.event_bindings
               then None
               else (
                 let binding = old_node.event_bindings.(index) in
                 if Ui.Event.Tag.equal binding.event_tag tag
                 then Some index
                 else loop (index + 1))
             in
             loop 0
           in
           let event_bindings =
             Array.map
               (fun (binding : View.Private.event_binding) ->
                  match find_old binding.tag with
                  | Some index
                    when Ui.Event.Handler.Private.same
                           old_node.handlers.(index)
                           binding.handler -> old_node.event_bindings.(index)
                  | old_index ->
                    Option.iter
                      (fun index ->
                         remove_handler old_node.event_bindings.(index).handler_id)
                      old_index;
                    let mounted =
                      { Mounted_tree.Mounted_binding.event_tag = binding.tag
                      ; handler_id = allocate_handler_id t
                      }
                    in
                    add_handler old_node.node_id mounted binding.handler;
                    mounted)
               widget_bindings
           in
           let handlers =
             Array.map
               (fun (binding : View.Private.event_binding) -> binding.handler)
               widget_bindings
           in
           Array.iter
             (fun (old_binding : Mounted_tree.Mounted_binding.t) ->
                let retained =
                  Array.exists
                    (fun (binding : View.Private.event_binding) ->
                       Ui.Event.Tag.equal old_binding.event_tag binding.tag)
                    widget_bindings
                in
                if not retained then remove_handler old_binding.handler_id)
             old_node.event_bindings;
           if not (binding_arrays_equal old_node.event_bindings event_bindings)
           then
             emit
               (Frame_patch.Operation.Update_event_bindings
                  { node_id = old_node.node_id; event_bindings });
           event_bindings, handlers
         and reconcile_children old_node children =
           let old_children = old_node.Mounted_tree.Private.children in
           let used = Array.make (Array.length old_children) false in
           let keyed = Key_table.create (Array.length old_children) in
           Array.iteri
             (fun index child ->
                match child.Mounted_tree.Private.key with
                | None -> ()
                | Some key -> Key_table.add keyed key index)
             old_children;
           let children =
             Array.mapi
               (fun index (child : View.t) ->
                  let (Av child_view) = View.Private.view child in
                  let new_key = child_view.key in
                  let matched_index =
                    match new_key with
                    | Some key -> Key_table.find_opt keyed key
                    | None ->
                      if
                        index < Array.length old_children
                        && Option.is_none old_children.(index).key
                      then Some index
                      else None
                  in
                  match matched_index with
                  | Some old_index when not used.(old_index) ->
                    used.(old_index) <- true;
                    reconcile_node old_children.(old_index) child
                  | None | Some _ -> mount child)
               children
           in
           Array.iteri
             (fun index child -> if not used.(index) then queue_drop child)
             old_children;
           if not (child_ids_equal old_children children)
           then
             emit
               (Frame_patch.Operation.Set_children
                  { node_id = old_node.node_id
                  ; children =
                      Array.map (fun child -> child.Mounted_tree.Private.node_id) children
                  });
           children
         and reconcile_node old_node widget =
           if old_node.Mounted_tree.Private.source_widget == widget
           then old_node
           else (
             let (Av view) = View.Private.view widget in
             let compatible =
               key_options_equal old_node.key view.key
               && View.Private.kind_tag_equal
                    old_node.node_tag
                    (View.Private.kind_tag_of_widget widget)
             in
             if not compatible
             then (
               let mounted = mount widget in
               queue_drop old_node;
               mounted)
             else (
               if not (View.Private.node_equal_widgets old_node.source_widget widget)
               then
                 emit
                   (Frame_patch.Operation.Update_node
                      { node_id = old_node.node_id; widget });
               let event_bindings, handlers =
                 reconcile_bindings old_node view.event_bindings
               in
               let children = reconcile_children old_node view.children in
               { Mounted_tree.Private.node_id = old_node.node_id
               ; key = view.key
               ; test_id = view.test_id
               ; node_tag = View.Private.kind_tag_of_widget widget
               ; event_bindings
               ; handlers
               ; children
               ; source_widget = widget
               }))
         in
         let root, kind =
           match old with
           | None ->
             let root = mount new_widget in
             emit (Frame_patch.Operation.Set_root root.node_id);
             root, Frame_patch.Full_snapshot
           | Some old_tree ->
             let old_root = Mounted_tree.Private.root old_tree in
             let root = reconcile_node old_root new_widget in
             if not (Node_id.equal old_root.node_id root.node_id)
             then emit (Frame_patch.Operation.Set_root root.node_id);
             root, Frame_patch.Incremental_frame
         in
         let mounted_tree = Mounted_tree.Private.create root in
         let handler_frame =
           Handler_registry.Frame.Private.derive
             ~revision:target_revision
             ~base_revision
             ~base:handler_base
             ~removals:(List.rev !handler_removals_reversed)
             ~additions:(List.rev !handler_additions_reversed)
         in
         let operations = List.rev !operations_reversed @ List.rev !drops_reversed in
         let frame_patch =
           Frame_patch.Private.create ~kind ~base_revision ~target_revision operations
         in
         ignore t.runtime_epoch;
         Ok { mounted_tree; frame_patch; handler_frame }))
;;
