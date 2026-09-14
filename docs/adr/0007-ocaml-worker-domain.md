# ADR 0007: Singleton OCaml UI and worker runtime

- Status: Accepted
- Date: 2026-08-01
- Supersedes: The concurrent multiple-runtime allowance in [ADR 0002](0002-runtime-boundary.md)
- Extends: The scheduling and presentation contract in [ADR 0006](0006-foreground-vsync-pump.md)
- Implementation status: Implemented

## Context

The embedded application runs one process-wide OCaml runtime.

Every Dart foreign thread that calls the current C bridge enters OCaml domain 0, so another Dart isolate does not create parallel OCaml execution.

The application needs one additional OCaml execution context for long-lived business computation, bidirectional request and push traffic, and worker-owned resources such as SQLite.

The current native backend stores multiple `handle -> Driver.t` entries and ADR 0002 permits multiple logical runtimes in one process.

Those instances exist because repeated `bf_runtime_create` calls allocate independent logical App and Driver entries in that table.

They are not additional embedded OCaml runtimes, OCaml Domains, or Flutter UI isolates.

That flexibility is not required by the product architecture and complicates worker ownership, lifecycle, hot restart, SQLite cleanup, and backpressure.

This ADR removes concurrent multiple-runtime support and fixes a singleton topology.

## Decision

One application process has one embedded OCaml runtime, at most one active logical `bf_runtime`, exactly one `Driver.t` while that runtime is active, at most one active Dart runtime coordinator lease, and at most one OCaml Worker Domain.

After the Worker Domain is first started, it remains the only spawned OCaml Domain and hosts at most one worker session at a time.

The active worker-backed topology is:

```text
one application process
|
+-- Flutter engine
|   |
|   +-- one Flutter UI isolate
|   |       owns Flutter widgets, rendering, and platform plugins
|   |
|   +-- one active Dart runtime coordinator isolate
|           owns the active bf_runtime lease
|           serializes every FFI call
|
+-- one embedded OCaml runtime
    |
    +-- OCaml UI domain 0
    |   |
    |   +-- one active logical bf_runtime
    |   +-- one Driver.t
    |   +-- Bonsai, reconciliation, and UI state
    |   +-- one worker client and mailbox endpoint
    |   |
    |   +== bounded immutable messages ==+
    |                                      |
    +-- one OCaml Worker Domain            |
        |                                  |
        +-- one worker session <-----------+
        +-- one process-wide Eio backend loop
        +-- one session switch and Coordinator fiber
        +-- bounded request and background fibers
        +-- worker-owned mutable state and native resources
```

The first spawned Domain is normally Domain 1, but behavior must use the architectural name `OCaml Worker Domain` and must not depend on its numeric identifier.

The Flutter UI isolate communicates only with the Dart runtime coordinator isolate.

The Dart runtime coordinator communicates with OCaml only through the existing synchronous C ABI.

The OCaml Worker Domain communicates only with OCaml domain 0 through internal mailboxes.

The OCaml Worker Domain never calls Dart, Flutter, the C callback bridge, Bonsai, or the Driver.

## Cardinality

The following limits are process-wide and normative.

| Resource | Maximum live count | Notes |
| --- | ---: | --- |
| Embedded OCaml runtime | 1 | Started once by `caml_startup_exn`. |
| OCaml UI domain 0 | 1 | Created with the OCaml runtime. |
| Active logical `bf_runtime` | 1 | Owns the only active native handle and runtime epoch. |
| Active `Driver.t` | 1 | Exists only with the active logical runtime. |
| Active Dart runtime coordinator lease | 1 | Normally owned by one coordinator isolate; a stale isolate may transiently survive abnormal owner loss but has no valid native lease. |
| OCaml Worker Domain | 1 | Started lazily and reused sequentially. |
| Active worker session | 1 | Exists only for the active worker-backed App. |
| SQLite connection | 1 per worker session | Created, used, and closed on the Worker Domain. |

