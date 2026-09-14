# Native Scroll Sections and Collapsing Headers

`View.Scroll_sections` composes keyed sections in a native SwiftUI ScrollView
with LazyVStack or LazyHStack and actual Section headers and footers. Both
axes return typed viewports and require a bounded Body slot. The API replaces
Sliver AppBar and PreferredSize; their constructors and wire nodes 38/39 are
removed. Windowed fixed/varied and mixed-content capabilities now use
[Collection](virtual-lists.md); there is no remaining Sliver compatibility path.

## Composition

```ocaml
let content =
  View.Scroll_sections.vertical ~pin_headers:true
    [ View.Scroll_sections.hero ~key:(Key.string "expanded-header")
        ~height:200. ~stretch:true expanded_content
    ; View.Scroll_sections.section ~key:(Key.string "messages")
        ~header:collapsed_title_and_bottom_controls keyed_rows
    ]
in
View.Body.Vertical.create [View.Body.Vertical.fill content]
```

A normal section accepts optional header and footer views followed by keyed
rows. The header and footer occupy stable, unkeyed wrapper slots so row keys
cannot collide with a header's own application key. Reordering rows preserves
logical and rendered node identity. Section keys must be unique in the container;
row keys must be unique in their section. There are at most 1,024 sections.
Spacing is finite and nonnegative. Pinning defaults to false; indicators default
to true. Empty containers and sections are allowed.

Pinned headers occupy the top of a vertical viewport or the leading edge of a
horizontal viewport. Pinned footers occupy the bottom or trailing edge. These
are native Section behaviors, including RTL adaptation; see Apple's
[lazy stack section documentation](https://developer.apple.com/documentation/swiftui/grouping-data-with-lazy-stack-views).
Applications provide their own opaque backgrounds for overlapping pinned content.
A section footer is distinct from an AppBar's bottom controls: put controls that
must stay at the top together with the collapsed title in the section header.

The optional hero is a single ordinary subtree with a finite positive height.
It must be the first section of a vertical container and has no header or footer.
It naturally scrolls away as the following section header reaches the top. To
pin only bottom controls, put the title in the hero and the controls in the
section header. Navigation commands continue to use native Toolbar placements.

Stretching uses SwiftUI visualEffect and native scroll geometry. During leading
overscroll, scaling about the hero's bottom fills the extra space above it.
The geometry stays within SwiftUI and does not send an OCaml event every frame.
Reduce Motion disables this elastic effect. This is custom native composition;
there are no floating, snap, force-elevated or preferred-size compatibility flags.
Actual elastic overscroll, Reduce Motion appearance and physical iOS behavior
still require visual/device acceptance.

## Ownership and transport

Node 75 carries vertical, pin_headers, pin_footers, spacing and shows_indicators,
with update mask 63, including the initial Start/End anchor. Node 76 carries has_header, has_footer, optional hero_height
and stretch, with mask 15. The container permits the optional Scroll_notification binding;
individual sections have no events. Each section is directly
owned by one section container; a hero has exactly three child slots, and a
normal section has at least its header/footer slots. Atomic staging rejects
invalid masks, values, truncation, ownership, placement and child structure.

Ordinary native controls own actions. Changes to a section's configuration or
children reject callbacks from the previous presentation until the new frame is
presented. Removed headers cannot act after being recreated. Hidden and closed
sessions reject actions. This uses the existing session presentation boundary.

## Catalog and verification

Gallery's outer scrolling header now uses this API. Scroll_sections_catalog
also provides bounded vertical and horizontal previews and the actual OCaml
native-sections/native-sections-horizontal test entrypoints. Controls change
hero height, stretch, pinning, header presence and row order, with independent
header/footer actions and model counters.

The native window test covers both axes in LTR and RTL. It measures actual
accessibility rectangles against the native scroll viewport after scrolling,
checks a 40-point hero height increase, executes header/footer actions, reverses
rows, toggles pinning, removes and recreates headers, and resizes the window.
It checks native ScrollView and logical node retention, stale callbacks before
presentation, hidden sessions and shutdown. These tests establish measured macOS
layout and event behavior, not runtime screenshots or physical elastic gestures.

- `swift test --scratch-path _build/swift --filter ScrollSectionsTests`
- `swift test --scratch-path _build/swift --filter actualSections`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`

The OCaml public API test covers stable header slots, duplicate keys, invalid
spacing and hero placement/heights. The protocol regression embeds valid retired
frames and requires Unknown_node_kind. The new generated OCaml fixture contains
section-container and hero updates. Other remaining widgets, the standalone
Gallery, full Flutter deletion and required Mail screenshots remain unfinished.

Optional `on_scroll` observes this container directly without binding its individual
sections. See [ordered observations](swiftui-scroll.md#ordered-scroll-observations)
for payloads, lifecycle and queue semantics.

Ordinary content can fill the available viewport through
[`Scroll.fill_viewport`](swiftui-scroll.md#filling-a-viewport-with-ordinary-content),
composed with Weighted items. This does not add a virtual section fill policy.

The optional `initial_anchor` shares [Scroll initial-position semantics](swiftui-scroll.md#initial-positioning-and-retained-offsets).
Changing the initial option does not scroll an established viewport. Native
position correction preserves the logical leading offset on viewport resize;
section content changes continue to use SwiftUI keyed anchoring.
