# OCaml Patch Size and 60 Hz Frame Budget

Historical Flutter measurements: the referenced renderer and commands have
been removed. These numbers do not establish SwiftUI frame or memory budgets.
New measurements must use the current native App and runtime benchmarks.

Recorded on 2026-08-21. These measurements define one reproducible workload;
they are not a content-independent wire-size limit.

## Result

On the tested iPhone 13, an incremental patch of **33,803 bytes** reliably
exceeded the 16 ms frame budget for this visible-node creation workload. That
patch contained 406 operations and made 372 nodes dirty while inserting 368
keyed `Text` nodes. All 30 samples across the ascending and descending boundary
runs exceeded 16 ms.

The transition began below that point but was sensitive to device state:

- 32,363-byte patches crossed the budget in 4 of 10 descending samples and 16
  of 20 samples in a sustained ascending run.
- 33,083-byte patches crossed the budget in 9 of 10 descending samples and 16
  of 20 samples in a sustained ascending run.
- 33,803-byte patches crossed the budget in every sample in both runs.

For this workload, treat approximately **32–34 KiB** as the onset region and
**33.8 KiB** as the first observed consistently over-budget size. Applications
that need headroom should split or virtualize the work before 30 KiB rather
than using 33.8 KiB as a permissible maximum.

## Environment

- Device: physical iPhone 13 (`iPhone14,5`)
- OS: iOS 26.6.1
- Display target: 60 Hz
- Flutter: 3.44.8 stable, revision `058e0af2c2`
- Dart: 3.12.2
- Flutter build mode: Profile
- OCaml mode: iPhoneOS Profile native complete object
- Warm-up: two expansion/collapse cycles per size
- Boundary samples: ten samples per size in the reverse confirmation run

The frame-budget value is `max(buildDuration, rasterDuration)`. Flutter runs
the UI and raster stages as a pipeline, so summing those durations would not
represent the 60 Hz throughput condition. The integration driver records the
100th-percentile stage time within each expansion action, then the table below
summarizes those action samples.

## Reverse boundary confirmation

| Visible text nodes | Patch bytes | Operations | Median max stage | p90 max stage | Over 16 ms |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 320 | 29,483 | 358 | 14.183 ms | 16.392 ms | 2 / 10 |
| 352 | 32,363 | 390 | 15.800 ms | 18.641 ms | 4 / 10 |
| 360 | 33,083 | 398 | 16.870 ms | 18.843 ms | 9 / 10 |
| 368 | 33,803 | 406 | 18.529 ms | 20.127 ms | 10 / 10 |

At 33,803 bytes, the p90 decode and `NodeStore` apply times were each 0.122 ms,
while the p90 Flutter build time was 20.127 ms and raster time was 0.361 ms.
The budget failure was therefore dominated by materializing and laying out the
visible Flutter widget tree, not by wire decoding or the transactional store.

## Workload

The Profile fixture starts with a scroll viewport containing size-selection
buttons. An OCaml button event replaces that baseline with a column containing
one control and `N` keyed `Text` nodes. OCaml reconciliation emits a real
incremental frame, the runtime isolate transfers it through the native bridge,
and `BonsaiFlutterRoot` decodes, commits, builds, and presents it. Each sample
collapses back to the baseline before the next expansion.

The displayed text payload is:

```text
Patch item 000000: OCaml to Flutter visible text payload
```

All scroll positioning occurs outside the measured action. Each action-scoped
Flutter timeline remains open for two additional vsync pumps so both build and
raster events are complete before the driver summarizes it.

## Interpretation

Patch byte size is only a proxy for work. A similarly sized patch that updates
one property, carries an application payload, changes offscreen virtual nodes,
or creates complex custom widgets will have a different threshold. Operation
count, dirty visible-node count, layout shape, device, refresh rate, build mode,
and thermal state all matter.

The protocol's 16 MiB maximum frame size remains a safety bound and must not be
interpreted as a performance budget. For production guardrails, record at
least `patchBytes`, patch count, dirty visible nodes, build time, and raster
time, and define separate limits for representative patch shapes.

## Reproduction

From `flutter/integration_test`, first stage the current iPhoneOS object:

```sh
BONSAI_FLUTTER="$(opam var bin)/bonsai-flutter"
"$BONSAI_FLUTTER" build-native --target=iphoneos --profile=profile
```

Then run the reverse boundary sweep on the physical device:

```sh
"$BONSAI_FLUTTER" exec --profile=profile -- \
  flutter drive --profile --no-dds \
  -d 00008110-000A71C414BB801E \
  --dart-define=BONSAI_PATCH_SIZE_COUNTS=368,360,352,320 \
  --dart-define=BONSAI_PATCH_SIZE_WARMUPS=2 \
  --dart-define=BONSAI_PATCH_SIZE_SAMPLES=10 \
  --target integration_test/patch_size_profile_test.dart \
  --driver test_driver/patch_size_profile_test.dart \
  --timeout 600
```

The driver writes `build/patch_size_profile_summary.json`.
