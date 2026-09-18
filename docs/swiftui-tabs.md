# Native Tabs

`View.Tabs` composes persistent application pages with SwiftUI `TabView` and
`Tab`. Each item supplies a stable page key, literal title, SF Symbol name and
bounded `View.Body.t`. Scroll and collection viewports belong inside that body;
the API does not expose an unrestricted viewport-to-view conversion.

```ocaml
let mail = ID.Navigation.Page_key.of_string "mail" in
let chat = ID.Navigation.Page_key.of_string "chat" in
View.Tabs.create ~selection:mail ~on_change
  [ View.Tabs.item ~page_key:mail ~title:"Mail" ~symbol:"tray"
      ~badge:"3" ~accessibility_label:"Inbox messages" mail_body
  ; View.Tabs.item ~page_key:chat ~title:"Chat" ~symbol:"bubble.left" chat_body
  ]
```

One to 256 items are allowed. Keys must be nonempty and unique, and selection
must identify an item. Keys compare by their exact UTF-8 bytes, including in
Swift's native selection binding. Canonically equivalent Unicode strings can
therefore identify different pages, matching OCaml identity. Omitted application
keys derive from the page key. Item order is independent of selected identity.
Symbol names must be nonempty. Titles are literal application text.

Optional badge text and an independent accessibility label are literal strings.
A present value must not be blank under OCaml String.trim's ASCII whitespace
rules. Omit a value to remove that metadata and use native defaults. Badge text
can represent a count, including "0" and a large exact integer string, or a short
indicator such as "•". The renderer passes Text to native TabContent.badge rather
than converting counts through a floating-point value or a zero-hiding integer
badge overload. Use application-localized words when a textual indicator needs
more context. The accessibility label uses TabContent.accessibilityLabel and does
not replace the visible title. Both modifiers compile for physical iOS 26.
See Apple's [tab metadata API](https://developer.apple.com/documentation/swiftui/tabcontent).

Material.Tabs is removed. Its single-selection strip is represented by
View.Picker with Segmented style, stable signed option IDs and native composed
labels. Primary/Secondary Material appearance variants are removed. Application
pages use View.Tabs; a selection strip alone does not create hidden page bodies.
See [native Picker](swiftui-picker.md).

Material.navigation_bar and its destination descriptors are also removed.
Application navigation now uses these keyed pages instead of a standalone bar
that emits a selected index. OCaml owns the selected page key and receives event
52. Titles, SF Symbols, optional badge text and accessibility labels belong to
each native Tab. An application can derive its symbol from the selected state;
SwiftUI owns the default selected appearance. Container accessibility can use
View.semantics with Children.Contain.

The former arbitrary icon-view slots and Material-specific label/icon visibility,
alignment, sizing, shape, density and safe-area switches are removed. Native tab
layout and system insets determine presentation; core view modifiers compose
surrounding content. Gallery's redundant static bars are consolidated into its
interactive tabs scenario. Persistent footer content remains a fixed Body child.

