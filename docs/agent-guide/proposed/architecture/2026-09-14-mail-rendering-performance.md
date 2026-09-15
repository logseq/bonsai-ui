# Mail Rendering Performance

## Problem

Mail scrolling has excessive SwiftUI update/layout work and expensive idle
main-thread checks despite bounded row virtualization and inexpensive native
pumps. Optimizing only the bridge or changing the scroll container would not
address all mechanisms identified by the September 14 investigation.

This proposal records the agreed replacement design without backward
compatibility. The user accepted the recommended active-content animation
contract. B–F implementation and initial integrated correctness checks are recorded below.
The native extent/scroll correction is integrated in the working tree; the
current full Swift suite, platform compilation and Mail window checks pass.
Complete performance acceptance remains pending.
Static scaling exposed a residual OCaml validation scan; its repair passes OCaml,
native-boundary, complete Swift integration and native Mail window checks.
Controlled motion and complete performance verification remain pending.

### Evidence and limits

The baseline source is `5e8cbfe003c9d434aadc4f6b2f68015cfe889a98`. Artifacts are
under `/Users/rcmerci/benchmarks/bonsai-mail-20260914-1826/`: `report.md`,
`results.json`, and `diagnosis/causes.md`, with raw profiles and payloads. The
optimized macOS run used an M4 Max, macOS 26.6.2, Xcode 26.1.1 and a 120 Hz
display. These local artifacts are supporting evidence; the findings needed to
understand this decision are summarized here.

| Mechanism | Observed evidence | Design consequence |
| --- | --- | --- |
| Periodic retained-tree checks | Idle input/output stayed zero, but main-thread execution was 131.91 ms/s at Inbox top and 18.33 ms/s in empty Trash. Refresh sorts all nodes to find zero text fields and one collection, and repeatedly checks control ancestry. | Separate runtime pumping from presentation reconciliation; index relevant controllers. |
| Hidden expanded content | Initial 20 rows contained 2,629 nodes; 1,866 belonged to hidden expanded branches, 70.98% of the tree. Both branches are measured and placed. | Materialize one active content subtree per card. |
| Global geometry propagation | Every NativeNodeView publishes an anchor; the root merges and resolves all anchors. A short diagnostic interval contained 23,729 NodeLayoutAnchors preference transforms. | Resolve layout only for outstanding layout requests. |
| Broad measurement invalidation | Every commit advances an observable collection generation, including unchanged windows. Every measured row consumes it. New extents can rebuild geometry and rewrite ScrollPosition. | Separate callback validity from observable geometry and batch actual changes. |
| Handler churn | Three scroll runs generated 53/53/52 same-range requests after handler replacement; 53/52/52 responses were empty. Cost was about 3.1–3.3 ms/s of native execution. | Make handler dependencies describe callback behavior rather than the full Mail state. |

Of 15,399 running main-thread samples during scrolling, 73.35% included
AttributeGraph and 44.48% included NSHostingView.layout, versus 0.91% including
RenderTree.commit. These are overlapping stack categories, not exclusive time
allocations. They support prioritizing native update/layout work, but do not
isolate each amplifier's contribution.

Nonempty output-to-ack latency had a 165–176 ms median while pump p95 was about
1.8 ms and queue waits were microseconds. Existing counters cannot partition
the delay among graph updating, layout, CATransaction completion and main-actor
scheduling. Ack is not an actual frame presentation timestamp. Actual FPS
remains unmeasured; the previous hitch trace used discontinuous gestures and
is diagnostic evidence, not the required three-run continuous-motion acceptance.
Other Mail processes were present, so absolute timings also include possible
shared machine contention.

The retained row-root identities were stable in all 2,251 overlapping row-key
observations. There is no evidence of full-list reconstruction, repeated
snapshots, or an infinite measurement loop. The 750 ms pagination delay is
intentional application behavior, separate from ordinary scrolling.

## Proposal

Replace the five mechanisms above in independent, measurable steps. Keep OCaml
as the owner of Mail data, selection, expansion, paging and durable editor state.
Swift owns native layout, transient presentation, measurement caches and input
resources. Preserve revisioned event ownership and presentation acknowledgment.

### Governing principle: solve shared problems in bonsai-ui

If a problem can be solved correctly and generally in bonsai-ui, implement the
solution there instead of adding a Mail-specific fix. Apply this principle to
the public UI API, OCaml runtime/driver, bridge and native renderer. Mail is a
reproduction and acceptance workload, not a special case in framework behavior.

Before changing Mail for performance, identify why the shared layer cannot
solve the problem without application-specific knowledge. Only genuine Mail
business semantics or migration to an improved common API justify an example
change. Do not add Mail-only caches, throttles, node recognition or lifecycle
shortcuts for shared rendering defects. Validate general fixes with reusable
framework regressions as well as the real Mail workload. This principle governs
the candidate Mail changes below; they are not mandatory if a general solution
eliminates their need.

This proposal supersedes the earlier [Mail Scroll Runtime Traversal proposal](../../rejected/bugfix/2026-09-14-mail-scroll-runtime-traversal.md),
which has been retired through spec-dev-tool. Its traversal repair is included
here alongside the measured rendering causes; there is one implementation plan.
The [SwiftUI backend decision](../../proposed/architecture/2026-09-11-swiftui-only-apple-backend.md)
continues to govern supported platforms and business-state ownership.

### 1. Make layout measurement request driven

The all-node geometry cache has one production reader: `measureLayout` in
[HostServices.swift](../../../../swift/BonsaiSwiftUI/Sources/HostServices.swift).
Focus and gesture routing do not require every node's continuously cached frame.
The public `Host_effect.measure_layout` is already asynchronous, so it can await
a native layout result without adding an opt-in public widget API.

Replace the unconditional modifier in
[RenderTree.swift](../../../../swift/BonsaiSwiftUI/Sources/RenderTree.swift) and
the full-tree cache in
[NativeNodeGeometry.swift](../../../../swift/BonsaiSwiftUI/Sources/NativeNodeGeometry.swift)
with a request registry owned by the bound native window:

1. Resolve a presented target and register a request against its full
   RenderIdentity, native attachment identity and session epoch. Only that
   target activates an anchor publisher; unrelated nodes do not observe the
   registry's entire pending-request dictionary.
2. Resolve requested anchors in the existing application-root coordinate space.
   Coalesce concurrent requests for the same valid target/layout observation.
   Suspend the host-service task, never the main thread or presentation probe.
3. Fulfill each request once from an attached, valid layout observation, then
   remove its subscription. Do not reuse an earlier frame after content changes.
4. Cancel or fail pending requests on cancellation, target removal, attachment
   loss, epoch replacement or window closure. Bound an otherwise unresolved
   request with a documented internal timeout; distinguish timeout from an
   invalid target. A pending host request must not hold the presentation fence.

No pending requests means no per-node anchors and no full-frame dictionary.
Collection height measurement remains a separate, row-scoped mechanism. Tests
that inspect incidental `layoutFrame` population must instead exercise their
actual focus behavior or explicitly request layout. They must not force the
old global cache to remain.

### 2. Replace retained dual-branch surfaces with active content

The current [Morphing_surface contract](../../../../ocaml/ui/view.mli)
explicitly retains both keyed branches, including hidden native state. Merely
removing the hidden Swift view would violate that contract and would leave its
OCaml construction and wire traffic intact.

Replace the constructor's `compact_content` and `expanded_content` arguments
with a single `content` argument. Keep expansion state and duration controls as
presentation inputs. Build Mail's shared header once under stable keys and
conditionally construct detail content only while expanded. Delete the old
two-branch layout and branch-retention machinery. No adapter, alternate decoder
or retained hidden copy should preserve the old behavior.

The agreed visual contract is a stable card whose size and surface appearance
animate to the active content. It does not promise an exact crossfade between
two complete live subtrees. Removed detail controls immediately lose input,
focus and accessibility ownership; durable drafts and selections that must
survive collapse belong in OCaml. Native transient editing state is not retained
in an invisible branch. Reduce Motion and inactive scenes finish the animation.

Collection row placement must have one owner of extent interpolation. For Mail,
the collection coordinates row extent/neighbor placement; the surface reports
the active content's target size and animates visual styling. Do not nest a
second independent height animation that repeatedly changes the collection's
target. Rapid reversals retarget from the current displayed extent, not an
obsolete animation endpoint. Standalone surfaces may animate their own extent
when no collection coordinates it.

Migrate all consumers together: Mail, Gallery, `ocaml/ui/workflow.ml`, the native
runtime fixture, public docs and tests. Change the AST, encoder, wire validator
and Swift renderer atomically. The schema currently uses protocol 4.0; changing
node child semantics is incompatible and requires the next major version under
[protocol/README.md](../../../../protocol/README.md). Regenerate both languages
and fixtures, reject old frames, and never reuse a retired numeric ID for a
different node kind. This is a replacement of the existing node contract, not
a parallel legacy implementation.

### 3. Separate measurement validity from layout invalidation

Replace the observable generation advanced by every commit in
[CollectionMeasurements.swift](../../../../swift/BonsaiSwiftUI/Sources/CollectionMeasurements.swift)
and [RenderCollection.swift](../../../../swift/BonsaiSwiftUI/Sources/RenderCollection.swift).
Use three distinct concepts:

| State | Ownership and invalidation |
| --- | --- |
| Measurement context | Axis, width, Dynamic Type, direction, font and the declared measurement revision. A real context change invalidates affected cached extents and requires fresh measurements. |
| Row attachment token | Full mounted-row identity plus a context token. Used to reject callbacks from evicted/remounted rows or old contexts; bookkeeping is not a globally observed layout dependency. |
| Accepted extent | Cached by stable row key within the valid context. Publish layout changes only when an accepted extent actually changes. |

