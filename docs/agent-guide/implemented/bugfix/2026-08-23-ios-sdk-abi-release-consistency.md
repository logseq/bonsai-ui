# Ios Sdk Abi Release Consistency

## Problem

The generated iPhoneOS framework SDK release declares ABI version 3 while the
host CLI and native bridge support ABI version 2. The controlled framework
updater can install that release, but `bonsai-flutter toolchain verify
iphoneos` rejects the resulting immutable SDK manifest, leaving the fixed
iPhoneOS switch unusable.

## Proposal

Publish a corrected framework SDK package whose manifest declares ABI version
2. Increment the SDK package version so the invalid package is replaced by a
new immutable release. Keep the runtime SDK version and build recipe revision
unchanged because neither runtime artifacts nor the build recipe changed.

## Decision

Release framework SDK package `0.1.0~dev.16` with ABI version 2. Retain runtime
SDK package `0.1.0~dev.1` and build recipe revision 3.

## Alternatives considered

### Increase the supported ABI to 3

This would misrepresent the native bridge, which still exports ABI 2.0, and
would turn a release metadata mistake into an unnecessary host and runtime ABI
change.

### Reinstall the fixed iPhoneOS switch

Reinstalling cannot make ABI 3 compatible with a CLI and native bridge that
support ABI 2, so it would only repeat the failure.

## Acceptance criteria

- The generated framework SDK manifest declares ABI version 2.
- `tool/ios/regenerate_sdk_repository.sh --check` reports a reproducible SDK
  repository.
- The controlled framework updater installs the corrected package while
  retaining runtime SDK version `0.1.0~dev.1`.
- `bonsai-flutter toolchain verify iphoneos` succeeds with the installed host
  CLI.

## Risks

- The already-published invalid `dev.15` Git revision remains in repository
  history, but the generated repository exposes only the corrected immutable
  package version.

## Consequences

- Existing fixed iPhoneOS switches can upgrade the framework layer without
  rebuilding the runtime layer.
- The host CLI accepts the installed SDK manifest and can verify the immutable
  switch fingerprint.
- Future ABI increments must coincide with matching CLI and native bridge ABI
  changes.

## Questions

None.
