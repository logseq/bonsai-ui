# Expandable Composer Fab Presentation Transition

## Problem

`ExpandableMessageComposer` accepts `fabPresentation`, `animationDuration`,
and `animationCurve`, but a same-key update from `extended` to `compact`
replaces the collapsed FAB presentation in one build. The outer
`_ExpandableMessageComposerState`, active modal route, draft controller, and
focus node survive, but the visible width, label, and shape do not transition.

The discontinuity is observable before the configured duration expires: an
extended FAB about 113.697 logical pixels wide becomes exactly 56 logical
pixels wide on the first property-update frame, its `Capture` label disappears,
and its compact shape is already settled. The reverse update has the same jump.
This makes the component's existing motion inputs misleading and breaks the
requested Material motion behavior.

Current code explains the result:

- `_ExpandableMessageComposerState._buildFab` synchronously selects either
  `FloatingActionButton.extended` or the regular `FloatingActionButton` from
  `widget.fabPresentation`.
- `animationDuration` is used only for the modal bottom-sheet route, and
  `animationCurve` is not used by the collapsed FAB.
- The settled variants are already correct: compact is a non-mini 56 by 56 FAB,
  and both variants share one outer tooltip and button semantics node.
- Same-key and open-modal tests already prove State, route, draft, controller,
  focus, and action continuity. The missing coverage is the visual transition,
  interruption, and reduced-motion behavior.

## Evidence

- A RED widget test changed a stable-key composer from `extended` to `compact`
  and observed the first updated frame at exactly 56 logical pixels instead of
  the prior extended width.
- `_buildFab` selected a settled constructor directly from
  `widget.fabPresentation`; no animation object retained painted progress.
- The route duration was the only consumer of `animationDuration`, and the
  collapsed FAB did not read `animationCurve` or
  `MediaQuery.disableAnimations`.

## Proposal

Research and specify one collapsed-FAB morph owned by the existing
`_ExpandableMessageComposerState`. The proposed contract should define a
continuous progress value whose endpoints exactly match the current extended
and standard compact presentations and whose intermediate frames interpolate:

- FAB width while keeping the scaffold trailing edge fixed;
- label opacity and the horizontal space occupied by the label and its gap;
- the resolved extended and regular FAB shapes; and
- any endpoint padding needed to make compact settle at exactly 56 by 56.

A presentation update should animate from the currently painted progress to
the new endpoint with the component's configured duration and curve. A reversal
must not queue a second animation or jump through an endpoint. An active morph
must adopt updated duration and curve values immediately while continuing from
its current visual progress. A zero configured duration or
`MediaQuery.disableAnimations == true` makes the effective duration zero and
must synchronously settle at the target with no intermediate frame.

Keep a single interactive FAB surface and the existing outer tooltip and
semantics ownership throughout the morph. Do not key the animation by
presentation, create a second composer State, duplicate semantics, or move
draft/route resources. An update while the modal route is active should update
the hidden target configuration without rebuilding the route; dismissal should
reveal the current settled presentation rather than replaying an invisible
transition.

The investigation should compare an explicit controller-driven morph with
Flutter implicit animation primitives, including how each handles rapid
reversal, a duration or curve update during motion, Material 2 and Material 3
default shapes, custom `FloatingActionButtonThemeData`, RTL trailing placement,
large text, and disabled state. Both settled endpoints must use the standard
Flutter FAB constructors, and every transition frame must remain one literal
Flutter `FloatingActionButton`. No frame may expose two clickable FABs or two
button semantics nodes.

Expected implementation scope is limited to
`flutter/packages/bonsai_flutter/lib/src/native_widget/expandable_message_composer.dart`
and its focused Flutter tests. The public Dart/OCaml properties, kind-7 schema
version 2 payload, registry identity, event IDs, modal route, and files under
`spec/` or any Dune file should remain unchanged.

## Decision

The existing composer State owns one interruptible collapsed-FAB morph. Width,
label opacity and occupied space, and shape interpolate continuously between
the standard extended and regular 56-by-56 FAB endpoints while scaffold
trailing alignment stays fixed. Every frame contains exactly one literal
`FloatingActionButton`, one tooltip, and one button semantics node.

