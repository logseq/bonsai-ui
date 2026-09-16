# Cooperative shutdown verification

## Scope and source identity

The public generation-bound `BonsaiApplicationEvents.beginShutdown` operation
owns terminal application-only transport. Tests use the real OCaml/native bridge
and one real Eio worker service; they do not model Journal's graph reducers.
`baseline.patch` and `baseline-status.txt` preserve the pre-existing staged input.
The feature publication excludes those unrelated source changes. Installed CLI
packaging also retains the user's existing host-configuration changes; archive
identity and framework/SDK source equality are recorded separately at release.

## RED evidence

`red.log` records a successfully started OCaml fixture and an expected assertion
failure after 0.449 seconds: hidden ordinary sending never reached a native
request. `red-test.swift.txt` retains the test-only baseline path, removed after
adding the supported explicit shutdown operation. The failure was behavioral,
not a compiler or fixture startup failure.

## Runtime verification

`ShutdownTests.swift` owns the native session/bridge boundary. It covers visible,
hidden, inactive, pending presentation, a queued real worker completion, full
ordinary and lifecycle event queues, repeated quit, terminal deadline and explicit
cancellation, close/restart, final reply acceptance, late provider results,
invalid admission, and exactly-once disconnect/worker teardown. The fixture also
produces an ordinary application request and a clipboard host request; neither
is dispatched by shutdown. After-display invocation counts remain unchanged.

The native window test uses the public `BonsaiApplicationView` and bridge, actual
`NSApp.hide`, `NSApp.deactivate` and `NSWindow.miniaturize`, and records each
window state with timings. Its NSHostingView supplies scene phase explicitly
(the standalone test harness does not own a SwiftUI Scene). The native inactive
state and the session inactive gate are tested separately. `NSApp.isActive` was
false in all four recorded window cases; the visible case does not establish an
active-application observation.

Initial window timings were 31.3 ms visible, 28.1 ms hidden, 27.4 ms inactive,
and 30.2 ms minimized. Subsequent logs retain timings for the final code.
These are transport-fixture timings, not Journal's complete graph-close path.

The C ABI test additionally verifies zero presentation token and unchanged
unpresented revision, retired-token rejection, rejection of ordinary pumping,
clock/malformed-input errors and output-buffer release.

## iOS evidence

`platforms.log` records physical-iOS Swift module compilation, all example Swift
source typechecks, supported-target checks and explicit unsupported-target
rejection. `xcrun devicectl list devices` identified an iPhone 13 as unavailable.
Physical-device execution is unverified. A suspended or killed process cannot
run this exchange; the API does not grant background execution time.

## Release and additional checks

The [release record](release.json) identifies source commit
`d8be5273407e8137e1d1a073f732ef4e702509e3` and separate SDK commit
`2211f9b89d4e8e2985db4dc851b6731b2f659b3d`, both pushed to
`codex/cooperative-application-shutdown`. Framework SDK `.43` uses native ABI 4.0
and unchanged runtime SDK `.7`. Its immutable source archive SHA-256 is
`9acfb3a7a26c5c7d68cea47d91b762eea7a7bcf417917d315f22e28e2bd65489`.

The installed framework, CLI and testing packages all identify final archive
SHA-256 `72ca232e251821d50776f312ee2976c4169d0627703e45dc49d8e567cf3f42a3`.
All 399 OCaml/native/Swift framework files in that archive exactly match the SDK
source archive. The final archive also preserves the pre-existing host CLI
configuration work; the source feature commit does not silently include it.
SDK publication reuses the staged canonical repository URL metadata needed for
reproducible generation. The original worktree index remains unchanged, including
its pre-existing staged SDK `.42`; working generated output intentionally advances
to `.43`. The baseline patch retains the prior generated output as well.

Validation logs record `dune build @all @install`, `dune runtest`, a clean
publication-worktree build/test, 189 native session tests, 21 final focused
bridge/lifetime tests, seven real C ABI tests, formatting checks, three physical-iOS
Swift compile/platform tests, two installed iOS tests (including an independent
unsigned App link), SDK reproduction, installed `doctor` and toolchain verification.
The linker emits existing Apple text-stub warnings; they do not indicate a failed
build. Physical-device execution remains unavailable.

`run_installed_shutdown.py` builds and CLI-launches a disposable synthetic App,
without framework source overrides or patched generated hosts. A native Quit
AppleEvent enters its application delegate, which starts the public shutdown
operation and returns `terminateLater`. The native reply is released after the
OCaml response and worker teardown. Installed results were 15.2 ms visible,
14.9 ms hidden, 15.6 ms inactive and 15.2 ms minimized. Every result reports zero
ordinary-provider calls, one disconnect, one accepted final reply and one worker
close. The installed fixture uses an immediate real worker response; source
session tests additionally use a delayed response. It does not open user data.

The first probe incorrectly called `NSApp.terminate` synchronously from a Swift
concurrency task, leaving that executor inside AppKit's nested termination loop.
That probe was stopped and replaced with a native Quit event. Do not confuse that
harness invocation with a UI-initiated Quit callback; all retained installed
results use the actual native event and termination deferral.

A monotonic deadline bounds admission and cooperative provider execution, not
synchronous native/worker teardown. iOS suspension cannot execute shutdown work.

Text logs normalize trailing whitespace and line endings for repository checks.
