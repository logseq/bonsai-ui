# Retire Message Composer Demo

## Problem

`tool/message_composer_demo` is a standalone Flutter application described by
its own README and pubspec as temporary. It was added with the original
`MessageComposer` native-widget implementation and is not referenced by the
repository Makefile, CI contract, maintained product documentation, consumer
workspace list, package manifests, or production entrypoints.

The directory now contributes 75 tracked files and 3,173 lines. Most of that
surface is a generated macOS/iOS Flutter shell, while the maintained behavior
lives in `flutter/packages/bonsai_flutter/lib/src/native_widget/message_composer.dart`.
Keeping the demo creates an additional Flutter application, Apple host projects,
pubspec, analyzer configuration, tests, and golden image that must be understood
and updated even though none participates in a repository gate.

The demo's five widget tests exercise initial button visibility, draft-preserving
collapse, a local send flow, local action feedback, and theme switching. The
package's maintained `message_composer_test.dart` has twelve tests covering the
renderer-owned contract directly: custom child slots and visibility, text events,
draft-preserving collapse and reopen, drag thresholds, touch-intent arbitration,
stylus behavior, disabled states, native registration and emitted events, binary
props validation, and child-cardinality rejection. The demo's only separate
artifact consumer is its golden test, which owns
`artifacts/example-screenshots/message-composer-demo.png`; no maintained document
or other test references that image.

## Decision

Remove the temporary standalone demo and its private visual artifact:

- delete `tool/message_composer_demo` in full, including its generated macOS and
  iOS hosts, local application state, tests, and pubspec;
- delete `artifacts/example-screenshots/message-composer-demo.png`, whose only
  consumer is the removed demo golden test; and
- retain the production `MessageComposer` implementation, OCaml native-widget
  API and codec, package tests, `docs/custom-widgets.md`, and the renderer-wide
  touch-intent decision unchanged.

This removes a disconnected non-production application rather than relocating
it or introducing a generator. Runtime behavior, wire bytes, public APIs,
supported consumer workspaces, package tests, and platform gates remain
unchanged.

## Alternatives considered

### Keep the demo as a manual device lab

The standalone app provides a convenient visual and physical-device surface.
This is the strongest reason to retain it. However, the repository does not
list it as a supported example, does not run its analyzer or tests, and does not
record a distinct device-only contract that the package tests cannot express.
An unowned manual surface is likely to drift from the renderer contract.

### Promote the demo to a maintained example

Moving it under `examples/`, converting it to the managed consumer workflow,
and adding it to every OCaml, Flutter, macOS, and iPhoneOS gate would make its
ownership explicit. That increases supported application and packaging surface
instead of simplifying the repository and is not justified by a behavior gap.

### Keep only the golden test

Moving the demo composition into the package test suite would preserve visual
coverage, but it would add a maintained snapshot obligation without evidence
that the snapshot catches a contract not covered by behavioral assertions. The
existing golden is currently outside all repository gates.

## Consequences

- All 75 tracked paths under `tool/message_composer_demo` and the private
  `artifacts/example-screenshots/message-composer-demo.png` artifact are
  removed. Maintained code and documentation contain no reference to either.
- The public `MessageComposer` Dart and OCaml surfaces, production registration,
  wire format, and maintained documentation remain unchanged.
- `flutter/packages/bonsai_flutter/test/message_composer_test.dart` retains its
  twelve focused tests for custom button slots and visibility, text changes,
  collapse and reopen behavior, gesture arbitration, enablement, native events,
  codec validation, and invalid child cardinality.
- `make ci-contract`, the focused `MessageComposer` test suite,
  `spec-dev-tool check --all`, and `git diff --check` pass after removal.
- The repository-wide `make ci-ocaml` sweep reaches an unrelated existing
  `examples/mail` failure where `test_bottom_destinations_are_explicit_and_restore_`
  cannot match a mounted node. Running that consumer's `dune runtest` directly
  reproduces the same failure; this change does not modify the consumer.
- The repository-wide `make ci-flutter` sweep passes the package analyze and
  test stages, then reaches an unrelated existing `examples/gallery` failure:
  the consumer has no `test/` directory and its generated-host check reports a
  changed `lib/main.dart`. This change does not modify that consumer.
- Developers lose a ready-made interactive macOS/iPhone MessageComposer lab and
  a screenshot composition that includes surrounding application UI. Package
  widget tests do not replace ad hoc manual-finger or platform-keyboard
  exploration on a physical device.
- A downstream workflow could have invoked the demo without a repository
  reference. The user confirmed that no such external contract needs to be
  retained.
