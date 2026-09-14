# Expandable Composer Single Surface

## Problem

The modal bottom sheet paints `surfaceContainerLow`, while its nested
`MessageComposer` paints a second `surfaceContainerHighest` Material with an
outline and independent 20dp corner radius. Eight points of outer padding make
both surfaces visible simultaneously. On iPhone this reads as a gray card
placed inside a pale sheet rather than one coherent compose surface.

## Proposal

Make the modal bottom sheet the only visible surface. An internal presentation
scope marks the nested composer as embedded without adding an application or
OCaml-facing style option. In that scope, `MessageComposer` retains its editor,
actions, animation, gestures, and hit testing but uses a transparent Material
with no shape or outline. Standalone `MessageComposer` continues to own its
existing card surface because it has no surrounding surface owner.

Remove the expandable sheet's lateral and top wrapper padding. The composer's
existing 16dp content padding becomes the only horizontal inset, placing the
editor content 16dp from the sheet edge. Keep keyboard/safe-area padding at the
bottom, the sheet's 28dp top corners, and the accessible Material drag-handle
area unchanged.

## Decision

The modal bottom sheet is the only visible surface owner for the expandable
composer. Embedded composer content is transparent and unshaped; standalone
composer presentation remains an outlined card.

## Alternatives considered

### Alternative

Map the nested card colors to the sheet color while retaining its border,
rounded clip, and nested Material. That hides some contrast in one theme but
keeps two surface owners and can reappear under custom color schemes.

### Change every MessageComposer

Removing the surface from standalone composers would make those widgets depend
on undocumented host decoration. Their card surface remains valid outside a
modal sheet, so only the framework-owned embedded composition changes.

## Acceptance criteria

- The modal sheet contains no opaque or outlined Material between the sheet
  surface and the text editor.
- The sheet remains the single `surfaceContainerLow` owner with 28dp top
  corners, scrim, and drag handle.
- Editor content begins 16dp from the sheet's logical horizontal edge rather
  than the previous 24dp double inset.
- Standalone `MessageComposer` retains its `surfaceContainerHighest` card,
  outline, and animated corner radius.
- Focus, keyboard avoidance, safe area, draft preservation, actions, gestures,
  RTL, large text, reduced motion, and native registry behavior remain green.
- A Release demo is rebuilt, installed, and launched on the paired physical
  iPhone after automated verification.

## Risks

- Contextual presentation must remain framework-internal so applications
  cannot create divergent styling modes across the binary widget boundary.
- Removing the inner clip makes the bottom sheet solely responsible for
  clipping descendants at its rounded top edge.

## Questions

None. The supplied physical-iPhone screenshot demonstrates the double-surface
problem, and the requested single-surface direction determines ownership.

## Consequences

`MessageComposerSurfaceScope` now marks the framework-owned embedded
composition without adding an OCaml or application-facing presentation flag.
The embedded Material is transparent and unshaped, while standalone composers
retain the existing outlined card. The expandable sheet supplies the only
visible background and top corners, and duplicate lateral and top padding have
been removed.

The focused expandable and standalone composer suites pass 34 of 34 tests.
Formatting, Flutter analysis, all 457 Flutter tests, `dune build @all`, `dune
runtest`, the OCaml formatter, both protocol checks, agent-document validation,
and diff whitespace validation pass. Direct macOS interaction confirmed the
editor, attachment action, and send action render on one continuous sheet
surface. A Release build was automatically signed, installed, and launched on
the paired physical iPhone 13 after verification. Temporary demo sources and
the dependency override were removed after installation.
