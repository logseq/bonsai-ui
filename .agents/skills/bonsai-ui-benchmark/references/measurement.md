# Measurement guide

Paths below are relative to the repository root. Re-read the relevant code when
using this skill; symbol semantics and tool schemas can change.

## Build and fixture entrypoints

`tool/build_swiftui_example.py` accepts `counter`, `gallery`, `mail` and other
current examples. Its Profile configuration builds OCaml with Dune `release`;
verify that the generated Swift target is optimized too. Run from a configured
host opam switch; do not hard-code the switch from an earlier machine/session.

```sh
opam switch show
python3 tool/build_swiftui_example.py --help
# Set bench_switch to the configured host switch and bench_dir to the artifact directory.
opam exec --switch="$bench_switch" -- python3 tool/build_swiftui_example.py mail \
  --target macos --configuration Profile --host-directory "$bench_dir/mail-host"
```

The macOS result is normally
`mail-host/DerivedData/Build/Products/Profile/BonsaiMail.app` under `bench_dir`.
Use the emitted path, verify the running executable and attach by exact PID.
Use available app-control tooling for UI actions. Keep the application foreground
and visible. Inspect UI state before/after, not continuously during measurement.

For physical iOS, inspect the current CLI/help and `docs/swiftui-example-builds.md`.
The example builder requires a matching iPhoneOS complete object via
`--native-object`; a macOS object cannot be reused. Record signing/device setup
and the actual device refresh configuration separately.

Useful fixtures and implementations:

| Path | Purpose |
| --- | --- |
| `examples/counter/ocaml/` | Small state change and idle starting point |
| `examples/gallery/ocaml/gallery.ml` | `scroll_component`, `collection_component`, 10,000-item declared/measured catalogs |
| `examples/gallery/ocaml/scroll_observer_catalog.ml` | Observer-enabled/disabled variants; inspect whether handlers update UI |
| `examples/gallery/ocaml/mixed_collection_catalog.ml` | Mixed collection content |
| `examples/mail/ocaml/mail.ml` | Complex rows, expansion and pagination |
| `swift/BonsaiSwiftUI/Sources/CollectionViewport.swift` | Native scroll geometry and custom window layout |
| `swift/BonsaiSwiftUI/Sources/RenderCollection.swift` | Window requests, synchronization and measurement generation |
| `swift/BonsaiSwiftUI/Sources/CollectionMeasurements.swift` | Measured extents and callbacks |

Use actual materialized counts: 20 logical rows can contain hundreds of render
nodes. Match text lengths, hierarchy, row heights, visible range and traversal
between 1,000/10,000-item fixtures. Catalog initialization is a separate phase.

The command below is useful for isolating OCaml reconcile/codec work. It does not
measure the live bridge, SwiftUI rendering, scrolling FPS or end-to-end latency:

```sh
opam exec --switch="$bench_switch" -- dune exec --profile release ocaml/bench/runtime_bench.exe
```

`benchmark/BASELINE.md` and `benchmark/PATCH_SIZE_PROFILE.md` contain historical
Flutter data. Do not run their removed Flutter commands or import their byte-size
thresholds into SwiftUI acceptance. Protocol maximum sizes are safety limits,
not performance budgets.

## Measure the real SwiftUI/OCaml boundary

| Source | Measurement point |
| --- | --- |
| `swift/BonsaiSwiftUI/Sources/NativeRuntime.swift` | Serialized native queue; `pump`, `acknowledge`, `reject`, `copyOutput` |
| `native/src/bonsai_swiftui_native.h` | C ABI signatures and `bs_output_buffer.length` |
| `native/src/bonsai_swiftui_native.c` | Actual C calls and output ownership |
| `native/src/bonsai_swiftui_ocaml_bridge.c` | OCaml callback boundary and extra buffer copies |
| `swift/BonsaiSwiftUI/Sources/BonsaiSession.swift` | Encoded input batch, no-output fast path, staging/commit and presentation fencing |
| `swift/BonsaiSwiftUI/Sources/EventBatch.swift` | Inbound event encoding and event types |
| `swift/BonsaiSwiftUI/Sources/WireFrame.swift` | Full/incremental output decoding and operation classification |
| `swift/BonsaiSwiftUI/Sources/ViewEnvironment.swift` | `RuntimeStatistics` attached to emitted frames |
| `ocaml/runtime/driver.ml` | Empty-frame suppression, statistics production, optional semantic trace |
| `ocaml/ffi/native_backend.ml` | App trace routing and native transaction contract |

Count each boundary payload once: input `events.count`/C `input_length` and output
`bs_output_buffer.length` are corresponding views of the same traffic. Do not add
them twice. Extra OCaml/C/Swift memory copies are a separate copy-volume metric.
Record config/startup separately and include error/rejection traffic when present.
The calls' scalar arguments/status/tokens are control overhead, not encoded UI
patch bytes. Report their calls even if buffer lengths are zero; document the
accounting convention if assigning them a byte estimate.

