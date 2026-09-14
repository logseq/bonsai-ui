# Changelog

## Unreleased

- Added abstract `Widget.Keyed.t` evidence for materialized virtual-list items.
  `Sliver.fixed_extent` and `Sliver.varied_extent` now require explicitly keyed
  item roots, while the non-virtualized `Sliver.list` remains unchanged.
- Updated the immutable iPhoneOS SDK source binding to include configurable
  Swipe Action and host clip border radii, and published the refreshed SDK
  meta-package as `0.1.0~dev.3` without changing the native ABI or build recipe.
- Bound the immutable iPhoneOS SDK manifest to the exact Bonsai Flutter source
  revision and archive checksum, advanced its protocol ABI and build recipe to
  revision 2, published the SDK recipe as `0.1.0~dev.2`, and added one
  reproducible command for all repository locks and digests. Target GMP staging
  now stays inside writable package build storage instead of the immutable opam
  switch prefix.
- Added generic declarative modal-bottom-sheet Page presentation with typed
  barrier, focus, safe-area, keyboard-inset, restoration, and motion policies.
  The Flutter renderer uses a real non-opaque Material route, reads live
  same-key `can_pop` updates before Back, Escape, or barrier dismissal, and
  emits one typed RoutePop after an allowed removal. Typed content-bounded,
  scroll-controlled, and `Medium`/`Large` detented sizing supports coordinated
  resize-then-scroll gestures, preflighted drag dismissal, pointer and
  accessibility handle actions, and route-borrowed primary scroll controllers.
  Flutter owns one theme-backed, 24-pixel rounded and clipped outer surface for
  every sizing mode, so OCaml content does not configure sheet geometry.
  Modal presentation now coordinates the sheet, native barrier, and a receding
  transition on the immediately lower route while preserving that route's
  mounted identity. Navigator, modal-route, background-transition, and detented
  interaction responsibilities now live in focused internal renderer modules.
- Disabled Flutter icon tree shaking for every macOS and iOS Profile/Release
  build because Material icon code points arrive through runtime protocol
  frames and cannot be discovered by Flutter's static `IconData` scanner. The
  complete font adds approximately 1.6 MB uncompressed; duplicate or conflicting
  forwarded build flags are normalized deterministically. Run commands retain
  Flutter's icon-safe default without receiving its unsupported build-only flag.
- Added `bonsai-flutter exec --profile=PROFILE -- COMMAND` for Flutter and Xcode
  tests that require a staged macOS native artifact. The command holds the
  Flutter build lock, scopes the generated Native Assets profile to the child
  process, preserves its exit status, and restores the generated manifest after
  success, failure, or an interrupt.
- Routed macOS and iPhoneOS application complete-object builds through managed
  Dune aliases, moved iPhoneOS packages into a commit- and checksum-locked
  immutable global SDK, validated application lock subsets from the reachable
  Dune closure, and made unchanged artifact staging preserve timestamps.
- Replaced multi-entry native ownership with one process-wide logical runtime,
  Driver, and Dart coordinator lease. Added versioned Fresh and explicit
  replacement startup, stale-handle tombstones, and one lazily spawned,
  sequentially reused OCaml Worker Domain with a bounded request FIFO,
  guaranteed responses, coalesced pushes, cancellation, fair computation
  slices, condition-based idle waiting, and exact final-shutdown semantics.
- Added the OCaml-owned SQLite Worker Todo example. Flutter resolves its
  Application Support path and passes it through the startup envelope; the
  Worker Domain exclusively owns the SQLite 5.4.0 connection, migrations,
  statements, transactions, and cleanup. The example displays Flutter-host and
  OCaml-Worker startup-stage timings. Real macOS FFI tests cover CRUD, push
  ordering, suspension, resume, runtime recreation, and persistence, and
  iPhoneOS arm64 artifacts link Apple system SQLite while retaining the exact
  existing `bf_*` export boundary.
