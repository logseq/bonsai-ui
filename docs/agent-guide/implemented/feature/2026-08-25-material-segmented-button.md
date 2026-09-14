# Material Segmented Button

## Problem

`Bonsai_flutter_ui.Material` does not expose Flutter Material's
`SegmentedButton<T>`. Applications that need a compact choice control must use
`Radio_group`, render independent chips, approximate the control with generic
layout and pressable nodes, or add an application-specific native widget. None
of those alternatives preserves the native component's joined border,
selection indicator, keyboard and focus behavior, semantics, theme integration,
or horizontal and vertical layout behavior.

Flutter 3.44 models `SegmentedButton<T>` as a controlled selection component:

- `segments` is a non-empty list of `ButtonSegment<T>` values;
- every segment has a unique value, an optional icon, an optional label, an
  optional tooltip, and an enabled flag, with at least one of icon or label;
- `selected` is a set owned by the application;
- selection may be single or multiple and may optionally be empty;
- `onSelectionChanged` reports the complete new selected set;
- the whole control can be disabled independently of per-segment enabled state;
- the control may be horizontal or vertical, may expand using edge insets, and
  may show Flutter's default or an application-supplied selected icon; and
- visual styling otherwise comes from `SegmentedButtonThemeData` and an
  optional Flutter `ButtonStyle`.

The current bonsai_flutter protocol can encode stable `int64` option IDs for
`Radio_group`, but it has no unordered integer-set property or event payload.
Adding full segmented-button behavior therefore requires a deliberate public
selection model and a new typed event payload, not only a renderer factory.

This feature follows the linear-progress change, which assigns node kind `124`
and protocol minor version `22`. Segmented button therefore uses the next node
kind, `125`, and increments the protocol minor version to `23` without reusing
or renumbering existing IDs.

## Proposal

Add a dedicated renderer-independent Material segmented-button node backed by
Flutter's native `SegmentedButton<int>`.

The selected public shape uses stable signed 64-bit IDs, following
`Material.Radio_group`, while domain values remain in application OCaml:

```ocaml
module Segmented_button : sig
  type segment

  val segment
    :  id:int64
    -> ?enabled:bool
    -> ?icon:Widget.t
    -> ?label:Widget.t
    -> ?tooltip:string
    -> unit
    -> segment

  val create
    :  ?key:Key.t
    -> ?enabled:bool
    -> ?direction:Layout.Axis.t
    -> ?multi_selection_enabled:bool
    -> ?empty_selection_allowed:bool
    -> ?expanded_insets:Layout.Edge_insets.t
    -> ?show_selected_icon:bool
    -> ?selected_icon:Widget.t
    -> selected_ids:int64 list
    -> on_selection_changed:Event.Handler.t
    -> segment list
    -> unit
    -> Widget.t
end
```

The `int64 list` API boundary deliberately represents a semantic set without
exposing a collection type from a specific OCaml library. The constructor
interprets it as a set, rejects duplicates, and canonicalizes it by signed
ascending ID before logical-node construction. That keeps widget equality,
fingerprinting, reconciliation, encoding, tests, and emitted events independent
of caller or Dart set iteration order. An application maps the canonical IDs
back to its domain values after receiving an `Event.Payload.Int64_list`.

The logical node contains:

- canonical selected IDs;
- group enabled state;
- single- versus multi-selection policy;
- empty-selection policy;
- horizontal or vertical direction;
- optional expanded insets;
- selected-icon policy and child presence; and
- ordered segment metadata containing ID, enabled state, tooltip, and
  icon/label child-presence flags.

Children use one canonical wire order: optional group selected icon
first, then each segment's optional icon followed by its optional label in
segment-list order. Both OCaml and Flutter must derive and validate the exact
child count from the metadata before indexing children.

Construction must reject:

- an empty segment list;
- duplicate segment IDs;
- a segment with neither icon nor label;
- duplicate selected IDs;
- a selected ID that does not identify a segment;
- more than one selected ID in single-selection mode;
- an empty selected set when empty selection is disabled; and
- a custom selected icon when selected-icon display is disabled, unless the
  final public API makes that state unrepresentable.

