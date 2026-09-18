# Native List and row actions

`View.Native_list` composes SwiftUI List/Section with native intrinsic row sizing.
Sections and rows require stable, sibling-unique keys. Each section may contain a
header and footer. Row and section separator visibility independently accepts
`Automatic`, `Hidden` or `Visible`.

```ocaml
let content =
  Ui.View.Swipe_actions.create
    ~key:(Ui.Key.string "message-actions")
    ~allows_full_swipe:true
    ~actions:
      [ Ui.View.Swipe_actions.action
          ~side:End ~title:"Delete" ~symbol:"trash" ~role:Destructive
          ~background:(Ui.Style.Color.rgb ~red:220 ~green:30 ~blue:30)
          ~on_press:delete_handler () ]
    ~content:(Ui.View.text "Message") ()
in
Ui.View.Native_list.vertical
  [ Ui.View.Native_list.section ~key:(Ui.Key.string "inbox")
      ~header:(Ui.View.text "Inbox")
      [ Ui.View.Native_list.row ~key:(Ui.Key.string "message") content ] ]
```

Swipe_actions must be the immediate content of a Native_list row. Put decorations
inside its `content`. The renderer rejects actions outside this composition.
SwiftUI owns horizontal gesture recognition, reveal layout, closing and full
swipe. Start and End follow layout direction. `allows_full_swipe` defaults to
false; when enabled, the system invokes the first action on that side. Action
labels, SF Symbols, tint, semantic roles and enabled state are explicit. OCaml
owns effects and removal. Pending admission is released only by the matching
pumped event, and obsolete callbacks cannot target replacement handlers.

Vertical swipe, explicit action extents, arbitrary action child content, group
closing policies and per-action full-swipe/auto-close settings are removed.
There is no custom imitation behind the standard API. Removal remains a separate,
out-of-scope custom control and owns its own pan adapter.

The optional `on_visible_range` reports a half-open flattened row range through
`Event.Payload.Visible_range`; headers and footers do not count as rows. It is an
observation of native row visibility, not a sparse-materialization request.
The application supplies loaded rows and decides when/how to load more. Mail
uses this observation with its existing paging reducer. Generic Collection is
unchanged and still supplies its separate sparse virtualization contract.

List and swipeActions are available on the iOS 18+ and macOS 26+ baselines. macOS
uses native trackpad swipe semantics; mouse dragging is not an SDK substitute.
Appearance, accessibility actions and separator details follow system behavior.
