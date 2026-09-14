# Retire Generated Host Construction Tests

## Problem

`bonsai_flutter_tool` generates `flutter/test/widget_test.dart` for every
managed-adapter host. The test imports the generated host and application
adapter, constructs
`BonsaiFlutterHost(adapter: application.createBonsaiFlutterHostAdapter())`, and
asserts that the resulting Dart object is not null. It does not mount the
widget, await application preparation, start a runtime, render a frame, or
observe an error path.

The same constructor expression already appears in the generated
`flutter/lib/main.dart`, where `main` passes the adapter to
`BonsaiFlutterHost`. `flutter analyze` therefore compiles the same host,
adapter, imports, constructor, and static types for every consumer before the
consumer test command runs. The non-null assertion cannot fail after Dart has
successfully evaluated the non-null constructor expression.

Eight tracked managed examples carry byte-for-byte identical copies of this
15-line test:

- `examples/clock/flutter/test/widget_test.dart`;
- `examples/counter/flutter/test/widget_test.dart`;
- `examples/host_effects/flutter/test/widget_test.dart`;
- `examples/host_navigation/flutter/test/widget_test.dart`;
- `examples/mail/flutter/test/widget_test.dart`;
- `examples/navigation/flutter/test/widget_test.dart`;
- `examples/text_input/flutter/test/widget_test.dart`; and
- `examples/todo/flutter/test/widget_test.dart`.

The generator, synchronizer, and generator unit test add more test-only
machinery solely to emit and protect these copies. Each example also retains a
direct `flutter_test` dependency for this one file. New managed projects receive
both `flutter_test` and `integration_test` dev dependencies even though the
generated host contains no integration test. This creates repeated test runs,
generated-file ownership, and dependency surface without protecting behavior
beyond the existing analyzer gate.

## Proposal

Stop generating the tautological managed-host construction test and remove its
exclusively owned support surface:

- delete the eight tracked `widget_test.dart` files listed above;
- delete `managed_host_test` and `host_test` from
  `bonsai_flutter_tool/lib/host.ml`;
- remove `flutter/test/widget_test.dart` from `Host.render` and from the
  synchronizer's managed-source set;
- remove the `widget_test` lookup and its three substring assertions from
  `test_generated_managed_adapter_host` in
  `bonsai_flutter_tool/test/tool_tests.ml`;
- stop adding `flutter_test` and `integration_test` to a newly generated
  managed-host pubspec;
- remove the now-unused direct `flutter_test` dependency from the eight managed
  examples and regenerate their `pubspec.lock` files; and
- update the generated-host unit-test assertion that currently requires an
  `integration_test` dependency.

Do not replace the deleted test with a shared test, a compatibility file, or a
new test-only abstraction. Retain `flutter analyze` for every consumer,
`sync-host --check`, the tool's managed-host rendering and synchronization
tests, package-level `BonsaiFlutterRoot` and host-adapter tests, and every
example-specific behavioral test unchanged.

The net deletion is eight complete test files, two generator helpers, one
generated render entry, one managed-path predicate branch, four generator-test
assertions/lookups, two unused generated dev-dependency entries, and the
corresponding direct dependency and lockfile rows in the eight managed
examples. Production application behavior, generated `main.dart`, adapter
behavior, native artifacts, public APIs, and supported platform gates remain
unchanged.

## Decision

Implement the proposal exactly as written. The user confirmed that no
out-of-repository workflow or generated-project contract requires
`flutter/test/widget_test.dart`. Remove both predeclared test dependencies:
projects that add tests must explicitly declare the dependencies they actually
use, rather than relying on unused generator-maintained scaffolding.

## Alternatives considered

### Keep one representative generated construction test

One copy would avoid eight executions, but it would still assert only that a
non-null constructor returns a non-null object. The generator unit test already
checks the emitted `main.dart` constructor expression, and the representative
consumer's analyzer already compiles it. A retained copy would not own a
distinct boundary.

### Mount the generated host in a widget test

Mounting could exercise async adapter preparation, loading, failure, and root
creation. Those are real behaviors, but introducing such coverage changes the
test strategy instead of removing redundancy. Package tests already cover
`BonsaiFlutterRoot` and `BonsaiFlutterHostAdapter`; example-specific behavior
should be added only for a demonstrated consumer contract.

### Keep test dependencies as project scaffolding

Preinstalling `flutter_test` and `integration_test` makes it marginally easier
for a downstream project to add tests. It also makes unused dependencies part
of every generated project. A downstream project that adds tests can declare
the dependency it actually uses. The user confirmed that dependency-ready test
scaffolding is not an intended generator contract.

## Acceptance criteria

- Repository searches find no generated `managed host can be constructed`
  test, no `managed_host_test` or `host_test` helper, and no managed-source
  ownership for `flutter/test/widget_test.dart`.
- The eight listed test files are absent; their `flutter_test` dependencies and
  now-unreachable lockfile entries are absent after `flutter pub get`.
- A newly rendered managed host contains `flutter/lib/main.dart` but no
  `flutter/test/widget_test.dart`, `flutter_test`, or `integration_test` entry.
- `sync-host --check` passes for all managed examples without recreating a test
  file.
- `dune runtest bonsai_flutter_tool/test`, `make ci-contract`, each managed
  example's `flutter analyze`, `spec-dev-tool check --all`, and
  `git diff --check` pass.
- The repository's conditional consumer-test loop skips managed examples with
  no example-specific Dart tests and continues to run every consumer that does
  contain one.

## Risks

- A generated host or adapter could stop compiling in a consumer. The retained
  per-consumer `flutter analyze` invocation exercises that exact compile-time
  path before the removed test would have run.
- Downstream generated projects intentionally lose the obsolete test file and
  the two unused direct dependencies; no compatibility file or fallback will
  preserve them.
- Removing direct SDK test dependencies changes generated project metadata and
  lockfiles, although it does not change application runtime behavior.

## Consequences

- Managed-host generation now emits the application host and production
  metadata without predeclaring test SDK dependencies or creating a
  construction-only widget test.
- The eight managed examples no longer contain the generated test or its direct
  `flutter_test` dependency, and their regenerated lockfiles omit the
  unreachable test-only package closure.
- Consumer-owned test dependencies remain outside synchronized pubspec regions,
  and the CI consumer loop continues to analyze every example while running
  Flutter tests only where example-specific test files exist.
- Host construction remains compile-checked through each generated `main.dart`
  during Flutter analysis, while package-level host-adapter and root behavior
  tests remain unchanged.

## Questions

None. The user confirmed that the generated test path has no external contract
and that both unused test dependencies should be removed.