An unrelated commit or a window slide does not invalidate retained rows.
Newly mounted rows measure their active content. A native content-size change
is observed by that row's geometry callback without broadcasting a new sample
generation to every sibling. Key removal evicts its cache; an unchanged retained
key may reuse its cached extent after virtualization eviction until its declared
context becomes invalid.

Keep the public measured-catalog revision meaningful: changes that can alter
cached offscreen heights still invalidate those measurements. First establish
whether shared measurement invalidation and catalog handling can eliminate the
redundant work. Narrow Mail's revision calculation to actual sizing inputs only
where that distinction requires Mail-specific content knowledge; do not use
this adjustment to compensate for a general collection invalidation defect.
Append-only paging can preserve existing extents when existing
row content and declared extents are unchanged; width, text scale, expansion
and size-affecting content changes must not silently reuse stale measurements.
Global invalidation for a real declared revision change remains correct; a new
per-item revision protocol is not necessary for this first repair.

Collect valid changed extents into one scheduled main-actor batch, validate the
resulting geometry once, and replace the viewport geometry once per batch.
Revalidate attachment/context tokens at flush time. Ignore equal samples before
building overrides. Preserve key-based anchors through appends and reorders.

In [CollectionViewport.swift](../../../../swift/BonsaiSwiftUI/Sources/CollectionViewport.swift),
separate publishing new geometry from issuing a scroll command. The resize
investigation below shows that deferred absolute ScrollPosition corrections can
overwrite native travel, and matching their geometry reports cannot distinguish
all user input from command completion. Use an attachment-owned native position
accessor for geometry corrections on the existing SwiftUI collection instead:

- On the main actor, read current native travel before capturing or retargeting
  an anchor, then apply the correction synchronously. Apply this to immediate
  measured refinements as well as extent-animation samples. Preserve the exact
  logical anchor while aligning issued positions to display pixels.
- Convert the physical position and document/viewport extents for the current
  axis and layout direction. The UIKit accessor must account for native content
  insets; it must not infer coordinates solely from the latest model extent.
- Bind access to a native attachment identity and viewport object/axis identity.
  Retired callbacks and accessors cannot move a replacement view. Detachment
  captures pending travel, completes the logical animation, releases the native
  attachment, and prepares the retained anchor for remounting. Capture before
  the native coordinate hierarchy is removed, including unobserved travel when
  no extent animation is active.
- Use ScrollPosition for initial/unattached placement and explicit host scroll
  commands. Release persistent absolute placement before native geometry
  correction so a later SwiftUI update cannot replay an obsolete target. This
  is a lifecycle distinction, not a second compatibility renderer.

A size refinement that leaves the anchor unchanged must not restart positioning
or cancel the current gesture. Keep the existing CollectionWindowLayout and one
extent-animation owner. Preserve numerical-domain validation and reject invalid
batched geometry atomically. Validate mount replacement, detach/remount, initial
anchors, axis/direction changes and existing gesture behavior before promoting
the isolated native experiment; macOS-only benchmark success is insufficient.

### 4. Reconcile presentation on changes, not every pump

Build committed controller indexes in RenderTree: ordered fields and
collections, input-capable nodes, presentation nodes, and native extensions in
ancestor-before-descendant order. Reuse existing specialized indexes where
possible. A commit may traverse the materialized tree to maintain them; a
no-change refresh must not sort or scan decorative nodes.

Make presentation eligibility reconciliation explicit in
[BonsaiSession.swift](../../../../swift/BonsaiSwiftUI/Sources/BonsaiSession.swift).
Trigger it from commits, presentation/ack transitions, modal/navigation changes,
native mount/unmount callbacks, lifecycle changes and relevant controller
changes. Cache active-content eligibility by the state that actually determines
it. Do not replace periodic scans with repeated full ancestor walks for every
button on every refresh.

Native focus and gesture state can change without an OCaml commit. Their native
callbacks must mark the relevant controller dirty or update it directly. Clear
ownership synchronously on deactivation/detachment, including while an output
awaits acknowledgment. Simply moving every helper behind `pending == nil`
would be incorrect. Drain dirty work once, keep a small active-animation set
for frame-dependent updates, and sample collection requests from the collection
index. Disposal removes every retained index and pending dirty entry.

Keep the current runtime pump cadence for this repair: Bonsai clocks, scheduled
effects and native services still depend on runtime progress. Removing the
16 ms pump requires a separate wakeup/deadline contract that is not established
by these profiles. Idle pumping must perform constant session bookkeeping plus
work for relevant active resources, rather than work proportional to text/icon
node count.

### 5. Resolve handler churn at the appropriate shared boundary

First evaluate whether the common collection/handler API or driver can avoid
the feedback cycle while preserving revisioned callback behavior and delivery
to genuinely changed handlers. If a correct general solution is available,
implement it in bonsai-ui and validate it with a generic collection consumer;
do not require a separate Mail optimization. A shared solution must not ignore
behavior-changing dependencies or dispatch events to stale closures.

If the remaining issue requires application knowledge about which Mail state
affects paging behavior, use the following bounded example change. In
[mail.ml](../../../../examples/mail/ocaml/mail.ml), construct a dependency
record containing destination, relevant message count, load state, next cursor,
next generation and the stable setter/sleep functions. The callback must use
only this projection plus its event payload. Exclude painted indices, unrelated
selection, notices and read/star state when they do not affect those projected
values.

Keep native deduplication by `(handler, range)`: a genuinely changed handler
still requires synchronization. Never declare full-state snapshots equal while
allowing the callback to read omitted fields; that would retain stale behavior
under the Driver.Handler contract. Preserve current-state checks and generation
fencing around delayed page completion. Keep effects outside state updater
functions and preserve the intentional 750 ms page-load delay.

The target is zero handler replacement caused solely by recording a painted
range. Paging eligibility, destination or count changes may legitimately replace
the handler. They must remain separately identified in traffic results.

### Presentation fence and implementation sequence

Keep one pending candidate and its revisioned acknowledgment. Do not acknowledge
at decode/commit time, bypass the probe, or equate its CATransaction completion
with actual screen presentation. Add benchmark-only timestamps for native
return, commit completion, probe layout, transaction completion, main-actor
callback entry and ack enqueue. Use these to locate residual latency after the
layout changes. A remaining completion/scheduling bottleneck requires evidence
and a separate fence design before changing acknowledgment semantics.

Use the following sequence for implementation. Use focused failing behavioral
regressions before each implementation, then a controlled measurement of that
step. Keep artifacts and instrumentation differences outside production source
where practical.

| Step | Primary files | Behavioral proof |
| --- | --- | --- |
| A. Establish comparable baseline and stage markers | Benchmark harness; existing Mail binary and source manifest | Same viewport, row content, seed and delivered path; exact process and frame-data coverage. |
| B. Request-driven geometry | NativeNodeGeometry.swift, RenderTree.swift, HostServices.swift, NativeWindowHost.swift | No subscriptions without requests; correct root coordinates; cancellation, removal, concurrent requests and window/epoch teardown complete exactly once. |
| C. Active-content surfaces | ocaml/ui/view.ml and view.mli, ocaml/runtime/driver.ml, protocol/schema.sexp, MorphingSurface.swift, wire validation, all callers | Collapsed wire/native trees contain no expanded subtree; stable shared keys; rapid toggles, focus disposal, Reduce Motion and rejected old protocol frames. |
| D. Measurement and extent ownership | CollectionMeasurements.swift, RenderCollection.swift, CollectionViewport.swift; Mail catalog revision logic only for application-specific sizing semantics | Unrelated commits do not resample all rows; stale callbacks rejected; multiple size changes batch; no equal-position scroll commands; expansion/revisit/append preserve anchors. |
| E. Presentation reconciliation | RenderTree.swift, BonsaiSession.swift and controller mount/lifecycle callbacks | No-op refresh has no all-node scan; native-only changes still update focus/input; modal fencing, delayed ack and epoch disposal remain correct. |
| F. Handler churn | Shared collection/handler API and runtime/driver first; examples/mail/ocaml/mail.ml only if application-specific dependency projection remains necessary | Generic consumer and Mail avoid painted-only handler churn; destination/count/loading changes remain effective; late page completions cannot update another loading generation. |
| G. Integrated acceptance | Existing Swift/native tests and optimized real Mail application | All correctness and performance gates below pass in every required run. |

Steps C and D must be validated together for animation correctness before
claiming a usable Mail result. Capture isolated B/E/F contrasts and the coupled
C+D contrast; do not add their savings arithmetically or infer isolated causality
from the final aggregate result.

Implementation requires no planned changes to dune files or files under
`ocaml/spec/`. Public `ocaml/ui/view.mli` is outside that directory. If a future
step requires a restricted spec or build-file change, report the exact need
before expanding scope. No restricted spec or dune changes are planned.

### Implementation checkpoint (September 14)

- A: Preserved baseline source at commit `5e8cbfe` and built an optimized,
  independently instrumented Mail binary in
  `/Users/rcmerci/benchmarks/mail-rendering-performance-20260914/`.
  `instrument_baseline.py` records native return, commit completion, probe layout,
  transaction completion, main-actor entry and ack enqueue. Matched motion
  captures remain pending. The desktop was subsequently unlocked and foreground
  diagnostic measurements were collected; continuous-motion delivery and
  app-specific presentation attribution remain unresolved.
