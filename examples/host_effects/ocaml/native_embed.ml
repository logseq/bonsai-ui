let () =
  Native_backend.embed
    ~name:(Bonsai_swiftui_spec.Id.Application.Entrypoint_name.of_string "host_effects")
    Host_effects.app
;;
