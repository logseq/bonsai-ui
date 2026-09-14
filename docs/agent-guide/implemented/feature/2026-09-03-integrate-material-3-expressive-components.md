# Integrate Material 3 Expressive Components

## Problem

`bonsai_flutter` renders its logical Material nodes with Flutter SDK Material
widgets. Material 3 is enabled and application theme data is owned by OCaml,
but the renderer does not provide the spring motion, shape morphing, expressive
state layers, or component geometry of Material 3 Expressive.

The [`material_3_expressive`](https://pub.dev/packages/material_3_expressive)
package provides direct `M3E*` widgets for 45 widgets across 40 component
modules. Version 1.1.1 requires Flutter 3.44 or newer and Dart 3.12, which
matches this repository's Flutter 3.44 and Dart 3.12.2 baseline. The package is
therefore a plausible renderer dependency for every component that overlaps
the current Bonsai surface and the source for new logical widgets covering the
rest of its advertised component catalog.

The overlap is not equivalent to a mechanical class rename. Several package
widgets expose a narrower or differently shaped API than the existing logical
node contract:

- `M3EChip` accepts a string label rather than an arbitrary label widget, has
  one press callback rather than distinct selection semantics, and does not
  accept a custom delete icon;
- `M3EExtendedFab` requires an icon and a string label, while the Bonsai
  extended FAB has an optional icon and an arbitrary label widget;
- `M3ESegmentedButton` supports only horizontal segments with string labels,
  no per-segment enabled state or tooltip, no custom selected icon, and no
  explicit empty-selection policy;
- `M3ENavigationBarDestination` has no enabled state;
- `M3ETooltip` does not expose Bonsai's tap trigger, placement, duration,
  feedback, semantics, or triggered callback controls;
- `M3ETextField` lacks read-only and autofocus controls, while its change
  callback is string-only rather than the revisioned text-editing contract;
- `M3EListItem` accepts string headline and supporting text rather than
  arbitrary title and subtitle widgets;
- `M3EDialog` requires a string title and has no direct simple-dialog or
  declarative full-screen surface equivalent; and
- `M3ESnackbar.show` owns a simple overlay timer and returns no close reason,
  while `Host_effect.show_snack_bar` has cancellation, action, queuing, and
  typed completion semantics.

The package also requires `material_ui` for the Material library and explicitly
instructs clients to replace `package:flutter/material.dart` imports. That
affects renderer, navigation, native-widget, root, and test files beyond the
individual component builders.

The integration must preserve Bonsai's architecture unless a deliberate API
change is approved: OCaml owns application state and logical widget values,
Flutter owns rendering resources, transient route policy remains in
`Navigation`, and there is exactly one framework-owned application root.
There must not be a mixture of old and new implementations selected by runtime
conditions, compatibility aliases, or fallback paths.

The research baseline is
[`material_3_expressive` 1.1.1](https://github.com/paadevelopments/material_3_expressive/tree/v1.1.1)
at commit `26e0159712cf1a314f8cb33b485d4259fb5d2dea`.

## Proposal

Integrate `material_3_expressive` as the native renderer for its complete
advertised component catalog:

1. replace every current Bonsai component that has an M3E counterpart;
2. add renderer-independent OCaml support for every advertised M3E component
   family that Bonsai does not yet expose; and
3. retain `material_ui` implementations only for current Bonsai components for
   which the package has no counterpart, such as `Scaffold`, `DataTable`, and
   `Stepper`.

Keep logical node kinds, stable identity, controlled values, wire encoding, and
typed events unchanged when the package API can satisfy the existing contract.
When an M3E counterpart cannot represent the existing contract, reshape the
OCaml API and protocol to the M3E-supported semantics and remove the obsolete
capabilities. Do not keep aliases or render the M3E widget for a subset of
values while falling back to the old widget for the rest.

"Complete advertised catalog" means the component families documented in the
package README and gallery. Infrastructure and design foundations such as
`M3ETheme`, `M3EMaterialApp`, theme data, controllers, painters, shapes, and
typography helpers are implementation support rather than independent Bonsai
widgets. Constructor variants such as wavy progress, vertical sliders, date
ranges, and inline versus modal pickers remain in scope as semantic variants
of their component family.

### Dependency and theme integration

Pin `material_3_expressive` exactly to 1.1.1. Add `material_ui` as a direct,
exactly pinned dependency because repository code will import it directly.
Do not use a caret or other compatible-version constraint for either renderer
dependency. Replace `package:flutter/material.dart` imports throughout the
Flutter package and its tests with focused `package:flutter/widgets.dart`,
`package:flutter/services.dart`, and `package:material_ui/material_ui.dart`
imports as appropriate.

Do not replace `BonsaiFlutterRoot`'s single `MaterialApp` with
`M3EMaterialApp`. The latter owns adaptive brightness, dynamic colors, and its
own theme controller, which would conflict with the OCaml-owned
`Theme.application` contract. Initially let each M3E component use
`M3ETheme.of(context)`, whose documented fallback derives `M3EThemeData` from
the nearest Material `ThemeData`. This also allows `Ui.Widget.theme` subtree
overrides to remain visible; a root `M3ETheme` would otherwise mask nested
Material themes.

The package-derived theme is accepted as a fixed renderer mapping for
emphasized typography, motion, shapes, spacing, elevation, haptics, and
per-component themes. Those values remain unconfigurable from OCaml in this
decision. A future decision may add renderer-neutral expressive tokens after a
real cross-renderer customization requirement exists. Dynamic color, automatic
theme mode, and an M3E theme controller are out of scope.

### Current overlap inventory

The table classifies current core nodes and presentation mechanisms against
the 1.1.1 package API. "Direct" means the existing logical contract can be
preserved with a single M3E renderer. "Adapter" means a structural host is
needed without retaining the old visual implementation. "Breaking replacement"
means the package API cannot express at least one current capability, so the
obsolete Bonsai capability is removed. "No counterpart" means the package does
not implement the current component, which therefore remains on `material_ui`.

| Current Bonsai surface | Package mapping | Status | Required treatment |
| --- | --- | --- | --- |
| `Widget.button`, filled, tonal, elevated, outlined, and text buttons | `M3EButton` styles | Direct | Preserve enabled state, autofocus, arbitrary child, and press event. |
| `Material.icon_button` | `M3EIconButton` | Breaking replacement | Remove the public autofocus parameter because the package widget does not expose it. |
| `Material.Floating_action_button.icon` | `M3EFab` | Direct | Map small, standard, and large to small, medium, and large; preserve disabled and autofocus behavior. |
| `Material.Floating_action_button.extended` | `M3EExtendedFab` | Breaking replacement | Require an icon and string label; remove the arbitrary label child and optional-icon shape. |
| `Material.app_bar` | `M3EAppBar.top` | Adapter | Preserve arbitrary title and centered-title behavior; verify safe-area and preferred-size geometry inside `Scaffold`. |
| `Widget.Sliver.app_bar` | `M3EAppBar.sliver` | Breaking replacement | Remove expanded/collapsed heights, stretch, toolbar height, forced elevation, flexible space, and bottom slot controls; add the M3E variant, shape, and density semantics. |
| `Material.navigation_bar` | `M3ENavigationBar` | Breaking replacement | Remove per-destination enabled state; add M3E layout, label/icon behavior, size, shape, density, and badge semantics. |
| `Material.Radio_group` | repeated `M3ERadio<int>` | Direct | Keep the group-level stable-ID contract and emit the selected ID from each enabled radio. |
| `Material.Segmented_button` | `M3ESegmentedButton<int>` | Breaking replacement | Require string labels, horizontal direction, package selection behavior, and remove per-segment enabled/tooltip plus custom selected-icon controls. |
| `Material.slider` | `M3ESlider` | Direct and extend | Retain frame-coalesced change plus guaranteed change-end events; add centered, wavy, wavy-centered, vertical, and vertical-centered variants. |
| `Material.range_slider` | `M3ERangeSlider` | Direct and extend | Convert the typed range value, retain event guarantees, and add the wavy variant. |
| action, filter, choice, and input chips | `M3EChip` | Breaking replacement | Collapse the public family to M3E assist, suggestion, filter, and input types with string labels, leading child, selected state, press, and delete behavior; remove unsupported custom delete-icon and distinct `on_selected` shape. |
| `Material.checkbox` | `M3ECheckbox` | Direct | Keep the existing binary controlled value and typed boolean event. |
| `Material.switch` | `M3ESwitch` | Direct | Keep the existing controlled value and typed boolean event. |
| `Material.search_bar` | `M3ESearchBar` | Direct | Continue using `TextInputHost` for revision, selection, composing, focus, submission, and UTF-8 limit ownership. |
| `Material.text_field` | `M3ETextField` | Breaking replacement | Remove read-only and autofocus, retain the revisioned text host, and add filled/outlined, label, supporting/error text, leading/trailing, and multiline semantics. |
| `Material.list_tile` | `M3EListItem` | Breaking replacement | Replace arbitrary title/subtitle slots with string headline/supporting/overline fields and preserve leading/trailing children plus controlled selected state. |
| `Material.divider` | `M3EDivider` | Adapter | Wrap the M3E line to preserve Bonsai's independent cross-axis spacing property. |
| `Material.card` | `M3ECard` | Adapter | Map all three variants and pass zero padding so existing child layout does not acquire the package's default 16 dp inset. |
| circular and linear progress | `M3EProgressIndicator` | Direct and extend | Preserve determinate/indeterminate values and add explicit circular-wavy and linear-wavy variants. |
| `Material.Dialog.alert` | `M3EDialog` | Breaking replacement | Require a string title, retain optional icon/content and actions, and add top/bottom-divider semantics. |
| `Material.Dialog.simple` | none | No counterpart | Keep the current `SimpleDialog` implementation. |
| `Material.Dialog.fullscreen` | no constructible public surface | No counterpart | Keep the current declarative full-screen visual node on `material_ui`; the package's imperative `showFullScreen` helper cannot participate in the Navigation-owned route model. |
| `Material.Data_table` | none | No counterpart | Keep the current Material implementation. |
| `Material.Stepper` | none | No counterpart | Keep the current Material implementation. |
| `Material.Expansion_panel_list` | `M3EExpandableList` is a different contract | No counterpart | Keep the current externally controlled expansion-panel implementation. |
| `Material.tooltip` | `M3ETooltip` | Breaking replacement | Retain plain message and child; remove tap trigger, placement, duration, feedback, semantics-exclusion, and triggered-event parameters, then add rich title/message/actions as package-supported semantics. |
| `Host_effect.show_snack_bar` | `M3ESnackbar` | Adapter | Render the M3E visual surface through a Bonsai host that preserves cancellation, queueing, action, and close-reason completion instead of calling the package's fire-and-forget `show`. |
| `Navigation.Modal_bottom_sheet` and persistent scaffold bottom sheet | `M3EBottomSheet` | Adapter | Replace sheet visuals with the M3E surface while retaining Navigation-owned route presence, detents, keyboard coordination, barrier policy, safe-area policy, and typed completion. |
| `Material.scaffold` | none | No counterpart | Continue using `material_ui`'s `Scaffold`; only its supported slot children become expressive. |

### New component surface

Add the remaining advertised component families under `Ui.Material` or the
existing presentation owner indicated below. Public OCaml types expose semantic
variants, stable IDs, controlled values, and logical children. They do not
expose Dart generic values, `BuildContext`, builders, controllers, futures,
`WidgetStateProperty`, gradients, painters, or package theme classes.

#### Actions and selection

| Package component | Proposed Bonsai surface | State and event contract |
| --- | --- | --- |
| `M3EFabMenu` | `Material.Fab_menu` with left/right position, expand/collapse icons, and non-empty item descriptors | Flutter may own ephemeral open/close animation state. Each item has a stable `int64` ID, icon, string label, enabled state, and press event carrying the ID. |
| `M3EButtonGroup` | `Material.Button_group` with standard/connected type, button style/size/shape, axis, overflow policy, and action descriptors | OCaml owns optional single or multiple selected ID sets. Selection events carry stable IDs, never package indices. |
| `M3EToggleButton` | `Material.Toggle_button` with filled, tonal, elevated, outlined, and text styles plus optional normal/checked icon and label children | Controlled `checked:bool`; user interaction emits the requested boolean. |
| `M3ESplitButton` | `Material.Split_button` with filled, tonal, elevated, or outlined style, primary action, and a non-empty typed menu tree | Primary press emits unit; menu selection emits a stable item ID. Rich groups, dividers, and submenus reuse `Material.Menu` descriptors. |
| `M3EDropdownMenu` | `Material.Dropdown_menu` with static, loading, empty, and error content states, single/multiple selection, optional search, and item descriptors | OCaml owns available items, selected IDs, query, and async loading. Selection and query events are typed; the Dart `.future` constructor is not exposed across FFI. |
| `M3ESlider` variants | Extend `Material.slider` with standard, centered, wavy, wavy-centered, vertical, and vertical-centered kinds | Retain controlled value plus coalesced change and guaranteed change-end events. Renderer-only track builders and painter customization remain theme-owned. |
| `M3ERangeSlider.wavy` | Extend `Material.range_slider` with flat or wavy kind | Retain the controlled typed range and existing event guarantees. |
| `M3EDatePicker` and `M3ECalendarDatePicker` | `Material.Date_picker.calendar` for the inline widget plus `Host_effect.pick_date` and `Host_effect.pick_date_range` for modal presentation | Dates use timezone-free civil `{ year; month; day }` records. Bounds, current date, selected date/range, calendar mode, and selectable dates require deterministic validation. Typed effects wrap the package helper and return a value or cancellation. |
| `M3ETimePicker` and `M3EDialTimePicker` | `Material.Time_picker.dial` for the inline widget plus `Host_effect.pick_time` for modal presentation | Time uses `{ hour; minute }` with explicit 12/24-hour presentation. The typed effect wraps the package helper and returns a time or cancellation. |

`M3EButtonGroup` overflow menus and `M3ESplitButton` menus use renderer-owned
overlay presence but not renderer-owned selection. Async dropdown loading stays
in OCaml: an application handles a query/open event, performs its effect, and
publishes loading, error, or item descriptors in a later accepted frame.

#### Containment

| Package component | Proposed Bonsai surface | State and event contract |
| --- | --- | --- |
| `M3ECarousel` | `Material.Carousel` with hero, contained, and uncontained layout, horizontal/vertical axis, stable keyed children, and hero alignment | Tap and layout-change events translate package indices to accepted-frame stable child IDs. Scroll offset and animation resources remain in Flutter. |
| `M3ECardList` | `Material.Card_list` with finite, scrollable, and sliver forms and stable keyed item children | The logical tree supplies children directly; Dart `itemBuilder` closures are renderer implementation details. Large data remains served through the existing virtual-sliver ownership model rather than serializing absent items. |
| `M3ESelection` | `Material.Selection` host, contextual app bar, and selection-leading wrapper | OCaml owns the canonical sorted set of selected stable item IDs. A renderer resource bridges that set to `M3ESelectionController`; select, toggle, clear, and select-all events carry IDs. System back emits a clear request before route pop. |
| `M3EDismissibleColumn` | `Material.Dismissible_list.column` | Items have stable IDs. A direction-aware dismissal request uses an explicit pending/accepted/rejected handshake so the package's `Future<bool>` never becomes business-state ownership. |
| `M3EDismissibleList` | `Material.Dismissible_list.horizontal` | Same stable-ID dismissal handshake as the column form; Flutter owns only drag and removal animation resources. |
| `M3EExpandableList` | `Material.Expandable_list` with finite, scrollable, and sliver forms | Add the component alongside, not in place of, `Expansion_panel_list`. OCaml owns expanded stable IDs and single/multiple policy; an adapter synchronizes the package's index-based internal state after every accepted frame. |
| `M3EBottomSheet` | `Material.Bottom_sheet.surface`, the persistent Scaffold slot, and `Navigation.Modal_bottom_sheet` | The constructible surface owns only M3E shape, handle, and motion. `Scaffold` or `Navigation` owns presence; existing modal route, keyboard, barrier, safe-area, detent, and completion contracts remain authoritative. |
| `M3ESideSheet` | `Material.Side_sheet.surface` and `Navigation.Modal_side_sheet` | Title and body are logical children; route presence, barrier, dismissal, safe area, and completion follow a typed Navigation presentation contract. |

`M3EListItem`, `M3ECard`, `M3EDivider`, and `M3EDialog` are covered by the
replacement table. The existing `Material.Expansion_panel_list` remains a
separate Material component because `M3EExpandableList` has different visuals,
layout forms, and state behavior rather than being its renderer equivalent.

#### Navigation and feedback

| Package component | Proposed Bonsai surface | State and event contract |
| --- | --- | --- |
| `M3EAppBar.bottom` and `.search` | Replace the flat `app_bar` function with `Material.App_bar.top`, `.bottom`, `.sliver`, and `.search` | Top/bottom bars expose logical slots. Search reuses the revisioned text/search contract and typed suggestions; bar-local focus/open animation stays in Flutter. |
| `M3ETabs` | `Material.Tabs` with primary/secondary variant and non-empty stable tab descriptors | OCaml owns selected tab ID; selection emits the requested stable ID. Labels are strings and optional icons are logical children. |
| `M3ENavigationRail` | `Material.Navigation_rail` with sections, destinations, collapsed/expanded modality, trailing slot, and optional FAB descriptor | Selected destination and requested expanded/collapsed type are typed controlled values. Package indices translate to stable destination IDs. |
| `M3ENavigationDrawer` | `Material.Navigation_drawer` with headline and stable destination descriptors | OCaml owns the selected destination ID and drawer route/presence; selection emits a stable ID. |
| `M3EToolbar` | `Material.Toolbar` with floating/docked placement, axis, semantic action descriptors, overflow, optional FAB, controlled expanded state, and controlled active action | Action/FAB/overflow events carry stable IDs. Scroll-exit visibility uses renderer resources driven by the existing scroll-notification domain. |
| `M3EMenu` | `Material.Menu` with an anchor child and typed entry, selectable, toggleable, widget, group, divider, and submenu descriptors | Flutter owns temporary overlay presence and collision-aware placement. OCaml owns selected/toggled values; events carry stable node IDs. |
| `M3EBadge` | `Material.badge` wrapper with dot/count, top-left/top-center/top-right alignment, and child | Pure logical wrapper with no event or renderer-owned business state. |
| `M3ELoadingIndicator` | `Material.loading_indicator` with uncontained/contained variant | Pure feedback node; optional host-driven rotation is a finite controlled value. |
| `M3ERefreshIndicator` | `Material.Refresh_indicator` wrapper with expressive, contained, Material, adaptive, and no-spinner variants | Refresh emits a request token and stays refreshing until OCaml completes that token. Programmatic show is a typed command/effect, not an exposed Dart controller. |
| rich `M3ETooltip` | Extend the replacement `Material.tooltip` with a plain or rich content kind | Rich title/message are strings and actions are logical children. Overlay presence and dismiss timing stay renderer-local. |
| `M3ESearchAnchor` | `Material.Search_anchor` with revisioned text state, bar slots, controlled suggestions, and full-screen/docked presentation | Search query/edit/submit/open/close/suggestion events are typed. Suggestions have stable IDs; package controller and search-view route are renderer resources, not application state. |

The existing circular and linear progress nodes gain explicit wavy variants,
and the existing snackbar host renders `M3ESnackbar`. This completes the
Feedback catalog without introducing a second transient-message API.

### Protocol and ownership implications

The additional surface requires new protocol node kinds, property records,
child-slot validation, event tags, payload shapes, fingerprints, debug names,
and cross-language fixtures. Repeated interactive descriptors use unique
signed `int64` IDs. Date and time payloads use validated explicit records rather
than Unix timestamps, locale-formatted strings, or Dart objects. Selection sets
are canonicalized in signed ascending order before equality and encoding.

Renderer resources are permitted for focus nodes, text/search controllers,
scroll controllers, overlay portals, animation controllers, package selection
controllers, and pending async-completion handles. Their identity is keyed by
logical node ID and epoch, and they are disposed when the node or runtime is
removed. They may retain presentation mechanics but never become the source of
truth for selected IDs, text, application routes, or data-loading results.

Package APIs that require `Future<bool>` or `Future<void>` use a protocol
request-token handshake rather than an immediate optimistic answer. Dismiss and refresh
requests carry a monotonically increasing token. A later accepted frame marks
that token pending, accepted/completed, or rejected, allowing the renderer to
complete the package future exactly once. Stale completions from an earlier
node binding or runtime epoch are ignored.

Ordinary dialogs, bottom sheets, and side sheets remain declarative
`Navigation` presentations. Their M3E widgets provide visual surfaces only;
they do not call package `show*` helpers or own the application route stack.
Date and time pickers are the deliberate exception: they are typed
`Host_effect` operations because their complete contract is to open a
short-lived picker and return one value or cancellation. Only the host-effect
dispatcher calls the corresponding package helper; application and logical
widget APIs never receive `BuildContext`, Dart futures, or raw `show*` access.

Built-in `Native_widget` implementations are not separate public component
families in the M3E catalog. They continue to compose the public logical nodes
where possible, and their private Material controls are migrated only when the
same M3E component can preserve the extension's documented behavior. This
avoids silently changing native-extension layout or gesture contracts while
still preventing a second public legacy component path.

### Replacement rules

1. Keep one implementation per logical node kind. Do not inspect properties to
   select M3E versus legacy Material at runtime.
2. Do not add compatibility constructors, aliases, deprecated parameters, or
   protocol fallbacks. If a logical contract is narrowed, remove the obsolete
   path from the OCaml API, protocol schema, renderer, tests, examples, and
   documentation in the same change.
3. Preserve controlled state. Package widgets must receive current values from
   accepted frames and must never become the authoritative owner of selection,
   text, navigation, slider, or expansion state.
4. Preserve existing event identity and delivery guarantees, especially text
   revisions, slider coalescing, stable IDs, and host-effect completion.
5. Keep ordinary modal route and barrier ownership in `Navigation`. Static M3E
   `show*` helpers are called only inside the typed date/time picker host-effect
   dispatcher, never directly by application or logical widget code.
6. Prefer package theme defaults over serializing Dart style objects. Any new
   renderer-neutral semantic variant requires a separate explicit decision.
7. Update gallery coverage so every replaced and newly added component is
   rendered in enabled, disabled, selected, unselected, light, and dark states
   where applicable.

## Decision

Adopt `material_3_expressive` 1.1.1 as the sole renderer for its complete
advertised component catalog. Replace overlapping Bonsai components, add the
missing renderer-independent OCaml component families, and narrow contracts
that the package cannot represent. Keep `material_ui` only for components with
no constructible M3E counterpart. Preserve OCaml ownership of business state,
Navigation ownership of declarative routes, and typed host effects for modal
date and time pickers. Remove obsolete APIs and protocol paths without
compatibility layers or runtime fallbacks.

## Alternatives considered

### Apply only an expressive theme to Flutter Material widgets

Keep all current constructors and imitate Material 3 Expressive with
`ThemeData`, component themes, and local decoration. This preserves API parity,
but it does not use the requested package's direct widgets and cannot reproduce
their spring-driven geometry and interaction behavior consistently.

### Replace only exact overlaps and omit the remaining catalog

Replace only components whose current public contract maps directly, leave
narrower same-named components on Material, and do not add package-only
families. This would minimize breaking API changes, but it does not satisfy the
requested complete replacement and catalog expansion. It would also preserve
two visual systems without a principled component boundary.

### Preserve current contracts with forks or copied M3E internals

Fork the package or copy its internal painters and interaction primitives to
fill every API gap. This could preserve contracts while matching the visuals,
but it transfers maintenance of a young and rapidly changing design system to
this repository and would no longer be a straightforward package integration.

### Keep both renderers behind a flag

Add a theme option or runtime feature flag that switches between legacy
Material and M3E. This doubles the renderer and test matrix and creates the
fallback and compatibility paths prohibited by the repository policy.

## Acceptance criteria

- `material_3_expressive` is a direct exact `1.1.1` dependency;
  `material_ui` is also direct and exactly pinned. Both resolve on the
  repository's Flutter/Dart baseline without a compatible-version constraint.
- No Flutter package or test file imports `package:flutter/material.dart` after
  the `material_ui` migration.
- Every current component with an M3E counterpart renders the corresponding
  `M3E*` component through one renderer path. Direct and Adapter replacements
  retain their existing logical/event contract; Breaking replacements remove
  every obsolete API, protocol, test, example, and documentation path.
- Existing `Scaffold`, `SimpleDialog`, declarative full-screen dialog,
  `DataTable`, `Stepper`, and `ExpansionPanelList` nodes remain on `material_ui`
  because the package has no constructible equivalent component for their
  contracts; this exception does not create a runtime fallback.
- Every advertised package component family in the complete catalog has a
  renderer-independent Bonsai entry point, including FAB menus, button groups,
  toggle and split buttons, dropdowns, all slider variants, date/time pickers,
  carousel, card/selection/dismissible/expandable lists, bottom and side sheets,
  all app-bar variants, tabs, navigation rail/drawer, toolbars, menus, badges,
  loading and refresh indicators, rich tooltips, and search anchors.
- New repeated interactive models use unique stable signed `int64` IDs and
  translate accepted-frame IDs to package indices only inside the renderer.
- Date/time values and results use validated typed protocol records. No locale
  string, Unix timestamp, or Dart object crosses the wire.
- Dropdown loading, dismiss confirmation, refresh completion, and other async
  workflows are owned by OCaml and use epoch-safe typed request/completion
  handshakes; no Dart `Future`, builder, or controller crosses FFI.
- `BonsaiFlutterRoot` still owns exactly one `MaterialApp`, follows the
  OCaml-selected theme mode and high-contrast variant, and does not install an
  M3E theme controller or dynamic-color owner.
- Application and subtree theme changes update all replaced components without
  replacing logical node identity or retaining a stale derived M3E theme.
- Text input still preserves UTF-16 selection and composing ranges, rejects
  stale edits, respects UTF-8 limits, and disposes renderer-owned controllers
  and focus nodes.
- Slider and range-slider continuous changes remain coalesced to at most one
  per frame, and every change-end value is delivered.
- Navigation, tabs, rails, drawers, menus, dropdowns, button groups, radio,
  segmented selection, table, dialog option, carousel, selection, and expansion
  events use accepted-frame stable IDs or documented destination indices.
- Snack-bar, dialog, bottom-sheet, and side-sheet presentation retains typed
  completion, cancellation, Navigation route, barrier, keyboard, and safe-area
  contracts while using M3E visual surfaces. Date/time picker host effects
  return typed values or cancellation and expose no raw package helper.
- Widget tests cover every replaced and newly added family, including
  semantics, keyboard focus, disabled interaction, RTL, text scale, reduced
  motion, light/dark themes, high contrast, overlay dismissal, controller
  disposal, stable-ID translation, and stale async completion.
- Gallery screenshots are regenerated and reviewed for overflow, clipping,
  safe-area regressions, and unexpected padding changes on supported target
  sizes.
- Flutter analysis, Flutter tests, OCaml tests, cross-language fixtures, example
  builds, and repository-wide agent-document checks pass.
- Patch-size and runtime benchmark results record the cost of
  `material_3_expressive`, `material_ui`, `motor`, `material_new_shapes`, and
  `dynamic_color` relative to the existing baseline.

## Consequences

Applications gain the complete M3E catalog, expressive motion and geometry,
typed date/time pickers, stable-ID interaction models, and consistent M3E
visuals across replaced components. Existing OCaml code using removed
parameters or the old app-bar, list-item, alert-dialog, tooltip, chip,
segmented-button, icon-button, FAB, text-field, or sliver-app-bar contracts must
be updated to the new APIs. The renderer dependency graph and binary input grow,
and future package upgrades require explicit behavioral, visual, protocol, and
performance review. Controlled state, route ownership, subtree themes, FFI
types, and resource disposal remain within the existing Bonsai architecture.

## Implementation

Implemented the complete advertised component catalog against
`material_3_expressive` 1.1.1 and `material_ui` 1.1.1. The renderer now uses
the M3E widgets for every overlapping component, while the explicitly listed
components with no M3E counterpart remain on `material_ui`. All
`package:flutter/material.dart` imports were removed.

The public OCaml surface now includes the replacement APIs and the new action,
selection, containment, navigation, feedback, date, and time families described
above. The complete new catalog is encoded by the `Material_expressive` node
with component selectors 0 through 30. Stable descriptor IDs, canonical
selection sets, controlled values, slot validation, and typed events are
validated on both sides of the wire. Existing node kinds whose contracts were
narrowed no longer encode or expose the obsolete capabilities; the retired
app-bar, list-item, alert-dialog, and tooltip protocol kinds were removed
instead of retained as aliases.

The protocol version is 2.26. Typed civil-date, civil-date-range, and time
payloads are used by the modal picker host effects. Search open and close
events, request-token dismiss and refresh handshakes, controller lifecycle,
selection translation, and carousel layout callbacks are bound to accepted
node identity and runtime epoch. `Card_list.sliver` and
`Expandable_list.sliver` produce native sliver renderers rather than box
adapters.

`BonsaiFlutterRoot` still owns one `MaterialApp`. M3E components derive their
theme from the active Material theme, so application and subtree theme changes
remain OCaml-controlled. No dynamic-color owner, M3E application root, runtime
renderer flag, fallback renderer, compatibility constructor, or protocol
migration path was added.

The gallery and FFI gallery fixture render the complete catalog. A separate
temporary OCaml catalog at
`examples/material_3_expressive_catalog_temp.ml` demonstrates every replaced
and newly added widget family in one source file.

## Validation

The following final checks passed:

- `dune build @all @fmt`, `make test`, `make protocol-check`, and
  `make protocol-fixtures-check`;
- Flutter analysis and all 496 `bonsai_flutter` package tests;
- Flutter analysis and all 33 `bonsai_flutter_native` tests;
- Flutter analysis for the integration project and every example project;
- all 14 real-OCaml FFI integration tests, including gallery layout at
  390 x 844 and 1440 x 900; and
- standalone native compilation of
  `examples/material_3_expressive_catalog_temp.ml` against the installed
  workspace package.

Headless gallery screenshots were generated and inspected at 390 x 844 and
1440 x 900, at both the top and bottom of the catalog. The first narrow pass
found overflows in the FAB, chip, and progress groups. The gallery layouts were
corrected, the screenshots were regenerated without overflow, clipping,
safe-area, or unexpected-padding defects, and the two viewport checks were
retained as `gallery_layout_ffi_test.dart`. The transient PNG files are not
repository artifacts.

A final live macOS Gallery run used the installed `bonsai-flutter` CLI with the
current workspace framework and renderer sources. The first passes exposed
four package composition assumptions that headless coverage had not exercised:
`M3ESelection` required bounded height, `M3EDismissibleList` required a bounded
internal viewport, `M3ESideSheet` forced infinite height, and the modal
`M3ENavigationRail` root overlay lost `RendererResourceScope`. Each case was
reproduced with a failing widget test before its adapter fix. The final app ran
without Flutter exceptions and exported a complete 26 MiB Skia scene from its
live VM service.

The tracked patch at validation time contained 141 changed files, 9,817
insertions, and 4,478 deletions, before counting the decision document and
three new source/test files. Pub-cache source sizes for the pinned dependency
graph were 6,408 KiB for `material_3_expressive`, 25,408 KiB for `material_ui`,
4,400 KiB for `motor`, 1,168 KiB for `material_new_shapes`, and 1,692 KiB for
`dynamic_color`, or 39,076 KiB in total.

Runtime microbenchmarks were rerun against the recorded baseline. Dart median
times in microseconds were 170.70 for frame decode, 178.90 for a full
`NodeStore` update, 105.93 for one dirty node, 123.20 for 100 dirty nodes,
111.10 for keyed reorder, 3.18 for text-controller reconciliation, 6.60 for
resource lifecycle, 424.45 for event batching, and 2.95 for isolate transfer.
The corresponding baselines were 175.00, 179.90, 106.94, 111.68, 105.06,
2.97, 5.91, 385.60, and 2.01. OCaml median times in microseconds were 61.341
for an unchanged tree, 409.150 for 1,000 siblings, 4,498.410 for 10,000
siblings, 88.584 for full protocol encode, 88.034 for one runtime encode pass,
92.516 for full protocol decode, 0.241 for incremental encode, and 0.263 for
incremental decode. Their baselines were 85.435, 401.020, 4,410.410, 89.114,
90.650, 95.660, 0.225, and 0.251. The results show no systemic regression;
the small-test deltas are retained here because microbenchmark variance is
material at these durations.

## Risks

- Version 1.1.1 is recent, the publisher is unverified on pub.dev, and the
  package has had frequent releases. Pinning reduces surprise but makes
  upstream security, Flutter compatibility, and bug-fix review a repository
  responsibility.
- Migrating from `flutter/material.dart` to `material_ui` is repository-wide and
  can expose type or export differences in navigation and native widgets that
  are unrelated to the visible component replacements.
- M3E defaults can change component size, intrinsic layout, hit targets,
  safe-area handling, overlay placement, and animation timing. Existing pages
  may overflow even when logical APIs do not change.
- `M3EThemeData.fromMaterial` supplies expressive component defaults and an
  emphasized type scale that are not represented in the current OCaml theme
  protocol. This is an accepted fixed renderer mapping, so changing the pinned
  package version requires explicit visual and behavioral review.
- Spring animations and morph painters add tickers and per-frame work. Large
  lists containing interactive controls may regress frame time, memory use, or
  test settling behavior.
- The new dependency graph includes `motor`, `material_new_shapes`,
  `dynamic_color`, and `material_ui`, increasing binary size and supply-chain
  surface even when dynamic color and complex shapes are not used directly.
- Package widgets may not exactly match Flutter Material semantics, focus,
  restoration, or accessibility behavior. Visual similarity is not sufficient
  verification.
- Narrowing the OCaml API to achieve complete package coverage is an
  intentional breaking change with no compatibility layer, per repository
  policy.

## Questions

No open questions remain. The exploration resolves the previous questions as
follows:

1. Narrow existing APIs to the matching M3E contract and delete unsupported
   parameters without compatibility or fallback renderers.
2. Use `M3EThemeData.fromMaterial`; treat package-provided expressive defaults
   as a fixed renderer mapping and defer renderer-neutral expressive tokens.
3. Keep ordinary dialog, bottom-sheet, and side-sheet ownership in
   `Navigation`; expose modal date/time pickers as typed host effects and never
   expose raw package `show*` helpers.
4. Use an epoch-safe request-token handshake for dismiss confirmation, refresh
   completion, and other package callbacks returning futures.
5. Pin `material_3_expressive` exactly to 1.1.1.
