# Swipe Action Direction Aware Gesture Arbitration

## Problem

The Journal page renders its content with a sliver list whose items support
both vertical scrolling and horizontal swipe actions. The original performance
hypothesis was that list updates produced patches that were too large and
marked too many nodes dirty. Adding stable keys to the
`Sliver.varied_extent` items substantially reduced patch size and unnecessary
node updates, improving reconciliation and item reuse.

That optimization did not remove a separate interaction problem on a physical
iPhone. During a vertical finger drag, the finger can travel approximately
24--29 logical pixels before the list begins to move. The list then scrolls at
the expected speed, but its delayed start makes the page feel sticky and
disconnected from the finger.

Physical-device investigation separates this symptom from rendering
throughput:

- Overall frame rate and build duration remain normal, without a corresponding
  dropped-frame pattern.
- OCaml runtime work, patch size, and dirty-node count are no longer the
  dominant costs.
- A list without swipe wrappers begins scrolling with little observable delay.
- Adding the horizontal swipe interaction to each item reliably reproduces the
  approximately 24--29 pixel startup lag.

Each item is wrapped by `Swipe_action`, whose horizontal drag recognizer enters
Flutter's gesture arena alongside the enclosing list's vertical scroll
recognizer. The existing swipe recognizer waits for enough movement to resolve
whether the user intends to drag horizontally. Until that competition is
resolved, the list cannot take ownership of the vertical drag. The resulting
problem is therefore delayed gesture ownership, not slow list movement after
scrolling begins.

Stable item keys and direction-aware gesture arbitration address different
parts of the interaction. Stable keys reduce reconstruction, patch work, and
dirty nodes when list contents change. Direction-aware arbitration reduces the
gesture-arena delay at the start of every vertical touch drag. Both
optimizations are required.

## Decision

`Swipe_action` uses a private direction-aware horizontal drag recognizer in
the Flutter renderer. The recognizer records each touch pointer's down
position and rejects the horizontal gesture when the absolute cumulative
displacement satisfies both conditions:

- `dy >= 6` logical pixels;
- `dy >= 1.5 * dx`.

The rule is intentionally asymmetric. It only rejects a decisively vertical
touch drag early; it does not accept a horizontal drag early. A horizontal or
ambiguous drag continues through the existing Flutter horizontal-drag
threshold and gesture-arena behavior. This preserves the current timing for
swipe tracking and cancellation of nested taps while removing the unnecessary
horizontal participant from a clear vertical drag.

Keep this behavior local to `Swipe_action`. Do not change the global gesture
settings, the list's vertical gesture handling, or other `Gesture` components.
Apply the early direction classification only to `PointerDeviceKind.touch`.
Stylus, inverted-stylus, mouse, trackpad, and unknown pointer kinds retain the
current behavior.

This is an internal Flutter renderer change. It requires no business-layer
call-site changes, OCaml API changes, native-widget schema changes, or wire
protocol changes. The existing stable-key optimization remains in place.

## Alternatives considered

### Keep only the stable item keys

Stable keys improve update and reuse efficiency, but physical-device testing
shows that the startup delay remains when the list is otherwise healthy. This
does not address per-drag gesture competition.

### Tune gesture slop globally

Reducing Flutter's global touch slop could make the arena resolve sooner, but it
would affect every drag interaction in the application and could increase
accidental gesture activation outside `Swipe_action`. The observed problem is
local to swipe-wrapped list items.

### Change the list's vertical scroll recognizer

Making the list claim gestures more aggressively could damage horizontal swipe
recognition and would couple a reusable item interaction to one parent layout.
The horizontal participant has the directional knowledge needed to leave the
arena early.

### Classify every drag immediately by its first delta

The first touch sample is noisy and often diagonal. Immediate classification
would reduce latency but could permanently choose the wrong gesture before the
user's intent is clear.

### Add an application-facing configuration option

The desired arbitration is an implementation correction for
`Swipe_action`, not a Journal-specific policy. Exposing thresholds through the
OCaml API or native-widget payload would expand the compatibility and testing
surface without an identified business-level use case.

## Consequences

- A decisive vertical touch drag removes `Swipe_action`'s horizontal
  recognizer from the gesture arena at the 6 logical-pixel boundary. A focused
  widget test verifies that the enclosing scrollable moves on the following
  pointer sample instead of waiting for horizontal touch slop.
- Movement below the distance threshold and movement just outside the
  axis-dominance boundary remain undecided and can still become horizontal
  swipes.
- Existing tests continue to cover horizontal tracking, direction reversal,
  sub-threshold rebound, distance and fling commits, nested-tap cancellation,
  and LTR/RTL direction mapping.
- Stylus, inverted-stylus, unknown, mouse, and trackpad regression tests retain
  their existing gesture behavior because early classification records only
  touch pointers.
- The implementation is local to the Flutter `Swipe_action` host. The OCaml
  API, native-widget schema, wire protocol, list recognizer, and business call
  sites are unchanged.
- Stable item keys remain responsible for reconciliation efficiency; this
  recognizer addresses gesture ownership only.
- Widget tests establish deterministic arena behavior but do not quantify
  physical-device responsiveness. Profile-mode trials on the target iPhone
  remain required to report `startupDistance`, `startupLatency`, and
  `startupSamples` for pure and swipe-wrapped lists at normal, slow, and fast
  drag speeds.
