# Native Navigation Stack

`View.Navigation_stack` describes a SwiftUI NavigationStack with one root and
an ordered destination path. OCaml owns the accepted path; SwiftUI owns native
back-button and interactive transition behavior. This surface has no Flutter
page-transition or restoration-ID parameters.

```ocaml
let detail =
  View.Navigation_stack.destination
    ~page_key ~title:"Message" (View.Body.static message_content)
in
View.Navigation_stack.create
  ~title:"Inbox" ~on_path_change ~path:[ detail ]
  (View.Body.Vertical.create
     [ View.Body.Vertical.fill (View.Scroll.vertical inbox_content) ])
```

Root and destination content accept `View.Body.t`, replacing the former ordinary
view parameters. This supplies native page constraints to typed scrolling content
without an arbitrary fixed-size conversion. Static content uses Body.static. The
stack returns View.t for embedding in a native container, as Tabs and Split do.
Page toolbars and fixed bottom content compose within the body; see
[native page bars](swiftui-app-bars.md).

The root is outside the path. A destination is an opaque value, so arbitrary
views cannot be inserted into the path. Each destination has a nonempty page
key, title and `can_pop` flag, which defaults to true. Its default application
key derives from its page key; an explicit application key is also supported.
Keys must be unique within a stack. A stack accepts at most 256 destinations.
Page keys preserve exact UTF-8 identity, including canonically equivalent but
byte-distinct Unicode strings.

A native back operation delivers
`Event.Payload.Navigation_path_changed remaining_page_keys`. The remaining
keys must be a strict prefix of the presented path. Returning several levels
is one event, avoiding partially admitted sequences of individual pop events.
Every removed destination must allow popping. Programmatic pushes and path
replacement originate in OCaml, not from an unvalidated native destination.
Applications accept a request by publishing the requested path, or decline it
by retaining the current path. Applications should still apply their own
state and unsaved-change policy in the handler.

The native controller provides immediate local path feedback after queue
admission. It admits only one unresolved request per stack. A rejected queue
admission leaves the path unchanged. A subsequent OCaml frame reconciles the
accepted path; an unchanged response restores the authoritative path without
requiring an artificial renderer frame. Teardown invalidates the controller.

Native callbacks are checked against both current and presented nodes, handler
identity, session visibility/activity and the presented path. The binding also
captures its source path: a callback left behind by a previous transition cannot
pop a replacement destination. SwiftUI route identity includes runtime/node
identity and the exact page-key bytes. Changing only a title or pop policy keeps
the route; replacing its key changes the route identity.

Input from retained content must belong to the top page in both the presented
OCaml tree and the current native path. Covered root/intermediate pages cannot
activate handlers merely because they remain mounted. While a native pop is
awaiting OCaml confirmation, neither the departing page nor the newly revealed
page admits content input. Navigation controls can still report the path intent,
and asynchronous host replies continue independently of page visibility.

## Wire representation

| Element | ID | Mask | Payload |
| --- | --- | --- | --- |
| Navigation stack | 13 | 1 | Root title string; exactly one binding for event 50. |
| Navigation destination | 14 | 7 | Page-key string, title string, strict can-pop boolean; no bindings. |
| Navigation path event | 50 | — | u32 count followed by UTF-8 page-key strings. |

Stack children are `[root; destination; ...]`. Destination nodes have one
ordinary content child and must be directly owned by a stack. Empty stacks,
non-destination path children, orphan destinations, duplicate page keys,
invalid booleans and incorrect bindings reject the candidate transaction.
Both OCaml property encoders and both decoders reject empty destination keys.
Event encoders/decoders enforce the 256-key limit, nonempty keys and uniqueness.

## Verification and current scope

The Navigation example now uses only native stack, destination, Button, Text
and Frame nodes. Its root and detail actions remain in OCaml. Its own SwiftUI
App entrypoint can be built with:

```sh
python3 tool/build_swiftui_example.py navigation
```

The actual Navigation component is also embedded in the native runtime fixture.
Tests push a destination through its OCaml handler, reject a back request before
presentation acknowledgment, accept a native request after presentation and
retain the root/button objects on return. Other real OCaml scenarios exercise
multi-page paths, inactivity and unchanged responses that decline navigation.
Native view tests verify that destination content is shown and the root is
revealed after a request. Protocol/controller tests cover ownership, byte-exact
Unicode identity, stale bindings, queue rejection and protected intermediate
pages.

`native/test/test_navigation_window.py` builds and runs a separate SwiftUI App
using the real OCaml Navigation component. It locates and activates the actual
SwiftUI control hosted inside the system Back toolbar item and observes the
root return. The outer AppKit toolbar accessibility wrapper does not implement
that press action. The test therefore queries the item's public hosted view,
not a private selector or the OCaml callback. This test is part of `make
swift-test` and creates/closes only its own application window.

Host Navigation additionally combines the production clipboard service with
Settings push, explicit Close and system Back at 640- and 360-point widths.
Its runtime regression first exposed acceptance of hidden home-page actions
and speculative-pop input; those now fail admission at the shared session
boundary. A delayed clipboard response updates the retained home model while
Settings remains open, and the value is visible after returning. The test also
covers empty and bounded Unicode reads, oversized rejection and runtime restart.
See [the example](../examples/host_navigation/README.md).

An ordinary NSHostingController test did not produce SwiftUI's scene title or
navigation toolbar, even for a minimal native reference. It remains useful for
content checks; the standalone SwiftUI App supplies the system-toolbar evidence.

Ordinary stack navigation, split navigation and native modal presentation now
have separate APIs. Mail integrates [NavigationSplitView](swiftui-navigation-split.md)
and [native tabs](swiftui-tabs.md); modal content uses [Sheet](swiftui-sheet.md).
The unused legacy Navigator/Page API, Material modal-route types, wire nodes
66/67 and route-pop event 16 are removed. Application actions own returned
values and canonical path or presentation changes; native back requests carry
a complete proposed path rather than an independent route result.

Physical iOS back gestures/cancellation, modal focus/IME, complete application
integration and visual acceptance remain outstanding. No Mail screenshots or
physical iOS execution are established by these macOS tests.

References: [Apple: Understanding the navigation stack](https://developer.apple.com/documentation/swiftui/understanding-the-navigation-stack)
and [Apple: NSHostingController scene bridging](https://developer.apple.com/documentation/swiftui/nshostingcontroller/scenebridgingoptions).
