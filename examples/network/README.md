# Secure Network Lab

HTTPS and secure WebSocket behavior run in the OCaml Worker Domain. SwiftUI
renders the application using native Buttons, a revisioned TextField and a
bounded ScrollView. The supported targets are physical iOS 26+ arm64 and
macOS 26+ arm64. Simulator is unsupported.

The HTTPS panel supports requests, cancellation, status and bounded response
previews. The WebSocket panel supports connect, Unicode text echo, disconnect
and a bounded transcript. Its field and Send button are disabled while the
connection is unavailable. Drafts and native field identity survive network
updates. Certificate validation, endpoint policy and transport logic stay in
OCaml. The [embedded Worker](../../docs/swiftui-worker.md) preserves host signal
ownership and exposes no subprocess manager.

## macOS development

With the project opam environment active, run from the repository root:

```sh
python3 tool/build_swiftui_example.py network
open examples/network/apple/DerivedData/Build/Products/Debug/BonsaiNetwork.app
```

The build stages the OCaml complete object with static GMP when required by
Zarith/TLS, then links it into the SwiftUI application. It requires a local
`libgmp.a` discoverable through `pkg-config`.

## Deterministic acceptance

Run from the repository root:

```sh
dune build @runtest native/test/libruntime_fixture.dylib
swift test --scratch-path _build/swift --filter actualNetwork
python3 native/test/test_network_window.py
```

The native window scenario launches the actual OCaml app against local TLS
HTTPS/WSS endpoints. It exercises a successful response, cancellation while a
response body is incomplete, a failed response, Unicode editing and WSS echo,
normal disconnect, field retention and narrow-window layout. It injects only
test endpoints and a fixture trust anchor; it uses production HTTP, WebSocket,
TLS and Worker implementations. The staging test checks close/restart lifecycle.
Existing OCaml transport and policy tests cover malformed traffic, certificate
and hostname rejection, limits and stale generations.

Public endpoints in `network_example.ml` are optional manual smoke-test
conveniences. The production provider smoke command is excluded from CI:

```sh
cd examples/network
dune exec --root=. ocaml/network_smoke_cli.exe
```

## Remaining migration work

The actual OCaml Network program now cross-builds and links into a signed
iOS 26 arm64 SwiftUI Release App. Its final executable has no unresolved GMP
symbols. Physical-device interaction remains unverified; see
[example build evidence](../../docs/swiftui-example-builds.md). Historical Flutter
build sizes, iOS 15 results and signed-device results do not establish SwiftUI
acceptance. Package/CLI/SDK naming and the old
CI consumer/iOS contract checks still require migration. Visual screenshots and
VoiceOver acceptance remain outstanding.


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
