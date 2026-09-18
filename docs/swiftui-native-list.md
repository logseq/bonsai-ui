# Native List and row actions

`View.Native_list` composes SwiftUI List/Section with native intrinsic row sizing.
Sections and rows require stable, sibling-unique keys. Each section may contain a
header and footer. `vertical` requires `~style:Plain`, `Inset`, or
`Inset_grouped`; the last style is iOS-only and is rejected explicitly on macOS
before publication. Row and section separator visibility independently accepts
`Automatic`, `Hidden` or `Visible`.

```ocaml
let actions =
  Ui.View.Swipe_actions.create ~allows_full_swipe:true
    ~actions:
      [ Ui.View.Swipe_actions.action ~key:(Ui.Key.string "delete")
          ~side:End ~title:"Delete" ~symbol:"trash" ~role:Destructive
          ~background:(Ui.Style.Color.rgb ~red:220 ~green:30 ~blue:30)
          ~on_press:delete_handler () ] ()
in
Ui.View.Native_list.vertical ~style:Plain
  [ Ui.View.Native_list.section ~key:(Ui.Key.string "inbox")
      ~header:(Ui.View.text "Inbox")
      [ Ui.View.Native_list.row ~key:(Ui.Key.string "message")
          ~swipe_actions:actions (Ui.View.text "Message") ] ]
```

Swipe and [context menu](swiftui-context-menu.md) descriptors are explicit row-owned slots, separate from the ordinary label
and child rows. `Swipe_actions.create` returns a descriptor, not a widget. The
obsolete `~content` wrapper constructor is removed. Every action has a stable,
sibling-unique key. Parent actions attach only to the parent's label, so expanded
children retain independent native action owners.
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

The optional `on_visible_range` reports a half-open range through
`Event.Payload.Visible_range`. Its indices follow the depth-first sequence of
currently expanded logical rows. Disclosure parents count; headers, footers, and
collapsed descendants do not. It is an
observation of native row visibility, not a sparse-materialization request.
The application supplies loaded rows and decides when/how to load more. Mail
uses this observation with its existing paging reducer. Generic Collection is
unchanged and still supplies its separate sparse virtualization contract.

List and swipeActions are available on the iOS 26+ and macOS 26+ baselines. macOS
uses native trackpad swipe semantics; mouse dragging is not an SDK substitute.
Appearance, accessibility actions and separator details follow system behavior.

## Hierarchical rows

`Native_list.disclosure_row` takes a label, controlled expansion state and handler,
optional swipe/context actions, separators, and independently keyed child rows:

```ocaml
Ui.View.Native_list.disclosure_row ~key:(Ui.Key.string "outline-parent")
  ~expanded ~on_expanded_changed:expansion_handler
  ~label:(Ui.View.text "Notes")
  [ Ui.View.Native_list.row ~key:(Ui.Key.string "child")
      (Ui.View.text "Child note") ]
```

The expansion handler receives `Event.Payload.Bool`. OCaml decides whether to
accept the change and supplies the next `expanded` value. Native expansion,
ordinary label controls, and row actions remain distinct. In a native List,
SwiftUI can report both label activation and expansion for the same accessibility
activation; the framework arbitrates those callbacks within that native callback
turn so opening a label does not also expand it.

Keys are unique among siblings, including actions within their own descriptor.
A label's keys and a child row's keys have separate ownership scopes. Moving a
row into another parent creates a new incarnation and revokes the old callbacks.
Collapsed descendants remain in the logical tree but cannot receive input or
appear in native accessibility. Their state and loaded content stay in OCaml.

## Explicit row scrolling

A scroll request belongs to one List instance. Its positive token increases for
each new command, even when targeting the same row again. Target keys are scoped
to the List and section; the row ancestry path must be nonempty. In the flat
case the path contains one key. Do not target a section header.

```ocaml
let target =
  Ui.View.Native_list.target
    ~section:(Ui.Key.string "journal")
    ~row_path:[Ui.Key.string "entry-42"]
in
let request =
  Ui.View.Native_list.scroll_request ~token:next_token ~target
    ~anchor:Center ~animated:true ()
in
Ui.View.Native_list.vertical ~style:Plain
  ~scroll_request:request ~on_scroll_completed:completion_handler sections
```

Decode the completion handler payload with
`Ui.View.Native_list.completion_of_payload`. It returns the request token and
`Succeeded`, `Missing_target`, `Hidden_target`, `Cancelled`, `Superseded`, or
`Positioning_failed`. A request requires a completion handler. Removing the
optional request cancels pending work; a newer token supersedes it. Repeating a
settled token does not move again, and changing that token's payload is invalid.

The native owner captures the target row incarnation before waiting for mounting.
Missing rows fail immediately; inserting a later row with the same key does not
retarget an old request. Admission waits at most 500 ms for the mounted,
acknowledged List. A lazy offscreen cell need not exist before issuing the native
scroll. Positioning then has a two-second bound. Success requires two native
geometry observations at least 16 ms apart, aligned within one point. Top,
Center, and Bottom use the full native row rectangle and actual viewport, with
clamping at content boundaries and defined alignment for rows taller than the
viewport. Visibility alone does not establish success.

Clearing, user scrolling, deactivation, and target replacement stop movement and
finish cancellation. Disposal revokes callbacks. Completion retains the original
handler across later rebindings, without retaining whole historical render trees;
transport retries never repeat movement. Reduce Motion and immediate requests
suppress animation. Returning from detail should leave the request unchanged or
absent: preserve the native List instance and let it retain its position.

macOS hosted tests cover these positioning and cancellation behaviors. The iOS
26 branch typechecks, but physical iPhone scrolling and gestures remain unverified.
