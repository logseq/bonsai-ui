# Native Text Editor

`View.text_editor` is a native, scrollable plain-text editing surface. OCaml
owns the canonical document; a retained AppKit/UIKit controller owns local echo,
selection and composition. SwiftUI mounts the controller through
NSViewRepresentable or UIViewRepresentable. The standalone `text_input` example
now uses this public constructor and a SwiftUI application host; its Flutter
host and configuration are removed.

The editor shares revision ownership with the native field and composer
capabilities described in [text fields](swiftui-text-fields.md).

## Physical UIKit checkpoint

On September 14, 2026, the application-owned Release hosted XCTest passed on a
physical iPhone 13 running iOS 26.6.1 (10.934 seconds). It mounts the actual
`text_input` OCaml application and drives its retained UITextView through
Unicode insertion, two marked-text updates, commit, UTF-16 selection replacement,
focus resignation and unmount/remount. Exact UTF-8 comparisons preserve a
decomposed accent; the surrogate-pair replacement uses both UTF-16 code units.
Composition and selection survive the host's intervening runtime refreshes.
Remounting produces a distinct editor with the initial document.

The test is `examples/text_input/apple-tests/TextInputRuntimeTests.swift`.
After the internal spec-module rename and host development-localization fix,
the same test passes again in 10.716 seconds. The current result bundle is
`/tmp/swiftui-text-input-renamed.xcresult`; original window attachments are
exported under `_build/validation/swiftui-text-input-renamed`.
It invokes native UITextInput methods on the device. System candidate-window
selection, hardware-keyboard propagation and system UI automation remain separate
acceptance checks. These window captures do not include the keyboard's separate
system window. The hosted test also verifies that the built bundle resolves
its development localization to the Xcode project's `en` language.

## Editing values

Text remains exact UTF-8 data. Selection and composition use UTF-16 scalar
boundaries, as native Apple text APIs do. A position inside a surrogate pair
is invalid; a position between combining scalars is valid. Swift compares
editing text by UTF-8 bytes, avoiding String's canonical-equivalence comparison
when detecting a document change. This preserves distinct NFC/NFD input.

A nonempty composing range must contain the entire selection. A caret at
either edge is valid. Empty composing ranges normalize to no composition.
Native tests demonstrated that NSTextView ends composition when
selection moves outside it. The new invariant rejects such contradictory
remote values before native mutation. The OCaml `Text_editing.Value.create`
constructor, outgoing/incoming property codecs, outgoing/incoming edit-event
codecs, and Swift `TextValue` enforce it. No protected ID definition changed.

The value API remains in `ocaml/ui/text_editing.mli`; its description now uses
native Apple terminology. The broader field/search/composer property schemas
still require migration.

## Revisions and local echo

`TextSession` owns one native-local editing session. The OCaml application
continues to own the canonical document. Accepted text, selection and marked
text changes each advance the local revision once. Duplicate native
notifications do not create another revision. Every edit carries the session
identity, local revision and latest known canonical document revision.

| Remote update | Native behavior |
| --- | --- |
| Ack | Advance the known document revision; preserve current local echo and marked text. |
| Correction | Replace only when the accepted local revision equals the current local revision. A stale correction can advance the known document revision without replacing newer input. |
| Force_replace | Replace explicitly while keeping the same session's local revision monotonic. |
| New session | Reset the revision baseline and native editing state, even if text bytes are identical. |

An identical remote snapshot has no effect. An older document revision cannot
overwrite later native typing, including through Force_replace. A non-forced
update acknowledging a future local revision is invalid and leaves the session
unchanged. Counter exhaustion also rejects an edit without partial mutation.
These semantics are recorded in the governing proposal.

## Native control behavior

`NativeTextController` owns an NSTextView on macOS and a UITextView on iOS.
The two implementations share session/revision logic. Native marked-text,
insertion, commit and AppKit selection operations are grouped so intermediate delegate callbacks
do not publish incomplete editing states. Applying a remote value suppresses
local feedback; an Ack does not reset the native text control.

