module ID = Bonsai_swiftui_spec.Id

type t = ID.Ui.application_key

let string = ID.Ui.Application_key.string
let int value = ID.Ui.Application_key.int64 (Int64.of_int value)
let int64 = ID.Ui.Application_key.int64
let compare left right = Stdlib.compare left right
let equal left right = compare left right = 0
let hash value = Hashtbl.hash value

let to_debug_string = function
  | ID.Ui.String value -> Printf.sprintf "%S" value
  | ID.Ui.Int64 value -> Int64.to_string value
;;