- B: Replaced the retained all-node frame cache with window-owned asynchronous
  requests and per-target subscriptions. Attachment/sample identities fence
  observations; cancellation, removal, replacement, window closure and the
  two-second timeout release subscriptions. Focus tests use native focus
  resources. Targeted suites passed (21 tests, then 11 lifecycle tests), and the
  three platform checks passed, including physical iOS module typechecking.
  Baseline/stage-B sources and test logs are preserved outside the worktree.
- C: Migrated the public constructor and Mail/Gallery/Workflow to one active
  child, upgraded BSFR to 5.0, regenerated both fixture families and removed
  branch filtering. Standalone surface regressions and real Gallery/Workflow
  passed (8 tests). An editor-removal regression exposed missing synchronous
  macOS focus release in the common text controller; disposal now disables it.
  Mail preserves a shared header and removes expanded detail nodes. Its action
  controls remain siblings of the header button for native accessibility. A
  real OCaml initial-frame census with 20 rows changed from 2,629 nodes and
  159,169 bytes to 863 nodes and 52,895 bytes; this is logical-tree/transport
  evidence, not a native-frame performance result.
- D: Replaced commit generations with context tokens and full row/mount tokens.
  Changed extents flush in a single validated main-actor batch; stale mounts,
  old contexts and invalid aggregate geometry cannot publish. Equal effective
  display-pixel positions do not issue scroll commands; RTL document growth
  still corrects its physical anchor. Newly mounted rows refine immediately,
  while subsequent active-row changes use collection-owned interpolation.
  Coupled targeted suites passed (19 tests), including both axes and LTR/RTL.
  A real Mail regression passed repeated expansion/reversal, shared-header
  identity, one-child trees, detail removal and collection extent ownership.
  `dune build @all @runtest @fmt`, generator/OCaml fixture checks, all decision
  checks and the three platform checks passed. Root-coordinate measurements
  after two native window resizes match native control frames.
- E: Committed controller indexes replace all-node refresh scans and sorts.
  Presentation reconciliation runs on commits, acknowledgment, lifecycle,
  modal changes and native ownership transitions. Cached eligibility is cleared
  synchronously on those transitions. Native focus/gesture controllers retain
  their direct mount callbacks; text fields retry autofocus from native
  attachment/layout callbacks. Session deactivation now revokes text-field and
  editor availability synchronously without treating a pending property
  acknowledgment as editor detachment. Seven integrated regressions passed,
  including native extension remounts, ancestor-first nesting, Disclosure,
  real Mail and 100/1000 decorative-node index isolation. Twenty unchanged
  pumps leave the reconciliation count unchanged. Two failures were reproduced
  before repair: Disclosure collapse retained input collection until the next
  pump, and an inactive session retained native text-field focus.
- F: The shared Driver.Handler API already provides stable identity for equal
  behavior dependencies. It cannot infer which Mail fields an arbitrary closure
  reads. Mail now supplies the specified paging dependency record; the callback
  reads only that projection and rechecks current generation when loading.
  Generic collection and Mail regressions preserve painted-only handler identity
  and fresh count/loading behavior. Mail sizing compares actual card sizing
  inputs: star changes and append-only pages preserve the measurement revision;
  read-font and expansion changes advance it. Both Mail failures were reproduced
  before their repairs. The OCaml build, tests and formatting checks passed.
  A seven-event painted-only C ABI replay, all below the pagination threshold,
  replaced the paging handler seven times in both baseline and C+D, and zero
  times after F. C+D emitted 15,262 response bytes versus 15,087 after F for
  these delivered events; this replay excludes native feedback/deduplication
  and is not scrolling or timing acceptance.
- G: The coupled C+D checkpoint passed all 500 Swift tests in 109 suites and
  both native Mail window appearances. The E+F run completed 503 Swift tests
  with one intermittent pre-existing pointer-contact lifetime assertion; its
  isolated rerun passed. That assertion now checks weak ownership after a
  scoped autorelease pool releases temporary Foundation references, and all
  five focused pointer tests passed. The repeated complete run passed all 503
  tests in 109 suites (468.824 seconds). E+F also passed both native Mail window
  appearances, the three platform checks, OCaml build/tests/formatting,
  viewport type checks and both generated fixture-family checks.
  Optimized B, C+D, F and E+F binaries, patches and source hashes are preserved
  beside the baseline. Matched controlled performance captures and
  all absolute frame-pacing acceptance gates remain outstanding. No performance
  gate or full completion is claimed by the correctness tests above.
- G diagnostics: Three consecutive warmed 10-second idle intervals on E+F
  emitted zero input/output bytes, preserved revision 25, and recorded no drops.
  Pump/ack rates were 58.28–58.47/s each. Native execution was 5.56–6.24 ms/s;
  whole-main-thread CPU was 6.61–7.94 ms/s. The latter bounds refresh CPU but
  does not directly measure it. These intervals are not the required three
  independent idle/motion/settled sequences; see `stage-ef-idle.summary.json`
  in the external artifact directory. CUA-delivered scrolling had a 204.84 ms
  p95 viewport gap and cannot establish continuous-motion acceptance. A local
  CGEvent helper was initially compiled and dry-run only. The user subsequently
  authorized the bounded native driver to activate the benchmark window, place
  the pointer and deliver each 20-second 60 Hz scroll, stopping on user takeover.
  A fresh Animation Hitches capture and recovery failed when
  temporary storage filled. The raw capture was preserved with a verified
  compression round trip in `live-diagnostic.ktrace.gz`; no frame gate is
  inferred from the incomplete trace.
- G follow-up diagnostics: Same-machine warmed Inbox-top measurements now
  include baseline, F and a fresh E+F process, with three consecutive 10-second
  idle intervals each. Whole-main CPU medians were 185.61, 71.48 and 6.09 ms/s,
  respectively; worst intervals were 186.75, 71.50 and 6.13 ms/s. All intervals
  emitted zero payload bytes, retained revision 5 and dropped no bridge records.
  Native-call elapsed wall-time medians were 8.75, 6.04 and 5.93 ms/s; these
  include any descheduling and bound execution rather than directly measuring
  native-thread CPU. The F/E+F contrast supports reduced idle refresh overhead,
  but does not replace scaling, instrumentation-overhead or full motion runs.
  `idle-contrast.json` and `.csv` preserve every interval and executable identity.
  For 116 nonempty outputs during the earlier discontinuous CUA motion, elapsed
  output-to-ack latency was p50 61.07, p95 70.05 and max 79.19 ms; commit-to-probe
  layout contributed a 40.12 ms median. Complete stage rows are preserved in
  `live-motion-stages.csv`; these wall-time stages do not certify actual frames.
  Current macOS Instruments explicitly disables Core Animation FPS as
  unsupported. Successful targeted Frame Lifetimes/Display traces still lack
  Mail-window presentation attribution; their global swaps are not Mail FPS.
- G residual finding: An isolated static fixture with 103 versus 1,003 retained
  nodes passed the main-thread and absolute idle bounds in three independent
  runs per size, but native-call elapsed cost increased from a 3.28 ms/s median
  to 6.06 ms/s. Every pair exceeded the 25% and 1 ms/s scaling thresholds.
  CPU sampling identifies `Reconciler.validate_unique_keys`/`check_children` in
  unchanged pumps. Validation currently traverses the candidate before the
  existing physical-identity reuse path. The repair extends that reuse to validation only
  when the candidate is the same immutable root as the validated mounted tree.
  It preserves revision/handler-base checks and validation of changed or full-snapshot
  candidates. An allocation-scaling regression failed before the repair and
  passed afterward; validation-fence regressions and the complete OCaml/native
  checks passed. Failed raw
  runs remain preserved in `static-scaling-results.json` and `.csv`.
- G static retest: Rebuilt optimized fixtures and repeated six independent
  processes, alternating 103/1,003 retained nodes. Every 10-second idle interval
  emitted zero input/output bytes, kept revision 1, and dropped no records.
  Native-call wall-time medians were 2.78/2.88 ms/s (worst 2.86/2.97); whole-main
  CPU medians were 5.69/5.71 ms/s (worst 5.87/5.94). No paired run exceeded the
  scale-growth threshold; all measured static idle absolute bounds passed.
  `static-validated-results.json` and `.csv` retain all runs and memory readings.
  Counter-disabled overhead, collection scaling and actual motion frames remain
  separate outstanding checks. The updated optimized Mail build and signing
  verification passed (`stage-g-manifest.json`). The final Swift run passed 503
  tests in 109 suites (468.054 seconds), and both native Mail window appearances
  passed after the residual repair.
- G collection preparation: Isolated optimized declared/measured fixtures now
  provide 1,000/10,000 logical items, matching row content, a 420x580-point
  viewport and overscan 4. `collection-scaling-plan.json` predates measurements
  and declares event/operation/byte budgets. Four real C ABI range replays pass
  those budgets, preserve overlapping row IDs and handler identity, reject no
  valid requests, and emit no output for a duplicate range. Each mode/count
  emits 6,532 bytes over the same six steady nonempty transitions; the tenfold
  logical-count change affects only initialization. These are codec/reconcile
  results, not native scrolling or measured-row feedback acceptance.
