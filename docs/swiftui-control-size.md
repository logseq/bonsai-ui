# Native Button Composition and Control Size

`View.button` is the core action surface. It accepts Automatic, Plain, Bordered
and Prominent styles, Normal/Cancel/Destructive roles, a controlled enabled
state and a composed label. Disabled buttons publish no Press binding.
An icon-only label should provide an explicit accessibility label through
`View.semantics`.

`View.control_size ~size child` sets SwiftUI's control-size environment for its
subtree. The five choices are `Mini`, `Small`, `Regular`, `Large` and
`Extra_large`. Nested scopes override the inherited value. Size is a semantic
native preference, not a fixed width, height or Material density value; the
platform and control style determine its appearance.

```ocaml
View.button
  ~style:View.Button_style.Prominent
  ~on_press
  ~child:(View.text "Continue")
  ()
|> View.control_size ~size:View.Control_size.Large
```

The modifier has one child, no input bindings and one required enum property.
Wire node 55 accepts values zero through four. Invalid enum values, malformed
updates and invalid child counts reject the entire candidate transaction.
Changing the size preserves the existing button and label identities.

The public Cupertino module and dedicated Material icon-button constructor,
private nodes and wire kinds 112 and 100 are removed. Those uses now compose
core Buttons with ordinary text, SF Symbols and accessibility modifiers. There
are no compatibility constructors. The former Material button and floating
action constructors, private nodes and codecs are also removed. Core Button
autofocus now has actual OCaml/native macOS focus and Space-activation tests.
Physical iOS keyboard acceptance remains outstanding.

## Verification

`ControlSizeTests.swift` compares the actual renderer's native macOS Button
measurements against equivalent SwiftUI Buttons for all five sizes. It checks
nested overrides and rejects invalid or truncated updates atomically. The
initial tests failed because node 55 was unsupported.

Gallery's actual `button_component` is embedded by the `native-buttons` runtime
fixture. The integration test originally failed on old Cupertino node 112.
Its replacement exercises all five sizes, activation, enablement, stable keyed
identity, hidden input and disposal through the real OCaml bridge.

`native/test/test_button_window.py` runs a real SwiftUI App. At 640 and 360
points, it presses Automatic, Bordered, Prominent and icon-only Refresh buttons
across all five sizes, observes the resulting forty actions, and verifies
labels and disabled controls. `make swift-test` includes this acceptance test.

Coverage establishes native macOS Button behavior. It does not establish that
every custom UIKit/AppKit adapter consumes this environment, nor physical-iOS
appearance or behavior. [Native Button autofocus](swiftui-button-focus.md) now
separately verifies observed focus, Space activation and lifecycle admission
through real OCaml/native-window tests. Physical keyboard, IME and modal-focus
acceptance remain outstanding.
