# Windowed SwiftUI Collections

The selected virtual collection path uses a SwiftUI ScrollView with explicit
item geometry and an asynchronously supplied OCaml window on either axis. The public
`View.Collection` API, catalog/window wire nodes, retained controller and
BonsaiSession request scheduling are integrated. Gallery and the actual Mail
message-list component use the public catalog/window API. Gallery and Mail use native measured items. Mail retains declared estimates for
unloaded messages, while its visible rows follow intrinsic text and morphing
surface heights. Physical gesture acceptance remains unfinished.

## Native List experiment

`tool/probe_swiftui_list.swift` runs a reproducible macOS diagnostic with 10,000
rows, 40-point declared heights, a 420 by 600 point window, a jump to offset
300,000, and an offscreen row changing from 40 to 180 points. It uses a real
SwiftUI List and inspects the underlying native table without opening the
window. This is a geometry experiment, not a Mail app or screenshot substitute.

```sh
mkdir -p _build/probes/list
xcrun swiftc -parse-as-library -target arm64-apple-macos26.0 \
  tool/probe_swiftui_list.swift -o _build/probes/list/probe
_build/probes/list/probe
```

On macOS 26 with Xcode 26.1.1, the 24-point minimum case estimated unvisited
rows at 24 points: the measured document height was approximately 253,289
instead of 400,000. The jump reached the final estimated rows. Setting the
minimum to 40 made the fixed-height case exact: the document height was
400,000 and the visible range was 7,500 through 7,514. This is evidence that a
fixed minimum can align fixed-height rows, not that List never reports useful
scroll geometry.

The sparse-height case still failed the required explicit-extent contract.
After offscreen row 10 changed to 180 points, its cached table rectangle
remained 40 points high and row 5,000 retained offset 200,000 instead of the
new declared 200,140. The diagnostic also emitted an AppKit reentrant-delegate
warning; that warning is recorded but is not used as evidence that a visible
production List would crash. These measurements cover the tested SDK/OS and
headless native window, not every possible List implementation or iOS behavior.

For the virtual collection's deterministic sparse extents, use one explicit
layout path rather than depending on List estimates or introducing another
runtime renderer when those estimates differ. Native List/Form can still serve
separate nonvirtual semantic controls. Generic swipe actions will need their
own SwiftUI drag/scroll arbitration; this selection does not remove that
capability from the migration scope.

## Geometry and window ownership

`CollectionGeometry` stores a total row count, a positive finite default
extent and sorted unique sparse overrides. It checks bounds and rejects
unrepresentable totals. Prefix adjustments and binary searches map content
offsets to exact half-open visible ranges without constructing every row.
Overscan expands that range while remaining independent of total item count.

`CollectionViewport` records native geometry and a SwiftUI ScrollPosition.
`WindowedCollectionView` supplies the full scroll-axis extent to ScrollView, placing
only the provided rows at their exact logical offsets. Unloaded space does
not instantiate rows. In `Declared` sizing, row content must honor its exact
extent. In `Measured` sizing, those values estimate unloaded items and native
intrinsic measurements refine the materialized window.

