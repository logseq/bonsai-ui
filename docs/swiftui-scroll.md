# Native SwiftUI Scroll Containers

`View.Scroll.vertical` and `View.Scroll.horizontal` contain one ordinary view
subtree and return the corresponding typed viewport. Their optional `key`
retains identity; `shows_indicators` defaults to true and `fill_viewport` to false. The renderer uses
SwiftUI ScrollView with the selected axis and indicators. Vertical content
fills the available width; horizontal content fills the available height.
The viewport must be placed in a bounded Body slot or assigned its finite
scroll-axis extent through `Viewport.Vertical.with_height` or
`Viewport.Horizontal.with_width`.

Content is eager and measured by SwiftUI. Use `View.Collection` for a large
logical dataset with an asynchronously materialized window. Scroll has no
required inert event handler, Sliver child, cache extent or primary-scroll
flag. Optional `on_scroll` reports native geometry through the existing
`Event.Payload.Scroll { pixels; delta }` payload. Explicit initial/end positioning
is available through `initial_anchor`; application-driven item changes use the
controlled Scroll_targets API.

Node 9 carries three strict booleans, `vertical`, `shows_indicators` and
`fill_viewport`, plus the `initial_anchor` enum, with property mask 15. Previous
masks 3 and 7 are rejected. It requires exactly one child and permits only the optional Scroll_notification
binding (tag 13). Invalid
flags, masks, truncated properties or child structure fail atomic staging.
OCaml encode/decode round trips cover both axes and both indicator values.
There is no old Scroll_view decoder in the Swift renderer.

`Gallery.scroll_component` renders both axes through the actual OCaml runtime.
The native window test scrolls each, changes content sizes and indicators,
resizes the window and verifies retained native ScrollView instances and
positions. Initial vertical and horizontal content extents are 800 points;
a button grows them to 960 and 1,000 points without resetting their offsets.
The Gallery component is also included in the main Gallery view.

Mail detail, Clock and Todo now use this container. Their old Sliver wrappers
and no-op scrolling handlers are removed. Mail's message list uses the
separate windowed collection API. The type-check fixtures now exercise the
new Scroll and Collection APIs, including rejected axis/slot mismatches and
rejected unkeyed collection content.

