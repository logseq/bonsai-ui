# Native sidebar composition

Material.Navigation_rail and Material.Navigation_drawer are removed. A sidebar
is application content composed from native controls and bounded bodies, with
NavigationSplitView for an embedded sidebar or Sheet for modal presentation.
There is no replacement descriptor family or Material renderer.

## Application state and layout

Keep the selected destination ID in OCaml. Each destination is a keyed Button
with a Label, selected accessibility metadata, and a handler capturing its stable
ID. Group headings and Dividers organize destinations without flattening groups
into package-specific indices. Disabled Buttons have no active input binding;
handlers can also check current application policy before changing selection.

Use View.Navigation_split.two_columns for sidebar/detail navigation. Its split
state carries the selected destination key, native visibility intent and preferred
compact column. Native column changes are controlled requests; they cannot replace
the application selection. Selecting a destination can prefer Detail for compact
presentation while retaining the current visibility intent. See
[native split navigation](swiftui-navigation-split.md).

Compose the sidebar as a vertical Body: a fixed heading and action area, a
scrolling destination region, and optional fixed trailing content. Put the
trailing content inside the scrolling region when it should follow the groups.
A normal Button represents the former FAB action, with its own enabled state
and handler independent of destination selection. No FAB ID is mixed into a
selection callback.

The old collapsed icon rail and expanded Material widths are removed. Native
sidebar visibility and compact-column selection determine presentation. The
Standard/Modal enum is also removed: modal navigation explicitly composes
View.Sheet, sharing the same OCaml destination state. Give the sheet's sidebar
body finite bounds with Body.with_size and select an appropriate native sizing
policy. Native dismissal is a controlled Boolean request. Sheet ownership fences
background controls and hidden or disposed modal callbacks; see
[native sheets](swiftui-sheet.md).

## Gallery and verification

Sidebar_catalog.component appears in Gallery and runs through the actual native
runtime as native-sidebar. Its two mailbox destinations and separate account
group use stable signed IDs, including a Unicode label and a disabled choice.
It demonstrates per-destination detail counters, selected semantics, reversed
ordering, rejected selection requests, independent Compose/help actions,
disabling Compose, and trailing content placement. It can switch between an
embedded split and a modal sidebar while retaining canonical selection, counters
and action history. Changing the presentation structure remounts its native
controls; callbacks from the previous structure are invalidated.

The native integration test first fails with unsupported legacy node 136. The
replacement test activates actual native Buttons and modal dismissal, checks
retained destination nodes under reordering/window resize, and measures trailing
help moving between a pinned footer and the position after the destination groups.
The test also verifies disabled actions, declined selection, native split requests,
modal background isolation, retained modal content across dismissal/reopening,
stale controls after presentation changes, hidden sessions and shutdown.

Old expressive component IDs 17 and 18 have no constructors or renderer cases.
OCaml encoding and decoding reject these retired component IDs. A regression
first proves that the previous decoder accepted them, then requires Invalid_props
while a still-active component continues to decode. The shared expressive node
remains only for other unmigrated Material components.

Material Tabs now uses segmented Picker; legacy navigation bars use native
TabView pages. Full Gallery remains separate work. Physical iOS compact navigation, VoiceOver reading/selection announcements,
keyboard navigation and actual screenshots still need runtime acceptance.