- Migrated the host and iPhoneOS build graphs to OCaml 5.1.1 and the Jane
  Street v0.17.x release line, removed bleeding-repository and keyword-mode
  requirements from CI, and regenerated the locked iOS runtime closure.
- Added the OCaml-owned Clock example for exact and approximate time, relative
  sleep, and recurring schedules.
- Rebased queued runtime-control events at presentation handoff so a
  continuously updating Clock cannot atomically lose a valid previous-frame
  button event behind an older environment event.
- Linked iPhoneOS native assets and probes against Security.framework, updated
  the privacy audit for OCaml 5.1's `mach_absolute_time` import, repaired the
  Mail trace event fixture, and made CI run every discovered example test.
- Replaced command-driven wakeups with a foreground-vsync pump. Visible idle
  runtimes advance public Bonsai clock and lifecycle semantics once per
  backpressured eligible Flutter frame; hidden, paused, and detached runtimes
  suspend and catch up after resume.
- Added exact presentation identities for every logical pump, including
  no-diff and recoverable cycles, with one unresolved-token barrier,
  two-phase renderer and event-prefix transactions, guarded post-frame
  success, deterministic rejection recovery, and lifecycle commit only after
  real presentation.
- Advanced the native runtime boundary to exact ABI 2.0 while retaining
  renderer protocol 1.12. Added monotonic pump time, explicit presentation
  success and rejection, stable cross-language error codes, generated binding
  checks, complete-object symbol audits, and exact owned-buffer release.
- Added bounded frame-loop, worker, root, OCaml clock/lifecycle, native bridge,
  and real-FFI autonomous-pump coverage. No upstream source, dependency
  revision, private time-source API, forced frame, or background timer is
  required.
- Established the OCaml-first architecture, native renderer boundary, binary
  protocol, lifecycle, reconciliation, and text-input decisions.
- Recorded the initial upstream toolchain baseline.
- Added abstract keys, typed immutable logical widgets, and typed Flex/Stack
  parent data.
- Added the mounted tree, monotonic node and handler IDs, expected-linear keyed
  reconciliation, full and incremental logical frame patches, atomic snapshot
  replay validation, and revision-scoped handler dispatch.
- Added headless tests for incremental updates, keyed identity, duplicate
  keys, stale handlers, 10,000 keyed siblings, and randomized patch
  application invariants.
- Bootstrapped Flutter 3.44.8 `package` and `package_ffi` packages.
- Added the typed Dart in-memory frame model and atomic copy-on-write
  `NodeStore`, with rollback, graph validation, node subscriptions, dirty node
  reporting, and pure Dart tests.
- Added a validated OCaml schema generator that emits stable OCaml and Dart
  protocol constants, debug names, and readable ID tables with a clean-tree
  check.
- Added bounded little-endian OCaml and Dart frame codecs for the first typed
  Empty/Text/Row/Column/Button protocol slice, including strict UTF-8,
  malformed-input classification, a shared Counter golden fixture, and
  decoder-to-`NodeStore` integration tests.
- Replaced the generated native `sum` example with the fixed-width
  `bf_runtime_*` C ABI, tracked native output ownership, private generated FFI
  bindings, and an idempotent Dart runtime wrapper.
- Added a dedicated Dart runtime isolate that serializes native calls, uses
  `TransferableTypedData`, sequences responses, and acknowledges shutdown.
  The unavailable OCaml backend is reported as a fatal status rather than
  being simulated.
- Added the typed Flutter `WidgetRegistry`, keyed per-node `NodeHost`, and
  Empty/Text/Row/Column/Button factories. Widget tests verify Counter fixture
  rendering, root replacement, subtree-local text rebuilds, stable ancestor
  elements, and typed Button event dispatch.
- Diagnosed the host widget-test failure as missing localhost proxy exclusion;
  the suite passes with a local `NO_PROXY` setting.
- Added the versioned inbound event-batch format, a shared Counter press
  fixture, typed Dart encoding, bounded OCaml decoding, and runtime-isolate
  transfer.
