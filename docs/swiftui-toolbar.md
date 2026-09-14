# Native toolbar composition

`View.Toolbar` attaches ordinary core controls to a navigation page or window's
SwiftUI toolbar. Apply `Toolbar.create` to the page content inside a
NavigationStack destination, or use `Body.toolbar` on bounded content supplied to
a native container. A toolbar modifier requires a system navigation/window host;
it does not draw a freestanding bar inside arbitrary layout content.

```ocaml
let items =
  [ View.Toolbar.item ~key:(Key.string "create") ~placement:Primary_action
      (View.button ~on_press:create
         ~child:(View.label ~title:(View.text "Create")
                   ~icon:(View.symbol ~name:"plus" ()) ()) ())
  ; View.Toolbar.item ~key:(Key.string "pinned") ~placement:Primary_action
      (View.toggle ~value:pinned ~on_changed:change_pinned
         ~style:View.Toggle_style.Button ~label:(View.text "Pinned") ())
  ]
in
View.Toolbar.create ~items page_content
```

Each item has a required stable application key and one ordinary view subtree.
Button, Toggle, Menu, Picker, Label and text retain their existing input,
accessibility and enabled-state contracts. An action's handler can close over an
application's signed command ID; the toolbar does not introduce an index-based
shared action event. Commands, controlled selected state and destructive roles
belong to their individual controls. A single-choice action group can use Picker;
a Boolean command uses Toggle.

There are nine cross-platform semantic placements:

| OCaml placement | SwiftUI placement |
| --- | --- |
| Automatic | automatic |
| Principal | principal |
| Navigation | navigation |
| Primary_action | primaryAction |
| Secondary_action | secondaryAction |
| Status | status |
| Confirmation_action | confirmationAction |
| Cancellation_action | cancellationAction |
| Destructive_action | destructiveAction |

The renderer uses a ToolbarItemGroup for each placement and keyed ForEach views
inside it. This structure supports physical iOS 18, without relying on newer
ForEach-of-ToolbarContent APIs. The native host determines ordering between
placements, system insets, grouping and overflow; source order applies within
each placement. See Apple's [toolbar placements](https://developer.apple.com/documentation/swiftui/toolbaritemplacement)
and [toolbar presentation guidance](https://developer.apple.com/videos/play/wwdc2022/110343/).

The old Material.Toolbar API, component 19 and its seven-icon enum are removed.
Use SF Symbols through ordinary Labels. Primary actions, including the former
FAB command, are normal Buttons in Primary_action. Material Floating/Docked,
axis, max-inline-actions, expanded and active-action property bags are removed.
The system owns toolbar overflow presentation. Application-specific floating
content can still use bounded Body/viewport overlays; see [page composition](swiftui-page-layout.md).
A required custom expanded region should be represented by explicit application
state and DisclosureGroup or Sheet, rather than by an alternate toolbar renderer.

## Identity and validation

Empty item lists remove the toolbar's controls while preserving its content.
The limit is 256 items, with unique keys and at most one Principal item. These
constraints are checked before constructing the OCaml view. Item subtrees retain
their render identity through reorder and placement changes. Removing an item
retires its node and handler; reintroducing the same application key after removal
does not revive old callbacks.

Node 74 has one property, `placements`, mask 1. Its encoding is a u16 count and
one u8 value in 0..8 per item. Its children are the page content followed by the
item subtrees in matching order. It has no event bindings. The Swift boundary
requires exactly count+1 children, rejects duplicate Principal placements,
unknown values, excessive counts and truncated updates before publication.
OCaml encoding and decoding validate the same placement rules. The retired
component-19 encoding is rejected in both directions.

Toolbar command input requires current and presented toolbar properties and
child ordering to match. This fences callbacks while a placement/reorder/removal
update awaits presentation. Body content continues to use its normal input
rules. Ancestor tab, navigation, modal and session visibility gates also apply.
There is no new parallel action dispatcher or compatibility event adapter.

## Verification

`Toolbar_catalog.component` is shared by Gallery and the actual native runtime
fixture `native-toolbar`. It composes a principal label, action Button, controlled
Pin Toggle and a secondary Menu with an unavailable action. Body controls reverse
items, move the action, enable/disable it and remove/restore all items. OCaml owns
the action count and selected state independently of toolbar lifetime.

The native runtime regression covers repeated actions, retained identity,
presentation fencing, disabled controls, removal/reinsertion, stale callbacks,
hidden sessions and shutdown. Swift staging tests cover reorder, removal to an
empty toolbar and malformed updates without changing the published tree.

The standalone SwiftUI App test finds the actual window toolbar's native Button
and Pin Toggle through public accessibility. Both controls update the OCaml state.
It checks repeated actions, reordering, disabled presentation, removal/restoration,
stale native control activation and state retention across window resize. The
same harness passes the other four system navigation scenarios independently.

Top/bottom AppBar now uses [native page bars](swiftui-app-bars.md). Scrolling
headers, search, complete Gallery, physical-device
interaction, keyboard/VoiceOver acceptance and runtime screenshots remain
separate migration or acceptance work. Toolbar customization persistence and
physical overflow interaction are not established by the staging/runtime tests.
