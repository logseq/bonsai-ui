# Gallery

The Native Form sample uses a deliberately bounded 420pt grouped Form with keyed
diagnostic rows, selectable LabeledContent values, and ContentUnavailableView
actions dispatched to ordinary OCaml handlers. See [the public form API](../../docs/swiftui-form.md).

## SwiftUI migration status

Gallery now owns a schema-3 configuration, SwiftUI App entrypoint, native card
registration, image resources and generated macOS/iOS Xcode hosts. Its native
complete object no longer requires a Flutter embedding environment flag.
The standalone macOS App builds through the public CLI and its PNG/GIF resources
are verified in the resulting bundle. The old Flutter host is removed from the
source tree.

The complete-page regression loads the actual OCaml component into
`BonsaiSession`, stages its tree, and dispatches the real toolbar counter action.
`actualCompleteGalleryStartsAndDispatches` passes in the 2026-09-18 native Form
checkpoint, including the added form sample. This is native runtime evidence;
physical iPhone interaction still requires separate verification.

Material Button/FAB samples now use native Button styles, Label and ControlSize
composition. The old EnvironmentBoundary API and wire node are removed: its
Flutter implementation only copied the current MediaQuery value, while SwiftUI
inherits environment values directly. Native environment observation and
publication to OCaml remain a separate unfinished capability. Gesture and Hover
already use native adapters, with further physical-device acceptance required;
see [gesture integration](../../docs/swiftui-gestures.md).

For host/build commands and the evidence boundary, see
[the Gallery port](../../docs/swiftui-gallery.md).

Ordinary and expandable message composer catalogs use standard SwiftUI native
registrations. The expandable catalog opens a native Sheet, keeps its draft
through closing/reopening and Compact/Extended launcher changes, and exercises
disablement, reset and removal from inside the Sheet. Native tests verify modal
input isolation, marked text, selection retention, raw actions and resource
lifecycle; independent SwiftUI Apps also verify native focus and line limits.
See [composer behavior and evidence](../../docs/swiftui-composer.md).

