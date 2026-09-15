module Test = Bonsai_swiftui_test
module Ui = Bonsai_swiftui_ui
module Runtime = Bonsai_swiftui_runtime
module ID = Bonsai_swiftui_spec.Id

let fail format = Printf.ksprintf failwith format
let require condition message = if not condition then fail "%s" message

let test_mail_app_disables_trace_by_default () =
  require
    (Option.is_none (App.Private.trace Mail.app))
    "the default mail app enables runtime tracing"
;;

let create_handle () =
  let time_source = Bonsai.Time_source.create ~start:Core.Time_ns.epoch in
  Test.Handle.create
    ~runtime_epoch:(ID.Runtime.Epoch.of_int64 902L)
    ~time_source
    Mail.component
;;

let require_present handle query message =
  require (Option.is_some (Test.Handle.find handle query)) message
;;

let require_absent handle query message =
  require (Option.is_none (Test.Handle.find handle query)) message
;;

let require_node handle query message =
  match Test.Handle.find handle query with
  | Some node -> node
  | None -> fail "%s" message
;;

let with_handle test =
  let handle = create_handle () in
  match test handle with
  | () -> Test.Handle.shutdown handle
  | exception error ->
    Test.Handle.shutdown handle;
    raise error
;;

let test_initial_inbox_and_semantics () =
  with_handle (fun handle ->
    require_present
      handle
      (Test.Query.test_id "mail-list-page")
      "mail list page is missing";
    require_present
      handle
      (Test.Query.test_id "mail-search-header")
      "static mail search header is missing";
    List.iter
      (fun id ->
         require_present
           handle
           (Test.Query.test_id (Printf.sprintf "mail-row-%d" id))
           (Printf.sprintf "visible inbox message %d is missing" id);
         let slidable =
           require_node
             handle
             (Test.Query.test_id (Printf.sprintf "mail-swipe-%d" id))
             (Printf.sprintf "Swipe_actions host for message %d is missing" id)
         in
         require
           (Ui.View.Private.kind_tag_equal
              slidable.Runtime.Mounted_tree.Snapshot.node_tag
              Ui.View.Private.K_swipe_actions)
           "mail swipe host is not a native Swipe_actions node";
         require
           (Array.length slidable.children = 4)
           "mail Swipe_actions host does not expose content and three actions")
      Mail.For_testing.initial_inbox_ids;
    require_present
      handle
      (Test.Query.semantics_label "Unread message from Mara Vale")
      "initial inbox does not expose unread semantics";
    require_present
      handle
      (Test.Query.semantics_label "Read message from River Tan")
      "initial inbox does not expose read semantics")
;;

let swipe_action handle id action_id =
  Test.Handle.present handle;
  let name =
    match action_id with
    | 1 -> "archive"
    | 2 -> "trash"
    | 3 -> "read"
    | _ -> fail "unknown action"
  in
  Test.Handle.click
    handle
    (Test.Query.key (Ui.Key.string (Printf.sprintf "mail-swipe-%s-%d" name id)))
;;

let press handle id =
  Test.Handle.present handle;
  Test.Handle.click handle (Test.Query.test_id (Printf.sprintf "mail-button-%d" id))
;;

let open_card handle id =
  Test.Handle.present handle;
  Test.Handle.click handle (Test.Query.test_id (Printf.sprintf "mail-card-open-%d" id))
;;

let native_visible_range handle ~first_index ~last_exclusive =
  Test.Handle.present handle;
  Test.Handle.visible_range
    handle
    (Test.Query.kind "Collection_catalog")
    ~first_index:(Int64.of_int first_index)
    ~last_exclusive:(Int64.of_int last_exclusive)
;;

let advance_logical_time handle nanoseconds =
  Test.Handle.present handle;
  ignore (Test.Handle.pump handle ~monotonic_now_ns:nanoseconds ());
  Test.Handle.presentation_succeeded handle ~monotonic_now_ns:nanoseconds
;;

let split_state handle =
  let node =
    require_node
      handle
      (Test.Query.test_id "mail-navigation-split")
      "native Mail split view is missing"
  in
  let (Av view) = Ui.View.Private.view node.widget in
  match view.node with
  | Ui.View.Private.Navigation_split { state; _ } -> state
  | _ -> fail "Mail does not use the native split contract"
;;

let selected_tab handle =
  let node =
    require_node handle (Test.Query.test_id "mail-tabs") "native Mail tabs are missing"
  in
  let (Av view) = Ui.View.Private.view node.widget in
  match view.node with
  | Ui.View.Private.Tabs { selection } -> ID.Navigation.Page_key.to_string selection
  | _ -> fail "Mail does not use native tabs"
