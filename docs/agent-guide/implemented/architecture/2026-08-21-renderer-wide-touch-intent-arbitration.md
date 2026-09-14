# Renderer Wide Touch Intent Arbitration

## Problem

Renderer-owned interactive widgets independently create Flutter gesture
recognizers. Each recognizer uses Flutter's default gesture-arena and touch-slop
behavior unless the widget implements a local exception. A parent scrollable
cannot begin tracking until every remaining competitor either accepts or
rejects the pointer.

The direction-aware recognizer in `Swipe_action` demonstrates why a local fix
is insufficient. It rejects a horizontal swipe after a touch reaches six
logical pixels of decisively vertical displacement, but a real Mail row also
contains a `PressableHost` tap recognizer. The swipe recognizer leaves the arena
at six pixels while the press recognizer remains until Flutter's normal touch
slop is exceeded. The list therefore retains nearly all of the original startup
delay.

Profile-mode measurements ran the real Mail renderer tree on a physical iPhone
with hardware model `D17AP`, iOS 26.6.1, Flutter 3.44.8, and engine revision
`0cd610717b`. The test injected pointer moves at a 16 millisecond cadence and
read the real Mail `ScrollPosition.pixels`; it did not simulate a simplified
row. Three trials at each distance produced identical results:

| Configuration | Move size | Startup samples | Startup distance |
| --- | ---: | ---: | ---: |
| Current renderer | 1 px | 23 | 23 px |
| Current renderer | 4 px | 6 | 24 px |
| Current renderer | 8 px | 4 | 32 px |
| Swipe recognizer disabled in the test bundle | 1 px | 23 | 23 px |
| Swipe recognizer disabled in the test bundle | 4 px | 6 | 24 px |
| Swipe recognizer disabled in the test bundle | 8 px | 4 | 32 px |
| Pressable recognizer disabled in the test bundle | 1 px | 10 | 10 px |
| Pressable recognizer disabled in the test bundle | 4 px | 3 | 12 px |
| Pressable recognizer disabled in the test bundle | 8 px | 2 | 16 px |

The exact synthetic cadence is not a substitute for manual-finger latency
statistics, but the same-device A/B isolates gesture ownership. Removing the
swipe recognizer does not improve the real row. Removing the press recognizer
does. Manual testing of the same Profile app also reports that vertical
scrolling still feels detached from the finger.

Other renderer-owned gesture entry points use the same independent defaults:

- `PressableHost` creates a tap recognizer for press feedback and activation.
- the generic `Gesture` widget creates tap, double-tap, and long-press
  recognizers;
- `Swipe_action` creates a horizontal drag recognizer;
- `MessageComposer` creates a vertical drag recognizer;
- the detented modal-sheet handle combines tap and vertical drag recognizers.

Raw `Listener` callbacks and semantics actions do not enter the gesture arena
and are not part of this problem. Flutter-owned recognizers inside Material
widgets are outside the initial scope. They may be investigated later only when
a real renderer tree demonstrates that one remains an arena blocker after the
renderer-owned migration.

## Decision

The Flutter renderer uses a shared touch-intent arbitration layer for
recognizers owned by `bonsai_flutter`. Gesture widgets consume shared policy
instead of owning
independent threshold calculations. The initial scope is strictly
renderer-owned recognizers; it does not replace recognizers created internally
by Flutter Material widgets.

The shared classifier records movement from each pointer-down position. For
`PointerDeviceKind.touch`, let `dx` and `dy` be the absolute cumulative
displacement. It reports:

- decisive horizontal when `dx >= 6` and `dx >= 1.5 * dy`;
- decisive vertical when `dy >= 6` and `dy >= 1.5 * dx`;
- ambiguous otherwise.

Classification remains cumulative, asymmetric at each recognizer, and local to
touch input. A noisy first delta or near-diagonal movement does not force a
decision. Mouse, trackpad, stylus, inverted-stylus, and unknown pointer kinds
retain their existing behavior unless later device evidence justifies a
separate policy.

The shared renderer-internal gesture package contains:

- a `TouchIntentTracker` that owns per-pointer down positions and
  classification;
- direction-aware tap, double-tap, long-press, horizontal-drag, and
  vertical-drag recognizers;
- a focused `BonsaiGestureDetector` or equivalent factory layer that configures
  only the callback combinations used by renderer widgets.

Apply role-specific rejection rules:

| Recognizer role | Early rejection |
| --- | --- |
| Horizontal drag | Decisive vertical touch intent |
| Vertical drag | Decisive horizontal touch intent |
| Tap, double tap, and long press | Any decisive horizontal or vertical touch intent |
| Ambiguous movement | No early rejection |

Tap-like recognizers therefore reject once touch displacement reaches six
logical pixels with at least 1.5 axis dominance in either direction. They do
not reject near-diagonal movement, and the early-rejection policy does not
apply to non-touch pointer kinds.

`Swipe_action` uses the shared horizontal recognizer instead of its former
local recognizer. `PressableHost`, generic `Gesture`, `MessageComposer`, and the
detented-sheet handle use the same factory and the role-specific rejection
rules above.

Do not change the OCaml public API, native-widget schema, wire protocol,
business call sites, global `DeviceGestureSettings`, or Flutter's Scrollable
implementation. Do not treat `Listener` or semantics callbacks as recognizers.

