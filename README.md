# BonsaiSwiftUI

BonsaiSwiftUI renders OCaml/Bonsai applications with SwiftUI on macOS 26.0+
Apple Silicon and physical iOS/iPadOS 18.0+ arm64 devices. Simulator, Intel Mac,
Catalyst and non-Apple platforms are unsupported.

The SwiftUI replacement is in progress and is not production ready. The runtime,
most view families, native application CLI and eleven example App entrypoints are
implemented. Complete widget/variant acceptance, full Mail visual acceptance,
broader physical-iOS execution and SDK
publication are unfinished. See the [agreed architecture](docs/agent-guide/proposed/architecture/2026-09-11-swiftui-only-apple-backend.md)
and [implementation ledger](docs/swiftui-implementation.md) for the full scope.
The Flutter/Dart source tree and host packages have been removed.
The OCaml packages are `bonsai_swiftui`, `bonsai_swiftui_test` and
`bonsai_swiftui_tool`; examples and application modules use the same namespace.
The virtual spec library exposes `Bonsai_swiftui_spec`; its comment/reference
rename was explicitly authorized. No compatibility package or command alias is
provided. Published SDK snapshots have not yet been regenerated. Current
[Mail macOS screenshots](docs/screenshots/swiftui-mail/committed-source/README.md)
include mouse-driven swipe actions and the resulting archived message.

## Architecture

OCaml owns application data, Bonsai computations, view identity, navigation,
event handlers, asynchronous work and incremental binary frames. Swift validates
and presents frames through a native view hierarchy, owns native resources and
editing sessions, and sends typed interaction intents back to OCaml. Application
reducers remain in OCaml, including in the Mail example.

The C boundary is in `native/`, and the Swift package exposes `BonsaiSwiftUI`.
Applications own their OCaml sources and `swift/App.swift`; the CLI generates
Xcode projects with separate macOS and physical-iOS targets. Narrow UIKit/AppKit
adapters supply capabilities such as revisioned native text editing.

See [application bodies](docs/swiftui-application-body.md),
[layout](docs/swiftui-layout.md), [text input](docs/swiftui-text-input.md),
[collections](docs/swiftui-collections.md),
[navigation](docs/swiftui-navigation-stack.md) and
[host services](docs/swiftui-host-services.md).

## Development prerequisites

The current source build uses OCaml 5.1.1, Dune 3.17+, Jane Street v0.17 packages
and ppxlib 0.35.0. Native verification has used Xcode 26.1.1 and Swift 6.2.1 on
macOS 26 arm64. The host generator requires Python 3.9+.

From a configured host opam switch containing the repository dependencies:

```sh
opam exec --switch="$HOST_SWITCH" -- dune build @all @runtest @fmt @install
```

`HOST_SWITCH` is the name or path of that switch. The replacement iOS compiler
and dependency closure have been built in an isolated worktree-local switch;
publication and installation of the new SDK remain unfinished. See the
[iOS toolchain evidence](docs/swiftui-ios-toolchain.md). An old iOS 15 SDK does
not satisfy the iOS 18 object checks.

## Native application CLI

The public executable is `bonsai-swiftui`; a development build is available at
`_build/default/bonsai_swiftui_tool/bin/main.exe`. To use that executable for an
external application, expose this checkout and its built OCaml libraries from
the repository root:

```sh
export BONSAI_SWIFTUI_SOURCE_ROOT="$PWD"
export OCAMLPATH="$PWD/_build/install/default/lib${OCAMLPATH:+:$OCAMLPATH}"
export BONSAI_SWIFTUI_CLI="$PWD/_build/default/bonsai_swiftui_tool/bin/main.exe"
```

With the same configured opam environment, create an empty application directory
and run:

```sh
"$BONSAI_SWIFTUI_CLI" init --name journal --bundle-identifier org.example.journal
"$BONSAI_SWIFTUI_CLI" build macos --profile debug
"$BONSAI_SWIFTUI_CLI" run macos --profile debug
"$BONSAI_SWIFTUI_CLI" sync-host --check
```

