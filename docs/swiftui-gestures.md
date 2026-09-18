# SwiftUI gesture migration

Generic Gesture now stages and renders through native SwiftUI recognizer
representables on macOS 26 and iOS 26. The actual OCaml window regression passes
single/double click, long press, primary pointer transitions and lifecycle
scenarios on macOS. Physical iOS interaction, multiple simultaneous contacts,
scroll-view competition and the combined Gallery remain unfinished.

## Event contract

Tap and Double_tap carry four finite Double coordinates (local x/y and root
window x/y, in points) and a pointer kind. Negative coordinates remain legal:
contacts and recognizers may report positions outside their initial bounds.
The supported kinds are mouse, touch, stylus, inverted stylus, trackpad and
unknown. Long_press uses the existing Unit payload and has no synthetic location.
`NativeTap`, the new `NativeEventPayload` cases and `EventBatch` preserve this
contract without a legacy decoder or a second wire format.

The native event queue retains repeated taps, double taps and long presses.
It admits only finite coordinates and respects both its event-count and byte
budgets. Rejected admission leaves previously queued events intact. OCaml's
sequence gate filters replayed batches without executing handlers again.

`native-gesture-events` embeds actual OCaml handlers in the runtime fixture.
The tests exercise every coordinate and pointer kind, repeated long presses,
replayed sequences, all nonfinite coordinates and exact queue limits. The RED
run uses the new typed API with an unimplemented encoder; valid admission and
actual runtime delivery fail. Implementing the payload encoding makes those
same tests pass. Related pointer, text and queue tests verify the shared encoder.

## Native recognizer ownership

