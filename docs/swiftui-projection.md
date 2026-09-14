# Native Plane Projection

`View.projection_effect` applies SwiftUI's `projectionEffect` to its child.
`Style.Projection` supplies identity, scale, translation and a general 3×3
projective matrix. The old `View.transform`, `Style.Transform`, 4×4 matrix
payload and generated transform names are removed.

```ocaml
View.symbol ~name:"star.fill" ~size:30. ()
|> View.projection_effect
     ~transform:(Style.Projection.scale ~x:0.8 ~y:1.2 ())
|> View.projection_effect
     ~transform:(Style.Projection.translate ~x:16. ~y:8. ())
```

The projection changes drawing without changing the parent's measured layout
extent. Modifiers apply from the child outward: scaling then translating is
different from translating then scaling. The effect uses native SwiftUI
coordinate and layout-direction behavior and does not add a clipping surface.

`Style.Projection.matrix3` copies exactly nine finite coefficients in the order
`m11, m12, m13, m21, m22, m23, m31, m32, m33`, matching SwiftUI's public matrix
fields. For a point `(x, y)`, the homogeneous divisor is
`w = m13*x + m23*y + m33`; the projected point is
`((m11*x + m21*y + m31)/w, (m12*x + m22*y + m32)/w)`.
This supports arbitrary affine effects and perspective of the rendered plane.
The constructor retains no mutable reference to the caller's array.

Wire node 29 is now `projection_effect`, with one `matrix3` field and update
mask 1. Nine finite doubles are required, with one child and no event bindings.
Truncated matrices, non-finite coefficients, wrong child counts and oversized
payloads reject the transaction. The old sixteen-value payload is not accepted.
Keyed projection and control nodes retain identity when coefficients change.

## Verification

`ProjectionTests.swift` initially failed because the renderer did not support
node 29. It now compares actual renderer pixels with native SwiftUI projections
constructed independently through CATransform3D, covering identity, scaling,
translation, rotation, reflection, shear and perspective in both layout
directions. The images must contain visible colored content. Separate checks
verify noncommuting modifier order, unchanged layout extent and atomic rejection
of malformed updates.

Gallery's `projection_component` runs through the real OCaml bridge. It cycles
identity, scaling, perspective and translation while retaining its Button,
composed symbol/text label, projection node and action count. Returning to the
initial mode restores the original coefficients. Closing the session fences
stale control callbacks. The component is included in the combined Gallery.

`native/test/test_projection_window.py` launches a real SwiftUI App and invokes
the native accessibility press action at 640 and 360 points. All eight mode
changes preserve the accessible label and return button actions to OCaml.
This does not establish pointer hit testing at projected coordinates, VoiceOver
usability or physical iOS behavior; those remain native acceptance work.

Semantic animation and its completion callbacks are a separate capability; see
[native animated opacity](swiftui-animated-opacity.md) for current ownership and
verification. Projection itself adds no completion event.