- G measurement provenance: The preceding idle and native interaction captures
  did not record system-frontmost application coverage. Their CPU, payload and
  structural results remain diagnostics; foreground performance acceptance is
  unmeasured. CUA window targeting alone did not establish system foreground.
  The authorized native driver now checks foreground and pointer ownership;
  a separate single-window ScreenCaptureKit observer checks foreground coverage.
  The first frame-observer calibration failed initialization and is retained as
  invalid measurement. Successful observer initialization alone does not validate
  frame counting: unchanged-window callbacks must be distinguished from actual
  content updates before this source can certify frame pacing.
  Subsequent native-input calibration produced 1,199 viewport updates during a
  20-second, six-point-per-tick path with two-second reversals. A sparse content
  signature distinguishes unchanged captured frames from window updates, but
  observation overhead and input timing still require validation. Initial
  moving captures detected about 59.9 changes/s with a 25.3 ms p95 interval;
  the input timer itself had approximately 4 ms p95 lateness. These are retained
  calibration findings, not completed foreground acceptance. The final
  counter-disabled Profile build and signing checks passed; its identity is in
  `stage-g-control-manifest.json`.
- G foreground residual: The first complete compact motion interval detected
  about 45.0 content changes/s, with p95 50.53 ms and maximum 75.49 ms; the
  counter-disabled contrast detected 44.34/s, p95 50.15 ms and maximum 66.47 ms.
  Both used the same 60 Hz input path. The observed pacing fails the target;
  calibrated frame-source and independent-run acceptance remain incomplete.
  Strict payload idle passed before/after the instrumented motion, with native
  wall time 3.14/2.89 ms/s and whole-main CPU 6.28/6.79 ms/s. Its post-motion
  ownership check stopped near the end of settling; the motion itself retained
  input ownership and frame-source foreground coverage. The control run retained
  ownership throughout. Output-to-ack latency was p50 43.52, p95 54.37 and maximum
  60.07 ms. No handler replacements, snapshots/resyncs, dropped records or
  predeclared compact byte-budget violations occurred; rows/nodes peaked at
  16/707. A separate counter-disabled, capture-free CPU sample has 5,516 running
  main-thread samples, 84.16% involving AttributeGraph and 61.37% involving graph
  transaction flushing (overlapping stack categories, not CPU percentages).
  The next bounded hypothesis is root observation: `BonsaiApplicationView.body`
  directly reads the changing presentation ticket while constructing its entire
  content hierarchy. Verify the invalidation boundary with failing regressions,
  isolate presentation-only observation in its own view, and contrast the same
  native workload before considering a container replacement. Preserve all
  presentation callbacks, lifecycle checks and acknowledgment fences.
- H: A real-runtime observation regression reproduced top-level invalidation on
  acknowledgment, incremental ticket publication and activity changes. The
  presentation observer now owns those reads in a separate SwiftUI view;
  content still observes root/application replacement. The regression and native
  counter-window presentation/removal test pass, as do all three platform checks.
  The first matched optimized Mail capture detected 59.14 content changes/s,
  versus 44.99 before the repair; whole-main motion CPU fell from 557.99 to
  244.35 ms/s, and output-to-ack p50 fell from 43.52 to 11.87 ms (p95 18.57 ms,
  maximum 19.62 ms). All 1,200 input ticks produced viewport updates, with the
  same 16,960 input bytes and 216,095 output bytes as G. The observation
  interval p95 remains 25.59 ms, so the absolute frame gate is not passed.
  Idle payload is zero before/after; whole-main idle upper bounds are 10.20 and
  6.04 ms/s, leaving the first refresh-CPU gate unproven. Foreground and input
  ownership coverage are complete. These are single-run contrasts, and source
  overhead plus the remaining required scenarios are still outstanding.
  `stage-h-manifest.json` identifies the build; `mail-h-compact-1/` preserves raw
  data, stages and JSON/CSV summaries. Full Swift integration passed 504 tests
  in 109 suites (469.923 seconds). The first native Mail run failed its light-mode
  synthetic mouse-drag check while dark mode passed; three unchanged light-mode
  repetitions and a subsequent full light/dark run passed. The initial failure
  remains preserved and its intermittent startup/input timing needs follow-up;
  do not treat reruns as evidence that the original failure did not occur.
  A subsequent direct-display-callback input calibration met its predeclared
  timing budget: 1,200 events in 20 seconds, input interval p95 17.45 ms, p99
  17.59 ms and maximum 17.84 ms. The declared 1,000-row calibration detected
  59.95 content changes/s with interval p95 17.32 ms, p99 17.64 ms and maximum
  25.07 ms, with uninterrupted foreground/input ownership and zero observer
  drops. Earlier input jitter therefore affected the frame-interval diagnostic;
  Mail and required independent scenarios must use the calibrated driver before
  acceptance. The H counter-disabled Profile build and signature verification
  passed; `stage-h-control-manifest.json` records its identity.
  Direct-callback Mail follow-up still misses the observed p95 pacing target:
  the counter-disabled control detected 59.80 changes/s, p95 25.02 ms and maximum
  34.49 ms; the instrumented run detected 59.85/s, p95 24.46 ms and maximum
  33.19 ms. Whole-main motion CPU was 219.33/227.45 ms/s. Both retained complete
  foreground/input ownership; idle main upper bounds were below 6 ms/s. The
  instrumented run retained the same traffic and row/node bounds, zero idle
  payload and zero drops; output-to-ack p50/p95/max was 11.60/19.53/21.15 ms.
  Its input p95 was 17.585 ms, and the control's was 17.547 ms, narrowly failing
  the separate 17.50 ms input calibration budget; that budget is unchanged.
  A capture-free H control CPU sample has 1,934 running main samples, 53.98%
  involving AttributeGraph and 35.68% NSHostingView.layout (overlapping
  categories). Long frame intervals are more often near commits, but most are
  not; correlation alone does not identify a sole cause. The isolated vertical
  LazyVStack study in `stage-i-lazy-plan.json` retains the exact transmitted row
  window, active content, measured extents and OCaml object. It does not select
  or modify the production container.
  The prototype failed anchoring: twenty -88-point viewport jumps occurred
  during six-point input steps, the path reached 450 instead of 720 points,
  and its longest changed-content interval was 983.80 ms. Its 44.90 changes/s
  and lower traffic cannot count as savings because visible motion differed.
  `stage-i-lazy-verdict.json` rejects this exact prototype; no production
  container replacement was made. A future native-container design must
  explicitly resolve lazy anchoring and row availability before timing claims.
- J diagnostic: A bounded view-work counter recorded all 1,200 input ticks and
  zero dropped records. All 1,620 NativeNodeView body evaluations belonged to
  1,620 newly created nodes; untouched nodes were not re-evaluated. There were
  120 collection body evaluations, 1,760 measured-row wrapper evaluations,
  1,820 row geometry transforms, 240 window size calculations and 480 placements.
  Scroll phase changed to interacting only once. This rejects retained content
  body churn and repeated phase toggling as the remaining mechanism.
  A raw catalog audit also corrected the warmed scenario description: cold
  mount has 20 messages, the first warm traversal publishes 21 keys including
  a loading row, then 40 messages before timed idle. Audited G/H/I/J compact
  captures share this sequence. Setup loading/completion frames are 18,126/442
  output bytes and remain outside steady-state totals. The 20-row cold census
  remains valid; it must not be described as the warmed logical count.
  The next isolated studies retain a bounded row window while preserving all
  visible-range callbacks, and replace relative row offsets with stable global
  indices in ForEach. Neither selects a production API or implementation change.
- K/L diagnostics (September 15): Conservative window retention preserved every
  visible-range callback and the full 0..720-point motion. Its first completed
  capture reduced patches from 120 to 42, output bytes from 216,095 to 139,973,
  and whole-main motion CPU from 227.45 to 180.18 ms/s. Observed content changes
  were 59.748/s, with p95/p99/max intervals 17.545/32.727/42.475 ms. These observed
  thresholds pass in one run; independent repeats, frame-source validation and
  other correctness scenarios remain incomplete. Input p95 17.568 ms narrowly
  fails its separate 17.50 ms plan. The first attempt stopped during warmup on
  ownership loss without posting scroll events and is retained as invalid.
  The peak remains 16 rows/707 nodes, but settling retains 15 rows/668 nodes
  instead of 11/512: the same total overscan budget is allocated asymmetrically.
  Output-to-ack p50/p95/max rises to 22.62/27.29/28.60 ms for larger refill
  patches. A shared policy and behavior tests are required before production.
  The stable-global-index alternative produced exactly the same J work counts
  and is not selected. All prototypes remain outside the production worktree.
  The counter-disabled K follow-up failed to reproduce the pacing pass:
  59.075 observed changes/s, p95/p99/max 24.937/33.430/42.682 ms, and main motion
  CPU 182.29 ms/s. Window retention is therefore not accepted for production.
- M diagnostic (September 15): Replacing SwiftUI scroll geometry observation
  with native clip-view bounds notifications preserved 1,200 input events and
  the 0..720-point path, but reported a 631-by-581-point viewport versus H's
  420-by-581-point viewport. The visible list still appeared 420 points wide.
  This coordinate discrepancy prevents a matched-geometry performance verdict.
  Observed changes were 59.198/s with p95/p99/max 24.570/32.839/33.967 ms and
  main motion CPU 250.62 ms/s. Preserve these results as diagnostic evidence;
  resolve the native coordinate source before attributing any timing difference
  to the observation mechanism. No production implementation was changed.
  The bounded M2 native census explains the discrepancy: the HostingScrollView
  spans 648 points, its clip/document visible width is 631, and the collection
  probe has a 228-point horizontal offset. The native document rectangle is not
  an equivalent replacement for the SwiftUI viewport; this substitution is not
  selected.
