# Align iOS SDK ABI with Protocol 3

## Problem

Installing framework SDK `0.1.0~dev.35` succeeds, but the installed CLI rejects
its manifest during `toolchain verify iphoneos`. The SDK lock and generated
manifest declare SDK ABI 3 after the protocol 3.0 change, while
`Sdk.supported_abi_version` still declares 2. Reinstalling the same toolchain
cannot repair this mismatch. The native FFI ABI remains independently at 2.0.

## Decision

Set the CLI's supported SDK ABI to 3. Exercise manifest validation with the
actual supported CLI constants, accepting ABI 3 and rejecting ABI 2. Keep the
runtime package and native FFI ABI unchanged. Push this fix, regenerate a new
framework SDK package from that source commit, and push its generated update
separately. Reinstall the host packages from the regeneration commit and run
the installed controlled SDK updater, then verify the iPhoneOS toolchain.

## Alternatives considered

### Reinstallation or compatibility

- Reinstall the complete runtime: does not change the incompatible CLI constant.
- Accept both SDK ABIs: retains a compatibility path for the retired protocol.
- Revert the SDK ABI marker: contradicts the selected protocol-breaking update.

## Acceptance criteria

- A manifest with SDK ABI 3 validates using the current CLI's supported values.
- The same validation rejects the previous SDK ABI 2.
- CLI tests, formatting, generated repository checks, and document checks pass.
- Installed host packages and SDK are updated, and `toolchain verify iphoneos`
  succeeds without rebuilding the unchanged runtime package.

## Risks

- The SDK package version must advance because published package versions are
immutable. Source and regeneration commits must remain separate.

## Questions

None. The user's request to update the local framework and iOS SDK authorizes
repairing this version-alignment defect to complete installation and validation.


## Consequences

The CLI now requires SDK ABI 3, matching the protocol 3.0 SDK manifest. Native
FFI ABI 2.0 and runtime package `0.1.0~dev.5` remain unchanged. The manifest
regression first reproduced the installed verification failure, then passed
with the supported ABI corrected. Shared current-manifest fixtures now use ABI
3, including toolchain verification and build synchronization tests. All 87 CLI
tests and `dune build @all @fmt` pass. Installation uses the existing controlled
framework updater and the repository's two-commit publication sequence.
