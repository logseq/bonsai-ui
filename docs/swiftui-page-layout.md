# Native page layout composition

`Material.scaffold` and its node 96 are removed. Page layout uses ordinary
SwiftUI content and the existing bounded `View.Body` contract. Fixed header and
footer content occupy real layout space, scrolling content receives the remaining
bounds, and an overlay attaches to the region whose bounds it should follow.
There is no new Scaffold node, slot protocol or floating-button location enum.

```ocaml
let viewport =
  View.Scroll.vertical rows
  |> View.Viewport.Vertical.overlay
       ~alignment:Layout.Alignment.Bottom_end
       ~overlay:
         (View.button ~on_press:create ~child:(View.text "New") ()
          |> View.padding
               ~insets:(Layout.Edge_insets.only ~trailing:16. ~bottom:16. ()))
in
let body =
  View.Body.Vertical.create
    [ View.Body.Vertical.fixed header
    ; View.Body.Vertical.fill viewport
    ; View.Body.Vertical.fixed footer
    ]
in
App.View.create ~theme ~body
```

The footer is persistent content, not a modal presentation. Changing its height
changes the scroll region's allocated height. The overlay follows that region,
so it does not need to know the footer's height. Use Sheet for modal content and
native navigation/tab APIs for destinations. Material notch shapes, docking
locations and global slot ordering are removed. Regular layout, directional
alignment and spacing express positioning explicitly.

`Viewport.Vertical.overlay` and `Viewport.Horizontal.overlay` preserve their
axis types. Their overlays do not change the base region's measurement or become
part of its scrolling content. `Body.overlay` remains available for content
that should follow the entire bounded body instead. These operations use the
existing native overlay renderer; no new wire node is introduced.

`Body.with_size ~width ~height` supplies finite positive bounds and returns an
ordinary View. This permits a bounded page demonstration inside a larger scroll
catalog without extracting the private body representation. Gallery embeds the
page-layout catalog at 480 by 400 points; an actual application passes its Body
directly to App.View and receives bounds from its window. Invalid dimensions
are rejected, and the existing Frame protocol carries the finite dimensions.

## Gallery and verification

Gallery's root now uses a bounded NavigationStack page with native title/toolbar,
scrolling catalog, fixed bottom status and a native New Button. The scrolling
header and other legacy Gallery sections still need migration before the whole
standalone Gallery can render. Its top/bottom Material bars are removed; see
[native page bars](swiftui-app-bars.md).

`Page_layout_catalog.component` is included in Gallery and embedded as
`native-page-layout`. It uses core buttons, a 50-row native ScrollView, fixed
header/footer content and a viewport overlay. The native window regression
first failed at the former Scaffold node 96. The replacement verifies:

- Header, footer, floating and row actions reach the same actual OCaml state;
  repeated actions remain separate.
- Increasing the footer from 60 to 100 points reduces the scroll region by
  40 points without resetting the current scroll position.
- Resizing the native window changes the allocated viewport while preserving
  native scroll identity, logical nodes and the 400-point scroll offset.
- The footer remains stationary during body scrolling and the floating action
  stays above it during expansion and resizing.
- Hidden/disposed sessions reject retained actions.

The OCaml tests also inspect bounded Body and overlay structure without a
Scaffold wrapper. The generated viewport-body fixture now starts at its ordinary
overlay root. The old Scaffold property record, encoder/decoder, renderer registry
branch and Material floating-location type are removed.

This unit does not establish the full remaining toolbar/navigation-bar API,
physical keyboard avoidance, VoiceOver, large-catalog performance, complete
Gallery or iOS execution. The native-local composer extension still needs its
SwiftUI replacement; it can no longer depend on a removed Scaffold slot. Actual
Mail screenshots remain a separate required deliverable.
