# Journal native public UI implementation evidence

Implementation on framework base d1c97bd, macOS 26.6.2 (25G83), Xcode 26.1.1
(17B100). All seven production capability areas are implemented. Physical iPhone 13
acceptance on iOS 26.7 (23H24) passed all 12 new-API UI tests, plus two Mail runtime
and two Mail UI tests. No commit has been created. The final acceptance section
below supersedes historical checkpoint status; failed attempts remain recorded.

## Implemented

- iOS 26 minimum throughout active framework configuration, CLI validation,
  generated example hosts, compiler settings, and current user guidance.
- Required Native_list.style: Plain, Inset, Inset_grouped. macOS rejects
  Inset_grouped before publishing the tree, with an explicit capability diagnostic.
- View.Navigation_link.create: stable key, byte-exact activation identity, enabled
  state, ordinary label, and OCaml Handler. The native control has one bounded
  pending intent per stack, exact event settlement, unchanged-route release,
  replacement/disposal fencing, and presentation-triggered retry without polling.
- Protocol major 10 and updated generated constants, C ABI declaration, codecs,
  and opposite-language fixtures.
- Native grouped Form, reusable Section, LabeledContent, ContentUnavailableView,
  and native text selection. Form requires keyed children and produces a typed
  vertical viewport. Public documentation and Gallery demonstrate diagnostic
  values and ordinary OCaml actions. Fresh wire nodes are 140–144; retired 136
  remains rejected.

- Flat List scroll requests: monotonic tokens, scoped byte-exact target keys,
  native lazy-cell realization, stable observed completion, bounded readiness and
  movement, cancellation, and original callback retention across arbitrary handler
  rebindings. Source-owner disposal and terminal consumption revoke even a
  previously validated callback batch. No whole historical frame is retained.
  Hierarchical target registration now includes collapsed descendants.

- Hierarchical Native_list.disclosure_row with controlled expansion, independent
  label/swipe/context slots, sibling-scoped keys, depth-first visible indices,
  collapsed input/accessibility fencing, label/expansion arbitration, and native
  parent-label/descendant scrolling. Reparenting revokes the previous incarnation.
- Context_menu keyed actions and ordinary view attachment. Every native menu
  configuration captures owner/action/handler/presentation identities. macOS uses
  NSHostingMenu with SwiftUI buttons and labels; iOS uses UIContextMenuInteraction
  and UIMenu. The original content stays in its SwiftUI tree, with noninteractive
  window-scoped bounds anchors. Rebinding while a native menu is tracking cannot
  retarget the selection. Hidden-and-revealed swipe callbacks are also revoked.

The public APIs cover the seven standard UI portions identified in the decision.
The consumer has not been migrated. Application-specific reading-density, feedback,
unlock, sync-feedback and title layouts still require their own audit; graph state,
pagination, expansion, route acceptance and revisioned editor ownership stay in OCaml.

## Historical verification checkpoints

Full-suite runs began after every capability was implemented, following the
user's updated testing instruction. Only affected tests ran at intermediate
checkpoints; earlier full-suite evidence below predates that instruction.

- RED evidence: old iOS deployment acceptance, unsupported List style decoding,
  missing core intent handling, missing presentation-readiness notification,
  orphan link acceptance, and canonical-Unicode activation confusion.
- `make test protocol-check protocol-fixtures-check`: passed.
- Focused Swift tests: 24 tests across six suites passed, covering core navigation,
  existing navigation ownership, List styles, native List rendering, and real Mail
  pagination. Earlier List/swipe/system run: 14 tests passed.
- iOS Swift module and all example entrypoints typechecked at iOS 26; three platform
  checks passed. This is compilation evidence, not an iOS interaction result.
- Native C/OCaml prerequisite: seven tests passed.
- Forms checkpoint: 29 focused tests across seven suites pass with completed-report
  verification, including five new forms tests. `Group(sections:)` sees two native sections with two and one content rows
  through the actual erased renderer. Hosted native geometry matches a direct
  SwiftUI reference within one point; both contain one scroll container. Real
  OCaml action delivery updates a selected diagnostic value, reorders keyed rows,
  and disables the original action without remounting it. The native comparison
  uses the same leaf typography to isolate structural differences.
