# Retain child mounts across native parent visibility

## Problem

After interactive Back on iPhone, Journal's toolbar is visible but its actions
are rejected. LLDB confirms the controlled navigation path is empty and the tree
contains only the root route. BonsaiSession.activate reaches the correct enabled
Capture node but isInActiveContent returns false. The native Chrome owner retains
body/title child mounts but has lost toolbar child mounts.

NativeViewInstance.unmount clears all child mount counts when its parent mount
count reaches zero. UIKit retains toolbar children across navigation without
replaying their appearance callbacks; their independent mount lifetimes have not
ended. Clearing those counts creates an unbalanced lifecycle.

## Decision

Let each child mount/unmount callback own its count. Parent unmount still fences
all child input through mounted > 0 and invalidates event generations, but does
not erase independent child counts. Disposal clears them. A child actually
removed while its parent is hidden remains removed on return.

The production state owner is NativeViewInstance. Its deterministic mount,
unmount, child mount/unmount, presentation and disposal interface reproduces the
missing count without SwiftUI, transport or application reducers. Add only that
owner regression. Retain existing hosted tests and physical UI acceptance.

## Alternatives considered

### Renew the native navigation Binding

Rejected after the physical regression still failed. LLDB shows the route itself
already settled correctly. The speculative wrapper was removed.

### Remount the toolbar on every return

Rejected because it conceals unbalanced ownership and replaces native control
identity unnecessarily.

## Acceptance criteria

- Parent unmount rejects child input; remount restores independently mounted
  children without requiring a duplicate child appearance.
- Child removal while hidden remains rejected after the parent returns.
- Old event generations, duplicate parent mounts and disposal remain fenced.
- Existing hosted child identity/omission and navigation tests pass.
- Physical edge-swipe Back allows opening Capture afterward.

## Consequences

Parent visibility and child mount lifetimes remain independent. Parent mount
state continues fencing input without losing independently retained toolbar
children. Existing child disappearance and disposal perform cleanup.

## Risks

- Retaining counts must not admit hidden parents; mounted > 0 remains mandatory.
- Each actual child disappearance must keep its existing balancing callback.

## Questions

- None. This repairs the approved native iPhone navigation behavior; no product
  choice or protected interface change is needed.

## Validation

The deterministic owner regression fails two remount assertions before the
one-line production removal and passes afterward. Nineteen focused native-view,
editor and navigation tests pass. Additional existing native resource lifecycle,
child omission, Sheet and Popover tests pass. The signed physical iPhone test
passes Append input, rotation, Close/reopen, draft cleanup, edge-swipe Back and
opening Capture afterward. Earlier failed attempts and LLDB diagnosis are retained
in Journal's batch 20 report. No navigation Binding change remains; no protected
OCaml, Dune or compatibility paths changed.
