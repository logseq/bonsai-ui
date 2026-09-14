module Ui = Bonsai_swiftui_ui
module Runtime = Bonsai_swiftui_runtime
module ID = Bonsai_swiftui_spec.Id
module View = Ui.View
module Key = Ui.Key
module Event = Ui.Event
module Mounted_tree = Runtime.Mounted_tree
module Frame_patch = Runtime.Frame_patch

module Handler_registry = struct
  include Runtime.Handler_registry

  module Frame = struct
    include Runtime.Handler_registry.Frame

    module Private = struct
      let create ~revision entries =
        Runtime.Handler_registry.Frame.Private.create
          ~revision:(ID.Runtime.Renderer_revision.of_int64 revision)
          entries
      ;;

      let empty ~revision =
        Runtime.Handler_registry.Frame.Private.empty
          ~revision:(ID.Runtime.Renderer_revision.of_int64 revision)
      ;;

      let derive ~revision ~base_revision ~base ~removals ~additions =
        Runtime.Handler_registry.Frame.Private.derive
          ~revision:(ID.Runtime.Renderer_revision.of_int64 revision)
          ~base_revision:(ID.Runtime.Renderer_revision.of_int64 base_revision)
          ~base
          ~removals
          ~additions
      ;;
    end
  end

  let create ~runtime_epoch =
    Runtime.Handler_registry.create
      ~runtime_epoch:(ID.Runtime.Epoch.of_int64 runtime_epoch)
  ;;

  let mark_displayed_revision t ~revision =
    Runtime.Handler_registry.mark_displayed_revision
      t
      ~revision:(ID.Runtime.Renderer_revision.of_int64 revision)
  ;;

  let retire_before t ~revision =
    Runtime.Handler_registry.retire_before
      t
      ~revision:(ID.Runtime.Renderer_revision.of_int64 revision)
  ;;

  let commit_displayed_revision t ~revision =
    Runtime.Handler_registry.commit_displayed_revision
      t
      ~revision:(ID.Runtime.Renderer_revision.of_int64 revision)
  ;;
end

module Reconciler = struct
  include Runtime.Reconciler

  let create ~runtime_epoch =
    Runtime.Reconciler.create ~runtime_epoch:(ID.Runtime.Epoch.of_int64 runtime_epoch)
  ;;

  let reconcile t ~base_revision ~target_revision ~old ~base_handler_frame widget =
    Runtime.Reconciler.reconcile
      t
      ~base_revision:(ID.Runtime.Renderer_revision.of_int64 base_revision)
      ~target_revision:(ID.Runtime.Renderer_revision.of_int64 target_revision)
      ~old
      ~base_handler_frame
      widget
  ;;
end

module Runtime_error = Runtime.Runtime_error

exception Test_failure of string

let epoch = ID.Runtime.Epoch.of_int64
let revision = ID.Runtime.Renderer_revision.of_int64
let event_sequence = ID.Runtime.Event_sequence.of_int64
let fail format = Printf.ksprintf (fun message -> raise (Test_failure message)) format
let check condition format = if not condition then fail "%s" format

let check_int ~expected ~actual label =
  if expected <> actual then fail "%s: expected %d, got %d" label expected actual
;;

let check_int64 ~expected ~actual label =
  if not (Int64.equal expected actual)
  then fail "%s: expected %Ld, got %Ld" label expected actual
;;

let check_kind ~expected ~actual label =
  if not (View.Private.kind_tag_equal expected actual)
  then
    fail
      "%s: expected %s, got %s"
      label
      (View.Private.kind_tag_to_string expected)
      (View.Private.kind_tag_to_string actual)
;;

let ok = function
  | Ok value -> value
  | Error error -> fail "unexpected error: %s" (Runtime_error.to_string error)
;;

module Mounted_handler_frames = Hashtbl.Make (struct
    type t = Mounted_tree.t

    let equal = ( == )
    let hash = Hashtbl.hash
  end)

let mounted_handler_frames = Mounted_handler_frames.create 128

let reconcile_exn reconciler ~base_revision ~target_revision ~old widget =
  let base_handler_frame =
    Option.map (Mounted_handler_frames.find mounted_handler_frames) old
  in
  let output =
    Reconciler.reconcile
      reconciler
      ~base_revision
      ~target_revision
      ~old
      ~base_handler_frame
      widget
    |> ok
  in
  Mounted_handler_frames.replace
    mounted_handler_frames
    output.mounted_tree
    output.handler_frame;
  output
;;

let count_operations patch predicate =
  Frame_patch.operations patch
  |> List.fold_left
       (fun count operation -> if predicate operation then count + 1 else count)
       0
;;

let is_create = function
  | Frame_patch.Operation.Create_node _ -> true
  | _ -> false
;;

let is_update_props = function
  | Frame_patch.Operation.Update_node _ -> true
  | _ -> false
;;

let is_update_event_bindings = function
  | Frame_patch.Operation.Update_event_bindings _ -> true
  | _ -> false
;;

let is_set_children = function
  | Frame_patch.Operation.Set_children _ -> true
  | _ -> false
;;

let is_set_root = function
  | Frame_patch.Operation.Set_root _ -> true
  | _ -> false
;;

let is_drop = function
  | Frame_patch.Operation.Drop_node _ -> true
  | _ -> false
;;

let apply_and_compare ~old_snapshot output =
  let applied = Frame_patch.apply ~old:old_snapshot output.Reconciler.frame_patch |> ok in
  let expected = Mounted_tree.snapshot output.mounted_tree in
  check
    (Mounted_tree.Snapshot.equal applied expected)
    "patch application did not reproduce the mounted snapshot"
;;

let node_by_key snapshot key =
  match Mounted_tree.Snapshot.find_by_key snapshot key with
  | Some node -> node
  | None -> fail "missing mounted node for key %s" (Key.to_debug_string key)
;;

let node_by_text snapshot text =
  match Mounted_tree.Snapshot.find_by_text snapshot text with
  | Some node -> node
  | None -> fail "missing mounted text node %S" text
;;

let binding_exn node tag =
  let matching =
    Array.to_list node.Mounted_tree.Snapshot.event_bindings
    |> List.filter (fun binding ->
      Event.Tag.equal binding.Mounted_tree.Mounted_binding.event_tag tag)
  in
  match matching with
  | [ binding ] -> binding
  | _ -> fail "expected exactly one %s binding" (Event.Tag.to_string tag)
;;

let press_handler ?name callback = Event.Handler.create ?name (fun _ -> callback ())

let expect_invalid_argument operation message =
  match operation () with
  | exception Invalid_argument _ -> ()
  | exception exception_ -> fail "%s raised %s" message (Printexc.to_string exception_)
  | _ -> fail "%s did not raise Invalid_argument" message
;;

let test_swiftui_button_semantics () =
  let handler = press_handler (fun () -> ()) in
  let child = View.text "Save" in
  let disabled = View.button ~enabled:false ~on_press:handler ~child () in
  let (Av disabled_view) = View.Private.view disabled in
  check_int
    ~expected:0
    ~actual:(Array.length disabled_view.event_bindings)
    "disabled button must not publish an actionable handler";
  let make role style = View.button ~role ~style ~on_press:handler ~child () in
  let normal = make View.Button_role.Normal View.Button_style.Automatic in
  let destructive = make View.Button_role.Destructive View.Button_style.Automatic in
  let prominent = make View.Button_role.Normal View.Button_style.Prominent in
  check
    (not (View.Private.node_equal_widgets normal destructive))
    "button role must participate in reconciliation";
  check
    (not (View.Private.node_equal_widgets normal prominent))
    "button style must participate in reconciliation"
;;