;;

let select_tab handle key =
  Test.Handle.present handle;
  Test.Handle.tab_selected
    handle
    (Test.Query.test_id "mail-tabs")
    ~page_key:(ID.Navigation.Page_key.of_string key)
;;

let change_split handle state =
  Test.Handle.present handle;
  Test.Handle.navigation_split_changed
    handle
    (Test.Query.test_id "mail-navigation-split")
    ~state
;;

let return_from_detail handle ~page_key () =
  change_split
    handle
    (Ui.Navigation.Split_state.create
       ~visibility:(Ui.Navigation.Split_state.visibility (split_state handle))
       ~compact_column:Ui.Navigation.Split_column.Content
       ~selection_key:page_key
       ())
;;

let test_native_tabs_keep_all_four_pages () =
  with_handle (fun handle ->
    require (selected_tab handle = "mail") "Mail is not initially selected";
    let items = Test.Handle.find_all handle (Test.Query.kind "Tab") in
    let keys =
      List.map
        (fun node ->
           let (Av view) =
             Ui.View.Private.view node.Runtime.Mounted_tree.Snapshot.widget
           in
           match view.node with
           | Ui.View.Private.Tab { page_key; _ } ->
             ID.Navigation.Page_key.to_string page_key
           | _ -> fail "unexpected tab")
        items
      |> List.sort String.compare
    in
    require
      (keys = [ "chat"; "mail"; "meet"; "spaces" ])
      "Mail does not expose four native tabs";
    select_tab handle "chat";
    require (selected_tab handle = "chat") "Chat was not selected";
    let retained = Test.Handle.find_all handle (Test.Query.kind "Tab") in
    require
      (List.for_all
         (fun original ->
            List.exists
              (fun node ->
                 Runtime.Node_id.equal
                   node.Runtime.Mounted_tree.Snapshot.node_id
                   original.Runtime.Mounted_tree.Snapshot.node_id)
              retained)
         items)
      "tab selection replaced an application page";
    select_tab handle "unknown";
    require (selected_tab handle = "chat") "unknown tab changed the application selection")
;;

let test_native_navigation_owns_its_layout () =
  with_handle (fun handle ->
    ignore (split_state handle);
    ignore (selected_tab handle);
    List.iter
      (fun kind ->
         require_absent
           handle
           (Test.Query.kind kind)
           ("Mail retained obsolete navigation/layout node " ^ kind))
      [ "Navigator"; "Page"; "Material_scaffold"; "Ignores_safe_area" ];
    require_absent
      handle
      (Test.Query.test_id "mail-bottom-navigation")
      "Mail still paints its own tab bar";
    require_present
      handle
      (Test.Query.test_id "mail-detail-placeholder")
      "unselected detail column has no placeholder")
;;

let test_star_preserves_keyed_row_identity () =
  with_handle (fun handle ->
    let row_before =
      match Test.Handle.find handle (Test.Query.test_id "mail-row-2") with
      | Some row -> row
      | None -> fail "mail row 2 is missing"
    in
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-star-2");
    let row_after =
      match Test.Handle.find handle (Test.Query.test_id "mail-row-2") with
      | Some row -> row
      | None -> fail "mail row 2 disappeared after starring"
    in
    require
      (Runtime.Node_id.equal row_before.node_id row_after.node_id)
      "starring replaced the keyed mail row";
    require_present
      handle
      (Test.Query.semantics_label "Starred message from River Tan")
      "starred state is not exposed semantically")
;;

let test_expand_open_and_platform_pop_preserve_state () =
  with_handle (fun handle ->
    let swipe_before =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "mail swipe host 1 is missing before open"
    in
    press handle 1;
    require_present
      handle
      (Test.Query.test_id "mail-card-1")
      "row press did not expand the inline card";
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "row expansion opened the detail page";
    require_present
      handle
      (Test.Query.semantics_label "Unread message from Mara Vale")
      "row expansion marked the message read";
    open_card handle 1;
    let swipe_while_open =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "mail swipe host 1 disappeared behind detail"
    in
    require
      (Runtime.Node_id.equal swipe_before.node_id swipe_while_open.node_id)
      "opening an unread message replaced its keyed swipe host";
    require_present
      handle
      (Test.Query.key (Ui.Key.string "mail-detail-1"))
      "detail page key is missing or unstable";
    require_present
      handle
      (Test.Query.visible_text "The field notes are ready")
      "detail subject does not match the selected message";
    require_present
      handle
      (Test.Query.visible_text "Mara Vale")
      "detail sender does not match the selected message";
    Test.Handle.present handle;
    return_from_detail
      handle
      ~page_key:(ID.Navigation.Page_key.of_string "mail-detail-1")
      ();
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "platform pop did not return to the inbox";
    require_present
      handle
      (Test.Query.test_id "mail-card-1")
      "platform pop did not restore the expanded card";
    require_present
      handle
      (Test.Query.semantics_label "Read message from Mara Vale")
      "opened message did not remain read after platform pop";
    let swipe_after =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "mail swipe host 1 disappeared after pop"
    in
    require
      (Runtime.Node_id.equal swipe_before.node_id swipe_after.node_id)
      "read-state change replaced the keyed swipe host")
