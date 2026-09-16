# Canonical repository location

## Problem

The project remote points to `logseq/bonsai-ui`, but package metadata and iOS
release generators still advertise the previous repository. Consumers follow
incorrect source and issue links, and newly generated SDK metadata repeats them.

## Proposal

Use `https://github.com/logseq/bonsai-ui` for project homepage, issues, development
repository and commit archive URLs. Update the source field in `dune-project`
as repository metadata requested by the user, without changing any Dune build
stanzas. Preserve third-party repository URLs and author identities.

Regenerate SDK metadata from a fresh checksum-identified local source archive,
including its snapshot and package checksums. Advance the framework SDK snapshot
to 41 so the installed snapshot 40 remains immutable. Do not install or publish
this new snapshot as part of the repository metadata edit.

## Decision

Update owned package metadata and generator inputs to the canonical repository,
then regenerate framework SDK snapshot 41 using the new local source archive.
Keep the existing SSH remote, which already addresses `logseq/bonsai-ui`.

## Alternatives considered

### Edit only generated package files

Rejected because regeneration would restore old links and existing checksums
would no longer describe the files.

## Acceptance criteria

- Project source and package links use the canonical repository.
- No old project repository URL remains in maintained repository files.
- Release artifact tests and SDK generation/reproducibility checks pass.
- Existing remote authentication, third-party URLs and runtime behavior remain intact.

## Consequences

New package artifacts advertise the correct repository and issue tracker.
SDK snapshot 41 identifies the updated source archive by its actual SHA-256;
installed snapshot 40 and previously distributed local releases are unchanged.

## Risks

- The local SDK source archive is machine-local until a release is published.
- Public commit-based SDK publication still requires a matching pushed source commit.

## Questions

None. The user supplied the canonical repository and requested related updates.

## Validation

- The scan including hidden and Git-ignored files finds no former project URL
  outside excluded build output and Git internals.
- All three release-artifact tests and four SDK repository tests pass.
- SDK regeneration with the recorded local source archive passes `--check`.
- `opam exec --switch=bonsai-ui -- dune build @all @runtest @fmt @install` passes.
- `git diff --check` passes.
- OPAM resolves canonical homepage, issues and development repository fields in
  all seven framework/example/generated SDK manifests checked.
- The DataScript Worker contract passes against the installed iOS switch,
  including its unsigned physical-iOS App build.

## Subsequent local installation

The user subsequently requested updating the local opam packages. A new immutable
release at `~/.local/share/bonsai-swiftui/releases/2026-09-16-logseq-installed/`
was packaged from the updated worktree. Its archive SHA-256 is
`1e4be4d52491d889ff2f848dca358eddfb6687e4ea36f5cbccd929fe0a389f5a`.
The existing local opam repositories now select that release and its copied SDK
repository. The host library and CLI were reinstalled in `bonsai-ui`; the iOS
host library was reinstalled and framework SDK upgraded to snapshot 41 in
`bonsai-swiftui-ios`. Runtime SDK 7 was reused.

Installed package metadata uses the canonical repository. Toolchain verification
and both installed-consumer tests pass in 36.413 seconds. The active switch is
still `bonsai-ui`. No public publication, source commit or push occurred.
