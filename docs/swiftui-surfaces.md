# Native decorative surfaces

`Native_widget.Surface` provides shared SwiftUI backgrounds for ordinary OCaml
views. It is a standard framework registration, available in every
`BonsaiApplicationView`; applications do not register a renderer themselves.

```ocaml
let module Surface = Bonsai_swiftui_ui.Native_widget.Surface in
Surface.create
  ~corner_radius:24.
  ~fill:(Surface.Thin_material tint)
  ~border_color:outline
  ~border_width:0.75
  ~shadow:(Surface.shadow ~color:shadow_color ~radius:14. ~y:6. ())
  content
```

## Contract

- `Solid` uses one ARGB color. `Linear` and `Angular` take 2–16 evenly spaced
  colors. Linear gradients run top to bottom; angular gradients begin at the
  trailing edge and rotate around the center. Repeat the first color to close
  a continuous color ring.
- `Ultra_thin_material`, `Thin_material` and `Regular_material` composite their ARGB tint over native
  SwiftUI material. With Reduce Transparency enabled, the same RGB tint becomes
  opaque. This accessibility behavior does not depend on application state.
- `opacity` defaults to 1 and accepts a finite value in [0, 1]. It affects the
  painted background only, preserving child text and controls at full opacity.
  Material opacity is forced to 1 under Reduce Transparency. To make a panel more
  transparent, use Ultra thin, reduce the tint alpha, and lower background opacity.
- A surface retains one OCaml child. The fill, inset border and shadow do not
  change layout, intercept gestures or add accessibility elements. Content is
  not clipped; use `View.clip` explicitly when required.
- Corner radius, shadow radius and border width must be finite and non-negative.
  Shadow offsets may be negative but must be finite.
- `presentation_background:true` also sets the containing native sheet's
  background and corner radius. Place this surface at the sheet content root.
  On iOS the system presentation background is explicitly clear and the surface
  paints one standard SwiftUI material layer behind the content. macOS paints
  the content surface. A fractional sheet detent can retain translucency on
  iOS 26; the native full-height Large detent is opaque.
  Sheet visibility, dismissal, detents and sizing remain `View.Sheet` concerns.
- Surfaces introduce no animations. Reduce Motion therefore requires no separate
  animation path; system sheet transitions continue to follow native settings.

## Native envelope

Standard native-widget kind **8**, schema version **2**, capabilities **0**.
Applications cannot replace this reserved registration. The normal native-widget
bridge carries its payload and retained child; there is no Note-specific protocol
or renderer branch.

All numbers are little endian. The payload contains:

1. Fill byte: solid 0, linear 1, angular 2, thin material 3, regular material 4, ultra thin material 5.
2. Color-count byte, presentation-background Boolean byte, reserved zero byte.
3. Six Float64 values: corner radius, shadow radius, shadow X, shadow Y, border width, opacity.
4. UInt32 ARGB shadow and border colors, followed by the fill colors.

The Swift decoder rejects invalid flags, modes, counts, nonfinite dimensions,
negative radii, invalid opacity, trailing bytes and truncated payloads before publishing a tree.
The registration requires exactly one child. Public OCaml construction validates
its inputs before emitting the envelope.

`SurfaceTests` checks registration, malformed payload rejection, native rendering
and accessible child preservation. It also verifies opaque reduced-transparency
paint on different backdrops in light and dark appearances. The Note example exercises all fills except
an isolated angular page background, including material sheet presentation.
