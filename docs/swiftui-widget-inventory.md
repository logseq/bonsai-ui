# SwiftUI widget migration inventory

This inventory makes the baseline public surface explicit. It is an acceptance
worklist, not a claim that every component has been replaced or verified. The
baseline is commit `39c486233d0a1a614c6cb1267a80fa19d6076fcc`.

## Scope and evidence

The [machine-readable inventory](swiftui-widget-inventory.json) records every
public `val` declaration and named sum constructor found in the baseline
`Widget`, `Material`, `Cupertino` and `Native_widget` signatures, excluding
`Private` and `For_testing`. It records source paths, exact one-based lines and
signature hashes. These include helper values as well as view constructors.

There are **228 public values** and **175 named sum constructors**.
The four public signatures contain no `include` or module-alias declarations
requiring another signature to enumerate their values. Parameter records,
optional arguments, type aliases, and auxiliary Layout/Style/Theme contracts
still require a separate behavioral review; the sum-constructor count does not
cover that entire domain.

| Baseline module | Public values |
| --- | ---: |
| `Widget` | 85 |
| `Material` | 102 |
| `Cupertino` | 2 |
| `Native_widget` | 39 |

## Foundational API review

[Fifteen foundational values](swiftui-core-api-review.md) now have individual
API reviews covering root identity, test metadata, empty/text content, stacks,
frames and visual modifiers. Each records exact current declarations, parameter
changes, renderer and available Gallery/test evidence. The center-factor,
text-overflow, inset-direction, constraint and projection changes are explicit.
Two headless identity/query helpers have no invented visual Gallery scenario.

Together with menu, civil-picker, control, layout/content, extension, list and
navigation/input reviews, **228 of 228 public values** have an individual API
review. **175 of 175 named constructors**
have an explicit replacement or removal rationale. Overall acceptance remains
pending; these reviews do not imply complete physical-device verification.

## Navigation and input API review

[The final primary mapping review](swiftui-navigation-input-api-review.md)
covers the remaining 43 values and 55 constructors. It distinguishes tab strips
from application pages, single from multiple selection, native presentation
from removed Material geometry, and composed actions from old container events.
Scoped theme now has interactive Gallery and native OCaml regression coverage.
The [combined Dropdown scenario](swiftui-dropdown.md) also has native-window
coverage for filtering, content states and independent selection models.
Physical-device and complete accessibility acceptance remain open.

## Control API review

[The control review](swiftui-control-api-review.md) covers buttons, FABs,
Boolean controls, pickers, sliders, tags, progress and button groups. It records
callback changes, disabled behavior and the removal of Material presentation
variants. Existing focused verification passes 28 tests in seven suites.

## Layout and content API review

[The layout/content review](swiftui-layout-content-api-review.md) adds 49 values
and 14 named constructors. It covers bounded Body/Viewport composition, weighted
layout, layers, rich text, symbols, images and native container presentation.
The seven auxiliary Image_fit choices are recorded separately from the primary
constructor count, including the changed default. Source/test hashes match the
current complete Swift regression; typed viewport compile checks also pass.

## Native extension API review

[The extension review](swiftui-extension-api-review.md) covers all 39 baseline
Native_widget values and 36 constructors. It records which capabilities became
core controls, how event routing changed, and which native composer contracts
remain. The obsolete public comment claiming the expandable SwiftUI registration
was missing has been corrected. Runtime behavior and public signatures are unchanged.

## Scroll and list API review

[The list review](swiftui-list-api-review.md) covers 39 additional values and
28 named constructors. Catalog/window ownership, mixed content, eager versus
windowed materialization, per-item state and callback changes are explicit.
Native sections, Table and scroll targets do not silently claim bounded OCaml
materialization. Existing source-matched regression evidence is reused.

## Menu API review

Ten values in `Material.Menu`, `Material.Fab_menu` and `Material.Split_button`
now have an individual `api_review` in the JSON inventory, with the exact
current declaration, parameter disposition, Swift renderer and Gallery scenario.
Selectable and toggleable entries consolidate into `View.Menu.choice`;
dividers and groups gain stable IDs; string labels become View content.
FAB placement/collapse presentation and Material split-button styles are removed
in favor of parent layout and independently chosen native controls.

