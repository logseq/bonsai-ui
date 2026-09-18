# SwiftUI Dependency Preflight Performance

## Problem

Repeated `bonsai-swiftui build` and `run` commands pay for dependency validation
before reaching the application's incremental OCaml and Xcode builds. The user
reported an Amplify dependency closure containing `aws-sdk-swift` and a temporary
dependency directory of approximately 3 GB. That size is a user observation, not
a measurement reproduced for this document. Completed measurements are recorded
in the acceptance report below.

The baseline source at commit `ca0805fb69db6faedec9d4b959bbb48833f24b51`
establishes the original mechanism (the linked files now contain the replacement):

| Location | Baseline behavior | Cost or constraint |
| --- | --- | --- |
| [`build_system.ml`](../../../../bonsai_swiftui_tool/lib/build_system.ml), `build_apple` / `run_apple` | Calls `Host.Locked` before native selection and before acquiring `apple.lock`; run delegates to build | Every application build/run enters preflight, regardless of existing application artifacts |
| [`host.ml`](../../../../bonsai_swiftui_tool/lib/host.ml), `sync` | Passes `--locked-preflight` without a selected platform or profile | Preflight cannot follow the requested build scope |
| [`swiftui_xcode_host.py`](../../../../tool/swiftui_xcode_host.py), `resolve_packages` | Creates `TemporaryDirectory(prefix="bonsai-package-resolution-")`; puts host, package checkouts, and DerivedData inside it | Successful preflight outputs disappear after each invocation |
| Same function | Supplies `-disablePackageRepositoryCache` and a fresh `-clonedSourcePackagesDirPath` | Explicitly disables repository-cache reuse; repeated transfer cost depends on Xcode and external caches, but this pipeline retains no checkout cache |
| Same function | For both `PLATFORMS`, invokes resolution and then an unsigned Debug probe build | An iOS Release request still runs macOS Debug and iOS Debug dependency validation first: four preflight `xcodebuild` invocations |
| [`plan.ml`](../../../../bonsai_swiftui_tool/lib/plan.ml), `apple_build` | Builds the requested configuration using `<apple_root>/DerivedData` | The real application build already has a persistent build directory separate from the discarded probe directory |

Applications without remote Swift packages take an early exit and do not execute
these remote-package probes. The probe links selected remote products without
the application's OCaml complete object. Its cost should not be attributed to
application OCaml compilation.

The [implemented host-configuration decision](../../implemented/feature/2026-09-16-swiftui-cli-application-host-configuration.md)
requires remote semantic validation before publishing generated host output or
staging native objects. It also requires one application-owned lock shared by
the two platform graphs. These guarantees explain why the probe exists; removing
it is a behavior decision, not just a cache optimization.

## Decision

The user confirmed all three design choices on 2026-09-18: retain and cache
dependency preflight, validate only the requested platform/profile on a miss,
and store disposable state within the project. Reuse successful validation and
persistent package/build state. Ordinary
build/run validates only the selected platform and profile on a cache miss.
Explicit `resolve-packages` retains both-platform validation before publishing
the shared lock. There is no new user-facing skip-validation switch.

### Command behavior

| Operation | Agreed behavior |
| --- | --- |
| `sync-host` / `sync-host --check` | Remain offline; never populate, touch, or require the dependency cache |
| `resolve-packages` | Resolve both platform graphs, build both Debug probes, compare pins, and publish the lock/host only after all checks pass; reuse downloads and incremental probe outputs, but always run explicit validation |
| `build ios --profile release` | Validate all local configuration and lock inputs; reuse a matching iOS Release validation record, or run only the iOS Release probe; then perform the real locked application build |
| Other build/run selections | Apply the same rule to the selected platform/profile; run does not introduce another validation pass |
| No remote packages | Preserve the existing local-only path; create no dependency cache |

Every build still validates local input structure, ownership, entitlement files,
and the application-owned lock before trusting a cached result. A lock merely
matching direct pins is insufficient evidence that the transitive graph is
complete: only a successful Xcode validation can create a reusable record.
The actual application build continues to enforce the locked versions and
revisions with the existing locked-resolution flags.

The selected-platform policy deliberately changes the prior build/run guarantee:
an iOS build no longer certifies current macOS compilation. Structural errors in
any platform's configuration still fail early. Both-platform dependency graph
agreement remains the responsibility of explicit resolution; switching platform
or profile triggers that selection's first validation. Debug resolution does not
certify Release or Profile compilation.