;;

let test_swipe_archive_removes_only_target_and_retains_following_identity () =
  with_handle (fun handle ->
    let following_before =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-2")
        "following swipe host is missing before archive"
    in
    swipe_action handle 1 1;
    require_absent
      handle
      (Test.Query.test_id "mail-swipe-1")
      "archive swipe did not remove the target";
    require_absent
      handle
      (Test.Query.test_id "mail-row-1")
      "archive swipe left the target row mounted";
    let following_after =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-2")
        "archive removed the following row"
    in
    require
      (Runtime.Node_id.equal following_before.node_id following_after.node_id)
      "archiving a preceding row replaced the following keyed swipe host";
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "archive swipe opened the detail page")
;;

let test_swipe_trash_action_removes_target () =
  with_handle (fun handle ->
    swipe_action handle 1 2;
    require_absent
      handle
      (Test.Query.test_id "mail-row-1")
      "Trash action left the target in the inbox";
    require_present
      handle
      (Test.Query.test_id "mail-row-2")
      "Trash action removed an unrelated inbox row";
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "Trash action opened the detail page")
;;

let test_swipe_read_action_updates_in_place_without_navigation () =
  with_handle (fun handle ->
    let before =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "swipe host is missing before mark read"
    in
    swipe_action handle 1 3;
    require_present
      handle
      (Test.Query.semantics_label "Read message from Mara Vale")
      "end swipe did not mark the unread message read";
    let after_read =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "swipe host disappeared after mark read"
    in
    require
      (Runtime.Node_id.equal before.node_id after_read.node_id)
      "mark read replaced the keyed swipe host";
    swipe_action handle 1 3;
    require_present
      handle
      (Test.Query.semantics_label "Unread message from Mara Vale")
      "second end swipe did not mark the read message unread";
    let after_unread =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "swipe host disappeared after mark unread"
    in
    require
      (Runtime.Node_id.equal before.node_id after_unread.node_id)
      "mark unread replaced the keyed swipe host";
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "read-state swipe opened the detail page")
;;

let test_stale_split_return_is_ignored () =
  with_handle (fun handle ->
    press handle 1;
    open_card handle 1;
    Test.Handle.present handle;
    return_from_detail
      handle
      ~page_key:(ID.Navigation.Page_key.of_string "mail-detail-999")
      ();
    require_present
      handle
      (Test.Query.test_id "mail-detail-page")
      "stale route-pop key cleared the selected detail";
    Test.Handle.present handle;
    return_from_detail
      handle
      ~page_key:(ID.Navigation.Page_key.of_string "mail-detail-1")
      ();
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "matching route-pop key did not clear detail")
;;

let test_archive_delete_and_mark_unread () =
  let expect_removed action_id message_id =
    with_handle (fun handle ->
      press handle message_id;
      open_card handle message_id;
      Test.Handle.present handle;
      Test.Handle.click handle (Test.Query.test_id action_id);
      require_absent
        handle
        (Test.Query.test_id (Printf.sprintf "mail-row-%d" message_id))
        (Printf.sprintf
           "%s did not remove message %d from the inbox"
           action_id
           message_id);
      require_absent
        handle
        (Test.Query.test_id "mail-detail-page")
        (Printf.sprintf "%s did not pop detail" action_id))
  in
  expect_removed "mail-archive" 1;
  expect_removed "mail-delete" 2;
  with_handle (fun handle ->
    press handle 3;
    open_card handle 3;
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-mark-unread");
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "mark unread did not pop detail";
    require_present
      handle
      (Test.Query.semantics_label "Unread message from Orin Studio")
      "mark unread did not update row semantics")
;;