This closes the API-mapping portion for these values, not their complete
acceptance. Physical-iOS interaction, appearance, maximum-size performance and
all variant behavior still need evidence. The separate asynchronous
[host action chooser](swiftui-host-menus.md) is a host service, not a replacement
for the inline `View.Menu` widget.

## Family-level replacement directions

These directions are drawn from the current implementation guides. Each
baseline value has a row in the JSON inventory, so a consolidated family does
not silently remove its old members. A guide may contain both completed work
and outstanding checks. No row is accepted solely because its guide exists.

| Baseline family | Values | Current direction | Guide |
| --- | ---: | --- | --- |
| `Cupertino.button` | 1 | View.button | [Contract](swiftui-button-focus.md) |
| `Cupertino.switch` | 1 | View.toggle | [Contract](swiftui-toggle.md) |
| `Material.App_bar` | 3 | Toolbar, Body, Scroll_sections and search composition | [Contract](swiftui-toolbar.md) |
| `Material.App_bar.search` | 2 | View.text_field, Button and presentation composition | [Contract](swiftui-search.md) |
| `Material.Bottom_sheet` | 1 | View.Sheet and Body composition | [Contract](swiftui-sheet.md) |
| `Material.Button_group` | 2 | View.button and flow/stack composition | [Contract](swiftui-control-size.md) |
| `Material.Card_list` | 4 | View.group_box and Scroll/Collection composition | [Contract](swiftui-group-box.md) |
| `Material.Carousel` | 2 | View.Scroll_targets | [Contract](swiftui-scroll-targets.md) |
| `Material.Chip` | 4 | View.button, View.toggle and removal-action composition | [Contract](swiftui-tags.md) |
| `Material.Data_table` | 4 | View.Table | [Contract](swiftui-table.md) |
| `Material.Date` | 2 | View.Date and View.Date_picker | [Contract](swiftui-civil-selection.md) |
| `Material.Dialog` | 4 | View.Sheet with ordinary content and controls | [Contract](swiftui-sheet.md) |
| `Material.Dismissible_list` | 3 | View.Removal | [Contract](swiftui-removal.md) |
| `Material.Dropdown_menu` | 2 | View.Picker with application-owned search/empty/error content | [Contract](swiftui-picker.md) |
| `Material.Expandable_list` | 4 | View.disclosure_group and Scroll/Collection composition | [Contract](swiftui-disclosure.md) |
| `Material.Expansion_panel_list` | 2 | View.disclosure_group | [Contract](swiftui-disclosure.md) |
| `Material.Fab_menu` | 2 | View.Menu and ordinary primary Button composition | [Contract](swiftui-menu.md) |
| `Material.Floating_action_button` | 2 | View.button, Label, control size and layout composition | [Contract](swiftui-button-focus.md) |
| `Material.Menu` | 7 | View.Menu | [Contract](swiftui-menu.md) |
| `Material.Navigation_destination` | 1 | View.Tabs.item and navigation composition | [Contract](swiftui-navigation-split.md) |
| `Material.Navigation_drawer` | 2 | View.Navigation_split and sidebar composition | [Contract](swiftui-navigation-split.md) |
| `Material.Navigation_rail` | 4 | View.Navigation_split and sidebar composition | [Contract](swiftui-navigation-split.md) |
| `Material.Radio_group` | 2 | View.Picker | [Contract](swiftui-picker.md) |
| `Material.Range` | 1 | View.Slider range values | [Contract](swiftui-slider.md) |
| `Material.Refresh_indicator` | 1 | View.Refresh | [Contract](swiftui-refresh.md) |
| `Material.Search_anchor` | 2 | View.text_field and View.Popover / View.Sheet composition | [Contract](swiftui-search.md) |
| `Material.Segmented_button` | 2 | View.Picker for single selection; keyed Toggles for multiple selection | [Contract](swiftui-multiple-selection.md) |
| `Material.Selection` | 2 | Keyed View.toggle and View.Toolbar | [Contract](swiftui-contextual-selection.md) |
| `Material.Side_sheet` | 1 | View.Sheet and navigation composition | [Contract](swiftui-sheet.md) |
| `Material.Split_button` | 1 | View.button plus View.Menu | [Contract](swiftui-menu.md) |
| `Material.Stepper` | 2 | Workflow and native control composition | [Contract](swiftui-workflow.md) |
| `Material.Tabs` | 2 | View.Tabs | [Contract](swiftui-tabs.md) |
| `Material.Time` | 2 | View.Time and View.Time_picker | [Contract](swiftui-civil-selection.md) |
| `Material.Toggle_button` | 1 | View.toggle with Button style | [Contract](swiftui-toggle.md) |
| `Material.Toolbar` | 3 | View.Toolbar | [Contract](swiftui-toolbar.md) |
| `Material.Tooltip` | 2 | View.help and View.Popover | [Contract](swiftui-help.md) |
| `Material.badge` | 1 | View.badge | [Contract](swiftui-badge.md) |
| `Material.card` | 1 | View.group_box | [Contract](swiftui-group-box.md) |
| `Material.checkbox` | 1 | View.toggle with Checkbox style | [Contract](swiftui-toggle.md) |
| `Material.circular_progress_indicator` | 1 | View.progress with Circular style | [Contract](swiftui-progress.md) |
| `Material.divider` | 1 | View.divider and layout composition | [Contract](swiftui-group-box.md) |
| `Material.elevated_button` | 1 | View.button, Label, control size and layout composition | [Contract](swiftui-button-focus.md) |
| `Material.filled_button` | 1 | View.button, Label, control size and layout composition | [Contract](swiftui-button-focus.md) |
| `Material.filled_tonal_button` | 1 | View.button, Label, control size and layout composition | [Contract](swiftui-button-focus.md) |
| `Material.icon_button` | 1 | View.button, Label, control size and layout composition | [Contract](swiftui-button-focus.md) |
| `Material.linear_progress_indicator` | 1 | View.progress with Linear style | [Contract](swiftui-progress.md) |
| `Material.list_tile` | 1 | View.label and native row composition | [Contract](swiftui-label.md) |
| `Material.loading_indicator` | 1 | View.progress | [Contract](swiftui-progress.md) |
| `Material.navigation_bar` | 1 | View.Tabs and View.Navigation_split | [Contract](swiftui-navigation-split.md) |
| `Material.outlined_button` | 1 | View.button, Label, control size and layout composition | [Contract](swiftui-button-focus.md) |
| `Material.range_slider` | 1 | View.Slider.range | [Contract](swiftui-slider.md) |
| `Material.scaffold` | 1 | View.Body, Toolbar and overlay composition | [Contract](swiftui-page-layout.md) |
| `Material.search_bar` | 1 | View.text_field, Button, Toolbar and presentation composition | [Contract](swiftui-search.md) |
| `Material.slider` | 1 | View.Slider.create | [Contract](swiftui-slider.md) |
| `Material.switch` | 1 | View.toggle with Switch style | [Contract](swiftui-toggle.md) |
| `Material.text_button` | 1 | View.button, Label, control size and layout composition | [Contract](swiftui-button-focus.md) |
| `Material.text_field` | 1 | View.text_field, View.secure_field or View.text_editor | [Contract](swiftui-text-fields.md) |
| `Native_widget` | 6 | Native_widget typed extensions with BonsaiNativeViews Swift registrations | [Contract](custom-widgets.md) |
| `Native_widget.Expandable_message_composer` | 7 | Native_widget.Expandable_message_composer with native composition | [Contract](swiftui-composer.md) |
| `Native_widget.Message_composer` | 7 | Native_widget.Message_composer with SwiftUI/native text adapters | [Contract](swiftui-composer.md) |
| `Native_widget.Morphing_surface` | 2 | View.Morphing_surface | [Contract](swiftui-morphing-surface.md) |
| `Native_widget.Navigation_shell` | 5 | View.Navigation_split and application-owned navigation | [Contract](swiftui-navigation-split.md) |
| `Native_widget.Slidable` | 10 | View.Swipe_actions | [Contract](swiftui-swipe-actions.md) |
| `Native_widget.Slidable_auto_close_behavior` | 2 | View.Swipe_actions ownership and group closure | [Contract](swiftui-swipe-actions.md) |
| `Widget` | 18 | View core layout, text and modifiers | [Contract](swiftui-implementation.md) |
| `Widget.Body` | 14 | View.Body and bounded vertical/horizontal composition | [Contract](swiftui-application-body.md) |
| `Widget.Flex` | 5 | View.Weighted and View.layout_priority | [Contract](swiftui-implementation.md) |
| `Widget.Scroll_view` | 2 | View.Scroll or View.Scroll_sections | [Contract](swiftui-scroll.md) |
| `Widget.Sliver` | 9 | View.Collection or View.Scroll_sections; choose by virtualization needs | [Contract](swiftui-scroll-sections.md) |
| `Widget.Sparse_extent` | 6 | View.Collection sparse catalog and extent transitions | [Contract](virtual-lists.md) |
| `Widget.Stack` | 3 | View.stack, View.overlay, View.frame and View.offset | [Contract](swiftui-implementation.md) |
| `Widget.Viewport` | 14 | View.Viewport.Vertical / Horizontal | [Contract](virtual-lists.md) |
| `Widget.animated_opacity` | 1 | View.animated_opacity | [Contract](swiftui-animated-opacity.md) |
| `Widget.environment_boundary` | 1 | Removed; SwiftUI environment inheritance | [Contract](swiftui-host-environment.md) |
| `Widget.focus_scope` | 1 | View.focus_scope | [Contract](swiftui-keyboard.md) |
| `Widget.icon` | 1 | View.symbol with named SF Symbols | [Contract](swiftui-symbols.md) |
| `Widget.image` | 1 | View.image | [Contract](swiftui-images.md) |
| `Widget.keyboard_listener` | 1 | View.keyboard_listener; UIKit capture implemented, physical acceptance pending | [Contract](swiftui-keyboard.md) |
| `Widget.mouse_region` | 1 | View.hover_region | [Contract](swiftui-pointer-events.md) |
| `Widget.navigator` | 1 | View.Navigation_stack | [Contract](swiftui-navigation-stack.md) |
| `Widget.page` | 1 | View.Navigation_stack destinations and View.Sheet | [Contract](swiftui-sheet.md) |
| `Widget.preferred_size` | 1 | View.frame and toolbar/page composition | [Contract](swiftui-page-layout.md) |
| `Widget.pressable` | 1 | View.button | [Contract](swiftui-button-focus.md) |
| `Widget.rich_text` | 1 | View.rich_text with styled spans | [Contract](swiftui-rich-text.md) |
| `Widget.safe_area` | 1 | View.ignores_safe_area and View.safe_area_padding | [Contract](swiftui-safe-area.md) |
| `Widget.transform` | 1 | View.projection_effect | [Contract](swiftui-projection.md) |

## Remaining per-entry audit

For each value, record its exact current API or explicit removal rationale,
its Swift implementation, both-platform Gallery scenario, and a meaningful
interaction test with observed results. For every named sum constructor,
record whether its behavior is preserved, consolidated into composition, or
intentionally removed with a stated rationale. Review parameter records and
optional arguments too. All inventory entries currently remain pending this
audit; family links do not substitute for it.

UIKit KeyboardListener now has native capture code; its physical acceptance
gap remains explicitly recorded. Compilation,
frame staging, a selected macOS test or a placeholder does not establish
physical iOS behavior. See the [full proposal](agent-guide/proposed/architecture/2026-09-11-swiftui-only-apple-backend.md)
for the complete acceptance criteria and [implementation ledger](swiftui-implementation.md)
for existing checkpoint evidence.

The civil selection review now records exact APIs and optional-argument changes
for Material.Date, Date_picker, Time and Time_picker. Both old date-page modes
have explicit removal rationales; both hour-format variants map to current
View.Time_picker variants. The shared Gallery entrypoint has native macOS
control-to-OCaml tests. These API reviews leave overall entries pending because
physical iOS, accessibility and complete variant acceptance remain unfinished.
