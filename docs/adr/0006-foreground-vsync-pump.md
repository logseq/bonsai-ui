# ADR 0006: Foreground vsync pump

- Status: Accepted
- Date: 2026-07-29
- Supersedes: The command-driven scheduling portion of
  [ADR 0002](0002-runtime-boundary.md)

## Context

The runtime currently advances only when Flutter starts it, submits input, or
acknowledges a renderer revision. Bonsai timers, observed time, lifecycle
transitions, before-display work, and after-display actions can therefore
remain pending indefinitely when no external input arrives.

The pinned public Bonsai APIs can advance and flush the complete runtime, but
they do not expose one exact next deadline or a complete pending-work query.
Changing, overlaying, or using private APIs from upstream Bonsai, Bonsai
Concrete, Incremental, Incr_dom, or Flutter is outside the runtime boundary.

## Decision

Flutter owns a recursive foreground loop built with
`SchedulerBinding.scheduleFrameCallback`. Each eligible Flutter frame grants
at most one logical pump to the dedicated Dart runtime isolate. The worker
serializes every native call, advances a worker-owned monotonic clock, and
coalesces grants while a presentation is unresolved. The OCaml Driver maps
that elapsed time onto its retained `Bonsai.Time_source`, calls the public
clock-advance API, and flushes the Bonsai Driver once for each consumed grant.

The loop continues while Flutter is `resumed` or `inactive` and
`framesEnabled` is true. It stops for `hidden`, `paused`, `detached`, or
independent loss of `framesEnabled`. Resume catches up overdue work on later
foreground frames. There is no fixed-period timer, forced frame, native
callback thread, busy loop, or background fallback.

Every successful logical pump issues a positive, non-reusable
`presentation_id`, including pumps which produce no renderer diff.
`presentation_id` identifies the lifecycle transaction; renderer revision
continues to identify wire-frame state and advances only when a binary frame
is emitted. At most one presentation may be unresolved.

The renderer protocol remains version 1.12. The native runtime boundary
becomes ABI 2.0 and requires an exact independent ABI version match. The
runtime-driving ABI consists of `bf_runtime_pump`,
`bf_runtime_presentation_succeeded`, and
`bf_runtime_presentation_rejected`; the old `bf_runtime_step` and
`bf_runtime_frame_presented` operations have no compatibility fallback.

This version statement records the constraint of the foreground-pump change:
that change retained protocol 1.12 while advancing only the native ABI. Later
compatible schema additions advanced the current renderer protocol to 1.14
without changing this ADR's scheduling or presentation contracts.

## Transaction contracts

### Pump

`pump(monotonic_now_ns, optional_input_batch)` validates the clock and the
complete input batch before input-derived mutation. It advances the public
time source, executes either the complete valid batch or no input, flushes
Bonsai once, reconciles against the last successfully presented tree, and
prepares host operations without consuming them.

It then reserves exactly one `presentation_id`, optionally reserves a new
renderer revision and wire frame, and retains the complete candidate behind
the presentation barrier. A recoverable invalid input batch is dropped
atomically but still produces a presentation token and diagnostic so it
cannot starve timer or lifecycle progress.

### Presentation success

`presentationSucceeded(generation, presentation_id, revision)` is accepted
only for the exact unresolved token and the current live eligible generation.
A retained token issued before suspension may be acknowledged by the new
eligible generation after resume.

Flutter sends success from the matching guarded post-frame callback after the
candidate has been applied and a later real Flutter frame has completed its
persistent callbacks. The worker samples its monotonic clock again. OCaml
validates the clock before mutation, commits the prepared host-operation
prefix and candidate renderer metadata, advances the public time source
without flushing, clears the barrier, and triggers lifecycle work exactly
once. A later granted pump flushes lifecycle-injected actions and any due
timers.

### Presentation rejection

`presentationRejected(generation, presentation_id, revision, reason)` accepts
one of:

- `decodeFailed`
- `frameValidationFailed`
- `rendererEpochMismatch`
- `rendererRevisionMismatch`

Only the exact unresolved token may be rejected. Rejection runs no lifecycle,
does not commit the candidate tree or host-operation prefix, burns any issued
renderer revision, clears the barrier, and forces the next emitted wire frame
to be a full snapshot. Failures after live renderer commit or host dispatch
starts are terminal and must not use this path.

## Isolate protocol

The ordered UI-to-worker command stream contains:

- `VsyncGranted(generation)`
- `VisibilityChanged(generation, eligible)`
- `PresentationSucceeded(generation, presentationId, revision, events)`
- `PresentationRejected(generation, presentationId, revision, reason)`
- a same-port debug snapshot barrier
- disposal

The ordered worker-to-UI update stream contains startup readiness,
`CycleReady(presentationId, revision, optionalBytes,
recoverableDiagnostic)`, fatal diagnostics, debug snapshots, and disposal
completion.

The worker has `Booting`, `Ready`, `Pumping`,
`AwaitingPresentation(token)`, and `Terminal` states. Grants received behind
the presentation barrier coalesce to one pending grant for the latest live
generation. Visibility loss invalidates stored grants but retains an
unresolved presentation. Old-generation, duplicate, future, or unsolicited
presentation results reach no native call and are terminal coordinator
errors.

## Clock contract

The worker starts one `Stopwatch` immediately after native runtime creation
and converts checked elapsed microseconds to nonnegative signed 64-bit
nanoseconds immediately before each pump and accepted success
acknowledgment. Flutter frame timestamps and wall-clock time are not clock
authority.

The OCaml Driver records the supplied time source's initial `Time_ns` as its
logical origin. It rejects negative, decreasing, unrepresentable, or
origin-overflowing elapsed values before mutating time, input, lifecycle,
handler, or mounted-tree state.

## Consequences

Complete public Bonsai timer, observed-clock, before-display, after-display,
and lifecycle semantics advance without external Flutter input. Visually idle
foreground runtimes still perform one backpressured logical pump per eligible
Flutter frame and acknowledge no-diff presentation tokens on real frames.

Application suspension performs no logical pumping and promises no background
timer execution. The next foreground frames acknowledge any retained token
and catch up elapsed work.

Tests must use bounded frame counts or predicate-based helpers because a live
foreground root intentionally prevents `pumpAndSettle` from settling.
No upstream source, overlay, dependency revision, private time-source API, or
shadow timer registry is required.
