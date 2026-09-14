# Ios Keyboard Avoids Expandable Composer

## Problem

When `ExpandableMessageComposer` is used as a `Scaffold.bottomNavigationBar`,
the scaffold positions it at the physical bottom of the viewport. Focusing the
expanded editor opens the iOS software keyboard, but the composer only reserves
the bottom safe-area padding. The keyboard therefore paints over the complete
editor even though `MediaQuery.viewInsets.bottom` reports its height.

The existing adaptive-layout test checks width, overflow, and body separation
with a non-zero keyboard inset, but never compares the editor geometry with the
keyboard top. It consequently accepts the obscured layout seen on a physical
iPhone.

## Proposal

Treat the larger of `MediaQuery.padding.bottom` and
`MediaQuery.viewInsets.bottom` as the composer's current bottom avoidance
inset. Include that inset in the bottom-navigation-bar height and pad the
composer surface above it. Use the same inset when calculating the available
expanded editor height so safe area and keyboard space are not counted twice.

Keep the correction local to `ExpandableMessageComposer`; do not require every
consumer scaffold to add an application-specific animated padding wrapper. The
existing geometry animation follows keyboard inset changes, and removing the
keyboard restores the expanded surface to the safe bottom edge without losing
focus, draft, or native widget identity.

## Decision

`ExpandableMessageComposer` uses the larger of bottom safe-area padding and
the software-keyboard view inset as one bottom avoidance inset. It includes
that value in its reserved bottom-navigation-bar height, pads the visible
surface above it, and subtracts the same value once when computing available
expanded height.

## Alternatives considered

### Alternative

Wrap each consumer's `bottomNavigationBar` in padding based on
`MediaQuery.viewInsets.bottom`. This duplicates a correctness requirement at
every call site and leaves OCaml-created native widgets dependent on host
composition details, so it is not selected.

## Acceptance criteria

- With an iPhone-sized viewport and a non-zero software-keyboard inset, the
  settled expanded composer bottom is at or above the reported keyboard top.
- Returning the keyboard inset to zero restores the expanded composer to the
  viewport bottom without an empty reserved gap.
- Safe-area, RTL, large-text, reduced-motion, body-space, gesture, focus, and
  draft-preservation behavior remains green.
- The complete Flutter package passes formatting, static analysis, and tests;
  a signed Release build installs and launches on the connected physical
  iPhone.

## Consequences

- `ExpandableMessageComposer` reserves exactly the larger of the bottom safe
  area and software-keyboard inset. Its visible surface therefore settles at
  the keyboard top and returns to the safe bottom edge after dismissal.
- The focused composer suites pass all 32 tests. The complete Flutter package
  passes all 455 tests, formatting, and static analysis.
- The signed arm64 iOS Release bundle passes native-object and app-bundle
  verification, installs on the connected physical iPhone, and launches the
  corrected demo target.

## Risks

- Keyboard and composer animations have platform-specific durations. The
  geometry must settle correctly even if their intermediate motion is not
  perfectly phase-aligned.
- Adding the inset to the bottom-navigation-bar height reduces scaffold body
  space while the keyboard is visible; the inset must be counted once, not in
  addition to safe-area padding.

## Questions

None. The physical-device screenshot, Flutter scaffold layout contract, and
existing public ownership decision determine the required behavior.
