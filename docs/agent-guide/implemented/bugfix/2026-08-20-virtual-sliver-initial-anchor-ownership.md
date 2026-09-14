# Virtual Sliver Initial Anchor Ownership

## Problem

`SliverFixedExtentHost` and `SliverVariedExtentHost` share the controller owned
by their enclosing `Scroll_view`, but every host independently attempts to set
the initial controller offset when its `first_index` is positive. The only
arbitration is a check that `controller.offset == 0` when a post-frame callback
runs.

This is not a stable ownership rule. For example, given two virtual slivers in
one scroll view, the first with `first_index = 0` and the second with
`first_index = 200`, the second host may jump the shared controller into its own
content and skip the first sliver. Callback order becomes an undeclared source
of global scroll position. The existing preceding-header tests exercise one
virtual sliver, not competing virtual slivers.

## Decision

The enclosing `Scroll_view` owns one initial-anchor coordinator through
`ScrollViewScope`. Virtual slivers register their post-layout anchor candidates
with the coordinator instead of calling `jumpTo` independently. The
coordinator commits at most one initial controller adjustment.

The implicit compatibility rule for the current API is that the earliest
virtual sliver in scroll order owns the initial virtual anchor:

- if its `first_index = 0`, the scroll view stays at its normal leading offset;
- if its `first_index > 0`, the coordinator targets that sliver's global leading
  offset plus its local logical-item offset;
- later virtual slivers never change the initial controller position;
- after user interaction or any non-zero established controller offset, no
  implicit initial anchor may be committed.

Candidate selection uses laid-out sliver positions rather than widget
callback order. Fixed and varied geometry continue to compute their own local
logical offsets, while only the coordinator may mutate the shared controller.

## Alternatives considered

### Keep first callback wins

This preserves the current race and makes scroll position depend on build and
post-frame callback ordering.

### Add an absolute initial offset to `Scroll_view` and remove implicit anchors

Explicit scroll-view ownership is conceptually clean, but it makes every
single-sliver consumer calculate absolute offsets including preceding sliver
geometry. It may be considered as a later API redesign; it is not required to
remove the current multi-host race.

### Allow every host to correct the controller

Serial corrections cause visible jumps and still do not define which logical
collection owns restoration.

## Consequences

- Parameterized fixed, varied, and mixed-host tests prove that only the earliest
  laid-out virtual sliver establishes the initial position.
- An earliest zero-index host protects the normal leading offset, while a
  single non-zero host after a box sliver preserves global-offset anchoring and
  scroll-extent clamping.
- User scrolling or an externally established non-zero offset prevents implicit
  correction.
- The coordinator performs at most one `jumpTo` and is disposed with its
  `Scroll_view` owner.
- Selecting the earliest virtual sliver formalizes behavior that was previously
  unspecified; applications that accidentally relied on a later sliver winning
  will change behavior.
- Sliver order must be derived from real layout information, including reverse
  scroll direction and padding, rather than registration timing.