The native fixture embeds the actual migrated Gallery sections independently.
`make swift-test` exercises these sections through the real OCaml runtime and
native controls. Picker covers Automatic, Menu, Segmented and Inline single
selection. Multiple selection uses native Button and Checkbox Toggles sharing
an OCaml set, including composed symbol/text labels, unavailable choices,
rejected requests, reordering and clearing. The old RadioGroup and Segmented
button constructors have been removed. The former Chip section now uses native
actions, filter Toggles and removable keyed tags in a native wrapping layout; see [tags](../../docs/swiftui-tags.md).
The core Button section cycles five native control sizes and exercises styles,
icon-only accessibility labels and disabling at two window widths; see
[control size](../../docs/swiftui-control-size.md).
The projection section cycles native scale, translation and perspective while
retaining its accessible action control; see [projection](../../docs/swiftui-projection.md).
The animated-opacity section tests lifecycle completions from inside a disabled
control label; see [animated opacity](../../docs/swiftui-animated-opacity.md).
The workflow section replaces the former Material Stepper and tests selection,
Continue/Back, status descriptions, hidden content and reorder/layout changes;
see [workflows](../../docs/swiftui-workflow.md).
The disclosure section replaces expansion panels and expandable lists with
native DisclosureGroup controls and OCaml-owned single/multiple policy, including
rejected requests and disabled content; see [disclosures](../../docs/swiftui-disclosure.md).
The group section replaces Card/CardList with native GroupBox and keyed Button
composition, testing independent header/body actions, disabling, label changes
and reordering; see [groups](../../docs/swiftui-group-box.md).
The label section replaces ListTile with native Label and composed rows, including
full-width primary actions, selected semantics and independent accessories; see
[labels](../../docs/swiftui-label.md).
The badge section tests native dot/count overlays, exact large counts, directional
alignment, visibility and retained content actions; see [badges](../../docs/swiftui-badge.md).
The hover section exercises overlapping and nested regions, pass-through,
reordering, handler replacement and retained child Button actions through the
native renderer, including shared window-source lifecycle and application-local
queued mouse movement; see [pointer input](../../docs/swiftui-pointer-events.md).
The civil selection section replaces the Material calendar and dial with linked
native date fields and a time DatePicker. It exercises accepted/rejected requests,
restricted dates, disabled controls and handler replacement; native macOS menu
and time-field actions update the actual OCaml model. See
[civil date and time selection](../../docs/swiftui-civil-selection.md).
The menu section replaces Material Menu, SplitButton and FAB menu with hierarchical
native menus and Button/Menu composition. It exercises checked choices, repeated
actions, nested and disabled branches, ignored updates and handler replacement;
see [native menus](../../docs/swiftui-menu.md).
The searchable selection catalog replaces ButtonGroup and DropdownMenu with
Picker, Toggle, Menu and native text-input composition. It retains canonical
selection through filtering and loading/error states and exercises wrapping,
scrolling, menu overflow, five sizes and Unicode marked text; see
[choice composition](../../docs/swiftui-choice-composition.md).
The carousel catalog replaces Material Carousel with axis-specific native scroll
targets and independent card Buttons. It exercises controlled position, preview
fractions, directional anchors, free scrolling, rejected updates, reordering and
empty content; see [scroll targets](../../docs/swiftui-scroll-targets.md).
The help section replaces plain Tooltip with native SwiftUI help text and tests
Unicode hint updates, independent actions and disabled controls. Rich help now uses
controlled native popovers with independent Buttons, rejected native dismissal,
hidden-session restoration and retained child state; see
[native help](../../docs/swiftui-help.md) and [popovers](../../docs/swiftui-popover.md).
The sheet catalog replaces Material dialog and sheet surfaces with five native
presentation compositions. It covers choice enablement, modal background
isolation, nested popovers, rejected dismissal and hidden-session restoration;
it also exercises Automatic/Fitted/Form/Page sizing policies with measured native
window geometry. See [native sheets](../../docs/swiftui-sheet.md). The unused
legacy modal route API and protocol are removed; native focus, keyboard avoidance,
scroll/detent gestures and physical acceptance remain open.
The page-layout catalog replaces Scaffold slots with fixed header/footer content,
a bounded native scrolling region and a viewport overlay. It verifies repeated
independent actions, footer resizing, window resizing, retained scroll position
and node identity. Gallery embeds this bounded demonstration with Body.with_size;
see [page layouts](../../docs/swiftui-page-layout.md).
The sidebar catalog replaces NavigationRail/NavigationDrawer with grouped native
Buttons, selected semantics, bounded scrolling and a pinned or inline trailing
action. It exercises split and modal Sheet presentation, per-destination state,
disabling, reordering, rejected selection and stale callbacks; see
[sidebar composition](../../docs/swiftui-sidebar-composition.md).
Material Tabs is consolidated into the linked native choice-Picker scenario,
including real segmented-control label/icon, signed-ID and rejected-selection
tests. The native tabs scenario now cycles badges and accessibility labels while
retaining its page state; actual system tab controls verify the label changes.
The redundant static Material navigation bars are removed in favor of this
interactive TabView scenario. Persistent bottom content is a fixed Body child.
Badge appearance still needs visual acceptance; see [native tabs](../../docs/swiftui-tabs.md).
The toolbar catalog replaces Material.Toolbar with a native principal title,
action Button, Pin Toggle and secondary Menu. It exercises retained commands,
placement changes, reordering, disabling and removal/restoration; see
[native toolbar composition](../../docs/swiftui-toolbar.md).
The app-bar catalog replaces static top/bottom Material bars with independent
native toolbar commands and fixed bottom controls around a scrolling page.
Its detail route accepts a bounded scrolling body and owns separate commands;
see [native page bars](../../docs/swiftui-app-bars.md).
See [Picker](../../docs/swiftui-picker.md),
[multiple selection](../../docs/swiftui-multiple-selection.md) and the
[implementation ledger](../../docs/swiftui-implementation.md).

## Remaining work

Native SwiftUI App hosts exist for both supported platforms, and the complete
macOS Gallery tree/presentation/toolbar regression passes. The Material module
and Button/FAB constructors are removed. This does not establish every native
control's layout, custom-card behavior, accessibility or physical interaction.
Physical Button keyboard acceptance, UIKit KeyboardListener and full-page
acceptance remain unfinished. See [Gallery verification](../../docs/swiftui-gallery.md).
The target platforms remain physical iOS 26+ arm64 and macOS 26+ arm64;
Simulator is unsupported.
