# Expandable Composer Fab Presentation

## Problem

`Native_widget.Expandable_message_composer` always renders
`FloatingActionButton.extended` while collapsed. OCaml can update the label,
icon, tooltip, enablement, editor configuration, and actions, but it cannot ask
the same composer to use an icon-only FAB. An application that needs a compact
capture affordance must therefore replace the composer with another widget or
another composer.

Replacement crosses the component's state boundary. The Flutter
`_ExpandableMessageComposerState` owns the draft `TextEditingController`, editor
`FocusNode`, active `ModalBottomSheetRoute`, route generation, and live sheet
configuration. Replacing the native node, changing its logical key, or changing
the outer stateful widget type disposes that state, closes the route, and loses
the draft. Presentation is ordinary mutable configuration and must not become
part of widget identity.

The requested OCaml contract has two explicit presentations, `Extended` and
`Compact`. `fab_presentation` is required for both constructors. There is no
always-extended default, deprecated overload, optional value, or decoding
fallback.

## Evidence

- The OCaml kind-`7` payload has a 24-byte header. Bytes `20..23` are currently
  required to be zero, so one byte is available without growing the payload.
- Native widget schema version `1` promises that all four bytes are reserved.
  Reinterpreting one byte while retaining version `1` would make an old payload
  indistinguishable from a new `Extended` payload and would let old Dart code
  render `Extended` while silently rejecting only `Compact`.
- OCaml reconciliation retains a node when its kind, logical key, and parent
  context remain compatible. A property change then becomes `UpdateProps` for
  the existing node ID.
- Flutter wraps that node in `NodeHost(key: ValueKey<int>(nodeId))`. Rebuilding
  the registry factory for the same node produces another
  `ExpandableMessageComposer` at the same element position, so Flutter calls
  `didUpdateWidget` on the existing `_ExpandableMessageComposerState` instead
  of calling `dispose` and `createState`.
- The active sheet reads live widget configuration through
  `_sheetConfiguration`, while its controller, focus node, and route stay on
  the outer State. The collapsed FAB presentation does not need to enter the
  sheet configuration or route lifecycle.
- Both `FloatingActionButton.extended` and the regular icon-only
  `FloatingActionButton` construct the same public Flutter widget class. The
  presentation switch therefore changes only the descendant FAB configuration;
  it does not require a second outer composer type or State owner.

## Decision

Add the required OCaml type and parameters exactly at the existing constructor
boundary:

```ocaml
module Expandable_message_composer : sig
  type fab_presentation =
    | Extended
    | Compact

  val create
    :  ?key:Key.t
    -> ?enabled:bool
    -> fab_presentation:fab_presentation
    -> fab_label:string
    -> fab_tooltip:string
    -> fab_icon:Widget.t
    -> ?animation_duration_ms:int
    -> ?animation_curve:Animation.Curve.t
    -> ?max_lines:int
    -> ?hint_text:string
    -> buttons:button list
    -> on_event:(event -> unit)
    -> unit
    -> Widget.t

  val create_with_handler
    :  ?key:Key.t
    -> ?enabled:bool
    -> fab_presentation:fab_presentation
    -> fab_label:string
    -> fab_tooltip:string
    -> fab_icon:Widget.t
    -> ?animation_duration_ms:int
    -> ?animation_curve:Animation.Curve.t
    -> ?max_lines:int
    -> ?hint_text:string
    -> buttons:button list
    -> on_event:Event.Handler.t
    -> unit
    -> Widget.t
end
```

Add `fab_presentation` to the internal OCaml props, encoder, decoder, and
`For_testing.props`. Both constructor implementations pass the required value
through `make_props`; neither constructor supplies a default. Existing call
sites must select a presentation explicitly.

Replace native widget kind `7` schema version `1` with version `2`; do not
register or emit version `1`. The core native-widget envelope, kind ID,
capability bits, child ordering, and event IDs stay unchanged. Version `2`
keeps the 24-byte header and assigns it as follows:

| Offset | Width | Meaning |
| ---: | ---: | --- |
| 0 | 1 | flags: bit 0 is `enabled`; all other bits are reserved zero |
| 1 | 1 | curve: `0` linear, `1` ease-in, `2` ease-out, `3` ease-in-out |
| 2 | 2 | animation duration in milliseconds |
| 4 | 2 | positive `max_lines` |
| 6 | 2 | composer button count |
| 8 | 4 | FAB label byte length |
| 12 | 4 | FAB tooltip byte length |
| 16 | 4 | hint byte length |
| 20 | 1 | FAB presentation: `0` extended, `1` compact |
| 21 | 3 | reserved zero |

