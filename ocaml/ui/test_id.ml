module ID = Bonsai_swiftui_spec.Id

type t = ID.Ui.test_id

let string value =
  if String.length value = 0 then invalid_arg "Test_id.string: value must not be empty";
  ID.Ui.Test_id.of_string value
;;

let equal = ID.Ui.Test_id.equal
let to_string = ID.Ui.Test_id.to_string
