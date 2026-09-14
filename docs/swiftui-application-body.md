# Bounded SwiftUI Application Bodies

`App.View.create` and `Driver.View.create` now accept `View.Body.t`. The single
application window supplies finite layout bounds, so its root is a valid owner
of vertical or horizontal scrolling content. The Material Scaffold API and wire node are removed; a viewport becomes
application content through this bounded body.

Ordinary content explicitly declares a static body:

```ocaml
App.View.create ~theme ~body:(Ui.View.Body.static content)
```

A heading and a scrolling region use a bounded body directly:

```ocaml
let body =
  Ui.View.Body.Vertical.create
    [ Ui.View.Body.Vertical.fixed (Ui.View.text "Clock")
    ; Ui.View.Body.Vertical.fill
        (Ui.View.Scroll.vertical ~key:(Ui.Key.string "clock-scroll") sections)
    ]
in
App.View.create ~theme ~body
```

The root constructor has one signature. No ordinary-View overload or implicit
conversion remains. Existing applications, examples and native fixtures now
wrap ordinary content with `Body.static`. Internally the driver extracts the
body's view tree at the framework boundary; this adds no legacy decoder, wrapper
node or alternate runtime. Axis-specific viewport constraints remain intact.

## Persistent content and embedded bodies

Fixed header/footer children reserve space around a scrolling body. Typed
viewport overlays attach floating actions to that region without compensating
for footer height. See [page layout composition](swiftui-page-layout.md).
`Body.with_size ~width ~height` supplies finite positive bounds when embedding a
Body as an ordinary View, such as a Gallery demonstration. Application roots
continue to receive their dimensions from the native window.

NavigationStack root and destination pages also accept Body.t. Their native
navigation container supplies finite constraints, so scrolling pages do not
need fixed-height conversions. Use Body.toolbar for page commands and fixed
children for persistent bottom content; see [native page bars](swiftui-app-bars.md).

## Clock port

The actual Clock example uses this root contract with native SwiftUI ScrollView,
Buttons, section headings and styled containers. Its accessibility container
uses `Children.Contain`; combining the entire scroll region hid its timers and
buttons behind one accessibility element. The standalone native regression
reproduced that issue before the example's grouping was corrected.

OCaml retains manual sampling, exact/approximate time, reactive deadlines,
relative sleep, absolute waits, all four recurring schedules, schedule restart,
frame boundaries and event history. The runtime begins at current wall time
and advances by monotonic elapsed time. Consequently the next absolute five-second
boundary is not necessarily five seconds from runtime creation.

`ClockTests.swift` drives the real C/OCaml runtime with explicit monotonic times,
stages every native frame and acknowledges presentation. It checks each of the
above timer families and confirms before/after-display completion. Its initial
failure was the unsupported Material Scaffold node. `test_clock_window.py`
then uses the real SwiftUI App host and actual OCaml Clock to press controls,
observe native presentation waits and complete a real three-second sleep.

The old Clock Flutter host, adapter and configuration are deleted. A SwiftUI
App entrypoint and ungated native complete-object build replace them. Clock's
macOS bundle uses the shared development build helper. Clock also cross-builds
and links into a signed iOS 18 arm64 Release App; see
[example build evidence](swiftui-example-builds.md). Physical-device execution,
production CLI/SDK packaging and the broader CLI/package rename remain pending.
