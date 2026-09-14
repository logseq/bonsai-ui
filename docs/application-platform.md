# Application platform bridge

The application bridge carries opaque bytes between OCaml and application-owned
Swift code. The application owns its codec, native integrations and notification
subscriptions. Standard clipboard, URL, window and other built-in services use
the separate `Host_effect` service path.

## Swift host

Pass a `BonsaiApplicationBridge` to `BonsaiApplicationView`:

```swift
import BonsaiSwiftUI
import Foundation
import SwiftUI

@MainActor func makeBridge() -> BonsaiApplicationBridge {
  BonsaiApplicationBridge(request: { request in
    guard request == Data([1, 1]) else {
      throw BonsaiApplicationError.handlerFailed("Unknown application request")
    }
    guard let identifier = Bundle.main.bundleIdentifier else {
      throw BonsaiApplicationError.unavailable
    }
    return Data([1, 1]) + Data(identifier.utf8)
  })
}

// Inside the application-owned SwiftUI scene:
// BonsaiApplicationView(entrypoint: "my-app", applicationBridge: makeBridge())
```

All callbacks run on MainActor. An async handler may suspend for native I/O;
do not block the actor with synchronous long-running work. Multiple requests
can execute concurrently and complete in any order. Their IDs and correlation
remain private to the framework.

The optional `connected` callback receives a `BonsaiApplicationEvents` sender
after the first frame is acknowledged. Register application-owned native
observers there and release them in `disconnected`, which runs once per closed
connection. The [Host Effects implementation](../examples/host_effects/swift/ApplicationBridge.swift)
observes `NSSystemTimeZoneDidChange` and sends a versioned time-zone event.
Neither the framework nor the example changes system preferences.

`try events.send(bytes)` copies and admits an ordered event synchronously. Its
`SendError` cases are `closed`, `payloadTooLarge` and `backpressure`. A rejected
send leaves existing events and their sequence numbers intact. Applications
choose whether a full queue requires a later retry or dropping an obsolete
notification. A sender retained from a closed session remains closed after the
host restarts.

## OCaml application

Obtain the runtime-scoped bridge with `App.Context.application_platform` or
`Driver.Handler.application_platform`. The operations are in
`Host_effect.Application_platform`:

```ocaml
let platform = Driver.Handler.application_platform handlers in
let effect =
  Bonsai.Effect.bind
    (Host_effect.Application_platform.request platform encoded_request)
    ~f:(function
      | Ok response -> decode_and_apply_response response
      | Error error -> handle_application_error error)
```

Register `Host_effect.Application_platform.on_event` once for the runtime, for
example in a root `Bonsai.Cont.Edge.lifecycle` activation effect. Each subscriber
receives an independently owned byte buffer; subscriptions run in registration
order and are cleared at runtime shutdown. There is no per-subscriber removal
API. The framework does not interpret the application payload.

The [Host Effects OCaml component](../examples/host_effects/ocaml/host_effects.ml)
uses version byte `1`, request/response tag `1` for its bundle identifier and
event tag `2` for time-zone changes. The remaining bytes are bounded printable
ASCII. OCaml validates these messages and owns the displayed state.

## Limits and errors

- Request, response and event payloads each allow at most 1 MiB, including an
  empty payload. Binary zeroes and invalid UTF-8 bytes are valid opaque data.
  Use `BonsaiApplicationBridge.maximumPayloadBytes` or OCaml's
  `Application_platform.maximum_payload_bytes` for the limit.
- Oversized payloads are rejected without truncation. A provider's oversized
  response resolves its request with `Payload_too_large`.
- New provider tasks are admitted only while the combined count of active tasks
  and buffered completions is below 256. Excess requests resolve with
  `Unavailable`; they do not create additional provider tasks. A missing provider also returns
  `Unavailable`.
- The shared native-input queue admits at most 1024 events and a 16 MiB encoded
  batch budget. Completed request responses are retained for later admission
  when this queue is full. Application event senders receive backpressure.
- `BonsaiApplicationError` has `unavailable`, `payloadTooLarge`,
  `handlerFailed(String)`, `cancelled`, `shutdown`, `runtimeReplaced` and
  `invalidResponse(String)` cases, matching the existing OCaml errors.
  Other thrown errors become `Handler_failed`. Error messages are bounded to
  4096 UTF-8 bytes; opaque payload contents are not logged by the framework.

## Presentation, cancellation and shutdown

Requests stage atomically with their frame and dispatch only after presentation
acknowledgment while the host is visible and active. Each runtime has its own
positive monotonically increasing application request IDs; these are independent
of built-in host-service IDs. Repeated IDs, malformed lengths and truncated or
oversized payloads reject the whole frame before any request can execute.

A connected event sender may enqueue events while the host is inactive. Native
pumping resumes when it becomes visible and active. Responses and events name
the displayed revision current at the next pump, including when their producer
completed while another frame awaited presentation.

OCaml's optional application cancellation token resolves its continuation with
`Cancelled`. This protocol has no outgoing per-request cancellation message:
the Swift handler may still finish. Each application reply is pumped separately
because OCaml atomically rejects a batch containing a cancelled, unknown or
duplicate reply. Isolating replies keeps that recoverable rejection from
swallowing adjacent UI input, application events or other valid responses.

Closing the host invalidates its sender, cancels its Swift tasks cooperatively,
releases the application's observer subscription and fences late completions
with a new connection generation. An uncancellable native operation can finish
later, but its result cannot enter a replacement runtime. Shutdown resolves
pending OCaml requests through the existing runtime lifecycle.

## Verification

`ApplicationTransportTests.swift`, `ApplicationBridgeTests.swift` and the real
`native-application-bridge` OCaml fixture cover request framing, independent ID
ownership, every error code, exact byte limits, opaque-buffer ownership,
out-of-order replies, local cancellation, duplicate replies, queue saturation,
provider admission, inactive/resumed sessions and close/restart fencing.
Notification tests use actual NotificationCenter delivery and explicitly remove
only their own observers. They do not mock the OCaml runtime.

The native Host Effects window test presses the application's bundle action,
observes its actual bundle identifier after the Swift/OCaml round trip, posts a
local time-zone notification and observes the actual current time zone in the
OCaml-rendered window. Physical iOS execution remains an acceptance gate even
when the iOS sources typecheck or an App bundle builds successfully.
