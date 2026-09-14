# Add `ppx_deriving_yojson` 3.9.1 To The iOS SDK

## Problem

An external `bonsai_flutter` application now depends on
`ppx_deriving_yojson` 3.9.1 and uses `[@@deriving yojson]`. Native macOS builds
can resolve that package from the application's host opam switch, but iPhoneOS
builds use the immutable `bonsai-flutter-ios` SDK package universe. A consumer
may use only packages and Findlib components present in the checked-in
supported SDK closure.

The current supported closure contains compatible prerequisites, including
`yojson` 3.0.0, `ppxlib` 0.35.0, `ppx_derivers` 1.2.1, and `cppo` 1.8.0, but it
does not contain `ppx_deriving_yojson` or `ppx_deriving`. The installed host
switch currently resolves `ppx_deriving_yojson` 3.9.1 with `ppx_deriving`
6.0.3; both accept the SDK's OCaml 5.1.1 and `ppxlib` 0.35.0 versions.

This dependency crosses both sides of the iPhoneOS build boundary:

- the `ppx_deriving_yojson` driver and its compiler-facing dependencies must
  execute as native macOS host artifacts while Dune preprocesses application
  sources; and
- generated application code requires the target runtime components
  `ppx_deriving_yojson.runtime`, `ppx_deriving.runtime`, and `yojson` in the
  arm64 iPhoneOS closure.

Merely adding opam metadata for the host PPX would therefore leave the
generated native object without its target runtime closure. Conversely,
cross-compiling the complete PPX driver would put compiler tooling into the
application target and violate the existing host/target separation.

## Proposal

Add `ppx_deriving_yojson` 3.9.1 to the supported iPhoneOS SDK through the normal
application-closure resolver rather than by hand-editing generated package
rows.

Extend the repository-owned application closure fixture with the exact
`ppx_deriving_yojson` 3.9.1 dependency and a small type using
`[@@deriving yojson]`. Exercise both the generated encoder and decoder from a
fixture path that enters the iPhoneOS complete object. Configure that fixture
stanza with `(preprocess (pps ppx_deriving_yojson))` so the test covers Dune's
real cross-context PPX resolution instead of only proving that package metadata
exists.

Resolve the fixture again and regenerate the checked-in reference and
supported closures. The selected closure should classify only the generated
code's runtime components as arm64 iPhoneOS target artifacts while retaining
the PPX driver, compiler libraries, and other build-time dependencies as native
host artifacts or host metadata. Reuse the generic `Pure_ocaml` Dune recipe;
do not add a package-name allowlist or a `closure_capabilities.lock` entry
unless concrete build evidence demonstrates that the generic recipe is
insufficient.

Because the immutable dependency closure changes, advance both the runtime SDK
package version and the framework SDK package version that selects and
describes that runtime. Keep the Bonsai Flutter protocol ABI and SDK build
recipe revisions unchanged. Regenerate the committed local iOS opam
repository, replacing the old versioned SDK package paths rather than retaining
compatibility copies.

Add contract coverage for the exact dependency version, immutable source
checksum, selected host/target roles, target runtime components, SDK package
version increments, and absence of obsolete generated SDK package paths. Build
and verify an unsigned arm64 iPhoneOS complete object containing the generated
codec. When physical-device credentials are available, run the existing worker
device path and execute the codec round trip on the iPhone.

This proposal does not change Bonsai Flutter's OCaml API, Flutter host,
protocol, ABI, or application configuration format. It does not install
arbitrary packages into the global `bonsai-flutter-ios` switch and does not add
a compatibility or fallback code-generation path.

## Decision

Adopt the proposal. The application closure resolver treats a PPX selected by
the native target as a host build dependency, queries its declared
`ppx_runtime_deps`, and projects only those runtime components into the target
closure. For `ppx_deriving_yojson` 3.9.1, the resulting iPhoneOS components are
`ppx_deriving_yojson.runtime`, `ppx_deriving.runtime`, and `yojson`; the PPX
driver and compiler-facing artifacts remain in the native macOS host closure.

The DataScript worker fixture pins the exact package version, preprocesses its
source with the real Dune PPX path, and executes a generated encoder/decoder
round trip. The generic `Pure_ocaml` Dune recipe builds both runtime packages,
with no package-name capability entry or fallback. Runtime SDK
`0.1.0~dev.5` and framework SDK `0.1.0~dev.32` replace their obsolete versioned
repository paths while ABI revision 2 and build recipe revision 4 remain
unchanged.

## Alternatives considered

### Treat the package as host-only

Install or describe only the native macOS PPX driver. This is insufficient
because `ppx_deriving_yojson` declares target runtime dependencies and the
generated code references both its runtime support and `Yojson`.