The starter uses a real OCaml counter and a Swift `BonsaiApplicationView`.
Configuration lives in `bonsai-swiftui.sexp`. Debug uses Dune `dev`; Profile and
Release use Dune `release`, with separate native and Xcode outputs. Existing
application sources remain unchanged by host synchronization and adoption.

See the [CLI guide](docs/swiftui-cli.md) for configuration, source ownership,
explicit iOS complete-object builds, signing, device launch, `exec` and cleanup.
The CLI has no Flutter initialization, Dart adapter or pubspec injection path.
Installed package and SDK publication is still separate work.

## Examples and Mail

Counter, Clock, Todo, Text Input, Navigation, Host Navigation, Host Effects,
Network, SQLite Worker and Mail have standalone Swift App entrypoints. The
[build matrix](docs/swiftui-example-builds.md) records macOS Debug and signed
physical-iOS Release evidence and the source checkpoint for those builds.
Gallery also builds native macOS and physical-iOS hosts. Its full-tree macOS
staging/dispatch test passes, and UIKit KeyboardListener is implemented; complete
native page and physical-keyboard acceptance remain outstanding. See [Gallery acceptance](docs/swiftui-gallery.md).

Build Mail from this repository using the configured host switch:

```sh
opam exec --switch="$HOST_SWITCH" -- python3 tool/build_swiftui_example.py mail
open examples/mail/apple/DerivedData/Build/Products/Debug/BonsaiMail.app
```

The helper builds Mail's actual OCaml complete object and links it into the
SwiftUI App. It also supports Profile/Release and physical-iOS builds using an
explicit iOS 18 complete object. See [Xcode host commands](docs/swiftui-xcode-host.md).
The examples' generated Xcode hosts can already be built through this helper;
all eleven examples own native CLI configurations and renamed OCaml packages.

Mail's native window tests exercise message expansion, archiving and mailbox
selection through OCaml. The [capture evidence](docs/screenshots/swiftui-mail/README.md)
contains four complete macOS window captures and an iPhone Inbox capture.
Mail's hosted runtime XCTest also passes on iPhone 13. Remaining physical UI
scenarios and final published-source capture provenance are still required.
Mail now requests Light to match its fixed palette; current physical-iOS
appearance and fresh captures remain unverified.

## Verification

After the repository build above, run these gates sequentially in the configured
host environment:

```sh
python3 tool/run_swift_tests.py
python3 tool/test_swiftui_cli.py
python3 tool/test_swiftui_example_cli.py
python3 tool/test_swiftui_xcode_host.py
python3 native/test/test_mail_window.py
spec-dev-tool check --all
```

The Swift suite checks native runtime/transport/rendering behavior. The CLI
suite builds an independent generated application in all three configurations,
launches its SwiftUI window and verifies a button updates real OCaml state.
The Xcode suite builds the actual Mail host and executes its macOS XCTest
scenario. A signed iOS build or `build-for-testing` result does not establish
physical-device execution.

`make ci-swift` runs the Swift/native gates, Xcode host tests, window tests,
input fixture verification and generated-host checks. `make ci-macos` and
`make ci-ios` build all eleven examples in Debug, Profile and Release; iOS
builds are unsigned and target physical devices. These complete matrix targets
have not been fully revalidated after package renaming. Window captures require
an unlocked Mac; physical-device interaction remains a separate acceptance gate.
The obsolete Dart/Flutter Make targets have been removed.

`make ci-ios-device EXAMPLE=mail IOS_DEVICE_ID=... IOS_DEVELOPMENT_TEAM=...`
preflights and launches the selected example on a physical device. This launch
target is separate from XCTest UI acceptance. The framework SDK must be rebuilt
and published from the final pushed source before distribution is complete.

## License

MIT
