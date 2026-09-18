# Navigation

The OCaml component owns the navigation path and button handlers. The root
opens a detail destination; the native SwiftUI Back control or the explicit
Close button returns to the root. `swift/App.swift` supplies the application
scene through `BonsaiApplicationView`.

Build the macOS 26+ arm64 application from the repository root:

```sh
python3 tool/build_swiftui_example.py navigation
open examples/navigation/apple/DerivedData/Build/Products/Debug/BonsaiNavigation.app
```

The development helper links the actual OCaml complete object and local Swift
module and verifies the ad-hoc signature. The Swift entrypoint also defines
an iOS scene; physical iOS 26+ packaging and device validation remain unfinished.
Simulator is unsupported.

`make swift-test` includes a separate SwiftUI App test that opens the actual
OCaml example, activates the system Back toolbar control and verifies the
return to the root. See [Native Navigation Stack](../../docs/swiftui-navigation-stack.md)
for the path contract and remaining navigation migration work.


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
