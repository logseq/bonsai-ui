# Lifecycle

Presentation acknowledgment is the commit point for Bonsai after-display work.
Decoding a frame or publishing a validated candidate is not sufficient.

## Startup and ownership

The public Swift host supports one active native runtime and one application
window. `NativeRuntime` orders C calls on its private serial queue. Creating a
second owner fails without displacing the first. Each `BonsaiSession.start`
receives a new lifetime identity; the owning SwiftUI task uses that same identity
for polling, error handling and cleanup. A retired task cannot close a newer
session when an application view is removed and quickly recreated.

`BonsaiApplicationView` observes scene activity and native visibility. Its
refresh task currently sleeps 16 ms between active/visible refreshes and 250 ms
otherwise. The session gates logical pumping while inactive, hidden, busy or
awaiting presentation. This is periodic foreground polling, not a
`CADisplayLink` or display-vsync guarantee. There is no background timer promise.

## Pump and presentation

An admitted pump validates monotonic time and its input batch, advances the
OCaml time source, applies accepted events, flushes Bonsai, reconciles the next
candidate and prepares handler/host-operation state. It reserves one positive
presentation token. Changed view state receives a new renderer revision and
full or incremental bytes; unchanged view state still requires acknowledgment.

Swift validates and stages the complete candidate before applying it. Native
presentation probes coordinate observed layout/visibility with acknowledgment
of the matching session, token and revision. Only successful acknowledgment
advances presented state and releases after-display work. Host requests then
execute through their presentation/activity gate. A rejected candidate cannot
partially mutate the committed tree and causes snapshot recovery.

An unresolved token blocks the next logical pump. Hiding the application keeps
its pending work; resume resolves presentation before later logical work.
Native callbacks retain their owning identity and cannot apply to a replacement
node, handler or session. Input admission also checks active content, including
native modal presentation and ancestor controls.

## Clock and worker work

The native wrapper checks nondecreasing monotonic nanosecond samples. OCaml maps
them to the retained public Bonsai time source. Due alarms and lifecycle effects
advance during admitted foreground work. Background suspension does not run
logical pumps; overdue work is handled after foreground scheduling resumes.
The [Clock example](../examples/clock/README.md) covers reactive, sampled,
one-shot and recurring behavior.

Worker-backed applications use the same UI runtime slot. The optional Worker
Domain owns Eio resources and communicates through bounded immutable messages.
Domain 0 drains accepted worker responses/pushes into Bonsai effects as part of
its pump. Native presentation, UI state and handlers never move onto the Worker
Domain. See [worker lifecycle](swiftui-worker.md) for structural cancellation,
service teardown and process-wide Domain reuse.

## Shutdown

Public Swift closure is serialized and idempotent. It clears the handle before
later queued operations can reuse it. The raw C pointer is invalid after
destruction and must not be reused directly. Native output buffers are copied
and freed by the wrapper on every output path.

Session closure invalidates its lifetime, cancels host/application requests,
clears deferred work and input, releases native node resources and discards the
view tree. A stale response, timer, view task or presentation callback cannot
complete work in the next lifetime. Worker-backed shutdown unwinds the owned
service session before clearing runtime ownership.

## Verification

Tests use bounded predicates and explicit completion reports. A view's ongoing
refresh task makes an unbounded wait for UI quiescence unsuitable as a completion
condition. Real OCaml/native tests cover no-diff tokens, concurrent calls,
rejection/recovery, hidden/resumed work, stale events and repeated closure.
Notification tests additionally cover immediate view removal/restart with
retained native buttons. Physical iOS, IME/modal interaction and performance
acceptance remain distinct from these targeted runtime tests.

### Cooperative application closure

`BonsaiApplicationEvents.beginShutdown` enters a terminal application-only
transport mode. It has its own finite scheduling lifetime and can drain the
existing worker while hidden, inactive, minimized or awaiting presentation.
An existing token is retired without presentation success; displayed state and
Bonsai presentation lifecycles do not advance. Only application transport is
committed. Built-in host operations are cancelled and UI effects are not run.

The operation always ends in serialized native closure, including timeout and
cancellation. Concurrent close callers join the same teardown task, so a second
close cannot enable a replacement runtime while the first is still releasing
resources. See [the public shutdown contract](application-platform.md#cooperative-terminal-shutdown)
for admission, request selection, duplicate Quit behavior and iOS limitations.