- N diagnostic (September 15): Initializing each measurement mount UUID on its
  first appearance, with a stable nil State initializer, reduced measured-row
  body calls from 1,760 to 120 and geometry transforms from 1,820 to 180. The
  completed 20-second run preserved 1,200 inputs, the 420-by-581-point viewport,
  exact 0..720-point motion, 120 patches, 2,340 created/dropped nodes and
  16,960/216,095 input/output bytes. No diagnostic records were dropped.
  An integration work-count regression fails against J with 872 evaluations of
  rows already present before motion; its expected count is zero for unchanged
  retained rows. Add native lifecycle coverage for initial measurement, removal,
  replacement and context changes in both axes before applying the production
  repair. Fresh timing, complete regressions and the original acceptance matrix
  remain required; lower work counts alone do not establish frame acceptance.
  The repair is now applied to the production measurement wrapper. Thirteen
  focused tests pass, including real Mail, Gallery in both axes/LTR/RTL and the
  new native lifecycle cases. The first timing run preserves the same motion,
  bridge operations and row/node bound, but does not demonstrate a timing win:
  main CPU is 232.36 ms/s versus H's 227.45, with 59.125 observed changes/s and
  p95/p99/max 24.906/33.437/34.659 ms. Idle traffic and native/main CPU gates
  pass. The separate input p95 gate still fails at 17.553 ms. Full regressions,
  counter-disabled timing and the original acceptance matrix remain open.
  Full N validation subsequently passed 505 Swift tests in 109 suites
  (481.594 seconds), all three platform checks (28.655 seconds), and native Mail
  with both host appearances (15.081 seconds). The measured diagnostic source
  matches production after excluding only counters, comments and whitespace.
  `stage-n-mount-verdict.json` records exact hashes and validation evidence.
  Three fresh counter-disabled N compact captures subsequently completed.
  Observed change rates were 59.875/59.949/59.949 per second, with p95 intervals
  17.768/17.662/17.557 ms and whole-main CPU 212.39/211.66/208.68 ms/s. All three
  observed pacing thresholds pass; the first input p95 narrowly fails its
  independently declared gate. These are captured-window observations, not
  proof of complete app presentation coverage. Conservative interval bounds
  were verified against discrete timeline refinements, but depend on the
  capture timestamps identifying actual display changes. Physical display
  attribution, instrumentation overhead and remaining scenarios stay open.
- Native hitch diagnostics (September 15): Exact-PID Instruments attribution
  now provides stronger evidence than the earlier global frame tables. The N
  control's standard Animation Hitches plus Display trace contains 91 target
  hitches with 783.33 ms of union duration, entirely inside the marked 20-second
  motion. A lighter Blank-template Hitches plus Display run, without Time
  Profiler, contains 110 hitches totaling 933.33 ms. Even dividing these partial
  captures by the full motion gives lower bounds of 39.17 and 46.67 ms/s, above
  the 5 ms/s gate under these instruments. Instrument overhead remains an
  explicit limitation; absence of Time Profiler does not imply zero overhead.
  The standard trace's 2,993 running main-thread samples contain ViewGraph
  update in 46.14%, AttributeGraph in 42.77%, hosting layout in 28.37% and hit
  testing in 15.57%. These inclusive categories overlap and are not utilization.
  Joining exact-PID update swap/surface IDs to frame lifetimes and then matching
  lifetime endpoints to displayed surface times is promising, but the tables
  label the display differently (Display 4 versus Display 1). Surface/time
  matches alone do not resolve display identity. Formal frame acceptance stays
  UNMEASURED; no global swap count or frame lifetime is reported as app FPS.
- O isolated hosting diagnostic (September 15): A macOS-only prototype places
  each measured row's native content inside its own NSHostingController while
  retaining the original measurement wrapper, ScrollView, window and OCaml
  object. The instrumented compact capture preserves 1,200 inputs, the viewport,
  full motion and 16,960/216,095 traffic bytes. Main CPU falls to 161.36 ms/s and
  observed p95 is 17.516 ms. Its counter-disabled capture uses 164.54 ms/s but
  observed p95 is 25.035 ms, above the threshold. A separate light Instruments
  trace attributes 94 hitches totaling 808.33 ms to this exact process; the
  full-motion lower bound is 40.42 ms/s. This prototype is not selected for
  production: lower CPU has not established acceptable pacing, and layout
  requests across hosting boundaries, expansion, input ownership and iOS
  semantics are not certified. Preserve both passing and failing observations.
  The next isolated contrast keeps the same collection/bridge behavior and
  replaces native row content with a single 88-point text row to distinguish
  row complexity from the remaining scroll/window infrastructure cost.
- P simple-content diagnostic (September 15): Keeping the N instrumented
  collection and bridge unchanged while replacing native measured-row content
  with one 88-point text row preserved all 1,200 input/viewport updates, the
  420-by-581-point viewport, 40 warmed logical rows, full 0..720-point motion,
  120 patches, 2,340 created/dropped nodes and 16,960/216,095 bytes. Whole-main
  CPU fell from 232.36 to 117.30 ms/s; observed changes were 59.974/s with
  p95/p99/max 17.373/17.712/18.900 ms, and output-to-ack p50/p95/max became
  4.613/7.512/9.044 ms. Input timing gates pass in this run. This establishes
  a substantial native-content cost under an unchanged OCaml workload, while
  deliberately omitting Mail controls; it is not a production simplification.
  The separate light Instruments run still attributes 57 hitches / 491.67 ms
  to the target, a full-motion lower bound of 24.58 ms/s. The hitch gate remains
  failed under the instrument despite the observed pacing pass. Independent
  counter-disabled repeats and the formal simple-row scaling scenario remain
  distinct requirements.
  Q is prepared as a diagnostic-only contrast omitting NativeLayoutPublisher
  around native nodes while retaining real Mail content. Layout requests are
  intentionally unavailable in this prototype; no production omission is
  authorized by its results. After unlock, Q preflight detected user interaction
  before formal input capture, so native measurement remains pending until an
  available foreground interval. R is separately built with only the swipe-pane
  GeometryReader conditional on an exposed pane; independent size configuration,
  gestures and action metadata remain unchanged. This tests empty background
  geometry cost without conflating it with Q's layout publisher omission.
  Actual action reveal/close, both axes, LTR/RTL, resize and native ownership
  regressions remain required before selecting any production R change.


- Compact diff audit (September 15): Replay of every N wire operation verifies
  1,700 overlapping row identities and their complete subtrees. The 120 outputs
  are incremental, with no unchanged property/child-list writes, binding churn,
  catalog retransmission, full snapshot or unrelated creates/drops. Sixty row
  entries/exits account for 2,340 node creates/drops in each direction. Revisited
  evicted rows are recreated; retained rows are preserved. Whole bounded key and
  child-ID arrays repeat 22,880 bytes of retained identifiers (10.59% of the
  216,095-byte output), so the protocol is incremental but not a minimal splice
  encoding. Entry/exit subtree operations account for 79.54% of output. H and P
  captures independently have identical counts/bytes. See `scroll-diff-audit.md`
  and per-run `diff-audit*.json`; other interaction scenarios remain unaudited.


- Native presentation source follow-up (September 15): Exact target PID updates
  can now be joined by display/swap/surface identity to frame lifetimes, then by
  unique swap/surface IDs to actual hardware swap timestamps. This supersedes
  the earlier timestamp-proximity join and avoids assuming display-label aliases.
  Eleven utility regressions cover process filtering, duplicate updates, wrong
  surface/swap, ambiguous display/hardware identities, missing lifetime/interior
  data, tail preservation, endpoint disagreement and long intervals. Both the
  tests and actual N/O/P trace replays pass the association checks. Matched
  presentations number 622/711/710; endpoint disagreement is at most 124 ns.
  Their diagnostic native p95 is approximately 25 ms in all three variants.
  These short captures do not cover full marked motion; formal frame acceptance
  remains UNMEASURED and hitch diagnostics still exceed the gate. SCK's passing
  captured-window bounds are explicitly conditional, not physical presentation
  acceptance. Full-interval native capture and controlled instrument overhead
  are the next required evidence once the foreground Mac is available.


- Q/R foreground contrasts after unlock (September 15): Q completed with
  188.58 ms/s whole-main CPU; the immediately repeated N baseline used
  220.99 ms/s, a 14.67% difference. Both observed p95 values remain about
  25 ms. Q's input p95 narrowly fails its separate gate at 17.504 ms. R used
  234.34 ms/s, with observed p95/p99 24.990/33.465 ms and no demonstrated
  improvement. All three preserve 1,200 inputs/viewport updates, the full
  0..720-point path, 40 warmed rows and 16,960/216,095 bytes; the detailed diff
  audits report no redundancy violations. Q is diagnostic-only and R is not
  selected. `qr-layout-comparison.json` preserves exact identities and results.
  A following same-binary plain/native-recorder pair excludes SCK: whole-main
  motion CPU is 244.92 ms/s without a frame recorder and 250.90 with light
  Hitches/Display recording, a single-pair increase of 2.44%. This is preliminary
  overhead evidence, not repeated-run acceptance. The new trace spans the full
  input sequence, but exported frame data fails validation: 12 target frame
  lifetimes inside motion have no corresponding hardware swap, even when
  searching by swap ID without surface filtering. Hardware records contain an
  interior gap around trace seconds 27–29. The trace has only 211 distinct
  target update keys and 227 lifetime rows, so completeness of the Hitches
  detail tables is also unresolved. The strict join rejects the capture;
  missing records must not be removed to calculate a passing result. CPU and
  diff diagnostics remain usable separately; full-motion frame acceptance is
  UNMEASURED. Earlier short-trace associations establish identity consistency,
  not completeness of presentation coverage. An explicit Frame Lifetimes
  source contrast is required before relying on these tables for FPS.
  The explicit Frame Lifetimes contrast completed all inputs and saved its
  50.45-second trace, but is rejected for acceptance: recorder footprint peaked
  at 126.3G on a 64 GiB machine, and the reused target's bridge buffer dropped
  90,699 entries. Preserve it only for source semantics. No CPU, diff or FPS
  acceptance follows from this run. Exported hardware swaps end at trace
  second 27.8724, before motion ends; 2,922 of 5,844 legacy lifetime rows have
  raw start timestamps outside the 50.45-second trace. No heuristic timestamp
  correction or deletion establishes frame coverage. The recorder and exports
  have exited. The random layout-owner initialization
  hypothesis is also not supported by existing N work counts: all 1,620 layout
  publisher body calls correspond to new native nodes, with no retained node
  body work; no owner change is selected.