### Install the dependency directly into `bonsai-flutter-ios`

Mutate the fixed global switch for this one application. This would make builds
depend on developer-local state, bypass source and checksum locks, and break
the immutable SDK model. The package must be part of a versioned runtime SDK
instead.

### Add closure rows without an executable fixture

Insert `ppx_deriving` and `ppx_deriving_yojson` into the supported lock and
generated repository without compiling a consumer. This would not verify that
Dune selects the host PPX driver, exposes only the runtime libraries to the
cross context, or links the generated code successfully.

### Generate codecs on macOS and commit the expanded source

Pre-expand `[@@deriving yojson]` and avoid PPX execution during iPhoneOS builds.
This creates a second generated-source workflow, can drift from the source type,
and hides a supported pure-OCaml dependency from the SDK rather than fixing the
SDK closure.

### Hand-write JSON codecs in the consumer

Avoid the SDK change by replacing the deriving dependency with handwritten
functions. That duplicates generated behavior in every consumer and does not
satisfy the request to support `ppx_deriving_yojson` 3.9.1 in the iOS SDK.

## Acceptance criteria

- The application closure fixture pins `ppx_deriving_yojson` exactly at 3.9.1
  and invokes it through Dune's `(pps ppx_deriving_yojson)` preprocessing path.
- Fixture source declares a representative `[@@deriving yojson]` type and
  executes a successful generated encode/decode round trip.
- The resolved reference and supported closure locks contain immutable source
  identities and checksums for `ppx_deriving_yojson` 3.9.1 and the selected
  compatible `ppx_deriving` version.
- The closure contains `ppx_deriving_yojson.runtime`,
  `ppx_deriving.runtime`, and `yojson` as target components required by the
  generated application code.
- PPX executables and compiler-facing archives remain native host artifacts;
  none are copied into the iPhoneOS target library or final application bundle.
- The generic `Pure_ocaml` Dune recipe builds and stages the selected runtime
  components without a package-specific capability entry or build fallback.
- The immutable runtime SDK package version advances, and the framework SDK
  package version that embeds the new manifest advances without changing the
  protocol ABI or SDK build recipe revisions.
- The generated local opam repository contains only the newly selected SDK
  package versions and reproduces byte-for-byte under
  `tool/ios/regenerate_sdk_repository.sh --check`.
- Closure, DataScript worker, SDK layering, repository, and CI contract checks
  cover the new package and pass.
- An unsigned release iPhoneOS complete object using the derived codec is
  verified as arm64, platform `IOS`, and minimum iOS 15.0.
- The codec round trip passes on a physical iPhone when device signing
  credentials are available.

## Consequences

- iPhoneOS applications can use `[@@deriving yojson]` without committing
  pre-expanded source or installing compiler tooling into the target sysroot.
- The checked-in DataScript worker closure now contains 123 packages: 69 target
  packages, 53 host-only packages, one target-build package, and 106 target
  Findlib components.
- The generated repository carries immutable source identities for
  `ppx_deriving` 6.0.3 and `ppx_deriving_yojson` 3.9.1 and contains only runtime
  archives for those packages in the iPhoneOS target library.
- The generated codec and its runtime symbols are present in a verified release
  complete object for arm64 iPhoneOS with minimum iOS 15.0.
- Physical-device execution remains conditional on the existing signing
  environment variables; the contract now requires the codec round-trip marker
  whenever that path runs.

## Risks

- Changing the dependency closure changes the runtime SDK identity. Existing
  `bonsai-flutter-ios` installations require complete toolchain replacement;
  the framework-only updater is insufficient.
- `ppx_deriving_yojson` combines a host PPX driver and target runtime libraries
  in one opam package. Incorrect component classification could either leak
  host compiler artifacts into the app or omit required target archives.
- `ppx_deriving_yojson` 3.9.1 constrains `ppxlib` to the range
  `[0.30.0, 0.36.0)`. A future `ppxlib` upgrade must revisit this package even
  though it is compatible with the current 0.35.0 SDK version.
- Extending the existing DataScript worker fixture couples this core
  pure-OCaml PPX check to a larger SQLite closure. A separate fixture would
  isolate failures but would add another closure-union and device-test path.
- If the current generic Dune runtime builder cannot build only the selected
  runtime components from these mixed PPX packages, the required build-recipe
  change is outside this proposal and must be explored explicitly rather than
  hidden behind a package-specific fallback.

## Questions

- None. The user explicitly approved modifying
  `tool/ios/fixtures/application-closure/app.dune` with
  `(preprocess (pps ppx_deriving_yojson))` and selected the existing DataScript
  worker fixture as the closure and physical-device verification path.