The Flutter wire boundary must repeat every structural and selection-policy
validation. Flutter then builds `SegmentedButton<int>` mechanically, maps
metadata to `ButtonSegment<int>`, passes the controlled selected set, and sets
`onSelectionChanged` to `null` when the group is disabled. Per-segment enabled
flags continue to map to `ButtonSegment.enabled`.

The protocol work adds:

- `material_segmented_button` node kind `125`;
- `segmented_selection_changed` event tag `35`;
- a length-prefixed signed-`int64` set/list encoding for selected IDs and the
  event payload;
- structured segment metadata encoding; and
- protocol minor version `23` plus regenerated OCaml and Dart protocol artifacts
  and cross-language fixtures.

The wire representation must define selected IDs as sorted and unique. A
decoder rejects non-canonical ordering instead of silently normalizing
malformed frames. The renderer emits the complete newly selected set in the
same canonical order. Selection-change events are discrete user actions and
must not be frame-coalesced.

The initial component inherits its appearance from Flutter's Material 3 theme.
It does not serialize `ButtonStyle`, `WidgetStateProperty`, custom colors,
borders, shapes, mouse cursors, or animation configuration. Tooltips, direction,
expanded insets, per-segment enabled state, and selected-icon behavior are
semantic component capabilities and are all included in the initial surface.

Implementation covers the public OCaml surface, logical widget identity
and reconciliation, schema and codecs, event dispatch, Flutter renderer,
gallery examples, Material component documentation, and focused OCaml/Dart
tests. It does not change `Radio_group`, chips, generic buttons, or introduce a
compatibility wrapper around an application-specific segmented control.

## Decision

Adopt the proposal in full:

1. Support Flutter's complete single-, multi-, and empty-selection model in the
   initial release.
2. Represent selected sets at the public OCaml and event-payload boundaries as
   canonicalized `int64 list` values rather than exposing a library-specific
   set type.
3. Include `icon`, `label`, `tooltip`, per-segment enabled state, direction,
   expanded insets, default/custom selected-icon behavior, and group enabled
   state in the initial semantic surface.
4. Keep `on_selection_changed` required and represent whole-control disabled
   state with explicit `?enabled:bool`, matching the existing Material button
   APIs and keeping event-binding identity stable.
5. Require selected IDs to be strictly sorted and unique on the wire. OCaml
   canonicalizes valid API input before encoding; wire decoders reject
   duplicates and non-canonical order instead of normalizing malformed frames.
6. Inherit visual styling from the Material theme and exclude `ButtonStyle`,
   custom colors, borders, shapes, cursors, and animation configuration.

## Alternatives considered

### Support single selection only

Reuse an optional `int64` selected ID and an `int64` selection event, closely
matching `Radio_group`. This is the smallest protocol addition and covers the
most common segmented-control use case. It does not support Flutter's native
multi-selection behavior, however, and adding it later would require replacing
the public selection type and event contract because backward-compatibility
layers are not preserved in this repository.

### Split single and multi selection into separate constructors

Expose `single_select` with `int64 option` and `multi_select` with an ID list.
This makes invalid selection cardinality less representable but duplicates
most arguments and still requires the list/set wire payload for full Flutter
coverage. A shared `create` surface more closely follows the native component
and keeps mode switches controlled by application state.

### Identify segments by list index

Emit the selected index or an index set. This avoids application-supplied IDs
but makes selection identity change when segments are inserted or reordered.
Stable `int64` IDs match the existing radio-group design and make incremental
reconciliation and domain mapping explicit.

### Expose only text labels

Store a string label directly in each segment and omit child slots. This is
simple but fails to represent Flutter's icon-only and icon-plus-label segments,
including a custom selected icon. Arbitrary logical widget children are already
used for Material destinations, radio labels, chips, and dialog slots.

### Build the control from generic pressables

This avoids a protocol node but reimplements native Material layout, border
painting, focus traversal, semantics, state layers, and theme behavior in the
application. It would not constitute support for Flutter's Material component.

### Expose Flutter `ButtonStyle`

