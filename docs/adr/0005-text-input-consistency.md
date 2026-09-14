# ADR 0005: Optimistic local text input with canonical OCaml state

- Status: Accepted
- Date: 2026-07-25

## Context

Flutter must synchronously cooperate with platform IMEs, selection handles,
caret animation, and composing sessions. Sending every edit to OCaml before
local display would break input latency and composition. Treating Dart text as
business truth would violate the framework boundary.

## Decision

Flutter owns the live editing session and applies local edits optimistically.
OCaml owns the canonical document and accepts, corrects, or force-replaces
edits using explicit session, local, base-document, and document revisions.

Text is UTF-8 on the wire. Selection and composing offsets are UTF-16 code-unit
offsets. OCaml provides checked `Text_index.Utf16` conversions.

An acknowledgment never writes an unchanged value back to the controller.
Ordinary OCaml updates older than the current local revision are ignored.
Corrections apply only to the matching session and revision. A force
replacement creates a new session and intentionally supersedes local state.
Live composing ranges are preserved unless the matching correction requires a
change.

Controllers and focus nodes belong to `RendererResourceStore` and are keyed by
runtime epoch and node ID.

## Consequences

Typing latency does not depend on FFI or Bonsai stabilization. OCaml remains
the persistent semantic authority. The protocol is more explicit than a
simple controlled `TextField`, but stale-update behavior and IME composition
become testable and deterministic.

