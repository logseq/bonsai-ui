(lang 3)
(app
 (name sqlite_worker)
 (apple_root apple)
 (bundle_identifier org.bonsai-swiftui.example.sqlite-worker)
 (native_target ocaml/native_embed.exe.o)
 (features sqlite)
 (macos (minimum_version 26.0) (architectures arm64))
 (ios (minimum_version 18.0) (architectures arm64)))