The strings and per-button records following the header retain their current
layout. Both decoders reject any presentation value other than `0` or `1`, any
nonzero reserved byte, truncation, or trailing data. Version dispatch rejects
version `1` before its payload reaches the version-`2` decoder. This is a hard
schema replacement, not a migration or compatibility layer.

Add the corresponding public Dart enum and make it required in both
`ExpandableMessageComposerProps` and `ExpandableMessageComposer`. The registry
passes the decoded value into the widget. Include it in props equality and
hashing so a presentation-only frame is observable as a real property update.

Define the visual mapping narrowly:

- `Extended` renders `FloatingActionButton.extended`, with `fab_icon` and the
  existing single-line, scale-down `fab_label`.
- `Compact` renders the standard icon-only `FloatingActionButton`, with
  `fab_icon` as its child. It does not mean `FloatingActionButton.small`.
- Both variants retain `heroTag: null`, the same enabled/disabled callback,
  tooltip, explicit button semantics, scaffold-owned placement, modal-opening
  behavior, and Material theming.

`fab_label` remains required, non-empty, valid UTF-8, and encoded even for
`Compact`. This keeps the public API symmetric and allows a later same-node
switch to `Extended` without inventing conditional validation or a second
metadata source. `fab_tooltip` remains the accessible label for both variants.

Keep one `ExpandableMessageComposer` `StatefulWidget` and one
`_ExpandableMessageComposerState`. `fab_presentation` must not be placed in a
Flutter key, used to choose a different outer widget type, or used to recreate
the route/controller/focus resources. `_buildFab` selects only the collapsed
FAB descendant. If presentation changes while the modal is active, the current
route, draft, and focused editor remain mounted; after dismissal, the newly
selected collapsed variant appears.

The implementation scope is limited to:

- `ocaml/ui/native_widget.mli` and `ocaml/ui/native_widget.ml` for the required
  API and version-`2` codec;
- `ocaml/test/native_widget_tests.ml` for the constructor, payload, strict
  decoder, and required-argument contract;
- `flutter/packages/bonsai_flutter/lib/src/native_widget/expandable_message_composer.dart`
  for the Dart enum, version-`2` codec/registration, and visual selection;
- `flutter/packages/bonsai_flutter/test/expandable_message_composer_test.dart`
  for rendering, registry updates, and State continuity;
- `docs/custom-widgets.md` and the stable API documentation for the explicit
  presentation and version-`2` wire contract.

No core frame encoding, generated protocol IDs, native widget kind, Dune file,
or OCaml file below `spec/` needs to change. Existing source call sites and
tests are updated directly; no deprecated constructor is retained.

## Alternatives considered

### Keep version 1 and consume one reserved byte

This minimizes the numerical diff but violates the existing version-`1`
reserved-byte contract. An old version-`1` payload has zero at offset `20` and
would silently become `Extended`, which is precisely an always-extended wire
fallback. Old Dart would also treat new `Compact` payloads as malformed rather
than rejecting the schema at version dispatch. Version `2` makes the break
explicit and symmetric.

### Add `?extended:bool` or default presentation to `Extended`

A boolean does not match the requested domain API and ages poorly if a third
presentation is ever introduced. Making either form optional preserves the
current behavior for omitted calls, so it fails the requirement that every
OCaml caller make an explicit choice.

### Switch between two OCaml widgets

An application could conditionally render a standalone FAB or two separately
keyed composers. That changes node or widget identity and therefore cannot
guarantee continuity of the native controller, focus node, modal route, or
draft. It also moves a native-local presentation detail into application state.

### Use separate outer Flutter widget classes

Returning `ExtendedExpandableMessageComposer` versus
`CompactExpandableMessageComposer` would cause Flutter element replacement
when the runtime type changes. Hoisting shared resources above both variants
would add another state owner solely to recover continuity already provided by
the existing widget. Selecting the FAB inside `_buildFab` is the smaller and
safer boundary.

### Make `fab_label` optional for Compact

Conditional presence complicates the OCaml API and wire format, makes
`Compact -> Extended` depend on a simultaneous second property update, and
weakens current validation. The requested API keeps `fab_label` required in
both presentations.