let test_button_is_a_typed_core_widget () =
  let activations = ref 0 in
  let handler = press_handler (fun () -> Stdlib.incr activations) in
  let widget =
    View.button
      ~key:(Key.string "button")
      ~role:View.Button_role.Destructive
      ~style:View.Button_style.Prominent
      ~on_press:handler
      ~child:(View.text "Message")
      ()
  in
  let (Av view) = View.Private.view widget in
  check
    (View.Private.kind_tag_equal
       (View.Private.node_kind_tag view.node)
       View.Private.K_button)
    "button must be a core widget kind";
  check_int ~expected:1 ~actual:(Array.length view.children) "button child count";
  (match view.node with
   | View.Private.Button { enabled; role; style; autofocus } ->
     check enabled "button enabled state";
     check (role = View.Button_role.Destructive) "button role";
     check (style = View.Button_style.Prominent) "button style";
     check (not autofocus) "button autofocus defaults to false"
   | _ -> fail "button must expose typed core props");
  let binding = view.event_bindings.(0) in
  check
    (Event.Tag.equal binding.tag Event.Tag.Press)
    "button must use the core press event";
  Event.Handler.Private.invoke binding.handler Event.Payload.Unit;
  check_int ~expected:1 ~actual:!activations "button activation count"
;;

let test_initial_mount_is_full_snapshot () =
  let reconciler = Reconciler.create ~runtime_epoch:41L in
  let widget = View.column [ View.text "hello"; View.text "world" ] in
  let output =
    reconcile_exn reconciler ~base_revision:0L ~target_revision:1L ~old:None widget
  in
  check
    (Frame_patch.kind output.frame_patch = Frame_patch.Full_snapshot)
    "initial mount must be a full snapshot";
  check_int ~expected:3 ~actual:(Mounted_tree.node_count output.mounted_tree) "node count";
  check_int
    ~expected:3
    ~actual:(count_operations output.frame_patch is_create)
    "create count";
  check_int
    ~expected:1
    ~actual:(count_operations output.frame_patch is_set_root)
    "set root count";
  apply_and_compare ~old_snapshot:None output
;;

let test_physical_equality_emits_no_patch () =
  let reconciler = Reconciler.create ~runtime_epoch:42L in
  let widget = View.column [ View.text "unchanged" ] in
  let first =
    reconcile_exn reconciler ~base_revision:0L ~target_revision:1L ~old:None widget
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      widget
  in
  check (Frame_patch.is_empty second.frame_patch) "physical equality emitted a patch";
  check_int64
    ~expected:(Mounted_tree.root_id first.mounted_tree |> Runtime.Node_id.to_int64)
    ~actual:(Mounted_tree.root_id second.mounted_tree |> Runtime.Node_id.to_int64)
    "root identity";
  apply_and_compare ~old_snapshot:(Some (Mounted_tree.snapshot first.mounted_tree)) second
;;

let test_one_text_change_is_one_prop_update () =
  let reconciler = Reconciler.create ~runtime_epoch:43L in
  let key = Key.string "counter" in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (View.text ~key "Count: 0")
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (View.text ~key "Count: 1")
  in
  check_int
    ~expected:1
    ~actual:(List.length (Frame_patch.operations second.frame_patch))
    "patch operation count";
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_update_props)
    "prop update count";
  apply_and_compare ~old_snapshot:(Some (Mounted_tree.snapshot first.mounted_tree)) second
;;

let keyed_text key value = View.text ~key:(Key.string key) value

let test_keyed_reorder_preserves_identity () =
  let reconciler = Reconciler.create ~runtime_epoch:44L in
  let old_widget =
    View.column [ keyed_text "a" "A"; keyed_text "b" "B"; keyed_text "c" "C" ]
  in
  let first =
    reconcile_exn reconciler ~base_revision:0L ~target_revision:1L ~old:None old_widget
  in
  let first_snapshot = Mounted_tree.snapshot first.mounted_tree in
  let ids_before =
    List.map
      (fun key -> (node_by_key first_snapshot (Key.string key)).node_id)
      [ "a"; "b"; "c" ]
  in
  let new_widget =
    View.column [ keyed_text "c" "C"; keyed_text "a" "A"; keyed_text "b" "B" ]
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      new_widget
  in
  let second_snapshot = Mounted_tree.snapshot second.mounted_tree in
  let ids_after =
    List.map
      (fun key -> (node_by_key second_snapshot (Key.string key)).node_id)
      [ "a"; "b"; "c" ]
  in
  check (ids_before = ids_after) "keyed reorder changed node identities";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_create) "creates";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_drop) "drops";
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_set_children)
    "set children";
  apply_and_compare ~old_snapshot:(Some first_snapshot) second
;;

let test_keyed_insert_and_delete_are_incremental () =
  let reconciler = Reconciler.create ~runtime_epoch:45L in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (View.column [ keyed_text "a" "A"; keyed_text "b" "B" ])
  in
  let first_snapshot = Mounted_tree.snapshot first.mounted_tree in
  let a_before = (node_by_key first_snapshot (Key.string "a")).node_id in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (View.column [ keyed_text "x" "X"; keyed_text "a" "A" ])
  in
  let second_snapshot = Mounted_tree.snapshot second.mounted_tree in
  let a_after = (node_by_key second_snapshot (Key.string "a")).node_id in
  check_int64
    ~expected:(Runtime.Node_id.to_int64 a_before)
    ~actual:(Runtime.Node_id.to_int64 a_after)
    "surviving keyed child";
  check_int ~expected:1 ~actual:(count_operations second.frame_patch is_create) "creates";
  check_int ~expected:1 ~actual:(count_operations second.frame_patch is_drop) "drops";
  apply_and_compare ~old_snapshot:(Some first_snapshot) second
;;

let test_virtual_window_shift_preserves_keyed_overlap () =
  let reconciler = Reconciler.create ~runtime_epoch:451L in
  let on_visible_range = Event.Handler.create (fun _ -> ()) in
  let item key label = View.Keyed.create ~key:(Key.string key) (View.text label) in
  let catalog =
    View.Collection.Catalog.create
      ~keys:(List.map Key.string [ "a"; "b"; "c" ])
      ~default_extent:48.
      ()
  in
  let window ~first_index items =
    View.Collection.vertical ~catalog ~first_index ~items ~on_visible_range ()
    |> View.Viewport.Vertical.with_height ~height:96.
  in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (window ~first_index:0 [ item "a" "A"; item "b" "B" ])
  in
  let first_snapshot = Mounted_tree.snapshot first.mounted_tree in
  let a_before = (node_by_key first_snapshot (Key.string "a")).node_id in
  let b_before = (node_by_key first_snapshot (Key.string "b")).node_id in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (window ~first_index:1 [ item "b" "B"; item "c" "C" ])
  in
  let second_snapshot = Mounted_tree.snapshot second.mounted_tree in
  let b_after = (node_by_key second_snapshot (Key.string "b")).node_id in
  let c_after = (node_by_key second_snapshot (Key.string "c")).node_id in
  check
    (Runtime.Node_id.equal b_before b_after)
    "overlapping virtual item changed node identity";
  check
    (Option.is_none (Mounted_tree.Snapshot.find_by_key second_snapshot (Key.string "a")))
    "departed virtual item remained mounted";
  check
    (not (Runtime.Node_id.equal a_before c_after))
    "new virtual item reused the departed node ID";
  check_int ~expected:1 ~actual:(count_operations second.frame_patch is_create) "creates";
  check_int ~expected:1 ~actual:(count_operations second.frame_patch is_drop) "drops";
  apply_and_compare ~old_snapshot:(Some first_snapshot) second
;;

let test_virtual_list_duplicate_item_keys_are_rejected () =
  let duplicate = Key.string "duplicate-virtual-item" in
  let item label = View.Keyed.create ~key:duplicate (View.text label) in
  let catalog =
    View.Collection.Catalog.create
      ~keys:[ duplicate; Key.string "other" ]
      ~default_extent:48.
      ()
  in
  match
    View.Collection.vertical
      ~catalog
      ~first_index:0
      ~items:[ item "One"; item "Two" ]
      ~on_visible_range:(Event.Handler.create (fun _ -> ()))
      ()
  with
  | exception Invalid_argument _ -> ()
  | _ -> fail "duplicate virtual-list item keys were accepted"
;;

let test_kind_replacement_remounts () =
  let reconciler = Reconciler.create ~runtime_epoch:46L in
  let key = Key.string "root" in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (View.text ~key "old")
  in
  let old_id = Mounted_tree.root_id first.mounted_tree in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (View.column ~key [ View.text "new" ])
  in
  let new_id = Mounted_tree.root_id second.mounted_tree in
  check (not (Runtime.Node_id.equal old_id new_id)) "kind replacement reused node ID";
  check_int ~expected:2 ~actual:(count_operations second.frame_patch is_create) "creates";
  check_int ~expected:1 ~actual:(count_operations second.frame_patch is_drop) "drops";
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_set_root)
    "root replacement";
  apply_and_compare ~old_snapshot:(Some (Mounted_tree.snapshot first.mounted_tree)) second
