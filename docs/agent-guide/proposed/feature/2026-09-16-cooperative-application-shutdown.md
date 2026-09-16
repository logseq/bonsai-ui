# Cooperative Application Shutdown

## Problem

An application-owned termination exchange cannot progress after the native
window is hidden. `BonsaiApplicationEvents.send` admits the event, but
`BonsaiSession.refresh` requires visibility and activity. Application request
dispatch and reply admission have the same gates. The public view owns the
session privately and exposes no cooperative close operation.

There is a second, independent prerequisite: both `NativeRuntime.pump` and
`Driver.pump` reject work while a presentation token is pending. Merely relaxing
the Swift activity check does not solve hidden termination. A synthetic
presentation acknowledgment would incorrectly commit host commands, handler
revisions and Bonsai after-display lifecycle work.

The supplied Journal report identifies installed archive SHA-256
`dbce93fc108e052328dc0b94576930a3c1caceb1d60b84b05e19382f9f1161fc`.
The existing host-configuration release report records the same archive and
framework SDK `0.1.0~dev.42`. The reported timings are consumer evidence, not a
runtime test performed in this task.

## Proposal

Add an opt-in, terminal cooperative shutdown operation to the public application
connection. The application selects the initial opaque event, the permitted
shutdown request payloads and the terminal reply. Framework code must not know
Journal's codec, graph reducers or authentication behavior.

### Public operation

Expose `beginShutdown` on the generation-bound `BonsaiApplicationEvents` received
by the existing public `connected` callback. It returns a public operation
handle, with an async result, cancellation and bounded additional event
admission. No private `BonsaiSession` access or generated-host changes are needed.

The operation takes a bounded initial event, a finite timeout, a synchronous
application-owned request predicate and an async shutdown request handler. The
handler returns either a normal response or a final response that ends the
exchange after that response has been accepted by OCaml. The native termination
deferral is released by the caller after the operation result; it must not be
released merely because a provider handler was entered.

Only requests selected by the predicate execute through the shutdown handler.
The existing ordinary request handler does not gain permission to execute while
hidden. UI-capable application integrations must not be selected by the shutdown
predicate. Unselected requests resolve with `Shutdown` without invoking either provider. The framework cannot infer
the safety or meaning of arbitrary opaque application payloads.

### Runtime and presentation

Add explicit shutdown entry and pump operations through `NativeRuntime`, the C
bridge, `Native_backend` and `Driver`. The transition is serialized with any
in-flight pump or acknowledgment, and fences pending presentation callbacks.
It does not acknowledge an unpresented frame or advance displayed revisions.

The shutdown pump admits only application events and application responses,
drains the existing bounded worker hook, schedules effects and stabilizes the
existing Bonsai runtime. It extracts and commits application transport requests
without reconciling or publishing a new native view tree. Existing unpresented
application requests must remain eligible exactly once; their paired host
operations must not be committed. No new presentation token is reserved.

Built-in host responses, UI input and environment updates are excluded from the
shutdown input batch. Do not execute host commands, native dialogs, navigation,
announcements, native view updates or presentation-triggered Bonsai lifecycles.
The shutdown exchange must use already-registered application subscriptions and
effect continuations, not require activation or after-display work for a new UI.
Reuse the actual worker service and its lifetime; do not create a second worker.

### Admission, ordering and termination

- Validate payload sizes and timeout before altering the running session.
  An invalid operation leaves existing input and sequence numbers unchanged.
- Preserve FIFO order among previously admitted application events and the
  initial shutdown event. Freeze ordinary event admission when shutdown starts.
  Reserve one separate initial payload (at most 1 MiB) so a saturated ordinary
  queue cannot prevent starting shutdown. Admit it into the existing
  1024-event/16-MiB queue when space becomes available; native batch limits
  remain unchanged.
- Additional shutdown events use the same bounded queue and return backpressure
  without consuming sequence numbers. Keep the 1-MiB opaque payload limit.
- Use a serial shutdown provider with one retained reply. Bound new OCaml
  pending requests and queued operations to 256 and 16 MiB each.
  Retain a completion until admission succeeds; isolate individual application
  replies so a cancelled or stale reply cannot discard adjacent events.
- Repeated `beginShutdown` calls in one connection return the same operation.
  The first event, policy and deadline win; duplicates neither enqueue another
  quit event nor extend the deadline. Result observation has no side effects.
- Use a monotonic deadline. Expiration, explicit cancellation and view removal
  stop new work and retire the connection. The operation is terminal:
  it closes the runtime on success, timeout, cancellation or runtime failure.
  Continuing the same application after cancelling Quit is outside this proposal.
- Return a distinguishable successful, timed-out, cancelled, closed or failed
  result. Deliver the final provider response into OCaml before reporting success.
  Caller cancellation must never be misreported as successful cleanup.
