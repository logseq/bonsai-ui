(lang 4)
(app
 (name sqlite_worker)
 (apple_root apple)
 (native_target ocaml/native_embed.exe.o)
 (features sqlite)
 (macos (bundle_identifier org.bonsai-swiftui.example.sqlite-worker) (minimum_version 26.0) (architectures arm64))
 (ios (bundle_identifier org.bonsai-swiftui.example.sqlite-worker) (minimum_version 26.0) (architectures arm64)))