;;

let test_duplicate_keys_fail_without_consuming_ids () =
  let reconciler = Reconciler.create ~runtime_epoch:47L in
  let duplicate = Key.string "duplicate" in
  let invalid =
    View.column [ View.text ~key:duplicate "one"; View.text ~key:duplicate "two" ]
  in
  (match
     Reconciler.reconcile
       reconciler
       ~base_revision:0L
       ~target_revision:1L
       ~old:None
       ~base_handler_frame:None
       invalid
   with
   | Error (Runtime_error.Duplicate_key { key; side; parent_path; first; second }) ->
     check (Key.equal key duplicate) "duplicate error reported the wrong key";
     check (side = Runtime_error.Candidate) "duplicate error reported the wrong side";
     (match parent_path with
      | [ { Runtime_error.kind; key = None } ] ->
        check_kind
          ~expected:View.Private.K_column
          ~actual:kind
          "root duplicate parent kind"
      | _ -> fail "root duplicate error reported the wrong parent path");
     check_int ~expected:0 ~actual:first.child_index "first duplicate child index";
     check_kind
       ~expected:View.Private.K_text
       ~actual:first.kind
       "first duplicate child kind";
     check_int ~expected:1 ~actual:second.child_index "second duplicate child index";
     check_kind
       ~expected:View.Private.K_text
       ~actual:second.kind
       "second duplicate child kind";
     let formatted =
       Runtime_error.to_string
         (Runtime_error.Duplicate_key { key; side; parent_path; first; second })
     in
     check
       (String.equal
          formatted
          "duplicate key \"duplicate\" in candidate children\n\n\
           View tree path:\n\
          \  Column\n\n\
           Duplicate siblings:\n\
          \  child[0]: Text[key=\"duplicate\"]\n\
          \  child[1]: Text[key=\"duplicate\"]")
       "root duplicate error formatting was not deterministic"
   | Error error -> fail "wrong duplicate-key error: %s" (Runtime_error.to_string error)
   | Ok _ -> fail "duplicate keys reconciled successfully");
  let valid =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (View.empty ())
  in
  check_int64
    ~expected:1L
    ~actual:(Mounted_tree.root_id valid.mounted_tree |> Runtime.Node_id.to_int64)
    "failed reconciliation consumed a node ID"
;;

let test_nested_duplicate_keys_fail () =
  let reconciler = Reconciler.create ~runtime_epoch:48L in
  let root_key = Key.string "root" in
  let parent_key = Key.string "nested-parent" in
  let key = Key.int 7 in
  let invalid =
    View.column
      ~key:root_key
      [ View.frame
          ~max_width:Ui.Layout.Frame_limit.Fill
          ~max_height:Ui.Layout.Frame_limit.Fill
          (View.row
             ~key:parent_key
             [ View.empty ~key (); View.text ~key "same nested parent" ])
      ]
  in
  match
    Reconciler.reconcile
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      ~base_handler_frame:None
      invalid
  with
  | Error
      (Runtime_error.Duplicate_key { key = actual_key; side; parent_path; first; second })
    ->
    check (Key.equal actual_key key) "nested duplicate reported the wrong key";
    check (side = Runtime_error.Candidate) "nested duplicate reported the wrong side";
    (match parent_path with
     | [ { Runtime_error.kind = root_kind; key = Some actual_root_key }
       ; { kind = frame_kind; key = None }
       ; { kind = parent_kind; key = Some actual_parent_key }
       ] ->
       check_kind ~expected:View.Private.K_column ~actual:root_kind "nested root kind";
       check (Key.equal actual_root_key root_key) "nested root key was not preserved";
       check_kind
         ~expected:View.Private.K_frame
         ~actual:frame_kind
         "nested unkeyed ancestor kind";
       check_kind ~expected:View.Private.K_row ~actual:parent_kind "nested parent kind";
       check
         (Key.equal actual_parent_key parent_key)
         "nested parent key was not preserved"
     | _ -> fail "nested duplicate error reported the wrong root-to-parent path");
    check_int ~expected:0 ~actual:first.child_index "nested first duplicate child index";
    check_kind
      ~expected:View.Private.K_empty
      ~actual:first.kind
      "nested first duplicate child kind";
    check_int ~expected:1 ~actual:second.child_index "nested second duplicate child index";
    check_kind
      ~expected:View.Private.K_text
      ~actual:second.kind
      "nested second duplicate child kind";
    check
      (String.equal
         (Runtime_error.to_string
            (Runtime_error.Duplicate_key
               { key = actual_key; side; parent_path; first; second }))
         "duplicate key 7 in candidate children\n\n\
          View tree path:\n\
         \  Column[key=\"root\"]\n\
         \  > Frame\n\
         \  > Row[key=\"nested-parent\"]\n\n\
          Duplicate siblings:\n\
         \  child[0]: Empty[key=7]\n\
         \  child[1]: Text[key=7]")
      "nested duplicate error formatting was not deterministic"
  | Error error -> fail "wrong nested duplicate error: %s" (Runtime_error.to_string error)
  | Ok _ -> fail "nested duplicate keys reconciled successfully"
;;

let test_existing_duplicate_key_formatting () =
  (* Mounted trees are abstract and can only be produced by successful
     reconciliation, which validates candidate keys before allocating nodes.
     An existing-side duplicate therefore cannot be constructed through the
     public reconciler API. This formatter test covers the structured side
     without adding an impossible production path solely for testing. *)
  let key = Key.string "existing-duplicate" in
  let error =
    Runtime_error.Duplicate_key
      { key
      ; side = Runtime_error.Existing
      ; parent_path =
          [ { Runtime_error.kind = View.Private.K_row
            ; key = Some (Key.string "mounted-parent")
            }
          ]
      ; first = { child_index = 2; kind = View.Private.K_text }
      ; second = { child_index = 5; kind = View.Private.K_empty }
      }
  in
  check
    (String.equal
       (Runtime_error.to_string error)
       "duplicate key \"existing-duplicate\" in existing children\n\n\
        View tree path:\n\
       \  Row[key=\"mounted-parent\"]\n\n\
        Duplicate siblings:\n\
       \  child[2]: Text[key=\"existing-duplicate\"]\n\
       \  child[5]: Empty[key=\"existing-duplicate\"]")
    "existing duplicate side formatting was not deterministic"
;;

let test_mixed_siblings_detect_duplicates () =
  let reconciler = Reconciler.create ~runtime_epoch:484L in
  let key = Key.string "repeated" in
  let widget =
    View.column
      [ View.text "unkeyed"
      ; View.empty ~key ()
      ; View.text "still unkeyed"
      ; View.text ~key "duplicate"
      ]
  in
  match
    Reconciler.reconcile
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      ~base_handler_frame:None
      widget
  with
  | Error
      (Runtime_error.Duplicate_key
         { parent_path; key = actual_key; side = Runtime_error.Candidate; _ }) ->
    (match List.rev parent_path with
     | { Runtime_error.kind; _ } :: _ ->
       check_kind
         ~expected:View.Private.K_column
         ~actual:kind
         "mixed duplicate parent kind"
     | [] -> fail "mixed duplicate omitted its parent path");
    check (Key.equal actual_key key) "duplicate reported the wrong key"
  | Error error -> fail "wrong mixed-sibling error: %s" (Runtime_error.to_string error)
  | Ok _ -> fail "mixed keyed siblings accepted a duplicate"
;;

let test_single_child_ancestor_still_validates_nested_duplicates () =
  let reconciler = Reconciler.create ~runtime_epoch:485L in
  let first = Key.string "first" in
  let later = Key.string "later" in
  let widget =
    View.column
      [ View.column
          [ View.empty ~key:first ()
          ; View.empty ~key:later ()
          ; View.text ~key:first "first duplicate"
          ; View.text ~key:later "later duplicate"
          ]
      ]
  in
  match
    Reconciler.reconcile
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      ~base_handler_frame:None
      widget
  with
  | Error (Runtime_error.Duplicate_key { key; _ }) ->
    check (Key.equal key first) "validator did not report the first duplicate"
  | Error error -> fail "wrong nested error: %s" (Runtime_error.to_string error)
  | Ok _ -> fail "single-child ancestor skipped nested duplicate validation"
