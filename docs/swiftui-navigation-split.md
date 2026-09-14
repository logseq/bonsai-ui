# Native Navigation Split View

`View.Navigation_split.create` composes sidebar, content and detail columns.
`View.Navigation_split.two_columns` composes sidebar and detail using the native
two-column SwiftUI NavigationSplitView initializer. `Navigation.Split_state`
holds the visibility intent, preferred compact column and an optional application
selection key.
OCaml owns that state; native column changes request a new complete state.

```ocaml
let state =
  Navigation.Split_state.create
    ~visibility:Navigation.Split_visibility.All
    ~compact_column:Navigation.Split_column.Content
    ()
in
View.Navigation_split.create
  ~state ~sidebar_title:"Folders" ~content_title:"Messages" ~detail_title:"Reading"
  ~on_change ~sidebar ~content ~detail ()
```

For a sidebar/detail application, supply only the two real columns:

```ocaml
let state =
  Navigation.Split_state.create
    ~visibility:Navigation.Split_visibility.All
    ~compact_column:Navigation.Split_column.Sidebar
    ()
in
View.Navigation_split.two_columns
  ~state ~sidebar_title:"Folders" ~detail_title:"Reading"
  ~on_change ~sidebar ~detail ()
```

The two-column constructor requires Sidebar or Detail as the preferred compact
column. Content raises `Invalid_argument`; the shared state's default Content
is intended for three-column applications. There is no empty middle column,
legacy rail/drawer renderer or synthetic layout in this implementation.

Visibility choices are `Automatic`, `All`, `Double_column` and `Detail_only`.
Compact-column choices are `Sidebar`, `Content` and `Detail`. Defaults are
Automatic visibility, Content as the preferred compact column, and no selection.
The optional selection key must be nonempty and preserves exact UTF-8 identity.
Column titles and each bounded `View.Body.t` column are supplied
independently. Use `Body.static view` for ordinary content or a typed vertical/
horizontal body for scroll and collection viewports.

