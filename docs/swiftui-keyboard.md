# Native Keyboard Events

The Swift event transport implements the keyboard contract through `NativeKey`
and event tag 9. Both Apple renderers now decode and mount KeyboardListener.
The AppKit capture path passes native window/OCaml tests. UIKit capture is
implemented and compiles for physical iOS 18; its actual keyboard, IME and
handled/ignored propagation still require device acceptance.

## Transport contract

The current BSFR event record carries two unsigned 64-bit identifiers, one
action byte and a 32-bit modifier mask. Both identifiers must fit a nonnegative
OCaml int64; zero and Int64.max are valid. The action is a closed Swift enum:
down is 0, up is 1 and repeat is 2. No modifier bits are discarded by transport.
The later native key-mapping checkpoint defines and verifies the platform adapters.

Keyboard records are discrete events. The shared queue preserves repeated
keys and every down/up boundary, including identical adjacent repeat records.
It rejects excess event or byte budgets without replacing existing records.
Out-of-range identifiers are rejected before queue mutation. The existing
runtime sequence/displayed-revision protocol provides replay fencing.

The text-editor admission path explicitly rejects keyboard payloads. Adding a
payload encoder does not authorize it on text-edit handlers or introduce a
listener admission path. Native keyboard ownership must be implemented with
the corresponding renderer and presentation checks.

## Verification

Three tests fail with seven issues when the new payload is present but still
rejected by the encoder (`/tmp/swiftui-key-red-final.log`, 0.022 seconds).
Earlier compiler failures concern enum exhaustiveness and test-harness Swift
syntax; they are not behavioral RED. After implementing the record encoding,
all three tests pass in 0.018 seconds (`/tmp/swiftui-key-green.log`).

The native fixture registers an actual OCaml `View.keyboard_listener` and
accumulates decoded key payloads. The Swift test reads its emitted binding,
encodes twelve down/repeat/repeat/up records with boundary identifiers and
modifier masks, and checks the complete returned OCaml history. Replaying the
same batch leaves that history unchanged. The fixture is exercised at the
native runtime boundary, without claiming NodeStore or SwiftUI rendering of
the still-unsupported KeyboardListener node.

The related event, queue, text-editor and gesture regression passes 28 tests
in nine suites in 0.133 seconds (`/tmp/swiftui-key-related.log`). Three platform
checks pass in 20.151 seconds (`/tmp/swiftui-key-platforms.log`), including the
full module and retained example entrypoints for physical iOS 18 arm64. OCaml
build/test/format/install and generated-protocol checking pass
(`/tmp/swiftui-key-ocaml.log`). No full Swift suite was rerun for this isolated
encoding change; the prior 416-test run belongs to the pointer-contact
checkpoint.

## Remaining implementation and acceptance

Implement native capture and platform key mapping, listener rendering and
focus/autofocus, handled/ignored propagation, nested controls and IME behavior.
Verify lifecycle changes, binding replacement, hidden/disabled content,
keyboard repeat and physical iOS/macOS input. FocusScope is covered by the
later checkpoint below; Button autofocus remains unfinished. No system keyboard setting was
changed and no new Mail screenshot was produced by this checkpoint.

## Native key mapping

`NativeKeyMapping.swift` maps native Apple events into the existing tag-9
payload. Physical identifiers use `(HID page << 16) | usage`, with Keyboard/
Keypad page `0x07`. Carbon virtual positions are mapped explicitly for ANSI,
ISO, JIS, keypad, function, navigation and modifier keys. UIKit supplies a
Keyboard/Keypad HID usage directly. Unknown physical keys use zero; the macOS
Fn event has no invented HID assignment and currently uses unknown identity
while retaining the Function modifier flag.

Logical character identifiers are unmodified Unicode scalars after NFC
normalization. Multi-scalar results are unknown, not truncated. Known
non-character HID keys use `0x110000 + physical`, independently of platform
character spelling. Other empty/control/native-function character values also
use that physical identity when available. Unknown physical and logical values
remain zero. This is a native contract, not Flutter logical-key numbering.

