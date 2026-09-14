# Clock

Clock demonstrates the application-facing `Bonsai.Cont.Clock` APIs and
presentation-aware frame waits through the SwiftUI host. OCaml owns every time
read, timer state, recurring counter, event history and view construction.

The interface uses a bounded application body containing a heading and native
vertical ScrollView. Sections use keyed view reconciliation, native Buttons,
accessible headings and styled containers. The old Flutter host and Scaffold
are removed.

From the repository root with its OCaml dependencies active:

```sh
python3 tool/build_swiftui_example.py clock
open examples/clock/apple/DerivedData/Build/Products/Debug/BonsaiClock.app
```

The development bundle targets macOS 26+ arm64. The Swift entrypoint also declares
an iOS WindowGroup; physical iOS 18+ packaging and device validation remain part
of the overall backend migration. Simulator is unsupported.

The logical clock starts at wall time and advances from elapsed monotonic time
on eligible foreground frames. Timers are observed when foreground pumping
resumes; no background timer service is implied. `after_display` waits for the
native presentation acknowledgment.

The native runtime test advances explicit monotonic timestamps and checks manual
sampling, deadlines, relative sleep, the next absolute boundary, recurring work,
schedule restart and both presentation waits. The standalone window test presses
native controls and observes a real three-second sleep and presentation waits
through OCaml. Both checks run as part of `make swift-test`.


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
The old OCaml package identifiers and installed SDK publication remain part of
the unfinished repository migration.
