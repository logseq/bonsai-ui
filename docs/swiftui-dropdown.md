# Searchable choice composition

The former Material Dropdown is composed from native `View.text_field`,
`View.Picker`, keyed `View.toggle` controls, progress, text and Buttons.
[Dropdown_catalog.component](../examples/gallery/ocaml/dropdown_catalog.ml)
is shared by Gallery and the real `native-dropdown` OCaml runtime entrypoint.
There is no new dropdown node, selection decoder or parallel renderer.

OCaml owns the revisioned query, content state, optional single selection and
independent multiple-selection set. Changing presentation mode preserves both
selection models. Filtering changes the displayed choices without deleting
hidden selections. A Picker displays no selection while its canonical ID is
filtered out; clearing the query reveals that ID again. Multiple selection uses
one Bool intent per item, so independent queued changes do not replace each
other's set updates.

The example exposes Items, Loading, Empty and Error states explicitly. An Items
state with no query matches has a separate no-matches message. Retry returns to
Items and preserves query/selection. These controls demonstrate application
state transitions; they do not start network requests. Query matching is
ASCII-case-insensitive substring matching and preserves Unicode bytes.

Native edits return acknowledged local revisions, UTF-16 selection and marked
ranges through the existing editing contract. Clear publishes an explicit
document correction. The keyed native field remains mounted across query,
content and selection-mode changes. Disabled state applies to the input and
choices; disabled source items remain ineligible independently of that state.

Selection handlers check the current mode, enabled state, content, filtered
choices and rejection policy. Removed or filtered controls also lose native
event admission. Rejecting a valid native request restores the accepted Picker
or Toggle value through the existing controlled-state reconciliation.

## Verification

`DropdownCompositionTests.swift` opens real native windows at 360- and 620-point
widths. It edits the AppKit field editor with Chinese and emoji text, dispatches
the native popup's target/action, and sends multiple-selection intents through
the production Toggle controller. It checks filtering, retained field/control
identity, independent queued memberships, all content states, retry, clearing,
disabled options, stale bindings, removed choices, rejected selections and
shutdown. The combined test failed on the absent runtime entrypoint before the
shared example was implemented.

Four focused tests pass in 7.699 seconds, including both dropdown widths,
complete Gallery startup/dispatch and the existing independent Picker/multiple
selection regressions. OCaml tests/formatting and the Gallery macOS complete
object pass. The updated Gallery also compiles to a physical-iOS object with
minimum iOS 18.0. Detailed evidence is recorded in
`_build/validation/swiftui-dropdown.json`.

This closes the combined macOS example/interaction gap identified by the
[API review](swiftui-navigation-input-api-review.md). Physical iOS touch/IME,
VoiceOver and visual acceptance remain open. AppKit field-editor insertion is
not evidence of a physical keyboard or an actual input-method session.