A UI-only App still occupies the singleton `bf_runtime` and Driver slot.

A UI-only App may leave the already-started Worker Domain idle and has no worker session.

A worker-backed App has exactly one worker session while it is operational and at most one over its logical runtime lifetime.

## Terminology

The following names are normative in code and documentation.

| Term | Meaning |
| --- | --- |
| Flutter UI isolate | The single Dart isolate attached to the Flutter engine. |
| Dart runtime coordinator isolate | The spawned Dart isolate that owns the one active coordinator lease and serializes calls for the active native runtime. |
| OCaml UI domain 0 | The initial OCaml Domain that owns the singleton Driver and all UI-facing OCaml state. |
| OCaml Worker Domain | The only spawned OCaml Domain, which owns zero or one worker session. |
| Logical `bf_runtime` | The singleton active backend instance identified by one runtime epoch. |
| Worker session | The singleton application-specific business state attached to the Worker Domain. |
| Runtime lease | A Dart/C handle permitted to address the current logical runtime epoch. |

The unqualified term `worker` is avoided when it could refer to either the Dart runtime coordinator or the OCaml Worker Domain.

A tombstoned C wrapper retained by an old Dart isolate is not an active logical `bf_runtime` because it owns no Driver or worker session and all calls through its old handle are rejected.

## Singleton state machines

Domain 0 owns one runtime slot.

```text
Empty -> Creating -> Active -> Destroying -> Empty
Empty -> Finalized
```

The slot never contains two runtime instances.

An explicit final runtime shutdown adds the absorbing `Finalized` state after the active runtime, if any, has completed `Destroying -> Empty`.

All later create calls fail with `Runtime_stopped`.

The Worker Domain has one process-wide lifecycle and one optional session slot.

```text
Not_started -> Idle <-> Attached

Not_started | Idle | Attached | Terminal
                    -> Stopping -> Stopped

Not_started | Idle | Attached
                    -> Terminal
```

`Idle` means the Worker Domain is blocked with no attached worker session.

`Attached` means it owns the one worker session associated with the active logical runtime.

`Terminal` means an unrecoverable Worker Domain failure occurred and no later worker-backed runtime may start until process relaunch.

`Stopped` is used only by explicit final runtime shutdown in a controlled test or embedding host and does not transition back to `Idle`.

A caught worker handler or background-fiber failure makes the application worker client terminal, structurally cancels and removes that session, keeps the backend runtime `Active` long enough to render or report the failure, and leaves the process-wide Worker Domain reusable.

It does not add a `Terminal` variant to the backend runtime-slot state machine.

An uncaught worker-loop or mailbox-invariant failure makes the Worker Domain subsystem `Terminal`.

## Create and replacement policy

Runtime creation inspects and serializes the singleton slot before spawning or attaching worker state.

The startup envelope defines an explicit launch policy.

| Policy | Behavior when the slot is `Empty` | Behavior when the slot is `Active` |
| --- | --- | --- |
| `Fresh` | Create the singleton runtime. | Fail with `Runtime_already_active`. |
| `Replace_existing` | Create the singleton runtime. | Synchronously retire the old runtime, then create the replacement. |

Creation during `Creating` or `Destroying` fails with `Runtime_busy` and is never queued.

`Replace_existing` exists for full Flutter hot restart and abnormal loss of the former Dart owner.

It is an explicit ownership transfer rather than support for two concurrent roots.

Replacement uses this complete transition in one serialized create call:

```text
Active(old)
-> Destroying(old)
-> Empty
-> Creating(new)
-> Active(new)
```

The old session is removed, its resources are closed, the old Driver is shut down, and the old slot reaches `Empty` before the replacement allocates a new Driver or attaches a new worker session.

At no point may the old and new Driver or worker session coexist.

The old handle is tombstoned before the replacement becomes Active.

