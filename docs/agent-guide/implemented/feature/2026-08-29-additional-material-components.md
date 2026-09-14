# Unblocked Additional Material Components

## Problem

The renderer-independent Material surface lacks a focused set of components
whose state ownership and Flutter mapping are already clear:

- standalone `SearchBar`;
- a general-purpose `Tooltip`;
- non-paginated `DataTable`;
- `Stepper`;
- controlled `ExpansionPanelList`;
- `SimpleDialog` and `Dialog.fullscreen`, merged with the existing
  `AlertDialog` surface;
- the Material 3 assist and suggestion uses of the existing `ActionChip`;
- elevated action, filter, and choice chips;
- filled and outlined card variants; and
- vertical dividers.

The original exploration also considered `SearchAnchor`, `MaterialBanner`,
`CarouselView`, `PaginatedDataTable`, and `AboutDialog`. Each requires an
additional ownership or scope decision. They are intentionally excluded from
this decision rather than delaying the unblocked components or embedding
premature fallback behavior.

Several selected capabilities already exist under a related API. Adding a new
node for every Flutter constructor would duplicate `ActionChip`, `Card`,
`Divider`, and dialog concepts. The additions instead need coherent public
families, shared protocol representations where their shapes match, controlled
OCaml state, and direct Flutter 3.44.8 mappings.

The baseline is Flutter 3.44.8 at revision `058e0af2c2` and protocol version
1.23. The existing Material decisions continue to apply:

- OCaml owns application and controlled component state;
- Flutter owns rendering resources and animation mechanics;
- modal route policy belongs to `Navigation.Modal_dialog`;
- semantic variants are represented explicitly while visual styling normally
  comes from the active Material theme;
- logical nodes remain serializable and incrementally reconcilable; and
- replaced public APIs are removed without compatibility aliases.

## Proposal

Add only the unblocked components and extensions described below. Use stable
signed `int64` IDs for repeated interactive descriptors, translate Flutter
indices back to IDs from the accepted frame, and emit one typed event shape per
event tag.

### Standalone search bar

Add a dedicated `Material.Search_bar` surface that maps to Flutter's
`SearchBar` but reuses the existing revisioned text editing contract.
`SearchBar` is not a string-only input: selection, composing ranges, stale
edits, focus, submit behavior, and IME synchronization must behave identically
to `Material.text_field`.

The public constructor accepts:

- the existing text input session ID, document revision, accepted local
  revision, update mode, and `Text_editing.Value.t`;
- edit, submit, focus-change, and optional limit-reached handlers;
- optional leading and ordered trailing children;
- optional hint text;
- enablement, read-only state, autofocus, keyboard type, input action, and
  UTF-8 limit; and
- an optional tap handler.

The renderer should extract the revision and controller synchronization logic
from the current text-field host into shared internal machinery. The
search-bar host owns and disposes its `TextEditingController` and focus
resources while OCaml remains authoritative for accepted text.

`SearchAnchor`, suggestions, search-view routing, and `SearchController`
open/close commands are not part of this decision.

### General tooltip

Add a `Material.tooltip` wrapper with exactly one child and:

- a required non-empty UTF-8 message;
- optional enabled state;
- semantic inclusion or exclusion;
- preferred above/below placement;
- long-press or tap trigger mode;
- finite non-negative wait, show, and exit durations;
- tap-to-dismiss and feedback policy; and
- an optional triggered handler.

Manual trigger mode is excluded because it requires a separate declarative
visibility or imperative command contract. Colors, rich text, decoration,
padding, constraints, cursors, and custom position delegates remain
theme-owned or out of scope.

Existing component-native tooltip fields remain in place. Flutter uses those
fields to integrate tooltip text with each component's semantics and hit
target; the general wrapper fills only the arbitrary-child gap.

### Non-paginated data table

Add one `Material.Data_table` module with abstract `Column`, `Row`, and
`Cell` descriptors and a non-paginated table constructor.

A column has:

