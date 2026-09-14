# Viewport layout

A viewport requires a finite extent on its scroll axis. The OCaml API represents
that requirement with distinct opaque types: `Viewport.Vertical.t` requires
height, and `Viewport.Horizontal.t` requires width. `View.Scroll`,
`View.Collection` and `View.Scroll_sections` return these types. Ordinary
non-scrolling content has type `View.t`.

## Bounded application bodies

`Body.Vertical.fill` and `Body.Horizontal.fill` allocate the remaining finite
space among weighted children. `fixed` children use their intrinsic size.
The matching axis is checked by OCaml rather than supplied as a runtime option.

```ocaml
let feed =
  View.Collection.vertical
    ~catalog
    ~first_index
    ~items:keyed_items
    ~on_visible_range
    ()
in
let body =
  View.Body.Vertical.create
    [ View.Body.Vertical.fixed search_action
    ; View.Body.Vertical.fill feed
    ]
in
App.View.create ~theme ~body
```

The SwiftUI application window supplies the root proposal. Navigation and
presentation APIs consume `Body.t` where a finite body is required. Use
`Body.static` for ordinary content. `Body.overlay` retains the bounded base and
positions the overlay using native layout alignment.

## Explicit previews

Convert a viewport into ordinary content with a finite scroll-axis extent:

```ocaml
let preview =
  feed |> View.Viewport.Vertical.with_height ~height:240.
in
View.column [ heading; preview ]
```

Use `Viewport.Horizontal.with_width` for a horizontal viewport. These constructors
reject NaN, infinity, zero and negative values. A complete Body can be embedded
with `Body.with_size ~width ~height`. Gallery uses these boundaries for independent
interactive previews inside its page.

## Native ownership

Each collection has one SwiftUI viewport and one application catalog. Mixed
headers, rows and footers share its global index space. Stable keys retain
identity through window updates and catalog reorder. Initial position is an
explicit collection setting; the window's `first_index` only identifies its
materialized records. See [Virtual lists](virtual-lists.md).

Ordinary `Scroll` accepts a single eager view. Its `fill_viewport` option provides
a finite minimum so weighted content can fill spare space while longer content
still scrolls. `Scroll_sections` uses native lazy sections and supports pinned
headers/footers. Neither requires a separate sliver content type.

The native renderer uses bounded proposals and validates protocol properties
before publication. The compile-failure fixtures in `ocaml/test/viewport_compile`
verify invalid axis/ordinary-content combinations; native window tests verify
actual sizing, scrolling, resizing and retained identity. These checks do not
substitute for physical iOS or visual acceptance.
