# Native page bars

Material.App_bar.top and Material.App_bar.bottom are removed. Native navigation
titles and toolbar items supply top-of-page controls. Persistent bottom controls
are fixed children around a bounded scrolling region. The former Material bar
slots, center-title flag, safe-area Boolean and bottom FAB slot have no parallel
renderer or compatibility constructor.

Use Navigation_stack.create with a typed Body.t root. Destination content also
accepts Body.t. Ordinary content uses Body.static; scrolling content uses the
corresponding Body.Vertical or Body.Horizontal fill child. The stack is still an
ordinary View.t for use in a framework-owned container, matching Navigation_split
and Tabs. No arbitrary fixed height is needed to put a scroll viewport inside a
root or detail page.

```ocaml
let body =
  View.Body.Vertical.create
    [ View.Body.Vertical.fill (View.Scroll.vertical rows)
    ; View.Body.Vertical.fixed bottom_actions
    ]
  |> View.Body.toolbar
       ~items:
         [ View.Toolbar.item ~key:(Key.string "create") ~placement:Primary_action
             (View.button ~on_press:create ~child:(View.text "Create") ())
         ]
in
View.Navigation_stack.create ~title:"Inbox" ~path:[] ~on_path_change body
```

The native title handles the standard navigation title and its accessibility.
A custom title subtree can use Toolbar.Principal; independent leading commands
use Navigation and main actions use Primary_action. These are semantic placements,
not promises of pixel coordinates or identical placement on iOS and macOS. A
Menu provides additional commands. Native controls own their activation, roles,
enabled state and semantics; see [toolbar composition](swiftui-toolbar.md).

Bottom controls can use ordinary Buttons, Labels, Menus, Toggles and composed
layout. The former bottom FAB action is an ordinary primary Button; a separate
floating action uses Body/viewport overlays when the application needs it.
The containing navigation/window host supplies safe-area constraints. Explicit
edge behavior uses Body.safe_area_padding or Body.ignores_safe_area rather than
a Material AppBar flag. See [safe areas](swiftui-safe-area.md) and
[bounded page composition](swiftui-page-layout.md).

## Ownership and scope

Each navigation page owns its own toolbar and bottom content. OCaml owns actions,
accepted navigation paths and any selected state. Root content stays mounted
logically while a destination is open, but root toolbar and bottom-control
callbacks cannot act on the covered page. Closing the destination or accepting a
system Back request reveals the retained root state. A removed destination's
callbacks cannot act on the restored page.

Changing bottom content height changes the scroll region's available height.
The bottom controls remain fixed while the rows scroll. The catalog exercises
60- and 100-point bottom regions; applications choose their own layout and sizing.
These explicit demo dimensions are not framework-wide toolbar or footer heights.

## Catalog and protocol

App_bar_catalog is shared by the Gallery preview and the native-app-bars fixture.
It includes independent leading/top actions, a bottom action and an icon-only
Compose action with a native accessibility label/help. Controls resize the bottom
region and open a scrollable detail page with its own toolbar and Close control.
OCaml retains the action count and bottom-size state across navigation.

Gallery's main root now uses NavigationStack, a real increment-counter toolbar
command and fixed bottom status around its bounded body. Its old static top and
bottom Material bar demonstrations are removed. The combined Gallery uses
the SwiftUI backend; complete behavioral and physical-device acceptance remain
open. Its outer scrolling header uses [native sections](swiftui-scroll-sections.md).

No new wire node or event is needed. Native stack/destination nodes 13/14 still
carry titles and route identities; toolbar node 74 and ordinary Button events
supply commands. The public bounded-body change removes the former View.t page
parameters. Retired expressive components 15 and 30 are rejected in encoding and
decoding; the old Flutter renderer cases are removed.

## Verification

The actual OCaml runtime regression verifies independent page actions, root node
retention, rejection of covered-page commands, destination removal, hidden
sessions and shutdown. The standalone SwiftUI App locates the native leading,
primary, detail and Back controls in the system toolbar, then checks their OCaml
results. It verifies fixed bottom controls during scrolling, a 40-point reduction
in the viewport when bottom content grows, window-width adaptation, bounded
destination scrolling and the retained root scroll position after system Back.
It also verifies that enabled root toolbar commands are absent on the detail page.

- `swift test --scratch-path _build/swift --filter actualAppBars`
- `python3 native/test/test_navigation_window.py NavigationWindowTests.test_native_app_bars_reach_actual_gallery`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`

Scrolling/collapsing headers now use [native sections](swiftui-scroll-sections.md),
and PreferredSize is removed. AppBar search now uses [native search composition](swiftui-search.md).
Complete Gallery migration remains
separate work. Physical iOS navigation, keyboard,
VoiceOver, dynamic text sizing and real Mail screenshots still require acceptance.