- a unique stable ID;
- one label child;
- optional tooltip text;
- numeric alignment; and
- sortability.

A row has:

- a unique stable ID;
- controlled selected state;
- selection enablement; and
- exactly one cell per column.

A cell has:

- one content child;
- placeholder and editable-indicator semantics; and
- optional activation.

The table owns controlled sort-column ID, sort direction, selected rows, and
handlers for sort requests, row selection, select-all, and cell activation.
Events carry typed records containing stable row and column IDs rather than
Flutter indices. Hover, pointer-down, tap-cancel, double-tap, long-press,
per-cell style overrides, custom column-width objects, and
`PaginatedDataTable` are excluded.

OCaml validates a non-empty column list, unique IDs, exact row widths, known
sort and selection IDs, and finite non-negative dimensions. Dart repeats these
checks at the wire boundary. Child order is column labels followed by row-major
cell content.

### Controlled stepper

Add a `Material.Stepper` module with:

- vertical or horizontal orientation;
- a non-empty ordered list of steps with unique stable IDs;
- a controlled current step ID;
- step-selected, continue, and cancel handlers; and
- theme-driven Material rendering.

Each abstract step has a required title and content, optional subtitle and
horizontal label, an active flag, and an indexed, editing, complete, disabled,
or error state.

Flutter documents that a `Stepper` should not receive a structurally
different step list without a different key. The renderer must replace the
inner Flutter state when ordered step identity changes, even if the logical
node reconciles in place. Step selection events carry stable IDs.

Custom controls builders, step-icon builders, connector styling, dimensions,
scroll controllers, and physics are excluded.

### Controlled expansion panels

Add a `Material.Expansion_panel_list` module with abstract panels, a
selection policy, and a controlled expanded-ID set.

Each panel has a unique stable ID, header child, body child, enablement, and a
flag controlling whether the whole header is tappable. The selection policy is
either:

- multiple panels expanded; or
- at most one panel expanded.

Any user toggle emits the complete canonical expanded-ID set as
`Event.Payload.Int64_list`. OCaml validates unique IDs, known expanded IDs,
and at most one expanded ID in single mode. Dart repeats the validation.

Both policies map to the externally controlled `ExpansionPanelList`
constructor. Do not use `ExpansionPanelList.radio`, because its open panel is
Flutter-owned and its public value is only an initial value.

Animation duration, expanded header padding, elevation, gap size, and colors
use Flutter and theme defaults in the initial surface.

### Dialog visual family

Replace the flat `Material.alert_dialog` entry point with a
`Material.Dialog` module containing:

- `alert`, preserving optional icon, title, content, and ordered actions;
- `simple`, with an optional title and a non-empty ordered list of options;
  and
- `fullscreen`, wrapping exactly one logical child.

A simple-dialog option has a unique stable `int64` ID, enablement, and one
label child. Selecting an option emits its ID. OCaml decides whether to remove
the dialog page and how to map the ID to an application value.

All three constructors describe only visual content. Applications present
them through pages using `Navigation.Modal_dialog`, which remains the sole
owner of barriers, route presence, back behavior, safe area, focus, and
transition policy. `Dialog.fullscreen` changes the Flutter visual surface; it
does not create a second navigation path.

`AboutDialog`, license-page presentation, and adaptive dialog variants are
excluded. The obsolete `Material.alert_dialog` function is removed rather
than kept as an alias for `Material.Dialog.alert`.

### Existing chip family

Do not add `assist_chip` or `suggestion_chip` constructors. Flutter 3.44.8
has no corresponding classes. Its `ActionChip` documentation defines:

- an assist chip as an action chip with an action icon/avatar; and
- a suggestion chip as an action chip with a label and no icon/avatar.

Document those roles on the existing `Material.action_chip` and demonstrate
both in the gallery.

Add a shared semantic chip presentation:

```ocaml
type chip_presentation =
  | Flat
  | Elevated
```

