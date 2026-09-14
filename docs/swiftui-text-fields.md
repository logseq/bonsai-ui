# Native text fields

`View.text_field` and `View.secure_field` are single-line native entry surfaces.
They use NSTextField/NSSecureTextField on macOS and UITextField with native secure
entry on iOS. A SwiftUI representable supplies layout, enabled state and theme
font family. Native controls retain platform selection, focus and secure-entry
behavior.

Both constructors require an accessibility label, a revisioned text snapshot and
edit/submit/focus handlers. Prompt text is optional. Return submits outside marked
text by default; `submit_on_return:false` suppresses that event. Enabled/read-only
state and an optional UTF-8 byte limit follow the existing TextEditor contract.
Supporting text, errors and leading/trailing content belong in ordinary SwiftUI
composition; the fields do not implement Material container variants.

`Text_editing.Keyboard` provides Text, Number, Email, Phone and Url. UIKit uses
its native default, decimal, email, phone and URL keyboards. macOS keeps the
physical keyboard. `Text_editing.Submit_label` provides Done, Next, Search, Send,
Go and Continue for the iOS return-key label. The label does not move focus or
perform an application action; the submit handler owns that behavior. Multiline
entry uses `View.text_editor` and an explicit frame or bounded body.

Autofocus is a one-shot request for a new node or a false-to-true property change.
It waits for an enabled native control in a visible window and a matching,
acknowledged application presentation. Inactive applications and inactive content
cannot consume the request. Disabling a field before its first focus defers the
request. Blurring a field or reactivating the application does not rearm it.

## Protocol and lifetime

The `text_field` and `secure_field` node kinds use IDs 47 and 49. Their first nine
properties share TextEditor's session/revision/value/configuration payload;
label, prompt, keyboard, submit label and autofocus follow it. The full update
mask is 16383. Both are leaves with
required edit, submit and focus bindings and an optional limit event binding.
Separate node kinds make a plain/secure change replace the native control.

RenderTree retains controllers by node identity. It validates incoming snapshots
against local revisions before publishing any node, applies acknowledgments
without overwriting a newer draft, and disposes removed or replaced controllers.
Label/prompt changes update the retained native field. BonsaiSession admits input
only from the displayed application generation and matching text session.

Native selection callbacks may occur inside a marked-text mutation. Capture runs
on the next main-actor turn, after the mutation is complete; submission flushes
capture before emitting. An unadmitted edit restores the prior TextSession and
native value. AppKit partial-string validation and UIKit delegate validation
reject over-limit ordinary edits before installing them. The shared TextSession
also checks completed native values, including composition paths.

## Evidence and remaining work

Actual macOS controls cover plain/secure entry, Unicode edits, acknowledgment,
correction, submission, marked text and UTF-16 selection, read-only/disabled
behavior, native byte-limit rejection, event-admission rollback and disposal.
Renderer tests cover keyed reversal, retained fields, label updates, malformed
frames and rejection of future acknowledgments. Real OCaml runtime tests cover
presentation gating, editing acknowledgment and submission for both field kinds.
Todo uses the public constructor and verifies editing, focus, selection, reversal,
completion, insertion and deletion at narrow and wide window sizes.

Native field nodes also propagate their application enabled state into the
SwiftUI environment. Setting only `NSTextField.isEnabled` is insufficient:
SwiftUI can overwrite it when mounting the representable. The actual Network
window regression covers initial disablement, connection-driven enablement,
Unicode input and disablement after disconnect.

SQLite Worker uses an explicit correction when Add clears the title; keeping
that update as an acknowledgment left the native control showing its old draft.
The real window test verifies that insertion clears the field while retaining
the same native editor. Ordinary subsequent edits switch back to acknowledgment.

The old Material TextField constructor, logical node, wire payload and schema
entry are removed. Gallery, Network and SQLite now use the native field; their
headless helpers recognize native plain/secure fields and multiline editors.
The protocol fixture uses `ocaml_bounded_text_field.hex`; node 103 has no decoder.
The old Flutter renderer tree and example hosts have been deleted.

Search now uses [native field and presentation composition](swiftui-search.md).
Composer surfaces now use native standard extensions and controlled Sheet
composition. The UIKit adapter and its
keyboard/return-key mappings are typechecked for physical iOS 18 but have no
physical-device interaction evidence. macOS composition tests call the native
text-input API; manual IME and VoiceOver acceptance are still required.
Physical editing acceptance remains outstanding. Mail's current application
captures are recorded separately in its screenshot manifest.
