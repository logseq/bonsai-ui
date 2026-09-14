# Host effects and environment

Host effects are typed asynchronous requests from OCaml to the SwiftUI host.
`Driver.Handler.host_effects` provides the runtime-scoped context. Performing an
effect allocates a monotonic request ID, retains the Bonsai continuation, and
emits a HostRequest operation. The host validates commands with their frame,
executes them after presentation acknowledgment while active and visible, and
returns a bounded HostResponse. The next OCaml step resumes the continuation.

The current host implements clipboard read/write, URL opening, file import and
export, text focus, normalized scrolling, window title and size, platform
information, layout measurement, notifications, action menus and haptics. Civil-picker
host requests remain migration work. The API surface alone does not establish
an implemented host service. See the [service matrix](swiftui-host-services.md).

`Host_effect.show_notice` presents a SwiftUI notification with an optional action
and duration. It returns `Action`, `Dismiss`, `Swipe` or `Timeout`. Requests queue
in order; displayed time pauses while inactive. Cancellation removes only the
matching request. See the [notification contract](swiftui-notices.md).

`Host_effect.show_native_menu` presents a scrollable SwiftUI action chooser and
returns the selected ID or native dismissal. Menus and file dialogs share the
owned window's modal admission gate. See the [menu contract](swiftui-host-menus.md).

`Host_effect.haptic_feedback` submits native iOS impact/selection feedback or
macOS generic feedback. Its result confirms submission, not physical delivery;
see the [haptic contract](swiftui-haptics.md).

Focus, measurement and scrolling resolve nodes in the owned native window.
They require presented, matching node identities. Scroll alignment is clamped to
0...1 and converted into the current native scrollable extent; completion waits
for observed positioning. Missing, removed or incompatible nodes return an
error. See [node services](swiftui-node-services.md) and
[scrolling](swiftui-scroll-service.md).

Responses are success, error or cancellation. `Host_effect.Cancellation`
cancels an outstanding request. Session closure cancels host tasks, clears
unsent requests and fences late callbacks from a new runtime lifetime. OCaml
shutdown releases pending continuations. The application-specific byte bridge
is documented separately in [application platform](application-platform.md).

Environment updates use a separate, change-filtered input path. The wire format
carries viewport size, display scale, text scale, appearance, platform, locale,
safe area, keyboard insets, accessibility preferences, orientation and pointer
capabilities. OCaml exposes the accepted snapshot through `Environment.value`;
unchanged samples do not invalidate Bonsai. Automatic macOS observation is
implemented; automatic UIKit observation remains unfinished. See
[host environment](swiftui-host-environment.md).