This architecture supersedes the component-local scope of
[`Swipe_action` Direction-Aware Gesture Arbitration](../../implemented/bugfix/2026-08-21-swipe-action-direction-aware-gesture-arbitration.md)
without denying or deleting that earlier decision. The implemented document
remains as the historical record of the first local step while this
architecture is designed and implemented. After this architecture is
implemented and verified, archive the earlier decision because renderer-wide
arbitration becomes the authoritative solution.

The six-pixel boundary means competing renderer recognizers leave the arena at
that displacement. It does not guarantee that `ScrollPosition.pixels` changes
at exactly six pixels. On iOS, `BouncingScrollPhysics` applies an additional
3.5 logical-pixel motion-start threshold after the scrollable takes ownership.
The physical-device target is therefore relative to an otherwise equivalent
pure row: a swipe-wrapped row may require at most one additional delivered
sample, and its startup distance must remain within one scheduled move
increment of the pure row under the same delivery method. This target seeks
near-parity without requiring `startupSamples <= 1` from pointer down.

## Alternatives considered

### Keep direction awareness local to `Swipe_action`

This is the current implementation. Real Mail measurements remain at 23--32
logical pixels because `PressableHost` stays in the arena. A recognizer-local
fix cannot establish a renderer-wide ownership guarantee.

### Lower global gesture slop

Changing global `DeviceGestureSettings` would affect Flutter-owned controls,
navigation, text selection, and interactions outside the renderer components
that produced the defect. It also uses radial distance rather than the selected
axis-dominance rule.

### Set a six-pixel slop on stock recognizers

Per-recognizer gesture settings are simpler than custom recognizers, but stock
tap and long-press recognizers reject by radial distance. They cannot preserve
the rule that near-diagonal movement remains ambiguous, and the setting can
also alter stylus behavior.

### Put all recognizers in one gesture-arena team

A team coordinates acceptance but does not express the required directional
rejection policy by itself. One team member rejecting does not necessarily
remove the remaining members, and unrelated child actions must still cancel
independently.

### Change Scrollable drag-start behavior

Using down-position drag behavior or changing iOS scroll physics could recover
the scrollable's pending displacement, but it changes list behavior globally
and exceeds the gesture-ownership problem. It is necessary only if the required
outcome is movement at six pixels rather than ownership within one additional
sample.

### Infer only the nearest ancestor Scrollable axis

A tap recognizer could reject only intent matching its nearest scrollable's
axis. This minimizes cancellation changes but complicates nested horizontal and
vertical scrollables and does not cover sibling drag recognizers such as a
sheet-handle drag. This alternative is not selected: tap-like recognizers reject
either decisive axis so the policy is independent of ancestor-axis inference.

### Replace every Flutter-owned Material recognizer

Reimplementing buttons, ink responses, navigation controls, and other Material
interactions would create a large maintenance and accessibility surface. This
alternative is not selected for the initial architecture. Expansion requires a
later decision supported by real-tree evidence of a remaining Flutter-owned
blocker.

## Consequences

- One classifier now owns the six-pixel and 1.5-axis-dominance policy. Tests
  cover both equality boundaries, accumulated movement, sub-threshold and
  near-diagonal movement, reversal before a decision, and touch-only filtering.
- Renderer behavior tests cover decisive and ambiguous movement, tap,
  double-tap, long-press, drag, fling, reversal, LTR/RTL mapping, semantics,
  composer dragging, sheet dragging, and all relevant pointer kinds.
- `PressableHost`, generic `Gesture`, `Swipe_action`, `MessageComposer`, and the
  detented-sheet handle use `BonsaiGestureDetector`; the component-local swipe
  threshold calculation has been removed.
- Fixed slow, normal, and fast delivery schedules are applied identically to
  pure and swipe-wrapped Mail rows. On the macOS runner, both variants started
  after 10 samples at 10 pixels, 3 samples at 12 pixels, and 2 samples at 16
  pixels respectively across all three trials.
- The real Mail renderer tree produced the same 10/3/2 sample and 10/12/16
  pixel startup results on the macOS runner. The test reports actual elapsed
  startup latency for every trial.
- The package analyzer, all 398 package tests, both targeted macOS integration
  suites, native arm64 complete-object verification, and agent-document checks
  pass. Three unrelated pre-existing headless integration tests remain red in
  the current worktree because their FFI fixtures do not render the nodes or
  viewport expected by those tests.
- No OCaml API, native-widget schema, wire protocol, business call site, or
  Flutter-owned Material recognizer changes.
- A six-pixel tap cancellation boundary can suppress an intentional tap after
  axis-dominant finger jitter. Device filtering and near-diagonal tests bound
  that risk, but direction reversal cannot restore a recognizer after it has
  rejected the pointer.
- Renderer-only policy does not cover recognizers created internally by
  Flutter Material widgets. Expansion requires a separate decision supported
  by real-tree evidence.
- macOS synthetic cadence validates arena ownership and deterministic parity;
  it does not replace manual-finger distribution measurements on a physical
  iPhone.
- The earlier component-local `Swipe_action` decision is archived as historical
  context because this renderer-wide policy is now authoritative.