- Current declared collection scaling (September 15): Three fresh native runs
  each at 1,000 and 10,000 items complete the guarded 10/20/10-second sequence
  with the same 420x580 viewport and full 0..720-point path. All six runs have
  150 window transitions, 15,900 input bytes, 99,190 output bytes and at most
  21 rows/70 nodes; all three size-scaling ratios are 1.0. Exact wire audits
  preserve overlapping rows and report no redundant updates or predeclared
  byte-budget violations. Initial catalog frames are separately 10,050 and
  82,050 bytes. All twelve idle intervals pass traffic/execution bounds.
  Motion whole-main CPU median/worst is 116.11/125.83 ms/s at 1,000 items and
  118.46/136.60 at 10,000. Four input p95 gates narrowly fail; actual frame
  pacing, counter-disabled overhead and remaining scenarios are still open.
  See `final-declared-scaling-report.md` and the matching JSON/CSV results in
  the external artifact directory. No overall acceptance is claimed.
- Measured scaling exposed two same-handler duplicate range requests while
  the rows were already materialized. Native view regressions reproduce the
  issue after an overscan text resize and a measurement-context change: the
  final range stays 0..<3 but is requested again. Both fail before the repair.
  Measurement publication now preserves the last accepted handler/range;
  actual range and handler changes remain detectable, while catalog changes
  and unfilled-window synchronization retain their retry behavior. The native
  retest removes exactly two inputs (212 bytes), from 262 to 260 range events,
  without changing 121,465 output bytes or 220 patches. All three repaired
  1,000/10,000-item pairs now have identical traffic, no duplicates, maximum
  20 rows/67 nodes and the full matched path. All twelve idle intervals pass.
  Preserve the failing capture as `final-measured-1000-1`; retests are
  `request-measured-*`. Motion whole-main CPU median/worst is 116.17/144.44
  ms/s at 1,000 items and 127.55/149.55 at 10,000. No CPU speedup is attributed
  to the request repair. The first 10,000-item input p95 is 17.539666 ms and
  fails the unchanged 17.50 ms input gate; the other five pass. Input timing
  does not measure app presentation intervals. See
  `request-measured-scaling-report.md` and matching JSON/CSV artifacts.
  Current integration passes 506 Swift tests in 109 suites (479.723 seconds),
  three platform checks (29.194 seconds), and native Mail window validation
  under both light/dark host appearances (15.326 seconds). Actual frame pacing
  and the complete performance matrix remain unproven.
- Current static foreground scaling (September 15): Three fresh processes
  each with 103 and 1,003 decoded retained nodes pass all twelve idle intervals:
  zero payload, events or operations, stable revision/snapshot/resync counts,
  no lost records, and idle execution/call bounds satisfied. At 103 nodes,
  idle main median/worst is 5.389/5.504 ms/s and native call wall time is
  2.468/2.559; at 1,003 nodes these are 5.380/5.441 and 2.720/2.935. Settled
  main medians are 5.177 and 5.532, and native wall medians 2.376 and 2.509.
  No paired idle comparison triggers the combined >25% and >1 ms/s growth
  gate. Four input timing failures are retained separately. The small static
  tree fits the viewport, so these are idle comparisons, not matched motion
  measurements. The original static source differs from the repaired measured
  source only in the two collection-only request resets; ordinary Scroll
  does not execute those methods. Source identity and this scope are recorded
  in `final-static-foreground-plan.json`; complete results are in
  `final-static-foreground-report.md` and matching JSON/CSV artifacts.
  Counter-disabled overhead and actual motion frames remain unmeasured.
- The display-crop follow-up is implemented outside production and has fifteen
  passing geometry/occlusion guard cases after recorded failing baselines. A
  full-window attempt stops before input on rectangle occlusion. A fixed
  100x480-point interior strip then completes the simple measured collection
  sequence with 1,199 sampled content changes and zero idle changes. However,
  all 6,004 display timestamps are later than callback receipt (motion median
  about 4.03 ms in the future), violating the predeclared source check. This
  does not establish actual FPS or justify timestamp correction. Apple DTS
  records the same symptom without a supported resolution. See
  `display-crop-source-report.md` and the captured frame-source verdict. The
  guard's sampled visibility and total observer overhead also remain limits.
- Current counter controls now have three alternating on/off pairs each for
  the 1,000-item measured collection and 1,003-node static tree. All twelve
  fresh processes complete the guarded input sequence and all twenty-four
  idle intervals stay below the 10 ms/s whole-main upper bound. Paired motion
  CPU increases have median/worst 1.276%/7.808% for measured rows and
  1.827%/2.835% for static rows; the largest positive idle differences are
  0.280 and 0.152 ms/s. No predeclared CPU diagnostic flag fires. Five input
  timing gates fail and remain recorded. Counter-on paths/traffic are audited;
  controls have matching source, fixture, input and endpoint UI evidence but
  no per-event viewport recorder. These results do not establish zero overhead,
  a timing correction factor, frame-observer overhead or real Mail coverage.
  See `counter-overhead-current-report.md` and its full JSON/CSV results.

- Real Mail expanded-run preparation exposed a correctness failure before the
  third timed sample: after loading another page and returning to native offset
  zero, the first two rows remain blank. The preserved bridge trace continues
  requesting visible range `6..<14` and retains window `2..<18` despite the
  final native geometry observation at offset zero. Evidence is preserved in
  `current-mail-warmup-blank-1`; the two earlier expanded captures remain scoped
  pre-repair evidence, not complete correctness acceptance.
- Investigate measured-anchor lifetime with native ScrollView regression tests.
  A catalog append or an extent refinement below the leading item must not
  suppress subsequent native scrolling when it issued no position correction.
  A genuine outstanding correction must survive another geometry replacement
  until native layout reaches its target. Write and run the regressions before
  changing production code, then validate both paths and rerun real Mail.

- The native regression reproduces the blank-window cause in four cases:
  vertical/horizontal catalog append and trailing extent refinement all retain
  internal offset 4007 after native offset reaches zero. Two pending-correction
  controls already pass. The repair retains a measurement anchor only while a
  programmatic position correction is outstanding. All six cases then pass,
  together with nineteen targeted tests across five suites. The complete
  Swift suite passes 507 tests in 109 suites (495.882 seconds; fresh xUnit
  validated), and all three supported-platform checks pass. The new isolated
  Profile Mail build is recorded in `measurement-anchor-mail-manifest.json`;
  all three fresh real Mail repetitions now restore the first two rows after
  the original failing warmup. The native Mail host test also passes in both
  light/dark appearances (15.265 seconds). Each captured motion has 150 range
  events, 110 patches, 15,900 input bytes and 239,750 output bytes, no redundant
  operations/lost records, and at most 16 rows/826 nodes. The expanded first row
  is evicted and reenters five times per run with the same 158-node structure;
  native endpoint checks show the complete expanded card at the top. All six
  idle intervals pass. All three input p95 gates fail slightly (17.562, 17.508,
  17.547 ms versus 17.50 ms), and actual frame pacing remains unmeasured. See
  `measurement-anchor-expanded-report.md` and its JSON/CSV. This closes the
  reproduced false-anchor correctness issue, not the complete performance
  decision or untested interaction scenarios.

- Three fresh current Mail processes now exercise pagination during motion:
  20 messages become a 21-key loading catalog and then 40 messages before the
  first reversal. All three have 162 range events, 121 incremental outputs,
  17,172 input bytes and 216,759 output bytes. The 442-byte append frame retains
  all sixteen materialized rows with zero node creation/removal. Exactly two
  handler replacements accompany the two catalog changes; no range-only churn,
  duplicate same-handler range or unrelated subtree recreation is found.
  All 3,600 native geometry samples match the prescribed path and remain
  covered by the latest completed Swift window commit. The coverage checker
  also detects the preserved pre-repair blank-top failure. All six idle
  intervals pass and no records are lost. Input p95 remains over budget in
  all three runs (17.582, 17.567, 17.581 ms); this variation is already present
  at display-link callback receipt, before input construction/posting. No
  application-computation attribution or frame-rate claim follows from it.
  See `measurement-anchor-paging-report.md`, its JSON/CSV, and
  `paging-input-timing-diagnostic.json`. Paging cancellation/navigation races,
  expansion during motion, resize/large text, current Mail observer overhead,
  memory plateau and actual frame acceptance remain separate open work.

- Read-only input-clock diagnostics preserve three display-link probes and
  three absolute-wait probes, plus three absolute-wait probes with a bounded
  low-latency ProcessInfo activity. All nine fail the existing input timing
  gates; neither tested absolute-wait variant is an improvement. QoS checks
  report the userInteractive class. No events are posted and the authorized
  driver is unchanged. These rejected diagnostic candidates do not relax the
  input gate, rewrite previous measurements or establish actual frames. See
  `input-clock-probe-report.md` and its raw source-identified results.


