# Native Stacks, Frames, and Spacers

## Stacks and layout modifiers

`View.row`, `View.column`, and `View.stack` render native HStack, VStack,
and ZStack containers. All take ordinary view children. Row/column spacing
is optional: omission uses native spacing, zero removes the gap, and a
negative finite value permits overlap. NaN and infinities are rejected.

```ocaml
View.row
  ~spacing:12.
  ~alignment:Layout.Vertical_alignment.First_text_baseline
  [ title; value ]

View.column
  ~spacing:8.
  ~alignment:Layout.Horizontal_alignment.Leading
  [ header; content ]

View.stack ~alignment:Layout.Alignment.Bottom_end [ background; badge ]
```

Row vertical alignment supports top, center, bottom, first text baseline,
and last text baseline. Column horizontal alignment supports leading, center,
and trailing. Stack uses all nine `Layout.Alignment` values. Leading/trailing
positions follow the native layout direction. The default alignment is center.
These are eager containers; bounded and lazy collections remain a separate API.
See [Apple's HStack documentation](https://developer.apple.com/documentation/swiftui/hstack).

`View.layout_priority priority child` sets the native relative layout priority.
The value must be finite, and may be negative. Higher priorities receive space
before lower priorities when the parent has limited room. This follows
[SwiftUI's layout priority rule](https://developer.apple.com/documentation/swiftui/view/layoutpriority(_:)).
Proportional allocation is provided by the weighted stacks described below.

`View.offset ?x ?y child` moves the displayed content while preserving its
measurement. Both coordinates default to zero and accept finite positive or
negative point values, following the native
[offset modifier](https://developer.apple.com/documentation/swiftui/view/offset(x:y:)).
It can be combined with stack alignment and frame sizing.

The Gallery `stacks_section` covers baseline alignment, ZStack alignment,
compression priority, and offset placement. The real OCaml integration test
updates all three containers and both modifiers without replacing observed
nodes. Native raster comparisons cover LTR/RTL, all alignments, default/zero/
negative/positive spacing, and constrained text.

The legacy positioned `View.Stack` has been removed. Its consumers now use the
native overlay composition below. Body/Viewport scrolling remains unfinished;
see the full [implementation ledger](swiftui-implementation.md).

## Overlays and anchors

`View.overlay ~overlay base` uses the base view's measurement and proposes its
size to the overlay. Unlike `View.stack`, overlay content does not contribute
to the container's reported size. Alignment defaults to Center; all nine
`Layout.Alignment` values follow the native layout direction.

```ocaml
base
|> View.overlay ~alignment:Layout.Alignment.Bottom_end
     ~overlay:(actions
       |> View.padding ~insets:(Layout.Edge_insets.only ~trailing:16. ~bottom:16. ()))
```

Compose multiple overlays in drawing order. Use a fixed frame for an anchored
item, a flexible frame with a zero minimum and Fill maximum for an inset region,
and directional padding for the edge distances. Signed finite padding can
extend content outside the base. An offset moves the displayed content without
changing its measurement. Overflow is not implicitly clipped. An EmptyView
base retains SwiftUI's native empty sizing; a framed zero-minimum Spacer can
reserve an explicit blank surface.

`View.Body.overlay ~overlay body` applies the same two-child composition to a
typed body. There is no special tight-positioned base or child parent data.
The old `View.Stack.child`, `View.Stack.positioned`, position records, and the
wire parent-data field have been removed. Create-node payloads end after their
event bindings. The old Overlay `dismissible` field had no renderer behavior
and is removed instead of retained as a no-op.

Mail's outline connectors and expanded-header actions use these compositions.
Gallery's `overlays_section` demonstrates outside badges, stretched inset
content, and independently anchored labels. Native tests compare all nine
alignments in both directions, oversized and empty content, and signed insets.
The real OCaml update retains node identity when alignment and insets change.
The Gallery PNGs in `_build/validation/` are offscreen component verification;
they do not satisfy the running Mail screenshot requirement.

## Weighted stacks

`View.Weighted.row` and `View.Weighted.column` use SwiftUI's custom Layout
protocol. They accept typed fixed/share item descriptions; allocation belongs
to the container, and changing it preserves the child view's identity.

```ocaml
View.Weighted.row ~spacing:8.
  [ View.Weighted.fixed avatar
  ; View.Weighted.share ~weight:2. subject
  ; View.Weighted.share ~weight:1. ~fills:false timestamp
  ]
```

`fixed` measures its child with an unspecified main-axis proposal. `share`
uses a positive finite floating-point weight, defaulting to 1. With a finite
main-axis proposal, the layout subtracts fixed sizes and gaps, clamps the
remaining extent to zero, and distributes it in proportion to the weights.
Weights are normalized before summing, so large finite values cannot overflow
the total. Measurement and placement are linear in the materialized children.

Shares default to `fills:true`: the host adds a zero-minimum/infinite-maximum
frame along the main axis. `fills:false` lets content shrink within its proposed
share. Space it leaves unused is not redistributed. An explicit frame inside
a child can still exceed a proposal, following SwiftUI's normal layout rules.
Overflow is not clipped automatically.

An unspecified or infinite main-axis proposal measures all children at their
intrinsic sizes. A parent can subsequently propose a finite measured size,
which triggers proportional allocation for that new proposal. The unbounded
integration test uses native `fixedSize` to retain an unspecified proposal
through final placement; the layout does not cache an earlier proposal to
suppress the parent's later choice.

Spacing and cross-axis alignment follow the ordinary native stacks, including
text baselines. Omitted spacing uses native adjacent-view spacing. SwiftUI
handles RTL mirroring automatically for the custom Layout. EmptyView content
remains omitted; use a Spacer with explicit cross-axis framing when a blank
colored region must occupy both dimensions.

The old `View.Flex`, integer flex factors, loose/tight enum, and Flex parent-data
wire tags have been removed. Mail, Gallery, Todo, and SQLite worker callers use
Weighted. The still-pending Body/Viewport wrappers now delegate their allocation
to Weighted and accept `~weight` instead of `~flex`; their scrolling/rendering
migration remains unfinished.

The actual Gallery `weights_section` covers horizontal 1:2:3 shares, fixed
content, shrinking shares, and vertical 1:2 shares. The native integration test
changes weights and reorders keyed children while retaining all observed nodes.

## Frames and spacers

`View.frame` adds a native SwiftUI frame around its child. Omitted dimensions
follow the child's sizing behavior. A frame does not clip its content.

```ocaml
View.frame ~width:240. ~height:64. ~alignment:Layout.Alignment.Center title

View.frame
  ~min_width:0.
  ~max_width:Layout.Frame_limit.Fill
  ~min_height:32.
  ~ideal_height:48.
  ~max_height:(Layout.Frame_limit.Points 96.)
  ~alignment:Layout.Alignment.Center_start
  content
```

Fixed width and height use SwiftUI's
[`frame(width:height:alignment:)`](https://developer.apple.com/documentation/swiftui/view/frame(width:height:alignment:)).
Min/ideal/max values use its
[flexible frame modifier](https://developer.apple.com/documentation/swiftui/view/frame(minwidth:idealwidth:maxwidth:minheight:idealheight:maxheight:alignment:)).
The ideal dimension supplies an unspecified dimension in a layout proposal;
it is not an unconditional fixed size. Fill requests available space subject
to the native parent's proposal. Use a zero minimum with Fill when the frame
must also accept proposals smaller than its child's natural size.

Every point value must be finite and non-negative. Fixed and min/ideal/max
values cannot be combined on the same axis. Supplied min, ideal and finite max
values must be ordered. One axis can be fixed while the other is flexible.

Start/end alignment follows layout direction. The nine values in
`Layout.Alignment` map to SwiftUI leading/center/trailing and top/center/bottom.
Changing bounds or alignment updates the same node and retains child identity.

Use `View.spacer` for blank space:

```ocaml
View.row [ title; View.spacer (); actions ]

View.frame ~width:16. (View.spacer ~min_length:0. ())
```

An omitted minimum uses SwiftUI's platform default. A specified minimum must
be finite and non-negative. A fixed gap uses an explicit zero minimum and a
frame for its desired extent. `View.empty` maps to EmptyView and remains
omitted even when framed; it cannot reserve layout space.

The Gallery frame section and native integration tests exercise these APIs.
macOS rendering is verified; physical iOS layout and screenshots remain in the
[implementation ledger](swiftui-implementation.md)'s device gate.

## Native separators

`View.divider ()` creates SwiftUI `Divider`. In a row it produces a vertical
separator; in a column it produces a horizontal separator. The platform owns
its thickness and appearance. There is no explicit orientation property or
Material geometry bag. Use directional padding for spacing and indentation:

```ocaml
View.divider ()
|> View.padding ~insets:(Layout.Edge_insets.only ~leading:24. ~trailing:12. ())
```

`Material.divider` and `divider_orientation` are removed. Mail retains the
separator's allocated frame extent while the separator itself draws with
native appearance. Gallery demonstrates row, column and inset separators.
Wire node 105 is named `divider`, has no property payload and uses update mask
zero. It accepts neither children nor event bindings. Old geometry bytes and
masks reject the transaction.

`DividerTests.swift` compares the rendered separator with native SwiftUI in
row, column and stack parents, light/dark appearance and LTR/RTL. Padding and
keyed reorder retain the separator's node. The actual Gallery subtree renders
through the OCaml runtime; `gallery-dividers-{ltr,rtl}.png` are inspected
offscreen component artifacts under `_build/validation`. Physical-device
rendering and Mail application captures remain outstanding.


Finite control and tag groups can use [View.flow](swiftui-flow.md) for native
width-dependent wrapping, top-aligned rows and directional alignment.