- Forms checkpoint: `make test protocol-check protocol-fixtures-check`, seven
  native bridge tests, and three iOS 26 platform/typecheck tests passed. The compile
  fixture rejects inserting an unsized Form directly into another Scroll.
- Scroll checkpoint: 30 affected Swift tests across eight suites passed with a
  completed report. Additional hosted Plain and Inset cases pass with variable
  40/70-point and 500-point rows, all three anchors, first/last boundary clamping,
  an initially unrealized offscreen target, retained NSScrollView identity, and
  animation cancellation that remains at the interrupted offset for 400 ms.
  The real OCaml fixture completes through its originating callback after three
  handler rebindings. Focused OCaml API/event-dispatch tests and protocol fixture
  checks pass. RED logs establish missing lifecycle/adapter behavior, predating
  revision acceptance, and callback replay after disposal/consumption. The final iOS 26
  module/example typecheck passes, including the UIKit cancellation path. Full
  test runs are deferred.
- Hierarchy/context checkpoint: 44 affected Swift tests passed in seven completed-
  report-verified invocations (`journal-context-isolated-summary.log`). Coverage
  includes real native menu opening, ordinary action selection, duplicate selection,
  replacement during native tracking, same-configuration reopening, parent/child
  menus on actual List labels, collapsed/reparented owners, actual disclosure
  arrow and accessibility label activation, hidden and offscreen scroll targets,
  native parent-label alignment, existing List/swipe controls, and core links.
  The public OCaml surface, protocol tests, Mail example tests, generated schema
  and opposite-language fixture checks pass. The final iOS 26 module and example
  entrypoint typecheck passes; it does not establish iOS interaction behavior.
  An affected combined run still exits during a native runtime scenario after
  inline menu tracking without a completed report; that invocation is recorded as
  failed (`journal-context-swipe-focused.log`). Each final reported group has its
  own independently verified complete report, including both native menu cases.
- Generated host configuration: four tests passed.
- Rebuilt isolated iOS compiler/runtime: four real artifact checks passed.
- Device preflight tooling: eight tests passed.
- SDK generation tooling: four tests passed using isolated test repositories.
- Full iOS dependency-closure audit failed: local cross switch lacks the
  datascript_ocaml virtual interface artifact. No complete iOS App cross-build is
  claimed. Published SDK snapshots still refer to their earlier source commit;
  they have not been regenerated or published from this uncommitted work.
- Physical iPhone 13 was unavailable. Interactive Back, Reduce Motion, VoiceOver,
  and iPhone rendering are unverified. Historical evidence elsewhere was not
  relabeled as new passes.
- Initial full Swift runs exited with status zero during MenuTests without a
  completed Swift Testing report; these are failures, not passes. Isolated Menu
  tests reproduced it. An exit-stack probe showed async-main executor termination
  after inline native menu tracking. Scheduling the menu click on the main queue
  while the test suspends allowed isolated tests to finish, but did not fix the
  full-suite exit. That experiment was reverted; Menu production and test source
  remain unchanged. The original d1c97bd sources reproduce the same exit when
  running only the retained-menu test and its following queue test. The baseline
  build links the existing fixture dylib, but these two selected tests do not
  start an OCaml runtime. A verified suite run excluding only
  `retainedMenuRendersAfterAValidLabelReduction` reached the later native runtime
  tests, including the new form, complete Gallery and core navigation tests, then
  exited during `shutdownActualNativeWindow`'s inactive case without a completed
  report. This later exit is not yet diagnosed. Unqualified full-suite completion
  is not claimed; the 29-test focused run completed and passed independently.

## Native investigation

The standalone List probe realized an initially unmounted offscreen row using
ScrollViewReader. Native NSScrollView coordinates observed top/center/bottom,
clamping, a large row, and repeated targets. SwiftUI named coordinates included a
32pt Section-header displacement; uncorrected named coordinates are unsuitable
for completion. The retained probe is exploratory, not the production controller.

The first activation probe used the existing registered-view fixture to isolate
the shared admission gap and identical handler binding. The new core-constructor
regression subsequently reproduced the gap through real OCaml event pumping and
a hosted SwiftUI NavigationLink, and verified activation after native Back.

