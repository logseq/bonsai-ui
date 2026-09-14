# Consolidate Protocol Generator Validation

## Problem

`protocol/generator/generator_tests.ml` contains two large tests that mirror
the repository's authoritative protocol inputs and generated outputs:

- `test_schema_values` repeats selected literal values already present in
  `protocol/schema.sexp`, including the protocol version, limits, operation,
  node-kind, event-tag, and property IDs; and
- `test_all_targets_are_rendered_from_one_model` searches the OCaml interface,
  OCaml implementation, Dart, and Markdown render strings for 31 selected
  source fragments.

The assertions do not validate all schema entries or all rendered declarations.
Git history shows that individual feature commits append another selected
literal and one or more output substrings, so intentionally extending the
schema requires updating the schema, generated files, and a manually selected
subset of mirrored assertions.

The mandatory `ci-ocaml` boundary already runs the same schema loader and
`Render.all` through `generate.exe --check`. That command exact-compares all
four complete outputs with their committed artifacts:

- `ocaml/protocol/generated_protocol.mli`;
- `ocaml/protocol/generated_protocol.ml`;
- `flutter/packages/bonsai_flutter/lib/src/protocol/generated_protocol.dart`;
  and
- `protocol/generated/protocol-ids.md`.

`dune build @all` compiles both generated OCaml files, while `ci-flutter`
analyzes and tests consumers of the generated Dart declarations. Protocol and
cross-language fixture tests exercise the supported wire values and bytes. The
selected schema literals and substring checks are therefore a weaker,
maintenance-heavy duplicate of retained exact-generation, compilation, and
behavioral gates.

The synthetic `test_duplicate_ids_are_rejected` case is different: it proves a
schema validation failure that no valid generated artifact can exercise. It is
unique coverage and should remain.

## Proposal

Remove the two redundant tests while retaining the synthetic validation test:

- delete `load_schema` and `test_schema_values` from
  `protocol/generator/generator_tests.ml`;
- delete `test_all_targets_are_rendered_from_one_model` and both call sites;
- retain `test_duplicate_ids_are_rejected`, `expect_contains`, and its compact
  invalid schema fixture unchanged; and
- retain `protocol/schema.sexp`, all four generated artifacts, `Render.all`,
  `generate.exe --check`, all protocol/fixture behavior tests, and every CI
  command unchanged.

This reduces `generator_tests.ml` from a partial mirror of protocol contents to
the one independent parser invariant it currently owns. It removes roughly 175
lines of repeated test data without modifying a Dune file, production code,
schema value, generated artifact, wire byte, public API, or validation
obligation.

## Decision

Implement the proposal exactly as written. Treat `make protocol-check` as the
single authoritative generation-consistency gate. Standalone `dune runtest`
does not need to repeat selected current schema values or generated-source
fragments; it retains only the independent duplicate-ID rejection test in this
generator suite.

## Alternatives considered

### Retain one substring per output language

Four representative fragments would be smaller, but they would still be a
partial text comparison of the same `Render.all` result that `protocol-check`
compares in full. They would not add a distinct failure boundary.

### Replace the assertions with a synthetic miniature schema

A table-driven miniature schema could test naming conversion and each render
shape without pinning product entries. That changes generator unit-test
strategy and adds new test data. The current renderer is already checked
against the complete authoritative artifacts, so there is no demonstrated gap
requiring replacement coverage.

### Keep the mirrors for `dune runtest` alone

This gives `dune runtest` a partial stale-generation signal without running
`protocol-check`. It does not cover the whole generated output and it makes the
same concern owned by two commands. The user confirmed that this duplicated
partial guarantee is not required.

## Acceptance criteria

- `generator_tests.ml` retains the duplicate-ID rejection case and contains no
  literal assertions about the current product schema or substrings of current
  generated artifacts.
- `make protocol-check` exact-compares all four retained generated artifacts
  with `Render.all (Schema.load protocol/schema.sexp)`.
- `dune runtest protocol/generator`, `make protocol-check`, `dune build @all`,
  focused OCaml and Dart protocol tests, `spec-dev-tool check --all`, and
  `git diff --check` pass.
- No schema value, generated file, renderer implementation, public declaration,
  protocol byte, fixture, or Dune metadata changes.

## Risks

- Running `dune runtest` without `make protocol-check` would no longer catch a
  stale or malformed current generated artifact through these selected
  fragments. The full repository CI continues to run both commands.
- If maintainers view individual literals in `test_schema_values` as an
  independent protocol stability policy rather than a parser smoke test, their
  removal gives up that duplicated tripwire. The schema, generated artifact
  diff, cross-language fixtures, and behavioral codec tests remain the
  authoritative protections.
- The retained duplicate-ID test still uses `expect_contains` to validate its
  diagnostic. That text assertion protects user-facing failure meaning rather
  than generated source shape.

## Consequences

- `generator_tests.ml` now owns only the independent duplicate-ID parser
  invariant and no longer mirrors current product schema values or generated
  source fragments.
- Complete generated-output consistency remains owned by `make protocol-check`,
  while the generated OCaml declarations continue to be compiled and the
  cross-language protocol fixtures continue to be exercised behaviorally.
- The implementation removes 173 lines of duplicated generator-test code
  without changing the schema, renderer, generated artifacts, protocol bytes,
  public APIs, or Dune metadata.

## Questions

None. The user designated `make protocol-check` as the sole authoritative
generation-consistency gate.