- Added a bounded renderer event queue with monotonic sequences,
  displayed-revision capture, non-coalescible ordered input, explicit
  backpressure, and typed Scroll/VisibleRange coalescing.
- Added typed OCaml inbound-event conversion and batch dispatch through the
  revision-scoped handler registry. The shared Flutter Counter press fixture
  now invokes its intended OCaml handler in a headless cross-language test.
- Added a spec-first `Bonsai_runtime_adapter` over the real `Bonsai_driver`
  API. Its mandatory test verifies state effects,
  flush/result sequencing, presentation-gated lifecycle execution, and
  idempotent shutdown without exposing `Bonsai.Private` from the public
  interface.
- Added the OCaml `Driver` vertical slice: effect-only handler
  queuing, atomic batch validation, one Bonsai flush, reconciliation, binary
  encoding, presentation-ordered lifecycle work, and explicit handler
  retirement. Its Counter test proves a press produces only the expected text
  property update and rejected batches leak no effects.
- Selected OCaml 5.3.0 as the newest stable compiler supported by the locked
  Bonsai dependency graph, removed the alternate compiler build gates, and
  made every Bonsai driver library and test part of the default build.
- Isolated the selected `basement` revision's two macOS portability fixes in
  `vendor/patches`.
- Added Linux OCaml and Flutter CI plus macOS arm64 native integration CI,
  exposed the same boundaries through `make ci-*` and `just ci-*`, and pinned
  the upstream Jane Street opam repository revisions used by the OCaml 5.3.0
  dependency graph.
- Aligned the native fallback and integration package protocol reports with
  the generated protocol version.
- Wired the built-in focus and scroll host effects to the same node-scoped
  renderer resources used by `TextInput`, `ScrollView`, and `ListView`, with
  post-frame attachment, normalized scroll alignment, and lifecycle tests.
- Added protocol 1.12 semantic opacity animation: typed OCaml animation intent,
  a dedicated backward-compatible node kind, Flutter-local node-scoped
  `AnimationController` interpolation, revision-scoped completion events,
  reduced-motion behavior, and resource disposal coverage.
- Split cross-language golden data by producer: OCaml now generates typed
  output-frame fixtures consumed by Dart, while Dart generates typed input
  event-batch fixtures consumed by OCaml. Added Unicode, reorder, host,
  environment, epoch/revision, and animated-opacity coverage plus deterministic
  `make protocol-fixtures-{generate,check}` commands enforced by CI.
- Added a process-wide native application registry and named OCaml callbacks
  for create, logical pumping, presentation, and destroy. The C bridge retains only
  integer handles, registers foreign threads, holds the OCaml runtime lock only
  during callbacks, and copies all results into C-owned memory.
- Added an opt-in Dune complete object containing the linked Counter,
  `Bonsai_driver`, OCaml runtime, native backend, C bridge, and public `bf_*`
  symbols. The package build hook consumes it through a standard user define
  while preserving the default truthful fallback.
- Added a macOS arm64 Flutter integration workspace. Its widget test renders
  the real OCaml full snapshot, clicks the Flutter button, crosses the Dart
  runtime isolate and FFI, applies exactly one `Count: 1` incremental patch,
  preserves unaffected Element identity, acknowledges presentation, and
  destroys the runtime.
- Advanced the generated protocol to version 1.1 with fixed property IDs for
  Padding, Center, ScrollView, Button, Semantics, Theme, and MaterialCheckbox,
  plus the typed `ValueChanged` event.
- Added typed OCaml layout, color, theme, semantics, scroll, padding, center,
  and Material checkbox APIs. Reconciliation preserves the mounted subtree and
  emits only changed property operations for compatible updates.
- Added matching Dart frame values, strict little-endian codecs, transactional
  validation, and mechanical Flutter factories for Padding, Center,
  SingleChildScrollView, Semantics, Theme, and Checkbox.
- Added `BonsaiFlutterRoot` to own runtime startup, event-batch draining,
  atomic frame application, presentation acknowledgment, fatal-state
  rendering, and runtime disposal without application logic in Dart.
