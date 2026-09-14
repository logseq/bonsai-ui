# ADR 0003: Typed UI IR and OCaml reconciliation

- Status: Accepted
- Date: 2026-07-25

## Context

An OCaml-first backend needs stable public abstractions without mirroring the
entire Flutter API or leaking protocol dictionaries. Flutter parent-data
constraints and renderer resource identity need to be represented before
runtime errors.

## Decision

`Widget.t` is an abstract immutable logical node with:

- optional application key;
- typed node kind and kind-specific properties;
- typed event bindings;
- immutable child array;
- optional semantics;
- debug metadata excluded from release builds;
- a non-authoritative fingerprint.

Parent-data-sensitive containers expose distinct child types, including
`Flex.child` and `Stack.child`, so invalid combinations cannot be constructed
through the public API.

The mounted tree is separate. It contains monotonic node IDs, mounted handler
IDs, mounted properties, mounted children, and the source widget reference.

Reconciliation first checks physical equality, then key/kind/parent
compatibility, then typed property, event, and child differences. Keyed child
matching uses one old-key hash table and expected linear work. Unkeyed children
match by unkeyed ordinal. Duplicate keys are structured errors in every build.
Cross-parent moves remount.

## Consequences

Application keys never become Flutter business objects. Flutter uses stable
`ValueKey<NodeId>`. A keyed reorder preserves node IDs and renderer-local
controllers.

The initial child operation is `Set_children`. More compact move or splice
operations require measured benefit. Fingerprints may accelerate rejection
but cannot cause an equality false positive.

