# Text Input

This standalone SwiftUI application hosts the OCaml `View.text_editor` through
`BonsaiApplicationView`. The canonical document and revision acceptance logic
live in `ocaml/text_input_example.ml`. The native editor uses NSTextView on macOS
and UITextView on physical iOS, with UTF-16 selection and marked-text ranges.

Build and open the macOS 26+ arm64 application from the repository root:

```sh
python3 tool/build_swiftui_example.py text_input
open examples/text_input/apple/DerivedData/Build/Products/Debug/BonsaiTextInput.app
```

The build links the example's actual OCaml complete object and verifies the
ad-hoc bundle signature. The SwiftUI source also targets physical arm64 iOS 18+;
the signed Release bundle and hosted UIKit tests run on a physical iPhone.
Simulator, Catalyst and Intel macOS are unsupported.

`make swift-test` mounts the actual example in an NSHostingView and drives its
NSTextView input client. Three consecutive composing edits are coalesced before
one C/OCaml pump. OCaml returns the latest accepted local revision while the
native controller and marked text remain intact. Input before the first
presentation is rejected and rolled back. Additional tests cover stale local
versions, Unicode, byte limits, queue barriers, read-only state and teardown.

`apple-tests/TextInputRuntimeTests.swift` mounts this application on physical
iOS and verifies Unicode insertion, marked text across runtime updates, commit,
UTF-16 selection replacement, focus resignation and unmount/remount. It attaches
the hosted window's composition and committed states. System IME candidate-window
selection and hardware-keyboard behavior remain separate acceptance checks.


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
configurations, signing and physical-iOS builds with an explicit iOS 18 object.
Source package and spec-module identifiers now use the SwiftUI names. Installed
SDK publication remains part of the unfinished repository migration.
