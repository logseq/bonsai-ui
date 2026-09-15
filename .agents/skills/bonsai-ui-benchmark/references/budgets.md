# Benchmark budgets and verdicts

These are explicit starting budgets for this skill, not measured guarantees of
the current implementation or Apple standards. Record any workload-specific
replacement before collection, with its rationale. Do not relax a failed budget
after seeing a result. Keep traffic, rendering and correctness verdicts separate.

## Settled unchanged UI

The strict idle fixture has no input, animations, timers, host jobs, environment
changes or pending measurement/presentation work during the measured interval.

| Metric | Default gate |
| --- | --- |
| SwiftUI to OCaml encoded input | 0 bytes and 0 events after settling |
| OCaml to SwiftUI encoded output | 0 bytes, 0 UI operations, 0 nonempty frames |
| Revision, full snapshots, resyncs | No changes/increments |
| Native calls | Count empty pump/ack calls separately; they are not free or payload traffic |
| Idle native call rate | At most 65 pump/s and 65 ack/s with the current 16 ms foreground loop; no rejections |
| Idle execution cost | Refresh main-thread execution and native-queue execution each at most 10 ms per measured second, excluding waits (1% of one core each) |

The call ceiling detects duplicate polling and does not endorse a 60 Hz idle
wakeup policy. Report the rate and execution cost even when payload is zero.
Prefer lower idle wakeups in future designs; use the current scheduling contract
when revisiting this ceiling. If idle execution time cannot be measured, that
gate remains unmeasured instead of being inferred from a sample percentage.

Repeat with roughly 10x more static render nodes. Idle payload remains zero and
call counts stay independent of node count. Flag a repeated cost increase over
25% when it also exceeds 1 ms per second; retained-tree scans can be expensive
even with no wire traffic. Keep the absolute execution-cost gate as well.

For intentional clocks, subscriptions, application services or observers, use a
separate scenario with an explicit expected event rate. Account for these bytes
in totals; do not subtract unexplained events to make the strict idle test pass.

## Local changes and scrolling

- **No-op action:** the expected input event may cross the bridge, but after its
  acknowledgment it causes zero UI operations, no new widget revision, and no
  continuing payload. Attribute any necessary service response separately.
- **Single widget change:** operations touch the changed widget, required
  ancestors/bindings and documented dependents. No full snapshot or unrelated
  sibling recreation. After completion, traffic returns to the idle gate.
- **Native scrolling without an observer or virtual window change:** no scroll
  events or UI patches merely for changed pixel offsets. Legitimate gesture
  cancellation/focus transitions must be identified, bounded and reported.
- **Observed scrolling:** events follow the declared observer/coalescing
  semantics. Preserve required ordering and travel information. For a fixture
  with one coalesced continuous-position observer, declare an event-rate ceiling
  from its configured sampling rate, allowing at most 10% scheduling tolerance
  plus bounded start/end events. Do not apply that ceiling to intentionally
  uncoalesced gestures or multiple subscriptions. No-op handlers emit no UI patch.
- **Virtualized scrolling:** visible-range requests and window patches correspond
  to actual range/handler changes. Repeated identical ranges under the same
  handler/revision with no unfulfilled request are failures. A changed handler
  may require synchronization; record handler-only churn instead of hiding it.
  No full snapshot or resync after initial mount in steady scrolling.
- **Measured/expanded rows:** permit bounded updates for actual new measurements
  or animation state. After the gesture and configured animation duration end,
  allow up to 1 second for settling, then require the idle gate. Repeated
  measurement/geometry/scroll-correction traffic without new state is a failure.
- **Pagination:** catalog updates may scale with appended data or the catalog
  representation. Measure them separately from steady scrolling, retain existing
  keys, and forbid unrelated visible-row recreation or a full renderer resync.

Do not invent one universal KiB/frame limit: operation type, text size and node
complexity determine meaningful payload size. For each fixture declare an
operation/byte budget from the expected event and patch shape using the current
encoder, plus known framing/metadata. At minimum record:

```text
expected input events per action/range change
allowed output operation classes and affected nodes
maximum input/output bytes per action or window transition
expected steady-state calls/events per second
permitted initialization, measurement and pagination bursts
```

Derive these budgets from an independently justified minimal transition, not the
largest frame observed in the run being judged. If a valid byte budget cannot yet
be established, report measured totals and semantic/scaling results, and mark
absolute byte-budget acceptance unmeasured. Passing relative checks alone does
not establish that excessive absolute traffic is reasonable.

Compare 1,000 and 10,000 logical items with the same materialized window, content
and delivered scroll path. Exclude initial catalog upload and pagination from
this steady-state comparison, but report their costs. Outbound bytes per window
transition and inbound events per crossed row should remain within 25% across
the paired runs. Inspect exact counts when denominators are zero or small; do not
divide by zero or turn a single legitimate boundary event into a claimed 10x
regression. Compare both bytes/transition and transitions/crossed row so handler
churn cannot hide behind a low per-transition size. Work may scale with the
materialized window, but must not retransmit all logical rows on every scroll.

## Approximately 60 FPS

Evaluate only marked intervals with continuous expected visual motion on a
display configured to support at least 60 Hz. On a 60 Hz configuration use:

| Metric | Default gate, in each of 3 runs |
| --- | --- |
| Mean actual presented FPS | At least 59 FPS, a declared 1 FPS tolerance around the 60 FPS target |
| p95 presentation interval | At most 18.34 ms (about 1.1 x 16.67 ms) |
| p99 presentation interval | At most 33.34 ms |
| Maximum presentation interval | At most 50 ms during expected motion |
| Hitch time, when the instrument supports it | At most 5 ms/s of measured motion |
| Visual correctness | No blank window, jump, stale row or unintended activation |

Record the actual refresh policy. On a 120 Hz display the minimum user goal is
still approximately 60 FPS, but additionally report performance against the
8.33 ms native-refresh budget; do not call 60 FPS a successful 120 Hz result.
A display/power configuration capped below 60 Hz cannot certify the target.
Never demand 60 actual updates per second from an idle UI.

Mean FPS alone is insufficient: infrequent long stalls must remain visible in
percentiles and maxima. Apply presentation-interval gates to actual presentation
timestamps, not begin-to-end frame lifetime, SwiftUI transaction durations, or
GPU/CPU stage sums. Those other measurements are useful diagnostic evidence with
different meanings.

Absent presentation data makes FPS/frame-interval verdicts `UNMEASURED`.
Unsupported optional hitch metrics can be `N/A` with a reason; lost or ambiguous
data must not be reported as zero hitches. Report traffic loss, wrong-process
capture or intrusive instrumentation as invalid measurement, not an app failure
or a passing benchmark.
