# SwiftUI Sliders

Status: implemented native value, event, keyboard and accessibility paths;
macOS interval mouse scenarios pass. Physical-device acceptance remains incomplete.

The public API is `View.Slider.create` for one value and `View.Slider.range`
for an ordered interval. Both use an optional positive `step` in domain units,
an explicit accessible label (two labels for an interval), an optional
`on_change` handler and a required `on_change_end` handler. The default domain
is `[0, 1]`. `axis:Vertical` selects bottom-to-top increase and requires bounded
height. Horizontal controls follow the inherited layout direction.

```ocaml
View.Slider.create
  ~min:0.
  ~max:100.
  ~step:10.
  ~value:level
  ~label:"Volume"
  ~on_change:change_volume
  ~on_change_end:finish_volume
  ()

View.Slider.range
  ~min:0.
  ~max:100.
  ~step:5.
  ~value:(View.Slider.Range.create ~start:lower ~end_:upper)
  ~label_start:"Minimum price"
  ~label_end:"Maximum price"
  ~on_change_end:finish_interval
  ()
```

`Material.slider`, `Material.range_slider`, `Material.Range` and their private
constructors and legacy wire nodes were removed. Flutter `divisions`, centered
and wavy visual variants are replaced by native appearance and explicit step
values. There are no compatibility overloads. Gallery and the expressive
catalog consumers use the new API. Obsolete Flutter integration copies remain
scheduled for deletion with the rest of that backend.

## State and event contract

OCaml owns the accepted selection. Swift owns the active edit, a temporary
selection and an admitted request serial. Consecutive continuous events may
coalesce; end events are retained. A discrete keyboard or accessibility
adjustment sends the optional continuous event followed by the required end
event. An unchanged or rejected OCaml response restores the authoritative
selection. Changing semantic configuration fences stale bindings; changes to
only the accepted value may echo while an earlier presentation is pending.
Disabling, hiding or disposing a control cancels its local edit.

The native queue transports scalar doubles through tags 30/31 and ordered
pairs through tags 32/33. OCaml handlers receive `Float` or `Float_range`.
Session admission requires matching displayed/current configuration, an enabled
control, a bound handler and an in-domain payload.

Both languages validate finite bounds, values and domain span, `min < max`,
ordered range endpoints, nonempty labels and a finite positive step no greater
than the span. A step must also produce representable movement at both domain
ends. Native adjustments clamp before arithmetic can overflow; reaching a
finite endpoint cannot be silently discarded as an infinite input.

Core node 45 encodes value, minimum, maximum, optional step, enabled, vertical,
continuous-handler presence and label. Node 46 adds the upper endpoint and
second label. Their complete update masks are 255 and 1023. Both are leaf
nodes; enabled controls require their end binding and exactly the declared
continuous binding. Disabled controls have neither binding.

## Native composition

A scalar uses SwiftUI `Slider`. Its accessibility representation also uses a
native Slider with explicit step-aware adjustment. On macOS, attaching the
adjustment directly to the visual Slider changed values but reported failed
accessibility actions; the representation preserves the native action result.
A vertical scalar rotates its bounded horizontal control, with layout direction
fixed for the rotation.

An interval uses a SwiftUI track, selected span and two independently labeled
thumbs with 44-point hit regions. Each thumb has a native Slider accessibility
representation and a keyboard focus target. Horizontal left/right follows
layout direction; up/down increases/decreases in both orientations. A thumb
cannot cross the other endpoint. When both endpoints coincide, initial logical
drag direction chooses the endpoint and retains that choice until release.
The final release position is applied before emitting the end event. Explicit
point mirroring uses an LTR positioning surface to avoid SwiftUI mirroring the
thumb positions a second time; accessibility labels retain the inherited direction.

## Verified evidence and remaining acceptance

`swift/BonsaiSwiftUI/Tests/SliderTests.swift` checks malformed domains,
native accessibility stepping, range bounds, controls without continuous
handlers, and large finite domain endpoints. Its keyboard test uses the
AppKit focus loop and `NSWindow.sendEvent` in horizontal/vertical and LTR/RTL
combinations. Calling a first responder directly bypasses SwiftUI key dispatch
and is not the test path. Removing the focus/key implementation makes all four
combinations fail before restoring it.

The real `native-slider` entrypoint runs the actual Gallery OCaml component.
Native accessibility operations exercise accepted and ignored scalar/range
changes, disabling, retained identity and the vertical end-only control. The
visible end-event count verifies that the final event reaches OCaml.

`python3 native/test/test_slider_window.py` runs a standalone SwiftUI App and
is included in `make swift-test`. Eight combinations cover horizontal/vertical,
LTR/RTL and either endpoint moving first. Each case performs six native mouse
drags: opening a collapsed interval in either direction, bringing endpoints
together, reopening the collapsed pair and reaching the domain bounds. Values
and exactly one end event per drag are verified. An explicit PASS marker and
successful exit are both required.

The original test sent events outside the content area and expected an inactive
window to accept activation clicks. The harness now measures the SwiftUI global
content frame, explicitly allows activation clicks in its test window and queues
events through the application's normal event loop. No system input injection
or desktop unlock is involved. A pure SwiftUI DragGesture reference established
the event path before testing the production control.

The corrected test first reproduced the fixed-endpoint overlap defect, then
exposed the missing release position and double RTL mirroring. All eight cases
pass after those implementation fixes. This proves local macOS mouse dispatch,
not physical iOS touch or user desktop interaction.

Track clicking, cancellation during an interrupted drag, interaction inside a
swipe container, native pointer focus, physical iOS touch, VoiceOver and hardware
keyboard acceptance remain open. The scalar and interval capability is therefore
not yet fully accepted for the migration.
