(lang 4)
(app
 (name network)
 (apple_root apple)
 (native_target ocaml/native_embed.exe.o)
 (features network)
 (macos (bundle_identifier org.bonsai-swiftui.example.network) (minimum_version 26.0) (architectures arm64))
 (ios (bundle_identifier org.bonsai-swiftui.example.network) (minimum_version 26.0) (architectures arm64)))