The host passes these intents directly to SwiftUI. They are subject to native
platform behavior: in a three-column split, macOS keeps the content column
visible even for Detail_only. Native automatic styling may overlay the sidebar
instead of reducing the main column's width. The system-control regression checks
`NSSplitViewItem.isCollapsed` and the native column count, because overlapping
column origins do not imply a failed visibility request. See [Apple's split
styles](https://developer.apple.com/documentation/swiftui/navigationsplitviewstyle).
Compact-column preference controls the collapsed presentation on iPhone and
other narrow size classes; narrowing a macOS window is not equivalent to testing
that iPhone presentation. Automatic visibility compares equal to a concrete
native visibility, so callbacks encode the concrete result before considering
any default value. See [Apple's visibility documentation](https://developer.apple.com/documentation/swiftui/navigationsplitviewvisibility)
and [preferred compact columns](https://developer.apple.com/documentation/swiftui/navigationsplitviewcolumn).

## State ownership and events

A native sidebar or compact-column change emits
`Event.Payload.Navigation_split_changed requested_state`. It carries both
column fields and the selection key the native view observed. Native controls
cannot replace the application selection key. A parent can use that key when
checking whether a queued request still applies to its selected item.

The session validates the current and presented owner, children, handler,
selection key and column titles, plus session activity and visibility, before
admitting an event. Column visibility/preference echoes alone do not invalidate
that semantic context. SwiftUI may report intermediate states and then a final
state while an earlier echo awaits presentation; the final request stays queued
with the actual displayed revision until the pending frame is acknowledged.
Changed selection, children, titles or handlers still reject the callback. No
frame acknowledgment or event revision is fabricated to admit these requests. The controller
updates native state only after queue admission. Consecutive split events for
the same owner/handler/presented revision coalesce to their latest complete
state. Updating visibility and compact preference during one native operation
therefore keeps both changes.

An OCaml response reconciles authoritative state. If the application declines
the request without changing its view, the unchanged response restores the
native state. Resolving an older submitted request does not erase a newer
pending native request. Changing the application selection invalidates pending
state for the previous selection; disposal rejects later callbacks. Switching
between two and three columns clears pending native state and invalidates
unread bindings. Two-column controllers and session admission reject Content
requests even if the request has an otherwise valid selection and handler.

SwiftUI retains split bindings across view updates. A binding records the
version of its most recent getter read rather than its construction version.
A write that has not observed a newer selection is rejected, while a retained
system binding that reads the current selection remains usable. A test first
caught valid system sidebar clicks being rejected by construction-version
checks; the native App test now covers that interaction. Acknowledging native state does not advance the read generation when the
visible value stays identical. Otherwise a retained system binding could be
rejected on the next click despite having no changed value to read again. A
regression test reproduces this without timing assumptions, and the standalone
App now repeats three native sidebar hide/show cycles. Physical interactive
back cancellation still needs device acceptance, so this read-version check is
not claimed as proof of that entire gesture lifecycle.

## Wire representation

Node 15 has exactly two or three ordinary children and exactly one event-51 binding.
An absent content title selects two children (sidebar, detail); a present content
title selects three (sidebar, content, detail), including when the title is empty.
Its property mask is 63:

| Field | Encoding |
| --- | --- |
| Visibility | u8: Automatic 0, All 1, Double_column 2, Detail_only 3. |
| Compact column | u8: Sidebar 0, Content 1, Detail 2. |
| Selection key | Strict optional UTF-8 string; a present key cannot be empty. |
| Sidebar title | UTF-8 string. |
| Content title | Strict optional UTF-8 string; absence means no content column. |
| Detail title | UTF-8 string. |

Event 51 carries the first three fields. Both language boundaries reject
invalid enum values, invalid optional-string tags and empty selection keys.
Two-column properties cannot prefer Content; both OCaml encoding/decoding and
Swift decoding reject that combination. Child count must match the selected
column structure. Malformed updates reject the candidate without modifying the
displayed tree. The previous required-string encoding is removed.

## Verification and remaining Mail integration

Gallery's `split_component` supplies three columns by default and two columns
with `~two_columns:true`. It selects a message,
clears selection, requests the sidebar and can decline native column changes.
Both configurations appear in the Gallery tree and run independently through
the production native runtime fixture (`native-split` and
`native-split-two-columns`).

Native window tests render both column structures in explicitly All, wide
configurations and inspect the actual NSSplitView column count. Real OCaml tests cover selection updates, presentation fencing,
accepted changes, unchanged responses that decline a change, retained node
objects and teardown. Controller/event tests cover consecutive change
coalescing, an older response arriving behind a newer request, queue rejection,
byte-distinct Unicode selection and retained/stale binding reads.

`native/test/test_navigation_window.py` runs separate SwiftUI App processes for
NavigationStack system Back, both Gallery split configurations and Gallery tabs. The split scenario
selects a message, triggers the native system sidebar
control to hide and restore the sidebar, observes the corresponding OCaml text
updates, resizes the window and retains the selected detail. It uses public
accessibility on a hosted toolbar control or the standard item's public
target/action, according to the actual native toolbar item. The application is
compiled once for the four navigation scenarios, native toolbar and page-bar scenarios.
Each has a separate window identifier;
the split test explicitly establishes its wide size before checking columns.
`make swift-test` includes all six tests.

Mail now integrates the native split and tabs; see [Mail navigation](swiftui-mail-navigation.md).
Its old combined shell and custom tab bar have been removed. Native swipe,
morphing and Sheet/Popover implementations are covered in their dedicated guides.
NavigationRail/NavigationDrawer now use [sidebar composition](swiftui-sidebar-composition.md).
Legacy navigation bars now use keyed native TabView pages; Material Tabs uses
segmented Picker. Physical iOS compact/back behavior and full Mail runtime screenshots remain
open.
