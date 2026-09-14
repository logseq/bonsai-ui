# SwiftUI notifications

`Host_effect.show_notice` presents a SwiftUI notification in the owned window's
bottom safe area. It replaces `show_snack_bar`; the old API and Flutter-specific
`Hide` and `Remove` results have been removed. The remaining results are
`Action`, `Dismiss`, `Swipe` and `Timeout`. Request cancellation returns
`Error Cancelled`.

Messages and optional action labels must contain non-whitespace text and fit
the protocol string limit. Duration is a positive UInt32 number of milliseconds,
defaulting to 4000. Host request 15 carries the message, optional action label
and duration. Successful responses encode Action=0, Dismiss=1, Swipe=2 or
Timeout=3; retired result bytes are rejected.

Notifications display in FIFO order. Each timer starts after its row appears,
pauses while the window is inactive or hidden, and resumes with its remaining
duration. When VoiceOver is enabled, a notification with an action does not
time out. The message is announced once per presentation. Actual VoiceOver and
physical iOS acceptance remain outstanding.

The view uses native SwiftUI buttons, material and adaptive horizontal/vertical
layout. A downward drag closes the notice without invoking its action. Closing
the session cancels queued and visible notices. Presenter identities fence old
view callbacks; session task identities prevent delayed cleanup from closing a
newly started runtime.

## Verification

The real Host Effects example now provides Show notification, Show timed
notification and Cancel notification controls. Its standalone native App test
passes action, dismissal, cancellation and timeout at normal and 360-point
widths, together with its file, application bridge, clipboard, window and URL
scenarios (40.256 seconds). The macOS Debug example bundle also rebuilds
successfully from the updated OCaml program and SwiftUI sources.

Ten targeted Swift tests pass in 2.673 seconds. Real OCaml requests exercise
compact-window placement, FIFO order, paused timeout, cancellation of queued and
visible requests, stale buttons, immediate session restart and inactive startup.
They also cover session removal/presentation and the actual Mail tree and bounded
materialization. The wire test covers valid, truncated and invalid content and
duration payloads.

The standalone notification App test passes in 28.518 seconds. Local AppKit
mouse events reach the real drag gesture and produce the OCaml `Swipe` result
without invoking the action. The harness requires an explicit completion marker
as well as exit status zero.

The complete serial Swift regression passes **456 tests in 100 suites in
457.371 seconds**, with a fresh completed xUnit report checked by the runner.
OCaml all/test/format/install also passes. Protocol and input-fixture generation
checks and three platform checks passed at the preceding notification checkpoint;
no Swift implementation changed afterward, only example controls and documentation.
Physical iOS interaction, VoiceOver, final visual acceptance and the remaining
full-migration requirements are still open.