Presentation reversals and motion-parameter updates continue from the current
painted progress without jumping or queuing. `MediaQuery.disableAnimations`
overrides a nonzero encoded duration, and either reduced motion or an explicit
zero duration settles the target immediately. The animation remains ordinary
mutable configuration inside the existing keyed composer State and does not
change route, draft, controller, focus, event, registry, or wire ownership.

## Alternatives considered

### Continue switching the two settled FAB constructors

This preserves exact endpoint widgets but has no intermediate geometry or
label frames. `didUpdateWidget` continuity alone does not satisfy the visual
motion contract.

### Cross-fade or switch between two complete FABs

`AnimatedSwitcher` can fade between complete variants, but two descendants may
coexist during the transition. It does not inherently interpolate width or
shape, and it risks duplicate hit targets, tooltips, and semantics. It also
makes the scaffold trailing-edge geometry harder to keep stable.

### Animate only an outer width clip

Clipping an otherwise settled extended FAB can create intermediate widths, but
it leaves label opacity, hit testing, semantics bounds, shape, and compact
endpoint fidelity underspecified. A clip-only transition is therefore not a
complete morph.

### Replace the composer or key the FAB by presentation

Replacement would discard the continuity that the existing keyed component
already guarantees. Presentation remains mutable configuration, not an
identity boundary.

## Acceptance criteria

- Starting extended with a positive duration, the first update frame does not
  settle at width 56; before completion at least one frame has
  `56 < width < extendedWidth`, partial label opacity, partially collapsed label
  space, and an intermediate shape.
- The FAB's trailing edge remains unchanged across the full transition in all
  six scaffold FAB locations and in both LTR and RTL layouts.
- Extended and compact endpoints retain their current Material/theme behavior;
  compact settles at exactly 56 by 56 and contains no painted label.
- The configured curve changes sampled progress observably, and the configured
  duration determines transition completion.
- With an effective zero duration, the property-update frame is already at the
  target and no later intermediate animation frame appears.
- `extended -> compact -> extended` before the first transition completes
  reverses from the current visual progress without an endpoint jump or queued
  transition.
- There is exactly one clickable FAB, one button semantics node, and one
  tooltip throughout the animation and after completion.
- The same `ExpandableMessageComposer` State, node identity, modal route,
  exact draft, controller, focus node, enablement, and callbacks survive every
  presentation update.
- Focused tests cover both directions, midpoint geometry and opacity, shape,
  trailing-edge stability, interruption, zero-duration motion, open-modal
  updates, disabled state, RTL, large text, and custom Material themes.
- Dart formatting, Flutter analysis, focused composer tests, the complete
  Flutter package tests, and `spec-dev-tool check --all` pass.

## Risks

- Reproducing both regular and extended FAB theme endpoints during an
  intermediate custom composition can drift from Flutter defaults as Material
  implementations evolve.
- Measuring or reconstructing extended intrinsic width incorrectly can cause a
  first-frame jump, text overflow, or a 55/57-pixel compact endpoint under
  large text and custom themes.
- Rebuilding animation state from changing widget properties can restart the
  curve or lose velocity on rapid reversals unless interruption semantics are
  tested directly.
- Extra opacity or semantics wrappers can accidentally leave the disappearing
  label accessible after it is visually gone.

## Questions

None. The user selected reduced-motion override, immediate adoption of changed
motion parameters from current visual progress, and one literal
`FloatingActionButton` throughout the morph.

## Consequences

- The existing composer State now owns one `AnimationController` whose value is
  the continuous presentation progress. Endpoint frames use the standard
  compact and extended constructors; intermediate frames constrain one extended
  FAB while interpolating label space, opacity, padding, and resolved shape.
- Reversal and live motion-parameter updates animate from the current value.
  Zero duration, reduced motion, and hidden modal-route updates settle the
  selected endpoint immediately.
- Focused tests cover both directions, curve and duration changes, interruption,
  Material 2 shape interpolation, all scaffold locations, LTR and RTL, large
  text, disablement, reduced motion, and modal continuity.
- Flutter formatting and analysis pass, and all 460 Flutter package tests pass.