### Persistent state and validation identity

Use a disposable, project-owned cache under
`_build/bonsai-swiftui/dependencies/`. Keep the application-owned
`swift-packages/Package.resolved` as the source of truth. The implemented layout is:

```text
dependencies/
  packages/                         # Shared within this project, serialized access
  probes/<platform>/<profile>/      # Stable generated probe and DerivedData paths
  validation/<platform>/<profile>.json
```

Keep stable probe paths across input changes so Xcode can apply its own
incremental invalidation. Do not create another multi-gigabyte workspace per
fingerprint. A validation record is small metadata, not a second copy of package
sources. The implementation removes `-disablePackageRepositoryCache` and passes
the same project-local checkout root to preflight and the real application
build; keep their DerivedData separate. Do not assume that sharing checkouts
allows probe object files to be reused by the application's different project.
Real Xcode 26.1.1 tests and the Amplify consumer measurements confirm checkout
sharing. There is no alternate checkout layout.

A successful validation record must identify at least:

- A cache format/validation algorithm version and the effective probe generator.
- Canonical package declarations, URLs, requirements, selected products and their
  platform assignments, plus the full application-owned lock content digest.
- Platform, configuration, destination kind, architecture, deployment target,
  and effective probe build settings and generated input contents.
- Selected developer directory, Xcode build version, Swift compiler identity,
  and selected SDK identity/version. Toolchain changes invalidate validation.
- Application/framework locations and the local package manifests or other
  local inputs consulted by resolution/probe generation. Content changes must
  invalidate affected validation; an installed CLI version alone is insufficient
  for a mutable framework checkout.

Derive this identity from the effective probe inputs rather than a manually
maintained subset that can drift from generation. Entitlement or generator
changes that affect the probe invalidate it. Changes confined to application
OCaml/Swift source or resources do not invalidate dependency validation, because
the isolated probe does not compile those inputs; the actual application build
must still observe them. Do not hash the full downloaded dependency trees on
every invocation. Persisted validation is a local incremental-build optimization,
not an attestation against manual cache tampering.

On a hit, run no dependency resolver or probe-build subprocess. On a miss,
reuse stable checkouts/DerivedData, run the selected locked probe, verify that
the complete pin set is unchanged, and atomically write a success record only
after success. Malformed records, missing required cache state, interrupted
validation, and inconsistent inputs cause a miss. Never cache failure as success
or silently rerun unlocked resolution. Recheck inputs before publishing success
if they may have changed during validation.

Xcode can reuse a previous workspace graph without rewriting an incomplete
`Package.resolved`. On a miss, discard only `packages/workspace-state.json`
before resolution, retaining repositories, checkouts, artifacts, and DerivedData.
After Xcode succeeds, compare its actual remote checkout identities, normalized
URLs, versions, branches, and revisions with the complete lock pin set. Ignore
local filesystem framework references in this remote comparison. Unknown or
malformed resolver state fails validation; it must not create a success record.
The real remote-package CLI regression exposed this case during implementation.

Explicit resolution may seed successful Debug records for both platforms using
the final published lock. It cannot seed Release/Profile records. Pin or product
changes invalidate every affected selection's record, including ones left from
an earlier successful resolution.

### Mutation, concurrency, and cleanup

Local invalid inputs must fail before creating cache state. A remote validation
failure may leave reusable cache files and diagnostics, but must preserve the
application lock, generated host, and native staging outputs. This narrows the
old whole-project no-mutation assertion to exclude documented disposable cache
state; update the corresponding acceptance tests explicitly. `sync-host --check`
keeps its stronger read-only guarantee, including cache paths.

Serialize every writer of the shared project checkout/probe state, including
explicit resolution, preflight, actual application builds, and cleanup. The
baseline preflight occurred outside `apple.lock`. The implementation instead
uses `_build/.bonsai-swiftui-apple.lock` around the complete Apple build, explicit
resolution, and cleanup. Use one documented
lock order, acquire the dependency/build guard before generating probe outputs,
and recheck cache identity after acquiring it. Keep the guard outside any tree
that `clean` removes so cleanup cannot unlink an active lock and permit a second
writer. Do not share writable checkouts between independent projects.

