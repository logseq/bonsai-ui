# Application SwiftUI views

`Native_widget` carries an application-owned schema across the OCaml/SwiftUI
boundary. OCaml owns canonical state and typed events. Swift owns native content,
local SwiftUI state and any per-node resources. The core transports an opaque
property payload using node 128 and event 21.

## OCaml definition

Declare one positive numeric kind and an exact schema version. Kind IDs, versions
and event IDs must be within 1 through 65535. Properties and events may use any
encoding agreed by the two application components.

```ocaml
module Ui = Bonsai_swiftui_ui
module ID = Bonsai_flutter_spec.Id

type card_event = Activate

let card =
  Ui.Native_widget.Extension.create
    ~kind_id:(ID.Native_widget.Kind_id.of_int 1001)
    ~version:1
    ~capabilities:[ Ui.Native_widget.Capability.Stateful; Resource; Semantics ]
    ~encode_props:Bytes.of_string
    ~decode_event:(fun ~event_id payload ->
      if ID.Native_widget.Event_id.to_int event_id = 1 && Bytes.length payload = 0
      then Ok Activate
      else Error "Unknown card event")
    ()
```

Create a Bonsai handler with `Driver.Handler.create_native handlers
~name:"card" card ~equal:( == ) set_count ~f:...`, and pass it to
`Native_widget.widget_with_handler card ~props ~on_event`. Optional `~children`
are ordinary `View.t` values; supply stable keys when their identity must survive
updates. The Gallery implementation is in
[`native_view_catalog.ml`](../examples/gallery/ocaml/native_view_catalog.ml).
Its exported `card` is also used by the main Gallery component.

## Swift registration

Build a `BonsaiNativeViews` value before creating `BonsaiApplicationView`. The host
copies it into its session; later changes to the caller's registry cannot change
an existing session. Duplicate kinds and invalid metadata throw during
registration. A kind has one exact version and no version fallback.

```swift
import BonsaiSwiftUI
import SwiftUI

@MainActor @Observable final class CardResource {
  var localCount = 0
}

enum CardEvent { case activate }

@MainActor func nativeViews() throws -> BonsaiNativeViews {
  var registry = BonsaiNativeViews()
  try registry.register(
    kind: 1001, version: 1,
    capabilities: [.stateful, .resource, .semantics],
    decode: { data -> String in
      guard let text = String(data: data, encoding: .utf8) else {
        throw CocoaError(.fileReadInapplicableStringEncoding)
      }
      return text
    },
    encodeEvent: { (_: CardEvent) in BonsaiNativeEvent(id: 1) },
    makeResource: { CardResource() },
    dispose: { _ in /* Cancel application-owned work here. */ },
    content: { context in
      VStack {
        Text(context.properties)
        Button("Activate") { _ = context.emit(.activate) }
        Button("Local: \(context.resource.localCount)") {
          context.resource.localCount += 1
        }
        ForEach(context.children) { $0 }
      }
    })
  return registry
}
```

Pass the returned registry as `BonsaiApplicationView(entrypoint: "gallery",
nativeViews: registry)`. A registration without external resources can use
`makeResource: { () }` and `dispose: { _ in }`. A separate content `View` can own
`@State`; its identity survives compatible property and child changes.

Capabilities are explicit bit flags: `stateful`, `resource`, `semantics`,
`semanticsCanvas` and `virtualized`. A node's requirements must be a subset of
its registration's declarations. Declaring a capability does not implement it:
the application factory remains responsible for its native semantics or resource
behavior. Core collections should normally use `View.Collection` instead of an
application extension.

## Publication and resource ownership

Property decoding happens before candidate-frame publication. Decoders must be
pure: they must not allocate owned resources, send events or mutate application
state. Unknown kinds, wrong versions, unsupported capability bits and decoding
failures reject the whole candidate frame. No placeholder view is published and
no resource is allocated for that frame. The previously published tree survives.

