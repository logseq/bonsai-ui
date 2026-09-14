# Reconciliation

## Identity

Application `Key.t` and runtime `Node_id.t` are separate concepts. Keys are
semantic identities among siblings. Node IDs are monotonic 64-bit values,
unique only within a runtime epoch.

A mounted node is reusable only when its key, node kind, and parent context are
compatible. Cross-parent moves remount by default. Flutter receives
`ValueKey<NodeId>` and does not receive an application key object.

## Fast paths

Reconciliation applies these checks in order:

1. If `old.source_widget == new_widget`, reuse the complete mounted subtree,
   handler IDs, and node IDs and emit no patch.
2. If kind, key, or parent context is incompatible, drop the old subtree and
   mount the new subtree.
3. Otherwise, diff typed properties, event bindings, semantics, and children.

Fingerprints may reject equality quickly but are never sufficient to prove
equality. Typed property equality is authoritative.

## Children

For each parent, keyed old children are indexed once in a hash table. Keyed new
children perform expected constant-time lookup. An unkeyed child matches only
an unkeyed old child at the same absolute sibling index. Every old child is
consumed at most once.

This gives expected `O(old_count + new_count)` matching. Before allocation or
matching, candidate sibling keys are validated in deterministic preorder.
Duplicate sibling keys are application/widget-tree invariant violations and
produce a structured `Duplicate_key` error in every build mode. Mounted trees
can only originate from a successful validation, so an existing mounted tree
cannot contain duplicate sibling keys through the public runtime API.

The error retains reconciliation-side metadata, the complete root-to-parent
path, every path segment's widget kind and optional key, and the first and
second duplicate child indexes and kinds. The reconciler maintains the path as
shared traversal context and only reverses it when an error is constructed;
successful traversal remains linear and does not copy a complete path for each
node. `Runtime_error.to_string` is the only diagnostic formatting boundary.

`Duplicate_key` is fatal for the current runtime session. Its candidate is
never presented, and no presentation token, renderer revision, or frame bytes
are produced. The path is OCaml reconciliation metadata only: it does not
participate in widget equality, identity, fingerprints, node or handler ID
allocation, patches, or successful Flutter wire frames.

The first patch representation uses `Set_children(parent_id, child_ids)`.
This is linear, deterministic, and avoids premature LCS complexity. More
specific splice or move operations require benchmark evidence.

## Patch ordering

New nodes are created before a parent refers to them. Compatible node updates
precede `Set_children`. The root is selected after all reachable nodes exist.
Dropped nodes are listed after all new references have been installed.

Dart applies the entire ordered list to a transaction shadow copy and validates
it before commit.

## Required invariant

For every valid old mounted tree and logical new tree:

```text
apply_patches(snapshot(old), reconcile(old, new).patches)
=
snapshot(reconcile(old, new).mounted_tree)
```

Tests cover insertion, deletion, reorder, kind replacement, duplicate keys,
mixed keyed/unkeyed children, nested removal, empty roots, handler changes,
physical equality, 10,000 keyed siblings, and randomized mutations.
