# Local iOS SDK installation

## Problem

The installed SwiftUI CLI bundles SDK metadata for the former Flutter framework
and iOS 15 compiler. Its source-lock checksum does not match the current iOS 18
closure, and its locked commit lacks the SwiftUI package. The user requests
installation of the current framework, CLI and matching iOS SDK.

## Proposal

Allow SDK repository generation from an explicit checksum-identified framework
source archive, in addition to the existing immutable commit release input.
Use package metadata from that archive and record its actual SHA-256 identity;
do not describe uncommitted sources as a published commit. Generate matching
SwiftUI runtime/framework SDK recipes and install them into the global
`bonsai-swiftui-ios` opam switch without changing the active host switch.

Deliver the generated repository and archive outside the framework worktree,
install the corresponding CLI resources through opam, and validate an independent
application using ordinary `bonsai-swiftui build ios` without an explicit native
object or a framework source-root override. Public publication remains separate.

## Decision

Use a checksum-identified source archive for the local SDK release and a dedicated
installed opam switch. Do not require a framework worktree at application build
time. Preserve commit-based generation for publicly published source releases.

Real consumer tests also require two packaging corrections: declare the matching
host `bonsai_swiftui` dependency for Dune's host and target contexts, and install
GMP with Zarith rather than recording a temporary build-directory link path.
Runtime recipe/package 7 and framework SDK package 40 replace the initial local
packages. SDK build recipe 5
invalidates old native artifact fingerprints and is required by the CLI.

## Alternatives considered

### Install the existing SDK

Rejected: its namespace, framework source and deployment target do not satisfy
the current framework contract.

### Depend on the worktree-local compiler

Rejected as the consumer installation path: it would retain dependence on the
framework checkout instead of an installed opam SDK.

## Acceptance criteria

- Repository generation accepts an explicit source archive, reads its package
  metadata, records its checksum, and rejects malformed input before replacing
  existing output. Commit-based generation retains its existing checks.
- The installed SDK uses the SwiftUI namespace and physical iOS 18 arm64 target.
- Actual compiler/runtime artifact checks and CLI toolchain verification pass.
- An independent application builds for iOS with installed packages and SDK.
- No protected spec or Dune files change, and no remote publication occurs.

## Consequences

The host switch retains the OCaml UI library and CLI, while `bonsai-swiftui-ios`
owns the physical-device compiler and SDK. The CLI selects the target switch.
The local source archive and installed package assets are independent from the
framework checkout. SDK recipes that retain build-directory link paths are
rejected by actual installed-library linking checks.

## Risks

- Installing a new compiler and dependency closure can take substantial time.
- Local file URLs are machine-local release inputs, not public download links.
- Physical device execution requires an available device and is separate from
  SDK installation and unsigned generic-device App linking.

## Questions

None. The user explicitly requested completion of the SDK installation.

## Implementation and validation

- The archive-input generator and matching package recipes are implemented.
  Four repository tests and three release packager tests pass.
- Installed framework SDK `0.1.0~dev.40`, runtime SDK `0.1.0~dev.7`, and
  OCaml iOS compiler 5.1.1 in `bonsai-swiftui-ios`. At this checkpoint, the host switch was
  `bonsai-flutter-v017-exact`, with the UI library and updated CLI installed.
  After this installation checkpoint, the user renamed the host switch to
  `bonsai-ui`; current commands use that name.
- Installed CLI verification and four actual compiler/runtime artifact tests pass.
- Both installed-consumer tests pass in 33.576 seconds: an independent unsigned
  Release iOS App and a standalone Zarith object linked using installed GMP.
- The DataScript Worker contract passes against the global SDK, including
  process isolation and an unsigned physical-iOS App build.
- Host `dune build @all @runtest @fmt @install` passes, including 50 CLI tests.
- Local immutable release archives live outside the checkout. No source commit,
  push, public publication or device launch was performed.
