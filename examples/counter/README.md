# Counter

Counter keeps its state, view and increment handler in `ocaml/counter.ml`.
`swift/App.swift` hosts that application in `BonsaiApplicationView` using
SwiftUI. Its native Button sends events to OCaml; the Swift host owns no
counter state.

Build and open the macOS 26+ arm64 application from the repository root:

```sh
python3 tool/build_swiftui_example.py counter
open examples/counter/apple/DerivedData/Build/Products/Debug/BonsaiCounter.app
```

The helper generates an Xcode project and links the example's actual OCaml
complete object with the local Swift package into an ad-hoc-signed application. It uses the current
Dune workspace and installed dependencies, without publishing or pinning
the unfinished framework SDK.

The project also defines a physical-iOS target. iOS 26+ cross-compilation,
provisioning and device validation remain in progress; an iOS build requires
an explicit verified device complete object and a development team. Simulator is unsupported. See the repository's
`docs/swiftui-implementation.md` for the remaining migration work.


## Native CLI consumer

This example owns `bonsai-swiftui.sexp`, its OCaml sources and `swift/`.
Prepare the source-checkout environment described in the [root README](../../README.md),
then run from this example directory:

```sh
"$BONSAI_SWIFTUI_CLI" build macos --profile debug
"$BONSAI_SWIFTUI_CLI" run macos --profile debug
"$BONSAI_SWIFTUI_CLI" sync-host --check
```

The CLI builds this example's `ocaml/native_embed.exe.o` as an independent Dune
project and generates the `apple/` Xcode host. Swift and OCaml sources remain
application-owned. See the [CLI guide](../../docs/swiftui-cli.md) for optimized
configurations, signing and physical-iOS builds with an explicit iOS 26 object.
The old OCaml package identifiers and installed SDK publication remain part of
the unfinished repository migration.
