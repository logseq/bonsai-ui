# Native Animated Opacity

`View.animated_opacity` publishes an opacity target, a semantic animation intent
and a completion handler. SwiftUI interpolates the opacity locally with
`withAnimation`; OCaml receives an animation ID when the current intent
completes. No intermediate opacity samples cross the native boundary.

```ocaml
View.animated_opacity
  ~key:(Key.string "preview-fade")
  ~animation:(Animation.create ~id:animation_id ~duration_ms:240
                ~curve:Animation.Curve.Ease_in_out ())
  ~opacity:0.2
  ~on_completed
  preview
```

The target must be finite and within zero through one. Animation IDs are
non-negative signed-64-bit values; duration is a non-negative u32 millisecond
value. Linear, Ease_in, Ease_out and Ease_in_out map to native SwiftUI curves.
The view retains its child's layout extent and logical identity.

## Completion ownership

Initial mount uses the target without an animation or completion callback.
Changing the target or any intent property supersedes the previous in-flight
completion. A new ID with the same target still completes once. Zero-duration
and reduced-motion requests use an immediate native transition.

A changed intent starts only when its current properties and binding match the
presented tree, its content is active, and a native view is attached. Normal
completion uses SwiftUI's removed-animation completion criterion, followed by
an asynchronous MainActor callback. A generation check rejects interrupted and
disposed callbacks before they can enqueue an event.

Hidden or inactive content replaces its animation with a zero-duration native
transition and retains its pending completion until it becomes active and
mounted again. Temporary view detachment
retains the logical controller; logical removal, kind/epoch replacement and
session close dispose it. Restoring a removed view is an initial mount and does
not emit its previous completion.

Forced settling changes a second animatable coordinate alongside the target
opacity. This invalidates SwiftUI interpolation even when the opacity target is
unchanged, without changing child view identity. A zero-duration animation
replaces the existing interpolation; a nil animation alone leaves it running.
Only the opacity coordinate affects drawing. Forced transitions use the same
removed-animation completion and generation checks as ordinary animations.

A completion is a renderer lifecycle event. It can originate inside a disabled
Toggle's label without bypassing that Toggle's ordinary input isolation. It
still obeys navigation/content visibility, presentation, node identity and
current-handler checks. The event uses tag 15 and returns
`Event.Payload.Int64 animation_id` to OCaml.

Completion is marked delivered only when the bounded event queue admits it.
If admission fails, the controller retains the latest unadmitted completion and
retries from the session's update loop. A newer intent replaces that retained
completion. Once admitted, the event is not emitted again.

## Verification and remaining acceptance

Initial tests failed on unsupported node 71. Native raster tests now compare
initial opacity and layout with equivalent SwiftUI content. Malformed opacity,
ID, curve, payload, binding and child structures reject the entire transaction.
A real native queue test fills capacity, supersedes an unadmitted completion,
then verifies that draining the queue admits only the latest completion once.

Gallery embeds the animation inside a disabled native Toggle label. Its actual
OCaml integration holds a new frame unpresented longer than the requested
animation, verifies no early completion, then acknowledges it and measures the
native animation before receiving its single callback. Other controls remain
outside the label and change the target or remove the animation.

The native App scenario covers all four curves, duration, interrupted targets,
a repeated target with a new ID, zero duration, logical removal/remount, a
reduced-motion signal, hidden-session restoration and 640/360-point windows.
The reduced-motion test supplies the same controller signal used by the View's
read-only OS environment. It does not change or validate the user's system
accessibility setting. An attempted outer-transaction override did not reliably
substitute for that signal and is not used as Reduce Motion evidence.

A native NSHostingView regression starts a two-second fade and requires a
companion SwiftUI AnimatableModifier to report an intermediate value after
350 milliseconds. It then exercises mid-animation Reduce Motion, an 80-millisecond
hide/restore cycle (40 milliseconds in the focused test), repeated targets,
zero-duration targets and multiple visibility changes in one update. The
companion shares the controller transaction and animatable coordinates; it
records interpolated values rather than reading the target back. Both the value
120 milliseconds after cancellation and the value observed when completion is
admitted must reach the requested endpoint. The original duration subsequently
expires without a duplicate callback, and logical node identities remain stable.

The original implementation failed all four initial interruption cases: the
callback had completed while the companion still interpolated near 0.8 instead
of the 0.2 target. Nil animation with a changed coordinate also failed. A
zero-duration animation alone fixed changed targets but failed unchanged-target
cancellation; both the invalidating coordinate and zero duration are necessary.
The native Gallery App also switches the controller's Reduce Motion signal
mid-animation and restores visibility before the old duration expires.

This companion interpolation test is not a framebuffer capture. NSView bitmap
capture returned blank content in this environment, and the desktop remained
locked. Frame-by-frame verification of the actual composited opacity, actual
OS accessibility changes, physical iOS behavior and VoiceOver remain required
before complete native animation acceptance. No Mail screenshot was produced by
these tests.
