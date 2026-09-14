# Virtual lists

`View.Collection.vertical` and `View.Collection.horizontal` materialize a bounded
window of keyed OCaml views inside one SwiftUI ScrollView. The application owns
records, declared extents, paging and window contents. SwiftUI owns native layout,
scrolling and extent animation. No synchronous row request crosses FFI.

## Catalog and window

A catalog defines ordered stable keys, one positive finite default extent,
sorted sparse extent overrides, overscan and animation durations. Reuse it while
only the visible window changes. Rebuild it when records, ordering or extents
change. The materialized items must match the catalog keys at `first_index`.

```ocaml
let catalog =
  View.Collection.Catalog.create
    ~keys:(Array.to_list (Array.map (fun row -> Key.string row.id) rows))
    ~default_extent:48.
    ~overrides:[ { View.Collection.index = 104; extent = 312. } ]
    ~overscan:4
    ~expand_duration_ms:240
    ~collapse_duration_ms:190
    ()
in
let window =
  View.Collection.Window.create
    ~catalog
    ~visible_first_index:visible_first
    ~visible_last_exclusive:visible_last
in
let items =
  List.init (window.last_exclusive - window.first_index) (fun offset ->
    let row = rows.(window.first_index + offset) in
    View.Keyed.create ~key:(Key.string row.id) (render_row row))
in
View.Collection.vertical
  ~catalog
  ~first_index:window.first_index
  ~items
  ~on_visible_range
  ()
```

This example assumes at least 105 records so override index 104 is valid.
Catalog construction validates unique keys, finite positive extents, ordered
unique override indexes and duration/overscan limits. `Window.create` validates
visible bounds, expands a nonempty range by overscan and clamps it to the
catalog. An empty visible range yields an empty window.

The initial materialized window may be empty. After mounting with finite geometry,
BonsaiSession requests the visible range through the presented OCaml handler.
Decode that payload with `View.Collection.visible_range_of_payload`, store its
half-open bounds and derive the next window. Overscan is an application window
policy; the payload itself is the visible range. Missing rows occupy their
logical geometry until the next application frame supplies them.

## Position, updates and animation

`Collection.Initial_position.Start`, `End` and `Item key` choose the initial
position explicitly. Later window updates preserve the current native viewport.
Catalog changes resolve the current leading key against the new order and retain
its intra-item offset; deleting that key selects a surviving neighbor and clamps
to the available extent.

Fixed and varied rows share the same catalog. Overrides affect geometry even when
the corresponding row is outside the materialized window. SwiftUI interpolates
declared extents locally, preserves the logical anchor and honors reduced motion.
Per-frame animation values do not cross FFI. Empty and short physical documents
retain at least the viewport extent, including horizontal RTL coordinates.

For mixed content, give headers, separators, ordinary padded content and footers
their own keys and extents in the same flattened sequence. A single global
visible range maps back to those application records. See the real
[Gallery mixed scene](swiftui-collections.md#mixed-content-in-one-catalog).

## Pagination and limits

Include a loading row in the catalog with a stable key while a request is in
flight. Recompute the window against the new catalog when a page arrives.
Unchanged overlapping keys retain node identity. Mail implements this policy
and rejects repeated tail requests for an in-flight load generation.

These are explicit-extent collections. Self-sizing measurement, Dynamic Type
invalidation, physical iOS interaction and performance acceptance remain
unfinished. Native pinned sections use `View.Scroll_sections`; the mixed catalog
does not claim virtual pinned headers. Ordinary eager content uses `View.Scroll`.

Both collection axes return a typed viewport. Embed them through a matching
`Body` allocation or an explicit finite extent; see [Viewport layout](viewport-layout.md).
[SwiftUI collections](swiftui-collections.md) records runtime and protocol evidence.
