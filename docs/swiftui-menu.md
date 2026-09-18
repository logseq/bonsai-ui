# Native Menus

`View.Menu` replaces `Material.Menu`, `Material.Split_button` and
`Material.Fab_menu`. Menus use SwiftUI Menu, Button, Toggle, Section and Divider.
There is no expressive-node decoder or old constructor alias for these controls.

## Public composition

Each entry has a unique signed Int64 identity, including dividers and sections.
Labels are ordinary View values, supporting text and SF Symbol composition with
`View.label`. Use:

- `Menu.action ~id ~label ?enabled ?role ()` for an action.
- `Menu.choice ~id ~label ~selected ?enabled ()` for a checked choice.
- `Menu.divider ~id` for a separator.
- `Menu.section ~id ?label entries` for a group.
- `Menu.submenu ~id ~label ?enabled entries` for a nested menu.
- `Menu.create ?key ?enabled ~on_select ~label entries` for the anchor and contents.

Choices send an ID, and OCaml determines the next checked values. Applications
can implement single or multiple selection without a second native selection
model. Each action is delivered separately, including repeated identical IDs.
Menus reject empty contents, duplicate IDs anywhere in the hierarchy, more than
1024 entries or nesting beyond 32 levels. Sections and submenus must have children.

A primary action with secondary options is a `View.row` containing a normal
`View.button` and `View.Menu.create`. Core Button styles and enabled state remain
available independently. The former FAB menu uses a labeled symbol anchor and
labeled action entries. Placement belongs to application layout; the Material
left/right placement flag and alternate collapse icon are removed. SwiftUI owns
menu opening, dismissal and platform presentation. Menus retain SwiftUI’s automatic
style so toolbar overflow can discover and render their native submenus.

Apple documents how [adaptive menu controls](https://developer.apple.com/documentation/swiftui/populating-swiftui-menus-with-adaptive-controls)
map Button to actions, Menu to submenus and Section to groups. On the tested Mac,
a disabled submenu's container can remain expandable. All of its descendant
actions are disabled in the native menu and rejected by session admission. The
renderer explicitly propagates branch availability to descendants. No AppKit
introspection or replacement menu is used in production to alter this presentation.

## Identity, wire and input

Node 61 is `menu`. Its properties are a counted preorder entry list and an enabled
flag; the full property mask is 3. Each entry carries its signed ID, kind, enabled
and checked flags, action role, label presence and immediate child count. Label
views are ordinary keyed child nodes: the anchor first, followed by each entry's
label in preorder. Interactive labels use entry IDs for stable child identity.

OCaml and Swift validate the same count, depth, uniqueness and shape constraints.
Malformed kinds, roles, checked flags, label presence, child counts and bindings
cannot stage. Disabled menus have no event binding. Menu labels are presentation
content and cannot independently emit child Button actions.

Event 54, `menu_action`, carries a signed Int64. The native queue never coalesces
menu actions. The controller tracks pending actions and temporary checked values,
then reconciles the final state with OCaml. No-diff rejection restores the checked
state too. A later pending action survives resolution of an earlier pump.

Admission requires the displayed epoch and revision, current node, matching
configuration, matching handler and label-child identities, an enabled action
and enabled ancestors, and active visible content. Submenu, section and divider
IDs are not actions. Replacing configuration, child identities or bindings fences
retained menu closures and clears their pending state. Disposal also invalidates
callbacks. Plain checked-state echoes preserve the existing action identities.

## Gallery and verification

`Gallery.menu_component` is included in `Gallery.picker_component` and embedded
as `native-menu` for integration tests. It exercises repeated signed actions,
checked choices, sections, disabled actions and submenus, ignored changes, enabled
state and handler replacement. Static Gallery examples demonstrate symbol anchors,
icon labels and primary-action-plus-menu composition.

Swift tree tests cover malformed menu shapes, limits, duplicate IDs, stale handler
closures and non-coalesced event ordering. Real runtime tests verify actual OCaml
updates, repeated no-diff rejection, disabled ancestors, pending presentation,
hidden sessions and disposal. OCaml tests exercise the public constructor limits,
logical identity and full/incremental property round trips.

`native/test/test_menu_window.py` builds a separate SwiftUI application and
requires both successful process completion and its explicit PASS result.
SwiftUI populates the native menu lazily when it opens. The test opens its own
menu, closes its tracking loop with a timer, invokes native item actions and
checks OCaml state and native checkmarks after reconciliation. The standalone
App is necessary: menu tracking in the Swift Testing process caused that process
to exit without a completed test report, so status zero alone was insufficient.

These application-local native actions do not establish physical mouse, keyboard,
VoiceOver or iOS device acceptance. Performance at the maximum menu size, full
visual acceptance and physical interaction remain outstanding. This widget work
does not satisfy the Mail screenshot requirement.
