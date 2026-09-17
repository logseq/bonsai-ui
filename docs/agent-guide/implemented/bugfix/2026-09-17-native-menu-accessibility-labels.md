# Native Menu Accessibility Labels

## Problem

The physical iPhone Journal account Menu opens and visually displays Settings,
Diagnostics, Switch graph and Sign out. XCTest's accessibility snapshot exposes
four empty cells with no corresponding buttons or labels, so the existing native
acceptance cannot select Diagnostics by name. The menu opener lives under a
toolbar iconOnly label style; entry labels are bridged SwiftUI Label subtrees.

The owner is the native Menu's label/accessibility composition. Public pure
application events and valid NodeStore menu state cannot produce UIKit's
accessibility tree. Keep the existing iPhone UI acceptance as native evidence;
do not add a duplicate reducer, effect or transport regression.

## Decision

Let native Label own accessibility for symbols in its icon subtree. NativeSymbolView
currently applies accessibilityHidden(true) unconditionally; in a UIKit Menu this
suppresses the enclosing action's accessibility even when its title is visible.
Pass the native Label icon context through SwiftUI's environment and omit the
hidden state there, while standalone symbols remain decorative. Preserve native
visual labels and existing action-generation admission.

A disposable SwiftUI diagnosis isolated the behavior: nested Label with a hidden
SF Symbol produces empty menu cells even with hit testing enabled, combined
semantics or an explicit action accessibility label. Plain Button, plain Label
and the same nested Label without the hidden icon expose Diagnostics normally.
This is diagnostic infrastructure, not a copied production regression. The
unchanged full-application native acceptance remains the final iPhone check.

## Alternatives considered

### Force titleAndIcon label style

The physical rerun still produced empty cells. That unproven change was removed.

### Coordinate-based menu activation

This may activate a visible row but conceals missing native accessibility.

### Flatten all native labels into text

This would discard structured native label semantics. Prefer correcting the
native composition before introducing another label representation.

## Acceptance criteria

- Existing device acceptance first fails to locate Diagnostics in a visible menu.
- The physical menu exposes named native actions and selecting Diagnostics
  reaches the existing application-owned inspection screen.
- Retained menu snapshot and retired action tests continue passing.
- No protected OCaml interfaces or Dune changes are needed.

## Consequences

Native Label owns icon accessibility; standalone symbols remain decorative.

## Risks

- Native Label must continue to provide the action title without separately
  announcing its decorative icon. Standalone symbol behavior stays unchanged;
  verify existing native label appearance/action tests and the iPhone menu.

## Questions

- No unresolved user decision. Native accessible menus are already part of the
  authorized iPhone standardization scope.

## Validation infrastructure note

The existing retained-menu regression's one-shot dispatch cancellation could
leave AppKit in its modal menu tracking loop. A process sample confirmed the
blocked performClick. Its cancellation now runs in eventTracking mode against
the current popup menu and is invalidated after the click returns. All four
focused menu tests pass. This changes test cleanup only; the test still opens
the actual retained native menu and verifies its original Pinned item.

## Implementation outcome

The unchanged physical iPhone acceptance passes with zero failures after the
icon-context correction. Account menu exposes all four named actions; selecting
Diagnostics opens its screen and Close returns to the journal. Seven existing
label/symbol tests pass, as do the four focused menu tests. The consumer's signed
Release iPhone build and installation succeed. Evidence is archived in the
logseq_journal standardization report as batch17-physical-icon-accessibility.log,
batch17-physical-account-menu-accessibility.txt and batch17-device-acceptance.swift.
The titleAndIcon hypothesis was reverted. No OCaml interfaces or Dune files were
changed for this repair. Full screen-reader and device settings coverage remains
part of the consumer's broader acceptance, not a claimed result of this test.
