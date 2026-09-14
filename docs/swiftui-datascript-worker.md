# Native DataScript Worker Probe

The physical-device entrypoint is `tool/ios/test_datascript_worker_device.sh`.
It now builds a SwiftUI App containing a dedicated runtime/persistence probe.
It does not present the SQLite Worker application tree, and its acknowledged
frames establish runtime progress only. Mail, Gallery, and complete SQLite
Worker UI acceptance remain separate requirements.

## Actual application and Worker

`native/test/datascript_worker/dune` compiles the existing SQLite Worker
application, service and configuration sources together with the existing
DataScript/JSON/RRB fixtures. It copies these sources through Dune rather than
maintaining another application implementation. The resulting complete object
registers the `sqlite_worker` entrypoint through the production native backend.

The Worker stores and validates a typed DataScript fact in its SQLite storage.
The second process restores and validates that fact. The fixture also executes
the actual generated Yojson encoder/decoder and RRB vector invariants.
After successful validation it atomically publishes `probe-ready` with the
actual `persisted` or `restored` result. Its resource close function publishes
`probe-closed` only after `Datascript_sqlite.close` returns. These files are
probe synchronization, not application data or a new public protocol.

The Swift host reuses SQLite Worker's SWC1 startup payload builder. It removes
old probe results before opening the real `NativeRuntime`, pumps and consumes
frames, and waits for readiness with a bounded pump deadline. It explicitly
awaits `NativeRuntime.close()` and checks the Worker close result before
reporting success. Failure or cancellation after startup closes the runtime;
a startup failure never reports a successfully opened runtime. Device console
collection has a separate process timeout.

## Physical-device command

Run with an explicitly selected, paired and ready physical iOS 18+ device:

```sh
IOS_DEVICE_ID='<CoreDevice UUID or UDID>' \
IOS_DEVELOPMENT_TEAM='<Team ID>' \
IOS_BUNDLE_IDENTIFIER='org.example.datascript-worker-probe' \
  opam exec --switch=bonsai-flutter-v017-exact -- \
  tool/ios/test_datascript_worker_device.sh
```

The command preserves the pinned application dependency closure, cross-builds
for iOS 18 arm64, and signs a Release SwiftUI App with the selected development
identity. It performs device preflight before setup and again before installing.
It reinstalls the selected probe bundle to start with fresh storage, then
launches two independent App processes and requires persistence/restoration,
JSON, RRB, Worker shutdown, awaited host disposal, and final success evidence.
There is no Flutter discovery, Dart entrypoint, Flutter build, Simulator target,
or Native Assets manifest in this path. Internal compiler/SDK configuration
identifiers still await the broader package-name migration.

`tool/build_datascript_worker_probe.py` can build the same App unsigned from an
already verified physical-iOS complete object. The generator packages the
production BonsaiSwiftUI Swift package and its privacy resource. Unsigned build
success does not establish device execution.

## Binary constraints

`tool/ios/verify_app_bundle.sh` checks the static SwiftUI application executable,
its physical-iOS architecture/minimum, runtime symbols, allowed dependencies,
explicit system SQLite requirement, required-reason privacy resource and
matching application dSYM. It no longer expects the deleted Flutter framework
or a Dart Native Assets manifest. Complete ABI verification runs on the object
before linking; the application may have unused symbols stripped.

This probe exposed a missing integration of the extracted iOS process stubs.
The native embedding translation unit now includes those stubs only for
physical iOS, eliminating unresolved `fork`, `exec*` and `posix_spawn*` imports.
The macOS object does not define those overrides. Earlier iOS App artifacts
predate this fix and must be rebuilt for final acceptance. The separate signing
wrapper `tool/ci/verify_ios_bundle.sh` still needs its remaining Flutter paths
ported; the device probe directly invokes the updated bundle verifier and
`codesign --verify --deep --strict`.

## Verification and limits

- Actual independent macOS processes pass first-write and second-process
  restoration, including stale result removal and complete Worker/runtime
  shutdown. A corrupt database produces failure and no success result.
- Real macOS and physical-iOS complete objects pass process API isolation.
- The unsigned iOS 18 arm64 Release App builds from the current probe object.
- The actual bundle and its dSYM pass validation. Missing privacy data,
  incorrect SQLite mode and an invalid dSYM are rejected.
- The full `make ci-contract` passes, including these executable checks in
  the DataScript gate, main CI contract and iOS closure lock. The previously
  obsolete recipe/host-marker expectations now check the current native path.

Device readiness and signed on-device execution must be recorded separately.
The updated device command was run on 2026-09-14 and failed at its initial
preflight because DDI services were unavailable. It did not run toolchain setup,
sign, install or launch the probe. No new physical execution or screenshot is
implied by the build and host-process tests.