let test_detail_star_attachment_and_reply_notice () =
  with_handle (fun handle ->
    press handle 4;
    open_card handle 4;
    require_present
      handle
      (Test.Query.test_id "mail-attachment")
      "fixture attachment is missing";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-detail-star");
    require_present
      handle
      (Test.Query.semantics_label "Starred message from Juniper Works")
      "detail star did not update selected state";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-reply-all");
    require_present
      handle
      (Test.Query.test_id "mail-inline-notice")
      "reply action did not create the inline notice";
    require_present
      handle
      (Test.Query.visible_text "Composing is outside the scope of this demo.")
      "reply scope notice has the wrong content")
;;

let collection_catalog_node handle =
  require_node
    handle
    (Test.Query.kind "Collection_catalog")
    "mail collection catalog is missing"
;;

let collection_window_node handle =
  require_node
    handle
    (Test.Query.kind "Collection_window")
    "mail collection window is missing"
;;

let collection_first_index handle =
  let window = collection_window_node handle in
  let (Av view) = Ui.View.Private.view window.widget in
  match view.node with
  | Ui.View.Private.Collection_window { first_index; _ } -> first_index
  | _ -> fail "mail materialization has no collection window"
;;

let test_painted_ranges_keep_the_paging_handler_until_behavior_changes () =
  with_handle (fun handle ->
    let handler () =
      let node = collection_catalog_node handle in
      let (Av view) = Ui.View.Private.view node.widget in
      require (Array.length view.event_bindings = 1) "collection has ambiguous handlers";
      view.event_bindings.(0).handler
    in
    let initial = handler () in
    native_visible_range handle ~first_index:1 ~last_exclusive:8;
    require
      (handler () == initial)
      "recording a painted range replaced the paging handler";
    Test.Handle.present handle;
    let revision = Test.Handle.revision handle in
    native_visible_range handle ~first_index:1 ~last_exclusive:8;
    Test.Handle.present handle;
    require
      (Test.Handle.revision handle = revision)
      "equal painted range emitted a UI patch";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-star-2");
    require (handler () == initial) "star state replaced an unchanged paging handler";
    native_visible_range handle ~first_index:12 ~last_exclusive:20;
    require (handler () != initial) "loading behavior retained an obsolete paging handler";
    let loading = handler () in
    native_visible_range handle ~first_index:13 ~last_exclusive:20;
    require (handler () == loading) "painted range replaced the loading handler";
    advance_logical_time handle 750_000_010L;
    require (handler () != loading) "page completion retained the loading handler")
;;

let test_initial_virtual_inbox_has_twenty_unique_button_rows () =
  with_handle (fun handle ->
    require
      (List.length Mail.For_testing.initial_inbox_ids = 20)
      "initial inbox does not contain twenty messages";
    let unique = Hashtbl.create 20 in
    List.iter
      (fun id ->
         require (not (Hashtbl.mem unique id)) "initial inbox contains duplicate IDs";
         Hashtbl.add unique id ();
         require_present
           handle
           (Test.Query.test_id (Printf.sprintf "mail-button-%d" id))
           (Printf.sprintf "initial button row %d is missing" id))
      Mail.For_testing.initial_inbox_ids;
    let catalog = collection_catalog_node handle in
    let (Av view) = Ui.View.Private.view catalog.widget in
    match view.node with
    | Ui.View.Private.Collection_catalog { keys; _ } ->
      require (Array.length keys = 20) "initial logical mail count is not twenty";
      require
        (Array.length (collection_window_node handle).children <= 24)
        "initial virtual window exceeds the supplied bound"
    | _ -> fail "mail virtual list has no collection catalog")
;;

