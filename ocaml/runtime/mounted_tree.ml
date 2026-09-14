module Ui = Bonsai_swiftui_ui

module Mounted_binding = struct
  type t =
    { event_tag : Ui.Event.Tag.t
    ; handler_id : Handler_id.t
    }
end

module Snapshot = struct
  type node =
    { node_id : Node_id.t
    ; key : Ui.Key.t option
    ; test_id : Ui.Test_id.t option
    ; node_tag : Ui.View.Private.kind_tag
    ; widget : Ui.View.t
    ; event_bindings : Mounted_binding.t array
    ; children : Node_id.t array
    }

  type t =
    { root_id : Node_id.t option
    ; nodes : (Node_id.t, node) Hashtbl.t
    }

  let empty = { root_id = None; nodes = Hashtbl.create 0 }
  let root_id t = t.root_id
  let node_count t = Hashtbl.length t.nodes
  let find t node_id = Hashtbl.find_opt t.nodes node_id

  let binding_equal left right =
    Ui.Event.Tag.equal left.Mounted_binding.event_tag right.Mounted_binding.event_tag
    && Handler_id.equal left.handler_id right.handler_id
  ;;

  let option_key_equal = Option.equal Ui.Key.equal

  let node_equal left right =
    Node_id.equal left.node_id right.node_id
    && option_key_equal left.key right.key
    && Option.equal Ui.Test_id.equal left.test_id right.test_id
    && Ui.View.Private.kind_tag_equal left.node_tag right.node_tag
    && Ui.View.Private.node_equal_widgets left.widget right.widget
    && Array.length left.event_bindings = Array.length right.event_bindings
    && Array.for_all2 binding_equal left.event_bindings right.event_bindings
    && Array.length left.children = Array.length right.children
    && Array.for_all2 Node_id.equal left.children right.children
  ;;

  let equal left right =
    Option.equal Node_id.equal left.root_id right.root_id
    && Hashtbl.length left.nodes = Hashtbl.length right.nodes
    && Hashtbl.fold
         (fun node_id node equal_so_far ->
            equal_so_far
            &&
            match Hashtbl.find_opt right.nodes node_id with
            | None -> false
            | Some other -> node_equal node other)
         left.nodes
         true
  ;;

  let find_matching t predicate =
    Hashtbl.to_seq_values t.nodes
    |> Seq.find_map (fun node -> if predicate node then Some node else None)
  ;;

  let find_by_key t key =
    find_matching t (fun node ->
      match node.key with
      | None -> false
      | Some candidate -> Ui.Key.equal key candidate)
  ;;

  let find_by_test_id t test_id =
    find_matching t (fun node ->
      match node.test_id with
      | None -> false
      | Some candidate -> Ui.Test_id.equal test_id candidate)
  ;;

  let find_by_text t text =
    find_matching t (fun node ->
      let (Av view) = Ui.View.Private.view node.widget in
      match view.node with
      | Ui.View.Private.Text { value; _ } -> String.equal value text
      | _ -> false)
  ;;

  module Private = struct
    let create ~root_id nodes =
      let table = Hashtbl.create (List.length nodes) in
      List.iter (fun node -> Hashtbl.replace table node.node_id node) nodes;
      { root_id; nodes = table }
    ;;

    let nodes t = Hashtbl.to_seq_values t.nodes |> List.of_seq
  end
end

module Private = struct
  type node =
    { node_id : Node_id.t
    ; key : Ui.Key.t option
    ; test_id : Ui.Test_id.t option
    ; node_tag : Ui.View.Private.kind_tag
    ; event_bindings : Mounted_binding.t array
    ; handlers : Ui.Event.Handler.t array
    ; children : node array
    ; source_widget : Ui.View.t
    }

  let root t = t
  let create node = node
end

type t = Private.node

let root_id t = t.Private.node_id

let rec node_count_node node =
  Array.fold_left
    (fun count child -> count + node_count_node child)
    1
    node.Private.children
;;

let node_count t = node_count_node t

let snapshot t =
  let nodes = ref [] in
  let rec visit node =
    let snapshot_node : Snapshot.node =
      { node_id = node.Private.node_id
      ; key = node.key
      ; test_id = node.test_id
      ; node_tag = node.node_tag
      ; widget = node.source_widget
      ; event_bindings = Array.copy node.event_bindings
      ; children = Array.map (fun child -> child.Private.node_id) node.children
      }
    in
    nodes := snapshot_node :: !nodes;
    Array.iter visit node.children
  in
  visit t;
  Snapshot.Private.create ~root_id:(Some t.Private.node_id) !nodes
;;
