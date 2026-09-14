# SwiftUI Host Services

The Swift host currently implements clipboard read/write, native platform
information, URL opening, file import/export, native text focus, layout measurement,
window title/content-size requests, normalized container scrolling, notifications, action menus, haptics
and generic request cancellation. Other host-service families
remain part of the full migration.
The Host Effects example uses the actual OCaml Host_effect implementation and
native pasteboards; its Flutter host and configuration have been removed.

## Transaction and response contract

`HostCommand.decode` reads a positive Int64-bounded request ID followed by a
UInt16 kind: 0 cancels a request, 1 reads text and 2 writes a length-prefixed
UTF-8 string. Kind 3 opens a length-prefixed UTF-8 URL. Kind 4 carries a UInt16
extension count, length-prefixed extensions and a multiple-selection flag.
Kind 5 carries an optional suggested name and a UInt32-length opaque data blob.
Kinds 6 and 14 carry a positive node identity for focus and layout measurement;
kind 7 clears the owned window's focus and has no payload. Kind 8 carries a
positive container identity, finite Float64 alignment and Boolean animation
flag; see [native scroll service](swiftui-scroll-service.md).
Kind 9 sets a UTF-8 title, kind 10 carries two finite positive
Float64 content dimensions, and kind 13 requests native platform information
with an empty payload. Kind 11 carries a bounded action-choice domain; see
[action menus](swiftui-host-menus.md). Kind 12 carries a haptic kind byte from
0 through 3; see [haptics](swiftui-haptics.md). Kinds 16–18 present [civil picker services](swiftui-host-pickers.md). `FrameState.staging` validates every command and complete payload
alongside the view transaction. Unknown kinds, malformed payloads and repeated
request IDs reject the whole candidate before a native effect can run.

OCaml allocates monotonically increasing request IDs. The displayed frame keeps
a high-water mark across same-epoch full snapshot recovery; each new request
must exceed the previously accepted mark. IDs within one frame may arrive in
any order but must be unique. This avoids an unbounded lifetime set of IDs.
Cancellation refers to an existing ID and does not advance the mark.

The native event envelope uses tag 19 for a host response, with zero node and
handler IDs. Its payload contains the positive request ID, one status byte
(0 success, 1 error, 2 cancellation), a UInt32 byte count and response bytes.
Cancellation has an empty payload. Response data is limited to 1 MiB, and
responses cannot enter through a UI event binding or coalesce with one another.

## Presentation, activity and lifetime

`BonsaiSession` dispatches commands only after successful native presentation
acknowledgment. A command deferred during an inactive acknowledgment resumes
when the session becomes active and visible. Staging, rejected presentation
and hidden application state do not initiate clipboard effects.

Responses share the existing bounded event queue. Exhaustion records an input
failure rather than silently dropping a reply. A reply can complete while a
newer frame awaits presentation: before the next native pump, control responses
are rebased to the currently displayed revision. UI events retain their original
revision. Events arriving during an in-flight pump remain queued for the next
one.

`HostEffectDispatcher` permits at most 256 outstanding requests by default and
returns a typed error on saturation. Cancellation removes a pending request,
cancels its task and returns one cancellation response; repeated or unknown
cancellations are ignored. Per-operation identities fence late completions.
Closing the session cancels all tasks and clears deferred commands; the session
identity also prevents old replies from entering a restarted runtime whose IDs
begin again. A same-frame request/cancel pair does not mutate the pasteboard.

## Native clipboard

`NativeHostService` runs on MainActor and uses NSPasteboard on macOS or
UIPasteboard on iOS. Missing text reads as an empty string. Writes validate the
UTF-8 limit before mutation; oversized reads produce an error. Native failures
become bounded error responses. The example limits its status preview to 4096
UTF-8 bytes, preserving code-point boundaries, so a valid 1 MiB transfer cannot
overflow the rendered string limit once the status prefix is added.

Tests inject a real named NSPasteboard, not a replacement in-memory clipboard.
They cover Unicode, empty and maximum-sized transfers, oversized rejection,
delayed native operations, saturation, cancellation and restart. The production
example's native window test presses Read and Write and checks the resulting
OCaml status at normal and 360-point widths. Test pasteboards are released and
the user's general clipboard is untouched.

Host Effects and the other nine available Swift App examples now cross-build
their real OCaml programs and link into signed iOS 18 arm64 Release Apps.
System paste permission behavior and physical-device clipboard interaction
remain unverified. No Simulator support is provided. See
[example build evidence](swiftui-example-builds.md).

## Native platform information

`HostRequestId.platformInformation` decodes an empty request body. On execution,
`NativeHostService` writes three length-prefixed UTF-8 strings: `macos` or `ios`,
`ProcessInfo.processInfo.operatingSystemVersionString`, and
`Locale.autoupdatingCurrent.identifier`. The OS-version string is native display
text, not a version-parsing API. Values are read on each request; no startup cache
or Dart platform adapter is retained in this path. The existing typed OCaml
`Host_effect.platform_information` decoder consumes the exact three-string value.

