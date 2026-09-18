# SwiftUI dependency preflight performance acceptance

Status: passed. The installed CLI implements project-local cached preflight,
validates only the selected platform/profile on a miss, and shares persistent
package checkouts with the actual application build. Explicit resolution still
validates both Debug platform graphs before publishing the shared lock.

## Measured result

The unchanged `logseq_journal` iOS Release build decreased from **473.141 seconds**
(one original baseline) to a final-version warm median of
**16.104 seconds**, a **96.60% reduction**.
Five final installed CLI repetitions ranged from
14.977 to 16.168 seconds.
The separately instrumented original preflight took **458.754 seconds**;
final warm preflight median was **0.145 seconds**
(range 0.143–0.155),
a 99.968% reduction. A hit invokes **zero dependency
resolver or probe-build subprocesses**. Toolchain identity checks and the actual
locked application build still run.

| Scenario | Complete build (s) | Preflight (s) | Cache |
| --- | ---: | ---: | --- |
| Fresh project dependency cache | 186.334 | 116.508 | miss |
| OCaml-only edit | 19.107 | 0.314 | hit |
| Swift-only edit | 18.749 | 0.297 | hit |
| Lock whitespace edit | 210.446 | 143.736 | miss |
| Restore original lock bytes | 207.726 | 143.962 | miss |
| Switch to macOS Debug | 121.021 | 81.389 | miss |
| Return to iOS Release after switch | 64.699 | 0.162 | hit |
| Final generator: first validation | 197.833 | 134.672 | miss |

The fresh project cache result retains existing global repository caches and
application DerivedData. It is not a globally cold machine measurement. The
186.334-second fresh-cache build includes 35.620 seconds of resolution/fetch and
80.433 seconds of probe compilation. Original preflight made four Xcode calls:
macOS resolution 292.051 seconds, macOS Debug build 75.437 seconds, iOS resolution
27.816 seconds, and iOS Debug build 57.623 seconds.

A miss recreates resolver bookkeeping to detect incomplete transitive locks.
Xcode can then restage cached checkouts and rebuild substantial probe/application
code. The lock whitespace change demonstrates this cost without changing pins.
The 64.699-second return from macOS to iOS is retained as transition evidence;
it is not included in the steady-state median. Ordinary OCaml/Swift source edits
remain dependency hits. Measurements do not claim that retaining DerivedData
eliminates every compilation after an invalidation.

## Setup and version boundaries

Consumer: `/Users/rcmerci/gh-repos/logseq_journal`, Amplify 2.61.0 with its locked
`aws-sdk-swift` closure. Command:

```sh
bonsai-swiftui build ios --profile release --no-codesign
```

Installed runs use the normal opam CLI without `BONSAI_SWIFTUI_SOURCE_ROOT`.
The original source-tree CLI used baseline commit
`ca0805fb69db6faedec9d4b959bbb48833f24b51`. The separately instrumented old
preflight loaded that commit's original generator. Hardware: Mac Studio M4 Max,
16 CPU cores, 64 GB memory. Xcode 26.1.1 (17B100), Apple Swift 6.2.1, iOS/macOS
SDK 26.1. See [environment.json](environment.json) for input hashes and cache/network
conditions; [results.json](results.json) contains commands, individual samples,
phase timings, disk usage, and generator hashes.

Earlier remote-package matrix and the 18 cache tests used generator SHA-256
`1d1c9effc48fda8cbdbdf4b1357c3cbb25196f766862d2cbe57362428b48b884`. A final one-line correction in the
**no-remote-packages branch** restored read-only locked preflight before native
selection (`generate_project(**options, validate_only=locked)`). The remote path
was unchanged. Its dedicated regression first failed and then passed; three
focused local CLI tests passed after the correction. The final installed prime
and five warm samples use the final generator SHA-256:
`b28034744863a3128ea27e90c3ad1a834cdac46b906de47a0d61c8e6b10a24ea`. The installed helper was compared with the working tree.
These versions are recorded separately rather than relabeling older measurements.

