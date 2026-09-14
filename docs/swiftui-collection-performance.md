# SwiftUI collection measurements

Measured on September 14, 2026, on an Apple M4 Max running macOS 26.6.2,
using Swift 6.2.1 and the SwiftPM Debug library. The real OCaml
`native-mixed-v` and `native-mixed-h` entrypoints each supply 10,003 keyed
records. No application state or frame payload is mocked.

## Results

| Axis | Update | Samples | Median (ms) | p95 (ms) | Maximum (ms) |
| --- | --- | ---: | ---: | ---: | ---: |
| Vertical | Initial | 3 | 50.670 | 51.722 | 51.722 |
| Vertical | Adjacent | 300 | 2.116 | 2.642 | 5.821 |
| Vertical | Distant | 300 | 4.804 | 5.839 | 6.234 |
| Horizontal | Initial | 3 | 48.687 | 48.738 | 48.738 |
| Horizontal | Adjacent | 300 | 2.060 | 2.401 | 5.826 |
| Horizontal | Distant | 300 | 4.801 | 5.625 | 6.525 |

Totals include the native OCaml pump and output copy, Swift decoding, staging,
render-tree validation/commit, synchronous native scrolling/layout/display,
and native acknowledgment. Input encoding, the 2 ms inter-sample run-loop
delay and diagnostic assertions are excluded. The native viewport is checked
to reach the requested offset within one point after each update.

The initial snapshot publishes the catalog with an empty row window; it is
**not time to the first visible populated screen**. Runtime opening is also
separate (23.55–28.15 ms in these six processes). The raw reports include
the first populated window in warm-up. Each process then measures 100 adjacent
and 100 distant windows after 20 warm-up updates. Each axis uses three fresh
processes: 1,326 updates total, including initial and warm-up samples. p95 uses
the nearest-rank method; initial p95 has only three samples.

Every requested window contains 15 rows plus overscan. The diagnostic verifies
its exact keys and child count against the real catalog. Measured updates
contain at most 21 rows and 61 render nodes. Initial frames are 249,958 bytes;
adjacent and distant incremental frames are at most 3,536 and 3,552 bytes.

Sampled resident memory peaks at 88.56–89.05 MiB across the six processes.
This is whole-process RSS, including OCaml, SwiftUI, AppKit and their caches.
The final RSS sample still owns the render tree and native window even though
the OCaml runtime has closed; retained RSS is not evidence of a leak.

## Scope and reproduction

These are observations, not invented pass/fail budgets. The standalone
diagnostic drives real `NSScrollView` movement with synthetic visible-range
events and uses the production runtime, frame and renderer implementations.
It bypasses `BonsaiSession` input sampling and does not measure display-link
cadence, compositor presentation, physical gestures, Release performance,
self-sizing/Dynamic Type, iOS performance or maximum supported catalog size.
Those requirements remain open. Existing mixed-collection integration tests
separately cover session input, resize, anchor retention and boundedness.

From the Git worktree, with the configured OCaml switch:

```sh
opam exec --switch=bonsai-flutter-v017-exact -- dune build native/test/libruntime_fixture.dylib
python3 tool/measure_swiftui_collection.py
```

The runner rebuilds the Swift library incrementally, links only the current
SwiftPM output graph, and starts six fresh measurement processes. A failed
run cannot leave an earlier summary masquerading as a successful new report.
Compilation output, per-update measurements and full provenance are written
under `_build/validation/collection-performance/`.

The [recorded summary](performance/swiftui-collection-2026-09-14.json) retains
phase/component timings, individual memory runs, compiler/host versions,
the dirty-worktree revision, fixture/probe hashes and raw-report hashes.
The [Swift probe](../tool/measure_swiftui_collection.swift) and
[runner](../tool/measure_swiftui_collection.py) are reproducible diagnostics;
neither is linked into the shipped application.
