# Retain Native Field Focus Through Acknowledgment

## Problem

The Journal user reports that tapping the E2EE SecureField briefly opens the
iPhone keyboard, which immediately closes. NativeTextFieldController currently
disables and resigns the control whenever content admission becomes inactive.
Unlike the multiline editor, it does not distinguish a mounted native ancestor's
unacknowledged update from actual hiding/removal. The session also allows only
multiline continuous text events through that retained-focus admission path.

The public pure Journal password state and editing events do not execute native
responder acquisition or the AppKit/UIKit availability setters. Reproduce through
the existing native hosted ancestor fixture using public text_field/secure_field
construction, valid updates and acknowledgment. Do not add persistence, transport
or duplicate application reducer regression tests for this responder defect.

## Decision

Retain single-line native editing focus through an eligible mounted ancestor
update, using the same admission boundary already used by multiline editing.
Allow only continuous text input through this retained-focus path.


First demonstrate the same focus loss with the current single-line controller
under a native parent update. Extend mounted focus retention to plain and secure
fields through the session's existing mounted-child eligibility checks. Keep
host-disabled, removed, hidden, inactive and disposed controls fenced. Continuous
text edits may retain the existing editing session during acknowledgment; submit
and unrelated action events retain strict admission. Preserve read-only input
protection and one-shot autofocus.

## Alternatives considered

### Repeatedly request focus after each update

Rejected: it masks unwanted resignation, can flicker the keyboard and may steal
focus after intentional dismissal.

### Disable generation and presentation admission

Rejected: callbacks from removed pages and expired sessions must remain invalid.

## Acceptance criteria

- A native hosted regression reproduces lost focus across a real native parent
  update for plain and secure fields before production changes.
- After the fix, focus and consecutive input survive the pending update and
  acknowledgment, and the actual OCaml handler receives the edit.
- Actual child hiding, inactive sessions and disposal still release focus and
  reject editing; existing one-shot, disabled/read-only and text protocol tests
  remain green.
- Both AppKit and UIKit branches compile. macOS native evidence is explicit;
  physical iPhone keyboard acceptance remains pending device availability.
- No protected spec OCaml, Dune or public protocol changes are needed.

## Consequences

Plain and secure fields no longer resign solely because their mounted parent is
awaiting acknowledgment. Existing lifecycle and availability guards still apply.
No application password state, storage behavior or public protocol changes are
required. Physical iPhone keyboard acceptance remains a separate pending check.

## Risks

- Retaining focus must not admit submit actions or edits from detached controls.
  Use the existing retained mounted-path check, not broad acknowledgment bypass.
- The application also has an autofocus scope around the secure field. Inspect
  its independent behavior if the controller repair does not resolve the real
  unlock surface.

## Questions

- None. The user explicitly requested repair of the password focus behavior.

## Implementation evidence

The hosted AppKit regression reproduces the defect for plain and secure fields
before repair, including actual first-responder loss and disabled input. The
controller now retains existing editing focus only for eligible mounted content,
and the session admits its continuous text events during acknowledgment. Submit
admission and detached/inactive/hidden controls remain strict.

The focused suite passes 26 tests in six suites. The installed Swift host tool
was refreshed and the Journal generic iOS Release build passes without signing.
Evidence, red/green logs and working-tree source hashes are in
`docs/test-reports/2026-09-17-native-field-focus/`. The macOS application also
builds and opens its isolated encrypted graph. Physical iPhone keyboard acceptance
remains pending device availability; this decision does not claim that acceptance.
