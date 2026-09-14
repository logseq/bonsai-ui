# Restore Sliver App Bar Bottom Slot

## Problem

Applications need to place an arbitrary widget below the header toolbar, such
as tabs, filters, or a secondary control row. That widget must participate in
the app bar's layout and scrolling behavior. The current scrolling app-bar
contract has no bottom child slot, so applications cannot express this header.

The [Expressive integration decision](../../implemented/feature/2026-09-03-integrate-material-3-expressive-components.md)
replaced the original sliver app bar with `M3EAppBar.sliver` and explicitly
removed bottom, flexible-space, and geometry controls. The subsequent
[Material ownership decision](../../implemented/architecture/2026-09-04-material-only-overlapping-components.md)
moved the public constructor to `Material.App_bar.sliver`.

Current evidence:

- `ocaml/ui/material.mli` exposes title, leading, actions, scroll flags,
  colors, semantics, and Expressive variant/shape/density, but no bottom slot.
- `ocaml/ui/widget.mli` and `protocol/schema.sexp` encode the same restricted
  sliver-app-bar contract.
- `_buildSliverAppBar` in
  `flutter/packages/bonsai_flutter/lib/src/renderer/widget_registry.dart`
  passes only leading, title, and actions to `M3EAppBar.sliver`.
- The pinned dependency is `material_3_expressive: 1.1.1`. Its
  `lib/components/app_bars/m3e_app_bars.dart` defines `M3EAppBar.sliver`
  without a bottom parameter. Its internal `SliverAppBar` construction also
  omits bottom. This is a limitation of the installed component API, not a
  claim that the Material 3 design system prohibits secondary header content.
- Flutter's [SliverAppBar.bottom contract](https://api.flutter.dev/flutter/material/SliverAppBar/bottom.html)
  explicitly supports a widget below the toolbar through `PreferredSizeWidget`.

`Material.App_bar.bottom` is a separate bottom app bar. It does not represent
the bottom slot of a scrolling header and does not solve this problem.

## Decision

Replace the renderer behind `Material.App_bar.sliver` with Flutter's native
`SliverAppBar`, restore all previously removed native app-bar capabilities,
and provide optional bottom content that pins independently of the toolbar.
Keep public ownership in `Material.App_bar` and the result type
`Widget.Sliver.t`; do not resurrect `Widget.Sliver.app_bar`.

The agreed scope is to replace only `.sliver`, restore the full former
capability set, and pin bottom content independently. This proposal defines
the required behavior and implementation acceptance criteria.

### Bottom content and layout

Represent bottom content as one optional value pairing a `Widget.t` with a
finite, positive height in logical pixels. Absence means no bottom content and
no reserved bottom height. The height describes the content below the toolbar,
excluding the toolbar and top system inset.

Carry presence and height in logical and wire props, and carry the widget as
a normal retained child. Define child order explicitly as optional leading,
title, actions, optional flexible space, then optional bottom. Parse exactly
`action_count` action children so neither additional slot becomes an action.
Track flexible-space presence separately from bottom presence.

Bottom is a logical slot of `Material.App_bar.sliver`, but must render as a
separately pinned header after the native `SliverAppBar`. Passing it only to
`SliverAppBar.bottom` does not provide the requested independence. Use the
explicit height to size the secondary header; do not depend on a retained
child host exposing a descendant's `PreferredSizeWidget` runtime type.

The selected behavior is:

- Bottom starts directly below the toolbar/expanded app-bar region and scrolls
  naturally until it reaches its pin position.
- With `pinned = false`, the toolbar may scroll away while bottom stays pinned
  at the viewport's usable top edge.
- With `pinned = true`, bottom pins immediately below the retained toolbar.
  Toolbar pinning does not control whether bottom itself remains visible.
- Floating or snapping toolbar re-entry must keep bottom below the currently
  visible toolbar without overlap or duplicate space. Bottom does not inherit
  the toolbar's floating/snap flags.
- Bottom remains pinned while the following page content scrolls. It must not
  disappear merely because the app-bar region has scrolled out of view.
- Top system insets are accounted for once. Flexible space and stretch affect
  the native app-bar region, not the fixed height of the secondary header.