Extend existing `clean` semantics: platform cleanup removes that platform's
probe outputs and validation records while retaining shared downloads; full
cleanup removes all project dependency state. Never delete the global SwiftPM
repository cache or application-owned lock. Preserve existing symlink ownership
checks. Bound storage by the supported platform/profile slots rather than an
unbounded list of historic fingerprints.

### Observability and implementation boundary

Report separate elapsed times for local validation, dependency cache lookup,
package resolution/fetching, probe build, native compilation/staging, and actual
Xcode build. Report cache hit/miss with the changed input category and the
selected platform/profile. Preserve useful failure logs; diagnostics must not
imply that a cache hit guarantees a network-free application build.

The changed implementation areas are `host.ml`, `build_system.ml`, `plan.ml`,
`clean.ml`, the existing lock helper, `swiftui_xcode_host.py`, existing CLI/host
tests, and `docs/swiftui-cli.md`. Remove the old unconditional disposable
build/run preflight path once its replacement is verified. No compatibility
mode, custom dependency solver, configuration migration, protected OCaml spec
edit, or Dune edit is included. The implementation and performance checks are
complete. No runtime/iOS SDK change, commit, or push is included.

## Alternatives considered

### Remove build/run probes and rely on the actual application build

Run cheap local lock checks and let the selected application build resolve and
compile locked dependencies. Keep exhaustive validation in `resolve-packages`.
This is the simplest pipeline and avoids duplicate dependency compilation even
on a cold selected configuration. It would discover remote
product/platform/closure failures after generated host or native staging updates.
The user selected cached preflight to retain the failure-before-publication
contract instead.

### Persist downloads and DerivedData but run both probes every time

This removes repeated downloads and many compiler tasks with a smaller behavior
change. It retains four preflight Xcode invocations and unrelated platform work
on the warm path. It does not satisfy the agreed warm-path acceptance gate.

### Cache both-platform validation as one result

This more closely preserves the old cross-platform guarantee. Every miss still
makes an iOS Release build wait for macOS validation. The user selected validation
of only the requested platform/profile for build/run misses. Configuration
coverage remains explicit; a pair of Debug probes is not Release validation.

### Share writable dependency state across projects

A user-wide cache could reduce duplicate checkouts across consumers, but requires
cross-project ownership, locking, toolchain isolation, and eviction policies.
The user selected project-local disposable state and existing clean integration.
Xcode's repository cache may still be enabled; the CLI does not manage a shared
writable project checkout or probe workspace.

### Trust only the lock, or add a skip-preflight flag

The local lock parser does not prove exported products, platform support, or
complete transitive solver compatibility. A permanent bypass flag also leaves
the expensive default unchanged and creates two behavior paths. Neither is
recommended as the performance fix.

## Acceptance criteria

These gates define acceptance; the validation section links the completed evidence.

- The implementation is accepted only when both the warm-path performance
  gates and the lock/publication correctness gates below pass.

1. For an unchanged warm selection, preflight invokes zero resolver/probe
   `xcodebuild` processes. The actual application build still runs. An iOS
   Release miss invokes no macOS or Debug probe; explicit resolution still
   validates both platform graphs.
2. A missing, stale, or malformed lock fails before source/host/native mutation.
   An incomplete transitive lock, missing product, unavailable revision, and
   unsupported selected platform fail without updating those outputs or writing
   a success record. Compare full pin sets after validation; never change the
   application lock from build/run.
3. Exercise invalidation for lock revisions, product selections, toolchain/SDK,
   deployment target, configuration, generator, and relevant local manifests.
   Application-only source edits retain dependency hits but rebuild affected
   application outputs. Repeat tests after relocating the project/framework.
4. Concurrent build/build, build/resolve, and build/clean operations serialize
   cache access without accepting partial records or mutating each other's
   checkouts. Kill a validation process and verify safe retry. Corrupt/delete
   cache metadata and verify a miss, without unlocked resolution.
5. With the required package sources and artifacts populated, demonstrate an
   offline repeat on the supported Xcode. With an empty cache offline, report
   unavailable inputs rather than claiming that a lock guarantees offline use.
6. Platform/full clean remove only their specified disposable state. Offline
   host checks preserve paths, bytes, and mtimes, including cache state. Existing
   failure snapshots distinguish cache writes from protected application outputs.
