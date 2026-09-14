# Benchmark Baseline

Historical Flutter measurements: the referenced renderer and commands have
been removed. These numbers do not establish SwiftUI frame or memory budgets.
New measurements must use the current native App and runtime benchmarks.

Recorded on 2026-07-26. These numbers are an engineering baseline, not a
cross-machine performance guarantee.

## Environment

- Machine: Apple Mac Studio, Apple M4 Max, 64 GiB RAM, arm64
- OS: macOS / Darwin 25.5.0
- OCaml: 5.1.1
- Dune: 3.23.1
- Flutter: 3.44.8 stable, revision `058e0af2c2`
- Dart: 3.12.2
- OCaml mode: Dune `release`
- Dart renderer mode: `flutter test` debug/JIT
- Integration mode: `flutter test` debug with the macOS arm64 package_ffi
  native asset and embedded OCaml complete object

## Commands

```sh
dune exec --profile release ocaml/bench/runtime_bench.exe

cd flutter/packages/bonsai_flutter
flutter test benchmark/runtime_bench_test.dart --reporter expanded

cd ../../..
make integration-native-object

cd flutter/integration_test
flutter test benchmark/runtime_benchmark_test.dart --reporter expanded
```

## OCaml

| Scenario | Baseline |
| --- | ---: |
| Unchanged 1,000-node tree, physical equality | 70.03 us/op |
| One property changed | 0.20 us/op |
| 1,000 siblings, full snapshot | 413.41 us/op |
| 10,000 siblings, full snapshot | 4,597.62 us/op |
| Insert at front, 1,000 keyed siblings | 814.75 us/op |
| Delete middle, 1,000 keyed siblings | 818.54 us/op |
| Reverse 1,000 keyed siblings | 473.74 us/op |
| Reverse 10,000 keyed siblings | 5,276.11 us/op |
| Handler-only change | 0.34 us/op |
| Encode 1,000-node full snapshot | 78.87 us/op |
| Decode 1,000-node full snapshot | 84.41 us/op |
| Encode one-property incremental frame | 0.22 us/op |
| Decode one-property incremental frame | 0.24 us/op |

The 1,000-to-10,000 keyed reverse measurements scale approximately linearly
and are used to guard against accidental quadratic reconciliation.

## Dart renderer

| Scenario | Baseline |
| --- | ---: |
| Decode 1,000-node frame | 241.43 us/op |
| NodeStore 1,000-node full transaction | 235.65 us/op |
| One dirty node | 112.32 us/op |
| 100 dirty nodes | 125.01 us/op |
| Reorder 1,000 child IDs | 113.25 us/op |
| Text controller retention | 3.28 us/op |
| Resource create/dispose through resync | 4.24 us/op |
| Batch 1,000 ordered events | 94.16 us/op |
| Materialize 64 KiB isolate transfer | 2.29 us/op |

## Integration

| Scenario | Baseline |
| --- | ---: |
| Flutter click to OCaml frame presented | 15,645 us |
| Full resync through FFI and presentation | 13,131 us |
| Pump 1,000 visible widgets | 152,516 us |
| Pump 10,000 logical virtual-list nodes with a 20-node window | 38,461 us |
| Window resize pump | 9,633 us |
| Form a 100-edit rapid-typing batch | 2,409 us |

Integration timings include the Flutter test binding and therefore have more
variance than the codec and reconciler microbenchmarks. Track regressions by
repeating the same command on the same machine and comparing medians.
