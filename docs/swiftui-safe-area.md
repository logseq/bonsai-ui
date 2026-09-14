# Native Safe Areas

SwiftUI respects the host's safe area by default. Ordinary content needs no
wrapper to avoid system bars, display cutouts or the software keyboard.
`View.ignores_safe_area` explicitly expands a child into selected regions;
`View.safe_area_padding` adds signed point distances to the safe area inherited
by descendants.

```ocaml
content
|> View.ignores_safe_area
     ~regions:View.Safe_area_regions.Container
     ~edges:[ Layout.Edge.Top ]
|> View.safe_area_padding
     ~insets:(Layout.Edge_insets.only ~leading:12. ~trailing:20. ())
```

`Safe_area_regions` supports `Container`, `Keyboard` and `All`. Container is
the default, so extending under system bars does not implicitly disable
keyboard avoidance. Edges are `Leading`, `Top`, `Trailing` and `Bottom`.
Omitting edges selects all four; an empty list preserves native avoidance.
Duplicates and order are canonicalized to a set. Leading and trailing follow
SwiftUI's layout direction.

Padding distances must be finite and may be negative. They add to the native
safe area; they are not minimum distances compared with system insets. The
order of safe-area, background and frame modifiers follows ordinary SwiftUI
composition. These operations also preserve the typed axes of `Viewport`
and `Body` wrappers.

The previous `safe_area` constructor, its minimum-padding contract and wire
node 68 are removed. The new nodes have exactly one child and no event
bindings:

| Node | ID | Property mask | Payload |
| --- | --- | --- | --- |
| Ignores safe area | 11 | 3 | Region byte: Container 0, Keyboard 1, All 2; edge byte: leading 1, top 2, trailing 4, bottom 8. |
| Safe-area padding | 12 | 1 | Four finite f64 values: leading, top, trailing, bottom. |

Both decoders reject invalid region/edge values and non-finite distances.
Malformed updates leave the displayed tree unchanged. System safe-area
measurements in environment events remain separate from these view modifiers.

Mail now uses native default avoidance for its drawer and detail. Its content
explicitly extends at the bottom and its bottom navigation at the top, keeping
the existing composition intent. Full Mail navigation and native rendering
are still required before application screenshots can be delivered.

Gallery's `safe_area_component` cycles through native avoidance, container-top
extension, keyboard-only extension, all-region extension and asymmetric
padding. A real OCaml/native integration test hosts that component in a titled
macOS window with full-size content. It observes the actual titlebar safe area,
activates the native button, compares painted bounds through all five states,
resizes the window and verifies retained node objects. The test disables
NSHostingView's automatic content sizing so that the specified window sizes
remain under test control.

Directional and negative padding also match equivalent SwiftUI ImageRenderer
output. A related regression verifies that Spacer expands through background
and flexible-frame modifiers. Single-child modifiers compose their child
directly; runtime branch selection avoids conditional view containers that
alter Spacer's layout. Keyed child collections and stateful controls retain
explicit identity.

These tests cover macOS native geometry and current iOS source typechecking.
They do not verify a physical iPhone's keyboard, home indicator, rotation or
VoiceOver behavior. Those device acceptance checks and Mail screenshots remain
open; Simulator is outside the supported platform matrix.

References: [Apple: SafeAreaRegions](https://developer.apple.com/documentation/swiftui/safearearegions)
and [Apple: safeAreaPadding](https://developer.apple.com/documentation/swiftui/view/safeareapadding%28_%3A%29).