- Three fresh real-Mail resize captures (`resize-mail-expanded-2/3/4`) now
  complete 560 → 340 → 560 column changes during native scrolling, using an
  isolated host and the unchanged guarded driver. All 3,659 native viewport
  samples are covered by the latest completed window commit using captured
  sparse measured geometry. All six idle intervals have zero payload; no
  lost records, handler churn, duplicate requests, unrelated retained-row
  recreation or full-frame/resync delta is found. The expanded row survives
  five evictions/reentries per run with its original 158-node ordered shape;
  materialization stays within 16 rows / 826 nodes. Motion output is
  218,780 / 215,150 / 215,150 bytes. Two input p95 gates fail (17.549 and
  17.580 ms); the first passes at 17.324 ms. Whole-main CPU has median
  220.240 and worst 230.575 ms/s, without a new observer-overhead contrast.
  The first attempted capture remains INVALID_WORKLOAD: an old overlapping
  window received input instead of the target. The fixture now explicitly
  fronts its own window, checks stacking before capture, and schedules
  resizing from the first received driver event. These are benchmark-only
  changes; production Swift/OCaml and the original driver are unchanged.
  Coverage does not establish correct measurement/anchor semantics: native
  offset ends at 209 / 209 / 215 points from a 291-point start despite zero
  net scroll input, while width changes trigger extent/position corrections.
  A focused native timeline audit finds 13 / 9 / 13 backward movements in
  the first 300 ms after restoring the wide column, while driver input is
  exclusively forward. Directional scroll continuity therefore fails;
  an animation anchor overwriting phase-less wheel movement is a hypothesis
  pending native regression, not a proven cause or an implemented fix.
  See `measurement-resize-direction-diagnostic.json`. Do not claim no-jump
  acceptance. The macOS Dynamic Type probe also reports scale 1 for both tested categories, so it
  does not certify large-text coverage. Actual frames/hitches remain
  unmeasured. See `measurement-resize-report.md`, JSON/CSV, per-run geometry
  and action timelines, and `measured-coverage-tests.log` (two checks pass,
  including detection of the preserved real blank-window failure).


- The resize follow-up now has native regressions for phase-less movement,
  half-point input, both axes/directions, horizontal RTL, and changing rows
  before the anchor. The original inside-row cases lose all 36 points of
  input. A display-pixel comparison candidate passes the first regressions
  and a 509-test full suite, but later RTL/above-anchor cases still fail.
  Its one completed real-Mail diagnostic (`scroll-anchor-resize-2`) removes
  the restore-time backward oscillation while ending at 244 rather than the
  predeclared, geometry-validated 299 points. Window coverage and idle pass;
  motion endpoint correctness fails, and input p95 also fails at 17.515 ms.
  The earlier attempted run was interrupted during warmup and is retained
  as invalid. Both candidate approaches were reverted; the new regression
  tests remain to expose the unresolved production defect. The narrower
  full-suite pass is historical candidate evidence, not current acceptance.
  All original gates remain open as applicable. See
  `resize-anchor-investigation-report.md` and `resize-anchor-repair-plan.json`.
- Ordered native traces now show pending absolute scroll corrections overwriting
  native movement, including a repeated application after an initial matching
  geometry report. Velocity preservation and pending-target matching do not pass
  the regressions; half-point input may coincide with the correction target.
  A bounded AppKit-only synchronous correction experiment now passes 18
  targeted tests in five suites, including native wheel input, immediate
  retargeting, trailing-edge completion and stationary fractional anchors.
  Earlier one-point and retargeting failures remain recorded. This experiment
  is isolated and has not been selected for production; shared attachment and
  supported-platform behavior, full integration and real-Mail validation remain
  required. No performance gate changes. See `native-scroll-order-report.md`
  and its JSON results.
- The synchronous animation-only experiment completes a real-Mail resize run,
  but ends at 227 rather than the unchanged 299-point prediction. The remaining
  72-point deficit coincides with a post-animation row-height refinement from
  362 to 434 after reentry. Both idle checks, structural reentry and native
  window coverage pass; input p95 fails at 17.538 ms and frames remain
  unmeasured. An immediate-refinement/native-input regression then exposes
  another stale-anchor boundary. Extending the isolated correction to immediate
  changes passes 19 targeted tests in five suites, but requires fresh Mail
  validation and shared-platform work before any production selection. See
  `measurement-synchronous-results.json` and `native-scroll-order-report.md`.
  The first two all-corrections attempts are retained as INVALID_CAPTURE after
  takeover (zero / 848 input events). Three subsequent fresh processes complete
  all 1,200 events and both width changes: native endpoints are 299 / 299 / 299,
  restoration has no opposing movements, and all 3,630 native viewport/window
  joins pass coverage. Each run has 150 range events, 110 incremental frames,
  15,900 inbound / 239,750 outbound bytes, bounded 16 rows / 826 nodes and no
  handler churn, redundant diff or record loss. All six idle intervals pass.
  Input p95 is 17.273 / 17.452 / 17.519 ms; the third fails the unchanged gate.
  Actual FPS remains unmeasured. These scoped macOS results justify developing
  a shared attachment-aware correction design, not promoting the AppKit-only
  prototype. Production integration and all remaining original acceptance work
  are still required. See `measurement-synchronous-all-report.md` and JSON/CSV.
- Attachment hardening subsequently exposed stale-access, remount, axis and
  dynamic-direction defects in that isolated candidate. The replacement uses
  mount ownership and a captured axis/direction environment; it completes
  old-direction native travel before replacing that environment. Twenty-two
  lifecycle parameter cases and initial node tests now pass (8 functions,
  12.584 seconds). Broader integration and shared-platform work remain pending;
  earlier Mail results do not validate this latest source. See
  `native-scroll-direction-owned-lifecycle.log` and `native-scroll-order-report.md`.
- The shared isolated candidate subsequently passes the full 517-test /
  109-suite binary (558.504 seconds), 19 affected tests after synchronizing
  current production test files (12.568 seconds), and all three platform/module/
  example compilation checks (30.981 seconds). One new optimized Mail resize
  capture passes endpoint 299, coverage, semantic traffic, idle and input gates.
  A subsequent attempt stops during warmup on takeover without scrolling; two
  repetitions await timing. Production integration, physical UIKit lifecycle/
  coordinate verification, and actual-frame acceptance remain pending. See
  `measurement-owned-report.md` and `native-scroll-order-results.json`.
- A clean isolated copy now matches current production framework sources except
  for the native correction candidate. After removing all three inherited
  benchmark instrumentation changes, 21 selected offscreen macOS regression
  tests in four suites pass (107.924 seconds). This is a scoped clean-source
  checkpoint, not full production or FPS acceptance. The user has paused
  iPhone testing; no device test was installed or launched in this continuation.
  See `native-scroll-clean-results.json`.

### Production native correction integration (September 15)

The shared candidate is now integrated in the working tree. Native corrections
read pending physical movement before applying row-extent changes; attachment
ownership rejects retired geometry/writeback callbacks and pins the mounted axis
and direction until retirement. Initial placement and explicit host commands
continue to use ScrollPosition. The platform access views share ownership logic.

A new native window-removal regression caught a remaining lifecycle defect:
without an extent animation, removing the window before SwiftUI's next geometry
callback lost the final six points of native travel. All six nonanimated
axis/direction/sign cases failed (18 assertions); the six animated cases passed.
Capturing native position for both paths and releasing it before the coordinate
hierarchy is removed fixes all 12 cases. The original RED log is retained as
`native-scroll-window-removal-red.log`; GREEN is
`native-scroll-window-removal-green.log`.

The uninstrumented candidate then passes 22 tests in four suites (118.251 seconds),
covering the existing native travel, animation, lifecycle and initial-position
regressions. Three supported-platform/module/example compile checks also pass
(28.300 seconds). These are candidate results. Post-integration tests against the
actual working tree pass: 36 tests in seven suites (123.728 seconds), plus three
actual-worktree platform/module/example compile checks (28.200 seconds). The
subsequent required full Swift runner passes 520 tests in 109 suites (595.212
seconds), and actual Mail window checks pass under both light and dark host
appearance (15.336 seconds).
See `native-scroll-production-integration-manifest.json` and
`native-scroll-integration.patch` in the artifact directory.

The previous single valid owned-resize capture belongs to the earlier candidate
and is retained as historical evidence. It is not pooled into acceptance for this
new source. Three fresh current-source repetitions and the remaining interaction,
frame-pacing, overhead, memory and stage-attribution requirements remain pending.
iPhone runtime testing stays paused at the user's request; compile checks did
not install or launch an application on that device. The decision remains
PROPOSED and overall acceptance remains incomplete.

### Current-source measurement preparation

Two optimized macOS Mail builds now exist for the integrated production source:
`measurement-integrated-mail-on.app` and `measurement-integrated-mail-off.app`.
The off framework matches every production Swift source; the on framework adds
only the four documented boundary/stage/viewport instrumentation changes. Both
use the same guarded resize host and native OCaml object. Source fingerprints,
full dirty production patch and binaries are recorded in
`measurement-integrated-mail-manifest.json` and the per-build manifests.

`measurement-integrated-mail-resize-plan.json` fixes the current-source scenario;
`measurement-integrated-mail-overhead-plan.json` fixes three alternating off/on
pairs. The three on runs also serve as the new resize correctness repetitions.
The off capture passes `none` to the bridge export wrapper, so it never sends a
benchmark export signal to an uninstrumented process. Host resize logs remain
available after normal application termination. No new capture has run yet.

