# BonsaiSwiftUI

Source repository: [logseq/bonsai-ui](https://github.com/logseq/bonsai-ui).
Report issues in the [project issue tracker](https://github.com/logseq/bonsai-ui/issues).

BonsaiSwiftUI renders OCaml/Bonsai applications with SwiftUI on macOS 26.0+
Apple Silicon and physical iOS/iPadOS 18.0+ arm64 devices. Simulator, Intel Mac,
Catalyst and non-Apple platforms are unsupported.

The SwiftUI replacement is in progress and is not production ready. The runtime,
most view families, native application CLI and eleven example App entrypoints are
implemented. Complete widget/variant acceptance, full Mail visual acceptance,
broader physical-iOS execution and SDK
publication are unfinished. See the [agreed architecture](docs/agent-guide/proposed/architecture/2026-09-11-swiftui-only-apple-backend.md)
and [implementation ledger](docs/swiftui-implementation.md) for the full scope.
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
[collections](docs/swiftui-collections.md), [native List](docs/swiftui-native-list.md),
[navigation](docs/swiftui-navigation-stack.md) and
[host services](docs/swiftui-host-services.md).

## Framework development prerequisites

The current source build uses OCaml 5.1.1, Dune 3.17+, Jane Street v0.17 packages
and ppxlib 0.35.0. Native verification has used Xcode 26.1.1 and Swift 6.2.1 on
macOS 26 arm64. The host generator requires Python 3.9+.

From a configured host opam switch containing the repository dependencies:

```sh
opam exec --switch="$HOST_SWITCH" -- dune build @all @runtest @fmt @install
```

`HOST_SWITCH` is the name or path of that switch; the current local development
switch is `bonsai-ui`. In an already-open shell, refresh its environment with
`eval "$(opam env --switch=bonsai-ui --set-switch)"` after the rename.
The replacement iOS compiler
and dependency closure are also installed in the global `bonsai-swiftui-ios`
switch and verified by an independent App build. Public SDK publication remains
unfinished. See the
[iOS toolchain evidence](docs/swiftui-ios-toolchain.md). An old iOS 15 SDK does
not satisfy the iOS 18 object checks.

## Install and use from another repository

Applications consume the opam packages `bonsai_swiftui` (OCaml libraries) and
`bonsai_swiftui_tool` (the `bonsai-swiftui` CLI and native resources). They do not
need a framework checkout, `BONSAI_SWIFTUI_SOURCE_ROOT`, or a custom `OCAMLPATH`.
Opam downloads and compiles the release sources as part of installation.

With an OCaml 5.1.1 switch and the release's opam repository configured:

```sh
opam install bonsai_swiftui bonsai_swiftui_tool
eval "$(opam env)"

mkdir journal
cd journal
bonsai-swiftui init --name journal \
  --macos-bundle-identifier org.example.journal \
  --ios-bundle-identifier org.example.journal.ios
bonsai-swiftui build macos --profile debug
bonsai-swiftui run macos --profile debug
```

Install `bonsai_swiftui_test` when the application needs headless UI tests.
The starter owns its OCaml and Swift sources; the CLI manages the generated
Xcode host. Swift/C resources are installed under the opam prefix, and the CLI
finds them automatically.

The packages are not yet published to a public opam repository. A maintainer can
produce a consumable archive and local opam repository with
`python3 tool/package_opam_release.py _build/opam-release`. See
[opam installation and release packaging](docs/opam-installation.md) for adding
that repository and publishing artifacts. For physical iOS, install the matching
SDK once, then build from the application directory:

```sh
bonsai-swiftui toolchain install iphoneos
bonsai-swiftui build ios --profile release --no-codesign
```

The local SDK installation and independent App build are verified. Public SDK
publication and physical-device execution remain separate.

See the [CLI guide](docs/swiftui-cli.md) for configuration, ownership, signing,
device launch and cleanup. Framework contributors using an uninstalled checkout
can use the [source development environment](docs/opam-installation.md#framework-development).

## Examples and Mail

Counter, Clock, Todo, Text Input, Navigation, Host Navigation, Host Effects,
Network, SQLite Worker, Mail and [Note](examples/note/README.md) have standalone Swift App entrypoints. The
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

`make ci-ios-device EXAMPLE=mail IOS_DEVICE_ID=... IOS_DEVELOPMENT_TEAM=...`
preflights and launches the selected example on a physical device. This launch
target is separate from XCTest UI acceptance. The framework SDK must be rebuilt
and published from the final pushed source before distribution is complete.

## License

MIT

Application-owned platform identities, entitlement inputs and locked remote Swift
packages use [schema 4](docs/swiftui-cli.md#application-identities-entitlements-and-swift-packages).
