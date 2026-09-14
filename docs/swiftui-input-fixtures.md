# Swift Input Fixtures

The production Swift `EventBatch` encoder now owns all seven canonical input
fixtures: press, host error response, Unicode text edit with composition, text
limit notification, environment snapshot, opaque application response and
opaque application event. Their names use the `swift_` prefix. The Dart
generator and its seven outputs have been removed. OCaml tests consume the
Swift outputs and verify both decoded fields and byte-identical re-encoding.

Run `make protocol-fixtures-generate` to regenerate OCaml output fixtures and
Swift input fixtures. Run `make protocol-fixtures-check` to check both producer
sets without modifying the canonical fixtures. Use the configured host opam
switch for these commands.

`tool/generate_input_fixtures.py` first builds the native test fixture, then
exports production-encoded data through the focused Swift fixture tests into
a fresh temporary directory. The existing Swift Testing report verifier
requires a fresh, complete, successful report. The generator also requires all
seven expected outputs before copying or comparing any canonical files. Normal
Swift test runs compare against the canonical files without rewriting them.

The generation/check Make contract fails in both scenarios while the old Dart
commands remain (`/tmp/swiftui-fixture-commands-red.log`). Both commands select
the native producer after replacement. The actual check command passes. Two
deliberate negative checks corrupt and remove the environment fixture: each
returns status 1, names the stale fixture and leaves the input untouched.
Restoring the exact original bytes makes the check pass again. These checks
exercise the real generator and Swift report verification, not a mocked process.

## Environment snapshot encoding

The seventh fixture exposed a missing Swift encoder for environment event tag
20. `NativeHostEnvironment` now represents Apple platform, viewport dimensions,
pixel/text scales, brightness, locale, safe-area/keyboard insets, accessibility
flags, orientation and pointer kinds. It encodes the existing contract using
runtime-control ownership (node and handler IDs zero). Dimensions must be finite
and nonnegative; scales must be finite and positive; insets must be finite.
Signed insets remain valid as required by the current OCaml contract.

The fixture/validation tests fail before environment encoding (39 issues), then
pass with all seven fixture cases and the invalid-value/queue-preservation test.
The input bytes are produced by Swift and verified independently by the OCaml
cross-language tests. These fixture checks alone do not establish native environment observation.
Automatic macOS publication is implemented in the [host environment](swiftui-host-environment.md);
[UIKit observation](swiftui-host-environment.md) is also implemented and compiles
for physical iOS; device behavior remains unverified.

## Remaining cleanup

The protocol fixture path, Make targets and CI contract now use the native
SwiftUI backend. The root Flutter/Dart source tree has been removed. Namespace
cleanup, remaining capabilities, physical acceptance and source/SDK publication
remain unfinished. Historical screenshot manifests
continue to record the actual source names used by their captured builds;
they are not rewritten to imply a newer build or a new screenshot.