Host Effects exposes `Read platform information` and renders the response from
its OCaml handler. Requests share presentation/activation gates, transfer limits,
cancellation and session-restart fencing with clipboard effects. Reading platform
information does not access clipboard contents or change system preferences.

Tests compare the response with real Foundation values and execute the actual
OCaml example through the session. They cover deferred dispatch while inactive,
resumption, delayed replies, closure/restart, cancelled execution and preserved
pasteboard contents. Command validation includes a valid platform request and
rejection of trailing payload bytes. The native window scenario also reads the
information at its compact width. iOS runtime behavior remains a physical-device
acceptance item; compilation alone does not close that gate.

## Remaining service coverage

| Existing family | Swift host state |
| --- | --- |
| Clipboard read/write, request cancellation | Implemented and exercised with the actual OCaml example on macOS. |
| Open URL | Implemented through native application dispatch and the actual OCaml example on macOS; see [URL service](swiftui-url-service.md). Physical-iOS behavior remains unverified. |
| File pick/save | SwiftUI importer/exporter, session-owned copies and native macOS presentation/cancellation implemented. Actual macOS multiple selection, export, overwrite confirmation and cancellation now pass through the real App; physical-iOS interaction remains unverified. See [file services](swiftui-file-services.md). |
| Request/clear focus, measure layout | Implemented against presented native text inputs and SwiftUI geometry with actual OCaml request/response tests. Physical-iOS and broader presentation-surface acceptance remain open; see [node services](swiftui-node-services.md). |
| Scroll-to | Implemented through shared SwiftUI point bindings, observed completion and real OCaml/native macOS requests for all four container families. Physical iOS acceptance remains open; see [native scroll service](swiftui-scroll-service.md). |
| Window title/size | Implemented against the owned native window; iOS size requests return an explicit unsupported-operation failure. See [window services](swiftui-window-services.md). |
| Native menus | SwiftUI action chooser; see [contract](swiftui-host-menus.md). Physical interaction remains open. |
| Platform information | Implemented through Foundation and the actual OCaml example on macOS. |
| Haptics | Native iOS impact/selection and macOS generic requests, with actual OCaml/macOS response tests; physical feedback remains unverified. See [haptics](swiftui-haptics.md). |
| Notifications | `show_notice` uses a SwiftUI bottom safe-area presenter with real OCaml/native macOS tests; see [notifications](swiftui-notices.md). Physical iOS acceptance remains open. |
| Date/date-range/time pickers | Shared SwiftUI dialog presenter; see [civil picker services](swiftui-host-pickers.md). Physical-iOS acceptance pending. |
| Application-specific bridge requests/events | Implemented with actual OCaml request/event and native-window evidence; see [application bridge](application-platform.md). |

Unknown host command kinds reject the frame atomically. All declared service
kinds now have dispatch paths; per-service native and physical-device acceptance
requirements remain open as recorded above.
Bootstrap paths already used by SQLite Worker remain application-owned, while
SQLite, networking and Eio services continue to execute in OCaml.


## Platform-information verification checkpoint

The initial service/example tests fail because request 13 is unsupported and
`Read platform information` is absent (`/tmp/platform-info-red.log`). The native
App reproduces the missing action (`/tmp/platform-info-window-red.log`). After
implementation, 12 related tests pass in five suites
(`/tmp/platform-info-green.log`, 0.178 seconds); both Host Effects and Host
Navigation independent windows pass (`/tmp/platform-info-native-windows.log`,
47.586 seconds). OCaml `@all @runtest @fmt` passes with existing native linker
stub warnings (`/tmp/platform-info-ocaml.log`). The full regression passes 371 Swift tests in 83 suites with a fresh completed
xUnit report (`/tmp/platform-info-swift-full.log`, 331.039 seconds).
All three platform checks pass (`/tmp/platform-info-platforms.log`, 18.223
seconds), including physical iOS 18 compilation and explicit Simulator/Intel
rejection. Physical-device runtime acceptance remains unfinished.


The Host Effects and Mail macOS development bundles are rebuilt from this
worktree (`/tmp/platform-info-build-host.log` and
`/tmp/platform-info-build-mail.log`). Both pass deep/strict ad-hoc signature
verification and report arm64 with minimum macOS 26.0. Protocol generation,
shared fixtures, viewport compile-failure checks, strict handwritten Swift
formatting, whitespace checks and agent-document validation pass. The protected
spec tree is unchanged. Existing native linker and `Semantics.swift` unused-result
warnings remain. The Mac is still locked on the final computer-use check; no new
complete Mail screenshot, source push or generated SDK publication is claimed.