`action_chip`, `filter_chip`, and `choice_chip` accept the presentation
and map to their standard or `.elevated` Flutter constructors. The existing
`input_chip` remains flat because Flutter has no `InputChip.elevated`.
Malformed wire data requesting an elevated input chip is rejected.

The shared variant is included in chip properties, equality, fingerprints,
encoding, decoding, and the existing shared Dart chip renderer. No new chip
node kinds or public assist/suggestion aliases are introduced.

### Existing card and divider families

Extend the existing card node with:

```ocaml
type card_variant =
  | Elevated
  | Filled
  | Outlined
```

The current `Card` mapping is `Elevated`. The renderer maps the other
variants to `Card.filled` and `Card.outlined`. Theme defaults remain
authoritative, and the existing optional finite non-negative elevation remains
available for all variants. No new card node kinds are introduced.

Extend the existing divider node with:

```ocaml
type divider_orientation =
  | Horizontal
  | Vertical
```

Add shared optional thickness, cross-axis spacing, indent, and end-indent
properties. The renderer maps orientation to `Divider` or
`VerticalDivider`. Public naming should describe shared semantics instead of
exposing Flutter's asymmetric `height` and `width` names. All supplied
geometry must be finite and non-negative. No new divider node kind is
introduced.

### Protocol, reconciliation, and testing

Append node kinds and property tables for search bar, tooltip, data table,
stepper, expansion panel list, simple dialog, and fullscreen dialog. Preserve
existing numeric IDs and never reuse removed IDs. Extend existing chip, card,
and divider property tables rather than allocating variant-specific nodes.

Add typed event tags and payloads for search edits, table sort requests, row
selection, select-all, cell activation, step selection, expanded-ID sets, and
simple-dialog option selection. Reuse the existing `Text_edit`, `Int64`,
and `Int64_list` payloads where their shapes match. Do not encode structured
events as strings or overload `Value_changed` with multiple payload shapes.

Every variable child structure has explicit presence/count metadata and
canonical ordering. Equality and fingerprints include every property and
descriptor that affects rendering. Handler identity remains outside visual
fingerprints. Stateful hosts dispose controllers, focus resources, timers,
listeners, overlays, and callbacks when replaced or dropped.

Each component family requires:

1. public OCaml construction and compile-surface tests;
2. equality, fingerprint, reconciliation, and wire-frame tests;
3. OCaml/Dart codec round trips and malformed-frame rejection;
4. Flutter widget, event, controlled-update, semantics, focus, and disposal
   tests;
5. Material documentation; and
6. gallery examples for every selected variant.

Implementation may be committed in verified family-sized batches, but all
selected families belong to this decision.

## Decision

Implement only standalone `SearchBar`, general `Tooltip`, non-paginated
`DataTable`, `Stepper`, controlled `ExpansionPanelList`,
`SimpleDialog`, `Dialog.fullscreen`, the merged existing `AlertDialog`
family, assist/suggestion documentation for `ActionChip`, elevated action,
filter, and choice chips, filled/outlined cards, and vertical dividers.

Explicitly exclude `SearchAnchor`, `MaterialBanner`, `CarouselView`,
`PaginatedDataTable`, and `AboutDialog` from this decision. They require
separate future decisions and must not be partially implemented, emulated
through compatibility fallbacks, or included under hidden experimental APIs.

## Alternatives considered

### Keep the original broad component scope

The broad scope included five components with unresolved state, navigation,
transient presentation, lazy data, or controller ownership. Combining them
with the unblocked components would delay delivery and encourage premature
contracts. Separate future decisions keep those trade-offs explicit.

### Add one node and public constructor per Flutter constructor

This would duplicate existing action-chip semantics, split card and divider
families, and leave alert and simple dialogs unrelated. Shared public families
and semantic variants provide one validation, protocol, documentation, and
renderer path where behavior matches.

### Implement the selected components as generic compositions

Generic text input, gesture, layout, table-like rows, and decorated boxes can
approximate some visuals, but they do not reproduce Material semantics,
keyboard behavior, accessibility, intrinsic table layout, stepper animation,
tooltip overlays, or theme defaults. Core Material behavior belongs in the
standard renderer.