The bridge uses Apple's
[NSGestureRecognizerRepresentable](https://developer.apple.com/documentation/swiftui/nsgesturerecognizerrepresentable)
on macOS 26 and
[UIGestureRecognizerRepresentable](https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentable)
on iOS 26. These APIs attach native recognizers to SwiftUI gestures and provide
coordinate-space conversion. Their declarations are present in the installed
Xcode 26.1.1 SDK. Do not replace system single/double-click timing with an
application timer without evidence that the system recognizers cannot satisfy
the required contract.

`tool/probe_swiftui_native_gesture.swift` is a framework probe, not an acceptance
test. It posts an application-local click to its own window and reports native
recognizer creation, callbacks, coordinates and application/window activity.
It must report one recognition to exit successfully. Earlier locked-desktop
runs did not recognize clicks. After unlocking, the command-line probe also
needed an explicit accessory activation policy before its window could become
key. With that policy and `--activate`, application-local queued events produce
one native recognition with `active=true keyWindow=true`
(`/tmp/swiftui-native-gesture-active-verified.log`). The callback reports local
`(140, 46)` and global `(160, 112)` points for the injected window point
`(160, 140)`; coordinate conventions still need integration assertions.

An interactive run independently recognizes a real CUA click and then activates
the sibling Button (`/tmp/swiftui-native-gesture-interactive.log`). The Button
is outside the gesture target, so this does not establish nested-control
isolation. Neither run establishes actual OCaml gesture acceptance. No global
input or accessibility setting was changed.

Run the probe in a usable foreground desktop session:

```sh
xcrun swiftc -parse-as-library -target arm64-apple-macos26.0 \
  tool/probe_swiftui_native_gesture.swift -o /tmp/bonsai-native-gesture-probe
/tmp/bonsai-native-gesture-probe --activate
```

`NativeGestureController` belongs to the render node and registers weak native
recognizers. Binding replacement, loss of presentation, view unmounting and
node disposal invalidate recognition generations and reset the recognizers.
The Session admits input only from the current, active, presented Gesture
node with matching bindings and children. Unrelated text/history updates
preserve a recognition in progress.

System click/tap and press recognizers provide timing and movement thresholds.
Single click requires double click and long press to fail; double click also
requires long press to fail. There is no application double-click timer.
A separate passive recognizer observes pointer transitions without preventing
native controls or other recognizers. On tested macOS, a nested Button emits
its own action, with passive pointer events but no ancestor tap/long press.
The initial iOS passive recognizer tracks one contact; supporting all concurrent
contacts remains required before declaring the pointer behavior complete.

The App defines a named SwiftUI coordinate space at its content root. Native
representables convert both local and root event positions through SwiftUI.
Using the recognizer's built-in `.global` directly exposed a 32-point macOS
title-bar offset compared with root layout measurements. The named root space
fixes that discrepancy without manual title-bar or safe-area arithmetic in the
renderer. The native window regression independently checks both local and
root positions against the application's resolved layout anchors.

Scroll-view cancellation/competition, transformed and nested gesture targets,
secondary pointer buttons and actual iOS touches/Apple Pencil still need
additional acceptance. FocusScope, KeyboardListener and remaining Material
Button/FAB migration are separate unfinished Gallery prerequisites.


## Earlier transport verification checkpoint

The final related run passes 16 tests in seven suites
(`/tmp/gesture-events-final.log`, 0.090 seconds), including actual OCaml gesture,
pointer and native-text event handlers. `dune build @all @runtest @fmt` passes
(`/tmp/gesture-ocaml.log`); existing native linker stub warnings remain. Strict
handwritten Swift formatting, whitespace checks and agent document validation
pass. This checkpoint does not claim a full-suite rerun or native gesture
recognition acceptance.


All three platform checks pass (`/tmp/gesture-platforms.log`, 18.478 seconds),
including physical iOS 26 module/example compilation and explicit unsupported
target rejection. The protected spec tree is unchanged. No new Mail screenshot,
source commit/push or generated SDK publication was produced at this checkpoint.


## Native window regression

`native/test/gesture_window.swift` and `test_gesture_window.py` drive an actual
OCaml application with application-local native mouse events. Scenarios cover
single-click delivery and coordinates, double-click precedence, long press,
passive pointer identity/buttons, nested Button ownership, drag cancellation,
handler replacement, removal and session deactivation/reactivation. The
single-handler variant must remain usable without double-click or long-press
bindings. The fixture lives outside the protected spec tree.

The first harness run failed to start its standalone windows and timed out;
those failures are not behavioral RED. Bundled test executables and
option-prefixed arguments corrected the harness. The actual window regression
then fails all five scenarios because Gesture is not rendered
(`/tmp/swiftui-gesture-window-red-verified.log`, 31.095 seconds). A separate
real-runtime staging test fails specifically with `unsupportedNode(48)`
(`/tmp/swiftui-gesture-store-red.log`).

After implementing staging, renderer ownership, recognizers and Session input
admission, all five scenarios pass in 43.184 seconds
(`/tmp/swiftui-gesture-window-green-root.log`). The test also needs ordinary
SwiftUI accessibility materialization before selecting the fixture's native
Buttons; missing labels before materialization were a harness issue. The
root-coordinate discrepancy described above was a renderer issue and is fixed
by the App-owned named coordinate space.

All three platform checks pass in 22.384 seconds
(`/tmp/swiftui-gesture-platforms.log`), including full module and retained
example compilation for physical iOS 26 arm64, and unsupported Simulator/Intel
rejection. These builds do not prove device gesture behavior. The native
window command is included in `make swift-test` and requires a usable macOS
foreground session. The complete Swift regression passes all 410 tests in 90 suites with explicit
`--no-parallel` in 402.910 seconds (`/tmp/swiftui-gesture-full-serial.log`).
The default runner now uses that verified invocation because native UI suites
share one AppKit application. An earlier parallel run failed one pre-existing
500 ms MorphingSurface timing assertion; its unchanged assertion passes both
in isolation and in the complete serial run. No animation behavior or assertion
was weakened. OCaml `@all @runtest @fmt @install`, generated protocol checking,
all ten completion-report checks, strict Swift formatting, Python compilation,
whitespace and all 49 agent documents pass.


## AppKit pointer device metadata

Gesture and Hover now share `AppKitPointerDevices` within the application.
Ordinary mouse events use ID 0. Tablet events use their bounded native device
ID plus one, keeping them distinct from the ordinary mouse and consistent
across windows and observers. Pen, eraser and tablet cursor types come from
proximity events, never from a tablet-point event's `pointingDeviceType`.
A tablet point with no current proximity information carries the explicit
`unknown` kind; no unobserved pen/eraser identity is invented.

The device scope owns one local event monitor while leases exist. It records
proximity arrival/departure across application windows, clears type information
when the application resigns active, and removes the monitor and stored metadata
when its final lease is released. Capture, window source and Gesture controller
all release their leases on disposal; lease deinitialization also releases
ownership. Disposing one observer preserves metadata still owned by another.
The default scope is shared; the source constructor also accepts an internal
scope so its ownership regression is independent of other live test windows.

`AppKitPointerDeviceTests` constructs native AppKit event packets and delivers
them through this process's `NSApplication.sendEvent`. The initial regression
fails 16 identity/kind assertions, then passes after metadata sharing. A separate
inactivity regression fails while proximity information survives the resign-
active notification, and passes once that notification invalidates the cache.
The test covers cross-window proximity, two device IDs, pen/eraser transitions,
unknown proximity, departure, inactivity and independent observer disposal.
It does not generate global input or prove physical stylus hardware behavior.

The related 19 tests in seven suites pass in 0.423 seconds
(`/tmp/swiftui-pointer-related-final.log`), covering native sources/captures,
Hover ownership, queue encoding and actual OCaml pointer/Gesture handlers.
An intermediate combined run exposed a test assumption that no other metadata
leases existed; giving the ownership test its own native device scope corrects
that assumption without clearing live application metadata on every observer
removal.

The complete serial Swift suite passes 411 tests in 91 suites in 408.067 seconds
(`/tmp/swiftui-pointer-full.log`). Three platform checks pass in 19.957 seconds;
OCaml build/test/format/install and generated-protocol checks also pass.

The real Gesture window regression now additionally checks ID 0 and a combined
Hover/Gesture tablet scenario. Its current attempt fails before input because
the Mac has locked again (`/tmp/swiftui-pointer-window-red.log`). CUA confirms
the lock and the user has been asked to unlock the Mac. Those six setup failures
are not behavioral RED or passing pointer interaction evidence. Re-run the full
window scenarios in the unlocked session before accepting their integration.

## UIKit contact processing

The UIKit passive recognizer now uses `PointerContactInput` instead of storing
one touch and incrementing a counter independently in each recognizer. A shared
weak, object-identity map assigns direct-touch IDs from 2 upward; separate
observers of the same native touch receive the same ID. Ordinary mouse ID 0
and Pencil ID 1 match the existing UIKit hover source. Active contacts retain
their own kind and binding generation, and queued edges retain each contact's
position and button mask. Ending one contact leaves the others active. Draining
the queue preserves every edge even if UIKit delivers an action after several
touch callbacks. Cancellation removes that contact's pending edges; reset drops
all retained contacts and edges. Neither operation invents a pointer-up event.

The adapter visits every touch in each callback, allows mixed touch types and
enables multiple touches on its attached view during update/first admission.
Each queued position is converted individually with SwiftUI's
[`convert(globalPoint:to:)` API](https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentablecoordinatespaceconverter).
The system's multi-touch delivery, view attachment timing and native-window to
SwiftUI coordinate correspondence still require physical-device verification,
including transformed targets. Successful compilation does not establish them.

Five new tests fail against the empty input-contract scaffold (eight assertions,
0.033 seconds, `/tmp/swiftui-contact-red.log`) and pass after implementation
(0.019 seconds, `/tmp/swiftui-contact-green.log`). Four utility tests cover
simultaneous contacts, nested observers with opposite admission order,
object-identity rather than value equality, reserved hover IDs, duplicate or
unknown transitions, cancellation, reset and weak lifetime. The fifth sends
two contacts' four queued edges through the actual native OCaml runtime and
checks its complete history. These are input-processing and transport tests,
not a recording of UIKit receiving physical touches. Three platform checks pass
in 20.028 seconds (`/tmp/swiftui-contact-platforms.log`), including the complete
Swift module and retained example entrypoints for physical iOS 26 arm64.

The full serial regression passes 416 tests in 92 suites in 409.270 seconds
(`/tmp/swiftui-contact-full.log`). Strict formatting and all ten test-report
completion checks also pass.

## Remaining pointer acceptance

Physical iOS multi-contact delivery and nested recognizer identity, iOS
gestures/Apple Pencil, actual macOS tablet hardware,
secondary buttons, scroll competition, transformed/nested targets and consistent
root-coordinate conversion across Gesture and Hover remain acceptance work.