Any later pump, presentation, or destroy call made through an old handle is rejected or treated as an idempotent stale destroy and cannot affect the replacement.

If the old worker session cannot cooperatively stop and release its resources, replacement fails, the backend remains `Destroying`, and every later create fails.

There is no safe hard kill for an OCaml Domain.

Legacy raw entrypoint configurations use the documented compatibility launch policy during migration, while the versioned startup envelope makes the policy explicit.

The standard top-level `BonsaiFlutterRoot` path uses `Replace_existing` so the existing full hot-restart workflow can reclaim an orphaned old lease without creating overlapping runtimes.

Tests and lower-level embedders use `Fresh` when they need accidental concurrent creation to fail visibly.

Within one live Flutter UI isolate, `RuntimeClient` also owns a singleton coordinator slot.

It acquires `Empty -> Starting` before `Isolate.spawn`, publishes `Active` only after startup succeeds, and releases the slot only after startup failure, isolate exit, or completed disposal.

A second default `BonsaiFlutterRoot` therefore fails before spawning another Dart runtime coordinator isolate.

The native singleton remains authoritative across Flutter hot restart because Dart static state belongs to the old UI isolate and cannot fence a newly created isolate from an orphaned native lease.

This guard proves one active coordinator lease, not that an abnormal stale Dart isolate has already ceased to exist.

Calls from a stale coordinator are rejected by epoch and handle fencing, and the stale coordinator must terminate after observing that fatal condition.

## Ownership and confinement

| Owner | Exclusive state and responsibilities |
| --- | --- |
| Flutter UI isolate | Flutter widget, element, render-object, plugin, and platform-channel state. |
| Dart runtime coordinator isolate | The current runtime lease, native output buffers during copying, ordered pump commands, and presentation coordination. |
| OCaml UI domain 0 | The singleton runtime slot, `Driver.t`, Bonsai driver and effects, handler registry, mounted tree, environment, host effects, and entrypoint registry. |
| OCaml Worker Domain | The process-wide Eio backend, optional session switch, request and background fibers, business mutable state, SQLite connection, prepared statements, transactions, and other worker-only native handles. |

Mutable OCaml values must not be concurrently accessed across Domains.

Values published through a mailbox must be immutable after publication.

`bytes`, mutable arrays, `Queue.t`, `Hashtbl.t`, `ref`, closures that capture mutable UI state, `Driver.t`, Bonsai effects, SQLite handles, and prepared statements must not cross the Domain boundary unless a dedicated contract proves exclusive ownership transfer.

The initial implementation uses immutable application records, variants, strings, integers, and immutable collections for messages.

The current C bridge statics, singleton runtime slot, random state, and entrypoint registry remain confined to domain 0.

Every C binding used by the Worker Domain requires a multicore audit because one Domain lock does not protect process-global C state used by another Domain.

## Worker service contract

An App may provide one typed worker service for its singleton runtime instance.

The service defines immutable configuration, request, response, and push message types plus worker-domain-only mutable state.

The service provides direct-style `init`, `handle`, and `shutdown` operations.
It has no legacy `computation`, `step`, application cancellation callback, or
compatibility constructor.

The Worker Domain enters `Eio_posix.run` once for its process lifetime. Every
attached service owns one session `Switch`; every dispatched request owns a
nested request `Switch`. Stop fails the session switch, while Cancel fails only
the matching request switch. Application background work uses
`Session_context.fork_daemon` and cannot detach from the session lifetime.

`Serial` is the default handler policy. It permits one application handler to
hold the service semaphore while Eio I/O suspends that fiber, without blocking
the Coordinator, Cancel, Stop, or background fibers. An explicitly selected
`Concurrent { max_in_flight }` policy permits bounded fiber interleaving on the
same Worker Domain; it does not create parallel Domains or make mutable state
automatically safe.

Out-of-band Stop and Cancel control has priority over normal requests.

