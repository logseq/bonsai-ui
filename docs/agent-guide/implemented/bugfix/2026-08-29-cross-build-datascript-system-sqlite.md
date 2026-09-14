# Cross-build DataScript with system SQLite

## Problem

The iOS runtime SDK build for `datascript-ocaml-native` fails its relocatability audit. The pinned DataScript source adds `-L%{env:DATASCRIPT_SQLITE_LIB_DIR=.}` to `c_library_flags`, so its compiled archive always records an explicit library search path. The SDK recipe correctly rejects every `-L` entry because it can leak a build-machine path into the distributed toolchain. DataScript only needs the iOS system `sqlite3` library, which is already selected by `-lsqlite3`.

## Proposal

Add a narrowly scoped iOS SDK source patch for `datascript-ocaml-native` that changes its SQLite flags from `-L%{env:DATASCRIPT_SQLITE_LIB_DIR=.} -lsqlite3` to `-lsqlite3`. Apply the patch in the runtime package builder before cross-compilation, verify both the expected upstream input and the patched output, and fail if the upstream source drifts. Keep the existing SDK library-path audit unchanged.

Increment the iOS runtime recipe revision and publish new runtime and framework SDK development versions. Advance the host CLI's supported SDK build recipe revision in the same source release so it accepts the regenerated manifest and rejects the obsolete recipe. The dependency source revisions and the runtime ABI revision remain unchanged.

## Decision

The iOS runtime package builder applies `datascript-system-sqlite.patch` only to `datascript-ocaml-native`. It requires the pinned upstream flag declaration before applying the patch, verifies that `DATASCRIPT_SQLITE_LIB_DIR` is absent afterward, and requires the final `(:standard -lsqlite3)` declaration. The general `-L` relocatability audit remains strict.

The runtime recipe revision advances from 4 to 5, the SDK build recipe revision advances from 3 to 4, and the runtime package advances from `0.1.0~dev.2` to `0.1.0~dev.3`. The final framework package is `0.1.0~dev.28`, built from source revision `68f4f83a0c9289b0ff3399040d900dfb5645f252`. The ABI remains 2. The host CLI accepts build recipe revision 4 and rejects obsolete revision 3 manifests.

## Alternatives considered

### Allow the DataScript library path

Do not allow `-L.` or any other DataScript-specific search path in the SDK audit. Relative paths depend on the build working directory and absolute paths leak the build machine, so either form makes the archive non-relocatable.

### Set `DATASCRIPT_SQLITE_LIB_DIR`

Do not configure the environment variable to an iOS SDK path. The flag still records a `-L` entry and couples the package output to one Xcode installation.

### Remove or rewrite flags after compilation

Do not relax the audit or mutate compiled metadata. Patching the source declaration keeps the build input explicit and lets normal compiler and linker behavior produce the correct archive.

## Acceptance criteria

- A contract test applies the real patch to the expected upstream `sqlite/dune` declaration and proves the result contains `-lsqlite3` without `DATASCRIPT_SQLITE_LIB_DIR` or `-L.`.
- The runtime package builder applies the patch only to `datascript-ocaml-native`, rejects source drift, and verifies the patched declaration.
- The focused contracts and the complete repository contract suite pass.
- Host CLI unit tests accept SDK build recipe revision 4 and reject revision 3.
- New runtime and framework SDK versions are generated from the pushed recipe commit.
- A clean iOS toolchain installation succeeds with `melange-transit` 0.1.1 and the updated DataScript source.
- Toolchain verification and an unsigned example iOS build succeed.

## Risks

- A future upstream change to `sqlite/dune` will deliberately fail the patch precondition and require reviewing the recipe patch.
- Publishing the corrected recipe requires rebuilding the complete iOS runtime and framework SDK packages.

## Questions

- None. The user explicitly authorized the toolchain recipe fix, commits, and pushes after the reproducible installation failure was reported.

## Consequences

- A clean fixed-switch installation cross-built both `datascript_ocaml` and `datascript-ocaml-native` successfully, including the system SQLite linkage audit.
- The installed toolchain contains runtime SDK `0.1.0~dev.3`, framework SDK `0.1.0~dev.28`, DataScript `dev`, and `melange-transit-core` and `melange-transit-native` 0.1.1.
- The controlled framework updater preserved the immutable runtime package while replacing framework `dev.27` with `dev.28`.
- Toolchain verification passes with fingerprint `bf5888716f9a50e87f0b4ac4a611109a8c4dd41c45d321d45c6dcc4e002623b2`.
- The `sqlite_worker` unsigned debug iOS build produces a verified arm64 iPhoneOS application bundle with minimum deployment target 15.0.
- The real patch application contract, all 85 host tool tests, closure verification, opam lint, reproducible SDK generation, and the complete repository contract suite pass.
