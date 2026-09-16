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

Ordinary requests stage atomically with their frame and dispatch only after presentation
acknowledgment while the host is visible and active. Each runtime has its own
positive monotonically increasing application request IDs; these are independent
of built-in host-service IDs. Repeated IDs, malformed lengths and truncated or
oversized payloads reject the whole frame before any request can execute.

A connected event sender may enqueue events while the host is inactive. Ordinary native
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

## Cooperative terminal shutdown

A connected sender exposes `beginShutdown`. It is an explicit, opt-in exception
for application transport and the existing worker service. It does not activate,
unhide or present a window. Ordinary input, environment updates, native UI,
built-in host requests and the ordinary bridge provider remain gated.

```swift
// Retain the sender from BonsaiApplicationBridge.connected.
let shutdown = try events.beginShutdown(
  event: encodePrepareToTerminate(),
  timeout: .seconds(4),
  accepting: { request in isShutdownRequest(request) },
  request: { bytes in
    // Only application-owned, non-UI cleanup belongs in this handler.
    if isTerminationReady(bytes) {
      return .finish(encodeTerminationReadyReply())
    }
    return .reply(try await performShutdownRequest(bytes))
  })
let outcome = await shutdown.result
// Release the application's native termination deferral here.
```

The framework does not interpret payloads. The synchronous `accepting` predicate
selects permitted requests; other application requests resolve with `Shutdown`
without entering either provider. Ordinary provider tasks already running at entry
may finish; their replies remain fenced by the original connection. The shutdown provider is serial, with one
active task and one retained reply, each payload limited to 1 MiB. An oversized
provider reply resolves with `Payload_too_large` and cannot finish shutdown.
New OCaml application requests during shutdown are bounded by 256 outstanding
requests and 16 MiB of pending payloads; excess requests resolve with
`Unavailable`. Requests already pending at entry keep their identities.

`Response.reply` continues the exchange. `Response.finish` completes only after
that response has been accepted and flushed by OCaml, and native teardown has
finished. A rejected final reply reports failure. The shutdown path drains the
existing worker's bounded completion hook and stabilizes Bonsai, but does not
reconcile, publish or acknowledge a frame, advance displayed revisions, or run
presentation-triggered activation/after-display work. It retires any pending
presentation token explicitly; application requests from an unpresented frame
remain available exactly once. Cleanup must use already-registered subscriptions
and effect continuations, without depending on newly presented UI.

The first call freezes ordinary event admission and starts an independent
MainActor scheduling task. Previously admitted application events retain FIFO
order. The initial shutdown event has one separately bounded 1-MiB reservation;
it enters the shared 1024-event/16-MiB native queue once space is available, after
previous events. This lets a full ordinary queue drain without losing its events
or exceeding a native batch's limits. UI input and built-in host responses are
excluded from shutdown batches. `shutdown.send(bytes)` admits additional ordered
application events with the same payload and queue limits. It returns
`backpressure` until the reserved initial event has been admitted, and whenever
the queue is full. Replies retain their data and retry admission; individual
reply batches isolate recoverable cancellation or duplicate-reply failures.

Repeated `beginShutdown` calls on the same running connection return the same
operation. The first event, predicate, handler and deadline win. Later calls do
not enqueue another quit event or extend the deadline. Invalid initial payloads
or timeouts leave the original connection unchanged. Timeouts must be positive
and at most 60 seconds, measured with a monotonic clock.

This operation is **terminal**. Success, timeout, `shutdown.cancel()`, cancellation
of a task awaiting `result`, view removal and runtime failure all retire the
runtime. Outcomes distinguish `completed`, `timedOut`, `cancelled`, `closed` and
`failed`. It cannot cancel Quit and resume partially released application state.
The sender, operation and pending callbacks are fenced by their original lifetime;
late provider results cannot enter a replacement runtime. Disconnect runs once,
and restart waits for serialized native teardown.

A deadline stops admission and cancels providers cooperatively. It cannot preempt
synchronous OCaml code, a blocked MainActor, or an uncooperative worker's teardown;
`result` waits for actual resource release. On iOS, this API neither obtains
background execution time nor promises a Quit callback. A suspended or killed
process cannot execute the exchange. Use only execution time granted by iOS and
record device execution separately from compilation.

The [Host Effects delegate](../examples/host_effects/swift/App.swift) demonstrates
`terminateLater` and releases native deferral after the exchange, without making
the window visible. Its application codec uses event `[1, 12]` and ready
request/reply `[1, 13]`. This example has no domain-specific graph cleanup.
