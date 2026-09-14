module Runtime = Bonsai_swiftui_runtime
module Ui = Bonsai_swiftui_ui

type t =
  | Test_id of Ui.Test_id.t
  | Key of Ui.Key.t
  | Role of string
  | Visible_text of string
  | Semantics_label of string
  | Kind of string

let normalized value = String.lowercase_ascii value
let test_id value = Test_id (Ui.Test_id.string value)
let key value = Key value
let role value = Role (normalized value)
let visible_text value = Visible_text value
let semantics_label value = Semantics_label value
let kind value = Kind (normalized value)

let kind_name node =
  Ui.View.Private.kind_tag_to_string node.Runtime.Mounted_tree.Snapshot.node_tag
  |> normalized
;;

let node_role node =
  match node.Runtime.Mounted_tree.Snapshot.node_tag with
  | Ui.View.Private.K_button -> Some "button"
  | K_toggle -> Some "toggle"
  | K_text_field | K_secure_field -> Some "text_field"
  | K_text_editor -> Some "text_editor"
  | K_semantics ->
    let (Av view) = Ui.View.Private.view node.Runtime.Mounted_tree.Snapshot.widget in
    (match view.node with
     | Ui.View.Private.Semantics { role; _ } -> Some (Ui.Semantics.Role.to_string role)
     | _ -> None)
  | _ -> None
;;

let matches query node =
  match query with
  | Test_id test_id ->
    (match node.Runtime.Mounted_tree.Snapshot.test_id with
     | Some candidate -> Ui.Test_id.equal test_id candidate
     | None -> false)
  | Key key ->
    (match node.Runtime.Mounted_tree.Snapshot.key with
     | Some candidate -> Ui.Key.equal key candidate
     | None -> false)
  | Role role ->
    (match node_role node with
     | Some candidate -> String.equal role candidate
     | None -> false)
  | Visible_text text ->
    let (Av view) = Ui.View.Private.view node.Runtime.Mounted_tree.Snapshot.widget in
    (match view.node with
     | Ui.View.Private.Text { value; _ } -> String.equal value text
     | _ -> false)
  | Semantics_label label ->
    let (Av view) = Ui.View.Private.view node.Runtime.Mounted_tree.Snapshot.widget in
    (match view.node with
     | Ui.View.Private.Semantics { label = Some value; _ } -> String.equal value label
     | _ -> false)
  | Kind expected -> String.equal expected (kind_name node)
;;

module Private = struct
  let matches = matches
end