let test_three_sequential_pages_load_once_and_preserve_overlap_identity () =
  with_handle (fun handle ->
    let overlap_before =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-16")
        "overlap row is missing before pagination"
    in
    native_visible_range handle ~first_index:12 ~last_exclusive:20;
    require
      (collection_first_index handle = 8)
      "visible range did not expand through the shared overscan window policy";
    require_present
      handle
      (Test.Query.test_id "mail-loading-more")
      "tail prefetch did not show the inline loader";
    require_present
      handle
      (Test.Query.semantics_label "Loading more messages")
      "inline loader semantics are missing";
    native_visible_range handle ~first_index:13 ~last_exclusive:20;
    advance_logical_time handle 750_000_010L;
    require_absent
      handle
      (Test.Query.test_id "mail-loading-more")
      "first append did not remove the loader";
    require_present
      handle
      (Test.Query.test_id "mail-button-21")
      "first append did not add the next deterministic page";
    require_absent
      handle
      (Test.Query.test_id "mail-button-41")
      "duplicate tail notifications appended more than one page";
    let first_page_catalog = collection_catalog_node handle in
    let (Av fp_view) = Ui.View.Private.view first_page_catalog.widget in
    (match fp_view.node with
     | Ui.View.Private.Collection_catalog { keys; _ } ->
       require (Array.length keys = 40) "first cursor appended more than one page"
     | _ -> fail "mail virtual list has no collection catalog");
    let overlap_after =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-16")
        "overlap row disappeared after pagination"
    in
    require
      (Runtime.Node_id.equal overlap_before.node_id overlap_after.node_id)
      "pagination replaced an overlapping keyed row";
    native_visible_range handle ~first_index:32 ~last_exclusive:40;
    advance_logical_time handle 1_500_000_020L;
    require_present
      handle
      (Test.Query.test_id "mail-button-41")
      "second append did not add a page";
    native_visible_range handle ~first_index:52 ~last_exclusive:60;
    advance_logical_time handle 2_250_000_030L;
    require_present
      handle
      (Test.Query.test_id "mail-button-61")
      "third append did not add a page";
    native_visible_range handle ~first_index:72 ~last_exclusive:80;
    require_present
      handle
      (Test.Query.test_id "mail-loading-more")
      "the feed stopped offering another page after three appends";
    let final_window = collection_window_node handle in
    require
      (Array.length final_window.children <= 24)
      "rendered mail window grew with loaded session data")
;;

let test_sidebar_mailboxes_settings_and_native_column_state () =
  with_handle (fun handle ->
    let module Split = Ui.Navigation.Split_state in
    require
      (Split.visibility (split_state handle) = Ui.Navigation.Split_visibility.All)
      "Mail does not initially request its sidebar";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-menu");
    require
      (Split.compact_column (split_state handle) = Ui.Navigation.Split_column.Sidebar)
      "Menu did not request the compact sidebar";
    change_split
      handle
      (Split.create
         ~visibility:Ui.Navigation.Split_visibility.Double_column
         ~compact_column:Ui.Navigation.Split_column.Content
         ());
    require
      (Split.visibility (split_state handle)
       = Ui.Navigation.Split_visibility.Double_column)
      "native sidebar visibility was ignored";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-drawer-starred");
    require_absent
      handle
      (Test.Query.test_id "mail-row-2")
      "Starred retained an unstarred message";
    require_present
      handle
      (Test.Query.test_id "mail-row-1")
      "Starred hid a starred message";
    require
      (Split.compact_column (split_state handle) = Ui.Navigation.Split_column.Content)
      "mailbox selection did not show its message list";
    press handle 1;
    open_card handle 1;
    let selected = split_state handle in
    change_split
      handle
      (Split.create
         ~visibility:Ui.Navigation.Split_visibility.All
         ~compact_column:Ui.Navigation.Split_column.Detail
         ?selection_key:(Split.selection_key selected)
         ());
    require_present
      handle
      (Test.Query.test_id "mail-detail-page")
      "a visibility-only native change discarded the selected detail";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-drawer-settings");
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "switching mailbox kept the old detail";
    require_present
      handle
      (Test.Query.visible_text "Settings are outside the scope of this local mail demo.")
      "Settings has no explicit scope notice";
    change_split handle selected;
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "a stale split state restored an old message")
;;

let test_drawer_archived_trash_and_inbox_views_are_functional () =
  with_handle (fun handle ->
    swipe_action handle 1 1;
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-menu");
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-drawer-archived");
    require_present
      handle
      (Test.Query.test_id "mail-row-1")
      "Archived mailbox did not expose an archived message";
    require_absent
      handle
      (Test.Query.test_id "mail-row-2")
      "Archived mailbox retained an inbox message";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-menu");
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-drawer-inbox");
    press handle 2;
    open_card handle 2;
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-delete");
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-menu");
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-drawer-trash");
    require_present
      handle
      (Test.Query.test_id "mail-row-2")
      "Trash mailbox did not expose a deleted message";
    require_absent
      handle
      (Test.Query.test_id "mail-row-1")
      "Trash mailbox retained an archived message")
;;