Apple's [AppKit charactersIgnoringModifiers](https://developer.apple.com/documentation/appkit/nsevent/charactersignoringmodifiers)
retains Shift, whereas [UIKit's property](https://developer.apple.com/documentation/uikit/uikey/charactersignoringmodifiers)
ignores it. The AppKit mapper asks for characters with an empty modifier set
when Shift or Caps Lock is present. Held physical keys keep the logical
identity established on initial down across repeat and release; reset clears
that ownership for the future capture lifecycle.

Modifier bits 16–23 retain Apple Caps Lock, Shift, Control, Option, Command,
numeric keypad, Help and Function flags. AppKit device-specific left/right
bits determine modifier edges but are removed from the emitted modifier mask.
Caps Lock uses the stateless physical-key bit for down/up, independently of
its toggled Caps Lock state. Non-key NSEvents are rejected before accessing
key-only properties, since even reading `keyCode` on a mouse event raises an
AppKit exception.

Seven tests pass in 0.045 seconds after behavioral failures for missing
mapping, non-character platform spelling and Caps Lock edges. They exercise
real NSEvent objects, native layout translation, both Shift keys, Caps Lock,
Unicode normalization, repeat/up identity and reset. Another path in the same
seven tests encodes four mapped native packets, sends them to the actual
OCaml keyboard handler and verifies the complete returned history. These are
native packet tests; no global event posting or UI automation is involved.
The full module and retained App entrypoints typecheck for physical iOS 18;
all three platform checks pass in 20.689 seconds. UIKit hardware delivery has
not been observed.

The related event/queue/key run passes 12 tests in four suites in 0.059 seconds,
and OCaml all/test/format/install passes. That mapping checkpoint did not run a
full Swift suite; its complete Gallery acceptance test still failed on the
unimplemented keyboard node. The later macOS listener checkpoint removes that blocker.

At the mapping checkpoint, native capture, KeyboardListener rendering/admission,
listener autofocus, propagation and window/device acceptance were still required.
The later macOS implementation retains the real keyboard and focus nodes and
passes the complete Gallery tree/action test. UIKit capture and physical
acceptance remain required.

## FocusScope

Node 51 now renders within the existing SwiftUI view graph using native focus
state, including focus on the AppKit text-field adapters. No additional hosting
view splits layout preferences or navigation. A scope observes its own focus
and descendant focus; moving between its children preserves the aggregate state.
Nested scopes independently report their transitions to the actual OCaml handler.

The controller gates publication on mounting and the displayed node's identity,
properties, bindings, children, activity and content ownership. It deduplicates
transitions and reconciles current focus after reactivation or handler replacement.
Removed controllers reject further observations. Autofocus waits for presentation,
mounting and enablement and is consumed after successful native focus; reactivation
does not steal focus. Changing autofocus properties invalidates presentation before
a new request can run. Disabling presentation alone does not resign the native
editor or interrupt composition on each runtime update.

The real OCaml/native-window test first failed on unsupported node 51. A second
behavioral failure exposed an autofocus request running before updated properties
were presented. All six focus tests now pass in 2.122 seconds, covering nested
field-editor transitions, deduplication, hidden/inactive sessions, layout-anchor
preservation, native autofocus, lifecycle handling and atomic wire rejection.
The related text-field/focus tests pass 17 tests in four suites in 9.312 seconds.
All three platform checks pass in 20.913 seconds, including the whole module and
retained App entrypoints for physical iOS 18. OCaml all/test/format/install passes.

Physical iOS focus behavior, external keyboard input, IME acceptance and full
Gallery acceptance remain outstanding. At the FocusScope checkpoint,
KeyboardListener node 53 still had no renderer; the later macOS capture
checkpoint implements it without bypassing the node. The desktop connection continued
to report a locked Mac, and the separate iPhone preflight still failed because
DDI services were unavailable. No new screenshot or source/SDK publication is
claimed. Evidence: `_build/validation/swiftui-focus-scope.json`.


## macOS KeyboardListener

Node 53 now validates its two properties and single key binding, renders in
SwiftUI's existing focus/layout graph and captures native AppKit events through
one local monitor owned by the render tree. It observes only windows containing
mounted, focused, presented listeners. The deepest focused listener receives each
mapped event first; ignored events reach containing listeners and native controls.
An accepted handled event stops propagation, including native text insertion.
Queue failures preserve the session's existing fail-fast behavior.

Capture maps each event once per window and retains the logical identity through
repeat and release. Binding, presentation, mount, focus or responder changes retire
the held sequence. Repeats and releases without an owned down event are ignored. Ownership belongs
only to listeners that accepted the down event; a rejected listener cannot join
the sequence later, and rejecting a repeat retires that listener from the sequence.
AppKit field editors are shared between fields, so responder identity includes
the editor's delegate. A native first-responder observation also clears held keys
when focus leaves and returns before another key event arrives. Removing every
listener removes the monitor; disposed controllers reject late callbacks.

The real OCaml/window tests dispatch NSEvents through NSApplication in their own
process. They verify inner-to-outer callback history, native text insertion for
ignored keys, prevention for handled keys, down/repeat/repeat/up, autofocus,
hidden-session and unrelated-window isolation, and retained layout anchors.
Additional native-window tests cover shared field-editor reuse, immediate focus
clearing, rapid refocus, handler replacement, disposal and malformed wire frames.
These checks do not post global keyboard events or change system settings.

The initial tests fail on unsupported node 53. Further behavioral failures expose
shared-field-editor ownership, rapid-refocus and rejected-listener ownership
bugs; all are fixed. The targeted
run passes 19 tests in four suites in 6.502 seconds. It includes the complete
macOS Gallery tree/presentation/toolbar test, which now passes in 0.321 seconds.
That test uses a native-card registration fixture and does not verify the App's
own native card UI or every control's appearance/interaction.

At this macOS checkpoint, UIKit raw capture was still missing and NodeStore
rejected node 53 on iOS. The following UIKit checkpoint removes that source-level
restriction; device acceptance remains outstanding. Full physical iOS/iPad/macOS keyboard, IME, modal and
accessibility acceptance remains required. Evidence for this checkpoint is in
`_build/validation/swiftui-keyboard-listener-macos.json`.


The final complete serial Swift run passes 440 tests in 97 suites in 414.612
seconds (`/tmp/swiftui-keyboard-listener-final-full.log`). The completion wrapper
requires Swift Testing's successful completed xUnit report; a successful process
exit alone is insufficient. OCaml all/test/format/install and strict Swift format
lint also pass. The macOS native-window tests use native AppKit dispatch, but no
new physical-device keyboard input or application screenshot is claimed.

## UIKit capture and shared sequence ownership

`NativeKeyboardRoute` now supplies the same admitted-listener ownership rules to
AppKit and UIKit. `NativeKeyboardPresses` deduplicates the observer/interceptor
callbacks by native press identity, timestamp and phase. A new press object
starts a new down sequence; a release from an older object cannot finish it.
Rejected listeners cannot join repeats or releases. Focus, responder, binding
and presentation changes retire listener ownership; cancellation does not
manufacture an OCaml key-up event.

UIKit mounts a noninteractive UIView anchor in the existing SwiftUI focus graph.
Each window containing listeners owns two recognizers: a passive observer keeps
receiving ignored releases, while an interceptor ignores unhandled presses and
cancels handled presses before native responder delivery. Native press types are
read from keyboard-bearing events rather than using undocumented numeric types.
HID usage, characters and modifiers come from UIKey. Repeated began callbacks for
the same held press become repeats; analog force changes do not. Actual hardware
repeat delivery and press-type filtering order remain device-verification items.

[Apple's ignore-press contract](https://developer.apple.com/documentation/uikit/uigesturerecognizer/ignore(_:for:)-8qqor)
states that ignored presses are not cancelled on the associated view. The
[press timestamp](https://developer.apple.com/documentation/uikit/uipress/timestamp)
identifies the last native mutation. These contracts inform the implementation;
they do not substitute for executing it on an iPhone/iPad with a keyboard.

Source-level acceptance is separate from native acceptance: the complete module
and eleven App entrypoints compile for iOS 18, and node 53 is now wired through
NodeStore, RenderTree and BonsaiSession. The focused macOS/shared run passes 28
tests in eight suites (7.011 seconds), including the actual complete Gallery
staging/dispatch test and AppKit text editing. The new utility tests first failed
for missing dispatch and incorrect new-press/old-release ownership. No UIKit
hardware event, physical IME, modal shortcut or VoiceOver success is claimed.

Gallery's development-signed iOS Release App builds with the new capture source
and passes signature, provisioning and complete-object validation. The Release
optimizer crash in nested dictionary capture was removed by binding the delivery
closure before routing; optimization remains enabled. Source/artifact hashes
and logs are in `_build/validation/swiftui-uikit-keyboard.json`. Other example
App binaries retain their earlier checkpoint provenance.
