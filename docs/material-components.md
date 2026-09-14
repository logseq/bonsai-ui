# Material components

The public `Material` module and its private logical nodes are removed. Native
controls use the core `View` API and SwiftUI composition. This page records the
replacement choices; removal of the old surface does not establish every native
interaction or complete the full migration. See the
[implementation ledger](swiftui-implementation.md) for current coverage.

`Material.scaffold` is removed. Headers and persistent footer/navigation content
use fixed Body children around a bounded scrolling region. Floating actions use
native Buttons on a viewport or Body overlay; no Scaffold slot protocol or
floating-location enum remains. See [page layout composition](swiftui-page-layout.md).

Filled, tonal, outlined, elevated and text button constructors, along with all
FloatingActionButton sizes and its extended variant, are removed. Use
`View.button` with `Automatic`, `Plain`, `Bordered` or `Prominent` style, a native
role, composed text/SF Symbol/Label content and `View.control_size`. Place a
floating action with ordinary overlay/alignment/padding composition. There are
no legacy constructors or codecs; retired wire kinds 98, 99, 109, 110, 111 and
114 are rejected. See [native control-size scopes](swiftui-control-size.md).

Core Button now supports presentation-gated autofocus and focused Space
activation, with actual OCaml/native macOS lifecycle tests. Physical iOS
keyboard acceptance remains outstanding; see [native Button focus](swiftui-button-focus.md).

NavigationRail and NavigationDrawer are removed. Use [native sidebar
composition](swiftui-sidebar-composition.md): keyed Buttons and selected semantics,
bounded scrolling groups, independent actions, and NavigationSplitView or Sheet
presentation share OCaml-owned destination state.

Material.Tabs is removed. Its selection strip uses [segmented Picker](swiftui-picker.md)
with signed IDs and composed labels; application pages use [native TabView](swiftui-tabs.md).
The latter now accepts literal badge text and independent accessibility labels.

Material.Toolbar is removed. Use [native toolbar composition](swiftui-toolbar.md)
with keyed Buttons, Toggles, Menus and semantic placements. Native overflow owns
the bar's expansion; command handlers and selected state belong to each control.
Material.App_bar.top/bottom are also removed. Use native navigation titles,
page toolbars and fixed Body children; see [native page bars](swiftui-app-bars.md).
Scrolling headers and AppBar search remain separate work.

Material.navigation_bar and its destination descriptors are removed. Application
navigation uses native TabView pages with stable page keys, OCaml-owned selection,
SF Symbols, badges and accessibility labels. Material bar layout/style switches
are removed in favor of native presentation; see [native tabs](swiftui-tabs.md).

`Material.Radio_group` has been removed. Use [View.Picker](swiftui-picker.md)
for single selection, including stable signed IDs, initial empty selection,
disabled options and native segmented/inline/menu presentation.

`Material.Segmented_button` has been removed. Single selection uses Picker;
[multiple selection](swiftui-multiple-selection.md) uses keyed native Toggles
with shared OCaml state, composed labels and Button or Checkbox presentation.

Sliders now use native [View slider controls](swiftui-slider.md), including
finite domains, step validation and controlled range endpoints. Circular and
linear progress indicators use [View.progress](swiftui-progress.md), inheriting
SwiftUI styling. Omit the value for indeterminate progress or pass a finite
value in `0.0..1.0`. Bound linear progress with `View.frame` when needed.

```ocaml
Ui.View.frame ~width:240. (Ui.View.progress ~value:0.68 ())
```

`Material.Chip` has been removed. Actions use native Buttons, selections use
Button-style Toggles, and removable tags compose a Toggle with a sibling
removal Button. See [actions, filters and tags](swiftui-tags.md) for state
ownership, optional removal, native labels and verification.

ListTile is removed. Use [native Label and row composition](swiftui-label.md)
for title/icon content, selected semantics and separate main/accessory Buttons.

Badge now uses [View.badge](swiftui-badge.md), with native overlays, exact integer
counts and directional anchors. Its decoration does not own input or semantics.

Card and CardList now use [native GroupBox and keyed composition](swiftui-group-box.md).
The old elevation and Elevated/Filled/Outlined options are removed. Native
Buttons own selection and body actions independently. `View.divider` renders
SwiftUI Divider; parent layout and modifiers determine its geometry.

SearchBar, SearchAnchor and AppBar.search now use [native search
composition](swiftui-search.md): revisioned View.text_field, keyed suggestion
Buttons and inline, Popover or Sheet presentation. Their old constructors,
search node and generic expressive node are removed. Tooltip now uses [native help text](swiftui-help.md) and
[controlled popovers](swiftui-popover.md); its Material constructors are removed.

Selection and Selection.leading now use [keyed Toggles and contextual Toolbar
composition](swiftui-contextual-selection.md). OCaml owns the selected set,
select-all, clearing and batch actions. Their old components and shared
selected-ID event are removed.

Data tables now use [View.Table](swiftui-table.md): native SwiftUI Table at
regular width and a complete labeled-row presentation at compact width. OCaml
owns sorting and one selected-ID set. Cell actions, placeholder/edit content,
and select-all commands use ordinary compositions. Rich header content and help
remain available through the Column details disclosure. The Material constructor,
node 131 and table-specific select-all/cell-activation events are removed.

Stepper now uses [Workflow](swiftui-workflow.md), with OCaml-owned current-step
identity and native control composition. Expansion panels and expandable lists
use [View.disclosure_group](swiftui-disclosure.md), with individual Boolean
states and application-owned single/multiple expansion policy.

Dialog and Bottom_sheet / Side_sheet surfaces now use [native sheets](swiftui-sheet.md)
and ordinary Text, Button and choice composition. The old surface constructors,
simple/fullscreen dialog nodes and option event are removed. The unused
`Navigation.Modal_*`, Navigator/Page and route-pop protocol are also removed.
Persistent bottom content now uses Body composition. Native sheet focus,
keyboard avoidance, scroll/detent gestures and physical acceptance remain
outstanding.

`MaterialBanner`, `CarouselView`, `PaginatedDataTable`, and
`AboutDialog` are intentionally excluded; there are no fallback or experimental
paths for them.

Notifications are typed host effects. Use
`Host_effect.show_notice` with a message, optional action label, duration,
and optional cancellation token; its result identifies the exact close reason.