let test_tabs_are_explicit_and_restore_mail_state () =
  with_handle (fun handle ->
    native_visible_range handle ~first_index:12 ~last_exclusive:20;
    advance_logical_time handle 750_000_010L;
    require_present
      handle
      (Test.Query.test_id "mail-button-21")
      "precondition append did not complete";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-star-21");
    Test.Handle.present handle;
    select_tab handle "chat";
    require (selected_tab handle = "chat") "Chat destination was not selected";
    require_present
      handle
      (Test.Query.visible_text "Chat is outside the scope of this local mail demo.")
      "Chat destination has no explicit placeholder";
    Test.Handle.present handle;
    select_tab handle "spaces";
    require_present
      handle
      (Test.Query.visible_text "Spaces is outside the scope of this local mail demo.")
      "Spaces destination has no explicit placeholder";
    Test.Handle.present handle;
    select_tab handle "meet";
    require_present
      handle
      (Test.Query.visible_text "Meet is outside the scope of this local mail demo.")
      "Meet destination has no explicit placeholder";
    Test.Handle.present handle;
    select_tab handle "mail";
    require (selected_tab handle = "mail") "Mail was not restored";
    require_present
      handle
      (Test.Query.semantics_label "Not starred message from Field Correspondent 21")
      "returning to Mail lost message state";
    require_present
      handle
      (Test.Query.test_id "mail-button-21")
      "returning to Mail lost loaded messages")
;;

let test_rapid_activation_does_not_duplicate_expansion_or_detail () =
  with_handle (fun handle ->
    Test.Handle.present handle;
    press handle 1;
    require
      (List.length (Test.Handle.find_all handle (Test.Query.test_id "mail-card-1")) = 1)
      "rapid activation created duplicate expanded cards";
    require_absent
      handle
      (Test.Query.test_id "mail-detail-page")
      "rapid row activation opened detail";
    open_card handle 1;
    require_present
      handle
      (Test.Query.test_id "mail-detail-page")
      "Open did not open detail";
    require
      (List.length (Test.Handle.find_all handle (Test.Query.test_id "mail-detail-page"))
       = 1)
      "Open created duplicate detail pages")
;;

type collection_props =
  { keys : string array
  ; default_extent : float
  ; overrides : (int * float) list
  }

let collection_props handle =
  let catalog = collection_catalog_node handle in
  let (Av view) = Ui.View.Private.view catalog.widget in
  match view.node with
  | Ui.View.Private.Collection_catalog
      { keys
      ; default_extent
      ; overrides
      ; overscan
      ; expand_duration_ms
      ; collapse_duration_ms
      ; vertical
      ; _
      } ->
    require vertical "mail collection must remain vertical";
    require (overscan = 4) "mail collection changed its overscan policy";
    require
      (expand_duration_ms = 240 && collapse_duration_ms = 190)
      "mail collection lost expansion/collapse timing";
    { keys; default_extent; overrides }
  | _ -> fail "expected a collection catalog"
;;

let test_collection_catalog_and_window_share_exact_ordered_keys () =
  with_handle (fun handle ->
    let check_window () =
      let catalog = collection_props handle in
      let window = collection_window_node handle in
      let (Av view) = Ui.View.Private.view window.widget in
      match view.node with
      | Ui.View.Private.Collection_window { first_index; keys } ->
        require
          (keys = Array.sub catalog.keys first_index (Array.length keys))
          "mail window keys differ from catalog order";
        require
          (Array.length keys = Array.length window.children)
          "mail window does not have one child per key"
      | _ -> fail "expected collection window"
    in
    check_window ();
    native_visible_range handle ~first_index:12 ~last_exclusive:20;
    check_window ();
    advance_logical_time handle 800_000_010L;
    check_window ();
    swipe_action handle 16 1;
    check_window ())
;;

let test_detail_uses_native_scroll_content () =
  with_handle (fun handle ->
    press handle 1;
    open_card handle 1;
    let scroll =
      require_node
        handle
        (Test.Query.kind "Scroll")
        "mail detail has no native scroll container"
    in
    let (Av view) = Ui.View.Private.view scroll.widget in
    require
      (Array.length view.children = 1 && Array.length view.event_bindings = 0)
      "mail detail scroll requires an eager child without an inert event handler")
;;

let test_mail_uses_native_buttons_in_list_preview_and_detail () =
  with_handle (fun handle ->
    let check () =
      List.iter
        (fun kind ->
           require_absent handle (Test.Query.kind kind) "mail retained a Material button")
        [ "Material_text_button"; "Material_icon_button"; "Material_elevated_button" ];
      require_present handle (Test.Query.kind "Button") "mail has no native buttons"
    in
    check ();
    press handle 1;
    check ();
    open_card handle 1;
    check ())
;;