The Coordinator processes a bounded request batch before yielding. Stop and
Cancel remain runnable while a request is suspended in Eio. Synchronous native
calls, including SQLite statements, must remain short because Eio cannot
preempt them.

Initialization, migrations, business computation, native handle use, and resource cleanup all execute on the OCaml Worker Domain.

The domain-0 client exposes non-blocking send behavior and a domain-0-only event subscription that schedules Bonsai effects during a pump.

Subscriber closures remain on domain 0 and are never visible to the Worker Domain.

Application code cannot call `Domain.spawn` directly.

Per-request Domain creation is prohibited.

Request and session contexts expose their switch, complete Eio environment,
monotonic clock, network capability, optional runtime-opened confined data
directory, and typed push emitter. The complete environment lets application
code use Eio ecosystem libraries without framework-specific adapters. The
framework does not own an HTTP client; applications select and configure one
directly.

## Communication contract

The one attached worker session has three logical lanes.

| Direction | Lane | Delivery contract |
| --- | --- | --- |
| Domain 0 to Worker Domain | Request lane | Bounded FIFO with non-blocking `try_send`. |
| Worker Domain to domain 0 | Response lane | Bounded FIFO with capacity reserved for every accepted outstanding request. |
| Worker Domain to domain 0 | Push lane | Bounded by topic and latest-wins coalesced for snapshot-style notifications. |

Stop, Cancel, and session removal are out-of-band controls and cannot be blocked behind a full request lane.

Every request and response contains `runtime_epoch`, `worker_generation`, and `request_id`.

Every push contains `runtime_epoch`, `worker_generation`, and a monotonic `push_sequence`.

The epoch and generation fence stale messages across sequential replacement and hot restart and are not routing keys for concurrent sessions.

Application protocols add a business data revision when stale query results must not overwrite newer committed data.

Renderer revision and presentation ID are not reused as worker consistency identifiers.

Domain 0 never blocks while enqueuing a normal request or draining worker output.

A full request lane returns a typed backpressure result such as `Busy` instead of waiting or dropping the request.

An accepted request produces exactly one response, typed cancellation, or typed failure.

Responses are never silently dropped.

Snapshot-style pushes may replace an older undelivered push for the same topic, but the replacement retains the newest sequence and business revision.

The Worker Domain waits in the Eio backend when it has no runnable work and
never busy-spins. Cross-Domain mailbox publication broadcasts an Eio condition
as a wake hint; the bounded mailbox and out-of-band control state remain the
source of truth and are always rechecked after wake-up.

All mailbox lock sections are limited to queue or slot mutation and never contain Bonsai work, SQLite work, message decoding, or business computation.

## Pump ordering and UI visibility

Worker output becomes visible to Bonsai only during an accepted domain-0 pump.

One pump uses this deterministic order.

```text
1. Validate and dispatch the Flutter input batch.
2. Snapshot a bounded batch of worker responses and pushes.
3. Reject stale epoch, generation, request, sequence, and business revisions.
4. Convert accepted worker events into domain-0 Bonsai effects.
5. Drain the complete domain-0 effect queue.
6. Flush Bonsai once.
7. Reconcile once and produce at most one candidate frame.
```

Processing Flutter input first allows a UI action to advance a query generation before an older worker result from the same pump is considered.

A worker message arriving after the pump snapshots the outbox waits for the next pump.

No worker output is applied while a presentation token is unresolved because no new OCaml pump is accepted in that state.

The Worker Domain may continue computing and coalescing output behind the presentation barrier, but it cannot mutate candidate UI state or trigger Bonsai lifecycle work.

Worker pushes do not schedule Flutter frames directly.

The existing foreground vsync loop naturally observes pushes on later pumps while the application is eligible.

## Lifecycle

Worker-backed runtime creation follows this sequence.