The consumer's existing dirty source was preserved. Temporary source comments
and lock whitespace changes were restored byte-for-byte with original mtimes;
all tracked benchmark input hashes match the baseline. No package version or
application implementation was changed to improve the result.

There is one complete-build baseline and one instrumented old-preflight baseline,
not five baseline repetitions. Some earlier validation ran concurrently on this
machine; network throughput was not controlled. These numbers describe this
machine and cache state, rather than a universal speed guarantee. Real Xcode
command traces establish the structural zero-probe warm behavior independently.

## Correctness evidence

| Requirement | Completed evidence |
| --- | --- |
| OCaml build and native plans | `dune build @all`, `dune runtest`, 51 tool tests, four native-plan tests |
| Local validation and read-only ownership | Four host-configuration tests, two ownership tests; final local failure regression plus three focused CLI checks |
| Selected platform/profile; explicit both-platform resolution | 18 real Git-package/Xcode cache tests: aggregate of 17 plus one added transitive-lock regression |
| Invalidation | Lock, products, configuration/platform, toolchain/deployment, generator, framework manifests, relocated application/framework |
| Interrupted/corrupt state | Interrupted validation, missing/corrupt records/outputs, safe retry; failure cannot seed success |
| Concurrency and cleanup | Build/build, build/resolve, build/clean serialization; cleanup keeps the guard inode; symlink safety |
| Invalid remote graph | Real revision/product/platform failures and incomplete transitive lock preserve protected application outputs |
| Offline behavior | Warm preflight and empty-cache failure under network denial; real cached remote-package application builds offline |
| Installed CLI application | Installed-layout CLI builds and executes real OCaml |
| Journal performance | Fresh project cache, five final warm samples, source edits, lock-input changes, platform/profile switch |

The aggregate cache suite took 1592.701 seconds, the added transitive test
193.636 seconds, and the complete real remote CLI regression 800.177 seconds.
The remote CLI regression includes actual package execution across macOS
profiles and an offline complete build with cached remote packages.
The Makefile integration-test target includes the new cache suite. Python syntax,
OCaml formatting, and whitespace checks also passed.

A Journal network-denied complete-build attempt hit preflight but failed when
AWS build-tool plugins tried to create a nested sandbox
(`sandbox_apply: Operation not permitted`). This is a harness limitation;
it does **not** establish a successful offline Journal build. Offline application
acceptance uses a remote-package fixture without nested build-tool sandboxes.
No system network settings were changed.

## Storage and reproduction

The final layout contains 30 checkout directories, iOS Release and macOS Debug
probe slots, and two validation records. Project dependency state occupies about
6.7 GiB; application DerivedData about 10.7 GiB at the final inspection.
Per-run disk readings are in `results.json`. Repeated hits reuse the same trees;
no new fingerprint workspace is created. A discarded temporary old-cache backup
was removed. Platform cleanup removes only that platform's probes/records;
full cleanup removes project dependency state. Both preserve application pins
and the global repository cache.

Compressed logs in [logs/](logs/) retain the benchmark, installation, baseline,
red/green regression, and successful test evidence. Measurement drivers are
[measure.py](measure.py), [installed-scenarios-resume.py](installed-scenarios-resume.py),
and [baseline-preflight.py](baseline-preflight.py). Their absolute paths describe
this run; adapt paths before reusing them. Import `measure.measure` with a new
label to collect repetitions; do not overwrite the archived evidence. To rerun
the instrumented baseline, reconstruct `baseline_host.py` from the recorded
commit with `git show <commit>:tool/swiftui_xcode_host.py` in the driver's output
directory. Scenario edits must run without concurrent user edits.

The [implemented decision](../../agent-guide/implemented/architecture/2026-09-18-swiftui-dependency-preflight-performance.md)
records invalidation, publication, and cleanup contracts. No Dune or protected
OCaml spec files changed. No commit, push, or generated iOS SDK update is included.