let test_active_surface_tree_and_shared_header_identity () =
  with_handle (fun handle ->
    let surfaces = Test.Handle.find_all handle (Test.Query.kind "Morphing_surface") in
    require (surfaces <> []) "mail did not materialize any surfaces";
    List.iter
      (fun (node : Runtime.Mounted_tree.Snapshot.node) ->
         require (Array.length node.children = 1) "surface retained an inactive branch")
      surfaces;
    require_absent
      handle
      (Test.Query.test_id "mail-outline-1-0")
      "collapsed wire tree contains expanded details";
    let header = require_node handle (Test.Query.test_id "mail-row-1") "missing header" in
    let row = require_node handle (Test.Query.test_id "mail-swipe-1") "missing row" in
    press handle 1;
    let active_header =
      require_node
        handle
        (Test.Query.test_id "mail-active-header-1")
        "missing expanded shared header"
    in
    require
      (header.node_id = active_header.node_id)
      "expansion replaced the shared header";
    let active_row =
      require_node handle (Test.Query.test_id "mail-swipe-1") "missing row"
    in
    require (row.node_id = active_row.node_id) "expansion replaced the row root";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-card-collapse-1");
    require_absent
      handle
      (Test.Query.test_id "mail-outline-1-0")
      "collapse retained expanded details";
    let restored =
      require_node handle (Test.Query.test_id "mail-row-1") "missing header"
    in
    require (header.node_id = restored.node_id) "collapse replaced the shared header")
;;

let test_expansion_accordion_outline_and_collapse () =
  with_handle (fun handle ->
    let initial_props = collection_props handle in
    require
      (initial_props.overrides = [])
      "initial mail list contains a stale extent override";
    press handle 1;
    let expanded_props = collection_props handle in
    require
      (List.length expanded_props.overrides = 1)
      "expansion did not publish exactly one extent override";
    let index, height = List.hd expanded_props.overrides in
    require (index = 0) "expanded message override has the wrong logical index";
    require
      (Float.compare height expanded_props.default_extent > 0)
      "expanded message override is not taller than a compact row";
    List.iter
      (fun test_id ->
         require_present
           handle
           (Test.Query.test_id test_id)
           (Printf.sprintf "outline node %s is missing" test_id))
      [ "mail-outline-1-0"
      ; "mail-outline-1-1"
      ; "mail-outline-1-1-0"
      ; "mail-outline-1-1-1"
      ; "mail-outline-1-1-2"
      ; "mail-outline-1-2"
      ];
    require_present
      handle
      (Test.Query.visible_text "Field notes from the north plot")
      "outline source order starts with the wrong node";
    require_present
      handle
      (Test.Query.visible_text "Printed notes at the next workshop — Mara")
      "muted final outline node is missing";
    press handle 2;
    require_absent
      handle
      (Test.Query.test_id "mail-card-1")
      "accordion left the previous card expanded";
    require_present
      handle
      (Test.Query.test_id "mail-card-2")
      "accordion did not expand the newly activated row";
    let second_props = collection_props handle in
    require
      (List.map fst second_props.overrides = [ 1 ])
      "accordion did not atomically replace the extent override";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-card-collapse-2");
    require_absent
      handle
      (Test.Query.test_id "mail-card-2")
      "expanded header did not collapse the card";
    require
      ((collection_props handle).overrides = [])
      "collapse left an extent override behind")
;;

let test_expanded_nested_actions_are_isolated () =
  with_handle (fun handle ->
    press handle 1;
    let swipe_before =
      require_node
        handle
        (Test.Query.test_id "mail-swipe-1")
        "expanded swipe host missing"
    in
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-star-1");
    require_present handle (Test.Query.test_id "mail-card-1") "star collapsed the card";
    require_present
      handle
      (Test.Query.semantics_label "Not starred message from Mara Vale")
      "expanded star did not update state";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-card-reply-1");
    require_present
      handle
      (Test.Query.test_id "mail-card-notice-1")
      "card Reply did not show its deterministic scope notice";
    require_present handle (Test.Query.test_id "mail-card-1") "Reply collapsed the card";
    require_absent handle (Test.Query.test_id "mail-detail-page") "Reply opened detail";
    swipe_action handle 1 3;
    require_present
      handle
      (Test.Query.test_id "mail-card-1")
      "read swipe collapsed the card";
    let swipe_after =
      require_node handle (Test.Query.test_id "mail-swipe-1") "swipe host disappeared"
    in
    require
      (Runtime.Node_id.equal swipe_before.node_id swipe_after.node_id)
      "expanded state update replaced the keyed swipe host";
    swipe_action handle 1 1;
    require_absent handle (Test.Query.test_id "mail-card-1") "archive retained the card";
    require
      ((collection_props handle).overrides = [])
      "archive left the expanded extent override")
;;

