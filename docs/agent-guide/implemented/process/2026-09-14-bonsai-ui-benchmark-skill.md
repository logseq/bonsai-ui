# Bonsai Ui Benchmark Skill

## Problem

Bonsai UI needs a reusable benchmark workflow that checks SwiftUI/OCaml
communication during unchanged and interactive workloads, and verifies roughly
60 FPS during scrolling. Earlier Mail profiling located expensive work but did
not measure complete bridge traffic or establish a presented-frame FPS result.

## Decision

Added the repository-local `bonsai-ui-benchmark` skill under `.agents/skills/`.
It defines representative widget and collection scenarios, separates bridge calls,
payload bytes and semantic patches, and requires app-specific presentation data
for FPS acceptance. It includes current source entrypoints, repeatable collection
procedures, explicit provisional budgets and evidence requirements. This task
creates documentation and skill metadata only; it does not implement a benchmark
harness, modify runtime code, or claim new benchmark results.

## Alternatives considered

### Reuse the historical benchmark documents as acceptance thresholds

The existing baseline and patch-size documents describe the removed Flutter
renderer. Their limits cannot establish current SwiftUI performance budgets.

### Treat runtime pump rate as FPS

Empty pumps still require acknowledgments and do not correspond to displayed
frames. This would conceal both redundant polling and rendering stalls.

## Consequences

- The skill is discoverable at `.agents/skills/bonsai-ui-benchmark/SKILL.md`, with
  UI metadata and separate measurement/budget references.
- Scenarios cover idle trees, localized changes, native scrolling, declared and
  measured collections, direction changes, pagination, and the Mail example.
- Traffic and approximately 60 FPS have explicit, independently evaluated gates;
  missing measurements cannot produce a passing result.
- Local source/reference targets and current build/profiler help are checked.
  The bundled skill validator validates frontmatter and scaffold completion.
- No application, protocol, OCaml or Dune implementation is changed.

- Observer overhead can distort frame timing; collect low-overhead acceptance
  runs separately from diagnostic traces and verbose protocol logging.
- Default numerical tolerances are engineering starting points, not previously
  measured repository guarantees or Apple-defined standards.

- The user explicitly specified the location, communication checks and FPS goal.
  Scenario sizes and tolerances are stated as adjustable defaults. Creation of
  this skill does not constitute running the benchmark or passing its budgets.
