# Native context menus

`View.Context_menu` supplies keyed native menu actions for ordinary views and
native List labels. Titles, optional SF Symbols, enabled state and
`Normal | Destructive` roles are typed descriptors. Each action uses an ordinary
OCaml `Event.Handler.t`; selection delivers `Event.Payload.Unit` through `Press`.

```ocaml
let menu =
  Ui.View.Context_menu.create
    ~actions:
      [ Ui.View.Context_menu.action ~key:(Ui.Key.string "delete")
          ~title:"Delete" ~symbol:"trash" ~role:Destructive
          ~on_press:delete_handler () ] ()
in
Ui.View.Context_menu.attach ~key:(Ui.Key.string "entry-menu") menu
  (Ui.View.text "Open the context menu")
```

For native List rows, use the explicit `~context_menu` argument on
`Native_list.row` or `Native_list.disclosure_row`. Combine it with `~swipe_actions`
on the same row. Both native modifiers attach to the label. A parent's menu never
includes or owns its expanded descendants' actions. Ordinary label navigation
and controlled disclosure expansion remain independent.

Action keys are required and unique within a menu; separate rows may use the
same action key. Menus contain at most 64 actions. `create` produces an opaque
descriptor and `attach` produces an ordinary view. The row's label, swipe menu,
context menu and child rows have separate ownership slots. Generic modifiers
cannot replace those structural slots or wrap a row descriptor.

When the native interaction configures a menu, the framework captures its owner
incarnation, generation, action identities, properties and handler bindings.
Selection validates that snapshot immediately before ordinary event admission.
Changing a binding, disabling/removing an action, moving its owning row,
opening a newer menu, hiding the content or disposing the owner invalidates old
callbacks. A rejected selection is consumed and is never retried through a newer
handler. A new explicit menu opening creates a fresh presentation.

AppKit and UIKit own menu presentation, layout and dismissal. macOS renders
SwiftUI Button/Label content through NSHostingMenu; iOS uses UIContextMenuInteraction
and UIMenu with native action attributes. Both preserve destructive styling and
native menu accessibility. The public API does not require custom overlays or native-view
registration. It supports the framework's iOS 26 and macOS 26 baselines. The
Gallery swipe sample demonstrates both menu and swipe actions on each row.

A noninteractive background anchor supplies the label bounds without replacing
its native controls or intercepting primary input. Interaction is scoped to the
anchor's current presentation and content eligibility. AppKit observes the
window's context-click event; UIKit installs its interaction on the anchor's
containing ViewController view, including native sheets. UIKit previews use a
cropped immutable snapshot of the label; the live window is never a preview
view. Collapsed, clipped or inactive labels cannot open a menu. SwiftUI’s cached contextMenu builder is deliberately
not the snapshot boundary: a hosted regression shows it can rebuild a selected
handler during native tracking. Each platform adapter instead creates an immutable
action snapshot for each actual menu configuration. Physical iPhone tests verify
parent/child action isolation, navigation-link menu/swipe coexistence, and menus
inside native sheets. VoiceOver remains unverified; exact attempts and captures
are recorded in the implementation report.

## Wire structure

Protocol 10 uses node 146 for the action owner (`enabled`), node 147 for each
keyed action (`action_key`, `title`, `enabled`, `role`, optional `symbol`), and
node 148 for an ordinary view attachment. An attachment has exactly two children:
base content and menu owner. The menu owner contains only actions. Enabled
actions have exactly one Press binding; disabled actions have none.

Native List rows contain label slot 145, swipe owner 42, context owner 146, then
child rows. Leaves have exactly three slots. The decoder rejects orphan actions,
duplicate action keys, invalid roles, empty titles/symbols and retained action
incarnations transplanted into another owner before publishing the tree.