- Added the OCaml-owned Phase 4 Gallery and a minimal Flutter shell. Its native
  integration test verifies layout, dark theme, accessibility semantics,
  scrolling, Button and Checkbox rendering, and a checkbox round trip through
  Bonsai and FFI with no node remounts.
- Advanced the protocol to version 1.2 with the complete typed TextInput
  property layout and UTF-16-indexed TextEdit event payload.
- Added OCaml `Text_editing` values with safe UTF-8/UTF-16 boundary
  conversion, validated selection and composing ranges, revisioned update
  modes, keyboard types, and input actions.
- Added `TextInputHost` with optimistic local echo, exact-revision
  corrections, acknowledgment without controller writeback, stale correction
  rejection, force replacement, typed focus/submit/edit events, and composing
  protection.
- Added `RendererResourceStore` for node-scoped TextEditingController and
  FocusNode lifecycles. Tests prove keyed reorder retention and disposal on
  node drop, full snapshot replacement, and renderer shutdown.
- Added the OCaml-owned Text Input example and real FFI integration coverage
  for two rapid Chinese/emoji composing edits. Bonsai accepts both in one
  flush and returns one acknowledgment frame without disturbing the live
  controller or composing range.
- Advanced the protocol to version 1.3 with typed HostRequest,
  CancelHostRequest, HostResponse, EnvironmentChanged, RoutePop, Navigator,
  Page, Overlay, and MaterialDialog layouts.
- Added typed OCaml host effects for clipboard, URL, file operations, focus,
  scrolling, window controls, native menus, haptics, platform information,
  and layout measurement. Request IDs are monotonic; error, cancellation, and
  shutdown all release the pending continuation.
- Added an injectable Dart `HostEffectImplementation` and dispatcher outside
  the renderer patch transaction. Headless tests cover success, failure,
  cancellation, duplicate request protection, and pending-work disposal.
- Added a change-filtered Flutter Environment reporter and an OCaml
  `Environment` Bonsai dynamic input for viewport, scale, brightness,
  platform, locale, insets, accessibility, orientation, and pointer support.
- Added OCaml-owned declarative Navigator/Page stacks, typed system-pop
  events, Flutter-local route transitions, Overlay, and MaterialDialog hosts.
- Added the Host Effects and Navigation example plus a real FFI test that
  completes a clipboard request, updates Bonsai state, opens an OCaml-owned
  Settings route with overlay and dialog content, and processes a system pop.
- Advanced the protocol to version 1.4 with a versioned NativeWidget envelope,
  capability declarations, opaque typed properties, and typed native events.
- Added typed OCaml extension registration, native Bonsai effect handlers, a
  Dart `NativeWidgetRegistry`, version and capability negotiation, accessible
  unsupported-widget fallback, and application-shell factory registration.
- Extended `RendererResourceStore` with typed native resources retained by
  compatible node identity and disposed on version replacement, node drop,
  full reset, epoch change, and renderer shutdown.
- Added a fixed-extent VirtualList extension. Its 50,000-item test mounts only
  a 20-row window, emits visible ranges, and retains keyed row identity while
  advancing the window.
- Extended the Gallery with an OCaml-owned custom native card. The real FFI
  integration test registers its Dart factory, retains a FocusNode resource,
  sends a typed native event, and applies only the OCaml property update.
- Fixed Flutter input races across frame commits by attaching each renderer
  event to the revision that created its callback and retaining one preceding
  OCaml handler frame. Recoverable stale events no longer replace the
  application UI, and regression tests cover edits emitted between
  `NodeStore` commit and `TextInputHost` rebuild.
- Fixed the Gallery ListTile press handler so it toggles the OCaml-owned
  selection state, with real FFI coverage in both directions.
- Normalized transient Flutter text selections before protocol encoding so
  invalid, reversed, or surrogate-splitting ranges cannot crash Unicode text
  input on focus.
