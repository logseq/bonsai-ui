# Opam Consumer Installation

## Problem

The consumer instructions require a framework checkout and development environment
variables. The existing installed-layout test manually runs installation commands;
it does not establish that opam can install the packages and run an independent
application without framework source discovery.

## Proposal

The user requires opam-installed libraries rather than a consumer-managed framework
checkout. Distribute `bonsai_swiftui`, optional `bonsai_swiftui_test`, and the
`bonsai_swiftui_tool` CLI as opam packages. Native Swift/C resources belong in the
installed tool package. Consumers use ordinary opam environment activation and
`bonsai-swiftui init/build/run`, without source-root or OCAMLPATH overrides.

Provide a release packaging command that creates a source archive and an opam
repository with checksums. Opam owns downloading, building and installation; users
do not maintain a checkout. Validate a real opam installation in an isolated copy
of the configured dependency switch, then build and run a separate macOS counter.
Document the installation entrypoint and the separate maintainer source workflow.
Existing iOS SDK publication remains a release prerequisite; do not imply this
host-package change publishes or validates the replacement SDK.

## Decision

Use opam-installed OCaml libraries and CLI assets as the application consumer
contract. Keep source-root overrides exclusively for framework development.
Ship release archives and checksum-bearing opam repository metadata together.

## Alternatives considered

### Require a framework checkout

Rejected by the user. Environment variables pointing into `_build` describe
framework development, not the supported consumer installation contract.

### Only test a manually populated installation prefix

The existing test covers asset discovery but omits opam package build/install
semantics and is insufficient acceptance evidence by itself.

## Acceptance criteria

- Generate an installable opam repository and checksum-addressed source archive
  from the current source, including required generated resources.
- Install the three packages with opam in an isolated test environment.
- An independent application builds and updates real OCaml state using the
  installed CLI and libraries, without source-root or OCAMLPATH overrides.
- Document consumer installation, resource ownership, release prerequisites,
  and the limitations of reusing a preconfigured dependency switch for testing.
- Do not modify protected spec or Dune files or publish remote changes.

## Consequences

Application repositories no longer need a maintained framework checkout. Opam
owns library compilation, installation and native assets. Release publishers
must host the generated artifacts before public consumers can install them;
iOS additionally requires its matching SDK release. Local acceptance reuses
third-party dependencies and is not evidence of clean-machine provisioning.

## Risks

- Opam is a source package manager: installation may compile sources internally.
  The requirement removes the need for a user-managed framework checkout, not
  source compilation inside the package manager.
- The reused dependency switch does not prove clean-machine dependency solving.
- iOS additionally requires a matching published cross-compilation SDK.

## Questions

None. The user has specified the consumer installation contract; implementation
and local validation do not require a publication destination.

## Implementation and validation

- `tool/package_opam_release.py` creates a deterministic archive and opam
  repository for the three existing public packages. Required example sources
  are included because Dune reads their copy-file dependencies during package
  builds. No Dune or protected spec files changed.
- `tool/test_package_opam_release.py`: three tests pass after reproducing the
  missing release-packaging behavior.
- `tool/test_swiftui_opam_install.py`: real opam compilation and installation,
  independent Debug/Profile/Release App builds, signature checks, native OCaml
  counter interaction, and child-command handling pass in 200.170 seconds.
  The test relocates compiler/findlib paths in its isolated copied dependency
  switch; it does not alter the original switch or claim fresh dependency solving.
- README and `docs/opam-installation.md` make opam the consumer entrypoint and
  distinguish maintainer source development and unpublished iOS SDK work.
- Local release artifacts are available under `_build/opam-release`; no commit,
  push, public repository publication or iOS SDK update was performed.
