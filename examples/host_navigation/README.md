# Host Navigation

OCaml owns the clipboard result and Settings path. SwiftUI renders native
Buttons and NavigationStack; Close and the system Back control request an
OCaml state update. The home page remains mounted while Settings is open and
retains its clipboard result when returning.

The Settings page contains the original OCaml-owned stack and an inline
information section composed from native text, a divider and a column. The old
Material alert was an inline child with no actions or presentation state. This
example does not establish modal sheet or dialog acceptance; those capabilities
remain part of the framework migration.

Build and run from the repository root with the project opam environment active:

```sh
python3 tool/build_swiftui_example.py host_navigation
open examples/host_navigation/apple/DerivedData/Build/Products/Debug/BonsaiHostNavigation.app
```

This builds an ad-hoc signed macOS 26+ arm64 development application against the
actual OCaml complete object. The Swift framework and App entrypoint typecheck
against physical iOS 26 arm64. Native iPhoneOS packaging, device interaction and
visual acceptance remain outstanding. Simulator is unsupported. The previous
Flutter host and configuration have been removed.

Clipboard text uses the native host service and its 1 MiB UTF-8 transfer limit.
The example displays at most 4096 bytes without splitting a code point and uses
an eight-line preview. Empty text is accepted; native failures display
`Clipboard request failed`. A delayed read may complete while Settings is open
without changing navigation. Returning to Home reveals the retained result.

Run the production example's native window test:

```sh
python3 native/test/test_host_navigation_window.py
```

This presses Read, Open settings, Close settings and the system toolbar Back
button at 640- and 360-point widths, verifies retained Unicode clipboard text
and exercises an oversized native read. It uses an isolated named NSPasteboard
and releases it afterward; the user's general clipboard is untouched.

`make swift-test` also verifies delayed completion while navigating, root
identity retention, hidden-page input rejection, speculative Back input fencing,
empty and maximum-size Unicode transfers, oversized rejection and restart.
See [navigation](../../docs/swiftui-navigation-stack.md) and
[host services](../../docs/swiftui-host-services.md) for the shared contracts.


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
