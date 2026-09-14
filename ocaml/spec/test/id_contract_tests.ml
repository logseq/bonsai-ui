(** Behavioral contract for the production private ID implementation. *)

module ID = Bonsai_swiftui_spec.Id

let require condition message = if not condition then failwith message

let require_int64 module_name expected actual =
  require
    (Int64.equal expected actual)
    (Printf.sprintf "%s representation changed" module_name)
;;

let require_int module_name expected actual =
  require (expected = actual) (Printf.sprintf "%s representation changed" module_name)
;;

let require_string module_name expected actual =
  require
    (String.equal expected actual)
    (Printf.sprintf "%s representation changed" module_name)
;;

let () =
  require_int64
    "runtime handle"
    1L
    (ID.Runtime.Handle.of_int64 1L |> ID.Runtime.Handle.to_int64);
  require_int64
    "runtime epoch"
    2L
    (ID.Runtime.Epoch.of_int64 2L |> ID.Runtime.Epoch.to_int64);
  require_int64
    "presentation ID"
    3L
    (ID.Runtime.Presentation_id.of_int64 3L |> ID.Runtime.Presentation_id.to_int64);
  require_int64
    "renderer revision"
    4L
    (ID.Runtime.Renderer_revision.of_int64 4L |> ID.Runtime.Renderer_revision.to_int64);
  require_int64
    "event sequence"
    5L
    (ID.Runtime.Event_sequence.of_int64 5L |> ID.Runtime.Event_sequence.to_int64);
  require
    ID.Runtime.Renderer_revision.(equal (succ zero) one)
    "private int64 IDs do not preserve successor semantics";
  require
    ID.Runtime.Renderer_revision.(equal (pred one) zero)
    "private int64 IDs do not preserve predecessor semantics";
  require_int64
    "private int64 maximum"
    Int64.max_int
    ID.Runtime.Renderer_revision.(to_int64 max_value)
;;

let () =
  require_int64
    "worker generation"
    1L
    (ID.Worker.Generation.of_int64 1L |> ID.Worker.Generation.to_int64);
  require_int64
    "worker request ID"
    2L
    (ID.Worker.Request_id.of_int64 2L |> ID.Worker.Request_id.to_int64);
  require_int64
    "worker push sequence"
    3L
    (ID.Worker.Push_sequence.of_int64 3L |> ID.Worker.Push_sequence.to_int64);
  require_int
    "worker push topic"
    4
    (ID.Worker.Push_topic.of_int 4 |> ID.Worker.Push_topic.to_int);
  let domain_id = Domain.self () in
  require
    (ID.Worker.Domain_id.of_domain_id domain_id
     |> ID.Worker.Domain_id.to_domain_id
     = domain_id)
    "worker Domain ID representation changed"
;;

let () =
  let application_keys : ID.Ui.application_key list =
    [ ID.Ui.Application_key.string "item"; ID.Ui.Application_key.int64 2L ]
  in
  require (List.length application_keys = 2) "application key constructors changed";
  require_string
    "test ID"
    "root"
    (ID.Ui.Test_id.of_string "root" |> ID.Ui.Test_id.to_string);
  require_int64 "node ID" 1L (ID.Ui.Node_id.of_int64 1L |> ID.Ui.Node_id.to_int64);
  require_int64 "handler ID" 2L (ID.Ui.Handler_id.of_int64 2L |> ID.Ui.Handler_id.to_int64);
  require_int64
    "animation ID"
    3L
    (ID.Ui.Animation_id.of_int64 3L |> ID.Ui.Animation_id.to_int64)
;;

let () =
  require_int64
    "text session ID"
    1L
    (ID.Text_input.Session_id.of_int64 1L |> ID.Text_input.Session_id.to_int64);
  require_int64
    "text document revision"
    2L
    (ID.Text_input.Document_revision.of_int64 2L
     |> ID.Text_input.Document_revision.to_int64);
  require_int64
    "text local revision"
    3L
    (ID.Text_input.Local_revision.of_int64 3L |> ID.Text_input.Local_revision.to_int64)
;;

let () =
  require_string
    "page key"
    "home"
    (ID.Navigation.Page_key.of_string "home" |> ID.Navigation.Page_key.to_string);
  require_string
    "restoration scope"
    "app"
    (ID.Navigation.Restoration_scope_id.of_string "app"
     |> ID.Navigation.Restoration_scope_id.to_string);
  require_string
    "restoration ID"
    "home-page"
    (ID.Navigation.Restoration_id.of_string "home-page"
     |> ID.Navigation.Restoration_id.to_string)
;;

let () =
  require_int64
    "pointer ID"
    1L
    (ID.Input.Pointer_id.of_int64 1L |> ID.Input.Pointer_id.to_int64);
  require_int64
    "logical key"
    2L
    (ID.Input.Logical_key.of_int64 2L |> ID.Input.Logical_key.to_int64);
  require_int64
    "physical key"
    3L
    (ID.Input.Physical_key.of_int64 3L |> ID.Input.Physical_key.to_int64);
  require_int64
    "semantics action"
    4L
    (ID.Input.Semantics_action_id.of_int64 4L |> ID.Input.Semantics_action_id.to_int64)
;;

let () =
  require_int64
    "host request ID"
    1L
    (ID.Host.Request_id.of_int64 1L |> ID.Host.Request_id.to_int64);
  require_int64
    "host operation ID"
    2L
    (ID.Host.Operation_id.of_int64 2L |> ID.Host.Operation_id.to_int64);
  require_string
    "native menu item ID"
    "open"
    (ID.Host.Native_menu_item_id.of_string "open" |> ID.Host.Native_menu_item_id.to_string)
;;

let () =
  require_int
    "native widget kind ID"
    1
    (ID.Native_widget.Kind_id.of_int 1 |> ID.Native_widget.Kind_id.to_int);
  require_int
    "native widget event ID"
    2
    (ID.Native_widget.Event_id.of_int 2 |> ID.Native_widget.Event_id.to_int)
;;

let () =
  require_string
    "application entrypoint"
    "counter"
    (ID.Application.Entrypoint_name.of_string "counter"
     |> ID.Application.Entrypoint_name.to_string)
;;

let () =
  require_int
    "frame kind"
    1
    (ID.Protocol.Frame_kind.of_int 1 |> ID.Protocol.Frame_kind.to_int);
  require_int
    "operation"
    2
    (ID.Protocol.Operation.of_int 2 |> ID.Protocol.Operation.to_int);
  require_int
    "node kind"
    3
    (ID.Protocol.Node_kind.of_int 3 |> ID.Protocol.Node_kind.to_int);
  require_int
    "event tag"
    4
    (ID.Protocol.Event_tag.of_int 4 |> ID.Protocol.Event_tag.to_int);
  require_int
    "host request kind"
    5
    (ID.Protocol.Host_request_kind.of_int 5 |> ID.Protocol.Host_request_kind.to_int);
  require_int
    "runtime error"
    6
    (ID.Protocol.Runtime_error.of_int 6 |> ID.Protocol.Runtime_error.to_int);
  require_int "property" 7 (ID.Protocol.Property.of_int 7 |> ID.Protocol.Property.to_int)
;;

let () =
  require_int
    "FFI error code none"
    0
    (ID.Ffi.Error_code.of_int 0 |> ID.Ffi.Error_code.to_int);
  require_int
    "FFI error code scheduler"
    15
    (ID.Ffi.Error_code.of_int 15 |> ID.Ffi.Error_code.to_int)
;;
