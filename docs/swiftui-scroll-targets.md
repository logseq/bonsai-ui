# SwiftUI scroll targets

`View.Scroll_targets.horizontal` and `.vertical` replace Material Carousel with
bounded native ScrollView composition. Each item contains an arbitrary View and
a signed Int64 ID. Compose ordinary Buttons inside items for opening a card;
`on_position_changed` reports the focal item and does not invoke a card action.
The former Hero/Contained/Uncontained flags are removed. Explicit item fractions,
spacing, alignment and normal View modifiers define the presentation.

## Public contract

Both constructors return the corresponding axis-specific Viewport. The caller
must supply its bounded size using the existing viewport API. `fraction` defaults
to 1 and determines the item extent along the scroll axis relative to the viewport.
It must be finite and in (0, 1]. `spacing` defaults to zero and must be finite and
nonnegative. `alignment` is Start, Center or End, defaulting to Start. Start and
End follow horizontal layout direction. `snapping`, `enabled` and
`shows_indicators` default to true.

Item IDs are unique and own child keys, preserving identity across reorderings.
The wire count permits at most 65,535 items; that is a representation limit, not
a performance guarantee. Nonempty content requires `position = Some id` naming
an item. Empty content requires None. Programmatic position changes scroll to the
corresponding anchor. Position notifications carry `Event.Payload.Int64`.
Disabling scrolling removes its position-event binding while independent card
Buttons retain their own enabled state.

## Native rendering and state ownership

The renderer uses SwiftUI ScrollView, HStack/VStack, scroll target layout and
view-aligned snapping. Native content margins align the first and last cards as
well as interior cards. Horizontal RTL margins account for native scroll-content
coordinates. ScrollViewReader applies initial, programmatic and rejected
positions after a bounded layout is available.

Geometry preferences measure the focal target at the configured viewport anchor.
They report native viewport changes without requiring a synthetic click or a
second application reducer. Initial/configuration restoration suppresses
intermediate geometry observations until the requested target is aligned.
Layout identity includes size, item order, axis, fraction, spacing, alignment,
layout direction and snapping policy.

An observed position is staged locally until the OCaml response. Consecutive
position events for the same node, handler and displayed revision coalesce;
ordinary card actions remain distinct. Request serials preserve newer pending
intent. An unchanged OCaml response restores the authoritative position.
Replaced bindings, removed targets, inactive content and disposed nodes cannot
admit obsolete requests. Accepted native observations do not issue a scroll
command back to the same viewport: doing so would snap free scrolling to a card
anchor even when snapping is disabled.

Items currently use eager stacks. Native alignment tests exposed incorrect
estimated offsets with the initial lazy implementation. This implementation has
not established large-catalog performance; virtualized collections are a separate
API and do not substitute for this capability's outstanding performance checks.

## Protocol

Node 62 (`scroll_targets`) has complete property mask 511. Properties encode an
axis flag, UInt16 item count and signed Int64 IDs, optional Int64 position,
Float64 fraction and spacing, alignment byte and snapping/enabled/indicator
flags. Enabled nodes bind event 55 (`scroll_position_changed`) with an Int64
payload; disabled nodes have no binding. Child count must equal the ID count.
OCaml constructors, codecs and Swift transaction staging reject invalid domains,
duplicates, unknown positions, malformed flags and truncated properties before
publishing a frame. No Material Carousel compatibility constructor remains.

## Evidence and remaining acceptance

`examples/gallery/ocaml/carousel_catalog.ml` is the actual OCaml component used
by Gallery and the `native-carousel` test entrypoint. It exercises independent
card actions and position updates, full/preview cards, horizontal/vertical
layout, all alignments, snapping, disabled/rejected changes, reordering,
removal/restoration, empty content and handler replacement.

`ScrollTargetsTests.swift` checks atomic staging, malformed frames, controlled
state and obsolete callbacks. Native windows verify programmatic scrolling and
36 preview-card combinations across both axes, LTR/RTL, all three alignments and
first/middle/last initial positions. The actual runtime scenario verifies OCaml
state, repeated actions, coalescing and rejected/stale input.

`native/test/test_carousel_window.py` runs a standalone SwiftUI App with the
production OCaml component. It changes the actual NSClipView viewport and checks
that both axes update OCaml, preserve off-anchor free scrolling and restore
rejected positions. Its free-scroll regression first failed because a requested
345-point horizontal offset was reset to 292 points; the renderer now preserves
that native observation. The runner requires successful exit and a PASS marker.
It is included in `make swift-test`.

These are application-local viewport and accessibility actions. They do not
establish physical mouse/trackpad gesture behavior, momentum/snapping physics,
iOS device behavior, VoiceOver, visual acceptance or maximum-size performance.
Those checks and the complete standalone Gallery remain outstanding. The iOS
build target is physical iOS 18+ arm64; Simulator is unsupported.

Optional `on_scroll` observes native movement independently from the controlled
item-position binding. See [ordered observations](swiftui-scroll.md#ordered-scroll-observations).
