module ID = Bonsai_swiftui_spec.Id

type t = ID.Ui.node_id

let compare = ID.Ui.Node_id.compare
let equal = ID.Ui.Node_id.equal
let to_int64 = ID.Ui.Node_id.to_int64

module Private = struct
  let of_int64 value =
    if Int64.compare value 0L < 0 then invalid_arg "Node_id: negative value";
    ID.Ui.Node_id.of_int64 value
  ;;
end
