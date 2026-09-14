# Expandable Composer Floating Action Button

## Problem

`ExpandableMessageComposer` renders a real Material extended floating action
button when collapsed, but its base widget is shaped for
`Scaffold.bottomNavigationBar`. The widget always returns an aligned box that
is 72 logical pixels high plus the bottom safe-area inset. A scaffold reserves
that complete height below its body even though only the button is visible.

For capture-style use, the result is a blank bottom band containing a
right-aligned button. It does not behave like a floating action button: page
content stops above the band instead of extending behind and below the button.
The reserved band remains until the composer widget leaves the scaffold,
regardless of whether the modal composer is open.

This layout also assigns the wrong ownership. `Scaffold` already owns floating
action button positioning, safe-area avoidance, bottom-bar coexistence, and
docked versus floating locations. Recreating part of that geometry inside the
native widget makes the component dependent on a specific parent slot and was
the source of the now-obsolete bottom-navigation keyboard workaround.

## Evidence

- `_ExpandableMessageComposerState.build` wraps the collapsed FAB in bottom
  safe-area padding, a fixed 72-pixel `SizedBox`, 8-pixel padding, and a
  bottom-end `Align`.
- The focused Flutter tests mount the composer as
  `Scaffold.bottomNavigationBar`, so they preserve the blank band instead of
  detecting it.
- The renderer maps `Material.scaffold` children independently to
  `Scaffold.floatingActionButton` and `Scaffold.bottomNavigationBar`.
- The OCaml `Material.scaffold` API already exposes
  `floating_action_button` and `floating_action_button_location`; its default
  location is `End_float`. No protocol or public composer-property change is
  required.
- The expanded editor is already a `ModalBottomSheetRoute`. Its keyboard and
  bottom safe-area padding is route-local and does not require the collapsed
  widget to occupy bottom-navigation space.

## Proposal

Make `Expandable_message_composer` a floating-action-button-slot component.
Consumers place it in `Material.scaffold ~floating_action_button`, using the
existing `floating_action_button_location` when a location other than
`End_float` is wanted. Do not place it in `bottom_navigation_bar`.

Product examples use the existing `End_float` default. The component does not
hard-code that location: callers may select any existing scaffold-supported
floating or docked location through `floating_action_button_location`.

Simplify the Flutter widget's collapsed base presentation to the extended FAB
itself. Remove the bottom safe-area `Padding`, fixed-height `SizedBox`, inner
padding, and `Align`. Let `Scaffold.floatingActionButton` own margins,
safe-area placement, directionality, and bottom-navigation-bar avoidance. While
the owned modal route is active, keep returning an empty widget so the
background FAB cannot receive input or contribute semantics.

Keep the existing click behavior: pressing the collapsed extended FAB pushes
the same Material 3 modal bottom sheet. Keep the controller, focus node, draft,
route lifecycle, renderer resources, button events, keyboard avoidance, and
dismissal behavior in the native Flutter `State`.

This is a placement and collapsed-layout correction, not a new presentation
mode. Preserve native widget kind `7`, schema version `1`, and the existing
OCaml and Dart constructor properties. Update examples, tests, and user-facing
documentation to use the floating action button slot. Remove tests and guidance
that treat `bottomNavigationBar` as a supported composer placement rather than
maintaining both layouts.

`Expandable_message_composer` occupies the scaffold's single floating action
button slot. If a page already has another FAB, product code must explicitly
choose which action owns that slot. This bugfix does not combine, replace, or
arbitrate multiple actions automatically. A product requirement for concurrent
primary actions requires a separate feature or architecture decision for a
multi-action component.

## Decision

`Expandable_message_composer` is exclusively a
`Material.scaffold ~floating_action_button` child. Its collapsed Flutter root
is exactly the extended FAB, while `Scaffold` owns placement, safe-area margins,
directionality, and real bottom-navigation-bar coexistence. `End_float` remains
the default location, callers retain every existing standard location, and the
component continues to open its framework-owned modal bottom sheet.

The previous bottom-navigation-specific padding, fixed height, inset, and
alignment are removed without a compatibility mode. Native widget kind `7`,
schema version `1`, public constructor properties, events, modal route, draft,
focus, and dismissal ownership remain unchanged.

## Alternatives considered

### Keep `bottomNavigationBar` and make its box transparent

The current band is already visually empty; transparency does not restore the
body space reserved by scaffold layout. A zero-height or overflowed child would
also put painting and hit testing outside the parent bounds and retain the
wrong layout ownership.

### Position the composer with an application `Stack`

An application-level `Stack` can visually overlay the button, but every
consumer would need to reproduce scaffold margins, safe-area avoidance,
directionality, and bottom-bar coexistence. Flutter's dedicated floating action
button slot already implements this contract.

