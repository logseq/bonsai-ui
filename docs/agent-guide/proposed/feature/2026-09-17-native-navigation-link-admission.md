# Native NavigationLink admission for registered views

## Problem

Registered native views can display core-owned children, but cannot use a native
NavigationLink to request an application-owned route. NavigationStack currently
accepts native pops only. Journal and Favorites still use Buttons for navigation.

## Proposal

Expose a typed navigationLink helper on BonsaiNativeContext. It renders SwiftUI
NavigationLink(value:) within the existing Bonsai NavigationStack and submits the
supplied native-view event when SwiftUI requests the appended value. The existing
OCaml route remains authoritative: only a committed destination enters the path.
There is no extra stack, placeholder destination, parallel domain router or
protocol change. A request retains the presented event snapshot and originating
stack/path. Stale, disposed and wrong-stack requests are rejected. Admission
failure leaves navigation immediately retryable. An admitted request prevents
another navigation request until its exact native event is pumped; completion
releases admission even when the application does not change the route.

This bridge extension is within the user's confirmed native iPhone UI design.
It does not involve the deferred Undo/Redo capability or protected OCaml specs.

## Alternatives considered

### Keep Buttons or add a decorative chevron

Rejected because the approved design requires actual native NavigationLink.

### Let the native link create a second destination stack

Rejected because route ownership, system Back and child presentation would diverge
from the core-owned navigation graph.

## Acceptance criteria

- Public typed native contexts can construct native NavigationLink labels/events.
- Pure navigation-owner tests cover accepted and rejected admission, exact event
  settlement, unchanged core route, duplicate, stale-path, wrong-stack and disposed
  requests. Existing native Back policy and stale-binding tests remain green.
- A hosted native link dispatches the supplied event and the committed destination
  appears in the same stack, with native Back still functional.
- Journal and Favorites use the helper and retain stable row identities.
- Swift package tests and the iPhone app build pass. Device interaction acceptance
  is tracked separately; source inspection is not device evidence.
- No Dune files or protected spec OCaml files change.

## Risks

- A SwiftUI path setter must translate a link intent before the next core render;
  timing must be verified with a hosted link, not inferred from controller tests.
- Settlement must match the native event in the pumped batch; unrelated events
  must not release a pending link or make a stale callback current.

## Questions

- None. This implements the already approved native NavigationLink requirement;
  no additional product decision or protected-interface authorization is needed.


## Implementation evidence

The typed context helper, native stack admission and exact event settlement are
implemented. Journal and Favorites consume the public helper. The native owner
RED tests and hosted-control RED tests were observed before their corresponding
fixes. A real OCaml fixture verifies two successive native activations when the
first leaves the route unchanged; old context callbacks expire and native Back
still works. The focused navigation run passed 13 tests.

SwiftUI's internal optimistic push did not reproduce through the controller's
pure path state. Actual hosted activation reproduced an empty destination after
rejection or unchanged-route completion. The controller now republishes its
controlled path after the setter and matching event completion; it never commits
an intent as a destination. The narrow hosted regression is required for that
framework-owned behavior; no persistence or transport regression duplicates it.

The full 553-test Swift run has unrelated baseline collection failures (28 issues
across two wheel/measurement families), reproduced on baseline commit
acdb2c2fd06a84f05b012989191235da5a24b477. A menu/dialog test failed in the full run
but passes in isolation on baseline and current source. The full-suite acceptance
criterion is therefore not marked passed and this decision remains proposed.
The iPhone Release build passes; physical-device acceptance remains separate.
Detailed logs are retained in the consuming Journal repository under
`docs/test-reports/2026-09-16-native-swiftui-standardization/batch7-*`.

## Physical interactive Back follow-up

The physical Journal row opens a native Block destination and explicit Back works.
An edge-swipe pop visually reveals the root, but its Capture/Account controls no
longer activate. Existing pure controller request and route-reducer events settle
the pop normally; they do not reproduce SwiftUI retaining an earlier path Binding
through native interactive transitions. The physical regression now requires
opening Capture after the edge-swipe, not merely seeing its toolbar button.
Investigate the platform binding lifetime separately from retained action
snapshots; keep route-prefix, canPop, inactive, replacement and disposed fencing.

The first repair gives the persistent native stack binding a current action
snapshot at dispatch, while explicit retained snapshots keep their existing
replacement-path fence. Thirteen focused navigation tests pass, including stale
path, protected destinations, rejected pops, links and matching event settlement.
The rebuilt signed consumer is undergoing the unchanged physical follow-up check.

The native-binding hypothesis does not fix the physical failure. The unchanged
post-gesture Capture check remains red. The attempted wrapper is removed; inspect
actual native route and mount admission before another production change.

LLDB confirms the native route did settle to an empty path. Input was blocked by
Chrome's missing child mounts, not navigation binding admission. The separate
retained-child-mount decision owns the actual fix and deterministic owner test;
no navigation implementation change remains from this investigation.
