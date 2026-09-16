# Host switch documentation

## Problem

The user renamed the development switch to `bonsai-ui` and removed the former
host and Flutter iOS switches. Several current reproduction commands still
select the removed host switch.

## Proposal

Update current development and reproduction instructions to select `bonsai-ui`.
Explain shell environment refresh and the separate `bonsai-swiftui-ios` SDK
switch. Retain chronological execution records and capture manifests as evidence,
with a visible note identifying the current switch for reproducing old commands.
Audit executable scripts and configuration for dependencies on removed names.

## Decision

Use `bonsai-ui` in current host commands and identify historical names where
retained as execution evidence. Do not change runtime code or build definitions.

## Alternatives considered

### Rewrite every historical reference

Rejected because capture provenance and dated execution records describe the
environment used at the time, rather than current installation instructions.

## Acceptance criteria

- Current instructions use `bonsai-ui`; remaining old names are explicitly historical.
- Executable source/configuration does not depend on either removed switch.
- The documented host command and agent-document validation pass.

## Consequences

Current instructions resolve to the installed host switch. Historical records
remain auditable, while their reproduction uses the documented current name.

## Risks

- Already-open shells may retain the removed prefix until `opam env` is evaluated.

## Questions

None. The user requested the repository audit and necessary changes.

## Validation

Current commands and installation instructions now select `bonsai-ui`.
The implementation ledger explains how to rerun historical commands with the
new name. A scan including hidden and Git-ignored files, excluding build outputs,
finds removed switch names only in that ledger, two historical decisions and
one timestamped capture manifest. No executable script or active configuration
needs a switch-name change.

`opam exec --switch=bonsai-ui -- dune build @all @runtest @fmt @install` passes.
Whitespace checks pass for the updated instructions.