;;

let reference_duplicate_key root =
  let rec validate widget =
    let children = View.For_testing.children widget in
    let rec validate_children seen index =
      if index = Array.length children
      then None
      else (
        let child = children.(index) in
        match View.For_testing.key child with
        | Some key when List.exists (Key.equal key) seen ->
          Some (View.For_testing.kind_name widget, key)
        | key ->
          let seen = Option.fold ~none:seen ~some:(fun key -> key :: seen) key in
          (match validate child with
           | Some _ as duplicate -> duplicate
           | None -> validate_children seen (index + 1)))
    in
    validate_children [] 0
  in
  validate root
;;

let test_optimized_key_validation_matches_reference () =
  let random = Random.State.make [| 8; 17; 23; 42 |] in
  let rec generate depth =
    let key =
      if Random.State.int random 3 = 0
      then Some (Key.int (Random.State.int random 4))
      else None
    in
    if depth = 0
    then View.text ?key (Printf.sprintf "leaf-%d" (Random.State.bits random))
    else (
      let child_count = Random.State.int random 5 in
      let children = List.init child_count (fun _ -> generate (depth - 1)) in
      View.column ?key children)
  in
  for case = 0 to 299 do
    let widget = generate 4 in
    let expected = reference_duplicate_key widget in
    let reconciler = Reconciler.create ~runtime_epoch:(Int64.of_int (500 + case)) in
    let actual =
      match
        Reconciler.reconcile
          reconciler
          ~base_revision:0L
          ~target_revision:1L
          ~old:None
          ~base_handler_frame:None
          widget
      with
      | Ok _ -> None
      | Error (Runtime_error.Duplicate_key { parent_path; key; _ }) ->
        (match List.rev parent_path with
         | { Runtime_error.kind; _ } :: _ ->
           Some (View.Private.kind_tag_to_string kind, key)
         | [] -> fail "duplicate error omitted its parent path")
      | Error error -> fail "reference case returned %s" (Runtime_error.to_string error)
    in
    match expected, actual with
    | None, None -> ()
    | Some (expected_parent, expected_key), Some (actual_parent, actual_key) ->
      check
        (String.equal expected_parent actual_parent && Key.equal expected_key actual_key)
        "optimized validator disagreed with the reference duplicate"
    | None, Some _ -> fail "optimized validator reported a reference-valid tree"
    | Some _, None -> fail "optimized validator accepted a reference-invalid tree"
  done
;;

let test_mixed_keyed_and_unkeyed_match_by_index () =
  let reconciler = Reconciler.create ~runtime_epoch:49L in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (View.column [ View.text "first"; keyed_text "stable" "keyed"; View.text "last" ])
  in
  let before = Mounted_tree.snapshot first.mounted_tree in
  let last_before = (node_by_text before "last").node_id in
  let first_before = (node_by_text before "first").node_id in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (View.column [ keyed_text "stable" "keyed"; View.text "first"; View.text "last" ])
  in
  let after = Mounted_tree.snapshot second.mounted_tree in
  let last_after = (node_by_text after "last").node_id in
  let first_after = (node_by_text after "first").node_id in
  check_int64
    ~expected:(Runtime.Node_id.to_int64 last_before)
    ~actual:(Runtime.Node_id.to_int64 last_after)
    "same-index unkeyed child";
  check
    (not (Runtime.Node_id.equal first_before first_after))
    "unkeyed child moved to a different index without remounting";
  apply_and_compare ~old_snapshot:(Some before) second
;;

let test_nested_removal_drops_complete_subtree () =
  let reconciler = Reconciler.create ~runtime_epoch:50L in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (View.column [ View.column ~key:(Key.string "branch") [ View.text "leaf" ] ])
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (View.column [])
  in
  check_int
    ~expected:2
    ~actual:(count_operations second.frame_patch is_drop)
    "nested drops";
  apply_and_compare ~old_snapshot:(Some (Mounted_tree.snapshot first.mounted_tree)) second
;;

let test_persistent_handler_frame_derivation () =
  let handler = press_handler (fun () -> ()) in
  let entry handler_id =
    Handler_registry.Frame.
      { node_id = Runtime.Node_id.Private.of_int64 (Int64.add handler_id 100L)
      ; event_tag = Event.Tag.Press
      ; handler_id = Runtime.Handler_id.Private.of_int64 handler_id
      ; handler
      }
  in
  let first_entry = entry 1L in
  let second_entry = entry 2L in
  let third_entry = entry 3L in
  let base =
    Handler_registry.Frame.Private.create ~revision:1L [ first_entry; second_entry ]
  in
  check
    (Option.is_some (Handler_registry.Frame.find base first_entry.handler_id))
    "handler frame lookup missed an existing entry";
  let unchanged =
    Handler_registry.Frame.Private.derive
      ~revision:2L
      ~base_revision:1L
      ~base
      ~removals:[]
      ~additions:[]
  in
  check_int64
    ~expected:2L
    ~actual:
      (Handler_registry.Frame.revision unchanged |> ID.Runtime.Renderer_revision.to_int64)
    "derived handler frame revision";
  let changed =
    Handler_registry.Frame.Private.derive
      ~revision:3L
      ~base_revision:1L
      ~base
      ~removals:[ first_entry.handler_id ]
      ~additions:[ third_entry ]
  in
  check
    (Option.is_some (Handler_registry.Frame.find base first_entry.handler_id))
    "derivation mutated the base frame removal";
  check
    (Option.is_none (Handler_registry.Frame.find base third_entry.handler_id))
    "derivation mutated the base frame addition";
  check
    (Option.is_none (Handler_registry.Frame.find changed first_entry.handler_id))
    "derived frame retained a removed handler";
  check
    (Option.is_some (Handler_registry.Frame.find changed third_entry.handler_id))
    "derived frame omitted an added handler";
  expect_invalid_argument
    (fun () ->
       Handler_registry.Frame.Private.derive
         ~revision:4L
         ~base_revision:0L
         ~base
         ~removals:[]
         ~additions:[])
    "mismatched handler base revision";
  expect_invalid_argument
    (fun () ->
       Handler_registry.Frame.Private.derive
         ~revision:4L
         ~base_revision:1L
         ~base
         ~removals:[ first_entry.handler_id; first_entry.handler_id ]
         ~additions:[])
    "duplicate handler removal";
  expect_invalid_argument
    (fun () ->
       Handler_registry.Frame.Private.derive
         ~revision:4L
         ~base_revision:1L
         ~base
         ~removals:[ Runtime.Handler_id.Private.of_int64 99L ]
         ~additions:[])
    "missing handler removal";
  expect_invalid_argument
    (fun () ->
       Handler_registry.Frame.Private.derive
         ~revision:4L
         ~base_revision:1L
         ~base
         ~removals:[]
         ~additions:[ second_entry ])
    "colliding handler addition";
  expect_invalid_argument
    (fun () ->
       let duplicate = entry 9L in
       Handler_registry.Frame.Private.derive
         ~revision:4L
         ~base_revision:1L
         ~base
         ~removals:[]
         ~additions:[ duplicate; duplicate ])
    "duplicate handler addition";
  let rebuilt =
    Handler_registry.Frame.Private.create ~revision:5L [ first_entry; third_entry ]
  in
  let derived =
    Handler_registry.Frame.Private.derive
      ~revision:5L
      ~base_revision:0L
      ~base:(Handler_registry.Frame.Private.empty ~revision:0L)
      ~removals:[]
      ~additions:[ first_entry; third_entry ]
  in
  List.iter
    (fun (entry : Handler_registry.Frame.entry) ->
       check
         (Option.is_some (Handler_registry.Frame.find rebuilt entry.handler_id)
          && Option.is_some (Handler_registry.Frame.find derived entry.handler_id))
         "full handler derivation lookup mismatch")
    [ first_entry; third_entry ]
;;