The first toolbar prototype does not compile: ForEach's content requires View,
whereas ToolbarItemGroup conforms to ToolbarContent. A later standalone prototype
uses the public ToolbarContentBuilder erasure API and successfully renders dynamic
groups. Native NSToolbar item identifiers change on reordering; actual child view
and focus retention remain unproven. This is exploration, not production code or
iOS grouping evidence.

Two further probes place a native ControlGroup inside a ToolbarItem with an
explicit group ID, both with ordinary and customizable toolbar composition.
AppKit reports distinct NSToolbarItemGroup objects and the group IDs survive
reordering. However, one NSTextField object is replaced and its accepted editor
focus is lost. Stable group IDs alone do not establish native child retention.
Both probes remain exploratory; neither implementation has been adopted.

The Section erasure probe showed that the existing NativeNodeView boundary
preserves SwiftUI Section structure. Production Form therefore uses its ordinary
child renderer without a special Section bypass. `Group(sections:)` verifies the
structural result, rather than inferring it from decoded node kinds.

A hierarchical List probe places type-erased DisclosureGroups inside native
sections. AppKit reports 26 independent native rows (one header, five parents,
and twenty children). IDs attached to parent labels and individual children
scroll to their respective row rectangles rather than the expanded subtree.
The run emitted an AppKit reentrant delegate warning; production hosted tests
must revisit this. The probe does not yet establish action isolation or context
menu presentation lifetime.

## Historical remaining work after the List checkpoint

Implement context menus and explicit row actions; hierarchical rows and visibility indexing; keyed toolbar
groups/spacers; and controlled Alert/ConfirmationDialog. Verify native text-selection
gestures on a device. Add the remaining production behavior tests,
fixtures, examples, and native evidence, then complete the final verification.
No protected spec, Dune, consumer, or bonsai_flutter source has been changed.

## Hierarchy and menu presentation investigation

A direct SwiftUI List/DisclosureGroup probe reproduces a parent label Button
activation also requesting expansion for automatic, plain, borderless and bordered
button styles. Wrapping the label does not separate those native callbacks. The
production row owner arbitrates one callback turn and preserves OCaml expansion
authority. A rejected expansion cannot expose child accessibility before its OCaml
acknowledgment. A rejected or repeated core NavigationLink activation also consumes
the label interaction without falling through to expansion.

`journal-context-lifecycle-probe.log` reproduces the native context-menu lifetime
problem: SwiftUI's menu-content appearance persists across openings, its builder
is cached, and a handler rebind during NSMenu tracking can rebuild the native
selection callback. A one-shot render-time capture both retargeted an open menu
and prevented fresh unchanged openings. That implementation is removed. The native
configuration adapters create independent immutable menus at each real opening;
`journal-context-native-verified.log` proves both behaviors after the correction.
There is no compatibility renderer or application-specific registration path.

Remaining implementation scope: ordered keyed toolbar groups, native spacers,
Bottom_bar validation, focused native child retention, and tokenized Alert /
ConfirmationDialog ownership. The final full suite remains deferred until these
capabilities are implemented. The physical iPhone is still unavailable.

## Toolbar implementation checkpoint (historical whole-content host prototype)

The public API and wire grammar now represent independent keyed Items, Groups of
keyed children, native Fixed/Flexible ToolbarSpacers and Bottom_bar. Structural
scope and platform validation run before publication; raw cross-group node reuse
is rejected. The obsolete placement-array grammar is removed.

The first dynamic spacer probe crashed inside SwiftUI because erasure changed its
underlying type at an existing recursion level. A uniform ToolbarContent body
with conditional branches fixes this. Each native group uses an explicit item ID
and content identity. Retained content hosts belong to logical item/child slots;
SwiftUI still owns ToolbarItem, ControlGroup and ToolbarSpacer presentation.

Hosted production tests cover the body and both toolbar text fields, two children
within a group, entry and child reorder, placement changes, spacer removal and
insertion, local draft/selection, and active Chinese marked text. They assert the
same NSTextField and field editor remain inside actual native toolbar items.
The bounded focus transfer does not emit transient focus/unmark events. A later
OCaml force-replacement keeps its new text and selection; a user changing focus
during reorder retains the new focus owner. Initial focus/IME/content-selection
failures and completed green reports are retained alongside this report.

