# Text input consistency

Text input is a two-authority protocol: Flutter owns the live IME session and
local presentation, while OCaml owns the canonical document and business
semantics. Neither side blindly overwrites the other.

## Offset convention

Wire selection and composing offsets are UTF-16 code-unit offsets because that
is Flutter's `TextSelection` convention. Text bytes are UTF-8. OCaml uses
`Text_index.Utf16` conversion functions and never treats a UTF-16 offset as a
UTF-8 byte index.

## Revisions

Each text field carries:

- `session_id`, changed when the local editing session is replaced;
- `local_revision`, incremented by Flutter for every local edit;
- `document_revision`, incremented when OCaml accepts or replaces canonical
  content;
- `base_document_revision`, the canonical version on which a local edit was
  made.

An edit event contains the node ID, all relevant revisions, UTF-8 text,
selection, and composing ranges.

## Normal local edit

Flutter applies an edit to `TextEditingController` immediately and emits the
typed edit event. OCaml validates it and returns an acknowledgment for the
local revision, optionally with a new canonical document revision. An
acknowledgment containing the same content does not write back to the
controller.

This local echo keeps typing and IME candidate interaction independent of the
OCaml round-trip latency.

## Corrections

OCaml may return:

- `Ack`, accepting a local revision without a controller write;
- `Correction`, replacing content when the response is based on the current
  session and local revision;
- `Force_replace`, intentionally starting a new editing session for a
  programmatic replacement.

A normal update older than Flutter's current `local_revision` is discarded.
A correction does not destroy a live composing range unless it explicitly
targets the matching edit. A force replacement creates a new session and
clears incompatible pending local edits.

## Resource lifecycle

`TextEditingController` and `FocusNode` live in
`RendererResourceStore` under `(runtime_epoch, node_id)`. Keyed reorder
preserves them. Kind replacement, node drop, full epoch replacement, and
runtime shutdown dispose them exactly once.

`RendererResourceStore` synchronizes against the committed `NodeStore` epoch,
full-snapshot generation, node IDs, and kinds. `TextInputHost` borrows the
resource for its node; it does not recreate or dispose the controller during a
compatible property update or keyed reorder.

## Implemented update rules

The renderer tracks the current session, local revision, and last accepted
document revision beside the controller:

- every controller edit, including selection or composing changes, increments
  `local_revision` and emits a TextEdit payload immediately;
- Ack advances the document revision but never writes the same value back to
  the controller;
- Correction writes only when its session matches and
  `accepted_local_revision` equals the current local revision;
- an older Correction may advance known canonical metadata but cannot replace
  newer local text;
- ForceReplace or a new session replaces text, selection, and composing state
  and resets the local revision to the accepted value;
- an older document revision is ignored unless a new session explicitly
  forces replacement.

Remote controller writes are guarded and cannot recursively emit TextEdit.
FocusNode changes emit FocusChanged, and Flutter's input action emits
TextSubmit with the current string.

Each `TextInputHost` callback also retains the frame revision from the
`NodeHost` build that installed it. If a new frame is committed immediately
before Flutter rebuilds the host, a local edit can still come from the prior
callback and handler ID. When that ID was replaced, the event is tagged with
the prior revision, and the OCaml handler registry keeps exactly one preceding
frame so the edit reaches the matching handler instead of a replacement. When
the handler is unchanged, the callback uses the latest store revision so it
remains valid across unrelated frames.

## Current verification

Pure tests cover ASCII, Chinese, Japanese, Korean, emoji/surrogate pairs,
combining marks, selection, composing, paste, delete, submit, focus switching,
programmatic correction, force replacement, stale correction, rapid local
edits, callback/store revision races, keyed reorder, node drop, and full
reset. The native integration test sets two Chinese/emoji composing values
before one runtime step; OCaml/Bonsai accepts the latest local revision and
returns one Ack frame without rewriting the controller.

These tests drive Flutter's `TextEditingValue` and test text input channel.
They do not yet automate a physical macOS IME candidate window, so
device-level Pinyin/Japanese/Korean IME behavior is verified structurally but
is not claimed as a supported-platform result.

## Required tests

The shared model and integration suites keep these cases as required
regressions; supported-platform status still additionally requires the release
packaging and device matrix.