An empty output buffer still carries a presentation token. The current session
acknowledges it without committing another tree. Do not skip this acknowledgment
to make a benchmark faster, or treat its occurrence as a rendered frame. Preserve
queue serialization, monotonic clocks, buffer freeing and presentation fencing
when adding instrumentation.

`RuntimeStatistics` is useful but incomplete:

- `eventCount`, flush/read/reconcile/encode durations describe the producing
  frame's work. `lifecycleNanoseconds` reports the last completed lifecycle phase;
  do not attribute it to the current frame without checking its transaction.
- `patchBytes` is the entire encoded emitted frame length, including framing and
  statistics; `patchCount` includes the driver's UI, theme, host and application
  operations before the statistics operation. Neither is exclusively UI changes.
- `fullSnapshots` and `resyncs` are cumulative within a runtime. Take deltas within
  the same runtime/epoch; do not sum them across frames or silently bridge resets.
- No-output pumps have no statistics frame. Counting only these records misses
  idle calls, input traffic and native work.

The optional driver trace includes outbound byte counts and inbound event
summaries. It is diagnostic logging, not a complete low-overhead bidirectional
counter. Discover the current `App` trace configuration instead of inventing an
environment flag. Avoid serializing whole widget trees or logging each callback
in the FPS acceptance run.

If no complete counter exists, add benchmark-only in-memory counters at one
boundary in an isolated source copy. Count zero-byte calls and semantic event/op
classes. Batch export outside the timed region; use a bounded buffer with a
dropped-record counter. A run with lost records cannot certify traffic budgets.
Record native-call execution time on the native queue separately from waiting
time measured around the asynchronous Swift method.

Suggested raw records (an output format to implement, not an existing API):

```text
run, scenario, phase, sequence, monotonic_ns, runtime_id, epoch,
call_kind, input_bytes, output_bytes, event_counts_by_type,
presentation_id, revision, frame_kind, operation_counts_by_type,
changed_node_count, materialized_rows, materialized_nodes,
queue_wait_ns, native_call_ns, dropped_records
```

Preserve unavailable fields as null, not zero. Correlate cross-process/device
clocks using the profiler's timebase or explicit markers; do not subtract
unrelated timestamps. Sanity-check initial nonempty output, a known input event,
idle zero-output calls and complete acknowledgment pairs before trusting totals.

## Frame pacing and diagnostic traces

Use the target application's/window's presented-frame events from a supported
Instruments configuration. Check the installed templates and schemas first:

```sh
xcrun xctrace list templates
xcrun xctrace help record
# bench_pid is the verified target PID; select a template actually listed above.
xcrun xctrace record --template 'Animation Hitches' --attach "$bench_pid" \
  --time-limit 40s --output "$bench_dir/scroll.trace" --no-prompt
xcrun xctrace export --input "$bench_dir/scroll.trace" \
  --toc --output "$bench_dir/scroll-toc.xml"
```

The example capture leaves room for a marked 20-second continuous-motion region.
Use the recorded region, not the requested trace duration, as the denominator.
Wait for recording AND trace saving/postprocessing before exporting. Inspect the
TOC locally without dumping environment metadata; export only relevant tables.
Filter to the actual process/window: some render/hitch tables cover other apps.
Schema names and process association differ across Instruments versions. If the
trace cannot establish app-specific presentations, frame acceptance is unmeasured;
retain any valid hitch or CPU evidence with its narrower interpretation.

For a marked continuous-motion interval of duration T, report presented frames/T
and successive presentation intervals. Exclude idle/setup using explicit phase
markers, not by deleting long gaps: a stall during expected motion remains in the
denominator. Do not infer frame counts by dividing one second by average SwiftUI
transaction duration or by counting display-link callbacks. When provided, prefer
the instrument's missed-deadline and hitch metrics, documenting their definitions.

Use a separate `SwiftUI` trace to locate update fan-out, expensive bodies,
preferences and layout work. Begin with a short diagnostic capture: its tables
and postprocessing can be very large. Export selected groups before full update
tables. Transaction durations may overlap and are not per-frame presentation
intervals. Accessibility automation itself may create expensive graph updates.

Use a separate CPU sample when needed:

```sh
sample "$bench_pid" 10 1 -file "$bench_dir/scroll.sample.txt"
```

Inclusive stack counts overlap, and `sample` includes waiting stacks. Label
sampling fractions accurately; they are not CPU percentages or FPS. Compare
instrumented and counter-disabled optimized runs before trusting timing. If
measurement overhead could change a pass/fail result, use lighter instrumentation
and mark the timing verdict inconclusive until it is resolved.

Apple references for tool interpretation:

- [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)
- [Explore UI animation hitches and the render loop](https://developer.apple.com/videos/play/tech-talks/10855/)
