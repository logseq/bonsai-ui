# Virtual Sliver Zero Paint Range Recovery

## Problem

A bound virtual sliver can permanently miss its initial
`visible_range_changed` event. Both virtual hosts schedule a one-shot
post-frame report, but `_sliverViewportMetrics` returns no metrics while the
render sliver has no geometry or has a non-positive `paintExtent`. The failed
attempt is forgotten. A later ancestor-only layout transition from zero paint
to positive paint does not necessarily rebuild the host or move the shared
`ScrollController`, so no retry is guaranteed.

This breaks the renderer-to-OCaml feedback loop. A consumer that starts
pagination only after receiving the visible range can remain on passive
continuation content indefinitely until the user drags the list. The issue has
been observed in `logseq_journal` on iPhone with consumer revision `aa4b1c9`
and `bonsai_flutter` revision `2dc30ce`. The host implementation is unchanged
on the current main branch.

## Decision

Initial visible-range publication remains pending until a valid range has been
emitted. Retries are driven by actual sliver layout transitions,
not from an unconditional post-frame loop.

Both virtual host implementations use `SliverLayoutBuilder` as a small sliver
layout observation boundary. After child layout, it notifies state when usable geometry
becomes available or when the painted viewport changes. The state coalesces a
post-layout range report and retains the pending-initial flag when geometry is
still unavailable. Once a valid range is emitted, existing `_lastRange`
deduplication applies.

The existing controller-listener path remains responsible for scroll-driven
changes. Varied-extent transition suppression and anchor correction remain in
force: a layout signal may schedule a report, but it must not emit while range
reporting is intentionally suppressed.

This is a Dart renderer fix. It requires no protocol or OCaml API change.

## Alternatives considered

### Retry from every post-frame callback

An unbounded retry loop can continuously schedule frames for a permanently
offstage or zero-sized sliver, wasting power and preventing the application
from becoming idle.

### Depend on controller movement

This is the current behavior and requires user interaction to repair a layout
event that should be self-publishing.

### Emit an empty range for zero paint

An empty range is not the initial visible range and may cause consumers to
discard or unload the correct initial window. Unavailable geometry must not be
marked as successfully reported.

### Depend on `build` or `didUpdateWidget`

A pure ancestor render-layout change can reuse the exact same widget subtree,
so widget lifecycle callbacks are not a sufficient layout signal.

## Consequences

- Parameterized fixed- and varied-extent widget tests retain the same mounted
  subtree while moving from zero paint to a positive viewport without controller
  movement.
- Unusable geometry emits no event; recovery emits exactly one current range,
  idle frames do not duplicate it, and permanently zero paint does not create a
  frame loop.
- Existing preceding-sliver and varied-transition tests remain green.
- The iOS integration continuation fixture loads without a gesture.
- A layout observation boundary adds renderer complexity and must avoid
  layout-time state mutation.
- Layout can occur frequently; notifications must be coalesced and range
  deduplication must remain effective.
