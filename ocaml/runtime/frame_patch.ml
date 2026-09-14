module ID = Bonsai_swiftui_spec.Id
module Ui = Bonsai_swiftui_ui

module Operation = struct
  type create_node =
    { node_id : Node_id.t
    ; key : Ui.Key.t option
    ; test_id : Ui.Test_id.t option
    ; node_tag : Ui.View.Private.kind_tag
    ; widget : Ui.View.t
    ; event_bindings : Mounted_tree.Mounted_binding.t array
    }

  type t =
    | Create_node of create_node
    | Update_node of
        { node_id : Node_id.t
        ; widget : Ui.View.t
        }
    | Update_event_bindings of
        { node_id : Node_id.t
        ; event_bindings : Mounted_tree.Mounted_binding.t array
        }
    | Set_children of
        { node_id : Node_id.t
        ; children : Node_id.t array
        }
    | Set_root of Node_id.t
    | Drop_node of Node_id.t
end

type kind =
  | Full_snapshot
  | Incremental_frame

type t =
  { kind : kind
  ; base_revision : ID.Runtime.renderer_revision
  ; target_revision : ID.Runtime.renderer_revision
  ; operations : Operation.t list
  }

let kind t = t.kind
let base_revision t = t.base_revision
let target_revision t = t.target_revision
let operations t = t.operations
let is_empty t = t.operations = []

module Private = struct
  let create ~kind ~base_revision ~target_revision operations =
    { kind; base_revision; target_revision; operations }
  ;;
end

exception Patch_error of string

let patch_error format =
  Printf.ksprintf (fun message -> raise (Patch_error message)) format
;;

let copy_node (node : Mounted_tree.Snapshot.node) =
  { node with
    event_bindings = Array.copy node.event_bindings
  ; children = Array.copy node.children
  }
;;

let table_of_snapshot snapshot =
  let nodes = Hashtbl.create (Mounted_tree.Snapshot.node_count snapshot) in
  Mounted_tree.Snapshot.Private.nodes snapshot
  |> List.iter (fun node ->
    Hashtbl.add nodes node.Mounted_tree.Snapshot.node_id (copy_node node));
  nodes
;;

let find_node nodes node_id operation =
  match Hashtbl.find_opt nodes node_id with
  | Some node -> node
  | None ->
    patch_error "%s references missing node %Ld" operation (Node_id.to_int64 node_id)
;;

let validate ~root_id nodes =
  let root_id =
    match root_id with
    | Some root_id ->
      ignore (find_node nodes root_id "root");
      root_id
    | None -> patch_error "frame has no root"
  in
  let parent_counts = Hashtbl.create (Hashtbl.length nodes) in
  Hashtbl.iter (fun node_id _ -> Hashtbl.add parent_counts node_id 0) nodes;
  Hashtbl.iter
    (fun _ (node : Mounted_tree.Snapshot.node) ->
       Array.iter
         (fun child_id ->
            ignore (find_node nodes child_id "child reference");
            let count =
              Option.value ~default:0 (Hashtbl.find_opt parent_counts child_id)
            in
            Hashtbl.replace parent_counts child_id (count + 1))
         node.children)
    nodes;
  Hashtbl.iter
    (fun node_id count ->
       if Node_id.equal node_id root_id
       then (
         if count <> 0
         then patch_error "root node %Ld has a parent" (Node_id.to_int64 node_id))
       else if count <> 1
       then patch_error "node %Ld has %d parents" (Node_id.to_int64 node_id) count)
    parent_counts;
  let visiting = Hashtbl.create (Hashtbl.length nodes) in
  let visited = Hashtbl.create (Hashtbl.length nodes) in
  let rec visit node_id =
    if Hashtbl.mem visiting node_id
    then patch_error "cycle includes node %Ld" (Node_id.to_int64 node_id)
    else if not (Hashtbl.mem visited node_id)
    then (
      Hashtbl.add visiting node_id ();
      let node = find_node nodes node_id "tree traversal" in
      Array.iter visit node.children;
      Hashtbl.remove visiting node_id;
      Hashtbl.add visited node_id ())
  in
  visit root_id;
  if Hashtbl.length visited <> Hashtbl.length nodes
  then patch_error "frame contains unreachable nodes";
  Some root_id
;;

let apply ~old t =
  try
    if ID.Runtime.Renderer_revision.compare t.target_revision t.base_revision <= 0
    then patch_error "target revision must be greater than base revision";
    let root_id, nodes =
      match t.kind, old with
      | Full_snapshot, _ -> ref None, Hashtbl.create 16
      | Incremental_frame, Some snapshot ->
        ref (Mounted_tree.Snapshot.root_id snapshot), table_of_snapshot snapshot
      | Incremental_frame, None ->
        patch_error "incremental frame requires an old snapshot"
    in
    List.iter
      (function
        | Operation.Create_node create ->
          if Hashtbl.mem nodes create.node_id
          then patch_error "node %Ld already exists" (Node_id.to_int64 create.node_id);
          let node : Mounted_tree.Snapshot.node =
            { node_id = create.node_id
            ; key = create.key
            ; test_id = create.test_id
            ; node_tag = create.node_tag
            ; widget = create.widget
            ; event_bindings = Array.copy create.event_bindings
            ; children = [||]
            }
          in
          Hashtbl.add nodes create.node_id node
        | Operation.Update_node { node_id; widget } ->
          let node = find_node nodes node_id "Update_node" in
          Hashtbl.replace nodes node_id { node with widget }
        | Operation.Update_event_bindings { node_id; event_bindings } ->
          let node = find_node nodes node_id "Update_event_bindings" in
          Hashtbl.replace
            nodes
            node_id
            { node with event_bindings = Array.copy event_bindings }
        | Operation.Set_children { node_id; children } ->
          let node = find_node nodes node_id "Set_children" in
          Hashtbl.replace nodes node_id { node with children = Array.copy children }
        | Operation.Set_root node_id -> root_id := Some node_id
        | Operation.Drop_node node_id ->
          if not (Hashtbl.mem nodes node_id)
          then
            patch_error "Drop_node references missing node %Ld" (Node_id.to_int64 node_id);
          Hashtbl.remove nodes node_id)
      t.operations;
    let root_id = validate ~root_id:!root_id nodes in
    let nodes = Hashtbl.to_seq_values nodes |> List.of_seq in
    Ok (Mounted_tree.Snapshot.Private.create ~root_id nodes)
  with
  | Patch_error message -> Error (Runtime_error.Invalid_patch message)
;;
