# Native Surface Modifiers

Padding, background, clipping, and opacity are composed in the order in which
they wrap their child. They map directly to SwiftUI modifiers.

```ocaml
View.symbol ~name:"star.fill" ~size:24. ()
|> View.padding
     ~insets:(Layout.Edge_insets.only
                ~leading:28. ~top:8. ~trailing:4. ~bottom:8. ())
|> View.background ~color:blue ~corner_radius:8.
|> View.clip ~corner_radius:12.
|> View.opacity 0.7
```

`Layout.Edge_insets` uses leading and trailing point distances. These follow
SwiftUI's layout direction. `all` and `symmetric` remain useful for equal
insets. Values must be finite; negative insets are supported with native
SwiftUI semantics, including content extending beyond an overlay base.

`View.background` requires a color, including its alpha channel, and accepts
an optional corner radius that defaults to zero. It uses a continuous rounded
rectangle. It does not change the child's measurement or clip overflowing
content. Padding before background expands the colored area; padding after
background adds space outside it.

`View.clip` clips the child to a continuous rounded rectangle. The radius
defaults to zero; `antialiased` defaults to true. Both clip and background
radii must be finite and non-negative. `View.opacity` accepts a finite value
in the inclusive range 0 through 1.

The old Decoration object and Clip behavior enum have been removed. There is
no optional background-color field or save-layer mode in these new APIs.
The production wire format uses required ARGB color and radius for Background,
radius and a strict boolean for Clip, four directional distances for Padding,
and one scalar for Opacity. All four are single-child nodes with no events.
A malformed property update rejects the complete candidate transaction.

The Gallery's `modifiers_section` exercises background order, rounded and
rectangular clipping, opacity, and asymmetric directional padding. Its real
OCaml subtree is rendered through the native runtime in both layout directions.
`ModifierTests.swift` also compares the renderer against equivalent SwiftUI
expressions and checks incremental changes without remounting nodes.

Regenerate the component renders with:

```sh
BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation \
  swift test --scratch-path _build/swift --filter actualGalleryModifiersRender
```

The resulting `gallery-modifiers-ltr.png` and `gallery-modifiers-rtl.png` are
macOS ImageRenderer artifacts. Physical iOS rendering and the final Mail
application screenshots remain separate acceptance requirements.

Safe-area behavior is documented in [Native Safe Areas](swiftui-safe-area.md).
Single-child modifiers compose the child directly. Native node selection and
flexible-frame composition avoid conditional view containers that would change
Spacer expansion. A raster regression compares Spacer with background followed
by an expanding frame against the equivalent native SwiftUI expression.


[Native plane projection](swiftui-projection.md) documents `View.projection_effect`,
its 3×3 matrix contract, native composition order and rendering verification.


[Native animated opacity](swiftui-animated-opacity.md) adds semantic targets,
local SwiftUI interpolation and presentation-gated completion events.
