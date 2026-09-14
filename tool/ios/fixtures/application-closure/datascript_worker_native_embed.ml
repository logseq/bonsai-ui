let app =
  Sqlite_worker_example.create_app
    ~service:
      (Sqlite_worker_service.create_with_persistence_probe
         Datascript_worker_probe.persistence_probe)
;;

let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "sqlite_worker")
    app
;;
