# Native Child Mount Identity

## Problem

A registered native container can render `context.children[0]` without a ForEach.
When a valid tree commit replaces that child, SwiftUI retains the structural
position and does not rerun its appearance callbacks. On the physical iPhone,
the journal feedback container displayed child 20 but its mount table still
contained child 6. New content and navigation therefore rejected input.

The production owner is BonsaiNativeChild's native appearance lifecycle. Valid
NodeStore commits reproduce the replacement state but pure tree/reducer events
cannot execute SwiftUI appearance callbacks. Test the hosted native view only;
do not duplicate this regression in application reducers or transport tests.

## Decision

Key the rendered child subtree by its RenderIdentity so replacement unmounts
the old child and mounts the new one. Preserve the existing generation and
presentation checks. Add a hosted native regression for a directly indexed
child, including same-identity updates, replacement and container removal.

## Alternatives considered

### Key every application call site

Rejected: the SDK promises keyed children and must uphold that promise for all
registered containers, including direct indexing.

### Accept all declared children

Rejected: declared but omitted children must remain unable to dispatch input.

## Acceptance criteria

- A native hosted regression fails on child replacement before the fix.
- Current children mount, retired children unmount, and same-identity updates
  preserve ownership after the fix. Existing registered-view tests pass.
- Rebuild and install the SDK consumer and retest Favorites on the iPhone.

## Consequences

- Replacing identity intentionally resets subtree native state. Updating the
  same identity must not reset it or accumulate mount counts.

## Implementation progress

BonsaiNativeChild now keys its rendered subtree by RenderIdentity. The hosted
regression failed on stale old-child ownership and missing replacement ownership
before the change, then passed unchanged. The existing registered native view
resource/event lifecycle and nine-level nested presentation tests also pass.

The local SDK was reinstalled and the signed Journal iPhoneOS Release build
and USB installation succeeded. An initial physical rerun timed out at the iOS
Enable UI Automation prompt. After that prompt disappeared, the original native
XCTest acceptance passed Favorites navigation, return to Journals, Capture
opening and Close. Rows are enabled and native viewport pagination resumes.
The remaining test failure is a separately tracked native menu accessibility
issue (2026-09-17-native-menu-accessibility-labels.md), not child input admission.
Physical evidence is in the Journal standardization batch 16 report. No protected
OCaml interface or Dune files changed.
