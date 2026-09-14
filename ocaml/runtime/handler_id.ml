module ID = Bonsai_swiftui_spec.Id

type t = ID.Ui.handler_id

let compare = ID.Ui.Handler_id.compare
let equal = ID.Ui.Handler_id.equal
let to_int64 = ID.Ui.Handler_id.to_int64

module Private = struct
  let of_int64 value =
    if Int64.compare value 0L < 0 then invalid_arg "Handler_id: negative value";
    ID.Ui.Handler_id.of_int64 value
  ;;
end
