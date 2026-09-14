# Keyed Virtual-List Widget Items

## Problem

`Widget.t` stores an optional application key, and the public widget
constructors expose that key through optional `?key` arguments. Consequently,
the type of a constructed widget does not record whether its root has a key.

The virtual-list sliver APIs currently accept ordinary widgets:

```ocaml
val fixed_extent
  :  ...
  -> items:widget list
  -> ...
  -> t

val varied_extent
  :  ...
  -> items:widget list
  -> ...
  -> t
```

This contradicts the virtual-list contract, which describes `items` as a keyed
materialized window. An application can accidentally provide an unkeyed item,
and the compiler cannot distinguish it from a correctly keyed item.

Application keys preserve logical item identity during OCaml reconciliation
when the retained item's root kind and parent context also remain compatible.
Without a key, reconciliation matches a child positionally. A materialized
window shift, insertion, deletion, or reorder can therefore reuse an existing
node ID for a different logical item. Flutter keys `NodeHost` instances by
those node IDs, so a missing application key can retarget stateful renderer
resources even though the Flutter host itself remains keyed.

The existing duplicate-key validation protects sibling-key uniqueness at
runtime, but it does not reject missing keys. Key presence for list items must
be represented by the public OCaml type instead of relying on documentation or
a later runtime check.

## Decision

Introduce an abstract `Widget.Keyed.t` as compile-time evidence that the root
of a widget has an application key:

```ocaml
type t

module Keyed : sig
  type widget = t
  type t

  val create : key:Key.t -> widget -> t
end
```

`Keyed.create` applies the supplied key to the root of the input widget and
recomputes its fingerprint. It does not add a logical widget node or a renderer
wrapper. The implementation may represent `Keyed.t` as an alias of `Widget.t`,
but the public interface must keep it abstract so callers cannot construct the
evidence without supplying a key.

The internal implementation follows this design:

```ocaml
let with_application_key key (T view) =
  let key = Some key in
  let fingerprint =
    fingerprint
      ~key
      ~test_id:view.test_id
      ~node:view.node
      ~event_bindings:view.event_bindings
      ~children:view.children
  in
  T { view with key; fingerprint }
;;

module Keyed = struct
  type nonrec widget = t
  type t = widget

  let create ~key widget = with_application_key key widget
  let to_widget item = item
end
```

`Keyed.to_widget` is an implementation-only operation used when constructing
the private child array. It is not part of the public API. Applying
`Keyed.create` to a widget that already has a root key replaces that key with
the explicitly supplied key; the resulting value has one unambiguous list-item
identity.

The two virtual-list sliver entry points accept only the evidence type. The
non-virtualized `Sliver.list` API remains unchanged:

```ocaml
module Sliver : sig
  val list : ?key:Key.t -> widget list -> t

  val fixed_extent
    :  ?key:Key.t
    -> total_count:int
    -> first_index:int
    -> item_extent:float
    -> ?overscan:int
    -> items:Keyed.t list
    -> on_visible_range:Event.Handler.t
    -> unit
    -> t

  val varied_extent
    :  ?key:Key.t
    -> total_count:int
    -> first_index:int
    -> default_item_extent:float
    -> extent_overrides:Sparse_extent_override.t list
    -> ?overscan:int
    -> ?transition:Sparse_extent_transition.t
    -> items:Keyed.t list
    -> on_visible_range:Event.Handler.t
    -> unit
    -> t
end
```

Use one private conversion for both virtual-list constructors:

```ocaml
let keyed_children items =
  items
  |> List.map Keyed.to_widget
  |> plain_children
;;
```

Callers construct materialized items with stable domain identities:

```ocaml
let render_item item =
  Widget.Keyed.create
    ~key:(Key.string item.id)
    (Widget.text item.title)
;;
```

The old `widget list` signatures for `fixed_extent` and `varied_extent`, and all
of their old call sites, are removed. Do not add an overload, runtime conversion
from an arbitrary `Widget.t`, fallback, or compatibility module. In particular,
`Widget.text ~key ...` still has type `Widget.t` and does not satisfy a
`Widget.Keyed.t` list; virtual-list call sites must construct the evidence
explicitly with `Widget.Keyed.create`.

Keep ordinary layout collections such as `Widget.row`, `Widget.column`,
`Widget.Flex`, `Widget.Stack`, the non-virtualized `Widget.Sliver.list`,
`Scroll_view` sliver children, app-bar actions, and overlays unchanged. Those
collections frequently describe a static widget shape rather than a
materialized virtual window, so requiring keys there would add noise without
enforcing the virtual-list identity contract. Navigator page identity is also
outside this decision because it has its own required `page_key` domain.

