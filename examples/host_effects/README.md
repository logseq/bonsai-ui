# Host effects example

OCaml owns the asynchronous request flow and rendered result. SwiftUI presents
native Buttons and a bounded scrolling status panel. The native host reads and
writes text through NSPasteboard on macOS and UIPasteboard on iOS, returning a
typed response through the actual OCaml runtime. `Read platform information`
requests the current native OS name, OS-version display string and Foundation
locale identifier; its result is decoded and rendered by the OCaml application.
`Rename window` changes the owned NSWindow title on macOS or scene title on iOS.
`Resize window` requests a 760-by-560 content size on macOS; iOS returns an
explicit unsupported-operation error, which OCaml renders in the status panel.
The URL field preserves native editing revisions in OCaml. Open URL or Go
requests the system handler for the entered URL and displays success or failure.
Opening a URL requires an explicit action; editing the field does not launch it.

`Show notification` displays “Changes saved” with an Undo action. Its result
appears in the separate notification status. `Show timed notification` displays
“Refresh complete” for one second of active presentation. `Cancel notification`
cancels the latest outstanding request, including one still waiting in the
queue. The same native window test covers action, dismissal, cancellation and
timeout at normal and 360-point widths. See the
[notification contract](../../docs/swiftui-notices.md).

`Choose action` opens a scrollable SwiftUI chooser with Open item, Duplicate item
and a disabled action. Selecting Duplicate item updates the OCaml status to
`Action: duplicate`; Cancel records dismissal. See the
[action menu contract](../../docs/swiftui-host-menus.md).

The four `Haptic` buttons submit impact or selection requests and display the
typed OCaml result. iOS uses the requested weight/selection generator; macOS
uses generic feedback. Successful submission does not confirm physical output.
See the [haptic contract](../../docs/swiftui-haptics.md).

Build and run the local macOS development application from the repository root:

```sh
python3 tool/build_swiftui_example.py host_effects
open examples/host_effects/apple/DerivedData/Build/Products/Debug/BonsaiHostEffects.app
```

The supported targets are macOS 26+ arm64 and physical iOS 26+ arm64. This helper
builds an ad-hoc signed macOS application. The example's native program and SwiftUI
entrypoint have also built as a signed iOS Release App; see
[example build evidence](../../docs/swiftui-example-builds.md). Device clipboard
and window-service behavior remain unverified. Simulator is unsupported.

Requests execute only after their frame is acknowledged as presented and the
application is active and visible. Text transfers are limited to 1 MiB of UTF-8;
the displayed read preview is limited to 4096 bytes without splitting a code
point. This prevents a valid maximum-size clipboard response from producing an
oversized UI property. Write places `Written by Bonsai SwiftUI` on the clipboard.

Run the native window scenario:

```sh
python3 native/test/test_host_effects_window.py
```

This mounts the production OCaml application and presses its native controls.
It checks Unicode clipboard reads/writes, native platform information, the
resulting OCaml status and a 360-point window. It also verifies the requested
Unicode title, title retention across an unrelated response, and the native
content size after a resize request. The URL scenario edits the real field and
verifies delivery to a registered local native App, deferred dispatch while
inactive, an invalid-URL response and no launch after closure. The receiver has
a unique scheme, is unregistered after the test, and contacts no public website. It injects a named native pasteboard and releases it afterward, leaving
the user's general clipboard untouched. `make swift-test` additionally covers
atomic command validation, response encoding, presentation and activation gates,
cancellation, saturation, delayed replies, close/restart and transfer boundaries.

See [SwiftUI host services](../../docs/swiftui-host-services.md) for the transport
contract, lifecycle rules and remaining service migration scope.
The [window-service contract](../../docs/swiftui-window-services.md) describes
ownership, declarative-title priority, restoration and platform differences.


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

See the [native URL service](../../docs/swiftui-url-service.md) for cancellation semantics and measured evidence.

The application bridge action reads the native bundle identifier through an
application-owned versioned byte codec. The Swift host also observes time-zone
change notifications; OCaml validates the event and updates the separate
application-event label. See [application bridge](../../docs/application-platform.md).

Civil picker services expose Choose date, Choose date range and Choose time.
Each opens a SwiftUI sheet with explicit Save and Cancel actions. Changes are
committed to the OCaml status only on Save. See
[the domain and lifecycle contract](../../docs/swiftui-host-pickers.md).

The reactive `Environment:` status displays App.Context.environment's platform,
window dimensions, keyboard bottom inset and physical safe-area values. The
physical-iOS UI scenario in `apple-ui-tests/ios/EnvironmentUITests.swift` verifies
software-keyboard show/hide, stable viewport dimensions and restart. It requires
a connected iOS device and has not yet been executed for this checkpoint.


## Hidden-window Quit

The macOS application delegate starts a terminal cooperative shutdown through its
connected application sender. The example sends `[1, 12]`; OCaml returns an
application request `[1, 13]`, and Swift supplies the matching final reply. The
delegate releases `terminateLater` only after OCaml accepts the reply and the
runtime closes. Hiding or minimizing the window does not require reactivation.
The four-second deadline also closes the runtime on timeout; cancelling this
exchange cannot resume the same runtime. iOS does not install a macOS Quit
handler or acquire background execution time.
