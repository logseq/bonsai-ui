---
name: bonsai-ui-benchmark
description: "Benchmark bonsai-ui SwiftUI/OCaml bridge traffic and native rendering performance. Use for idle/no-change overhead, widget update efficiency, list virtualization, scrolling FPS, or performance regressions in this repository."
---

# Bonsai UI Benchmark

Measure two independent outcomes: SwiftUI/OCaml communication stays proportional
to meaningful work, and interactive rendering sustains approximately 60 FPS.
Low traffic does not prove smooth rendering; smooth rendering does not excuse
redundant traffic. Diagnose observed failures without assuming a particular
container or runtime optimization is the solution.

## Scope and preparation

- Follow the current worktree's `AGENTS.md` and agent-document workflow. Resolve
  repository paths from `git rev-parse --show-toplevel`, not a fixed user path.
- Default to optimized macOS builds. Benchmark physical iOS separately when
  requested; simulator results do not certify physical-device performance.
- A benchmark request permits measurement and benchmark-only fixtures, not
  production optimization. Honor a request to leave source unchanged. If counters
  or scenarios are missing, use an isolated source copy/worktree with documented
  instrumentation, or report the missing metric as `UNMEASURED`. A generated host
  directory alone does not isolate the framework sources it references.
- Record commit, dirty diff, fixture/instrumentation diff, exact binary and PID,
  hardware, OS, Xcode, OCaml switch, optimization flags, refresh rate, viewport,
  scale, power/thermal state, data seed, row structure, and enabled observers.
  Use deterministic local data and fixed keys. Keep network, image downloads,
  clock widgets and intentional timers out of the idle fixture.
- Keep builds, reports and traces in a named artifact directory outside tracked
  source unless the user specifies another location. Preserve raw measurements.

Read [measurement.md](references/measurement.md) before collecting data. It maps
the current bridge, existing statistics, build commands and Instruments workflow.
Read [budgets.md](references/budgets.md) before declaring any result; use its
default gates unless a previously agreed scenario budget supersedes them.

## Scenario matrix

Use existing Counter, Gallery and Mail examples where they implement the needed
case. Gallery has ordinary scrolling, declared/measured collections and mixed
collections. Verify the selected page's observers and state updates rather than
assuming its visible label describes an isolated workload. For missing cases,
construct the smallest fixture using current APIs; identify it as a fixture.

| Scenario | Workload and required contrast |
| --- | --- |
| Static widgets | Text, icon, button, padding/background and nested row/column; compare about 100 and 1,000 rendered nodes. Record settled idle before and after interaction. |
| Local change | Change one counter/text/toggle among unchanged siblings; 20 spaced actions. Also inject a handler action that leaves application state and widgets unchanged. |
| Native scroll | Scroll fixed content with no OCaml scroll observer, then with an explicit observer. Keep widget content unchanged in the observer variant to isolate inbound events. |
| Declared collection | Fixed-height keyed rows, 1,000 and 10,000 logical items, identical viewport/overscan and matched row content. Test slow scrolling and repeated fast direction changes. |
| Measured collection | Repeat with deterministic varying heights and text wrapping; expand/collapse a visible row and revisit it after eviction. |
| Complex rows | Mail-like nested content, actions and compact/expanded branches. Compare a simple row fixture at the same viewport and logical count; then reproduce in the real Mail example. |
| Pagination | Append fixed pages near the end while scrolling, preserve keys, and reverse direction after append. Separate deliberate fetch latency from rendering and protocol costs. |

For every scrolling case, include start, continuous motion, reversal, stop and
settled idle. Check for blank windows, jumps, stale rows and unintended actions;
high FPS with missing content is a failure. Confirm that materialized row and
native node counts stay bounded by the viewport, overscan and row complexity.
Business data and catalog metadata may legitimately grow with logical item count.

A full benchmark covers the matrix. A targeted request may select a subset, but
name omitted cases and do not call the result full-suite acceptance.

## Collection protocol

1. Declare scenario sizes, action sequence, expected events/patches and budgets
   before measuring. Fix scroll distance in logical pixels or rows and speed,
   rather than relying on an ambiguous wheel-step unit.
2. Warm up for at least 5 seconds and one traversal. Start idle measurement only
   after initial mount, environment publication, measurements, animations and
   pending presentations settle. A fixture that never settles is a finding;
   do not discard its churn as endless warm-up.
3. By default collect 10 seconds of idle, 20 seconds of continuous scrolling,
   and 10 seconds after settling, with 3 independent runs. Mark exact intervals
   and record the delivered scroll path. Exclude setup from steady-state budgets
   but report cold mount and pagination bursts separately.
4. Use low-overhead bridge counters and app-specific frame presentation data for
   acceptance. Collect verbose protocol traces, SwiftUI update traces and CPU
   samples in separate diagnostic runs. Do not compile, export another trace,
   inspect accessibility trees repeatedly, or record unrelated apps during a run.
5. For failures, correlate input, pump, output, commit, acknowledgment and
   presentation timestamps. Attribute bytes to event types and changed node IDs;
   attribute stalls to runtime work, main-thread work, layout or rendering only
   when the trace supports it. Use a controlled single-variable contrast before
   calling a hotspot the primary cause.
6. Compare all three runs with a same-device baseline when available. Retain
   failures and report median and worst run; a passing average cannot hide a
   failing run. A slow initial baseline does not relax the absolute FPS gate.

## Required measurements

Report these per scenario and phase, with clock and units defined:

- **Calls:** pump, acknowledgment and rejection counts/rates; zero-input and
  zero-output pumps; native execution versus queue wait and end-to-end latency.
- **Traffic:** actual payload bytes in each direction, bytes/second, payload
  p50/p95/max, event counts by type, and separately identified control overhead.
- **Semantic work:** incremental/full frames, UI operations versus metadata and
  host/application operations, changed/created/removed nodes, snapshots/resync
  deltas, duplicate visible-range requests, and row-window turnover.
- **Rendering:** actual presented-frame FPS during continuous motion, frame
  interval p50/p95/p99/max, missed deadlines and hitch time when supported;
  source process/window and coverage of the measured interval.
- **Supporting evidence:** materialized rows/nodes, idle main-thread CPU or time,
  memory before/after repeated traversal, and instrumentation overhead.

Do not substitute the 16 ms refresh sleep, pump count, presentation acknowledgment,
display-link callbacks, SwiftUI body updates, or transaction duration for actual
presented-frame FPS. Report idle FPS as `N/A`; a stationary UI need not redraw.
Missing or unsupported frame data is `UNMEASURED`, not an inferred 60 FPS.

## Deliverable

Write a concise report plus machine-readable results (JSON/CSV). Include:

- Reproduction commands, fixture/state setup, action script or gesture procedure,
  source/binary identity, instrument configuration and artifact paths.
- A per-scenario table with independent **traffic**, **frame pacing** and
  **correctness** results: `PASS`, `FAIL`, `UNMEASURED`, or `N/A` with reasons.
- Expected versus observed counts/bytes and exact violated budgets; predeclared
  exceptions, cold-start costs, run variability and missing coverage.
- Evidence-backed hotspots with source locations, clearly separated from
  hypotheses. Recommend the smallest experiment that would distinguish causes.

Overall acceptance requires every applicable gate to pass in every required
scenario. Do not claim a fix, run a production optimization, or replace an
existing baseline merely because a benchmark was requested.
