# SwiftUI Badge Overlays

`View.badge ?key ?count ?alignment ?visible content` decorates existing content
with native SwiftUI shapes and text. An omitted count displays a dot; an
explicit zero displays zero. Counts must be non-negative and retain their exact
integer value. Leading, Center and Trailing alignment refer to the top edge
and follow layout direction. The default is Trailing and visible.

The numeric badge uses native caption typography, white text and a semantic
red Capsule; the dot uses a red Circle. Alignment guides place the badge's
center on the chosen top anchor. The overlay does not change the content's
layout size. It is excluded from hit testing and accessibility, so it adds no
independent action or duplicate spoken count. Give the underlying control
meaningful semantics, as the Gallery does:

```ocaml
View.button ~on_press ~child:(View.text "Open notifications") ()
|> View.semantics ~properties:(Semantics.create ~value:"8 unread messages" ())
|> View.badge ~count:8
```

Setting `visible` to false hides only the decoration. Content identity,
enabled state and input ownership are retained. Padding belongs to the caller
when surrounding layout should reserve room for the overflow decoration.

The old `Material.badge` API and physical Top_left/Top_right alignment type are
removed. Node 58 stores optional unsigned count bytes, directional alignment
and visibility with update mask 7. The accepted integer domain ends at signed
Int64 maximum; the public OCaml constructor uses its non-negative `int` domain.
The old generic floating-point count transport is no longer used by Badge.
Negative counts, invalid flags/alignment, malformed children, event bindings,
truncation and trailing bytes reject the complete staged frame.

## Verification

Swift tests compare dot, zero, ordinary and maximum signed-64-bit counts against
independent native overlay expressions at all three anchors in LTR and RTL.
Hidden decoration matches the undecorated content. The actual Gallery component
covers precise maximum OCaml counts, dot/zero transitions, visibility, alignment,
disabled content, retained Button identity, presentation barriers and closure.
Its standalone App checks native accessibility values and actual Button actions
at 640 and 360 points. Full physical pointer/touch and device visual acceptance
remain part of the overall migration.
