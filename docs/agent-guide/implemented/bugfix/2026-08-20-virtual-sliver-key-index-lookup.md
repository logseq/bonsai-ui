# Virtual Sliver Key Index Lookup

## Problem

Both virtual sliver hosts implement `findChildIndexCallback` by scanning every
materialized child until a matching Flutter key is found. Flutter can invoke
this callback for each currently mounted keyed element when a new
`SliverChildBuilderDelegate` replaces the previous delegate after the
application moves its materialized window.

For a materialized window of size `W` and `A` active or kept-alive children, a
window update therefore performs `O(A * W)` key comparisons, with an `O(W^2)`
worst case when most of the window is active. This work occurs on the Flutter UI
thread during element reconciliation and can cause frame-time spikes for large
overscan windows. Fixed- and varied-extent hosts duplicate the same linear
implementation.

## Decision

Build one immutable `Map<Key, int>` from each host's current materialized
children to their logical indexes, then make `findChildIndexCallback` a constant
time map lookup.

Construct the map once per effective child-window update, not once per callback.
The logical value for child position `i` is `firstIndex + i`. Ignore null keys;
the normal renderer supplies keyed `NodeHost` children, while Flutter's
documented behavior for an unkeyed child remains no remapping. Reject duplicate
non-null keys at the closest existing invariant boundary rather than silently
choosing one logical index.

Share the lookup construction between fixed- and varied-extent hosts. Keep the
item builder, placeholder behavior, materialized-window ownership, and Flutter
delegate semantics unchanged. The optimization must preserve keyed element and
state identity across overlapping window shifts.

## Alternatives considered

### Keep the linear scan because visible windows are usually small

Overscan and application-owned materialization are intentionally configurable,
and large windows are valid. Repeated linear scans put an avoidable
multiplicative cost on the reconciliation path.

### Cache only the last key lookup

Flutter typically asks about multiple mounted children during one delegate
replacement, so a single-entry cache does not remove the `O(A * W)` behavior.

### Derive indexes directly from `ValueKey<int>`

The callback contract accepts opaque Flutter keys, and coupling virtual slivers
to the current `NodeHost` key representation would make future keyed wrappers
or custom renderer children incorrect.

## Consequences

- Fixed- and varied-extent hosts use one shared key-index lookup implementation
  with constant-time callback lookup after `O(W)` construction.
- Existing keyed children retain their Flutter element and state identity when
  an overlapping materialized window changes `firstIndex`.
- Keys removed from the current window return `null`, and newly added keys map
  to the correct logical index.
- Unkeyed children return `null` without changing placeholder behavior.
- Duplicate non-null keys are rejected deterministically rather than mapped to
  an arbitrary item.
- A focused complexity regression test shows lookup work growing linearly with
  window construction plus active lookups, rather than multiplying active
  children by window size.

### Operational risks

- The lookup allocates `O(W)` additional map storage for each effective window;
  this trades modest memory and one linear construction pass for predictable
  reconciliation time.
- Rebuilding the map on unrelated widget rebuilds would add avoidable
  allocation, so cache invalidation must follow the effective children,
  `firstIndex`, and key set rather than every frame indiscriminately.