Resource creation runs synchronously at commit and does not throw. Model fallible
or asynchronous domain work inside the resource and its view state. A compatible
update retains the resource; removal, replacement by another kind, epoch
replacement and session closure dispose it exactly once. Disposal must cancel
owned tasks, remove observers and release external handles. Hiding a view retains
its resource. Never rely on `onDisappear` for permanent resource destruction.

## Events and children

`context.emit(event)` returns queue admission, not an OCaml acknowledgment. Events
carry the registration's kind/version and are delivered through the normal OCaml
event queue. They are not coalesced. Zero event IDs, oversized payloads and a full
queue return `false`; application code decides whether to retry. Opaque payloads
use the transport frame budget rather than the text-string budget.

An event requires a mounted, active and presented native instance. Retained
callbacks expire across property/binding/child metadata changes, hiding,
unmounting and disposal. Obtain the current callback from the next content
snapshot; do not retain old contexts as an event channel.

`context.children` supplies keyed `BonsaiNativeChild` views. Only children actually
mounted by the native factory may dispatch input. Omitting a child from a
conditional branch fences its input even while it remains in the OCaml tree.
The factory owns its layout; each logical child should appear once.

## Core replacements and remaining work

Use core `View.Collection`/`View.Scroll`, `View.Morphing_surface`, navigation
stack/split/tabs and `View.Swipe_actions` for those capabilities. Their contracts
are documented in [collections](swiftui-collections.md),
[morphing surfaces](swiftui-morphing-surface.md),
[navigation](swiftui-navigation-stack.md) and [swipe actions](swiftui-swipe-actions.md).
Standard composer registrations are described below. The generic registration
API does not establish full standalone Gallery completion.

## Standard message composer

Each render tree installs kind 6/version 1 for
`Native_widget.Message_composer` and kind 7/version 2 for
`Native_widget.Expandable_message_composer`; applications cannot replace either
reserved registration.
The ordinary composer uses one SwiftUI surface and the existing native text
adapter. Its draft is explicitly ephemeral: OCaml observes text-change and
raw-text action events but does not send those observations back as corrections.
Sending leaves the draft intact. Change the logical key to reset it.

A stable composer retains text, selection and marked text across changes to
hint, enabled state, line limit and button metadata. Its editor grows to the
configured line limit and scrolls beyond it. Collapse reduces the editor to one
line and releases focus; focusing it again restores expansion. A dedicated
collapse handle owns downward dragging, leaving editor selection and scrolling
gestures separate. The collapse button provides the corresponding native action.
Reduced motion disables the explicit size animation.

Leading/trailing buttons use logical layout direction. Visibility tests trimmed
text; events contain the exact untrimmed current text. Arbitrary OCaml button
children are decorative labels, so their nested handlers do not run. Overall and
per-action disablement are independent. The standard composer uses the shared
one-MiB UTF-8 draft limit; reaching it leaves the draft unchanged and displays
`Draft limit reached`. Queue rejection also leaves the previous edit/selection
intact. Removal, epoch replacement and closure dispose the editor delegate and
callbacks.

Application registrations can use `validateChildren: { properties, count in ... }`
to enforce their own typed child-count contract. Validation runs before resource
creation and also runs for frames that change children while reusing decoded
properties. The composer requires exactly one child for each action record.

The expandable composer reuses the editor inside a SwiftUI Sheet. Closing and
reopening retain the draft and selection; configuration changes retain the
mounted Sheet. Disablement keeps Close available. Native modal ownership blocks
background input until dismissal completes. Compact/Extended launcher changes
use the configured duration and curve, with reduced-motion and zero-duration
handling. Sheet transitions and keyboard avoidance are platform-owned.

Use `context.canInteract()` immediately before a local native action that does
not emit an OCaml event, such as opening a presentation. It rechecks current
ownership synchronously, including modal isolation. Retained context callbacks
expire with their snapshot generation; `isPresented` is a rendering snapshot.
