# Preserve Native Menu Label Snapshot

## Problem

The Journal iPhone application crashes with EXC_BREAKPOINT in NativeMenu.label
while SwiftUI builds a deferred menu item. The view retains RenderMenu entries
but resolves their label indices against the live RenderNodeState.children.
A later valid tree commit can replace or retire that array before an old native
menu closure is evaluated. Validation of each committed tree cannot protect a
view that mixes two revisions.

## Decision

Capture the menu label children together with the menu configuration when
constructing NativeMenu. Deferred label rendering uses that snapshot. Existing
controller generation fencing remains responsible for rejecting retired actions.
Do not introduce bounds fallbacks, drop items or weaken tree validation.

This implements the already authorized Journal native iPhone menu and lifecycle
requirements. No product decision, protected OCaml interface or Dune change is
needed.

## Alternatives considered

### Guard missing children and draw empty labels

This conceals a mixed-revision view and silently removes labels. Retaining one
consistent presentation snapshot addresses the ownership defect directly.

### Change the graph or menu command owner

The defect occurs after valid tree publication in deferred SwiftUI rendering.
Graph reducers and menu command admission do not own native label lifetimes.

## Acceptance criteria

- Reproduce using valid public tree commits and an actually retained native menu
  view, without fabricating invalid node data or duplicating renderer logic.
- Retired or reduced menu label arrays do not crash deferred native rendering.
- Existing retired menu action and invalid-tree checks remain passing.
- Rebuild the SDK and Journal host, then rerun the physical iPhone navigation
  acceptance to distinguish this crash from any remaining input defect.
- No Dune or protected spec OCaml files change.

## Consequences

- A retained native view keeps label node references until SwiftUI releases that
  view. This is bounded by the existing native presentation lifetime; it does not
  retain obsolete event admission or add compatibility paths.

## Implementation evidence

NativeMenu captures its label children in its initializer. The hosted AppKit
regression retains the real NativeMenu, commits a valid smaller menu, and opens
the actual NSPopUpButton. Before the fix this trapped with Index out of range;
afterward the same regression passed, including the retained Pinned item.
The focused menu suite passed four tests, the actual OCaml menu runtime test
passed independently, and five navigation tests passed.

The locally pinned SDK was reinstalled and the Journal iPhoneOS Release build
was signed, installed and launched on the USB-connected iPhone 13. The native
XCTest navigation run no longer crashed in NativeMenu. Favorites still failed
to navigate, independently traced to stale native child mount identity and
tracked in 2026-09-17-native-child-mount-identity.md. No protected OCaml or
Dune files were changed by this repair. Batch 15 evidence is recorded in the
Journal standardization test report, including the crash and red/green logs.
