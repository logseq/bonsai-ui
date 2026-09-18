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

There are nine cross-platform semantic placements and an iOS bottom bar:

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
| Bottom_bar | bottomBar (iOS only; explicitly rejected on macOS) |

Entries form an ordered list of independently keyed `item`, `group`, and `spacer`
descriptors. A group owns an ordered list of `Toolbar.child ~key` ordinary views.
Entry keys are unique across a toolbar; child keys are unique within their group.
Distinct groups sharing a placement remain distinct native groups. The host
controls ordering between semantic placements.

```ocaml
let open View.Toolbar in
let items =
  [ group ~key:(Key.string "journal-navigation") ~placement:Bottom_bar
      [ child ~key:(Key.string "journals") journals_button
      ; child ~key:(Key.string "favorites") favorites_button ]
  ; spacer ~key:(Key.string "capture-gap") ~placement:Bottom_bar Flexible
  ; group ~key:(Key.string "journal-capture") ~placement:Bottom_bar
      [ child ~key:(Key.string "capture") capture_button ] ]
in
create ~items page_content
```

`Fixed` and `Flexible` use genuine SwiftUI `ToolbarSpacer` values. Fixed spacing
is system-defined, with no pixel-width parameter. On macOS use supported
placements such as Navigation and Primary_action. Native ToolbarItem/ControlGroup
composition owns group materials, sizing and overflow; this API does not draw a
custom bar. iOS interaction and group appearance require device verification.

The old Material.Toolbar API, component 19 and its seven-icon enum are removed.
Use SF Symbols through ordinary Labels. Primary actions, including the former
FAB command, are normal Buttons in Primary_action. Material Floating/Docked,
axis, max-inline-actions, expanded and active-action property bags are removed.
The system owns toolbar overflow presentation. Application-specific floating
content can still use bounded Body/viewport overlays; see [page composition](swiftui-page-layout.md).
A required custom expanded region should be represented by explicit application
state and DisclosureGroup or Sheet, rather than by an alternate toolbar renderer.

## Identity and validation

Empty entry lists remove the toolbar controls while preserving its body.
There may be at most 256 entries, 256 children per group, and one Principal entry.
The body has an independent structural slot. Unchanged group and child keys
retain their render and native content owners through reorder, placement, and
ordinary content updates. Moving a child to a different group creates a new
owner; old callbacks remain invalid after removal or reintroduction.

Node 74 now has empty properties and contains body slot 151 followed by entry
nodes 149. An entry encodes its key string, placement u8 (0..9), and kind u8
(0 item, 1 group, 2 fixed spacer, 3 flexible spacer). An item owns one ordinary
view; a group owns keyed child slots 150, each containing one ordinary view;
spacers have no children. Child slots encode their key string. All structural
nodes have no event bindings. Swift validates scopes, bounds, native capability,
structural parents and child counts atomically before publication. The obsolete
placement-list encoding has been removed.

Ordinary command input requires current and displayed toolbar entry/child
structure to match. Body input retains its normal rules. Eligible focused inputs
can retain their existing owner while a structural update awaits presentation;
this does not admit other callbacks early. Controls remain direct SwiftUI content,
so the native toolbar can discover their command semantics before mounting them,
including when a window first appears with overflow. Text field and editor
controllers retain their native input views; lightweight representable mounts
transfer those views only when a new mount belongs to a window. An owner-scoped
focus transfer ends on native remount or after 500 ms, and is revoked by
ownership/session replacement, disabled/hidden content, disposal or a different
focus owner.

## Verification

`Toolbar_catalog.component` is shared by Gallery and the actual native runtime
fixture `native-toolbar`. It composes a principal label, action Button, controlled
Pin Toggle and a secondary Menu with an unavailable action. Body controls reverse
items, move or reparent the action, enable/disable it and remove/restore all items. OCaml owns
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
