# Text Editor Autofocus

## Problem

Journal Capture and Append wrap a multiline native editor in an autofocus scope.
The scope receives container focus without making UITextView first responder:
physical iPhone XCTest observes no keyboard five seconds after presentation.
The public single-line field has explicit autofocus, but text_editor does not.

The native text controller owns first-responder state. Public pure Journal events
and valid tree snapshots reproduce the requested sheet and editor state, but do
not execute native responder acquisition. Test at the native hosted controller
and existing physical acceptance boundaries; do not duplicate application reducer,
persistence or transport regression coverage.

## Decision

Add an optional autofocus argument, default false, to text_editor. Encode it as
an editor-specific property after its shared editing payload. Use the existing
presentation admission to request native first responder once, after mounting,
while enabled and editable. Changing false to true requests again; canceled,
disposed or inactive editors cannot acquire focus. Re-enabling presentation after
success must not steal focus. Capture and Append use explicit editor autofocus
and remove the autofocus scope wrapper. Keep revisioned editing unchanged.

## Alternatives considered

### Redirect all focus scopes into their first editor

Rejected: a focus scope may intentionally focus its container and can include
multiple controls. Match the explicit single-line editor API instead.

### Synthetic tap in the UI test

Rejected: it conceals missing keyboard presentation in the actual product flow.

## Acceptance criteria

- The existing physical Capture keyboard check fails before the change and passes
  afterward; Close and reopening preserve unsaved input and focus behavior.
- Native hosted checks cover presentation/mount gating, disabled and read-only
  editors, one-shot acquisition, cancellation, renewed request and disposal.
- The required new editor property encodes and decodes without legacy fallback.
- Existing text editing and single-line field checks continue passing.
- No protected spec OCaml or Dune changes are required.

## Consequences

The native editor autofocus and dismissal acceptance is complete. Broader Journal
iPhone UI standardization, including accessibility and performance, remains open.

## Risks

- Responder acquisition before presentation or after disposal can steal focus;
  use the same session admission as single-line fields and retry when attached.
- The wire property is intentionally incompatible with old editor frames.

## Questions

- No unresolved user decision. Coherent Capture/Append focus is already part of
  the authorized native iPhone standardization scope.

## Physical follow-up

The first complete iPhone build still loses focus after acquiring it. LLDB shows
an enabled/editable/presented controller with its autofocus request consumed,
followed by setContentActive(false) from RenderTree.commit presentation
reconciliation. Its native ancestor has an unacknowledged properties update;
UITextView.setEditable(false) resigns the focused editor. This is input-admission
fencing, not native disappearance. Keep the currently focused, mounted editor
editable across native ancestor acknowledgment while continuing to reject
unadmitted input. Native child omission, modal dismissal, application inactivity,
disabling and disposal must still release focus. A native OCaml fixture and
hosted session check exercise the actual property update and acknowledgment;
no duplicated pure reducer, persistence or transport tests are added.

The physical sheet still loses focus after the native-container retention repair.
Sheet and Popover currently key the entire content by the action generation,
which remounts native editors whenever the dismissal binding changes. Separate
native content mount identity from action admission generation. Keep generation
fencing for obsolete dismissal bindings, track the actually mounted content
identity, and renew admitted appearance without replacing the SwiftUI subtree.
A hosted sheet regression checks the same native scroll view/editor/window and
focus across a valid binding update, plus rejection of the old dismissal binding.

The existing rejected native dismissal check also requires separating SwiftUI's
retained presentation Binding from action-generation snapshots. The platform
binding remains valid for that presentation's lifetime and dispatches through
current admission; retired presentations and explicit old action snapshots cannot
dismiss a replacement. Actual dismissal restoration receives a new presentation
identity. All 15 focused editor, Sheet, Popover and native session tests pass.
Physical iPhone verification remains pending.

## Continuous editing follow-up

The unchanged physical keyboard check now passes. Continuous native typing then
loses characters before draft reopening (expected Native draft check, observed
Naiedatcek). Pure Journal Capture edit admission accepts increasing local revisions
through its public Edit events; it does not execute native input rejection during
ancestor presentation acknowledgment. The native controller and BonsaiSession
own this boundary. A mounted, focused editor with the same editing session must
continue revisioned edits during ancestor acknowledgment, while ordinary actions
remain fenced. Hidden content, modal blocking, inactive sessions, disabled and
read-only editors must continue rejecting input. Extend the existing hosted
native session reproduction to verify uninterrupted native typing and delivery;
retain the physical acceptance as the consumer verification.

## Interactive dismissal follow-up

Physical continuous typing and explicit Close/reopen now preserve the complete
draft, Task selection and keyboard. Drag dismissal crashes with Swift exclusivity
violation inside SheetBridge.preferencesDidChange. The crash stack shows
nativeBinding.set -> requestDismissal -> invalidatePresentation -> text view
setEditable/resignFirstResponder -> keyboard layout reentering SwiftUI's active
SheetBridge mutation. Pure state transitions and AppKit dismissal do not execute
UIKit keyboard/SheetBridge reentrancy. Keep the existing physical draft acceptance
as the narrow regression. Dispatch a native dismissal after the current platform
callback returns, retaining both its presentation identity and captured action
generation so obsolete queued gestures cannot dismiss a replacement.

## Implementation

Implemented the opt-in editor API and mandatory wire flag, one-shot native
autofocus, stable native/modal content identity, continuous revisioned editing
through ancestor acknowledgment, and deferred native dismissal with captured
presentation/action fencing. Journal Capture and Append use explicit autofocus.

## Validation

- Native editor/wire/field regressions and SDK Dune build/tests pass.
- Eighteen focused editor, Sheet, Popover, native session and actual OCaml text
  event tests pass; seven affected modal/session tests pass after deferred dismissal.
- Physical iPhone 13, iOS 26.6.1: unchanged keyboard check passes; the full draft
  acceptance passes continuous input, Task intent, explicit Close/reopen, drag
  dismissal/reopen, cleanup, native Block back and Settings dismissal.
- Physical evidence is recorded in the Journal implementation ledger, batch 18,
  with failed attempts retained and final source/binary hashes.
- No protected spec OCaml or Dune files changed. No commit or push performed.