These tests establish native macOS scrolling and source-level iOS support,
not physical iOS gesture acceptance, complete application navigation return,
or screenshots of a standalone Mail application. Gallery
headers now use [native sections](swiftui-scroll-sections.md). Horizontal virtual
collections use the shared Collection API.
[Mixed virtual content](swiftui-collections.md#mixed-content-in-one-catalog) is
also implemented with one catalog and viewport. The obsolete Scroll_view/Sliver
public surface and decoders are removed.

## Ordered scroll observations

All four native containers (`Scroll`, `Scroll_sections`, `Collection` and
`Scroll_targets`) accept optional `on_scroll`. Observers attach directly to
individual SwiftUI ScrollViews, so nested viewports retain distinct sources.
Collection visible-range and Scroll_targets position bindings remain independent
and retain their existing required/disabled rules. Adding or removing an observer
preserves the native ScrollView instance and its offset.

`pixels` is the native visible rectangle's leading coordinate in points: minY
vertically and logical minX horizontally, including RTL. `delta` is the difference
from the preceding accepted sample. The first sample establishes a baseline;
activation, rebinding, axis changes, hiding and unmounting invalidate the old
callback generation and reset that baseline. A native scroll phase change first
flushes any unreported movement, then emits a zero-delta boundary. There is no
Flutter phase decoder or synthesized drag sequence.

The native event queue merges only adjacent, nonzero, same-direction increments
with the same node, handler and displayed revision. It retains the newest pixels
and the finite IEEE-754 sum of the deltas. Zero increments, reversals, intervening
input and revision changes are barriers; a nonfinite sum is kept as separate
finite events. At most 1,024 noncompactable events can be pending. Rejection of an
otherwise valid scroll event fails the session explicitly instead of evicting an
event. A copied pump batch remains immutable while new events form the next batch.

The Gallery exposes all eight container/axis combinations with a live position,
accumulated travel and notification toggle. Native integration tests run all four
containers in both axes and both layout directions, perform forward/reverse
scrolls, toggle observation, hide/resume and reject old callbacks while retaining
native identity. A nested horizontal/vertical scenario checks independent sources
and drives the real session to queue saturation. Queue tests cover every flush
boundary of the 24-point threshold reference streams, phase zeros, reversal,
intervening input, finite overflow and prepared-batch immutability. Physical iOS
phase/gesture acceptance is still required.

## Filling a viewport with ordinary content

Set `fill_viewport:true` to offer the content at least the current viewport's
scroll-axis extent. The native layout first measures intrinsic content with an
unspecified scroll-axis proposal, then proposes the larger of that result and
the viewport extent. It keeps larger content scrollable instead of compressing it
to the window. This uses SwiftUI's [proposed-size measurement](https://developer.apple.com/documentation/swiftui/proposedviewsize/)
and [LayoutSubview sizing](https://developer.apple.com/documentation/swiftui/layoutsubview/sizethatfits(_:)).

Compose existing Weighted items to allocate the remaining space:

```ocaml
View.Scroll.vertical ~fill_viewport:true
  (View.Weighted.column ~spacing:0.
     [ View.Weighted.fixed header
     ; View.Weighted.share content
     ; View.Weighted.fixed footer
     ])
```

The horizontal API works identically, with logical placement in RTL. The same
native hierarchy is retained when filling is toggled. Ordinary padding, text,
controls and stacks remain ordinary content; no Sliver wrapper or viewport-size
round trip through OCaml is involved. Weighted shares retain their existing
weight and minimum-size behavior; this feature does not introduce a separate
flex algorithm. Large virtual datasets continue to use Collection.

Gallery has both-axis examples with fixed 80/40-point header/footer content,
a filling action button, a long-content toggle and a filling toggle. The native
window test measures actual accessibility frames and scroll extents in all four
axis/direction combinations, resizes the window, activates the filling control,
checks the 900-point long-content extent and retains offset/identity through
mode changes. The old `Sliver.fill` constructor, node 34, codecs and renderer
entries are deleted. A captured formerly valid frame must now fail with
Unknown_node_kind; no compatibility decoder remains. Physical iOS layout and
interaction acceptance remains outstanding.

## Initial positioning and retained offsets

`Scroll.vertical` and `Scroll.horizontal` accept
`initial_anchor:Scroll_anchor.Start` (the default) or `Scroll_anchor.End`.
`Scroll_sections` accepts the same option. Start and End refer to logical scroll
order and follow RTL; they do not reverse the source collection. SwiftUI's
[`initialOffset` anchor role](https://developer.apple.com/documentation/swiftui/scrollanchorrole)
applies the initial position without changing short-content alignment or making
the viewport follow later appends. Changing this property on an established
viewport does not replay the initial scroll. A new viewport identity establishes
a new initial position.

Native geometry and ScrollPosition preserve the current logical leading offset
when the viewport changes size, including RTL coordinate shifts. Ordinary Scroll
content also preserves that offset when its measured content size changes.
Lazy sections keep SwiftUI's keyed content anchoring for content updates. Active
user scrolling owns its position and suspends automatic size corrections.
All geometry and correction work remains native; no OCaml sizing round trip is
introduced. This is independent of the optional ordered scroll observer.

The Gallery demonstrates both axes of ordinary, sectioned and virtual initial
positions. Real-window tests run Start/End for Scroll and Scroll_sections and
Start/End/distant key for Collection in LTR/RTL. They verify initial offsets,
configuration changes, appends, resize, visibility changes and retained native
identity. Virtual cases additionally verify that the *first* visible-range
request names the target window, with a bounded materialized tree. Physical
mouse/trackpad and iOS-device acceptance remains outstanding.
