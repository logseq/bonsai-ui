module ID = Bonsai_swiftui_spec.Id
module Ui = Bonsai_swiftui

let require condition message = if not condition then failwith message

let application_theme =
  Ui.Theme.create
    ~tint:(Ui.Style.Color.rgb ~red:103 ~green:80 ~blue:164)
    ~font_family:"Inter"
    ()
;;

let component context _graph =
  let environment = Ui.App.Context.environment context in
  let application_platform = Ui.App.Context.application_platform context in
  Ui.Application_platform.on_event application_platform (fun _payload ->
    Ui.Effect.return ());
  ignore
    (Ui.Application_platform.request
       application_platform
       (Bytes.of_string "compile-surface"));
  Bonsai.Cont.map environment ~f:(fun environment ->
    Ui.App.View.create
      ~theme:application_theme
      ~body:
        (Ui.View.Body.static
           (Ui.View.text
              (Printf.sprintf
                 "%.0fx%.0f"
                 environment.Ui.Environment.viewport_width
                 environment.viewport_height))))
;;

let worker_service =
  Ui.Worker.Service.create
    ~push_topic_count:1
    ~concurrency:Ui.Worker.Service.Serial
    ~init:(fun _session () -> Ok ())
    ~handle:(fun _request () request -> Ok request)
    ~shutdown:(fun () -> ())
    ()
;;

let worker_component client _context _graph =
  ignore (Ui.Worker.runtime_epoch client);
  ignore (Ui.Worker.worker_generation client);
  ignore (Ui.Worker.send client "compile-surface");
  Ui.Worker.on_event client (fun _ -> Ui.Effect.return ());
  Bonsai.Cont.return
    (Ui.App.View.create
       ~theme:application_theme
       ~body:(Ui.View.Body.static (Ui.View.text "worker public API")))
;;

let viewport_handler = Ui.Event.Handler.create (fun _ -> ())

let (_ : Ui.Viewport.Vertical.t) =
  Ui.View.Scroll.vertical ~on_scroll:viewport_handler (Ui.View.text "Public row")
;;

let (_ : Ui.Viewport.Vertical.t) =
  let keys =
    List.map Bonsai_swiftui_ui.Key.string [ "public-fixed-row"; "public-varied-row" ]
  in
  let catalog =
    Ui.View.Collection.Catalog.create
      ~keys
      ~default_extent:48.
      ~overrides:[ { Ui.View.Collection.index = 1; extent = 96. } ]
      ()
  in
  Ui.View.Collection.vertical
    ~catalog
    ~first_index:0
    ~items:
      (List.map (fun key -> Ui.View.Keyed.create ~key (Ui.View.text "Public row")) keys)
    ~on_visible_range:viewport_handler
    ()
;;

let (_ : Ui.Body.t) =
  Ui.Body.Vertical.create
    [ Ui.Body.Vertical.fixed (Ui.View.text "Search")
    ; Ui.Body.Vertical.fill
        (Ui.View.Scroll.vertical ~on_scroll:viewport_handler (Ui.View.empty ()))
    ]
;;

let () =
  let cancellation = Ui.Application_platform.Cancellation.create () in
  Ui.Application_platform.Cancellation.cancel cancellation;
  require
    (Ui.Application_platform.maximum_payload_bytes = 1_048_576)
    "unexpected public application payload limit";
  let (_ : Ui.Application_platform.error) = Ui.Application_platform.Runtime_replaced in
  let (_ : Ui.Host_effect.native_menu_item) =
    { item_id = ID.Host.Native_menu_item_id.of_string "copy"
    ; label = "Copy"
    ; enabled = true
    }
  in
  let (_ : Ui.Host_effect.haptic_kind) = Ui.Host_effect.Haptic_selection in
  let (_ : Ui.Host_effect.notice_close_reason) = Ui.Host_effect.Action in
  ignore Ui.Host_effect.show_notice;
  let app = Ui.App.create ~name:"public-api-test" component in
  let worker_app =
    Ui.App.create_with_worker
      ~name:"public-worker-api-test"
      ~decode_config:(fun payload ->
        if Bytes.length payload = 0 then Ok () else Error "unexpected payload")
      ~service:worker_service
      worker_component
  in
  Ui.Entrypoint.For_testing.clear ();
  Ui.Entrypoint.register
    ~name:(ID.Application.Entrypoint_name.of_string "public-api-test")
    app;
  Ui.Entrypoint.register
    ~name:(ID.Application.Entrypoint_name.of_string "public-worker-api-test")
    worker_app;
  require
    (Option.is_some
       (Ui.Entrypoint.For_testing.find
          (ID.Application.Entrypoint_name.of_string "public-api-test")))
    "registered public App was not discoverable";
  require
    (Option.is_some
       (Ui.Entrypoint.For_testing.find
          (ID.Application.Entrypoint_name.of_string "public-worker-api-test")))
    "registered public worker App was not discoverable";
  ignore (Ui.Effect.return ());
  ignore Ui.View.control_size
;;