### Use Flutter-owned indices as application identity

Indices become stale when OCaml reorders descriptors between an accepted frame
and event handling. Stable IDs preserve application identity and follow the
existing navigation, radio, segmented-button, and virtual-list patterns.

### Use `ExpansionPanelList.radio` for single mode

The radio constructor owns current selection in Flutter and accepts only an
initial open value. Rendering both modes with the controlled constructor keeps
OCaml authoritative and makes corrections deterministic.

### Keep `Material.alert_dialog` as a compatibility alias

That would retain two public paths for the same dialog family. Maintained call
sites should migrate directly to `Material.Dialog.alert`, and the obsolete
entry point should be removed.

## Acceptance criteria

- Only the components listed in the Decision section are implemented.
- `SearchAnchor`, `MaterialBanner`, `CarouselView`,
  `PaginatedDataTable`, and `AboutDialog` receive no node kinds, protocol
  fields, partial renderer paths, aliases, or experimental fallbacks.
- Standalone search bar uses the existing revisioned text editing contract and
  matches text-field selection, composing, focus, stale-update, and UTF-8 limit
  behavior.
- General tooltip supports the selected automatic trigger and lifecycle
  semantics without exposing manual control.
- Data table validates stable descriptors, controlled sort and selection, and
  emits typed stable-ID events.
- Stepper uses controlled current-step identity and safely replaces Flutter
  state when ordered step structure changes.
- Expansion panels support controlled single and multiple policies without
  using Flutter-owned radio state.
- Alert, simple, and fullscreen visuals share the `Material.Dialog` public
  family, while `Navigation.Modal_dialog` remains the sole route-policy owner.
- Action chip documentation and gallery coverage demonstrate assist and
  suggestion roles without adding duplicate constructors.
- Action, filter, and choice chips map flat/elevated presentation correctly;
  input chip remains flat and malformed elevated input-chip data is rejected.
- Card variants use the existing card node and map to `Card`,
  `Card.filled`, and `Card.outlined`.
- Divider orientation uses the existing divider node and maps to `Divider`
  and `VerticalDivider`.
- OCaml and Dart boundary validation, canonical children, equality,
  fingerprints, reconciliation, resource disposal, accessibility, public API,
  documentation, and gallery coverage satisfy the proposal.
- Protocol schema generation, cross-language fixtures, focused OCaml and
  Flutter tests, `dune build @all`, `dune runtest`, and
  `spec-dev-tool check --all` pass after implementation.
- Obsolete public paths replaced by the merged families are removed without
  compatibility aliases.

## Consequences

- The selected Material surface grows without depending on unresolved search
  overlay, transient banner, carousel virtualization, paginated source, or
  license-navigation contracts.
- Search bar and text field share one editing correctness model while retaining
  distinct Material renderers.
- Repeated interactive structures use stable IDs and controlled OCaml state.
- Dialog visuals have one discoverable public family and one existing external
  navigation owner.
- Chip, card, and divider additions extend existing nodes rather than
  multiplying equivalent protocol concepts.
- The public dialog merge is intentionally source-breaking for existing
  `Material.alert_dialog` call sites.
- Deferred components require new exploring documents before implementation.

## Risks

- Sharing the text controller engine can regress text-field behavior if the
  refactor is not protected by the existing revision and IME tests.
- `DataTable` performs intrinsic measurement and remains unsuitable for large
  data sets; pagination and virtualization are explicitly unavailable.
- Flutter's `Stepper` follows an archived Material stepper specification and
  asserts on structural changes unless the renderer replaces its state.
- Variable descriptor children increase protocol validation and reconciliation
  complexity.
- Tooltip overlays and stateful search resources can leak if replacement and
  drop cleanup are incomplete.
- Theme defaults can change with the pinned Flutter revision. Tests should
  assert semantic and stable structural behavior rather than incidental pixels.
- Removing `Material.alert_dialog` is a deliberate downstream source break.