let test_handler_deltas_avoid_full_tree_collection () =
  let reconciler = Reconciler.create ~runtime_epoch:501L in
  let handler = press_handler (fun () -> ()) in
  let key = Key.string "stable-button" in
  let view label = View.button ~key ~on_press:handler ~child:(View.text label) () in
  let first =
    reconcile_exn reconciler ~base_revision:0L ~target_revision:1L ~old:None (view "one")
  in
  let second =
    Reconciler.reconcile
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      ~base_handler_frame:(Some first.handler_frame)
      (view "two")
    |> ok
  in
  let binding =
    binding_exn
      (node_by_key (Mounted_tree.snapshot second.mounted_tree) key)
      Event.Tag.Press
  in
  check
    (Option.is_some (Handler_registry.Frame.find second.handler_frame binding.handler_id))
    "property-only update lost its reused handler";
  let reorder_reconciler = Reconciler.create ~runtime_epoch:503L in
  let first_handler = press_handler (fun () -> ()) in
  let second_handler = press_handler (fun () -> ()) in
  let keyed_button key handler =
    View.button ~key:(Key.string key) ~on_press:handler ~child:(View.text key) ()
  in
  let ordered =
    reconcile_exn
      reorder_reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (View.column
         [ keyed_button "first" first_handler; keyed_button "second" second_handler ])
  in
  let reversed =
    Reconciler.reconcile
      reorder_reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some ordered.mounted_tree)
      ~base_handler_frame:(Some ordered.handler_frame)
      (View.column
         [ keyed_button "second" second_handler; keyed_button "first" first_handler ])
    |> ok
  in
  List.iter
    (fun key ->
       let before =
         binding_exn
           (node_by_key (Mounted_tree.snapshot ordered.mounted_tree) (Key.string key))
           Event.Tag.Press
       in
       let after =
         binding_exn
           (node_by_key (Mounted_tree.snapshot reversed.mounted_tree) (Key.string key))
           Event.Tag.Press
       in
       check_int64
         ~expected:(Runtime.Handler_id.to_int64 before.handler_id)
         ~actual:(Runtime.Handler_id.to_int64 after.handler_id)
         "keyed reorder changed a handler ID")
    [ "first"; "second" ]
;;

let test_handler_delta_add_replace_remove_and_drop () =
  let reconciler = Reconciler.create ~runtime_epoch:502L in
  let old_tap = press_handler (fun () -> ()) in
  let new_tap = press_handler (fun () -> ()) in
  let double_tap = press_handler (fun () -> ()) in
  let long_press = press_handler (fun () -> ()) in
  let key = Key.string "gesture" in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (View.column
         [ View.gesture
             ~key
             ~on_tap:old_tap
             ~on_double_tap:double_tap
             (View.text "gesture")
         ])
  in
  let first_node = node_by_key (Mounted_tree.snapshot first.mounted_tree) key in
  let old_tap_binding = binding_exn first_node Event.Tag.Tap in
  let old_double_binding = binding_exn first_node Event.Tag.Double_tap in
  let second =
    Reconciler.reconcile
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      ~base_handler_frame:(Some first.handler_frame)
      (View.column
         [ View.gesture
             ~key
             ~on_tap:new_tap
             ~on_long_press:long_press
             (View.text "gesture")
         ])
    |> ok
  in
  let second_node = node_by_key (Mounted_tree.snapshot second.mounted_tree) key in
  let new_tap_binding = binding_exn second_node Event.Tag.Tap in
  let long_binding = binding_exn second_node Event.Tag.Long_press in
  List.iter
    (fun handler_id ->
       check
         (Option.is_none (Handler_registry.Frame.find second.handler_frame handler_id))
         "handler delta retained a replaced or removed handler")
    [ old_tap_binding.handler_id; old_double_binding.handler_id ];
  List.iter
    (fun handler_id ->
       check
         (Option.is_some (Handler_registry.Frame.find second.handler_frame handler_id))
         "handler delta omitted an added or replacement handler")
    [ new_tap_binding.handler_id; long_binding.handler_id ];
  check
    (Option.is_some
       (Handler_registry.Frame.find first.handler_frame old_tap_binding.handler_id))
    "handler delta mutated the previous revision";
  let third =
    Reconciler.reconcile
      reconciler
      ~base_revision:2L
      ~target_revision:3L
      ~old:(Some second.mounted_tree)
      ~base_handler_frame:(Some second.handler_frame)
      (View.column [])
    |> ok
  in
  List.iter
    (fun handler_id ->
       check
         (Option.is_none (Handler_registry.Frame.find third.handler_frame handler_id))
         "dropped subtree retained a handler entry")
    [ new_tap_binding.handler_id; long_binding.handler_id ];
  let fourth =
    Reconciler.reconcile
      reconciler
      ~base_revision:3L
      ~target_revision:4L
      ~old:(Some third.mounted_tree)
      ~base_handler_frame:(Some third.handler_frame)
      (View.column [ View.gesture ~key ~on_tap:new_tap (View.text "gesture") ])
    |> ok
  in
  let remounted =
    binding_exn
      (node_by_key (Mounted_tree.snapshot fourth.mounted_tree) key)
      Event.Tag.Tap
  in
  check
    (Runtime.Handler_id.compare remounted.handler_id new_tap_binding.handler_id > 0)
    "remounted handler did not receive a fresh monotonic ID"
;;

let test_handler_change_gets_new_id_and_one_revision_grace () =
  let reconciler = Reconciler.create ~runtime_epoch:51L in
  let registry = Handler_registry.create ~runtime_epoch:51L in
  let old_calls = ref 0 in
  let new_calls = ref 0 in
  let old_handler = press_handler ~name:"old" (fun () -> incr old_calls) in
  let new_handler = press_handler ~name:"new" (fun () -> incr new_calls) in
  let key = Key.string "button" in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (View.button ~key ~on_press:old_handler ~child:(View.text "save") ())
  in
  ok (Handler_registry.install registry first.handler_frame);
  ok (Handler_registry.commit_displayed_revision registry ~revision:1L);
  let first_node = node_by_key (Mounted_tree.snapshot first.mounted_tree) key in
  let first_binding = binding_exn first_node Event.Tag.Press in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (View.button ~key ~on_press:new_handler ~child:(View.text "save") ())
  in
  ok (Handler_registry.install registry second.handler_frame);
  let second_node = node_by_key (Mounted_tree.snapshot second.mounted_tree) key in
  let second_binding = binding_exn second_node Event.Tag.Press in
  check
    (not (Runtime.Handler_id.equal first_binding.handler_id second_binding.handler_id))
    "changed handler reused a handler ID";
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_update_event_bindings)
    "event binding update";
  (match
     Handler_registry.dispatch
       registry
       { runtime_epoch = epoch 51L
       ; displayed_revision = revision 2L
       ; node_id = second_node.node_id
       ; event_tag = Event.Tag.Press
       ; handler_id = second_binding.handler_id
       ; event_sequence = event_sequence 1L
       ; payload = Event.Payload.Unit
       }
   with
   | Error (Runtime_error.Stale_event _) -> ()
   | Error error ->
     fail "wrong unpresented-frame error: %s" (Runtime_error.to_string error)
   | Ok () -> fail "event from an unpresented frame invoked its handler");
  ok
    (Handler_registry.dispatch
       registry
       { runtime_epoch = epoch 51L
       ; displayed_revision = revision 1L
       ; node_id = first_node.node_id
       ; event_tag = Event.Tag.Press
       ; handler_id = first_binding.handler_id
       ; event_sequence = event_sequence 1L
       ; payload = Event.Payload.Unit
       });
  check_int ~expected:1 ~actual:!old_calls "old handler before presentation";
  check_int ~expected:0 ~actual:!new_calls "new handler before presentation";
  ok (Handler_registry.commit_displayed_revision registry ~revision:2L);
  ok
    (Handler_registry.dispatch
       registry
       { runtime_epoch = epoch 51L
       ; displayed_revision = revision 1L
       ; node_id = first_node.node_id
       ; event_tag = Event.Tag.Press
       ; handler_id = first_binding.handler_id
       ; event_sequence = event_sequence 2L
       ; payload = Event.Payload.Unit
       });
  check_int ~expected:2 ~actual:!old_calls "previous-frame handler during grace period";
  ok
    (Handler_registry.dispatch
       registry
       { runtime_epoch = epoch 51L
       ; displayed_revision = revision 2L
       ; node_id = second_node.node_id
       ; event_tag = Event.Tag.Press
       ; handler_id = second_binding.handler_id
       ; event_sequence = event_sequence 3L
       ; payload = Event.Payload.Unit
       });
  check_int ~expected:1 ~actual:!new_calls "new handler after presentation";
  let third =
    reconcile_exn
      reconciler
      ~base_revision:2L
      ~target_revision:3L
      ~old:(Some second.mounted_tree)
      (View.button ~key ~on_press:new_handler ~child:(View.text "save") ())
  in
  ok (Handler_registry.install registry third.handler_frame);
  ok (Handler_registry.commit_displayed_revision registry ~revision:3L);
  match
    Handler_registry.dispatch
      registry
      { runtime_epoch = epoch 51L
      ; displayed_revision = revision 1L
      ; node_id = first_node.node_id
      ; event_tag = Event.Tag.Press
      ; handler_id = first_binding.handler_id
      ; event_sequence = event_sequence 4L
      ; payload = Event.Payload.Unit
      }
  with
  | Error (Runtime_error.Stale_event _) -> ()
  | Error error -> fail "wrong stale-handler error: %s" (Runtime_error.to_string error)
  | Ok () -> fail "event exceeded the one-revision grace period"