SwiftUI exposes the native visible rectangle through
[onScrollGeometryChange](https://developer.apple.com/documentation/swiftui/view/onscrollgeometrychange(for:of:action:)).
The geometry callback only records native state. It does not call OCaml or
build row descriptions. BonsaiSession samples
that state at the runtime boundary after presentation and enforces displayed
node/revision ownership before sending a request. Only mounted collection
viewports with nonempty geometry participate. Rejected queue admission leaves
the request eligible for retry; a no-change response does not cause repeated
identical requests.

Metric changes preserve the top row and its intra-row offset. The owner can
supply a relocated index after resolving stable application identity. Appends,
viewport resizing, a removed tail and an empty collection clamp the offset
appropriately. The retained
collection controller resolves the anchor key in a changed catalog before
repositioning. Removing an earlier item therefore preserves the current item
and intra-row offset. An absent anchor prefers the next surviving old item,
then a previous survivor, before clamping an empty result. Mailbox-specific
anchors, navigation return and Mail expansion remain integration work.

Native window tests verify a jump to row 7,500 in a 10,000-row model, with 23
materialized rows at a 600-point viewport. They inspect actual row frames and
native content offsets, then verify offscreen expansion, appending 20 records,
resizing, anchor relocation and empty-state clamping. The tests use bounded
Swift fixture rows; they do not claim to render the Mail application.

## Public catalog and materialized window

`View.Collection.Catalog.create` takes ordered application keys, a default
`default_extent`, optional sorted sparse overrides (`{ index; extent }`), overscan,
and separate
expansion/collapse durations in milliseconds. The catalog is
immutable; keep it associated with the item/extent data revision and reuse it
when only the visible range changes. `Collection.Window.create` expands the
half-open visible range using that catalog, preserving an empty range as
empty. `Collection.vertical` and `Collection.horizontal` accept the catalog, first
index, keyed item views and the visible-range handler, returning the corresponding
typed viewport. Extents mean height vertically and width horizontally. The former
`default_height` argument and extent-record `height` field are removed.

The public constructor checks duplicate keys, extent bounds, finite positive
extents, unsigned 32-bit durations, overscan and materialized-key alignment. An integer key and the same
text as a string key remain distinct. Swift uses exact key bytes for identity,
so Unicode canonical equivalence cannot merge two protocol keys.

| Internal node | Properties | Ownership |
| --- | --- | --- |
| Collection catalog, node 7, mask 1023 | Ordered keys, default extent, sparse overrides, overscan, expand/collapse milliseconds, vertical axis flag, initial anchor, optional initial key and optional measurement revision | One visible-range binding and exactly one collection-window child. |
| Collection window, node 8, mask 3 | First index and materialized keys | One row subtree per key; no bindings; valid only under its catalog owner. |

The split avoids repeating the complete catalog on each scroll update. A
real-runtime test with 10,000 keys checks that the initial frame contains the
catalog, while a distant window update contains no catalog operation and is
under 16 KiB. Bounds, duplicate identities, invalid masks, key mismatches,
structural ownership and truncated catalog/window properties fail before publication.
OCaml property encode/decode round trips also cover both new nodes.

RenderTree retains the catalog controller and matching row nodes across
updates. Window changes preserve overlapping rows; an evicted row is disposed
and receives a fresh renderer identity on reentry. Clearing the visible window
makes its unfilled range eligible for another request. Removed collection
controllers cannot emit subsequent requests.

`Gallery.collection_component` exercises this path with 10,000 logical items
and remove-first-item and row-expansion actions. It starts with no row views, receives the
actual viewport request after the first presentation, and then materializes
19 rows for the initial 600-point viewport. Jumping to item 7,500 materializes
23 rows. The native host test verifies retained catalog/window objects,
row eviction/reentry, and the 40-point anchor correction after deleting the
first item. This is a real Gallery component; its test host is not a separate
Swift business-state implementation.

## Native sparse extent animation

`Catalog.create` accepts `expand_duration_ms` and `collapse_duration_ms`, both
zero by default. Expansion uses ease-out cubic and collapse uses ease-in-out
cubic. Swift interpolates only the union of old and new sparse overrides.
Each changed row uses the duration for its direction, so collapsing one row
and expanding another can finish independently. Retargeting starts at the
currently displayed extents rather than the previous target. Completion
installs the exact validated target geometry, with no residual overrides.

A SwiftUI-owned task samples the transition locally; no animation sample calls
FFI. It retains a logical leading-item anchor to avoid accumulating native pixel
rounding errors. User scrolling updates that anchor through the native scroll
phase and geometry callbacks. Apple distinguishes user interaction/deceleration
from programmatic animation in [ScrollPhase](https://developer.apple.com/documentation/swiftui/scrollphase).
Rapid real gestures and accessibility scrolling still require acceptance tests.

Changing keys, count, axis or default extent resolves immediately, with stable-key
relocation handled by the controller. Zero duration, reduced motion, view
removal, session deactivation/hiding and disposal also resolve to the target.
An unrepresentable intermediate geometry resolves to the validated target.
An interrupted task cannot install an obsolete target. The current sampling
task is not evidence that the required foreground display-driver work is done.

Native window tests cover offscreen expansion above the anchor, reversal,
exact final offsets, reduced motion and removal. A real Gallery integration
test commits the OCaml expansion target, then withholds further pumps and its
presentation acknowledgment while Swift completes the animation. It also
checks collapse and immediate settlement on session inactivity/visibility
changes. This proves local interpolation across the actual public protocol;
it does not prove Mail's complete morphing surfaces or physical-device gestures.

## Actual OCaml Mail boundary

The native test library now embeds the actual `Mail.app`. Swift encodes
`Visible_range_changed` events through the production C boundary. Consecutive
range requests coalesce only within the same node, handler and displayed
revision; button/input events retain ordering barriers. Invalid negative
ranges fail admission. Frame-size and queue-count budgets remain enforced.

The real-runtime test observes these application results:

- The initial 20 rows narrow to 11 materialized rows for visible range `[0, 7)`
  with four rows of overscan.
- Coalesced bottom-range intent `[13, 20)` produces 12 materialized rows,
  including the loading row, out of 21 logical rows.
- At 700 ms the page is still loading; at 800 ms there are 40 messages and 15
  materialized rows. Advancing the clock again does not append another page.

Mail now publishes the production catalog/window nodes with 240 ms expansion
and 190 ms collapse. Its catalog is reused while only the painted range
changes. A loading row contributes its own stable key; mailbox-specific owner
keys prevent accidental reuse of a different mailbox's native collection.
The OCaml tests verify ordered catalog/window keys through paging and archive,
retained overlap identity, three sequential pages, accordion expansion and
cleanup after actions and filtering.

The Mail boundary test calls the production catalog/window decoders and checks
that a range-only update does not repeat the catalog. Mail's complete tree now
stages in Swift and its standalone native window passes expansion and Archive
through OCaml. Separate Gallery tests verify BonsaiSession scheduling and native
scrolling/animation. Complete screenshots and physical-device acceptance remain
unfinished.

## Remaining acceptance work

Mail has moved to the public collection path. Mail detail, Clock and Todo use
[ordinary SwiftUI scroll containers](swiftui-scroll.md) for eager content.
The old Sliver/Scroll_view constructors, OCaml codecs and schema declarations
are removed. No compatibility aliases or old protocol decoders remain in the
OCaml/SwiftUI path. The legacy Flutter source trees have been removed. Declared
sparse extents and measured Mail content transitions run natively; physical
interaction acceptance remains incomplete.

Self-sizing measurement and cache invalidation now have native width and Dynamic
Type coverage. The actual Mail window passes a 560-to-340-point column change,
expansion/collapse and Archive checks on macOS. A hosted test on a physical
iPhone verifies row growth at accessibility Dynamic Type sizes, shrinkage after
restoring standard text, and the top scroll position. These checks do not cover
rapid gesture/request races, generic swipe actions, scroll restoration, or all
accessibility and keyboard behavior. Physical interaction acceptance remains
open; hosted-test screenshots are distinct from system UI automation evidence.

## Horizontal collections and resize anchors

Both directions use the same geometry, key-index map, bounded window and sparse
transition implementation. SwiftUI's Layout places each loaded item at its exact
scroll-axis offset and proposes its declared extent. The cross-axis proposal comes
from the enclosing layout; there is no fixed 320-point width fallback. Use a
bounded Body/Viewport slot, including a cross-axis frame for a shrink-wrapped
Gallery preview when necessary.

Horizontal coordinates and scroll positions are logical leading-edge coordinates.
SwiftUI automatically mirrors custom Layout placement in RTL, so the renderer
does not also mirror item positions. See Apple's
[layout direction documentation](https://developer.apple.com/documentation/swiftui/layoutdirection).
The native tests verify the physical document rectangles against logical offsets
in both LTR and RTL, including unloaded space before a distant materialized window.

A point-based [ScrollPosition](https://developer.apple.com/documentation/swiftui/scrollposition)
does not promise to retain an exact offset when container dimensions change.
The viewport therefore preserves its leading logical item when the scroll-axis
viewport extent changes outside user scrolling. It clamps the restored offset to
the new content bounds. The RTL regression initially shifted a 40-point catalog
from item 100 to item 95 when the window widened by 200 points; it now retains
item 100 and the same seven-point intra-item offset in actual native geometry.

All native viewport scenarios run on both axes in LTR and RTL: jumping to item
7,500 in 10,000 items, realizing only 23 rows for the 40-point/600-point fixture,
offscreen expansion, animation interruption, reduced motion, paging, resizing,
key relocation and empty-state clamping. Axis updates retain the catalog
controller, viewport and logical anchor. Invalid direction flags and the retired
six-property mask 63 are rejected atomically.

Gallery includes an additional horizontal catalog with 120-point items and a
400-point expanded item. The real OCaml window test starts empty, receives the
first presented visible range, loads nine items, jumps to item 7,500 with thirteen
loaded items, deletes the first key with a 120-point anchor correction, and
verifies eviction/reentry. The actual Gallery extent-animation test runs both
axes and directions, observes the OCaml target and verifies that interpolation
continues without another OCaml frame, then settles on session inactivity/hiding.
Mail keeps a vertical catalog; its call sites and tests use the new extent names.

- `swift test --scratch-path _build/swift --filter Collection`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`

This completes the horizontal fixed/sparse window path at the tested macOS
runtime and source-level iOS boundary. Self-sizing,
physical iOS gestures/VoiceOver/performance and required screenshots remain open.

Optional `on_scroll` reports native movement independently from visible-range
materialization. See [ordered observations](swiftui-scroll.md#ordered-scroll-observations).

Ordinary content can fill the available viewport through
[`Scroll.fill_viewport`](swiftui-scroll.md#filling-a-viewport-with-ordinary-content),
composed with Weighted items. This does not add a virtual section fill policy.

## Initial collection positions

Both Collection axes accept `initial_position`, defaulting to
`Collection.Initial_position.Start`. `End` starts at the final clamped viewport;
`Item key` places that catalog item at the logical leading edge where the
available scroll extent permits. The key must belong to the supplied catalog;
unknown keys are rejected before rendering. Keys use the catalog's canonical
encoding, and sparse extents participate in the initial coordinate calculation.
The OCaml catalog retains its private key membership table, so validating an
initial key does not scan the full catalog on every window render.

The container owns this explicit initial choice. The materialized window's
`first_index` describes its rows and does not implicitly select a scroll position.
The native controller initializes ScrollPosition from the catalog before the
viewport mounts. End uses the full logical extent and native clamping; an item
uses its prefix extent. The first actual visible-range request therefore already
names the selected region. Initial settings are read only when the controller is
created; later settings changes preserve the viewport and in-flight sparse
geometry animation. Catalog/data changes continue to retain the current stable
key rather than reapplying the initial position. An empty catalog at creation has
zero initial extent; End does not defer a jump until later data arrives.

Node 7 adds `initial_anchor` (Start=0, End=1, Item=2) and `initial_key` (present
exactly for Item), bringing its property mask to 511. Invalid combinations,
unknown keys and previous masks are rejected atomically. The window node is
unchanged. Runtime tests initialize a 10,000-item sparse catalog at the start,
end and key 7,500, verify its first requested window and actual native coordinate,
and keep fewer than 200 rendered nodes in each test scene. They also change the
initial configuration, append data, resize, hide/resume and retain the same
native viewport. Separate tests preserve an active extent animation when only
initial metadata changes.

## Mixed content in one catalog

`examples/gallery/ocaml/mixed_collection_catalog.ml` composes 3,000 fixed rows,
7,000 varied rows and ordinary header/interlude/footer content in one keyed
catalog. The application flattens its groups into a shared index space and
resolves the one global visible range into records. Headers and footers contain
GroupBox actions; the interlude contains a Divider and Text; padding is ordinary
row content. Each item has an explicit extent. This composition introduces no
Sliver renderer or independently scrolling child viewport.

Catalog construction depends only on topology and extent state, so scrolling
reuses the same catalog. Group reorder and header deletion relocate the
application window by stable key while the native controller retains its
leading item and intra-item offset. One catalog declares one animation policy.
Pinned section headers remain a separate Scroll_sections capability; this scene
does not establish pinned headers inside a virtual catalog or self-sizing rows.

The real-runtime test starts with 10,003 catalog items and no materialized rows.
It jumps to item 7,500, expands an offscreen row, resizes/removes the header,
swaps groups, resizes the window, crosses the interlude, activates the footer,
then clears and restores content. Both axes and LTR/RTL retain one native
viewport, stable overlapping row identity and fewer than 64 materialized items.
Evicted header actions are rejected. The wire test sends a distant visible range
through the native runtime and verifies that the subsequent frame updates the
window without republishing the catalog; that frame is smaller than 16 KiB.

The initial bounded-window regression hung while restoring an empty horizontal
RTL catalog. A separate SwiftUI App reproduced the same failure, timing out
after 30 seconds while its other three direction combinations passed. Native
geometry observations showed an invalid zero-width RTL document and an abnormal
visible rectangle after restoration. `WindowedCollectionView` now obtains the
finite viewport size with GeometryReader and gives content that minimum extent.
The logical catalog remains empty when there are no records; its physical
document still has a valid leading coordinate. All four App cases now restore
the header and activate it through the real OCaml handler.

```sh
swift test --scratch-path _build/swift --filter mixed
python3 native/test/test_mixed_collection_window.py
```

These are macOS runtime and native accessibility-action checks, not physical
pointer/keyboard, iOS or screenshot acceptance. The old Sliver and Scroll_view
constructors, driver mappings and protocol paths have now been removed; retired
node IDs are rejected. Their meaningful identity, range and key checks now use
Collection, and eager-content/body checks use Scroll.

## Native measured sizing

`Catalog.create ~sizing:(Measured { revision })` selects intrinsic measurement
within the same windowed ScrollView. Omitted sizing is `Declared`. The supplied
positive default and sparse extents remain estimates for unloaded items; gaps
contain no interactive views. Materialized content must have a finite positive
intrinsic extent on the scroll axis. Prefer minimum dimensions over scroll-axis
fill for adaptive rows.

The native cache stores measured extents by exact key bytes, preserving them
through reordering and dropping removed keys. A changed declared estimate for a
key invalidates its cached measurement. Change the nonnegative measurement
revision whenever content changes can invalidate offscreen sizes. A changed
cross-axis viewport size, Dynamic Type category, layout direction, scoped font
family or axis automatically discards the cache. Only actual context changes
advance the context token. Unrelated commits and window slides preserve retained
rows. Each native mount has its own token, combined with the full row identity;
evicted or remounted rows cannot submit stale samples. Cached extents survive
virtualization and append-only paging when existing sizing inputs are unchanged.
The mount UUID is created on first appearance from a stable empty State value.
Constructing a new UUID in the view initializer would invalidate retained
measurement wrappers whenever the parent supplies a new row window. Samples
are accepted after the mount token is available; appearance and context changes
replay the latest matching sample so the first measurement is not lost.

Measured updates restore the leading stable key and intra-item offset while
SwiftUI settles its geometry. Native ScrollPosition writeback is observed
without publishing another programmatic scroll, avoiding a layout feedback
loop when content shrinks. A new explicit scroll command or user scroll takes
ownership from the pending measurement anchor. Changed samples are validated and
published in one scheduled main-actor batch. Equal samples publish nothing.
Measurements and context changes preserve the last accepted handler/range.
They request a new window only when the resulting visible range or handler
changes; clearing an unfilled visible window still permits a retry.
Scroll commands are issued only when the effective display-pixel position changes;
RTL document growth is included in that comparison. Initial row measurements are
immediate; subsequent active-row extent changes use the collection timing. The
collection is the sole owner of extent interpolation for active-content surfaces.
Neither layout nor measurement calls OCaml synchronously.

`MeasuredCollectionTests` checks native offsets in a 10,000-item vertical
collection after narrowing the window, enlarging the font, replacing long text
with short text and switching to exact declared extents. Actual Gallery tests
exercise OCaml catalog encoding, native measurement, asynchronous bounded row
materialization, a jump to item 5,000 and deletion before that item on both axes
and in LTR/RTL. Cache tests cover stale attachment/context tokens and aggregate coordinate
overflow. These are macOS tests; the larger font is supplied explicitly and is
not evidence of physical iOS Dynamic Type behavior.

### Adaptive Mail rows

Mail uses measured sizing with a content revision. Read/star changes, expanded
content and notices invalidate cached content sizes; range-only updates reuse
the catalog. A separate revision bit tracks the accessibility row layout so
sizes measured before the host environment update cannot remain cached.

The compact row, expanded header, outline lines, notice and footer use minimum
heights. Outline text wraps. MorphingSurface supplies interpolated intrinsic
heights during expansion/collapse, which the collection measures while retaining
the leading item. The native window test adjusts the actual AppKit column
divider from 560 to 340 points, then checks wrapping, retained identity, collapse,
re-expansion and Archive in both host appearances.

At a body-text scale of 1.5 or greater, Mail moves the timestamp below the
message text, permits two subject/preview lines and removes the redundant avatar
from each row. The host environment changes the OCaml layout; SwiftUI owns font
scaling and actual measurement. This keeps the star action available while giving
message text more width.