```text
decode startup envelope and launch policy
-> when Active and Replace_existing, complete Active(old) -> Destroying -> Empty
-> acquire Empty -> Creating for the new runtime
-> ensure the one Worker Domain is started or idle
-> create one worker session with a fresh epoch and generation
-> initialize worker-owned resources on the Worker Domain
-> receive Ready or a typed startup failure
-> create the one domain-0 Driver
-> publish the active runtime lease
```

Startup may wait on the Dart runtime coordinator isolate because Flutter remains on its UI isolate and can render a loading state.

Any startup failure stops and cleans a partially initialized worker session, shuts down a partially created Driver, releases the singleton slot, and leaves the Worker Domain idle unless it failed terminally.

Normal pumping remains non-blocking with respect to the Worker Domain.

Logical runtime destruction follows this sequence.

```text
transition Active -> Destroying
-> tombstone the runtime lease
-> reject new requests and native operations
-> complete pending domain-0 requests as Shutdown
-> send out-of-band Stop
-> fail the session switch and structurally cancel request and background fibers
-> wait for their switch-owned resources to unwind
-> finalize statements and close worker-owned resources
-> remove the worker session and return the Worker Domain to Idle
-> shut down the Driver
-> clear the singleton runtime slot
```

Destroy is idempotent for the same stale handle.

The singleton slot is not cleared before worker resource cleanup and Driver shutdown complete.

If a worker is stuck in an uninterruptible native operation, the backend remains `Destroying` and no replacement may reuse state that the worker could still access.

Normal runtime destroy does not join the process-wide Worker Domain.

Explicit final runtime shutdown is an internal operation for controlled tests or an embedding host that owns process teardown.

It fails with `Runtime_busy` if creation or destruction is already in progress.

Otherwise it destroys the active runtime if present, moves the backend from `Empty` to `Finalized`, and stops the worker subsystem.

If the Worker Domain was successfully spawned, final shutdown wakes and joins that Domain handle exactly once.

If it was never spawned or spawn failed before producing a handle, final shutdown performs zero joins and transitions the worker subsystem directly to `Stopped`.

Repeated final shutdown is idempotent and never joins again.

The production Flutter application does not depend on an iOS or macOS process-termination callback to invoke this operation; ordinary OS process exit terminates the process-wide Domain with the process.

Production persistence correctness never depends on receiving an iOS process-termination callback.

Hot restart is a sequential ownership transfer that completely retires the old Driver and worker session before creating the new epoch and generation.

In-memory business state does not survive replacement.

Durable state such as SQLite is closed by the old session and reopened by the new session.

## Failure policy

A worker service catches handler and daemon exceptions at the worker-session
boundary, fails the session switch, closes its resources, returns the Worker
Domain to `Idle`, and emits one terminal application event for the singleton
active runtime. A typed handler `Error` fails only that request.

There is no other worker session to isolate or continue.

An uncaught Worker Domain loop failure makes the worker subsystem Terminal and worker-backed create fails until process relaunch.

After the active runtime has been destroyed, a UI-only runtime may still be created while the worker subsystem is `Terminal` because it neither attaches a session nor uses the failed Domain.

`Finalized` is stronger: it rejects UI-only and worker-backed create alike.

`Domain.recommended_domain_count ()` is diagnostic guidance and is not used as a capability gate.

An actual Domain spawn failure, initialization failure, or mailbox invariant failure produces an explicit startup or terminal error.

The implementation never falls back to running worker code on domain 0.

OCaml Domains share the major heap and garbage collector.

The Worker Domain provides CPU parallelism but not memory isolation, crash isolation, or protection from stop-the-world GC phases.

A native crash in a worker binding still terminates the Flutter process.

Mailbox item counts, message byte sizes, drain time, request execution time, and worker allocation rates must remain bounded and measured.

## Apple platform policy

The same singleton topology is used on macOS and physical iPhoneOS arm64 builds.

The Worker Domain is an OS thread inside the existing application process and uses the same App Sandbox as domain 0.

iOS suspension pauses the process and therefore pauses both OCaml Domains.

