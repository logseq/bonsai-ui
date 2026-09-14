# Expandable Message Composer Safe Area Jump

## Problem

`ExpandableMessageComposer` is the `Scaffold.floatingActionButton` child. While
its modal composer route is active, `_ExpandableMessageComposerState.build`
returns `SizedBox.shrink()` so the collapsed FAB cannot paint, receive input, or
contribute semantics behind the sheet. The only condition controlling that
replacement is whether `_sheetRoute` is null.

During a normal dismissal, the modal route can finish its reverse transition
before the iOS software keyboard has finished hiding. The route completion
callback then clears `_sheetRoute`, which lets the collapsed FAB re-enter the
Scaffold while the inherited `MediaQuery.viewInsets.bottom` is still positive.

The same ordering can occur without the route completion callback. A successful
save may replace the keyed composer while its sheet and keyboard are active.
The old State removes its active route synchronously in `dispose()`, while the
new State has no `_sheetRoute` and builds a collapsed FAB in the same widget
update. The new State therefore also needs to derive visibility from inherited
window geometry rather than from the old State's route lifecycle.

`Scaffold.resizeToAvoidBottomInset` defaults to true. For every positive bottom
view inset, Scaffold calculates a zero bottom `minViewPadding`; when the final
keyboard frame changes from a small positive inset to zero, the device bottom
Safe Area returns. On an iPhone with 34 logical pixels of bottom view padding,
the prematurely restored FAB can therefore appear about 33 pixels too close to
the physical bottom edge for one frame and then jump upward to its stable
`End_float` position.

This is not a modal-sheet placement defect. Route reversal and keyboard
dismissal are intentionally concurrent. The defect is that collapsed-content
visibility currently depends only on route ownership even though stable
Scaffold FAB placement also depends on the inherited keyboard inset.

## Evidence

- `_ExpandableMessageComposerState.build` returns the animated collapsed FAB
  whenever `_sheetRoute == null` and otherwise returns `SizedBox.shrink()`.
- The route completion callback unfocuses the editor and clears `_sheetRoute`
  as soon as the modal route completes; it does not wait for the keyboard inset
  to become zero.
- `_ExpandableMessageComposerState.dispose` removes an active route immediately,
  so a replacement State cannot infer the still-hiding keyboard from route
  ownership.
- Flutter Scaffold owns the standard FAB margin, directionality, bottom-bar
  coexistence, and Safe Area-aware placement. Reproducing those calculations
  inside `ExpandableMessageComposer` would conflict with the existing FAB-slot
  ownership decision.
- Existing tests cover route dismissal, keyed State replacement, iOS keyboard
  geometry for the expanded sheet, RTL, large text, reduced motion, focus,
  draft preservation, and repeated expansion, but do not hold a positive
  inherited keyboard inset after the route or old State disappears.

## Proposal

Make collapsed FAB visibility depend on both pieces of current inherited state:
the composer has no owned sheet route and
`MediaQuery.viewInsetsOf(context).bottom == 0`.

When either an owned sheet route is present or the inherited bottom keyboard
inset is positive, return an empty widget. This keeps the collapsed FAB out of
painting, hit testing, and semantics throughout keyboard dismissal. Reading the
inset during `build` establishes the normal inherited `MediaQuery` dependency,
so both the surviving State and a newly created keyed State rebuild when the
inset reaches zero. On that first zero-inset frame, Scaffold has also restored
the device bottom Safe Area and can lay out the existing FAB directly at its
stable location.

Keep `_dismissSheet` unchanged: unfocus and reverse/pop the route immediately,
allowing route reversal and keyboard dismissal to remain concurrent. Do not add
a retained `BuildContext`, `WidgetsBindingObserver`, metrics listener, timer,
post-frame delay, second FAB, opacity-only hiding, or composer-owned FAB
positioning. Do not change controller, draft, focus, animation, enabled state,
or modal-route ownership.

This is a native Flutter host-widget change only. The existing Dart constructor,
native widget schema, protocol, OCaml API, and generated files can express the
required behavior without modification. Because no OCaml framework source or
iPhoneOS SDK input changes, the fix should ship with the Flutter host package
and should not require a new framework/iOS SDK revision.

## Decision

The collapsed `ExpandableMessageComposer` is built only when the State owns no
modal sheet route and the inherited `MediaQuery.viewInsets.bottom` is zero.
When either condition is false, the widget returns `SizedBox.shrink()` so no
collapsed FAB paints, receives hit tests, or contributes semantics.

The implementation uses `MediaQuery.viewInsetsOf(context)` during `build`, so
the current State or a keyed replacement State rebuilds on the first zero-inset
frame. Route dismissal remains immediate and concurrent with keyboard
dismissal. No lifecycle observer, retained context, timer, post-frame delay,
custom FAB positioning, protocol change, or compatibility path is introduced.

## Alternatives considered

### Delay route dismissal until the keyboard is hidden

Waiting to pop the modal route would serialize keyboard dismissal and route
reversal, changing established Escape, scrim, drag, and action behavior. It
would also leave the replacement-State case unresolved because disposal must
remove the route immediately.

### Retain route state until the keyboard inset reaches zero

