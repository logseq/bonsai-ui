let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "sqlite_worker")
    Sqlite_worker_example.app
;;
