# Update Melange Transit 0.1.1 iOS SDK Closure

## Problem

The checked-in iPhoneOS application and supported dependency closures still
pin `melange-transit-core` and `melange-transit-native` at version `0.1.0` and
pin DataScript OCaml before its corresponding Transit dependency update. The
current upstream revisions are `melange-transit` 0.1.1 at
`a64270a1ed5c8ad3ff7e05dbb60e83ad0465ae93` and `datascript-ocaml` at
`5895af25101de15f56d7c5df383c150ca07cef90`. Leaving the SDK closure stale
prevents iPhoneOS consumers from receiving the Transit cache correctness fix
through the immutable runtime SDK.

## Proposal

Update the DataScript fixture pins, the reference and supported iPhoneOS
closure locks, and the local opam repository metadata to the two immutable
upstream revisions. Replace the obsolete Melange Transit 0.1.0 package paths
with 0.1.1 paths. Increment the immutable runtime SDK package version and the
framework SDK package version, retain the existing Bonsai Flutter protocol ABI
and build recipe revisions, and regenerate the committed SDK repository.

This change is limited to dependency and SDK packaging metadata. It does not
change Bonsai Flutter OCaml, Dart, protocol, or public API behavior.

## Decision

The iPhoneOS application fixture and SDK closure select DataScript OCaml commit
`5895af25101de15f56d7c5df383c150ca07cef90` and Melange Transit 0.1.1 commit
`a64270a1ed5c8ad3ff7e05dbb60e83ad0465ae93`. Their GitHub archives are locked
by SHA-256 in the reference closure, supported closure, and local opam
repository.

The Transit 0.1.0 opam package directories are removed instead of retained as
compatibility entries. The immutable runtime SDK advances from
`0.1.0~dev.1` to `0.1.0~dev.2`, and the framework SDK package that selects it
advances from `0.1.0~dev.25` to `0.1.0~dev.26`. The Bonsai Flutter source
revision, protocol ABI version, and SDK build recipe revision remain unchanged
because no framework source, protocol contract, or build recipe changed.

## Alternatives considered

### Keep the existing runtime SDK closure

Keep Transit 0.1.0 pinned and let non-iOS consumers select 0.1.1 independently.
This was not selected because the immutable iPhoneOS runtime SDK would retain
the cache bug and would disagree with the updated DataScript dependency.

### Retain both Transit package versions

Add 0.1.1 beside the existing 0.1.0 package metadata. This was not selected
because the SDK repository is a deterministic snapshot rather than a
compatibility repository, and obsolete dependency paths must be removed.

## Acceptance criteria

- The fixture pins the exact upstream DataScript and Melange Transit commits.
- Both checked-in closure locks select `melange-transit-core.0.1.1` and
  `melange-transit-native.0.1.1`, with valid source checksums and lock digests.
- The local iOS opam repository contains only the selected Transit 0.1.1
  package metadata.
- The runtime and framework SDK package versions advance without changing the
  protocol ABI or build recipe revisions.
- SDK repository regeneration is reproducible and all iOS closure, SDK
  layering, and CI contract checks pass.

## Risks

- The runtime SDK identity changes, so installed iPhoneOS toolchains require a
  complete replacement instead of a framework-only update.
- Incorrect archive checksums or incomplete closure metadata would make the
  immutable SDK unbuildable; repository regeneration and lock verification
  must validate them before completion.

## Questions

- None. The user selected the target package version, and both upstream
  revisions are already committed and pushed.

## Consequences

- iPhoneOS DataScript consumers receive the Transit 0.1.1 cache correctness
  fix through the immutable SDK dependency closure.
- Existing installations must replace the complete iPhoneOS toolchain because
  the runtime SDK package identity changed.
- The generated SDK repository contains only Transit 0.1.1 and is reproducible.
- Reference, supported, and generated runtime closure locks pass structural,
  dependency, checksum, count, and digest verification. The supported closure
  metadata now records its actual 143 target components instead of the stale
  value 141.
- The DataScript contract test covers exact upstream commits, selected Transit
  versions, obsolete package removal, and both SDK package version increments.
  SDK layering checks, opam lint, repository regeneration checks, and the full
  CI contract target pass.
