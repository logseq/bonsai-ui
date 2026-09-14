# Sliver Documentation Test Alignment

## Problem

Sliver documentation and test comments contained historical statements that no
longer described the implementation. For example, `viewport_body_test.dart`
formerly characterized the varied-extent feedback path as absent even though
both hosts implement it. Two historical free-form plans also described
completed renderer work as pending and mixed resolved decisions with open
risks. Such stale references made it difficult to distinguish current
invariants, unverified behavior, and completed migration history.

This is more than cosmetic: stale statements can redirect debugging toward
already-fixed stubs, hide missing regression coverage such as zero-paint
recovery and multiple virtual slivers, and cause future changes to rely on a
draft plan instead of current executable behavior.

## Decision

Maintained API documentation and executable tests are the source of truth for
current sliver behavior. Audit all sliver references outside generated files
and classify each as current contract, active decision, or obsolete migration
history.

The repository applies the following policy:

- update or remove test comments that contradict current behavior;
- move unresolved work into focused `spec-dev-tool` agent documents;
- migrate durable API explanations into `docs/virtual-lists.md`,
  `docs/viewport-layout.md`, and public OCaml docstrings;
- delete obsolete free-form implementation plans after their still-relevant
  decisions and risks have been captured by maintained documentation;
- avoid future source comments that cite a temporary plan as the rationale for
  a stable invariant; state the invariant directly instead;
- require documentation claims about renderer events or geometry to reference
  a regression test that exercises the real host path.

## Alternatives considered

### Keep historical plans with a warning banner

A banner reduces some confusion but leaves duplicated and contradictory search
results. Stable context belongs in maintained docs, while active decisions
belong in the agent-guide lifecycle.

### Update only the known stale comment

The visible stale comment is evidence of a broader lifecycle problem. A narrow
edit would leave completed checklists and open risks interleaved in the old
plans.

### Preserve all historical files indefinitely

Git already preserves history. Retaining obsolete working plans in the active
documentation tree conflicts with the project's policy of removing obsolete
paths rather than adding compatibility layers.

## Consequences

- Repository search no longer finds claims that fixed or varied hosts lack
  `visible_range_changed` support.
- `docs/virtual-lists.md` describes initial emission, painted-range semantics,
  window ownership, cache extent, anchoring, and current limitations.
- Focused agent documents capture the implemented sliver decisions, while the
  obsolete free-form implementation plans have been removed.
- Sliver test comments state the invariant exercised and match their assertions.
- `spec-dev-tool check --all`, OCaml tests, Flutter analysis, and Flutter tests
  form the completion gate for this documentation policy.
- Deleting historical plans can remove useful rationale unless durable
  decisions are migrated first; the retained material now lives in maintained
  docs and agent decisions.
- Documentation can drift again unless future sliver behavior changes update
  tests and maintained docs in the same change.