- Disconnect observers and release native resources once. Fence all deferred
  operations, provider completions, presentation callbacks and timers by both
  session lifetime and connection generation. An old sender or shutdown handle
  remains closed after restart. Block restart until native teardown completes.
- Deadline expiration can stop admission and fence callbacks, but cannot preempt
  a synchronous OCaml computation or an uncooperative native/worker teardown.
  Document this distinction without promising a hard process-exit deadline.

### Implementation and release scope

Use the existing native fixture and test targets; do not modify Dune files or
OCaml files under `ocaml/spec/`. Expected implementation owners are:

- `swift/BonsaiSwiftUI/Sources/BonsaiApplicationBridge.swift`,
  `BonsaiSession.swift`, `BonsaiApplicationView.swift` and `NativeRuntime.swift`.
- `ocaml/runtime/driver.ml`, `driver.mli`, and application transport internals
  in `ocaml/runtime/host_effect.ml` and `host_effect.mli` as needed.
- `ocaml/ffi/native_backend.ml`, `native_backend.mli`, and the existing
  `native/src/bonsai_swiftui_native*` and `bonsai_swiftui_ocaml_bridge*` files.
- Existing native OCaml fixtures, Swift session/bridge tests and native window
  tests; `docs/application-platform.md`, `docs/lifecycle.md`, `docs/ffi.md` and
  the Host Effects example.

Update ABI identity/checks consistently for the new native transport. No legacy
ABI fallback, Flutter path or compatibility migration is part of this change.
Preserve the staged baseline and keep the implementation commit scoped. After
pushing implementation, generate the iOS SDK from that exact pushed commit and
commit/push that SDK update separately as required by repository instructions.
Install matching framework/CLI packages and SDK, and record immutable archive
hashes, source commit, SDK source identity, versions and installation evidence.

## Alternatives considered

### Globally allow hidden pumping

Rejected: it neither resolves a pending presentation token nor preserves the
existing contract for UI input and host effects.

### Acknowledge or reject frames repeatedly during shutdown

Rejected: acknowledgment would falsely release presentation work; ordinary
rejection is renderer recovery and does not provide application-only transport
commit semantics. Shutdown must have an explicit runtime transition.

### Resume the same runtime after cancelled shutdown

Possible, but substantially different: it needs an explicit restoration protocol
for pending frames, dropped input, handlers, native provider tasks and partial
application cleanup. The recommended terminal operation avoids pretending that
an opaque partially completed graph-close exchange is reversible. The user selected terminal shutdown on 2026-09-16.

## Acceptance criteria

- Write behavioral tests before implementation and observe their expected
  failure. Cover real OCaml and the native session/bridge boundary rather than
  mocks of the runtime or copies of Journal domain reducers.
- Verify visible control, actual hidden application, inactive application and
  minimized window independently, recording native visibility/activity evidence.
  Toggling session flags alone is not macOS window evidence.
- An application event completes a real worker request and then an opaque native
  request/reply while hidden, including when presentation was already pending.
  Assert that no presentation acknowledgment is fabricated and no unrelated host
  command or native UI mutation is executed.
- Verify a worker completion queued before shutdown, newly completed worker work,
  full event queues, byte limits, reply backpressure, duplicate requests,
  concurrent close, deadline cancellation and uncancellable late callbacks.
- Assert exactly-once disconnect/resource release and no cross-generation
  delivery after restarting the same session owner.
- Preserve ordinary presentation-gated bridge tests and existing native lifetime
  tests. Verify the full source build/test requirements and package checks.
- Record macOS runtime results separately from iOS compilation and any available
  device execution. State explicitly that iOS suspension stops process execution;
  this API does not obtain background execution time or guarantee termination
  callbacks while suspended. Missing physical-device evidence stays unverified.
- Deliver public API documentation, an application-owned example and installed
  framework/CLI release evidence with the matching SDK identity. Do not claim
  Journal's complete graph-close path was tested by a transport fixture.

## Risks

- Terminal cancellation removes the option to cancel Quit and continue in the
  same runtime; this must be an intentional consumer contract.
- Bonsai effect stabilization can cause application-owned computation. Gating
  native host effects cannot make arbitrary application code safe or preemptible.
- Existing provider tasks can outlive cancellation. Their side effects cannot be
  undone by a generation fence, although their replies can be prevented from
  reaching a replacement runtime.
- The repository has extensive staged changes predating this task, including
  release metadata. Do not claim those changes were authored by this work or
  silently sweep them into its implementation commit.
- A finite admission deadline is distinct from bounded teardown of an
  uncooperative worker. Tests must report those phases separately.

## Questions

None. On 2026-09-16 the user confirmed terminal shutdown, including timeout and
explicit cancellation.

## Consequences

The shutdown connection cannot return to interactive use. Applications wait for
its result before releasing native termination deferral. Existing presentation
semantics remain unchanged outside the explicit shutdown operation.
