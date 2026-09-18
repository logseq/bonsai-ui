# Upstream baseline

The SwiftUI migration uses fixed OCaml dependency versions and the native Apple
toolchain. The measured host on 2026-09-14 is macOS 26.6.2 (25G83), arm64,
with Xcode 26.1.1 and Swift 6.2.1. These are recorded build inputs; this document
does not assert that an untested toolchain release is compatible.

| Component | Measured version | Notes |
| --- | --- | --- |
| OCaml | 5.1.1 | Host and physical-iOS compiler baseline |
| Xcode | 26.1.1 | Selected Apple SDKs and build system |
| Swift | 6.2.1 | SwiftUI renderer and application hosts |
| macOS target | arm64, macOS 26.0 | Native Swift package and complete objects |
| iOS target | arm64, iOS 26.0 | Physical iPhone/iPad only |

## Jane Street release line

All installed Jane Street release-train packages use `v0.17.x`. Direct
runtime dependencies resolve to:

| Package | Version |
| --- | --- |
| Bonsai | v0.17.0 |
| Incremental | v0.17.0 |
| Incr_dom | v0.17.0 |
| Virtual_dom | v0.17.0 |
| Core | v0.17.2 |
| Base | v0.17.3 |

The patch releases for Core and Base are part of the `v0.17` release line.
Manifests constrain every direct Jane Street dependency to versions greater
than or equal to `v0.17` and strictly below `v0.18`.

The default opam repository supplies immutable release-tag archives. CI does
not use the Jane Street bleeding repositories and does not pin local Bonsai,
Incremental, or Incr_dom source trees.

## Compiler and runtime selection

OCaml 5.1.1 is pinned in the compiler and package configuration. Bonsai v0.17
uses its continuation API through `Bonsai.Cont`; applications return `View.t`.
Runtime scheduling uses the public `Bonsai_driver` and `Bonsai.Time_source`
surfaces. Before-display callbacks drain to a fixed point during logical frame
flush; after-display work waits for the matching native presentation token.

The native package exposes `bs_*` ABI 4.0 and exact BSFR 5.0 framing. Swift
validates and presents updates; OCaml retains the canonical application state.
Input fixtures are produced by the production Swift encoder and decoded and
re-encoded by OCaml. See [input fixtures](swiftui-input-fixtures.md).

## Physical-iOS cross-build baseline

The isolated compiler and dependency closure use the locked opam-cross-ios
source revision, the repository-owned OCaml 5.1.1 recipe and an actual iOS 26
runtime rebuild. The compiler wrapper supplies arm64, the iPhoneOS sysroot and
minimum-version flags to C stubs as well as OCaml complete objects. Host PPX
executables remain macOS processes. Simulator, Intel and Catalyst are excluded.

Closure membership and package counts are derived from the checked-in locks.
Supported Dune and Topkg pure OCaml packages compile generically; platform
capabilities require explicit iPhoneOS recipes. Static GMP, system SQLite,
Apple entropy and exact TLS dependency checks remain part of the closure audit.
See [iOS toolchain evidence](swiftui-ios-toolchain.md) for reproducible commands.

## Verification boundary

Ten standalone SwiftUI examples have macOS and signed physical-iOS build
checkpoints. Gallery remains unfinished. Mail has actual macOS interaction
captures, an iPhone Inbox capture and a passing physical-device runtime XCTest.
Build-for-testing does not prove UI execution. New source/SDK publication,
remaining UI acceptance and full CI migration are still required; see the
[implementation ledger](swiftui-implementation.md).