;;

let test_unchanged_handler_reuses_id () =
  let reconciler = Reconciler.create ~runtime_epoch:52L in
  let handler = press_handler (fun () -> ()) in
  let key = Key.string "button" in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (View.button ~key ~on_press:handler ~child:(View.text "one") ())
  in
  let first_binding =
    binding_exn
      (node_by_key (Mounted_tree.snapshot first.mounted_tree) key)
      Event.Tag.Press
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (View.button ~key ~on_press:handler ~child:(View.text "two") ())
  in
  let second_binding =
    binding_exn
      (node_by_key (Mounted_tree.snapshot second.mounted_tree) key)
      Event.Tag.Press
  in
  check_int64
    ~expected:(Runtime.Handler_id.to_int64 first_binding.handler_id)
    ~actual:(Runtime.Handler_id.to_int64 second_binding.handler_id)
    "unchanged handler ID";
  check_int
    ~expected:0
    ~actual:(count_operations second.frame_patch is_update_event_bindings)
    "unchanged binding patch"
;;

let test_handler_registry_validates_epoch_sequence_and_binding () =
  let reconciler = Reconciler.create ~runtime_epoch:53L in
  let registry = Handler_registry.create ~runtime_epoch:53L in
  let calls = ref 0 in
  let key = Key.string "button" in
  let output =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (View.button
         ~key
         ~on_press:(press_handler (fun () -> incr calls))
         ~child:(View.text "go")
         ())
  in
  ok (Handler_registry.install registry output.handler_frame);
  ok (Handler_registry.commit_displayed_revision registry ~revision:1L);
  let node = node_by_key (Mounted_tree.snapshot output.mounted_tree) key in
  let binding = binding_exn node Event.Tag.Press in
  let event =
    { Handler_registry.runtime_epoch = epoch 53L
    ; displayed_revision = revision 1L
    ; node_id = node.node_id
    ; event_tag = Event.Tag.Press
    ; handler_id = binding.handler_id
    ; event_sequence = event_sequence 10L
    ; payload = Event.Payload.Unit
    }
  in
  (match Handler_registry.dispatch registry { event with runtime_epoch = epoch 999L } with
   | Error (Runtime_error.Wrong_runtime_epoch _) -> ()
   | Error error -> fail "wrong epoch error: %s" (Runtime_error.to_string error)
   | Ok () -> fail "wrong-epoch event was accepted");
  ok (Handler_registry.dispatch registry event);
  (match Handler_registry.dispatch registry event with
   | Error (Runtime_error.Duplicate_or_out_of_order_event _) -> ()
   | Error error -> fail "wrong duplicate error: %s" (Runtime_error.to_string error)
   | Ok () -> fail "duplicate event sequence was accepted");
  (match
     Handler_registry.dispatch
       registry
       { event with
         event_sequence = ID.Runtime.Event_sequence.of_int64 11L
       ; node_id = ID.Ui.Node_id.succ event.node_id
       }
   with
   | Error (Runtime_error.Handler_mismatch _) -> ()
   | Error error ->
     fail "wrong binding mismatch error: %s" (Runtime_error.to_string error)
   | Ok () -> fail "mismatched node invoked a handler");
  check_int ~expected:1 ~actual:!calls "validated handler call count"
;;

let test_handler_exception_is_structured () =
  let reconciler = Reconciler.create ~runtime_epoch:54L in
  let registry = Handler_registry.create ~runtime_epoch:54L in
  let key = Key.string "button" in
  let output =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (View.button
         ~key
         ~on_press:(press_handler (fun () -> failwith "handler exploded"))
         ~child:(View.text "go")
         ())
  in
  ok (Handler_registry.install registry output.handler_frame);
  ok (Handler_registry.commit_displayed_revision registry ~revision:1L);
  let node = node_by_key (Mounted_tree.snapshot output.mounted_tree) key in
  let binding = binding_exn node Event.Tag.Press in
  match
    Handler_registry.dispatch
      registry
      { runtime_epoch = epoch 54L
      ; displayed_revision = revision 1L
      ; node_id = node.node_id
      ; event_tag = Event.Tag.Press
      ; handler_id = binding.handler_id
      ; event_sequence = event_sequence 1L
      ; payload = Event.Payload.Unit
      }
  with
  | Error (Runtime_error.Handler_exception { message; _ }) ->
    check (String.equal message "handler exploded") "handler exception message changed"
  | Error error ->
    fail "wrong handler exception error: %s" (Runtime_error.to_string error)
  | Ok () -> fail "handler exception escaped structured handling"
;;

let test_handler_retirement_is_separate_from_presentation_marking () =
  let reconciler = Reconciler.create ~runtime_epoch:58L in
  let registry = Handler_registry.create ~runtime_epoch:58L in
  let handler = press_handler (fun () -> ()) in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (View.button ~on_press:handler ~child:(View.text "one") ())
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (View.button ~on_press:handler ~child:(View.text "two") ())
  in
  ok (Handler_registry.install registry first.handler_frame);
  ok (Handler_registry.install registry second.handler_frame);
  ok (Handler_registry.mark_displayed_revision registry ~revision:2L);
  check_int
    ~expected:2
    ~actual:(Handler_registry.retained_frame_count registry)
    "presentation marking retired a handler frame";
  Handler_registry.retire_before registry ~revision:2L;
  check_int
    ~expected:1
    ~actual:(Handler_registry.retained_frame_count registry)
    "explicit handler retirement"
;;

let test_node_ids_are_never_reused () =
  let reconciler = Reconciler.create ~runtime_epoch:55L in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (keyed_text "old" "old")
  in
  let old_id = Mounted_tree.root_id first.mounted_tree in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (keyed_text "new" "new")
  in
  let new_id = Mounted_tree.root_id second.mounted_tree in
  check
    (Runtime.Node_id.compare new_id old_id > 0)
    "node ID was reused or moved backwards"
;;

let test_ten_thousand_keyed_children_reverse_in_linear_shape () =
  let count = 10_000 in
  let child index =
    let key = Printf.sprintf "item-%05d" index in
    keyed_text key key
  in
  let reconciler = Reconciler.create ~runtime_epoch:56L in
  let old_children = List.init count child in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (View.column old_children)
  in
  let before = Mounted_tree.snapshot first.mounted_tree in
  let reversed_children = List.init count (fun index -> child (count - index - 1)) in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (View.column reversed_children)
  in
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_create) "creates";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_drop) "drops";
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_set_children)
    "set children";
  apply_and_compare ~old_snapshot:(Some before) second
;;

let random_unique_tree state generation =
  let root_children = 1 + Random.State.int state 24 in
  let keys = Array.init root_children (fun index -> (generation * 1000) + index) in
  for index = root_children - 1 downto 1 do
    let other = Random.State.int state (index + 1) in
    let temporary = keys.(index) in
    keys.(index) <- keys.(other);
    keys.(other) <- temporary
  done;
  let retained = Random.State.int state (root_children + 1) in
  Array.to_list (Array.sub keys 0 retained)
  |> List.map (fun key ->
    let text = Printf.sprintf "g%d-k%d" generation key in
    View.text ~key:(Key.int key) text)
  |> View.column