### Animate the label collapse inside the composer

The requested contract selects two settled FAB appearances and does not define
transition duration, geometry, or interruption behavior for the collapsed
button itself. Adding an `AnimatedSwitcher` or a custom morph would expand
state, semantics, layout, and golden-test surface without helping controller,
focus, or route continuity. A future animation requirement should define its
own behavior explicitly.

## Acceptance criteria

- OCaml exposes `fab_presentation = Extended | Compact`, and both `create` and
  `create_with_handler` require `~fab_presentation`; code omitting it does not
  compile. There is no old overload or default.
- Kind `7` emits and accepts only schema version `2`. Version `1`, unknown
  presentation bytes, nonzero bytes `21..23`, truncation, and trailing bytes
  are rejected without fallback.
- OCaml and Dart round trips preserve both presentation values, and props
  equality distinguishes presentation-only changes.
- `Extended` contains one real extended FAB with the requested icon and visible
  label. `Compact` contains one standard icon-only FAB with no label subtree.
- Both variants retain the same tooltip/accessibility label, enabled and
  disabled behavior, `heroTag: null`, scaffold FAB placement, and modal-opening
  interaction.
- With one stable logical key, changing only `fab_presentation` produces a
  property update for the same node ID and retains the same Flutter
  `_ExpandableMessageComposerState` instance.
- A collapsed same-key update changes between extended and compact without
  recreating the composer. A same-key update while the modal route is open
  preserves the same route, exact Unicode/whitespace draft, controller, focus,
  and enabled actions; dismissing the route reveals the new collapsed
  presentation.
- Repeated `Extended -> Compact -> Extended` updates do not emit composer
  events, push an additional route, duplicate the FAB, or lose semantics.
- Changing the logical key remains the explicit reset boundary: it removes an
  active owned route and creates an empty draft with fresh focus/controller
  state.
- Existing composer buttons, events, animation timing, reduced motion,
  keyboard/safe-area behavior, RTL, large text, narrow layouts, and all six
  scaffold FAB locations retain their current behavior.
- User-facing documentation describes `Compact` as the standard icon-only FAB,
  keeps `fab_label` required for both variants, and documents schema version
  `2` with no version-`1` compatibility path.
- OCaml formatting and relevant tests, Dart formatting, Flutter analysis, the
  focused composer tests, the complete Flutter package tests, and
  `spec-dev-tool check --all` pass.

## Consequences

- OCaml callers must choose `Extended` or `Compact` explicitly for both
  constructors. There is no default, overload, or deprecated compatibility
  path.
- Kind `7` now emits and registers only schema version `2`; producers and hosts
  must be updated together. Version `1` is rejected at dispatch.
- Compact presentation keeps the required label in the payload but paints only
  the standard icon-only FAB. Extended presentation retains the existing icon
  and scale-down, single-line label.
- Presentation-only updates remain ordinary props updates for the same native
  node and Flutter State. Active route, controller, focus node, exact draft,
  actions, and event behavior survive the update.
- The outer widget, key boundary, native kind, capabilities, child ordering,
  event IDs, core protocol, and generated IDs remain unchanged.
- The public OCaml and Dart APIs, strict codecs, registry, focused continuity
  tests, full package tests, and maintained custom-widget documentation now
  describe and enforce the same two-presentation contract.

## Risks

- Schema version `2` is intentionally incompatible with an older Flutter
  package or older OCaml producer. Deployments must update both sides together;
  this proposal deliberately adds no dual-version registration or decoding.
- Compact retains the label in payloads even though it does not paint it. This
  costs a small number of bytes but avoids presentation-dependent schemas and
  keeps same-frame switching deterministic.
- Presentation-only updates currently rebuild the active sheet through the
  general live-configuration notifier. The route, controller, focus node, and
  sheet State must be verified by identity and behavior so an incidental
  rebuild is not mistaken for state loss.
- Flutter's standard icon-only FAB and extended FAB have different intrinsic
  widths. Scaffold owns the resulting relocation at start, center, end,
  floating, and docked locations; the composer must not add compensating
  margins or alignment.
- There is no composer-owned morph animation between compact and extended.
  Adding one later requires a separate interaction contract, especially for
  rapid property changes and accessibility announcements.

## Questions

None. The requested OCaml signature fixes requiredness and naming, and the
existing Material contract makes `Compact` the standard icon-only FAB rather
than the separately named small FAB.
