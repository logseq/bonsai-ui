# Searchable choices and action groups

`Material.Button_group` and `Material.Dropdown_menu` are removed. The Gallery
selection catalog composes native controls and keeps canonical selection in
OCaml. It adds no replacement wire node or compatibility constructor.

## Composition

| Capability | SwiftUI-facing composition |
| --- | --- |
| Single selection | `View.Picker` with Segmented, Inline or Menu style |
| Multiple selection | Keyed Button-style Toggles or checked `View.Menu.choice` entries |
| Ordinary actions | Keyed Buttons or `View.Menu.action` entries; repeated actions remain separate |
| Horizontal wrapping | `View.flow` |
| Vertical groups | `View.column` |
| Scrolling overflow | Explicitly bounded horizontal or vertical `View.Scroll` |
| Menu overflow | Native Menu anchor and entries |
| Sizes | Five native `View.control_size` values |
| Icons and titles | `View.label` with an SF Symbol and text |
| Search | Native `View.text_field` and application-owned filtering |
| Loading, empty and failed content | Progress, Text and an independent retry Button |

Material connected/standard group types, round/square shape and package-specific
button styles are removed. Native Picker styles and ordinary Button/Toggle
composition own presentation. Selection policy and presentation are independent;
there is no overloaded no-selection/single-selection/multiple-selection event.

The example searches a small in-memory catalog. It trims ASCII whitespace and
uses ASCII-case-insensitive UTF-8 substring matching. Non-ASCII text is preserved;
this is not locale-aware Unicode case folding. Loading and failure controls
exercise presentation states rather than initiating a network request.

## State and input

Canonical single and multiple selections survive search filtering, empty
results, loading and failure. A filtered single-selection Picker receives `None`
when its canonical ID is absent from the visible options. Clearing the query
restores that selection. Only the explicit Clear selections action clears it.

Each handler checks current enabled state, ready content and visible enabled
choices before changing the model. This also rejects a choice queued after a
query update in the same event batch when that query hides the choice. Ignoring
selection changes leaves ordinary action Buttons enabled and functional.

Search uses a stable text-input session and acknowledges increasing local edit
revisions. Its exact UTF-16 selection and marked-text range are retained through
OCaml updates. The query editor stays mounted while content and presentation
change. Native option IDs preserve Toggle identity when choices are reordered;
removed controls cannot deliver retained callbacks.

## Gallery and checks

`examples/gallery/ocaml/selection_catalog.ml` is included in
`Gallery.picker_component` and embedded independently as
`native-selection-catalog`. It exercises single and multiple choices, action
counts, layouts, sizes, enabled and ignored state, filtering, Unicode input,
reordering, content states and retries.

`SelectionCatalogTests.swift` drives the actual OCaml component through the
native bridge. Native field-editor input verifies query acknowledgment, emoji
and marked text. Runtime tests check canonical state, no-diff rejection,
repeated actions, disabled/removed controls and all layouts. A separate test
checks actual AppKit popup, segmented and radio control sizes and their intrinsic
heights for all five values. SwiftUI already forwards the size environment to
these adapters; no manual adapter sizing code is needed.

`native/test/test_selection_catalog_window.py` runs a standalone SwiftUI App.
It invokes native accessibility and menu actions and edits the actual AppKit field
editor, then waits for the resulting OCaml state. It checks single and multiple
selection, repeated actions, filtering, empty results, error retry and canonical
selection restoration. Menu composition fits a 360-point window and retains
disabled entries and rejected checkmarks. Its PASS marker and process exit are
both required; menu tracking is confined to this App's own menu.

The Picker regression fixture also hosts this new catalog. Its original four
Picker controls are selected by their catalog labels, and the test checks that
the new catalog's canonical selection stays independent. Native text capture is
scheduled after completed field-editor mutations; the same-batch ordering test
allows that capture to enqueue before submitting later choices without pumping
OCaml between them.

These tests do not establish physical keyboard/IME, VoiceOver or iOS device
acceptance, nor do they provide the required Mail application screenshots.