The proposed renderer composition is a native `SliverAppBar` followed by a
fixed-extent `SliverPersistentHeader(pinned: true)`, with coordination for the
visible toolbar offset. Flutter documents the persistent header's
[pinning behavior](https://api.flutter.dev/flutter/widgets/SliverPersistentHeader/pinned.html).
The current `_buildScrollView` forwards one widget per logical sliver to
`CustomScrollView`, so presenting this logical node as two coordinated slivers
needs an explicit renderer composition design. Preserve the public
`Widget.Sliver.t` result and retained child ownership while designing that
integration, including use through existing sliver wrappers.

Do not assume that wrapping only the app bar and secondary header in
`SliverMainAxisGroup` solves composition. Flutter
[bounds pinned children to the group's extent](https://api.flutter.dev/flutter/widgets/SliverMainAxisGroup-class.html),
which would let this short group scroll away before the following page content.
Validate the composition in a focused layout prototype as the first
implementation step. The prototype must establish pinning beyond the app-bar
extent, toolbar-offset coordination, and retained ownership through supported
sliver wrappers before the full API and protocol changes are implemented.

Dynamic content and height updates must update the retained header without
recreating the scroll view. Automatic bottom-height measurement is out of scope.

### Native API and replacement scope

Retain title, leading, actions, center-title, colors, semantic label, and
`pinned`/`floating`/`snap`. Keep the current scroll defaults (`pinned = true`,
`floating = false`, `snap = false`) and reject snap without floating.

Remove Expressive-only `sliver_variant`, `sliver_shape`, and `sliver_density`
types, constructor arguments, wire fields, mappings, and obsolete assertions.
Do not silently reinterpret these options as native geometry settings.

Restore the complete former native capability set. The historical public
signature at `6205faf^:ocaml/ui/widget.mli` includes the following controls
removed by the Expressive replacement:

- `expanded_height`, `collapsed_height`, and `toolbar_height`;
- `flexible_space` and bottom content;
- `stretch`;
- `force_elevated` and `elevation`;
- `automatically_imply_leading`.

Restore these alongside the retained title, leading, actions, colors, semantics,
and scrolling options. This restores capabilities under `Material.App_bar.sliver`,
not the deleted generic namespace or old wire decoder. Bottom uses the selected
independent-pinning semantics and explicit-height representation rather than
the old toolbar-coupled behavior.

Expanded/collapsed heights describe only the native app-bar region, excluding
the independently pinned bottom height. Follow Flutter's inset conventions
and account for bottom height exactly once in the combined scrolling layout.
Native default geometry replaces the Expressive medium default when explicit
geometry is absent.

Restore the validation invariants recorded in the
[construction-validation decision](../../implemented/bugfix/2026-08-20-sliver-app-bar-construction-validation.md):
finite positive toolbar height; finite non-negative optional expanded/collapsed
heights and elevation; collapsed height at least toolbar height; collapsed
height no greater than expanded height when both are supplied; and snap only
with floating. Apply additional effective-geometry checks required by the native
constructor consistently across public construction, codecs, and rendering.
Replace the former requirement that bottom be a `Widget.preferred_size` node
with the explicit bottom content/height contract above.

Limit this replacement to `Material.App_bar.sliver`. The top, bottom, and
search constructors and other Expressive components remain outside the
selected scope. A scrolling header belongs in the scroll view's sliver
sequence; `Material.scaffold`'s fixed app-bar slot is not a sliver host.

### Affected implementation surfaces

- Public and private OCaml construction in `ocaml/ui/material.ml`,
  `ocaml/ui/material.mli`, `ocaml/ui/widget.ml`, and `ocaml/ui/widget.mli`.
- Wire records and codec validation in `ocaml/protocol/`, plus
  `protocol/schema.sexp` and its generated IDs, documentation, and fixtures.
- Dart props and binary codec in
  `flutter/packages/bonsai_flutter/lib/src/protocol/`, and the renderer's
  sliver-app-bar builder, child validation, retained node hosting, and scroll-view
  composition needed for independently pinned bottom content.
- OCaml constructor/protocol tests, Flutter codec and sliver-app-bar tests,
  maintained examples, and current API documentation.

Make the replacement a breaking API and wire-contract change using the
repository's protocol-version policy. Remove obsolete paths rather than
adding aliases, fallback rendering, legacy decoders, or migrations. Preserve
the sliver-app-bar node's identity; do not reuse retired field IDs for unrelated
semantics. The earlier decisions remain historical records; this decision
supersedes their Expressive sliver-renderer choice while retaining Material
namespace ownership.

This proposal requires no changes to files under `ocaml/spec/` or dune files.
If development encounters an unclear or unreasonable spec interface, stop and
report the precise issue and suggested amendment. After an implementation
commit and push, update
the iOS SDK repository from that pushed commit and commit/push its generated
update separately, as required by the repository workflow.

## Alternatives considered

### Extend or fork M3EAppBar

Add bottom forwarding to the dependency. This could retain Expressive geometry,
but introduces dependency maintenance for a capability already available in
native Flutter. It also conflicts with the requested direction of returning
to SliverAppBar.

### Attach bottom directly to SliverAppBar.bottom

This restores a secondary row with simpler native extent handling, but couples
its visibility to the app bar. The user selected independent pinning, so this
does not satisfy the required behavior.

### Add a non-pinned following sliver

This places content below the header but lets it scroll away. The selected
secondary header must remain pinned independently.

### Restore only bottom content and height

This reduces geometry work but omits the full native customization requested
by the user. Expanded/collapsed geometry, flexible space, stretch, elevation,
and automatic leading must be restored in the same change.

## Acceptance criteria

- A `Material.App_bar.sliver` can render arbitrary interactive bottom content
  below its toolbar in a scroll view, with correct height and no overlap.
- Leading, title, multiple actions, flexible space, and bottom coexist with
  deterministic child ownership. Omitting either optional slot reserves no
  space for that slot.
- With an unpinned toolbar, scrolling well beyond the app-bar region leaves
  bottom visible and interactive while the toolbar is offscreen.
- With a pinned toolbar, bottom remains directly below it. Floating/snap
  re-entry does not overlap bottom or introduce duplicate space. Verify top
  insets, long page content, and supported sliver wrappers.
- Expanded/collapsed height, toolbar height, flexible space, stretch,
  force-elevated, elevation, and automatic leading all reach the native
  `SliverAppBar` and produce their documented behavior.
- Adding, removing, replacing, and resizing bottom content through retained
  updates preserves the scroll position and functioning child event handlers.
- Invalid heights, invalid height ordering, invalid elevation, malformed child
  counts, and snap without floating are
  rejected at the applicable constructor, wire, and renderer boundaries.
- OCaml/Dart round trips and incremental prop updates agree on presence,
  height, all restored properties, and child order. Generated protocol
  artifacts match the schema.
- Tests verify native `SliverAppBar` rendering without an `M3EAppBar` wrapper,
  and retain the existing sliver-shaped error-boundary regression coverage.
- Removed Expressive sliver options have no remaining active consumers or
  compatibility paths. Tests and documentation describe the chosen native API.

## Risks

- Native defaults change header height, shape, typography, and collapse visuals
  relative to the existing medium Expressive default. Screens must be reviewed
  in expanded and collapsed states.
- Explicit height is predictable across the protocol, but callers must update
  it when bottom layout requirements change, including text scaling or wrapping.
- Incorrect child slicing or extent accounting can turn bottom content into an
  action, clip controls, or cause jumps while scrolling.
- Independent pinning requires coordination beyond replacing one constructor.
  A short sliver group, floating-toolbar overlap, or incorrect retained-host
  expansion can break pinning after scrolling past the header. Resolve these
  through a focused layout prototype before implementing the full contract.
- Native sliver and Expressive fixed app bars may look different within the
  same application. Replacing the other constructors would be a separate scope
  decision.
- Removing Expressive options and changing the wire contract requires current
  producers and hosts to be rebuilt together.

## Scope decision

All product questions were answered by the user on 2026-09-05.

1. **Replacement scope:** Replace only `Material.App_bar.sliver`. Keep `.top`,
   `.bottom`, and `.search` unchanged.
2. **Restored capability scope:** Restore all former native SliverAppBar
   capabilities, including expanded/collapsed height, toolbar height, flexible
   space, stretch, forced elevation, elevation, and automatic leading.
3. **Bottom scrolling behavior:** Pin bottom independently of the toolbar.
   Do not implement it solely as the native app bar's coupled bottom slot.

No product-scope questions remain open. Validate the renderer composition and
toolbar-offset coordination during the first implementation step against this
proposal's acceptance criteria.


## Consequences

Implemented on 2026-09-05. `Material.App_bar.sliver` now accepts
`?bottom:(Widget.t * float)` and all native controls listed above. The retained
logical and wire node remain kind 38. Protocol 3.0 removes the Expressive fields,
reserves their IDs, and assigns restored fields IDs 24–33. Native ABI remains
2.0; the native bridge and Dart loading gate both require protocol 3.0. The
obsolete version-dependent value-only Text decoder was removed when the major
version changed. Generated OCaml/Dart IDs, documentation, and both fixture
families use the new version, including an OCaml app-bar fixture verified by
Dart with byte-for-byte re-encoding.

The layout prototype was validated before the full API/protocol implementation.
The production `SliverAppBarHost` exposes one render sliver to the retained host
and viewport, containing the native toolbar and optional fixed-height pinned
persistent header. It reuses the render group's child ownership, transforms,
painting, and hit testing, but replaces the layout that would bound pinned
children to the group's scroll extent. The bottom receives the toolbar's
current painted edge as overlap, including floating/snap animation frames.
Negative viewport overlap reaches the native toolbar for stretch, while the
bottom's fixed height remains unchanged. Combined obstruction includes the
usable-top inset exactly once, including programmatic reveal after an unpinned
toolbar leaves. The composition remains stable when bottom is added or removed.
No scroll-view flattening, duplicate retained hosts, or short bounded sliver
group is used.

Regression coverage establishes long-page pinning, inset handling, floating/snap
coordination, independent stretch geometry, programmatic reveal, retained
ownership through horizontal/vertical sliver padding, action/slot slicing,
height changes, child replacement/removal/addition, event delivery, and
sliver-shaped error recovery. Constructor, codec, reconciliation, and renderer
checks cover native properties and invalid geometry. The gallery and catalog
consumers now demonstrate the native API. No spec or Dune files changed.

Validation passed: `dune build @all`, `dune runtest`, viewport compile checks,
`dune build @fmt`, schema and fixture regeneration checks, complete Flutter and
native package tests, both package analyzers, and gallery build/tests using the
uncommitted framework's Dune install tree through `OCAMLPATH`.

## Questions

None. Implementation follows the three scope decisions above. Source and SDK
commit/push sequencing remains the repository workflow described above.