let test_filter_cleanup_and_retained_app_destination () =
  with_handle (fun handle ->
    press handle 2;
    Test.Handle.present handle;
    select_tab handle "chat";
    Test.Handle.present handle;
    select_tab handle "mail";
    require_present
      handle
      (Test.Query.test_id "mail-card-2")
      "returning to Mail did not preserve expansion";
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-menu");
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-drawer-starred");
    require_absent
      handle
      (Test.Query.test_id "mail-card-2")
      "mailbox change retained an expanded card";
    require
      ((collection_props handle).overrides = [])
      "mailbox change retained a stale extent override")
;;

let test_measurement_revision_tracks_sizing_not_star_or_append () =
  with_handle (fun handle ->
    let revision () =
      let node = collection_catalog_node handle in
      let (Av view) = Ui.View.Private.view node.widget in
      match view.node with
      | Ui.View.Private.Collection_catalog { measurement_revision; _ } ->
        measurement_revision
      | _ -> fail "missing collection catalog"
    in
    let initial = revision () in
    Test.Handle.present handle;
    Test.Handle.click handle (Test.Query.test_id "mail-star-2");
    require (revision () = initial) "star appearance invalidated unchanged row sizing";
    native_visible_range handle ~first_index:12 ~last_exclusive:20;
    advance_logical_time handle 750_000_010L;
    require (revision () = initial) "append invalidated existing row extents";
    native_visible_range handle ~first_index:0 ~last_exclusive:8;
    swipe_action handle 1 3;
    require (revision () <> initial) "font-weight change reused stale extents";
    let before_expansion = revision () in
    press handle 1;
    require (revision () <> before_expansion) "expansion reused stale offscreen sizing")
;;

let test_accessibility_type_reflows_subjects_and_invalidates_measurements () =
  with_handle (fun handle ->
    let revision () =
      let node = collection_catalog_node handle in
      let (Av view) = Ui.View.Private.view node.widget in
      match view.node with
      | Ui.View.Private.Collection_catalog { measurement_revision; _ } ->
        measurement_revision
      | _ -> fail "missing collection catalog"
    in
    let initial_revision = revision () in
    let environment = Environment.Private.current (Environment.Private.create ()) in
    Test.Handle.present handle;
    Test.Handle.set_environment handle { environment with text_scale = 2.35 };
    let subject =
      require_node
        handle
        (Test.Query.visible_text "The field notes are ready")
        "accessible Mail subject is missing"
    in
    let (Av view) = Ui.View.Private.view subject.widget in
    (match view.node with
     | Ui.View.Private.Text { line_limit; _ } ->
       require (line_limit = Some 2) "large Mail subjects still truncate after one line"
     | _ -> fail "Mail subject is not text");
    require
      (revision () <> initial_revision)
      "adaptive row structure retained old measurements")
;;

let () =
  test_measurement_revision_tracks_sizing_not_star_or_append ();
  test_painted_ranges_keep_the_paging_handler_until_behavior_changes ();
  test_accessibility_type_reflows_subjects_and_invalidates_measurements ();
  test_mail_app_disables_trace_by_default ();
  test_collection_catalog_and_window_share_exact_ordered_keys ();
  test_initial_inbox_and_semantics ();
  test_detail_uses_native_scroll_content ();
  test_mail_uses_native_buttons_in_list_preview_and_detail ();
  test_initial_virtual_inbox_has_twenty_unique_button_rows ();
  test_star_preserves_keyed_row_identity ();
  test_expand_open_and_platform_pop_preserve_state ();
  test_active_surface_tree_and_shared_header_identity ();
  test_expansion_accordion_outline_and_collapse ();
  test_expanded_nested_actions_are_isolated ();
  test_filter_cleanup_and_retained_app_destination ();
  test_swipe_archive_removes_only_target_and_retains_following_identity ();
  test_swipe_trash_action_removes_target ();
  test_swipe_read_action_updates_in_place_without_navigation ();
  test_stale_split_return_is_ignored ();
  test_archive_delete_and_mark_unread ();
  test_detail_star_attachment_and_reply_notice ();
  test_three_sequential_pages_load_once_and_preserve_overlap_identity ();
  test_sidebar_mailboxes_settings_and_native_column_state ();
  test_drawer_archived_trash_and_inbox_views_are_functional ();
  test_native_tabs_keep_all_four_pages ();
  test_native_navigation_owns_its_layout ();
  test_tabs_are_explicit_and_restore_mail_state ();
  test_rapid_activation_does_not_duplicate_expansion_or_detail ()
;;