The required complete Swift command is `python3 tool/run_swift_tests.py`, whose
fresh xUnit report prevents zero-test or incomplete runs from passing. That
command now passes: 520 tests in 109 suites (595.212 seconds), with exit zero
after fresh xUnit validation. The earlier plain `swift test` attempt was
interrupted because its invocation omitted the required xUnit output; its log
and interruption reason are retained and are not a completed test result. After
the verified full run, `python3 native/test/test_mail_window.py` also passes
against the current framework under both host appearances (15.336 seconds).
Source/log fingerprints are in `native-scroll-production-complete-correctness.json`.
iPhone runtime testing remains paused. Current-source foreground timing is
awaiting the user; no performance gates are inferred from these checks.

### Cross-language verification after integration

The current worktree also passes the documented OCaml build/test/format aliases,
protocol and OCaml fixture generation checks, Swift input fixture consistency,
viewport type-boundary checks, Swift generator test and native C/OCaml runtime
checks. Dune validates its incremental dependency graph; cached up-to-date tests
were not forced to execute again. The runtime check executes six tests, and the
native fixture binary is unchanged from the verified 520-test Swift suite.

`production-cross-language-checks.json` records exact commands, log hashes and
scope. Two initial checks were refused by Dune's concurrent build lock and ran
no checks; their logs are preserved, and sequential reruns pass. No production
implementation changed during this verification. Current-source foreground
measurement still awaits user timing; iPhone runtime testing remains paused.

## Alternatives considered

### Only remove the two full-node sorts

This is a useful isolated repair but does not eliminate geometry preferences,
hidden subtrees, measurement broadcasts or the observed dominant graph/layout
work. It is included within the broader presentation reconciliation step.

### Immediately replace CollectionWindowLayout with List or LazyVStack

A container swap is not selected as the first implementation. Swift currently
receives an OCaml-produced row window; a lazy native container cannot
synchronously instantiate descriptions that have not crossed the bridge.
List also changes card styling, selection, swipe and expansion behavior. A
native container may ultimately be preferable, but the existing evidence does
not compare equivalent real Mail content under those designs.

If the proposed implementation still fails frame pacing and profiling identifies
window refill or custom placement as the remaining limit, compare native List
and LazyVStack with the same active row content. That experiment must explicitly
design native row availability, request prefetch and OCaml-owned state. It must
not ship a blank-placeholder benchmark or a second renderer as a compatibility
fallback. Select and replace the production path based on correctness and
measured results.

### Keep both branches but omit hidden anchors

This reduces only one multiplier. Hidden nodes still cross the bridge, retain
controllers and participate in branch measurement. It preserves the expensive
contract the user permits replacing.

### Cache everything indefinitely or suppress equal measurements globally

Unversioned caches fail after resize, text changes, eviction, key reuse and
session replacement. A global epsilon cannot substitute for callback ownership.
The proposed context and attachment tokens retain correctness while removing
commit-driven broadcasting.

### Make all handlers permanent or stop idle pumping

Permanent closures over changing snapshots violate handler semantics. A general
handler solution or, when application knowledge is necessary, precise dependency
projections must preserve callback freshness. Fully event-driven runtime
scheduling needs timer/service wakeups and is broader than replacing native
retained-tree checks. Neither shortcut is needed for this repair.

## Acceptance criteria

### Correctness and structural outcomes

- Every fix that can be implemented generally lives in bonsai-ui and has a
  reusable framework regression. Each Mail change is justified by application
  semantics or common API migration; no Mail-only workaround substitutes for
  a shared fix.
- Collapsed rows contain only shared/compact active content in both wire frames
  and native trees. Shared row roots retain identity across window overlap.
  Node count stays bounded by window size and active row complexity.
- With no layout requests, no node publishes NodeLayoutAnchors. Requested
  measurements are correct after scroll/resize and never resolve against a
  detached or replaced identity. Requests cannot deadlock presentation.
- Unrelated commits do not advance a generation observed by every measured row.
  Equal size samples cause no geometry publication or scroll command. Multiple
  valid size changes are combined, and stale callbacks are harmless.
- Strict idle refresh does not enumerate decorative nodes. Native mount/focus,
  modal transitions and inactive sessions retain correct input ownership without
  a new OCaml commit. No stale controller survives removal or epoch replacement.
- Painted-range-only changes preserve the handler identity. No-op events emit
  no UI patch; pagination retains keys and generation correctness.
- Mail expansion/collapse, read/star, archive/swipe, navigation, notices, paging,
  resize, large text and rapid reversal work without blank rows, jumps or
  unintended activation. Removed controls cannot receive input or a11y actions.
- Generator/fixture checks, relevant OCaml and Swift regressions, the complete
  Swift test runner, platform compile checks and the native Mail window test
  pass. Use commands in [docs/testing.md](../../../../docs/testing.md), including
  `python3 tool/run_swift_tests.py`, `python3 tool/test_swift_platforms.py` and
  `python3 native/test/test_mail_window.py`. A zero-test report is not acceptance.

### Performance protocol and gates

Follow the [bonsai-ui-benchmark skill](../../../../.agents/skills/bonsai-ui-benchmark/SKILL.md)
and its measurement/budget references. Rebuild an optimized macOS Mail binary
with recorded source, instrumentation and executable identity. Record other
processes and machine contention; establish a controlled baseline instead of
treating the earlier absolute timings as a matched performance comparison.

Warm up for at least five seconds and one traversal. Run three independent
10-second idle, 20-second continuous-scroll and 10-second settled-idle sequences.
Specify speed and distance in logical pixels/rows and verify the delivered path.
Use low-overhead acceptance counters and actual app-specific presentation data;
collect verbose SwiftUI/CPU traces separately.

Required targeted cases are real Mail compact scrolling, a visible expanded
row, rapid direction changes, expanded-row eviction/revisit, paging during
scrolling, resize/large text, and a matched simple-row contrast. Add 100 versus
1,000 static nodes for idle scaling and 1,000 versus 10,000 logical items for
declared/measured collection scaling. Name any omitted skill scenarios; this
targeted repair must not be described as full benchmark-matrix acceptance.

| Metric | Gate in every required run |
| --- | --- |
| Settled payload/revision | Zero input/output bytes and events, no UI operations, revision changes, full snapshots or resyncs. |
| Idle pump/ack | At most 65/s each, no rejection; count native calls separately from bytes. |
| Idle execution | Refresh main-thread execution and native-queue execution each at most 10 ms/s excluding waits. Also report whole-main-thread CPU separately; it is not identical to time inside refresh. |
| Idle node scaling | Flag a repeated increase above 25% that also exceeds 1 ms/s at 10x static nodes; absolute budgets still apply. |
| Virtualized traffic | Requests correspond to meaningful range/handler changes; no painted-only handler churn, unrelated sibling recreation or steady-state snapshots. Derive byte budgets from expected encoded transitions before collection. |
| Logical-count scaling | Bytes per window transition and events per crossed row remain within 25% at 1,000 versus 10,000 items with matched materialized content; exclude and report catalog upload/paging separately. |
| Actual frame pacing | Approximately 60 FPS: mean at least 59, presentation interval p95 at most 18.34 ms, p99 at most 33.34 ms, maximum at most 50 ms during continuous expected motion. |
| Hitches | At most 5 ms/s of motion when supported by a valid instrument. |
| Settling | Within one second after gesture and configured animation completion, return to strict idle gates. |

Record the actual display policy. On 120 Hz, additionally report the 8.33 ms
native refresh budget; a 60 FPS result does not certify 120 FPS. Ack latency,
pump counts and display-link callbacks cannot certify actual FPS. Missing frame
data or an unjustified byte budget remains `UNMEASURED`, never an inferred pass.

Report per-stage output-to-ack p50/p95/max to explain whether the original
165–176 ms median delay has disappeared. Do not invent a stage allocation or
relax the absolute presentation gates to accommodate a slow baseline. Include
memory after repeated traversals and exact materialized row/node counts.

Save raw artifacts and JSON/CSV verdicts for traffic, frame pacing and
correctness. Report all runs, median and worst run. macOS is the performance
acceptance target for this repair; shared Swift implementation and physical iOS
compile checks are included, but physical-device FPS is a separate measurement
and must not be claimed without running it.

## Risks

- Active-content rendering intentionally gives up hidden native subtree retention
  and an exact two-live-branch crossfade. Gallery/workflow consumers may need
  explicit OCaml state for drafts that previously survived invisibly.
- Request-driven layout introduces asynchronous completion where a cache lookup
  used to be immediate. Teardown, timeout and host-request scheduling must be
  tested together with the presentation fence.
- Missing a native mount, focus or lifecycle invalidation can leave stale input
  eligibility after removing polling. Existing real-window interaction tests
  are mandatory, including changes while acknowledgment is pending.
- Batched measurements and one extent animation owner can change timing and
  anchor behavior during rapid toggles or dragging. Correct interaction takes
  precedence over reducing callback counts.
- A major protocol change requires rebuilding OCaml and Swift together and
  updating generated fixtures; mixed versions must fail explicitly. No legacy
  branch or compatibility migration is part of the design.
- Isolated savings and the final frame-rate improvement are unmeasured. If
  acceptance still fails, residual profiling and the bounded container study
  remain required work before claiming the performance problem fixed.

## Questions

None. The user accepted the recommended expansion animation: a stable card with
animated active-content size and surface styling. Exact crossfades between two
complete live subtrees and hidden native-state retention are not required.
Durable state remains in OCaml; removed detail views release native editing,
focus and accessibility ownership. No outgoing-content snapshot mechanism is
required by this decision.
