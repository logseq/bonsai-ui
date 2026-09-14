# Preserve Scroll Event Travel Order

## Problem

Flutter emits every scroll notification from `_guardedScrollable` as a
`ScrollEventPayload { pixels, delta }`. `ScrollUpdateNotification` contributes
its signed `scrollDelta`; all other notification types contribute zero.

`EventBatchQueue` nevertheless classifies `scrollNotification` as a
coalescible state event. A new scroll event with the same node, handler, and tag
removes the pending event and appends the new one. This loses travel and also
moves the surviving scroll event after any ordered events that were between the
two notifications. The current queue test explicitly expects `{10, +1}` to be
discarded in favor of `{20, +2}`.

Consequently, runtime scheduling changes application behavior:

- `+23, +1` can arrive as only `+1`, so 24 points of real travel becomes one;
- `+24, ScrollEnd(0)` can arrive as only zero;
- `+20, -4, +20, +4` can arrive as only `+4`, erasing reversal boundaries;
- a slower runtime or higher-frequency touch, wheel, or trackpad source loses
  more information before the next presentation-success flush.

The protocol and OCaml dispatcher already preserve an ordered event list and
finite `pixels`/`delta` doubles. The loss occurs before encoding, inside the
Dart queue. However, the existing payload does not identify whether a zero
delta originated from `ScrollStart`, `ScrollEnd`, overscroll, or another
notification subtype.

## Evidence

- The previous queue test expected a pending `{10, +1}` scroll event to be
  removed and `{20, +2}` to be appended after an intervening press.
- RED reference-model tests reduced `+23,+1` to only `+1`, erased zero and sign
  boundaries, and showed that enqueueing after `prepareBatch` invalidated the
  prepared sequence prefix.
- The renderer already emits one typed `ScrollEventPayload` for every Flutter
  notification, so no protocol or widget-registry change was required.

## Proposal

Define scroll notifications as an ordered travel stream rather than a
latest-value state stream. The queue must retain enough ordered information for
the OCaml handler to reconstruct signed travel, same-direction accumulation,
direction changes, zero-delta boundaries, large deltas, and the order of
threshold crossings independently of flush cadence.

The leading candidate is lossless run compaction at enqueue time:

- only adjacent scroll updates for the same node, handler, tag, source
  revision, and nonzero sign may be merged;
- a merged run keeps the latest `pixels` and the exact sum of its deltas;
- zero deltas, sign changes, source-revision changes, and intervening events
  always create boundaries and retain order; and
- sequence, coalesced/dropped instrumentation, prepared-batch snapshots, and
  commit validation must have one documented meaning for a merged run.

This representation preserves every fact required by the supplied examples
without emitting one event per high-frequency update in the common
same-direction case. The investigation must prove that a consumer applying a
threshold accumulator sees the same transitions for immediate flushes, one
flush after all input, and flushes at every possible boundary.

The current payload does not gain notification phase identity. Each zero-delta
notification remains an ordered boundary, but OCaml does not distinguish
`ScrollStart`, `ScrollEnd`, and other zero-producing Flutter notification
classes. The expected implementation scope is the Dart queue and
renderer-focused tests only; no generated protocol file, OCaml public event
type, file under `spec/`, Dune file, event tag, or current scroll payload layout
changes.

If more than 1,024 pending runs cannot be compacted without losing a zero
boundary, sign reversal, source revision, or intervening event order, enqueue
must apply explicit backpressure and surface the existing fatal root error. It
must never silently evict ordered scroll travel. Merging same-sign deltas uses
normal IEEE-754 addition; preserving each source delta's exact bit pattern is
not part of this contract.

## Decision

Scroll notifications are ordered travel events, not latest-value state.
Adjacent nonzero events may be compacted only when node, handler, tag, source
revision, sign, and adjacency all match. A compacted run keeps the latest
`pixels` and the IEEE-754 sum of its deltas. Zero deltas, sign changes, source
revision changes, and intervening events are lossless order boundaries.

