# Expandable Composer Modal Bottom Sheet

## Problem

`ExpandableMessageComposer` currently changes an extended FAB into an inline
editor inside the layout slot that owns the widget. When used as a
`Scaffold.bottomNavigationBar`, the expanded editor consumes scaffold body
space, must reproduce keyboard avoidance itself, and remains visually tied to
the page rather than presenting a focused compose task.

The requested interaction follows the Gmail iOS compose affordance: tapping a
FAB should transition to a transient surface anchored to the bottom. Material
3 defines a modal bottom sheet as a blocking secondary surface with a scrim,
optional drag handle, dismiss gestures, 28dp top corners, full width on compact
screens, and a default 640dp maximum width on larger screens.

## Proposal

Replace the inline geometry morph with one Material modal bottom-sheet route.
The settled base widget contains only the real extended FAB. A successful FAB
press pushes a modal sheet with a scrim, drag handle, 28dp top corners,
safe-area handling, keyboard-inset padding, and the existing `MessageComposer`
as its content. The route uses the configured duration, supports reduced motion
through a zero duration, and focuses the editor only after its entrance
animation completes.

Keep the `TextEditingController` and `FocusNode` in the outer
`ExpandableMessageComposer` State so scrim dismissal, downward drag, Escape,
disablement, and re-opening preserve the draft. A changed widget key or State
disposal removes any owned modal route before disposing those resources. The
existing OCaml wire schema, events, buttons, and application-facing API remain
unchanged because this is a Flutter-local presentation replacement, not a new
logical state or compatibility mode.

The sheet is modal even on macOS so the same implementation can be exercised
before physical-iPhone testing. Its 640dp maximum width prevents an unsuitable
edge-to-edge desktop sheet; production consumers may choose a different
component for a desktop-specific side-sheet experience later.

## Decision

Adopt the Material modal bottom-sheet route as the only expanded presentation.
Remove the inline `AnimatedContainer` state machine and its keyboard-reserved
bottom-navigation geometry instead of retaining a second presentation mode.

## Alternatives considered

### Alternative

Keep the inline morph and wrap it in additional keyboard-aware scaffold logic.
This preserves the layout and keyboard ownership problems, does not provide
modal semantics or a scrim, and diverges from the requested Gmail-style
interaction.

### Persistent bottom sheet

A persistent sheet allows interaction with the page behind it. Composing is a
focused task and the requested Material interaction includes scrim and dismiss
behavior, so the modal variant is selected.

### Application-owned route

Requiring each OCaml consumer or generated host to push a sheet would split
controller, focus, dismissal, and draft ownership across the native-widget
boundary. The framework widget already owns those resources and remains the
correct route owner.

## Acceptance criteria

- The collapsed presentation is one real enabled or disabled extended FAB and
  no mounted editor or sheet.
- A FAB press presents one Material modal bottom sheet with a scrim, drag
  handle, 28dp top corners, compact full width, and large-window width no
  greater than 640dp.
- Standard motion mounts the editor during entrance and focuses only after the
  route settles. Zero-duration motion focuses in the next mounted frame.
- Scrim tap, decisive downward drag, and Escape dismiss the sheet and unfocus;
  short, upward, and decisive-horizontal gestures do not dismiss it.
- Unicode and whitespace drafts survive dismissal, disablement, and reopening;
  a changed key resets the draft and closes the old sheet.
- Keyboard, safe-area, RTL, large-text, narrow-width, and macOS layouts do not
  overflow or obscure the composer.
- Existing codecs, registry behavior, actions, standalone `MessageComposer`,
  OCaml tests, protocol checks, Flutter analysis, and the complete Flutter test
  suite remain green.
- A temporary demo builds and launches through the complete
  OCaml-to-native-to-Flutter macOS pipeline, and its primary interaction flows
  are exercised before requesting physical-iPhone testing.

## Risks

- A modal route outlives the widget subtree that pushed it unless disposal
  explicitly removes the owned route before controller and focus disposal.
- Nested composer and sheet vertical gestures can compete; only a decisive
  downward intent may close, while horizontal and upward intent must remain
  with the composer.
- Material 3 recommends modal bottom sheets primarily for mobile. macOS is a
  verification target here, not a commitment that modal sheets are the final
  desktop-specific information architecture.

## Questions

None. The requested Gmail-style interaction and Material 3 modal-sheet
guidance determine the presentation and dismissal contract.

## Consequences

The Flutter implementation now owns one `ModalBottomSheetRoute` per active
composer. The outer State retains the controller and focus node, propagates
renderer resources into the navigator overlay, hides the inactive FAB from
pointer and semantics traversal, and removes any owned route during disposal.
The previous inline morph and bottom-navigation keyboard-reservation path have
been removed.

Focused composer and message-composer tests pass 32 of 32 cases. The complete
Flutter package passes formatting, analysis, and all 455 tests. `dune build
@all`, `dune runtest`, the OCaml formatter, and both protocol checks pass. The
repository's viewport compile probe remains independently red because its
checked-in `valid.ml` calls the current required-argument `Theme.material` API
without `brightness` or `color_scheme`; the same mismatch exists at `HEAD`.

A temporary demo built through the complete macOS native-artifact and Flutter
host pipeline. Direct macOS interaction verified standard motion, scrim,
28dp corners, drag handle, focus, draft editing, action events, Escape and
downward-drag dismissal, draft preservation after reopening, reduced motion,
RTL logical-end placement, and 3.2x text scaling without overflow. The demo
source and dependency override were removed after verification.

The same temporary verification entrypoint was subsequently built in Release
mode, automatically signed, installed, and launched on a paired physical
iPhone 13 running iOS 26.6.1. The local entrypoint and dependency override were
removed after installation while leaving the installed application available
for hands-on keyboard verification.
