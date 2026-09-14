# Dune Closure Omitted Local Leaves

## Problem

`Dune_closure.resolve_csexp` assumes that every library named by an
`internal_deps` entry also has a library stanza in `dune describe
external-lib-deps`. Dune 3.23.1 omits dependency-free local leaf libraries from
that output even when other local stanzas reference them. The resolver therefore
rejects a valid workspace before the OCaml native build starts, even though the
omitted local library contributes no external Findlib dependency to the iPhoneOS
SDK closure.

## Proposal

Treat an `internal_deps` library that is absent from the
`external-lib-deps` stanza index as a terminal local leaf. Continue traversing
the remaining internal dependencies and preserve all external dependencies from
stanzas that are present.

Replace the existing regression test that expects an error with one that accepts
an omitted dependency-free leaf. Add a mixed-closure test proving that ignoring
an omitted leaf does not discard external dependencies contributed by the root
or by another local stanza. Add an integration test that creates a minimal Dune
workspace, obtains the real `dune describe external-lib-deps --format=csexp`
output, and resolves that output to an empty external closure.

## Decision

`Dune_closure.external_closure` skips an internal dependency that is absent from
the library stanza index and continues traversing the remaining dependencies.
Present local stanzas retain their existing recursive traversal, duplicate-name
validation remains unchanged, and reachable external dependencies continue to
be returned in canonical order.

The test suite covers an omitted-only leaf, an omitted leaf mixed with direct
and transitive external dependencies, and the actual output of Dune 3.23.1 for a
minimal dependency-free local library.

## Alternatives considered

### Require every internal dependency to have a stanza

Keeping the current error treats a documented observation of valid Dune 3.23.1
output as graph corruption and blocks dependency-free local libraries. The
resolver does not need a complete inventory of local libraries; it only needs
the external Findlib closure.

### Query `dune describe workspace` to complete the graph

Merging a second Dune description would distinguish omitted leaves explicitly,
but it adds a command, parser surface, and graph-merging logic without changing
the external dependency result. Dune already classifies the reference as an
internal dependency, so terminating that branch is sufficient.

## Acceptance criteria

- Resolving a csexp graph whose executable references only an omitted local leaf
  returns `Ok []`.
- Resolving a graph with an omitted local leaf alongside present external and
  internal dependencies returns every reachable external dependency.
- A real minimal Dune workspace demonstrates that the Dune output is accepted.
- `dune runtest bonsai_flutter_tool/test` passes.
- `dune build @all` passes.

## Risks

- A malformed synthetic graph with a missing internal stanza is no longer
  rejected by this resolver. This is acceptable because production input comes
  from Dune, which has already classified the dependency as internal, and an
  absent stanza cannot contribute external dependencies in this description.
- The integration test depends on the installed Dune command and its output
  semantics, which is intentional coverage of this compatibility boundary.

## Questions

- None. The report supplies the reproduced Dune output, desired behavior, test
  cases, and verification commands.

## Consequences

- Valid Dune workspaces containing dependency-free local leaf libraries no
  longer fail SDK dependency closure resolution.
- External dependencies from all represented reachable stanzas remain in the
  result when an omitted leaf is encountered.
- The real-Dune integration test confirms both the stanza omission and the
  resolver result against Dune 3.23.1.
- All 87 `bonsai_flutter_tool` tests pass, `dune build @all` passes, and the
  formatting alias is clean.
- Repository policy published framework SDK `0.1.0~dev.31` from source revision
  `9483aae1520844a44508f534fbaa48ef76b43d7c`; the runtime package, ABI, and
  build recipe revisions remain unchanged.