### Have the native widget insert its own `OverlayEntry`

An overlay would allow the widget to escape a bottom-navigation slot, but would
duplicate navigator/scaffold placement logic, complicate lifecycle and
semantics, and make floating-action-button location configuration indirect.
The native widget only needs to own the modal route; its collapsed placement
belongs to `Scaffold`.

### Add a placement mode for backward compatibility

A `bottomNavigationBar` versus `floatingActionButton` mode would preserve the
obsolete reserved-band behavior and add protocol and testing surface without a
product requirement. The old placement path should be removed rather than
retained as a fallback.

## Acceptance criteria

- With a collapsed expandable composer in `Scaffold.floatingActionButton`, the
  scaffold body extends to the bottom of the available content area; no
  composer-owned bottom band or fixed 72-pixel layout reservation exists.
- The collapsed presentation contains exactly one visible Material extended
  FAB at the scaffold-selected floating action button location.
- The default OCaml scaffold placement is `End_float`; explicit supported
  floating and docked locations continue to be controlled by
  `floating_action_button_location`.
- A real `bottomNavigationBar`, when present, remains visible and the scaffold
  positions the composer relative to it without composer-specific padding.
- Pressing the FAB hides its background subtree and presents exactly one modal
  bottom sheet with a scrim, drag dismissal, keyboard avoidance, safe-area
  handling, and focus behavior unchanged.
- Dismissing and reopening preserves the draft; changing the logical key resets
  state; disablement, button events, RTL, large text, and reduced motion retain
  their existing behavior.
- Tests mount the component through `floatingActionButton` and include a
  regression assertion that the collapsed component does not reduce scaffold
  body height.
- Documentation describes `Expandable_message_composer` as a
  `floating_action_button` child and does not recommend
  `bottom_navigation_bar` placement.
- Obsolete bottom-navigation-specific layout code, tests, and guidance are
  removed rather than retained as compatibility paths.
- Flutter formatting, static analysis, package tests, and the relevant OCaml
  tests pass.

## Risks

- A scaffold exposes one floating action button slot. An application that
  already uses that slot must explicitly choose which action owns it. The
  expandable composer will no longer consume the unrelated bottom navigation
  slot as a workaround. Supporting simultaneous primary actions requires a
  separately designed multi-action component.
- Moving placement ownership to `Scaffold` changes exact margins and safe-area
  geometry to Flutter's standard FAB contract. Golden or coordinate assertions
  based on the old 8-pixel inset need to be replaced with behavioral layout
  assertions.
- Floating and docked locations interact differently with a real bottom app
  bar. The component should rely on standard scaffold behavior and avoid
  special cases inside the native widget.
- Route-active replacement with `SizedBox.shrink` must not disturb modal route
  ownership or cause the logical native widget state to be recreated.

## Questions

None. Product examples use the default `End_float`, callers retain the existing
location parameter, and `Expandable_message_composer` occupies the scaffold's
single FAB slot. Product code resolves any existing-FAB conflict explicitly;
multi-action support is outside this bugfix and requires a separate decision.

## Consequences

- The collapsed component's render bounds equal the visible extended FAB; it
  no longer reserves a 72-pixel bottom band or overrides scaffold placement.
- Scaffold body content reaches the available bottom edge when there is no real
  bottom navigation bar. When one exists, only that real bar reserves body
  space, and Scaffold positions the FAB relative to it.
- All six supported floating and docked locations produce the same geometry as
  a direct Material extended FAB.
- Modal presentation, keyboard and safe-area avoidance, draft preservation,
  focus, dismissal, events, disablement, semantics, RTL, large text, and reduced
  motion retain their existing behavior.
- Public Dart, OCaml, and custom-widget documentation define the FAB-slot
  contract, the default `End_float` location, and the single-slot ownership
  rule. No protocol or native schema change is introduced.
- The focused expandable composer suite passes 24 of 24 tests. Dart formatting
  passes for all 84 package source and test files, Flutter analysis reports no
  issues, all 447 Flutter package tests pass, the relevant OCaml tests and OCaml
  formatting pass, and agent-document and diff-whitespace validation pass.
- A signed Debug integration runner built from the working-tree Flutter package
  passes on a physical iPhone 13 running iOS 26.6.1. It verifies that the
  collapsed body reaches the 844-point viewport bottom, the composer root equals
  the visible FAB bounds, tapping opens the modal, the focused composer follows
  the real 336-point software-keyboard inset, scrim dismissal restores the FAB,
  and reopening preserves the exact draft. The temporary device-test source and
  local package override were removed after verification.
