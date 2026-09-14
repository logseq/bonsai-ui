# Retire Legacy Protocol Fixture Aliases

## Problem

The cross-language protocol fixtures have explicit producer-qualified names:

- OCaml generates `ocaml_counter_full.hex` for Dart consumers; and
- Dart generates `dart_counter_press.hex` for OCaml consumers.

The repository also generates and commits `counter_full.hex` and
`counter_press.hex` as byte-for-byte compatibility aliases. The aliases are
not independent golden data, do not cover an additional protocol shape, and
are not production runtime or package APIs. `docs/protocol.md`,
`docs/testing.md`, and `protocol/README.md` explicitly identify them as legacy
compatibility paths while directing new tests to producer-qualified names.

Repository-owned consumers have not completed that migration. The OCaml
fixture generator writes both `ocaml_counter_full.hex` and
`counter_full.hex`; the Dart fixture generator writes both
`dart_counter_press.hex` and `counter_press.hex`. Several OCaml and Dart tests
still read the aliases, and `ocaml/test/dune` declares them as test data. This
creates two names for each identical artifact, makes fixture provenance
ambiguous at those call sites, and requires both generators and documentation
to preserve obsolete paths.

Repository-wide exact-name searches found no production consumer. The known
consumers are fixture generators, protocol tests, renderer tests,
`ocaml/test/dune`, and protocol/testing documentation. On 2026-08-31, the user
confirmed that no out-of-repository workflow or tool directly consumes either
committed alias.

## Proposal

Retire the two compatibility aliases and use only producer-qualified fixture
names:

- delete `protocol/generated/fixtures/counter_full.hex` and
  `protocol/generated/fixtures/counter_press.hex`;
- stop emitting those two names from
  `protocol/generator/generate_fixtures.ml` and
  `flutter/packages/bonsai_flutter/tool/generate_input_fixtures.dart`;
- migrate every repository-owned test and `ocaml/test/dune` dependency from
  `counter_full.hex` to `ocaml_counter_full.hex` and from
  `counter_press.hex` to `dart_counter_press.hex`; and
- remove the compatibility-alias statements from `docs/protocol.md`,
  `docs/testing.md`, and `protocol/README.md` while retaining the canonical
  producer/consumer contract.

Do not add redirects, copied fixtures, symlinks, fallback lookup, migration
scripts, or replacement aliases. The resulting repository has one committed
name per fixture and one producer per name.

The change preserves runtime protocol bytes, protocol versions, public OCaml
and Dart APIs, decoder behavior, generated protocol IDs, and test coverage.
Only non-production test artifact names and their internal references change.
The user explicitly authorized the required `ocaml/test/dune` dependency edit
on 2026-08-31.

## Decision

Implement the proposal exactly as written: retain only
`ocaml_counter_full.hex` and `dart_counter_press.hex`, remove both unqualified
aliases from the fixture corpus and generators, migrate every repository-owned
consumer, and delete the compatibility-alias documentation. Do not introduce
any replacement compatibility path.

## Alternatives considered

### Keep the aliases as documented compatibility paths

This avoids breaking unknown external scripts that read a committed fixture by
its original name. It retains two indistinguishable files, two generator
entries, ambiguous internal consumers, and a compatibility obligation that
conflicts with the repository policy to remove obsolete paths.

### Delete the producer-qualified fixtures instead

Keeping only the original short names would delete fewer current internal
references, but it would discard the provenance convention documented for the
cross-language contract. A reader could no longer determine from a filename
whether OCaml or Dart owns the bytes.

### Keep aliases but migrate all internal tests

This would make internal provenance clear but would preserve duplicate generated
artifacts solely for an unproven external consumer. It reduces call-site
ambiguity without removing the obsolete compatibility surface or generator
maintenance.

## Acceptance criteria

- Exact-name repository searches find no reference to `counter_full.hex` or
  `counter_press.hex` except where those strings occur as suffixes of
  `legacy_1_12_counter_full.hex`, `ocaml_counter_full.hex`, or
  `dart_counter_press.hex`.
- The two alias files are absent and both fixture generators emit only their
  producer-qualified canonical names.
- OCaml protocol, event-dispatch, and cross-language fixture tests read
  `ocaml_counter_full.hex` or `dart_counter_press.hex` according to producer
  ownership.
- Dart binary-codec, event-batch, widget-renderer, and cross-language fixture
  tests read the same canonical producer-qualified files.
- Protocol documentation describes one canonical producer/consumer path and
  no compatibility alias.
- `make protocol-fixtures-check`, focused OCaml protocol/event tests, focused
  Flutter protocol/renderer tests, `make ci-contract`,
  `spec-dev-tool check --all`, and `git diff --check` pass.
- Runtime protocol encodings, versions, decoder behavior, and public APIs are
  unchanged.

## Risks

- The implementation must update all test-data declarations and direct path
  lookups atomically or tests will fail because a fixture is missing.
- Removing the aliases intentionally gives up the two obsolete unqualified
  fixture paths; no redirect or fallback will preserve them.

## Consequences

- The protocol fixture corpus will expose one producer-qualified name per
  cross-language artifact.
- Internal tests and Dune data dependencies will state fixture provenance at
  each path lookup.
- Both fixture generators and the protocol documentation will stop carrying a
  compatibility-only obligation.
- The implementation removes both aliases, migrates every repository-owned
  consumer to the producer-qualified fixtures, and passes the fixture,
  focused protocol and renderer, CI contract, agent-document, and diff checks.

## Questions

None. The user confirmed that no out-of-repository workflow or tool consumes
either compatibility alias and explicitly authorized the required later
`ocaml/test/dune` dependency edit.
