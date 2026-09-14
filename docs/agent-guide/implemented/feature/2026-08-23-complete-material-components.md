# Complete Material 3 Component Surface

## Problem

`Bonsai_flutter_ui.Material` currently exposes a small renderer-independent
Material surface:

- `scaffold` and `app_bar`;
- `elevated_button`, `text_button`, and `icon_button`;
- `checkbox`, `switch`, and `text_field`;
- `list_tile`, `divider`, `card`, and `dialog`; and
- `circular_progress_indicator`.

These nodes render through Flutter 3.44, where Material 3 is the default, but
using a Material 3 theme does not make the component surface complete. Common
application flows still require native widgets, generic gesture/layout
compositions, or application-specific renderer extensions for basic Material
interactions.

The highest-value gaps are:

1. all `FloatingActionButton` sizes and the extended variant, together with a
   real `Scaffold.floatingActionButton` slot;
2. `FilledButton`, `FilledButton.tonal`, and `OutlinedButton`;
3. `SnackBar` presentation;
4. `NavigationBar` and destinations;
5. `AlertDialog` and the remaining bottom-sheet surface; and
6. `Radio`, `Slider`, `RangeSlider`, and Material chip variants.

The existing components are also structurally narrow. `Material.scaffold`
accepts only an optional app bar and a body. Its Flutter renderer manually
places the app bar in a fixed-height column instead of using
`Scaffold.appBar`. Buttons expose only enabled state and autofocus. The generic
dialog node carries a `barrier_dismissible` property, but the renderer builds a
plain `Dialog` and does not consume that property. These limitations make it
hard to extend the surface coherently by adding isolated constructors.

Bottom sheets require special care because they are not wholly absent. The
repository already provides a route-owned declarative modal bottom sheet in
`Navigation.Modal_bottom_sheet`, including content-bounded, scroll-controlled,
and detented sizing, barrier policy, safe-area policy, focus, drag dismissal,
semantics, and transition timing. Adding a second modal-bottom-sheet mechanism
under `Material` would duplicate lifecycle ownership and create conflicting
navigation models. The remaining gap is primarily a persistent
`Scaffold.bottomSheet` slot and a clearer public relationship between the
Material surface and the existing modal presentation API.

The component additions also exceed the current event vocabulary.
`value_changed` carries only a boolean, while sliders need finite floating-point
values or ranges and navigation bars need a destination index. Transient
surfaces need explicit identity and completion semantics so Flutter rebuilds
do not replay a snack bar, dialog, or sheet accidentally.