Copying the outer representable's entire accessibilityEnabled environment value
froze nested hosting roots before accessibility materialized. Hosting roots now
keep their own value while forwarding other environment values. Native group
controls are traversed through AXToolbar; top-level NSToolbarItem.view alone
misses group children. This scoped test update preserves existing system Back
lookup rather than changing unrelated native navigation behavior.

Verification at this checkpoint:

- 14 affected Swift tests across five suites completed successfully, including
  actual OCaml toolbar command ownership and native AX Button/Toggle activation.
- The focused identity test has six parameter cases (body/first/second field,
  each with and without marked text).
- The standalone Gallery Toolbar and native system Back window checks both pass.
- OCaml public surface and protocol codec executables pass.
- Protocol generation and opposite-language fixture checks pass.
- iOS 26 framework module and example-entrypoint typecheck passes. This does not
  establish device grouping, overflow, input, VoiceOver or preview behavior.

Toolbar acceptance remains open for explicit lease cancellation/expiry cases,
multiline/secure editor moves, native menu lifetime, overflow, and real OCaml
cross-group callback replacement. Controlled Alert/ConfirmationDialog are not
implemented yet. Full-suite testing remains deferred until all capabilities are
implemented. No commit, push, SDK publication, consumer edit, protected spec edit,
or Dune edit was performed.

## Toolbar native attachment and overflow checkpoint

