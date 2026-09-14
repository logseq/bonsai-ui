# Virtual Sliver Window Ownership Contract

## Problem

The virtual sliver API exposes `overscan`, `first_index`, `items`, and a pure
visible-range callback, but it does not make ownership of the materialized OCaml
window explicit. Flutter never requests an individual item synchronously. It
builds supplied children and renders `SizedBox.shrink()` for logical indexes
outside that window. The application must receive a visible range, expand it,
bound it to `total_count`, and rebuild the keyed item window quickly enough.

`overscan` currently influences viewport cache pixels, but it does not
automatically expand the OCaml `items` window. A caller can reasonably assume
that passing `~overscan:4` makes the framework retain four logical items on
each side, leading to empty placeholders during fast scrolling. Different
consumers implement different window arithmetic and initial-window policies.

## Decision

`visible_range_changed` remains semantically pure: it reports only the logical
range currently painted by the sliver. Formalize the separate materialized
window as an OCaml-owned policy through one public pure helper.

`Widget.Sliver.Window.create` accepts `total_count`, an overscan
count, and a visible range, and returns a bounded half-open materialization
range. Its contract includes empty collections, leading and trailing clamps,
and stable overlap. Consumers use the same overscan value for cache derivation
and materialization policy instead of duplicating arithmetic.

The maintained API documentation distinguishes three states:

- logical collection: `total_count`;
- painted range: emitted by `visible_range_changed`;
- materialized range: `first_index` plus the supplied keyed `items`.

Consumers must supply a useful initial materialized window before
the first event and must treat later range events as catch-up requests. Update
the canonical mail example uses the helper and includes a continuation row in
the logical window. Flutter does not synchronously call OCaml for rows.

## Alternatives considered

### Include overscan in `visible_range_changed`

That makes an event named visible range report non-visible items, couples event
semantics to a rendering policy, and still cannot guarantee that a pixel cache
corresponds to a fixed number of varied-extent items.

### Let Flutter request individual rows across FFI

Synchronous row construction would violate the retained-frame architecture and
put application logic on the renderer's layout path.

### Documentation only

Documentation explains ownership but leaves every consumer to reimplement
boundary arithmetic. A small pure helper creates one tested contract without
moving application state into the framework.

## Consequences

- The public interface exposes `Widget.Sliver.Window` without renderer or
  protocol types, and pure OCaml tests cover empty, boundary, middle, and large
  overscan ranges.
- The canonical mail consumer uses the helper for initial and catch-up windows;
  its keyed overlap test verifies identity across an update.
- Maintained documentation explicitly separates painted and materialized
  ranges and states that `overscan` does not fetch or create OCaml widgets.
- The wire payload and `visible_range_changed` event schema are unchanged.
- The helper cannot guarantee timely application updates; consumers still own
  state, effects, pagination, and keyed widget construction.
- Some consumers need asymmetric or velocity-aware prefetching and may choose a
  custom policy instead of the default helper.
- Keeping one `overscan` value for both logical window guidance and pixel cache
  derivation remains approximate for varied extents.
