(lang 3)
(app
 (name network)
 (apple_root apple)
 (bundle_identifier org.bonsai-swiftui.example.network)
 (native_target ocaml/native_embed.exe.o)
 (features network)
 (macos (minimum_version 26.0) (architectures arm64))
 (ios (minimum_version 18.0) (architectures arm64)))