;;

let test_randomized_patch_invariant () =
  let random = Random.State.make [| 0xB0; 0x5A; 0x1 |] in
  let reconciler = Reconciler.create ~runtime_epoch:57L in
  let mounted = ref None in
  let snapshot = ref None in
  for generation = 0 to 249 do
    let widget = random_unique_tree random generation in
    let output =
      reconcile_exn
        reconciler
        ~base_revision:(Int64.of_int generation)
        ~target_revision:(Int64.of_int (generation + 1))
        ~old:!mounted
        widget
    in
    apply_and_compare ~old_snapshot:!snapshot output;
    mounted := Some output.mounted_tree;
    snapshot := Some (Mounted_tree.snapshot output.mounted_tree)
  done
;;

let test_layout_material_and_semantics_widgets_are_incremental () =
  let reconciler = Reconciler.create ~runtime_epoch:59L in
  let changed_to = ref None in
  let on_changed =
    Event.Handler.create ~name:"checkbox-change" (function
      | Event.Payload.Bool value -> changed_to := Some value
      | _ -> ())
  in
  let on_scroll = Event.Handler.create ~name:"scroll" (fun _ -> ()) in
  let key = Key.string "checkbox" in
  let tree value =
    View.theme
      ~data:(Ui.Theme.create ~mode:Ui.Theme.Dark ())
      (View.semantics
         ~properties:(Ui.Semantics.create ~label:"Accept terms" ())
         (View.padding
            ~insets:(Ui.Layout.Edge_insets.symmetric ~horizontal:12. ~vertical:8. ())
            (View.frame
               ~max_width:Ui.Layout.Frame_limit.Fill
               ~max_height:Ui.Layout.Frame_limit.Fill
               (View.Scroll.vertical
                  ~on_scroll
                  (Ui.View.toggle
                     ~style:Ui.View.Toggle_style.Checkbox
                     ~label:(Ui.View.text "Completed")
                     ~key
                     ~value
                     ~on_changed
                     ())
                |> View.Viewport.Vertical.with_height ~height:240.))))
  in
  let first =
    reconcile_exn reconciler ~base_revision:0L ~target_revision:1L ~old:None (tree false)
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (tree true)
  in
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_update_props)
    "checkbox prop updates";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_create) "creates";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_drop) "drops";
  let checkbox = node_by_key (Mounted_tree.snapshot second.mounted_tree) key in
  let binding = binding_exn checkbox Event.Tag.Value_changed in
  let registry = Handler_registry.create ~runtime_epoch:59L in
  ok (Handler_registry.install registry second.handler_frame);
  ok (Handler_registry.commit_displayed_revision registry ~revision:2L);
  ok
    (Handler_registry.dispatch
       registry
       { runtime_epoch = epoch 59L
       ; displayed_revision = revision 2L
       ; node_id = checkbox.node_id
       ; event_tag = Event.Tag.Value_changed
       ; handler_id = binding.handler_id
       ; event_sequence = event_sequence 1L
       ; payload = Event.Payload.Bool false
       });
  check (!changed_to = Some false) "checkbox did not receive the typed bool payload";
  apply_and_compare ~old_snapshot:(Some (Mounted_tree.snapshot first.mounted_tree)) second
;;

let test_frame_reconciles_optional_maximum_transitions () =
  let reconciler = Reconciler.create ~runtime_epoch:590L in
  let key = Key.string "constraints" in
  let tree max_height =
    View.frame
      ~key
      ~min_height:44.
      ?max_height:
        (Option.map (fun value -> Ui.Layout.Frame_limit.Points value) max_height)
      (View.text "Visible")
  in
  let unbounded =
    reconcile_exn reconciler ~base_revision:0L ~target_revision:1L ~old:None (tree None)
  in
  let bounded =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some unbounded.mounted_tree)
      (tree (Some 200.))
  in
  check_int
    ~expected:1
    ~actual:(count_operations bounded.frame_patch is_update_props)
    "None to Some maximum update";
  check_int
    ~expected:0
    ~actual:(count_operations bounded.frame_patch is_create)
    "None to Some maximum creates";
  check_int
    ~expected:0
    ~actual:(count_operations bounded.frame_patch is_drop)
    "None to Some maximum drops";
  apply_and_compare
    ~old_snapshot:(Some (Mounted_tree.snapshot unbounded.mounted_tree))
    bounded;
  let unbounded_again =
    reconcile_exn
      reconciler
      ~base_revision:2L
      ~target_revision:3L
      ~old:(Some bounded.mounted_tree)
      (tree None)
  in
  check_int
    ~expected:1
    ~actual:(count_operations unbounded_again.frame_patch is_update_props)
    "Some to None maximum update";
  check_int
    ~expected:0
    ~actual:(count_operations unbounded_again.frame_patch is_create)
    "Some to None maximum creates";
  check_int
    ~expected:0
    ~actual:(count_operations unbounded_again.frame_patch is_drop)
    "Some to None maximum drops";
  apply_and_compare
    ~old_snapshot:(Some (Mounted_tree.snapshot bounded.mounted_tree))
    unbounded_again
;;

let test_linear_progress_indicator_reconciles_value_and_kind () =
  let reconciler = Reconciler.create ~runtime_epoch:591L in
  let key = Key.string "progress" in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (Ui.View.progress ~key ~value:0.25 ())
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (Ui.View.progress ~key ())
  in
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_update_props)
    "linear progress value update";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_create) "creates";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_drop) "drops";
  apply_and_compare ~old_snapshot:(Some (Mounted_tree.snapshot first.mounted_tree)) second;
  let third =
    reconcile_exn
      reconciler
      ~base_revision:2L
      ~target_revision:3L
      ~old:(Some second.mounted_tree)
      (Ui.View.progress ~style:Ui.View.Progress_style.Circular ~key ())
  in
  check_int
    ~expected:0
    ~actual:(count_operations third.frame_patch is_create)
    "progress style update retains the node";
  check_int
    ~expected:0
    ~actual:(count_operations third.frame_patch is_drop)
    "progress style update does not drop the node";
  check_int
    ~expected:1
    ~actual:(count_operations third.frame_patch is_update_props)
    "progress style update";
  apply_and_compare ~old_snapshot:(Some (Mounted_tree.snapshot second.mounted_tree)) third
;;

let test_native_text_field_props_and_typed_edit_are_incremental () =
  let reconciler = Reconciler.create ~runtime_epoch:60L in
  let edits = ref [] in
  let on_edit =
    Event.Handler.create ~name:"text-edit" (function
      | Event.Payload.Text_edit edit -> edits := edit :: !edits
      | _ -> ())
  in
  let on_submit = Event.Handler.create ~name:"text-submit" (fun _ -> ()) in
  let on_focus_changed = Event.Handler.create ~name:"focus-changed" (fun _ -> ()) in
  let key = Key.string "editor" in
  let value text offset =
    let selection =
      Ui.Text_editing.Range.create ~text ~start_utf16:offset ~end_utf16:offset
    in
    Ui.Text_editing.Value.create ~text ~selection ()
  in
  let tree ~document_revision ~accepted_local_revision ~update_mode value =
    Ui.View.text_field
      ~label:"Text input"
      ~key
      ~session_id:(ID.Text_input.Session_id.of_int64 7L)
      ~document_revision:(ID.Text_input.Document_revision.of_int64 document_revision)
      ~accepted_local_revision:
        (ID.Text_input.Local_revision.of_int64 accepted_local_revision)
      ~update_mode
      ~value
      ~on_edit
      ~on_submit
      ~on_focus_changed
      ()
  in
  let first =
    reconcile_exn
      reconciler
      ~base_revision:0L
      ~target_revision:1L
      ~old:None
      (tree
         ~document_revision:1L
         ~accepted_local_revision:0L
         ~update_mode:Ui.Text_editing.Force_replace
         (value "A😀" 3))
  in
  let second =
    reconcile_exn
      reconciler
      ~base_revision:1L
      ~target_revision:2L
      ~old:(Some first.mounted_tree)
      (tree
         ~document_revision:2L
         ~accepted_local_revision:1L
         ~update_mode:Ui.Text_editing.Correction
         (value "A😀!" 4))
  in
  check_int
    ~expected:1
    ~actual:(count_operations second.frame_patch is_update_props)
    "text input prop updates";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_create) "creates";
  check_int ~expected:0 ~actual:(count_operations second.frame_patch is_drop) "drops";
  let editor = node_by_key (Mounted_tree.snapshot second.mounted_tree) key in
  let binding = binding_exn editor Event.Tag.Text_edit in
  let registry = Handler_registry.create ~runtime_epoch:60L in
  ok (Handler_registry.install registry second.handler_frame);
  ok (Handler_registry.commit_displayed_revision registry ~revision:2L);
  ok
    (Handler_registry.dispatch
       registry
       { runtime_epoch = epoch 60L
       ; displayed_revision = revision 2L
       ; node_id = editor.node_id
       ; event_tag = Event.Tag.Text_edit
       ; handler_id = binding.handler_id
       ; event_sequence = event_sequence 1L
       ; payload =
           Event.Payload.Text_edit
             { session_id = ID.Text_input.Session_id.of_int64 7L
             ; local_revision = ID.Text_input.Local_revision.of_int64 2L
             ; base_document_revision = ID.Text_input.Document_revision.of_int64 2L
             ; text = "A😀!!"
             ; selection = { start_utf16 = 5; end_utf16 = 5 }
             ; composing = None
             }
       });
  check_int ~expected:1 ~actual:(List.length !edits) "typed text edit count";
  apply_and_compare ~old_snapshot:(Some (Mounted_tree.snapshot first.mounted_tree)) second