The controller supports editable/read-only/disabled state, a UTF-8 byte limit,
selection reporting, focus changes and Return submission outside composition.
A byte-limit rejection preserves the last valid value and does not advance the
local revision. A native pre-change check rejects excessive replacement text;
the post-change path also bounds marked-text changes. The limit defaults to
the protocol's 1 MiB string budget. It never truncates a Unicode scalar.

Disposal detaches delegates and callbacks and ends marked text. AppKit tests
verify release after draining the native autorelease pool, while retaining the
text view itself to check that obsolete callbacks cannot emit events.

Apple defines the native APIs used to represent composition in
[NSTextInputClient](https://developer.apple.com/documentation/appkit/nstextinputclient)
and [UITextInput.setMarkedText](https://developer.apple.com/documentation/uikit/uitextinput/setmarkedtext(_:selectedrange:)).

## Event transport and verification

The Press-only Swift encoder was replaced directly with `NativeEvent` and
`NativeEventPayload`. Ordered batches currently support Press, Text_edit,
Text_submit, Focus_changed and Text_limit_reached. Each payload has its own
wire representation; string and complete-frame limits are checked before
publication. Other event families still need native encoders. Historical
Dart-named golden input fixtures remain pending producer replacement; the new
Unicode edit encoding matches the existing cross-language fixture byte for byte.

The real-runtime test calls NSTextView's marked-text API, encodes the resulting
edit, dispatches it through the production C/OCaml bridge to the actual example,
and reads back its canonical value and Ack. Repeating the local revision in a
new valid event batch produces successful processing with no frame and no
renderer revision change. A duplicate wire sequence has a different status;
status alone is not used as proof of an unchanged application document.

The tests cover Unicode boundaries and exact bytes, stale/duplicate updates,
force replacement, session replacement, byte limits, selection-only changes,
IME commit, correction, native submission, focus, read-only behavior and
teardown. UIKit sources typecheck for physical arm64 iOS 18; this does not prove
physical keyboard/IME execution. NSTextInputClient method tests do not replace
manual candidate-window and keyboard testing.

## SwiftUI integration and bounded admission

Node 6 carries session identity, canonical and accepted local revisions, update
mode, the complete editing value, enabled/read-only state, Return behavior and
an optional UTF-8 limit. It requires edit, submit and focus bindings; the
limit-reached binding is optional. It has no children. Property updates carry
all nine fields with mask 511. Invalid fields, missing bindings and truncated
payloads fail before publication.

RenderTree retains the controller across property changes and disposes it when
the node or epoch is removed. Rehosting the SwiftUI representable does not
replace the controller. BonsaiSession validates incoming snapshots against the
current local session before committing any node, including rejecting an Ack
for an unissued local revision. Native input uses the displayed node, handler
and revision; input before the first presentation is rejected.

The mixed event queue is bounded by both event count and encoded frame bytes.
Only adjacent complete text edits with the same node, handler, session and
displayed revision can coalesce. Submit, focus and button events preserve
ordering barriers. A rejected edit restores the previous native value and local
revision. Encoding one incoming record establishes its exact byte cost without
re-encoding the whole queue on every edit.

The actual-example integration test mounts an NSHostingView, drives three
marked-text changes through NSTextView, pumps BonsaiSession, and verifies one
canonical document advance acknowledging local revision 3. The native view and
composition survive the Ack. Additional tests verify queue limits and barriers,
atomic snapshot validation, retained identity, read-only updates and disposal.
The standalone macOS bundle links its own OCaml complete object and passes
ad-hoc signing and strict signature verification. A locked desktop still
prevents real-window interaction and screenshot verification.

The editor fills its finite proposed viewport, with a 320 by 120 point ideal
size. macOS uses a transparent NSScrollView; UIKit supplies the UITextView's
native scrolling. Body typography and the configured font family come from the
native environment. External frame and padding modifiers compose around it.

Secure input, keyboard/action traits, field decoration, focus services,
accessibility and physical-device IME verification remain unfinished. Neither
the native input tests nor the standalone build are Mail screenshot evidence.
