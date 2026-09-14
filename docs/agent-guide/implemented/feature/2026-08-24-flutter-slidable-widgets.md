# Flutter Slidable Widgets

## Problem

`Bonsai_flutter_ui.Native_widget.Swipe_action` currently implements one
renderer-owned horizontal swipe action on each logical side of an item. Each
action has one icon, one label, one background, and either dismiss or rebound
behavior. The host owns custom drag, threshold, haptic, clipping, animation,
and semantics behavior.

This surface is too narrow for list-item interactions that need multiple
actions, independently configured action panes, selectable reveal motions,
auto-close groups, vertical sliding, or programmatic control. Expanding the
custom implementation would duplicate a substantial part of the established
[`flutter_slidable`](https://pub.dev/packages/flutter_slidable) package and
would leave Bonsai Flutter responsible for maintaining that duplicate.

`flutter_slidable` 4.0.3 is compatible with the repository's Flutter 3.44 and
Dart 3.12 baselines. Its public model consists of:

- `Slidable`, with optional start and end panes, horizontal or vertical drag,
  enabled state, text-direction handling, scroll-close behavior, group tags,
  and an optional controller;
- `ActionPane`, with an extent ratio, open and close thresholds, optional
  dismissal, and a list of actions;
- `BehindMotion`, `DrawerMotion`, `ScrollMotion`, and `StretchMotion`;
- `SlidableAction` and `CustomSlidableAction`, including flex, colors,
  auto-close, border radius, padding, alignment, and activation;
- `DismissiblePane`, including thresholds, animation durations, optional
  asynchronous confirmation, and dismissal completion;
- `SlidableAutoCloseBehavior`, which coordinates open items sharing a group;
  and
- `SlidableController` and notifications for imperative control and progress
  observation.

The package API cannot be exposed directly to OCaml. Flutter `Widget`,
`BuildContext`, callbacks, futures, controllers, and notification objects do
not cross the frame protocol. Bonsai Flutter needs a renderer-independent
OCaml surface, a deterministic native-widget payload, typed events, and clear
ownership of local animation state.

There is also an interaction-quality conflict. The repository's shared
touch-intent policy makes renderer-owned horizontal drag recognizers reject a
decisively vertical touch at six logical pixels with 1.5 axis dominance. This
keeps swipe-wrapped Mail rows within one delivered sample of otherwise
equivalent pure rows on a physical iPhone. `flutter_slidable` 4.0.3 constructs
an internal stock `GestureDetector`; it does not expose a recognizer factory.
Using it unchanged would move this drag outside the shared arbitration layer
and may restore the previously measured vertical-scroll startup delay.

The existing `Swipe_action` and a new package-backed surface should not remain
as parallel long-term APIs. Repository policy removes obsolete paths instead
of preserving compatibility wrappers, and two swipe systems would have
different geometry, gesture, accessibility, dismissal, and state semantics.

## Decision

Replace `Native_widget.Swipe_action` with a package-backed
`Native_widget.Slidable` surface and add a package-backed
`Native_widget.Slidable_auto_close_behavior` ancestor.

The resolved design choices are:

1. remove `Native_widget.Swipe_action` and migrate every existing call site;
2. defer imperative controller commands, ratio notifications, and asynchronous
   `confirmDismiss` to later decisions;
3. use the stock `flutter_slidable` gesture implementation even when it does
   not meet the renderer's existing physical-iPhone scroll-start parity target,
   without maintaining a fork or patch; and
4. expose both a fully custom `action ~child` constructor and an
   `icon_label_action ~icon ~label` convenience constructor in the first
   release.

### Dependency and ownership

Add `flutter_slidable` 4.0.3 as a direct runtime dependency of
`flutter/packages/bonsai_flutter`. The renderer package, rather than each
application host, owns the dependency. Generated and example host pubspecs
continue to depend only on `bonsai_flutter` and receive `flutter_slidable`
transitively.

The repository lockfiles must resolve the same package version and checksum.
The renderer imports only the package's public
`package:flutter_slidable/flutter_slidable.dart` library; it must not depend on
`package:flutter_slidable/src/...` implementation files.

Flutter owns controllers, animations, action-pane layout, open state,
scroll-close subscriptions, dismissal animation, and auto-close coordination.
OCaml owns the declared configuration, stable item identity, action and
dismissal effects, and removal of a dismissed item from application state.
Drag deltas and animation progress do not cross FFI.

### OCaml surface

The API uses abstract configuration values rather than pretending that
`ActionPane` and `CustomSlidableAction` are independent logical tree nodes. A
`Slidable` native host receives all visual children and constructs the package
widget subtree locally.

```ocaml
module Slidable : sig
  type side =
    | Start
    | End

  type motion =
    | Behind
    | Drawer
    | Scroll
    | Stretch

  type dismiss_motion = Inversed_drawer

  type action
  type dismissible
  type action_pane

  type event =
    | Action_pressed of int
    | Dismissed of side

  val action
    :  id:int
    -> ?enabled:bool
    -> ?flex:int
    -> ?foreground:Style.Color.t
    -> background:Style.Color.t
    -> ?auto_close:bool
    -> ?border_radius:float
    -> ?padding:Layout.Edge_insets.t
    -> ?alignment:Layout.Alignment.t
    -> child:Widget.t
    -> unit
    -> action

  val icon_label_action
    :  id:int
    -> ?enabled:bool
    -> ?flex:int
    -> ?foreground:Style.Color.t
    -> background:Style.Color.t
    -> ?auto_close:bool
    -> ?border_radius:float
    -> ?padding:Layout.Edge_insets.t
    -> ?alignment:Layout.Alignment.t
    -> ?spacing:float
    -> icon:Widget.t
    -> label:string
    -> unit
    -> action

  val dismissible
    :  ?dismiss_threshold:float
    -> ?dismissal_duration_ms:int
    -> ?resize_duration_ms:int
    -> ?close_on_cancel:bool
    -> ?motion:dismiss_motion
    -> unit
    -> dismissible

  val action_pane
    :  ?extent_ratio:float
    -> motion:motion
    -> ?dismissible:dismissible
    -> ?drag_dismissible:bool
    -> ?open_threshold:float
    -> ?close_threshold:float
    -> actions:action list
    -> unit
    -> action_pane

  val create
    :  key:Key.t
    -> ?enabled:bool
    -> ?close_on_scroll:bool
    -> ?direction:Layout.Axis.t
    -> ?use_text_direction:bool
    -> ?group_tag:string
    -> ?start_action_pane:action_pane
    -> ?end_action_pane:action_pane
    -> content:Widget.t
    -> on_event:(event -> unit)
    -> unit
    -> Widget.t

  val create_with_handler
    :  key:Key.t
    -> ?enabled:bool
    -> ?close_on_scroll:bool
    -> ?direction:Layout.Axis.t
    -> ?use_text_direction:bool
    -> ?group_tag:string
    -> ?start_action_pane:action_pane
    -> ?end_action_pane:action_pane
    -> content:Widget.t
    -> on_event:Event.Handler.t
    -> unit
    -> Widget.t

  val event_of_payload : Event.Payload.t -> event option
end

module Slidable_auto_close_behavior : sig
  val create
    :  ?key:Key.t
    -> ?close_when_opened:bool
    -> ?close_when_tapped:bool
    -> child:Widget.t
    -> unit
    -> Widget.t
end
```

Action IDs are positive unsigned 32-bit values and unique across both panes of
one `Slidable`. Disabled actions render through `CustomSlidableAction` with a
null callback. Arbitrary OCaml `Widget.t` action content maps to
`CustomSlidableAction.child`. `icon_label_action` is an OCaml convenience
constructor that builds the package's standard icon-over-label arrangement
from the supplied logical icon, label, and spacing before delegating to
`action`; it does not add a second wire action type or serialize
Flutter-specific `IconData`. Labels must be non-empty UTF-8 and spacing must be
finite and non-negative.

Every `Slidable` requires an application key. The package requires stable
identity for dismissible items, and open controllers must not migrate between
reconciled list rows. Requiring the key uniformly is simpler and safer than
making key presence depend on an opaque pane configuration.

At least one pane must be present. Every present pane contains at least one
action, has a finite extent ratio in `(0, 1]`, and has optional finite open and
close thresholds in `(0, 1)`. Flex values are positive. Radii, insets, and
durations are finite or non-negative as appropriate. Both OCaml construction
and Dart decoding enforce the same invariants.

All actions map through `CustomSlidableAction`. The two OCaml constructors
share the same payload, validation, event, and renderer behavior. Foreground
color remains optional so the package can derive accessible contrast from the
background.

### Payload and event contract

Reuse built-in native-widget kind `2` for `Slidable`, remove the old
`Swipe_action` registration, and advance the kind schema to version `3`. Old
version-2 frames fail explicitly; no decoder fallback or compatibility layer
remains. Allocate a new built-in kind ID for
`Slidable_auto_close_behavior`.

The `Slidable` children have one canonical order:

1. content;
2. start-pane action children in metadata order; and
3. end-pane action children in metadata order.

The payload contains global flags, axis and text-direction policy, optional
group tag, pane-presence flags, pane motion and thresholds, dismissal settings,
action counts, and per-action IDs and visual properties. Variable strings and
padding data use exact byte lengths. The decoder rejects unknown flags and
enums, duplicate or invalid action IDs, invalid numbers, incorrect child
counts, malformed UTF-8, trailing bytes, and inconsistent pane metadata.

One native event reports action activation with the action ID. A second event
reports completed dismissal with its logical start or end side. Action events
are emitted immediately from the package callback. Dismiss events are emitted
from `DismissiblePane.onDismissed`; the OCaml handler must remove the keyed item
from its collection in the resulting frame.

`Slidable_auto_close_behavior` owns only local coordination policy and one
logical child. Group tags remain properties of descendant `Slidable` hosts.
The behavior emits no event.

### Package capability coverage

The first release maps stable declarative package capabilities and defers APIs
whose semantics require a separate command or request-response design.

| Package capability | OCaml coverage |
| --- | --- |
| Start and end panes | Included |
| Multiple actions per pane | Included |
| Behind, drawer, scroll, and stretch motions | Included |
| Custom action child, flex, colors, auto-close, radius, padding, and alignment | Included |
| Horizontal and vertical axes | Included |
| Enabled, text-direction, and close-on-scroll policy | Included |
| Dismiss threshold, durations, motion, drag enablement, and completion | Included |
| Group tags and auto-close ancestor behavior | Included |
| `SlidableAction` convenience icon/label constructor | Included as the renderer-independent OCaml `icon_label_action` helper |
| Imperative controller open, close, and dismiss commands | Deferred |
| Ratio and open-state notifications | Deferred |
| Asynchronous `confirmDismiss` | Deferred |
| Arbitrary Dart motion widgets and ratio-aware builders | Not serializable and not proposed |

Programmatic controller operations should not be encoded as ordinary desired
properties because unrelated OCaml rebuilds could replay an imperative open,
close, or dismiss. If required, they need a nonce-bearing host-effect or
resource command design. Ratio notifications would be high-frequency native
events and need an explicit coalescing contract. `confirmDismiss` is a Flutter
`Future<bool>` callback; supporting an OCaml decision requires a correlated
request-response lifecycle, timeout and disposal behavior, and a policy for
frames arriving while confirmation is pending.

### Gesture integration

The stock package gesture detector uses Flutter's standard horizontal or
vertical drag recognizer and offers no public injection point. Use that stock
gesture implementation unchanged. Do not carry a fork or patch, import
package-private controller or gesture classes, or reimplement dismissal on top
of the public controller to bypass the package detector.

This decision accepts that package-backed rows may no longer meet the
physical-iPhone scroll-start parity target previously applied to the custom
`Swipe_action`. The renderer-wide touch-intent policy remains authoritative for
recognizers owned by Bonsai Flutter, but it does not govern the recognizer
owned internally by this third-party package. Removing `Swipe_action`
therefore also removes its package-specific participation in that earlier
target.

Retain the pure-row versus package-wrapped-row cadence tests and physical
device measurements as characterization, not as a pass/fail gate. Results must
be recorded so a future package upgrade or a separate gesture decision can
quantify the accepted difference.

### Development and verification

Implementation follows test-driven development:

- OCaml tests first define action, pane, dismissal, payload, child-order, and
  event contracts and fail after the obsolete `Swipe_action` expectations are
  removed;
- Dart decoder and widget tests first fail for the new version-3 shape,
  multiple actions, all motions, dismissal, disabled actions, close-on-scroll,
  auto-close groups, LTR/RTL mapping, vertical direction, semantics,
  reconciliation, and disposal;
- the Mail example and integration fixture migrate from `Swipe_action` without
  a compatibility wrapper and demonstrate at least two actions in one pane;
- deterministic gesture tests characterize pure and package-wrapped rows at
  slow, normal, and fast delivery schedules without requiring parity; and
- profile-mode physical-iPhone validation records startup samples, distance,
  and latency for isolated pure and package-wrapped representative rows before
  the decision is considered implemented, while any stock-package regression
  is accepted. Mail example physical and Profile tests are outside this
  decision's acceptance target.

The representative-row characterization ran in Profile mode on 2026-08-24 on
an iPhone 13 with iOS 26.6.1. Each cell below contains three trials. The stock
package consistently required more delivered samples and distance before the
vertical scroll position changed, as accepted by this decision.

| Delivery schedule | Pure samples / distance | Wrapped samples / distance | Pure latency | Wrapped latency |
| --- | --- | --- | --- | --- |
| Slow, 1 px per 16 ms | `10 / 10 px` | `23 / 23 px` | `331.851–333.637 ms` | `765.351–765.518 ms` |
| Normal, 4 px per 16 ms | `3 / 12 px` | `6 / 24 px` | `98.879–99.132 ms` | `198.336–199.439 ms` |
| Fast, 8 px per 16 ms | `2 / 16 px` | `4 / 32 px` | `65.492–65.910 ms` | `131.720–132.267 ms` |

The same device run passed eventual vertical scrolling, horizontal opening,
near-diagonal opening, RTL logical-start mapping, and stylus, inverted-stylus,
and unknown-pointer characterization. No Mail example device measurement is
required by the revised target.

Expected implementation files include `ocaml/ui/native_widget.ml` and `.mli`,
their OCaml tests, the renderer native-widget registration and tests,
`flutter/packages/bonsai_flutter/pubspec.yaml` and lockfiles, the Mail example
and integration fixture, and `docs/custom-widgets.md`. No protocol `.mli` under
`spec/` or Dune file is expected to change because native-widget payloads are
opaque to the core protocol.

The framework implementation was pushed as `bea79f5`, and the separately
committed iOS SDK repository update `c7069d9` published framework package
`0.1.0~dev.19` from that exact source revision. The runtime SDK, ABI version,
and build-recipe revision remained unchanged.

## Alternatives considered

### Expand the custom `Swipe_action`

The renderer could add action arrays, panes, motions, grouping, and controller
behavior to its existing host. This avoids a dependency and preserves full
gesture control, but it duplicates the package's layout, animation,
accessibility, dismissal, and lifecycle logic. The maintenance burden is the
reason to adopt `flutter_slidable`.

### Keep `Swipe_action` beside `Slidable`

This gives applications a simple bespoke option and a richer package-backed
option, but establishes two permanent swipe systems with different behavior.
It also conflicts with the repository instruction to remove obsolete paths
instead of maintaining compatibility surfaces.

### Mirror every Dart class and property one-for-one

This appears complete but exposes Flutter implementation details through a
renderer-independent OCaml API. Builders, widget-valued motions, contexts,
controllers, notifications, and futures do not have faithful serialized
equivalents. A capability-oriented OCaml model is smaller and has explicit
ownership.

### Add core protocol node kinds

Dedicated `Slidable`, `ActionPane`, and action nodes could provide stronger
tree structure, but the feature is implemented by one optional third-party
Flutter package and owns local mutable resources. Native-widget extensions
already provide versioning, opaque props, children, events, capability bits,
and reconciliation for this boundary. Expanding the core protocol would
increase every codec and renderer surface without a renderer-independent
requirement.

### Depend on package-private APIs to retain gesture policy

The renderer could import `flutter_slidable/src/controller.dart` and drive the
controller with `BonsaiGestureDetector`. This is rejected because the package
does not promise compatibility for private files or types. A minor package
release could break the host without a public API change.

### Maintain a fork or patch for touch-intent parity

A minimal fork could expose a drag-recognizer factory and route the package
through `BonsaiGestureDetector`, preserving the custom host's existing
physical-iPhone parity target. This is not selected because it would make
Bonsai Flutter responsible for rebasing, auditing, publishing, and validating
a third-party package variant. The stock package behavior and any resulting
scroll-start regression are accepted instead.

## Acceptance criteria

- `flutter_slidable` is owned transitively by the public renderer package and
  all checked lockfiles resolve the selected version deterministically.
- `Native_widget.Swipe_action`, its version-2 renderer, tests, docs, and call
  sites are removed rather than retained as aliases or fallbacks.
- OCaml can declare start and end panes with multiple stable action IDs, all
  four built-in motions, arbitrary widget content, pane thresholds,
  dismissal, horizontal or vertical direction, and auto-close grouping.
- OCaml constructors and Dart decoders reject the same malformed values,
  metadata, and child arrangements.
- Action activation and completed dismissal produce typed, exactly-once events
  while late callbacks after node disposal are suppressed.
- A dismissed keyed list item is removed by the next OCaml frame without a
  package assertion, duplicate callback, or transient reappearance.
- Package-owned open and animation state survives ordinary OCaml property
  patches for the same key and is disposed when the key disappears.
- LTR and RTL map logical start and end consistently; vertical mode maps start
  and end to the package's bottom and top behavior.
- Disabled actions, disabled hosts, close-on-scroll, close-on-action,
  auto-close group behavior, keyboard/semantics activation, and reduced-motion
  behavior have focused widget tests.
- Pure and package-wrapped representative-row startup samples, distance, and
  latency are recorded on the target iPhone; parity is not required and does
  not block implementation. Mail example tests are not part of this criterion.
- The renderer uses the stock public `flutter_slidable` package without a
  fork, patch, package-private import, or compatibility implementation.
- OCaml tests, renderer analyze/tests, native-object verification,
  documentation checks, and `spec-dev-tool check --all` pass. Mail example
  tests are outside this decision's acceptance target.

## Consequences

- `Native_widget.Slidable` version `3` replaces the removed version-2
  `Swipe_action` API and renderer without aliases, fallbacks, or parallel
  gesture implementations.
- OCaml applications can declare custom and icon-label actions, multiple
  start/end actions, all four stock motions, dismissal, vertical direction,
  group tags, and auto-close behavior through strict typed configuration and
  events.
- Flutter owns package controllers, gestures, animation, dismissal, and group
  coordination locally. Controller commands, ratio notifications, and
  asynchronous confirmation remain intentionally deferred.
- The stock package increases vertical-scroll startup samples, distance, and
  latency on the characterized iPhone. The measured difference is accepted
  and recorded rather than hidden behind a fork or compatibility host.
- The Mail call sites use the new API, but Mail example physical and Profile
  testing is outside the revised acceptance target.
- iPhoneOS framework package `0.1.0~dev.19` builds from framework revision
  `bea79f5`; the runtime SDK, ABI version, and build recipe remain unchanged.

## Risks

- The public package owns gesture recognition internally. The accepted stock
  behavior may make vertical scrolling start later than it did with the custom
  `Swipe_action`; the implementation records but does not gate on that
  regression.
- Adding a third-party runtime dependency makes package releases and Flutter
  minimum-version changes part of renderer maintenance. The dependency must
  be reviewed before upgrades instead of floating across major versions.
- A dismissal callback is locally asynchronous while collection removal is
  OCaml-owned. Slow application updates can leave a dismissed host in the tree
  longer than the package expects.
- Auto-close grouping depends on the actual Dart ancestor tree. Incorrect
  placement of the behavior wrapper or unstable group tags can leave multiple
  panes open.
- Arbitrary action children remain responsible for their own descriptive
  semantics. The `icon_label_action` helper standardizes the common visual
  arrangement but does not infer an application-specific semantic label beyond
  its supplied text.
- Reusing native kind `2` with schema version `3` deliberately rejects old
  frames. Framework and application objects must be rebuilt together.
- Deferring controller commands, progress notifications, and asynchronous
  confirmation means the first release does not expose every public Dart API,
  even though it covers the package's primary declarative widget behavior.

## Questions

- None. On 2026-08-24, the user selected replacement of `Swipe_action`, deferral
  of controller and asynchronous capabilities, stock package gesture behavior
  without a fork or patch, and both custom and icon-label action constructors.