This architecture provides no background execution entitlement, deadline, or guarantee.

Business transactions must remain short, and UI recovery after resume must tolerate coalesced pushes and request refresh.

SQLite and other filesystem resources receive an absolute sandbox path resolved by Flutter or Foundation at each launch.

Worker code must not derive or persist a container root path.

Physical-device Domain spawn, communication, cancellation, replacement, suspension, resource cleanup, and GC latency are implementation acceptance gates rather than assumed platform support.

## C ABI and renderer protocol

Internal worker communication adds no native-to-Dart callback and no worker operation to the renderer wire protocol.

The exported C ABI remains the serialized lifecycle, pump, presentation, error, buffer, and destroy surface.

Only the current Dart runtime coordinator owns the active runtime lease.

The OCaml native backend replaces its process-wide `handle -> Driver.t` table with one explicit singleton state slot.

A versioned startup envelope carries the entrypoint, launch policy, and opaque application payload through the existing `bf_runtime_create` byte buffer without adding an exported C symbol.

Old handles become tombstones and never route to the replacement Driver or worker session.

Replacement reclaims the old OCaml Driver, session, and worker-owned resources, but it cannot safely free a C `bf_runtime *` wrapper that an abnormal Dart owner may still address.

That wrapper and any buffer whose FFI call returned before the owner disappeared remain owned by the stale Dart side until it calls `bf_runtime_destroy` or the process exits.

The supported coordinator permits at most one such returned buffer at a time and frees it immediately after copying, so abnormal hot-restart residue is bounded per orphan.

Tests use the existing outstanding-buffer observation while the stale wrapper is still addressable, and the lifecycle documentation records the wrapper plus maximum-buffer bound instead of claiming that orphan replacement freed all native memory.

## Consequences

The process has one UI runtime authority, one Driver, and one worker execution context.

CPU-heavy OCaml work can run in parallel with domain-0 UI work without creating another OCaml runtime.

UI state remains deterministic because worker results are committed only at the existing pump boundary.

Request backpressure, stale-result fencing, push coalescing, cancellation, shutdown, and replacement become explicit contracts.

Concurrent multiple `BonsaiFlutterRoot` instances, multiple active entrypoints, and multiple Flutter engines sharing this backend are unsupported.

An abnormal stale Dart coordinator may exist transiently, but it is not an active coordinator and cannot address the new runtime.

This is an intentional breaking constraint relative to ADR 0002.

A long synchronous native call can still delay Stop and worker responses, so
SQLite statements, transactions, and other non-suspending work must remain
bounded. Eio-native waits suspend only their request fiber.

Shared heap collection and unsafe C bindings can still affect UI latency or process stability.

The architecture adds no mechanism for worker-originated Flutter wakeups while foreground pumping is stopped.

## Rejected alternatives

| Alternative | Reason rejected |
| --- | --- |
| Concurrent multiple `bf_runtime` and Driver instances | The product requires one UI runtime authority and one worker, and concurrency complicates ownership and lifecycle without a current use case. |
| A second Dart isolate that calls the existing OCaml FFI | It still enters OCaml domain 0 and cannot provide parallel OCaml execution. |
| One OCaml Domain per request | Domain creation is too expensive and makes cancellation and resource ownership unsafe. |
| Stopping and respawning the Worker Domain for every hot restart | A process-wide idle Domain preserves the fixed topology and avoids repeated OS-thread construction. |
| A second embedded OCaml runtime in the same process | The current startup, symbols, callbacks, heaps, and complete-object packaging do not support it safely. |
| A worker subprocess | It is incompatible with the current iOS process boundary and adds unnecessary IPC and packaging complexity. |
| Worker callbacks directly into Dart or Flutter | Flutter UI isolate affinity would be violated and the pull-based transactional boundary would be bypassed. |
| Sharing a SQLite connection across Domains | SQLite mutexes cannot make OCaml binding wrappers and application lifetimes safe across Domains. |