Using `_sheetRoute` as a proxy after its route has completed conflates route
ownership with window geometry and complicates disposal and repeated expansion.
A new keyed State has no access to the old route field, whereas it naturally
inherits the current `MediaQuery`.

### Observe window metrics outside build

A long-lived metrics observer or retained context would add registration,
disposal, and stale-lifecycle risks for geometry already exposed as an inherited
dependency. It would also require manually scheduling the same rebuild that
`MediaQuery.viewInsetsOf` provides.

### Hide the FAB with opacity or custom semantics wrappers

Opacity alone can preserve hit testing or semantics, and a stack of wrappers is
unnecessary. Returning the existing empty widget ensures the hidden collapsed
presentation paints nothing, cannot be hit, and contributes no FAB semantics.

### Reproduce Scaffold placement during positive insets

Computing a compensating offset would duplicate private Scaffold behavior and
would still expose a transient FAB. The required behavior is to reveal the
single existing FAB only when Scaffold's Safe Area-aware position is stable.

### Use a fixed delay after route completion

Keyboard animation timing varies by platform, input method, accessibility
settings, and user interaction. A timer cannot identify the first stable frame
and would make animations-disabled dismissal unnecessarily late.

## Acceptance criteria

- During same-State modal dismissal, the collapsed FAB is absent while the
  inherited `MediaQuery.viewInsets.bottom` remains positive after the route has
  completed.
- During keyed composer replacement with an active sheet and positive keyboard
  inset, the old route is removed and the replacement composer does not expose
  a collapsed FAB until the inherited inset reaches zero.
- In both paths, the collapsed FAB first appears on the zero-inset frame, at the
  same Safe Area-aware Scaffold position as a FAB initially built with a zero
  inset; there is no intermediate near-bottom placement.
- While hidden for a positive inset, the collapsed FAB does not paint, receive
  hit tests, or contribute FAB semantics.
- Route reversal starts immediately when dismissal is requested and remains
  concurrent with keyboard dismissal.
- With a zero keyboard inset, route dismissal restores the FAB normally with
  both ordinary animations and `Duration.zero`/disabled animations.
- Controller and exact draft preservation, focus behavior, FAB presentation
  animation, enabled/disabled semantics, RTL, large text, Escape, scrim, drag
  dismissal, save-driven replacement, and repeated expansion retain their
  existing behavior.
- Focused widget tests cover the same-State route-completion ordering and keyed
  replacement ordering using an iPhone-sized `MediaQuery` with non-zero bottom
  `viewPadding` and explicitly controlled `viewInsets`.
- The focused regression tests fail against the current implementation because
  the FAB becomes visible at a positive inset, then pass after the visibility
  condition is corrected.
- The complete `bonsai_flutter` Flutter test suite and `flutter analyze` pass.
- No OCaml, protocol, generated, or Dune file changes are required.

## Verification plan

Follow test-driven development:

1. Add both focused widget regression tests before changing the native widget.
2. Run the focused tests and confirm that each fails on the premature collapsed
   FAB visibility or placement, not because of a test harness error.
3. Add the smallest build-time visibility condition using the inherited bottom
   view inset.
4. Re-run the focused tests and existing expandable composer tests.
5. Review disposal, route-generation callbacks, inherited dependency rebuilds,
   and animation-controller ownership for leaks or delayed work; simplify any
   redundant code without broadening the change.
6. Run the complete package Flutter test suite, `flutter analyze`, formatting
   checks, `git diff --check`, and `spec-dev-tool check --all`.

## Risks

- Any unrelated positive bottom keyboard inset in the same inherited
  `MediaQuery` will keep the collapsed composer hidden. This is acceptable: it
  avoids exposing the FAB at unstable Scaffold geometry and restores it when
  that keyboard closes.
- Tests that only pump until the modal route disappears may accidentally let
  the simulated inset reach zero at the same time. The regression harness must
  control route progress and `MediaQuery.viewInsets` independently so it proves
  the transient interval exists.
- Reading the full `MediaQuery` instead of the view-insets aspect could trigger
  unnecessary rebuilds. The implementation should use the narrow inherited
  view-insets dependency.
- A visibility implementation that keeps the FAB subtree mounted but merely
  transparent could retain hit testing or semantics. The empty-widget behavior
  must remain structural.

## Questions

None. The reported lifecycle orderings, visibility requirement, allowed
inherited dependency, and explicit non-goals determine the candidate fix and
verification scope. Implementation was explicitly requested after exploration
completed.

## Consequences

- Same-State route completion and keyed State replacement no longer expose the
  collapsed FAB while a positive bottom keyboard inset leaves Scaffold's
  bottom safe-area placement unstable.
- The collapsed FAB returns on the first zero-inset build at the same
  Safe Area-aware Scaffold position as the original stable collapsed frame.
- Existing route reversal, focus, draft, presentation animation, enabled state,
  RTL, large-text, and repeated-expansion behavior remains owned by the existing
  implementation.
- Two focused widget tests cover the route-completion and keyed-replacement
  orderings. The complete Flutter package suite passes 469 tests, Flutter
  analysis reports no issues, Dart formatting and diff checks pass, and all
  agent decision documents validate.
- Only the Flutter host widget, its tests, and this decision document change.
  No OCaml, protocol, generated, Dune, framework source, or iPhoneOS SDK input
  changes are required.