Retain the reconciler's duplicate-key validation. The new type proves key
presence for each item, while the runtime validation continues to enforce key
uniqueness across siblings and to produce the existing structured diagnostic.

This is an OCaml UI API change only. Application keys remain reconciliation
metadata and do not enter the wire frame, so this decision requires no protocol
or `spec/` changes.

## Alternatives considered

### Validate missing keys at runtime

The sliver constructors could inspect each item and raise `Invalid_argument`
when a key is absent. That would detect the mistake later, would leave the
public contract as `widget list`, and would duplicate a property that the OCaml
type system can express directly.

### Add key-state phantom parameters to every widget

`Widget.t` could become a parameterized type such as `'key_state Widget.t`.
However, existing optional `?key` arguments cannot make a function's return
type depend on whether an optional argument was supplied. Ordinary containers
also need heterogeneous keyed and unkeyed children, which would require
existential wrappers or pervasive coercions. An isolated abstract evidence
type gives the list APIs the required guarantee without infecting the complete
widget algebra.

### Accept `(Key.t * Widget.t) list` or a public item record

A pair or record would make key presence explicit, but it would expose the
representation and require every list constructor to attach the key correctly.
The abstract evidence type centralizes key application, fingerprint
recalculation, and future invariants behind one smart constructor.

### Require keys for every multi-child widget

Rows, columns, stacks, app-bar actions, and other multi-child widgets often
contain fixed structural children whose positional identity is intentional.
Requiring keys for all of them would broaden the API break beyond the list-item
invariant and make simple layouts unnecessarily verbose.

### Preserve the old list signatures beside the keyed signatures

Parallel keyed and unkeyed entry points would allow new code to keep bypassing
the invariant and would turn the old unsafe path into permanent API surface.
The keyed signatures replace the old signatures directly.

## Consequences

- `Widget.Keyed.t` is abstract in `widget.mli` and can be constructed publicly
  only by supplying a `Key.t` to `Widget.Keyed.create`.
- `Widget.Keyed.create` keys the existing widget root without adding a widget
  node and recomputes the root fingerprint with the new key.
- `Widget.Sliver.fixed_extent` and `Widget.Sliver.varied_extent` accept
  `Widget.Keyed.t list`; no public unkeyed alternative remains for either
  virtual-list API. `Widget.Sliver.list` continues to accept `Widget.t list`.
- A compile-failure fixture proves that `Widget.t list`, including widgets
  built with direct optional `?key` arguments, cannot be passed as virtual-list
  items.
- Positive public API and surface tests demonstrate construction of both
  virtual-list sliver kinds from `Widget.Keyed.t` values and observe the expected
  application keys on their child roots. They also demonstrate that an unkeyed
  non-virtualized `Widget.Sliver.list` remains valid.
- Reconciliation tests demonstrate that keyed insertions, deletions, reorders,
  and overlapping virtual-window shifts preserve node identity for retained
  logical items whose root kind and parent context remain compatible. A root
  kind change with the same key remains a documented remount.
- An end-to-end Flutter renderer test shifts a materialized window from
  `[a; b]` to `[b; c]` and proves that `b` retains both its OCaml node ID and its
  keyed Flutter element or stateful renderer resource, while `a` is released
  and `c` is newly mounted.
- Duplicate item keys still produce the existing `Duplicate_key` runtime error
  and diagnostic.
- All repository call sites use `Widget.Keyed.create` with stable domain keys;
  no positional index is introduced as an identity for reorderable data.
- `dune build @all`, `dune runtest`, the viewport compile checks, the focused
  Flutter virtual-list tests, and `spec-dev-tool check --all` pass.
- This is a deliberate source-breaking API change for every caller of the two
  virtual-list sliver functions. The non-virtualized `Sliver.list` API is not
  affected.
- The evidence type proves that a key exists, but it cannot prove that keys are
  unique within a list or stable across frames. Runtime duplicate validation
  and application-level key selection remain necessary.
- Applying `Widget.Keyed.create` after a caller has already assigned a root key
  replaces the earlier key. Call sites must treat the key supplied to
  `Keyed.create` as the authoritative logical item identity.
- A stable key does not preserve a node ID across an incompatible root-kind or
  parent-context change. Item renderers that require retained root identity must
  keep those reconciliation properties stable.
- Keeping keys optional for general multi-child containers means those APIs can
  still be misused for dynamic data collections. This decision intentionally
  enforces the invariant only at APIs whose contract explicitly models list
  items.