The current `{ pixels, delta }` wire payload remains unchanged, so ordered
zero boundaries are observable but their Flutter start/end phase names are
not. More than 1,024 non-compactable pending runs produces explicit
backpressure/fatal handling rather than a drop, eviction, unbounded queue, or
protocol-level segmented payload.

## Alternatives considered

### Make every scroll notification non-coalescible

This is the simplest lossless ordering rule and should be kept as the reference
model in tests. It can fill the queue rapidly while the runtime is delayed,
turning a common high-frequency input into root-fatal backpressure at 1,024
pending events.

### Keep only the latest `pixels` and derive travel from positions

Start and end positions cannot recover reversals, overscroll behavior,
threshold-crossing order, or multiple zero notifications. It does not satisfy
the observable-stream requirement.

### Sum every pending delta for one handler

Net summation preserves neither direction changes nor ordered zero boundaries.
It can cancel real travel and produce a different threshold state.

### Merge adjacent same-sign travel runs

This is the leading candidate because summing contiguous same-direction deltas
preserves total travel and its direction boundaries. It still has a worst case:
alternating signs and zero notifications cannot be compacted without loss.

### Add a batched list of scroll segments to the wire payload

A segment list can retain many runs in one queued event and can encode phase
metadata, but it expands the protocol, generated fixtures, Dart/OCaml codecs,
public event types, and ABI review surface. It should be selected only if the
current event list plus documented backpressure cannot meet the required bound.

## Acceptance criteria

- For each stream `+23,+1`, `+24,0`, `+20,-4`,
  `+20,-4,+20,+4`, `+100`, and `-23,-1`, OCaml-observable signed
  travel and zero boundaries are identical whether the queue flushes after
  every input, once at the end, or at any intermediate boundary.
- A zero-delta event never replaces or erases a preceding nonzero run.
- Direction reversals always separate observable runs; no merge computes a net
  delta across opposite signs.
- Same-direction compaction, if selected, preserves the exact delta sum and
  latest pixels and does not cross another renderer event or source revision.
- Large deltas remain large enough for a consumer to perform every required
  threshold transition; they are not clamped or reduced to one transition.
- Event order relative to presses and other ordered events remains stable.
- Vertical, horizontal, reversed, overscrolled, touch, mouse-wheel, and
  trackpad-like input use the same queue semantics.
- Tests replace the current last-scroll-wins assertion with a reference-model
  matrix, include prepared-batch enqueue/commit behavior, and cover the chosen
  queue-bound policy.
- Dart formatting, Flutter analysis, focused event queue and renderer tests,
  the complete Flutter package tests, protocol checks if the wire changes, and
  `spec-dev-tool check --all` pass.

## Risks

- Any exact ordered representation can grow under alternating directions and
  zero notifications while the runtime is not consuming events.
- Floating-point summation can differ bit-for-bit from per-event application;
  tests must define whether exact arithmetic identity or equivalent signed
  travel within normal IEEE-754 behavior is required.
- Changing coalescing affects queue statistics, sequence gaps, backpressure,
  debug frame metrics, and event ordering beyond the payload assertions.
- Adding notification phase to the wire would be an intentional protocol and
  public OCaml API break, not a queue-only bugfix.

## Questions

None. The user selected ordered zero boundaries without phase names, lossless
adjacent same-sign run compaction, explicit backpressure above 1,024
non-compactable runs, and normal IEEE-754 summation.

## Consequences

- `EventBatchQueue` now treats scroll notifications separately from replaceable
  state. Only an adjacent unprepared run with matching identity, source
  revision, and nonzero sign is compacted.
- Prepared prefixes are immutable. New travel after preparation starts a new
  run, and resync invalidates any protected prepared prefix.
- Alternating signs, zero boundaries, intervening events, and full protected
  queues remain lossless and apply explicit backpressure instead of eviction.
- The reference-model matrix passes at every flush boundary, and all 460 Flutter
  package tests pass with formatting and analysis clean.
