# Retire Superseded Eio Host Spike Harnesses

## Problem

`tool/eio_worker_spike` still contains a host-only Phase 0 verification chain
that is disconnected from every maintained build, test, and documentation
entry point:

- `test.sh` compiles `eio_worker_backend_spike_test.ml` and then invokes
  `test_macos_provider_spike.sh`;
- `test_macos_provider_spike.sh` compiles
  `eio_worker_provider_spike_test.ml`; and
- `build_macos_complete_object.sh` builds a separate macOS complete object from
  the spike backend.

Repository-wide exact-name searches find no consumer of `test.sh` or
`build_macos_complete_object.sh`. The provider test script is reachable only
from the otherwise-unreferenced `test.sh`, and the two OCaml test programs are
reachable only from those host scripts. Neither the Make targets nor the
maintained documentation names this host chain.

The harness tests copies of the original prototype rather than the production
Worker implementation. Its backend assertions are now covered against the
real implementation by `ocaml/test/worker_runtime_tests.ml` and
`ocaml/test/bounded_mailbox_tests.ml`, including bounded enqueue, a blocking
idle wait, cross-Domain execution, sequential session reuse, out-of-band stop,
and idempotent final shutdown with exactly one join. Production Eio service
and cancellation behavior is additionally covered by
`ocaml/test/worker_eio_service_tests.ml` and
`ocaml/test/worker_eio_phase3_tests.ml`.

The same directory also owns separate iPhoneOS complete-object and physical
device probes. Those remain meaningful: `tool/test_ios_deployment_target_contract.sh`
inspects the iPhoneOS scripts, and `README.md` plus
`docs/ios-device-testing.md` use the physical Eio Worker probe as support
evidence. The accidental complexity is therefore the abandoned host harness,
not the complete spike directory.

On 2026-08-24, the user confirmed that no out-of-repository workflow invokes
`tool/eio_worker_spike/test.sh` or
`tool/eio_worker_spike/build_macos_complete_object.sh` directly. The final
unknown external consumer is therefore resolved.

## Decision

Delete the five host-only files:

- `tool/eio_worker_spike/test.sh`;
- `tool/eio_worker_spike/build_macos_complete_object.sh`;
- `tool/eio_worker_spike/test_macos_provider_spike.sh`;
- `tool/eio_worker_spike/eio_worker_backend_spike_test.ml`; and
- `tool/eio_worker_spike/eio_worker_provider_spike_test.ml`.

Retain the spike backend, provider, device callback, C and Objective-C hosts,
iPhoneOS build scripts, and iPhoneOS test scripts unchanged because they still
serve the cross-compilation and physical-device evidence. Do not replace the
deleted chain with a compatibility wrapper, alias, migration script, or new
generator.

This removes a second host-side verification path without changing runtime
behavior, public APIs, protocol bytes, generated artifacts, Dune metadata,
documented commands, or the supported iPhoneOS probes.

## Alternatives considered

### Keep the host harness as a manual diagnostic

This retains the strongest argument for the current design: the small
prototype can isolate Eio POSIX, provider, and complete-object failures from
the larger production runtime. However, there is no maintained entry point or
documentation for the harness, and passing it does not prove that the current
Worker implementation has the same behavior. The production tests provide
more relevant failure evidence.

### Delete the complete Eio Worker spike directory

This would remove more code, but it would also delete the iPhoneOS
complete-object and signed physical-device probes that still support explicit
repository claims. That is a testing-policy change, not a behavior-preserving
simplification.

### Retarget the iPhoneOS probes to production Worker modules

Testing the production implementation on device would be more direct, but it
requires redesigning the probe closure and deciding which production service
behaviors belong in the physical-device gate. That broader testing decision is
not required to remove the unreachable host chain.

## Consequences

- The five host-only files named in the decision are removed. No replacement
  script, compatibility path, migration layer, or generated artifact is added.
- The retained Eio backend, provider, device callback, C and Objective-C hosts,
  iPhoneOS build scripts, and iPhoneOS test scripts remain unchanged.
- The viewport compile fixture now constructs the required Material color
  scheme and passes the required brightness and color-scheme arguments to
  `Ui.Theme.material`. This repairs an unrelated stale fixture exposed by the
  repository verification sweep without changing the public API.
- `tool/test_ios_deployment_target_contract.sh`, `make ci-contract`,
  `dune build @all`, `dune runtest`, the viewport type check, formatting and
  protocol-generation checks, the release benchmark build, opam lint, and all
  eleven example consumer build and test gates pass after removal.
- `make ci-ocaml` is not invoked directly because its installation prerequisite
  executes `opam install .`, which violates the repository's Git-pin safety
  rule. Every non-install command owned by the target passes when run directly.
- Developers lose a small standalone macOS reproduction for the original Eio
  backend and provider prototype.
- The retained iPhoneOS probe continues to validate prototype modules rather
  than the production Worker implementation.
