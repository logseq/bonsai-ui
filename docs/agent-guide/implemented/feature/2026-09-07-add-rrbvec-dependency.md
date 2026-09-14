# Add Rrbvec To The Supported Application Dependencies

## Problem

Applications using `bonsai_flutter` need `rrbvec` on macOS and iPhoneOS.
The macOS host can already install it, but the immutable iOS SDK does not
provide the package or its target library. The framework does not use it.

## Proposal

Support `rrbvec.dev` as an application dependency, locking the upstream Git
revision and archive checksum. Add package metadata to the local SDK opam
repository. Extend the existing application-closure fixture with the package
and a native vector probe, then resolve and merge its closure into the SDK
support closure using the existing pure OCaml build mechanism.

Exercise persistence, indexed updates, concatenation, empty vectors, and slices
in the macOS fixture and compile the same probe into an arm64 iPhoneOS complete
object. Keep the production framework's opam dependencies, Dune declarations,
and OCaml API unchanged. The only Dune edit is the application fixture.

Advance runtime SDK and framework SDK package versions, regenerate the SDK
repository and run reproducibility checks. Keep the ABI unchanged and change
build-recipe revisions only if a recipe modification is actually needed.
Document the application's own opam and Dune declarations and the requirement
to replace an installed toolchain when its runtime version changes.

## Decision

The user clarified that only applications need the dependency and then asked
to make the corresponding repository changes for both macOS and iOS. Adopt
that SDK-only scope, including the proposed application fixture dependency
and executable validation. The earlier proposal to add a framework dependency
is superseded.

## Alternatives considered

### Make the framework depend on rrbvec

The framework does not use vectors. A framework dependency would impose an
unnecessary package on every macOS consumer and misrepresent ownership.

### Install only in the host switch

This leaves iPhoneOS applications outside the immutable SDK support boundary.

### Add package metadata without building a consumer

Metadata alone cannot demonstrate native archive availability or cross-context
linking. The fixture must actually call the library.

## Acceptance criteria

- Application fixture metadata and its native target depend on `rrbvec`.
- Host and SDK package sources use one immutable upstream revision.
- Vector operations preserve previous versions and pass on macOS.
- The generated SDK manifest and target closure contain `rrbvec`.
- The vector probe links into a verified arm64 iPhoneOS complete object.
- Both SDK package versions advance and generated metadata is reproducible.
- Framework dependencies and files under `spec/` remain unchanged.

## Consequences

- `rrbvec.dev` is locked to commit
  `dd5ce904f91d53235b5136f7a771f3f074c3971d`, with archive SHA-256
  `aed0c632d3612edbc925f24a8d30ad0f5ec16e5d202996872708c95c57b69e35`.
- The resolver classified `rrbvec` as a dependency-free `Pure_ocaml` target
  library. Its existing generic Dune cross-build recipe passed unchanged.
- The reference closure now has 130 packages, 70 target packages, 59 host-only
  packages, one target-build package, and 107 target components. The supported
  closure has 234 packages and 146 target components. Existing source identities
  were checked for conflicts while merging the resolved probe closure.
- Runtime SDK `0.1.0~dev.6` and framework SDK `0.1.0~dev.37` replace the prior
  versioned generated directories. The actual framework source is unchanged,
  so its already published revision and checksum remain unchanged, as do ABI 3
  and build recipe revision 4.
- The new integration test first passed on macOS and failed on the previous
  iOS SDK with `Package rrbvec not found`. After building the target library
  in an isolated staging directory, the same test passed macOS execution and
  verified an arm64 iPhoneOS complete object with minimum iOS 15.0.
- The Dune fixture also produced macOS and iPhoneOS native complete objects.
  The DataScript fixture explicitly calls the probe, ensuring Dune retains it
  in the linked object rather than omitting an unreferenced module.
- Closure, SDK layering, DataScript, network, deployment-target, and CI contract
  tests passed. SDK repository regeneration was reproducible; changed OCaml
  fixture files passed formatting checks.
- The user subsequently requested updating the installed framework and iOS
  SDK. The source change is published as
  `308e1b8f5ee41cca23808e875a0c3e2df1a33860`. Framework SDK
  `0.1.0~dev.38` pins that source in a separate repository regeneration commit;
  runtime SDK `0.1.0~dev.6` remains unchanged. The host packages must use the
  regeneration commit, followed by full replacement of the previous runtime
  SDK installation. No physical iPhone run was performed.

## Risks

- Upstream declares native, bytecode, and Melange modes; validate the existing
  cross-build mechanism against the actual source before assuming support.
- Runtime closure changes require complete installed toolchain replacement.
- The app must declare the library in its own opam and Dune metadata.

## Questions

- None. The user accepted SDK support for application-owned dependencies,
  including the fixture changes described in the preceding response.