7. Benchmark a representative Amplify / `aws-sdk-swift` consumer using identical
   source, pins, destination, profile, and toolchain before/after the change.
   Record hardware, Xcode/Swift/SDK versions, network conditions, command lines,
   and cache state. Cover a fresh project cache, a warm repeat, an OCaml-only
   edit, a Swift-only edit, a lock change, and a platform/profile switch. Separate
   a fresh project cache from a genuinely cold repository cache without deleting
   the user's global caches. Use at least five warm repetitions and report median
   and range, phase timings, preflight invocation count, fetch activity, and
   package/DerivedData disk usage.
8. Target at least a 90% reduction in warm dependency-preflight median time on
   that consumer relative to the current implementation, with zero repeated
   dependency fetch/compile activity attributable to a preflight hit. Report cold
   cost and total build time separately; do not promise a total-build percentage
   before measurement. Repeated identical runs must not create another checkout
   tree or accumulate another multi-gigabyte validation workspace.

Use focused command-planning/cache tests plus real Xcode acceptance. Existing
entrypoints include `python3 tool/test_swiftui_xcode_host.py`,
`python3 tool/test_swiftui_cli.py`, and the existing OCaml tool/native-plan test
executables. Mocked command counts do not establish actual package-cache reuse.
Use an unsigned iOS build for build-performance measurement; signed deployment
and application startup are separate costs.

## Validation

The [acceptance report](../../../test-reports/2026-09-18-dependency-preflight-performance/README.md)
records the installed CLI measurements on `logseq_journal`, original baseline,
phase timings, input hashes, cache footprint, and compressed test/build logs.
It distinguishes a fresh project dependency cache from globally cold sources,
and reports five final-version warm builds rather than extrapolating from a
single hit. The warm path invokes zero dependency resolver/probe builds.

Real Xcode coverage includes selected-platform/configuration validation,
explicit both-platform resolution, transitive lock completeness, failing remote
products/revisions/platforms, invalidation, concurrent writers, interrupted
validation, cleanup, and offline cache behavior. A no-remote-package regression
also verifies that a native failure cannot publish a previously absent host.
The report records which source version each test and measurement exercised.

## Consequences

Normal application edits retain cached dependency validation. A changed lock,
probe input, selection, or toolchain triggers validation for that selection.
`resolve-packages` remains the explicit both-platform check. Failures still
preserve application-owned pins, host outputs, and native staging.

Persistent dependency state occupies disk until cleanup; repeated hits do not
create new checkout trees. Misses can still incur substantial recompilation,
including after a lock formatting change. The optimization removes repeated
warm preflight work and does not eliminate cold dependency compilation.

## Risks

- An incomplete fingerprint could accept stale semantic validation. Version the
  format and test effective inputs; retain the actual locked application build.
- Persistent caches consume disk and require cleanup. Sharing checkouts with the
  application must be established with real Xcode evidence, not assumed from
  the existence of command-line flags.
- Recreating Xcode resolver bookkeeping on a miss can restage existing checkouts
  and trigger broad probe/application recompilation, even for a lock formatting
  change. Retaining directories does not guarantee Xcode will reuse every object.
  This cost is measured explicitly; unchanged validation hits avoid it entirely.
- The first selected-profile validation still compiles dependencies separately
  from the application. This change primarily removes repeated preflight cost;
  it does not eliminate every cold-build duplication.
- Skipping validation on a hit no longer checks current remote availability.
  Local reusable sources may make remote availability irrelevant to that build;
  actual missing-input failures must still be reported honestly.
- Selected-platform validation weakens automatic cross-platform coverage.
  Explicit resolution and CI must retain the agreed broader coverage.
- Shared-cache locking can serialize otherwise parallel platform builds. Measure
  this trade-off before considering a more complex concurrency model.
- The current per-subprocess timeout is 300 seconds. Large cold dependency
  builds may still exceed it; retain timing/failure evidence and decide timeout
  changes from measurements rather than treating a larger timeout as a speed fix.

## Questions

- None. The user confirmed all recommended choices on 2026-09-18:
  retain cached preflight before host/native publication; validate only the
  requested platform/profile on build/run misses while explicit resolution
  validates both platforms in Debug; use project-local disposable state with
  platform/full clean integration. Real Xcode checkout-sharing verification and
  performance measurements are complete; see the acceptance report.