The system supplies tab controls, layout and platform adaptation. There is no
custom bottom-bar implementation or platform-independent promise about bar
placement. See Apple's [Tab](https://developer.apple.com/documentation/swiftui/tab)
and [TabView](https://developer.apple.com/documentation/swiftui/tabview) APIs.
The implementation targets physical iOS 26+ arm64 and macOS 26+ arm64 only.

## Selection and retained content

A native selection emits `Event.Payload.Tab_selected page_key`. OCaml owns the
accepted selection. Native state changes only after queue admission; an
unchanged OCaml response restores the previous selection when a handler declines
the request. Consecutive selections for the same owner, handler and displayed
revision coalesce. Each admitted request has a local serial, so an older response
cannot clear a newer request even when both select the same page.

Removing or replacing a page invalidates its pending selection. Retained bindings
record their most recent getter generation: writes from a stale read are rejected,
while a fresh read can continue to use a retained SwiftUI binding. Accepting an
unchanged native selection does not invalidate that read: SwiftUI may reuse its
cached selection without another getter call. A timing-independent regression
covers a second native selection after acknowledgment. Teardown rejects
further requests. Current and presented owner, page identities/metadata, children and handlers
must match before selection input is admitted. A selection echo awaiting
presentation does not disable the native tab control: a later intent can queue
with the actual displayed revision until that presentation is acknowledged.

All logical pages stay mounted. Reordering and switching preserve their render
objects and OCaml state. Input from a page is admitted only when every enclosing
tab agrees in native state and both the current and presented OCaml trees. Hidden-page
callbacks and callbacks from either page during an unconfirmed switch cannot
mutate application state. This includes nested tab containers through ancestor
checks. The check covers event admission; native focus/IME handoff and background
animation suspension across tab changes still need dedicated acceptance tests.

## Wire representation

Node 31 (`tabs`) has selection as one nonempty UTF-8 string, property mask 1,
one event-52 binding, and one to 256 directly owned tab children. Node 40 (`tab`)
has a page key, title and symbol string, then optional badge and accessibility-label
strings. Its property mask is 31; it has one content child and no bindings.
The previous three-property encoding and mask 7 are removed. Tab nodes are invalid outside their owning tabs container.
Event 52 carries the nonempty selected page key.

Retired navigation-bar node 115 has no constructor, property encoding, generated
ID or renderer registration. A regression uses a formerly valid update frame and
requires Unknown_node_kind, rather than accepting the old bar or translating it.

Both language boundaries reject empty keys and symbols, invalid optional-string
tags and blank present metadata. Swift stages the entire
graph before publication and rejects missing selections, duplicate keys, invalid
ownership, child counts, bindings and malformed updates without altering the
displayed tree. The public OCaml constructor validates item count, keys and
selection before mounting.

## Verification and remaining Mail integration

Gallery's `tabs_component` exercises the public API with separate counters,
typed scroll bodies, selection locking and keyed reordering. A metadata action
cycles no badge, zero, the largest signed OCaml integer count, a bullet indicator,
and back to native defaults. Metadata updates preserve page objects and fence
selection until the changed metadata is presented. Native runtime tests
execute its actual OCaml handlers and verify retained counters/render objects,
accepted and declined selections, presentation fencing, hidden-page callbacks,
invalid selections and disposal. Native view tests render selected content and
retain it after reordering. Controller tests cover coalescing, repeated-page
requests, removed pages and captured bindings; malformed graph tests also include
all truncated update prefixes and byte-distinct Unicode keys.

The standalone SwiftUI App test activates the system tab radio controls through
public accessibility, then verifies the resulting OCaml selection text. It
increments Mail, switches to Chat, rejects a locked switch, returns to Mail and
reorders the tabs while retaining the counter. It also cycles the metadata and
selects the system tab using the new accessibility label, then verifies the
original label is restored when the override is removed. Some SwiftUI radio elements
perform their action while returning false from the accessibility press method;
the test verifies application state rather than trusting that return value.

The shared App harness now uses separate window identifiers for stack, split and
tab scenarios. It explicitly establishes the wide split size before assertions;
restoring a smaller previous test window must not change the tested layout.
That isolation keeps scenario geometry independent, but did not resolve an
intermittent sidebar callback rejection. The subsequent unchanged-echo binding
fix addresses that rejection and is covered by repeated system-sidebar cycles.

Mail now composes these tabs with native split columns; see [Mail navigation](swiftui-mail-navigation.md). Native scroll-position preservation, focus/IME handoff,
physical iOS tab interaction, complete Mail rendering and Mail screenshots remain
separate acceptance work. These tests do not constitute a completed Mail port.


Badge visual acceptance still needs a reviewable runtime capture. The macOS
native TabView hosts its tab control inside one toolbar item; querying badges
on individual NSToolbarItems does not inspect the badges within that control.
The test therefore does not claim to establish badge appearance from that query.
Wire round trips, literal metadata preservation and actual system accessibility
label updates are verified; exact native badge appearance remains part of the
outstanding visual/platform acceptance.