The whole-content hosting prototype above has been removed. A cold narrow window
revealed that its hidden representables never mounted, leaving the system's native
overflow menu empty. Toolbar controls now remain direct SwiftUI content. Plain and
secure field controllers and multiline editor controllers retain only their
actual native input view (plus the AppKit editor's scroll view). New representable
mounts attach that input after joining a window; mount serials prevent an older
still-live mount from taking it back. No nested NSHostingView/UIHostingConfiguration
or special hosting-root accessibility environment override remains.

The identity test now covers twelve scenarios, including secure fields and
multiline editors, and six cancellation cases cover disabled, hidden, rebound,
new-session, expired and disposed owners. The related ordinary field, multiline
editor, autofocus, native ancestor and expandable-composer tests also pass. An
actual OCaml reparent demonstration moves one keyed action between two persistent
groups; both previous native action owners remain rejected after moving back.

A separate native overflow regression exposed a second issue: forcing Menu's
macOS borderlessButton style removed its submenu from the toolbar's native menu
representation. Menu now uses SwiftUI's automatic native style. A cold narrow
window exposes and dispatches Button, Toggle and Menu actions to OCaml, including
disabled menu entries and rejection of a retained action after group reparenting.
Opening the overflow twice via AXPress in one hosted XCTest window remains a
harness investigation; it is not counted as verified reopening behavior.

The retained Menu test uses the standalone SwiftUI App harness because opening
its NSPopUpButton in the XCTest process exits before Swift Testing emits a complete
report. The first standalone version verifies real native opening, disabled items,
command dispatch, retained callbacks across reorder, and old callback rejection
after removal/reintroduction. The automatic-style version is verified separately.

Controlled Alert/ConfirmationDialog and final platform acceptance remain open.
Full-suite verification remains deferred. No consumer, protected spec or Dune file
was changed; no commit or push was performed.

## Controlled confirmation implementation checkpoint

`View.Confirmation` now exposes native Alert and ConfirmationDialog over one
stable base child. Node 152 carries text title/message and keyed semantic actions;
event 60 carries one typed token-scoped Action or Dismissed response. Fresh tokens
strictly increase within a retained presenter. The controller keeps bounded token
history, immutable opening/handler snapshots, one callback-turn dismissal
arbitration, exact pending-response settlement and consumed-response fencing.
Session integration blocks background input and restores OCaml-requested native
presentation even when its response produces no output diff. Gallery and the
actual runtime fixture share the same public OCaml example.

Seven controller/wire tests and an actual-runtime test (accept/ignore cases) pass.
The hosted native UI test passes four Alert/Dialog × accept/ignore scenarios,
including real native destructive/disabled buttons and stable base identity.
An ignored response restores a visible native confirmation with consumed actions
disabled. AXPress's Boolean return is not used as click proof; the assertions
verify the resulting OCaml state and native presentation.

Public surface, protocol codec and opposite-language fixtures pass. The iOS 26
framework and every example Swift entrypoint compile. Device presentation and
VoiceOver are not established by these checks. All seven requested capabilities
now have production implementations; final full-suite validation starts only now,
following the user's requested testing cadence.

## Initial final-regression and physical-device checkpoint

The iPhone 13 became available on iOS 26.7 (23H24). The user unlocked it and then
enabled UI Automation after Xcode reported an automation-mode timeout. Hardware
preflight passed. The initial UI-runner timeout is preserved as a failed attempt;
its two application-hosted tests passed, and the separate UI retry completed.

- `make test` completed, including viewport type checks. The C runtime's seven
  tests and protocol-generation checks passed.
- The first final Xcode-host run rejected four old iOS 18 complete-object inputs.
  Current Mail, Counter, SQLite Worker, and Gallery sources were cross-compiled
  with the iOS 26 compiler. Mach-O and complete-object/ABI checks passed. The
  three affected host-test methods subsequently passed, including the individual
  platform/linkage cases. This is source-worktree evidence, not a published SDK.
- The complete Swift Testing process exited early after starting
  `ControlSizeTests.sizesMatchNativeControlsAndNestedScopesOverrideTheParent`.
  The completion wrapper rejected the incomplete xUnit report. This run is not
  a full-suite pass; isolated follow-up verification remains pending.
- Physical Mail runtime: startup, presentation, acknowledgment, shutdown/restart,
  and Dynamic Type row remeasurement passed (two named tests).
- Physical Mail UI: inbox expansion/collapse, attachment detail, and swipe Archive
  passed (two named tests, zero failures). Original screenshots were inspected
  and are retained in `physical-ios26/`.
- The shared OCaml native fixture was cross-compiled independently for iOS using
  current worktree libraries, without changing Dune files or copying host native
  objects. `tool/build_native_ios_fixture.py` makes that build reproducible;
  `native/test/ios/` owns the application and UI tests.
- Initial physical new-API run: same-target fresh-token List positioning, core
  link unchanged-route settlement and Back/reopen, outline hidden/revealed
  targets, native Form action, and ignored-confirmation restoration passed.
  A subsequent toolbar test passed through the actual system overflow menu after
  reordering, disabling/enabling, and reparenting its action.
- Remaining physical investigations at this checkpoint: dialog outside dismissal,
  List-contained navigation followed by interactive Back and bottom-bar Capture,
  and parent context/child swipe gesture isolation. First attempts and their
  `.xcresult` bundles remain under `_build/ios/journal-device/`; none is counted
  as passing until its named test completes.

The old repository-local dependency audit's missing-interface diagnostic was
caused by a directory symlink that its `find` invocation did not traverse. That
historical diagnostic does not prove a missing Datascript interface. The old
local host switch also has stale links to a removed host installation. Current
application builds explicitly selected the installed host dependencies, the
locally rebuilt iOS 26 compiler/standard library, and current worktree framework
libraries. A fresh audit/rebuild of the entire target dependency closure remains
separate from the passing application complete-object checks.

## Final physical acceptance

All 12 tests in `native/test/ios/apple-ui-tests/ios/JournalNativeUITests.swift`
passed together with zero failures (189.7 seconds). The result bundle is
`_build/ios/journal-device/native-final-12.xcresult`; the retained summary and log
are [device summary](journal-final-device-summary-12.json) and
[complete device log](journal-ios26-native-final-12.log). The host renders the
actual cross-compiled OCaml fixture through `BonsaiApplicationView`.

| Physical scenario | Observed result |
| --- | --- |
| Flat native List | Offscreen row positioning and repeated same-target requests with fresh tokens succeed. |
| Core NavigationLink | Unchanged-route activation settles; a later activation pushes; Back and another activation work. |
| Hierarchical List | Hidden descendants report hidden; revealing them permits positioning; parent context and child swipe actions reach their own OCaml handlers. |
| One row with link, context and swipe | Menu and swipe dispatch independently; neither opens the destination; normal tap and Back still work. |
| Native toolbar | Distinct bottom groups and flexible space; Capture and page commands work after interactive Back. Reorder, disable/enable and reparent work through native overflow. |
| Native List retention | Interactive Back retains the original List and offset without any restoration request; an ordinary programmatic push/pop control also passes. |
| Context menu in Sheet | The menu opens on the presented controller's surface, reaches the OCaml handler, and closes the Sheet correctly. |
| Native Form | The ordinary unavailable-state action updates the OCaml diagnostic value. |
| Alert and ConfirmationDialog | Destructive action, explicit Cancel, outside dismissal with Cancel, and outside dismissal without Cancel produce exactly one correct response. Background input remains blocked. |
| Ignored confirmation response | The requested presentation returns with consumed actions disabled; no duplicate response is emitted. |

Physical RED tests exposed two production issues. First, SwiftUI's default value-
link activation recreated the underlying native List even when the provisional
route was rejected. Core links now enter captured controlled intent from touch,
accessibility default activation and keyboard activation before native path
mutation. Only the OCaml-accepted path navigates. A diagnostic run observed the
same native collection-view address and owner before and after Back, at the same
629.666-point offset. Temporary tracing and attempted identity wrappers were removed.

Second, using UIWindow as a targeted context preview animated the application
window, and attaching the interaction to the window cancelled menu presentation.
The final implementation attaches each interaction to its anchor's containing
view-controller surface, including Sheet controllers. It snapshots only the
label rectangle for the immutable preview. Original content and its controls
remain in their SwiftUI tree. The Sheet case failed before this correction and
passes in the final 12-test run.

The dialog result matches the native surface: outside dismissal invokes a supplied
Cancel action; without a Cancel action it returns `Dismissed`. The fixture now
exercises both cases. The test handles the observed iOS wireless-permission alert
and explicitly reopens the interrupted menu instead of reusing a stale action.

Original screenshots, capture metadata and source hashes are retained in
[physical-ios26](physical-ios26/). In particular:

- [Bottom toolbar groups](physical-ios26/native-bottom-toolbar-groups.png)
- [List and toolbar after interactive Back](physical-ios26/native-bottom-toolbar-after-back.png)
- [Context menu in a Sheet](physical-ios26/native-sheet-context-menu.png)
- [Navigation row context menu](physical-ios26/native-link-context-menu.png)
- [Navigation row swipe action](physical-ios26/native-link-swipe.png)
- [Capture manifest](physical-ios26/native-final-captures.json)
- [Verified source hashes](physical-ios26/native-final-source-sha256.json)

## Public replacement map

| Consumer's standard bridge portion | Public framework surface | Guide |
| --- | --- | --- |
| JournalList / JournalFavorites styles, row targeting, visibility | Required `Native_list.style`, scoped `scroll_request`, typed terminal results and row-only visibility | [Native List](../../swiftui-native-list.md) |
| Full-width native opening control | `Navigation_link.create`, stable activation identity and ordinary OCaml handler | [Navigation](../../swiftui-navigation-stack.md) |
| JournalOutline hierarchy and row actions | `Native_list.disclosure_row`, explicit label/swipe/context slots, scoped ancestry targets | [Native List](../../swiftui-native-list.md) |
| Ordinary and row context actions | `Context_menu.action`, `create`, `attach`; immutable native opening snapshots | [Context menus](../../swiftui-context-menu.md) |
| JournalChrome groups and Capture space | Keyed `Toolbar.item`, `group`, `child`, `spacer`, and iOS `Bottom_bar` | [Toolbar](../../swiftui-toolbar.md) |
| Standard JournalForms content | `Form.vertical`, `Section.create`, `labeled_content`, `content_unavailable`, `text_selection` | [Forms](../../swiftui-form.md) |
| JournalConfirmation | Token-scoped `Confirmation.alert` / `dialog` with one `Action key` or `Dismissed` response | [Confirmations](../../swiftui-confirmation.md) |

The platform and wire changes are intentionally breaking: iOS 26 minimum,
macOS 26 minimum, protocol major 10, required explicit List style, explicit row
slots and ordered toolbar entries. Unsupported macOS inset-grouped List and
bottom-bar requests fail before tree publication. There are no old wire decoders,
compatibility constructors, fallback renderers or consumer migrations.

## Final regression results

The complete Makefile test sequence was attempted only after all seven areas were
implemented. Its aggregate run is not green. Follow-up isolation preserves test
assertions and requires a completed Swift Testing xUnit report; a zero process
exit without that report remains a failure. Native UI execution was serialized;
independent window compilation ran concurrently.

| Verification layer | Final result and evidence |
| --- | --- |
| OCaml, viewport contracts and wire compatibility | `make test`, protocol generation/check and opposite-language fixtures pass. [Protocol log](journal-final-ocaml-protocol-3.log), [final OCaml run](journal-final-ocaml-after-device-fixtures.log). |
| Native C/OCaml bridge | Seven tests pass. [Log](journal-final-native-runtime-3.log). |
| iOS 26 platform and example compilation | Three platform tests pass, including framework and example typechecks and explicit unsupported-target rejection. [Log](journal-final-swift-platforms.log). |
| Generated Xcode hosts | The three affected methods pass after rebuilding their old iOS 18 object inputs at iOS 26; the initial full host run's other methods passed. [Retry log](journal-final-host-tests-retry.log). |
| Swift full inventory, isolated by suite/runtime declaration | 324 invocations: 322 pass, two fail. These are invocation counts, not unique test counts; parameterized cases and overlapping suite filters are retained. [Results](journal-final-isolated-swift-results.json), [run log](journal-final-isolated-swift-matrix.log). |
| All Makefile native-window scripts | Initial matrix: 27/30 pass. Mail and Gesture fixture corrections both pass on retry, making 29/30 scripts pass; Navigation has five passing methods and the baseline AppBars failure. [Initial results](journal-final-native-window-results.json), [Mail retry](journal-final-mail-window-retry.log), [Gesture retry](journal-final-gesture-window-retry.log). |
| Physical Mail | Two runtime and two UI tests pass, including restart, Dynamic Type, expand/collapse, detail and Archive. |
| Physical new public APIs | All 12 UI tests pass together with zero failures; see the physical acceptance section above. |

The remaining failures were reproduced on the original `d1c97bd` source:

- **MenuTests process completion:** the combined native-menu group exits without
  the required completed report. All four individual Menu declarations pass in
  independent invocations, including retained native rendering. The earlier
  original-source reproduction does not start the OCaml runtime. [Combined failed
  log](journal-final-MenuTests.log), [four individual results](journal-final-menu-individual-results.json).
- **Sidebar modal reopening:** the single actual-runtime test fails after native
  modal dismissal, with six identical assertions in both current sources and a
  fresh full HEAD archive with its own matching OCaml runtime dylib. No test or
  production behavior was changed to hide this. [Current retry](journal-final-sidebar-current-retry.log),
  [original HEAD](journal-final-sidebar-baseline.log).
- **AppBars bottom resize:** the standalone native window loses 52 points from
  its expected ScrollView offset (400 to 348). The original HEAD archive with its
  matching runtime reproduces the same failure. This existing ScrollView resize
  case is separate from native List retention after Back, which passes on the
  iPhone without restoration. [Current diagnostic](journal-final-app-bars-window-retry.log),
  [original HEAD](journal-final-app-bars-baseline.log).

The earlier aggregate shutdown-process exit did not reproduce in its final
independent invocation: all active, inactive, hidden and minimized cases pass with
completed report verification. [Shutdown run](journal-final-shutdown-window-isolated.log).
The failed aggregate run remains a failed run.

Two test fixtures needed updates without changing assertions' intended behavior:
Mail reads the explicit row swipe slot instead of assuming it is the first child;
Gesture uses the current layout-request measurement API instead of the already
removed `layoutFrame` property. All existing gesture scenarios pass after that
fixture correction.

## Remaining verification limits

- Device VoiceOver, the device-wide Reduce Motion setting, and physical diagnostic
  text-selection gestures have not been verified. Native selection construction
  and controller-level motion behavior do not substitute for those device checks.
- The complete installed iOS dependency-closure audit is not passing in this local
  environment: the repository host switch contains stale links, and old audit
  helpers assume an external `_opam` switch layout. Current application builds,
  iOS module/example checks, complete-object validation and physical application
  tests pass using the explicitly selected installed dependencies and local iOS 26
  compiler. These are separate claims.
- No SDK repository was regenerated or published. No framework commit or push was
  performed. A later authorized push must regenerate and separately commit/push
  the SDK from that pushed framework revision.
- Final `spec-dev-tool check --all`, `git diff --check`, evidence-link validation
  and physical acceptance source-hash comparison pass. The decision is now
  [implemented](../../agent-guide/implemented/feature/2026-09-18-journal-native-public-ui.md).
- The consumer, protected OCaml spec files and all Dune files remain unchanged.