;;

let test_native_text_field_utf8_limit_contract () =
  let handler = Event.Handler.create (fun _ -> ()) in
  let value =
    Ui.Text_editing.Value.create
      ~text:""
      ~selection:(Ui.Text_editing.Range.create ~text:"" ~start_utf16:0 ~end_utf16:0)
      ()
  in
  let create_widget max_utf8_bytes =
    Ui.View.text_field
      ~label:"Text input"
      ~max_utf8_bytes
      ~session_id:(ID.Text_input.Session_id.of_int64 7L)
      ~document_revision:(ID.Text_input.Document_revision.of_int64 9L)
      ~accepted_local_revision:(ID.Text_input.Local_revision.of_int64 0L)
      ~update_mode:Ui.Text_editing.Ack
      ~value
      ~on_edit:handler
      ~on_submit:handler
      ~on_focus_changed:handler
      ~on_limit_reached:handler
      ()
  in
  let widget = create_widget 64 in
  let (Av view) = View.Private.view widget in
  (match view.node with
   | View.Private.Text_field { max_utf8_bytes = Some 64; _ } -> ()
   | _ -> fail "Native text field did not retain max_utf8_bytes");
  check
    (Array.exists
       (fun binding ->
          Event.Tag.equal binding.View.Private.tag Event.Tag.Text_limit_reached)
       view.event_bindings)
    "Native text field did not bind on_limit_reached";
  ignore
    (Ui.View.text_field
       ~label:"Text input"
       ~max_utf8_bytes:64
       ~session_id:(ID.Text_input.Session_id.of_int64 7L)
       ~document_revision:(ID.Text_input.Document_revision.of_int64 9L)
       ~accepted_local_revision:(ID.Text_input.Local_revision.of_int64 0L)
       ~update_mode:Ui.Text_editing.Ack
       ~value
       ~on_edit:handler
       ~on_submit:handler
       ~on_focus_changed:handler
       ~on_limit_reached:handler
       ());
  List.iter
    (fun max_utf8_bytes ->
       expect_invalid_argument
         (fun () -> ignore (create_widget max_utf8_bytes))
         "Native text field accepted an invalid UTF-8 byte limit")
    [ 0; -1; 1_048_577 ];
  ignore
    (Ui.View.text_field
       ~label:"Text input"
       ~session_id:(ID.Text_input.Session_id.of_int64 7L)
       ~document_revision:(ID.Text_input.Document_revision.of_int64 9L)
       ~accepted_local_revision:(ID.Text_input.Local_revision.of_int64 0L)
       ~update_mode:Ui.Text_editing.Ack
       ~value
       ~on_edit:handler
       ~on_submit:handler
       ~on_focus_changed:handler
       ())
;;

let tests =
  [ "SwiftUI button semantics", test_swiftui_button_semantics
  ; "button is a typed core widget", test_button_is_a_typed_core_widget
  ; "initial mount is a full snapshot", test_initial_mount_is_full_snapshot
  ; "physical equality emits no patch", test_physical_equality_emits_no_patch
  ; "one text change is one prop update", test_one_text_change_is_one_prop_update
  ; "keyed reorder preserves identity", test_keyed_reorder_preserves_identity
  ; ( "keyed insert and delete are incremental"
    , test_keyed_insert_and_delete_are_incremental )
  ; ( "virtual window shift preserves keyed overlap"
    , test_virtual_window_shift_preserves_keyed_overlap )
  ; ( "virtual list duplicate item keys are rejected"
    , test_virtual_list_duplicate_item_keys_are_rejected )
  ; "kind replacement remounts", test_kind_replacement_remounts
  ; ( "duplicate keys fail without consuming IDs"
    , test_duplicate_keys_fail_without_consuming_ids )
  ; "nested duplicate keys fail", test_nested_duplicate_keys_fail
  ; "existing duplicate key formatting", test_existing_duplicate_key_formatting
  ; "mixed siblings detect duplicates", test_mixed_siblings_detect_duplicates
  ; ( "single-child ancestor still validates nested duplicates"
    , test_single_child_ancestor_still_validates_nested_duplicates )
  ; ( "optimized key validation matches reference"
    , test_optimized_key_validation_matches_reference )
  ; ( "mixed keyed and unkeyed children match by index"
    , test_mixed_keyed_and_unkeyed_match_by_index )
  ; "nested removal drops complete subtree", test_nested_removal_drops_complete_subtree
  ; "persistent handler frame derivation", test_persistent_handler_frame_derivation
  ; ( "handler deltas avoid full-tree collection"
    , test_handler_deltas_avoid_full_tree_collection )
  ; ( "handler delta add replace remove and drop"
    , test_handler_delta_add_replace_remove_and_drop )
  ; ( "handler change gets a new ID and one-revision grace"
    , test_handler_change_gets_new_id_and_one_revision_grace )
  ; "unchanged handler reuses ID", test_unchanged_handler_reuses_id
  ; ( "handler registry validates epoch, sequence, and binding"
    , test_handler_registry_validates_epoch_sequence_and_binding )
  ; "handler exception is structured", test_handler_exception_is_structured
  ; ( "handler retirement is separate from presentation marking"
    , test_handler_retirement_is_separate_from_presentation_marking )
  ; "node IDs are never reused", test_node_ids_are_never_reused
  ; ( "10,000 keyed children reverse in linear shape"
    , test_ten_thousand_keyed_children_reverse_in_linear_shape )
  ; "randomized patch invariant", test_randomized_patch_invariant
  ; ( "layout, Material, and semantics widgets update incrementally"
    , test_layout_material_and_semantics_widgets_are_incremental )
  ; ( "frame reconciles optional maximum transitions"
    , test_frame_reconciles_optional_maximum_transitions )
  ; ( "linear progress indicator reconciles value and kind"
    , test_linear_progress_indicator_reconciles_value_and_kind )
  ; ( "text input props and typed edit are incremental"
    , test_native_text_field_props_and_typed_edit_are_incremental )
  ; "Native text field UTF-8 limit contract", test_native_text_field_utf8_limit_contract
  ]
;;

let () =
  Printexc.record_backtrace true;
  let failures = ref [] in
  List.iter
    (fun (name, test) ->
       try
         test ();
         Printf.printf "ok - %s\n%!" name
       with
       | exception_ ->
         failures := (name, exception_, Printexc.get_backtrace ()) :: !failures;
         Printf.eprintf "not ok - %s\n%!" name)
    tests;
  match List.rev !failures with
  | [] -> ()
  | failures ->
    List.iter
      (fun (name, exception_, backtrace) ->
         Printf.eprintf "\n%s\n%s\n%s\n%!" name (Printexc.to_string exception_) backtrace)
      failures;
    exit 1
;;