The target baseline is Flutter 3.44's Material 3 implementation and its
[Material component catalog](https://docs.flutter.dev/ui/widgets/material),
not every helper class exported by `package:flutter/material.dart`.

## Proposal

Expand the renderer-independent Material API as one coherent component surface
rather than implementing each widget as an unrelated exception. The
implementation must preserve these system properties:

- OCaml owns application state and declares the current logical UI;
- Flutter owns only renderer resources and platform presentation mechanics;
- controlled component values flow from OCaml to Flutter and user changes flow
  back as typed events;
- theme defaults provide the standard Material 3 appearance;
- logical nodes remain serializable and incrementally reconcilable;
- transient presentation has stable identity and is not replayed by unrelated
  rebuilds; and
- obsolete APIs are removed when replaced instead of retaining compatibility
  wrappers or parallel legacy paths.

The resolved design choices are:

1. expose semantic and functional component parameters while inheriting visual
   styling from the Material theme; do not add per-component style objects;
2. present snack bars through a typed `Host_effect` with text content, an
   optional text action, duration, cancellation, and a typed close reason;
3. add `Navigation.Modal_dialog` as the sole modal owner and make
   `Material.alert_dialog` responsible only for the visual surface;
4. reuse `Navigation.Modal_bottom_sheet` for modal sheets and add only the
   persistent `Scaffold.bottomSheet` slot, without another sheet surface;
5. model radio selection as a serialized `Radio_group` with stable `int64`
   option IDs while application domain values remain in OCaml;
6. expose both slider `on_change` and `on_change_end`, make `on_change`
   optional and coalesced, guarantee delivery of `on_change_end`, and use a
   typed `{ start; end_ }` payload for range values; and
7. implement `ActionChip`, `FilterChip`, `ChoiceChip`, and `InputChip` in the
   first component release through distinct public constructors backed by
   shared internal properties, child validation, encoding, and theme handling.

## Decision

Adopt the proposal in full. Material components are represented by dedicated,
renderer-independent logical nodes and typed events; snack bars use the typed
host-effect lifecycle; modal policy remains owned by Navigation; styling comes
from Material 3 theme defaults; and every obsolete component path replaced by
this design is removed without a compatibility layer.

### Component scope

The selected public surface is grouped by behavior rather than by Flutter
constructor count.

| Group | Candidate public capability | Required Flutter mapping |
| --- | --- | --- |
| Scaffold | App bar, body, FAB, FAB location, bottom navigation bar, and persistent bottom sheet slots | `Scaffold` properties rather than a manual `Column` |
| Common buttons | Filled, filled tonal, outlined, elevated, text, and icon buttons | `FilledButton`, `FilledButton.tonal`, `OutlinedButton`, `ElevatedButton`, `TextButton`, `IconButton` |
| Floating action buttons | Standard, small, large, and extended variants | `FloatingActionButton`, `.small`, `.large`, `.extended` |
| Snack bars | Text, optional text action, duration, cancellation, and typed completion | Typed `Host_effect` implemented with `ScaffoldMessengerState.showSnackBar` |
| Navigation | Controlled selected index and typed destinations with label, icon, selected icon, and enabled state | `NavigationBar` and `NavigationDestination` |
| Dialogs | Material 3 alert surface with title, content, icon, and actions, separated from modal route policy | `AlertDialog` plus a route- or overlay-owned barrier |
| Bottom sheets | Reuse the existing modal route and add only the missing persistent scaffold slot | Existing `BonsaiModalBottomSheetRoute` and `Scaffold.bottomSheet` |
| Radio | Controlled selection with group semantics | `RadioGroup` and `Radio` rather than deprecated per-radio group ownership |
| Sliders | Single-value and range controls, optional divisions and labels, and drag lifecycle events | `Slider` and `RangeSlider` |
| Chips | Assist/suggestion action, filter/choice selection, and input deletion | `ActionChip`, `FilterChip`, `ChoiceChip`, and `InputChip` |

This scope does not include `Badge`, menus, date/time pickers, search,
`NavigationDrawer`, `NavigationRail`, `TabBar`, `Tooltip`, or linear progress.
Those remain separate future decisions so this change does not become an
unbounded mirror of Flutter's Material library.

### Public API shape

The OCaml API uses typed values for related variants and structured values for
repeated child metadata. The initial FAB shape is:

```ocaml
module Floating_action_button : sig
  type size =
    | Small
    | Standard
    | Large

  val icon
    :  ?key:Key.t
    -> ?size:size
    -> ?autofocus:bool
    -> on_press:Event.Handler.t
    -> icon:Widget.t
    -> unit
    -> Widget.t

  val extended
    :  ?key:Key.t
    -> ?autofocus:bool
    -> on_press:Event.Handler.t
    -> ?icon:Widget.t
    -> label:Widget.t
    -> unit
    -> Widget.t
end
```

Buttons should retain distinct public constructors because their Material
roles are meaningful at call sites:

```ocaml
val filled_button : ... -> Widget.t
val filled_tonal_button : ... -> Widget.t
val outlined_button : ... -> Widget.t
val elevated_button : ... -> Widget.t
val text_button : ... -> Widget.t
val icon_button : ... -> Widget.t
```

`Material.scaffold` should become the only core owner of Material scaffold
slots:

```ocaml
val scaffold
  :  ?key:Key.t
  -> ?app_bar:Widget.t
  -> ?floating_action_button:Widget.t
  -> ?floating_action_button_location:floating_action_button_location
  -> ?bottom_navigation_bar:Widget.t
  -> ?bottom_sheet:Widget.t
  -> body:Widget.Body.t
  -> unit
  -> Widget.t
```

The existing manual app-bar placement should be removed. The renderer should
pass recognized children directly to `Scaffold.appBar`,
`Scaffold.floatingActionButton`, `Scaffold.bottomNavigationBar`, and
`Scaffold.bottomSheet`. Child presence flags and a canonical child order must
be encoded explicitly and validated on both protocol boundaries.

Navigation destinations and chip configurations should be abstract OCaml
values with smart constructors. They may contain logical widget children such
as icons and labels, but their public representation should not expose wire
ordering or Flutter-only classes. `NavigationBar` remains controlled through a
selected index and emits the requested destination index. Filter, choice, and
input chips similarly receive controlled selected state where applicable. All
four chip roles have separate public constructors, while their implementation
shares common properties, child-slot validation, enabled and selected-state
encoding, and Material theme inheritance.

Radio controls expose group ownership rather than reproducing Flutter's
deprecated per-radio `groupValue` API. A `Radio_group` owns an optional selected
`int64` option ID and a collection of radio options with unique stable `int64`
IDs. A selection event carries the selected option ID. Applications map those
IDs to their domain values in OCaml; arbitrary domain values never enter the
wire protocol. The OCaml constructor rejects duplicate IDs and a selected ID
that is not present in the group, and Flutter repeats those validations at the
wire boundary.

Slider values must be finite. Constructors must reject invalid ranges,
out-of-range values, non-positive divisions, and reversed range selections
before a frame reaches Flutter. Flutter decoding must repeat wire-boundary
validation rather than trusting the OCaml producer. `on_change` is optional and
emits the most recent value at most once per Flutter frame while a drag is
active. `on_change_end` is required and its final value is never discarded by
coalescing. `RangeSlider` uses a typed `{ start; end_ }` value and event payload
instead of two unrelated scalar events.

### Styling depth

The component release inherits colors, typography, shape, state layers, and
elevation from `ThemeData` so every new component has correct
Material 3 defaults without serializing Flutter's full `ButtonStyle` or
`WidgetStateProperty` model.

Semantic component variants are in scope: filled versus filled tonal,
outlined, FAB size, chip role, selected state, disabled state, slider divisions,
and destination selection. Arbitrary per-state colors, cursors, padding,
shapes, elevation overrides, animation styles, `ButtonStyle`, and
`WidgetStateProperty` are not part of this decision. Applications style the
components through the inherited Material theme. A future renderer-neutral
design-token decision may add carefully selected customization without
copying Flutter style objects field-for-field.

### Transient presentation

Static nodes alone are insufficient for snack bars and modal barriers.

Snack bars use a typed host effect and intentionally accept text rather than an
arbitrary logical widget subtree:

```ocaml
type snack_bar_close_reason =
  | Action
  | Dismiss
  | Swipe
  | Hide
  | Remove
  | Timeout

val show_snack_bar
  :  ?cancellation:Cancellation.t
  -> ?action_label:string
  -> ?duration_ms:int
  -> t
  -> message:string
  -> unit
  -> (snack_bar_close_reason, error) result Bonsai.Effect.t
```

The Flutter host presents the message through
`ScaffoldMessengerState.showSnackBar`, maps Flutter's close reason to the typed
result, and sends exactly one response. Host-request identity prevents ordinary
widget rebuilds from replaying the presentation. Cancellation, runtime
replacement, and shutdown remove or close pending presentations and resolve
their effects through the existing host-effect error contract. This decision
does not add a declarative snack-bar node or arbitrary widget content.

`AlertDialog` separates its visual surface from modal presentation.
`Material.alert_dialog` describes optional icon, title, content, and action
children. A new `Navigation.Modal_dialog` page presentation exclusively owns
the barrier, focus, safe area, transition, dismissal, restoration, and back
behavior. The current `Material.dialog ~barrier_dismissible` API conflates
those concerns and is removed rather than retained as a second dialog policy.

Modal bottom sheets continue to use `Navigation.Modal_bottom_sheet`. This
decision does not add a second `showModalBottomSheet` host effect, modal route,
or reusable bottom-sheet surface. The persistent `bottom_sheet` child belongs
to `Material.scaffold`, maps directly to `Scaffold.bottomSheet`, and has no
modal barrier.

### Protocol and reconciliation

New component node kinds and properties must be appended to
`protocol/schema.sexp`, with stable numeric IDs and a protocol minor-version
increment. Existing IDs must not be reused. Generated OCaml and Dart constants,
debug names, and the readable protocol table remain generator-owned.

The new wire concepts are:

- button variants or separate button node kinds;
- FAB variant, enabled state, autofocus, optional label/icon flags, and
  scaffold location;
- scaffold slot-presence flags;
- navigation destination metadata and selected index;
- alert-dialog child-presence flags;
- radio selected/enabled state and group structure;
- slider value/range, limits, divisions, enabled state, and label;
- chip role, selected/enabled state, and optional child flags;
- `modal_dialog` page-presentation policy; and
- a `show_snack_bar` host request plus typed close-reason response.

The inbound event model needs typed payloads for at least destination indices,
floating-point values, and floating-point ranges. Event tags must encode one
payload shape each; a generic untyped `value_changed` payload must not be
introduced. Every finite-number payload must be validated when Dart emits it
and again when OCaml decodes it.

Node equality and fingerprints must include every property that affects
rendering or behavior. Event handler identity remains outside visual
fingerprints and travels through event bindings as it does for current
components. Stateful renderer hosts, if required for snack bars or radio
groups, must release controllers, messengers, timers, and callbacks when nodes
are replaced or dropped.

### Validation and testing

Each component group should have coverage at four levels:

1. public OCaml API construction and compile-surface tests;
2. OCaml widget equality, fingerprints, reconciliation, and wire-frame tests;
3. OCaml/Dart codec round trips, malformed-frame rejection, and generated
   protocol fixtures; and
4. Flutter widget tests for constructor mapping, controlled updates, disabled
   behavior, callbacks, semantics, focus, Material 3 rendering structure, and
   resource disposal.

The gallery should demonstrate every new component and all selected variants.
Tests should update a controlled value after a renderer event and prove that
the rebuilt Flutter widget reflects the authoritative OCaml state. Transient
surface tests must cover presentation, replacement, action, dismissal,
timeout, unrelated rebuilds, route changes, and runtime shutdown.

Accessibility acceptance must include semantic roles, labels, selected or
checked state, disabled state, keyboard activation, focus traversal, minimum
tap targets, text scaling, high-contrast theme behavior where Flutter provides
it, and reduced-motion behavior for transient surfaces.

## Alternatives considered

### Add thin one-off wrappers for each Flutter constructor

This would make the constructors available quickly, but it would leave
scaffold slots, typed selection events, transient lifecycle, validation, and
shared style policy unresolved. The resulting APIs would be inconsistent and
would likely need another source-breaking redesign.

### Expose Flutter Material classes directly through native widgets

Application-defined native widgets could implement every missing component.
That would bypass the renderer-independent logical tree, weaken protocol-level
validation and test queries, and force each application to maintain the same
bridges. Core Material components belong in the standard node registry.

### Model every interaction as a host effect

This fits snack bars and picker-like one-shot interactions, but it is a poor
fit for controlled components such as navigation bars, radio groups, sliders,
and chips. Host effects also cannot currently embed arbitrary logical widget
children. Effects should be considered only where presentation is genuinely
imperative.

### Model every transient surface as an ordinary child

An ordinary node does not define enqueueing, route barriers, focus ownership,
back navigation, replacement, timeout, or completion. Flutter may also rebuild
the same node many times. A transient presentation needs identity and a
stateful presentation owner even when its content is declarative.

### Add another modal bottom-sheet node under `Material`

The existing declarative navigation route already owns modal sheet mechanics
and has extensive sizing, keyboard, semantics, barrier, and transition tests.
A duplicate node would create two competing lifecycle implementations. The
existing route should be reused and clarified instead.

### Mirror Flutter's complete style objects in the first release

Serializing `ButtonStyle`, `WidgetStateProperty`, component theme data, and all
constructor parameters would greatly expand the protocol and couple the public
OCaml API to Flutter implementation details. Theme-driven Material 3 defaults
plus semantic variants provide a smaller stable foundation. A renderer-neutral
style model can be designed separately if the use cases require it.

### Keep the current dialog and scaffold APIs as compatibility wrappers

Parallel old and new constructors would preserve the existing structural
mistakes and make both paths permanent API surface. If the final design changes
their ownership or signatures, maintained call sites should migrate directly
and the obsolete paths should be removed.

## Acceptance criteria

- The implementation follows the resolved public OCaml shapes, child ordering,
  event payloads, protocol fields, validation rules, and presentation ownership
  in this proposal.
- `Material.scaffold` uses Flutter `Scaffold` slots for its app bar, FAB,
  bottom navigation bar, and any accepted persistent bottom sheet; the manual
  app-bar `Column` implementation no longer exists.
- Standard, small, large, and extended FABs are available, and the scaffold can
  place them through a typed location policy without exposing Flutter classes.
- Filled, filled tonal, and outlined buttons are available beside the retained
  Material 3 elevated, text, and icon roles.
- Snack bars use the typed host effect, accept text plus an optional text
  action, return a typed close reason, do not replay on rebuild, and clean up on
  cancellation, runtime replacement, and shutdown.
- `NavigationBar` supports typed destinations, controlled selection, disabled
  destinations, selected icons, semantics, and integer selection events.
- `AlertDialog` supports optional icon, title, content, and actions while modal
  barrier and route behavior have one explicit owner.
- Modal bottom sheets continue through `Navigation.Modal_bottom_sheet`; no
  duplicate modal route or host effect is introduced.
- Persistent bottom sheets are available only through `Scaffold.bottomSheet`
  and are tested independently from modal presentation; no standalone surface
  or duplicate modal API exists.
- Radio controls use one serialized group with stable unique `int64` option
  IDs and expose correct controlled selection and accessibility semantics.
- `Slider` and `RangeSlider` validate finite domains and selections, emit typed
  values, and support the selected drag event policy.
- Action, filter, choice, and input chip roles are all covered through distinct
  public constructors, including press, selection, and delete events where
  meaningful.
- Protocol schema generation, cross-language fixtures, codec tests, malformed
  input tests, OCaml reconciliation tests, Flutter widget tests, public API
  tests, and gallery coverage pass.
- Documentation explains controlled-state ownership, transient presentation,
  modal versus persistent sheets, theme-driven styling, and the supported
  Material 3 component matrix.
- Obsolete dialog, scaffold, or component paths replaced by the final design
  are removed without compatibility aliases or fallback renderers.
- `dune build @all`, `dune runtest`, focused Flutter tests, protocol fixture
  checks, and `spec-dev-tool check --all` pass after implementation.

## Consequences

- The renderer-independent Material surface now covers the selected Material 3
  scaffold slots, button roles, FAB variants, navigation bar, alert dialog,
  radio group, sliders, and chip roles through typed OCaml constructors and
  dedicated logical nodes.
- Protocol minor version 20 adds stable node kinds, properties, event tags,
  modal-dialog page fields, and the snack-bar host request. Generated OCaml and
  Dart constants, readable IDs, and cross-language fixtures are updated from
  the schema.
- Controlled selection and slider values remain owned by OCaml. Flutter emits
  typed destination, radio, scalar, and range payloads, coalescing continuous
  slider changes while preserving the final change-end event.
- Snack bars use request identity and renderer-owned `ScaffoldMessenger`
  resources, return typed close reasons, and participate in the existing
  cancellation and runtime-shutdown contracts instead of becoming declarative
  nodes.
- `Navigation.Modal_dialog` is the sole modal policy owner for alert dialogs,
  and `Navigation.Modal_bottom_sheet` remains the sole modal sheet API.
  Persistent sheets exist only as a direct `Scaffold.bottomSheet` child.
- The obsolete generic Material dialog node and public constructor are removed.
  Protocol node-kind ID 107 remains reserved as a tombstone and is not reused.
- Applications gain Material 3 theme defaults without a serialized Flutter
  style-object model. Component-specific style overrides remain outside this
  decision and require a separate renderer-neutral design if needed.
- The Gallery and maintained navigation examples use the new surfaces, and the
  OCaml, Flutter, protocol, fixture, formatting, viewport-type, and agent-doc
  validation suites pass with the implementation.

## Risks

- Adding all groups in one implementation change creates a large protocol and
  testing surface. Staging may be required even if one decision defines the
  final coherent API.
- A Flutter-shaped style API would erode renderer independence, while an API
  that is too theme-only may be insufficient for real applications.
- Incorrect transient identity can replay snack bars or lose completion
  callbacks during ordinary reconciliation.
- The typed snack-bar host effect deliberately gives up arbitrary widget
  content. Applications needing custom transient surfaces must use a different
  UI or a future separately designed presentation mechanism.
- Dialog and bottom-sheet barriers interact with back navigation, focus,
  keyboards, safe areas, restoration, and nested navigators.
- Navigation destinations and chips contain variable child structures, making
  child-order validation and incremental reconciliation more complex.
- Continuous slider events can generate excessive worker traffic and frame
  churn unless drag semantics or coalescing are explicit.
- Radio groups must preserve mutual exclusion and keyboard traversal without
  serializing arbitrary OCaml domain values.
- Material component defaults can change with the pinned Flutter version. Tests
  should assert semantic and structural contracts rather than fragile pixels
  except where visual regression coverage is intentional.
- Removing the old scaffold and dialog shapes is a deliberate source-breaking
  change for current applications and examples.
