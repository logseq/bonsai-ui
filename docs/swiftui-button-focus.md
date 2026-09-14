# Native Button Autofocus

`View.button ~autofocus:true` requests SwiftUI focus when the control is mounted,
enabled and acknowledged as presented. The argument defaults to `false`.
Roles, styles and composed labels remain ordinary SwiftUI Button behavior.
The former Material Button/FAB constructors and codecs are removed.

## Focus and activation contract

A request waits while the control is disabled or unpresented. Once native focus
is acquired, the request is consumed: moving focus to an editor does not cause
the Button to take it back. Changing `autofocus` from false to true requests
focus again. Removing the keyed node or closing the session invalidates its
controller; recreating the node starts a new lifetime.

The focus modifier shares the existing SwiftUI view graph. Explicit autofocus
uses edit focus interaction so a programmatic request can acquire focus on
macOS with keyboard navigation disabled. Ordinary buttons retain activation
focus interaction. No system keyboard or accessibility setting is changed.

An admitted Space key-down activates the currently focused Button once.
Repeats and key-up are consumed without another action. Command, Control and
Option combinations are ignored. The modifier requires enabled state, actual
observed focus and current presentation admission before dispatching an action.
It does not install a default keyboard shortcut.

Native focus is retained across the interval between replacing an action
handler and acknowledging the new frame. Actions are paused during that
interval. After presentation, Space dispatches the new handler. Removing focus
eligibility during that interval previously lost focus permanently because the
initial autofocus request had already been consumed; the actual OCaml test
reproduced this failure before the retention fix.

The wire Button properties now contain enabled, role, style and autofocus.
Autofocus is required in the new binary payload; old three-field payloads,
invalid Boolean flags and malformed updates are rejected. There is no old
payload decoder.

## Verification

`ButtonAutofocusTests.swift` contains three native-window/protocol tests and
one real OCaml runtime test. They cover presentation gating, one-shot Space
activation, repeat and modifier handling, disabled retry, editor focus without
stealing, layout-anchor preservation, handler replacement before and after
acknowledgment, inactive input, removal, recreation and session close. The
runtime fixture uses the public `View.button` API and observes OCaml action
counts through the rendered tree.

The initial wire test failed because the renderer rejected the new payload.
The actual runtime test then exposed lost focus after handler replacement.
All four tests passed after the implementation and retention fix. The Counter
event round-trip test now reads all four Button properties before extracting
its handler binding; its real OCaml increment and replay checks pass. Tests send
NSEvents through their own AppKit window, without global event injection.
This establishes macOS native-window integration, not physical keyboard input
or unlocked desktop screenshot acceptance.

Physical iOS keyboard behavior, IME interaction, VoiceOver, system keyboard
navigation variants and focus inside modal presentations remain unverified.
The shared source also requires the iOS platform compile check. This feature
does not complete UIKit KeyboardListener or the full migration.

The complete serial Swift regression passes 447 tests in 98 suites in 427.833
seconds, including the focus and Counter event tests. The runner validates the
fresh completed xUnit report.

## Framework investigation

Apple documents programmatic focus through
[FocusState and focused](https://developer.apple.com/documentation/swiftui/view/focused(_:)),
platform [focus interactions](https://developer.apple.com/documentation/swiftui/view/focusable(_:interactions:)),
and focused-view [key press handling](https://developer.apple.com/documentation/swiftui/view/onkeypress(_:phases:action:)).

`tool/probe_swiftui_button_focus.swift` remains an isolated framework probe,
not an OCaml acceptance test. With keyboard navigation off, the ordinary Button
and explicit activation-focus variants did not acquire focus. Edit interaction
acquired wrapper focus but did not itself activate the Button on Space. These
historical results motivated the explicit focused Space handler; they do not
replace the integration tests above.

The standalone native Button window test passes in 32.943 seconds across two
widths and five sizes. All three platform checks pass in 21.071 seconds,
including the full physical-iOS Swift module and example sources, and explicit
Simulator/Intel rejection. These compile checks do not establish iOS keyboard
behavior.
