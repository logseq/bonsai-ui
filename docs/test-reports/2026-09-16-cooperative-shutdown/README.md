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

Release identity and installed-package checks are added after source publication
and separate generated SDK publication. A monotonic deadline bounds admission
and cooperative provider execution, not synchronous native/worker teardown.
