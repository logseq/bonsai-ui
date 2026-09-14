# Sliver Wire Invariant Validation

## Problem

The public OCaml virtual-sliver constructors enforce logical-window and sparse
extent invariants, but the wire and host boundaries do not enforce the same
contract symmetrically.

In particular, the Dart encoder and decoder accept `firstIndex > totalCount`.
The varied-extent codec accepts override indexes that are out of range,
duplicated, or not strictly increasing. `NodeStore` validates only that the
props runtime type matches the node kind, so direct or decoded malformed props
reach the renderer. The OCaml wire encoder checks numeric field widths and
positive default extents but does not independently check the relational window
or override invariants represented by a private `Wire_frame` value.

`SparseExtentGeometry` relies on sorted unique overrides for binary search and
prefix-delta calculation. Accepting malformed values can therefore produce
incorrect item extents, scroll offsets, visible ranges, and initial anchors
instead of rejecting the frame atomically. Separately, the materialized child
window can contain more children than `totalCount - firstIndex`; that invariant
is only known once frame operations form the final tree.

## Decision

Define one virtual-sliver invariant set and enforce it at every boundary that
constructs, encodes, decodes, stores, or renders such values.

The shared props contract is:

- `totalCount` is non-negative and representable by the receiving runtime;
- `firstIndex` is in `0 .. totalCount`;
- fixed `itemExtent`, varied `defaultItemExtent`, and every override extent are
  finite and strictly positive;
- varied override indexes are strictly increasing, unique, and in
  `0 .. totalCount - 1`;
- override count does not exceed `totalCount` and remains within its wire field;
- `overscan` and transition durations retain their existing `u32` contract.

The final stored-tree contract additionally requires the number of materialized
children to be no greater than `totalCount - firstIndex` for both virtual sliver
kinds.

Use shared validation helpers within each language so encode and decode paths
cannot drift. Apply the props checks in the public OCaml constructors, OCaml
wire encoder and decoder, Dart wire encoder and decoder, and the Dart renderer
or store boundary used by directly constructed frames. Apply the child-window
check in `NodeStore` after all operations have produced the shadow tree, before
the frame commits. Keep renderer checks as defense in depth where malformed
objects can bypass the codec.

Reject invalid values with the existing structured `Invalid_props` or
`invalidProps` errors. Do not sort, clamp, truncate, or otherwise normalize a
malformed frame.

## Alternatives considered

### Rely on the public OCaml constructors

The normal producer path is validated, but codecs and `NodeStore` are explicit
trust boundaries and are also exercised by fixtures, foreign producers, and
direct Dart frames.

### Validate only in the Dart renderer

Renderer rejection is too late for atomic frame application and can interact
with widget error boundaries. The store should never commit a structurally
invalid virtual window.

### Sort or discard invalid overrides

Normalization hides producer bugs and changes the requested geometry. The same
bytes would also have different meaning across hosts unless every
implementation duplicated the normalization exactly.

## Consequences

- OCaml and Dart codec tests reject `firstIndex > totalCount` in both encode and
  decode directions for fixed and varied slivers.
- OCaml and Dart varied-extent codec tests reject out-of-range, duplicate, and
  descending override indexes in both directions.
- Boundary values for an empty list, `firstIndex = totalCount`, valid final
  override index, `u32` overscan, and transition durations continue to round
  trip.
- `NodeStore` atomically rejects fixed and varied materialized windows whose
  child count exceeds `totalCount - firstIndex` and leaves its prior tree and
  revision unchanged.
- Direct renderer construction with malformed virtual-sliver props fails with
  the project renderer error rather than a Flutter assertion or incorrect
  geometry.
- Public OCaml constructor tests and wire tests assert the same invariant table.

### Operational risks

- Repeating validation across languages and layers creates maintenance cost;
  shared per-language helpers and a mirrored test matrix are required to keep
  the contract aligned.
- Final-tree child validation makes `NodeStore` aware of node-specific child
  cardinality, expanding its responsibility beyond generic graph shape.
