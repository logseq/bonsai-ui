# Sliver Renderer Error Boundary Shape

## Problem

`NodeHost` catches renderer construction failures and substitutes
`BonsaiRendererErrorWidget`, which produces a `RenderBox`. This fallback is
valid for ordinary box widgets but not for a node mounted directly in a
`CustomScrollView.slivers` list. A viewport requires every direct child to
produce a `RenderSliver`.

When a sliver factory rejects invalid properties or child slots, the intended
`RendererBoundaryError` is therefore followed by render-protocol failures such
as `RenderViewport expected a child of type RenderSliver`. A mounted invalid
`SliverAppBar` currently produces multiple exceptions from one bad node instead
of containing the failure at the node boundary. The cached-error path for an
unchanged failed local revision returns the same incompatible box fallback.

This defeats the renderer boundary for every core sliver kind and can prevent
the containing viewport from rendering otherwise valid siblings.

## Decision

Make renderer error fallbacks preserve the parent render protocol expected by
the failed node.

Classify every core sliver node kind at the `NodeHost` error boundary. For a
failed sliver node, wrap the existing error surface in `SliverToBoxAdapter` so
the direct viewport child remains a `RenderSliver`. For every non-sliver node,
retain the existing box-shaped `BonsaiRendererErrorWidget` behavior.

Apply the same shape selection both when an error is first caught and when a
cached error is returned for the same `localRevision`. Keep one
`RendererBoundaryError` report for the original construction failure; the
fallback itself must mount without producing another Flutter framework error.
When a later node revision becomes valid, normal rendering must replace the
fallback through the existing retry behavior.

Keep the classification exhaustive and local to the core node-kind surface so
adding a future sliver kind requires an explicit decision about its fallback
shape.

## Alternatives considered

### Reject all invalid slivers before rendering

Construction and codec validation should reject known invalid values, but they
cannot prevent every factory failure, extension error, or Flutter-side
invariant change. The renderer boundary must remain structurally valid even
when an earlier validation layer misses a problem.

### Make every sliver factory catch its own errors

Per-factory wrappers duplicate boundary behavior, can miss exceptions thrown by
future factories, and separate the error cache from the place that owns it.

### Replace the complete scroll view on any child failure

Returning one box-shaped error for the entire scroll view would preserve render
types, but it discards valid sibling slivers and moves error ownership away from
the failing node.

## Consequences

- Mounting an invalid `SliverAppBar` inside a `Scroll_view` reports exactly one
  `RendererBoundaryError` and no `RenderViewport` child-type error.
- The fallback for a directly mounted failed sliver produces a `RenderSliver`
  and can coexist with valid sliver siblings.
- Rebuilding the same failed `localRevision` keeps a compatible cached
  fallback without reporting duplicate framework exceptions.
- Updating the failed node to a valid revision removes the fallback and renders
  the requested sliver.
- Ordinary box-node boundary tests retain the existing
  `BonsaiRendererErrorWidget` behavior.
- Tests cover all currently registered core sliver kinds or an exhaustive
  shared sliver-kind classifier.

### Operational risks

- A sliver error surface contributes scroll extent and can change the viewport
  layout while the node is invalid; containment is preferred over preserving
  the failed node's unavailable geometry.
- A manually maintained sliver-kind classification can drift when new protocol
  kinds are added unless exhaustiveness is enforced by tests or the type
  structure.