Mirroring `ButtonStyle` and `WidgetStateProperty` would greatly expand the
protocol and couple the OCaml API to Flutter-only state-resolution details. The
existing Material surface intentionally inherits component appearance from the
theme, so style serialization should remain a separate design decision.

### Implement this as a native-widget extension

The extension mechanism can render a segmented button, but every application
would need to register the capability and own a private payload and event
contract. A standard Flutter Material component belongs in the core logical
node and renderer registry.

## Acceptance criteria

- The public OCaml API can describe Flutter-valid single-select,
  multi-select, empty-select, disabled-group, and disabled-segment states.
- Segment identity is stable across reorderings and selected IDs are encoded
  and emitted canonically.
- Invalid segment definitions, IDs, child shapes, and selection policies are
  rejected before frame construction and again at the Flutter wire boundary.
- The protocol round-trips all selected-set cardinalities and segment metadata
  across OCaml and Dart without using untyped application payloads.
- Flutter renders exactly one native `SegmentedButton<int>` and maps every
  included semantic property to the corresponding Flutter property.
- A user selection produces exactly one typed event containing the complete new
  selected set, including the empty set when allowed.
- Controlled selection updates reconcile without remounting the node or
  retaining renderer-owned application state.
- Widget equality, fingerprints, frame patches, event dispatch, malformed-wire
  tests, and cross-language fixtures cover the new node and event payload.
- Gallery coverage demonstrates at least single selection, multi selection,
  empty selection, icons and labels, tooltips, disabled state, expanded layout,
  custom selected icons, and both directions.
- User-facing Material documentation describes controlled state ownership,
  stable IDs, validation, payload decoding, and inherited theme styling.
- Protocol generation checks, OCaml tests, Flutter format/analyze/tests, and
  repository decision-document checks pass.

## Consequences

- Applications can render Flutter's native `SegmentedButton<int>` from OCaml
  with controlled single, multiple, and empty selections, stable segment IDs,
  semantic child slots, disabled states, direction, expanded insets, and
  selected-icon policy.
- Protocol 1.23 adds stable node kind 125, event tag 35, canonical signed
  `int64` list encoding, structured segment metadata, generated IDs, and
  regenerated cross-language fixtures.
- OCaml construction canonicalizes valid selected IDs before logical-node
  identity is computed. Both wire decoders reject malformed metadata,
  non-canonical selections, invalid policies, and invalid expanded insets.
- Selection events carry the complete canonical ID set as the typed
  `Event.Payload.Int64_list` payload and remain discrete user actions rather
  than frame-coalesced values.
- The gallery and Material documentation demonstrate controlled state,
  horizontal and vertical layouts, single and multiple selection, empty
  selection, icons, labels, tooltips, disabled state, expanded layout, and a
  custom selected icon.
- Per-instance `ButtonStyle`, `WidgetStateProperty`, colors, borders, shapes,
  cursors, and animation configuration remain outside the public API; visual
  styling continues to come from the active Material theme.
- The protocol and framework source change affects the iPhoneOS SDK release
  inputs. After these framework changes are committed and pushed, the SDK
  repository must be regenerated, committed, and pushed separately according
  to the repository workflow.

## Risks

- A generic `int64 list` looks ordered even though selection is a set. Without
  strict canonicalization, semantically equal selection states could generate
  unnecessary patches or nondeterministic fixtures.
- Adding a new collection event payload touches event batching, payload limits,
  malformed-wire validation, runtime dispatch, and both codecs; a renderer-only
  test would miss most of the risk.
- Child metadata and child ordering can drift between OCaml and Dart, causing
  icons and labels to be assigned to the wrong segment unless both boundaries
  validate the same shape.
- Supporting too many Flutter style parameters would couple the protocol to
  framework implementation details and conflict with the current
  theme-owned-styling policy.
- Enforcing Flutter's recommendation of two to five segments as a hard rule
  would be stricter than Flutter, which only requires a non-empty list.
- The selected node and event IDs assume the linear-progress allocation is
  present. Implementation must stop rather than reuse those IDs if the active
  schema differs from this prerequisite.
