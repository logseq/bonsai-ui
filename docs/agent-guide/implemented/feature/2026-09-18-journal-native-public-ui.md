# Public native UI APIs for Journal

## Problem

`logseq_journal` owns SwiftUI bridges for native lists, navigation activation,
outline rows, toolbars, forms, and confirmation. Public OCaml framework APIs
should express these behaviors without moving application state into Swift.
Some underlying capabilities already exist; exposing another generic native
widget registration API would not close the public composition gaps.

The user authorized implementation on 2026-09-18 after resolving Q1–Q4.
The engineering probes below establish the native primitives and narrow admission
boundary. Implement the public APIs in dependency order, retaining the full
production regression and hosted acceptance requirements below.

### Inspection baseline and exact gaps

Inspected on 2026-09-18: framework HEAD `d1c97bd`, consumer HEAD `aa3c877`.
Framework paths below are repository-relative. Consumer paths are relative to
`/Users/rcmerci/gh-repos/logseq_journal` and were inspected read-only.

| Capability | Existing production support | Exact gap |
| --- | --- | --- |
| Native List | `ocaml/ui/view.mli`, `Native_list`: keyed sections/rows, row and section separators, visible range; `swift/BonsaiSwiftUI/Sources/NativeList.swift`: real `List` and `Section`, native visibility observation, refresh integration | No style property, explicit row target, scroll request lifecycle, or hierarchical row structure. |
| Scroll commands | `ocaml/runtime/host_effect.mli`, `scroll_to`: cancellable normalized container offset; `NativeScrollCommand.swift`: observed completion, interruption, Reduce Motion. `View.Scroll_targets` is a separate controlled scrolling container | Neither provides stable-key targeting in `Native_list`. `ScrollObservation.swift` excludes `.nativeList` from `scrollAxis`, so the existing host command cannot simply be used on a List. |
| Menus/actions | `View.Menu` supports native menu content; `View.Swipe_actions` supports roles, symbols, disabled actions and row-scoped native swipe interaction | No context-menu modifier. `NodeStore.swift` validates swipe content only as the immediate child of a List row; arbitrary wrapping or disclosure nesting is not supported. |
| Navigation | `View.Navigation_stack` gives OCaml route authority and native Back. `BonsaiNativeContext.navigationLink` and `NativeNavigationStack.swift` already admit native link requests and settle the exact native event, including unchanged routes | No public core OCaml link constructor. Existing helper captures a native-view generation and does not establish eligible cross-update intent retention for core controls. |
| Disclosure | `View.disclosure_group` is controlled; collapsed children lose input/accessibility, and nested label controls cannot dispatch | Generic disclosure content is not a hierarchy of native List rows with separate label actions. It cannot express independently owned parent/child swipe and context actions. |
| Toolbar | `View.Toolbar.item/create`, `Body.toolbar`: keyed ordinary children, nine placements, identity tests | No bottom bar, keyed group, or toolbar spacer. `NativeToolbar.swift` collects all items with the same placement into one `ToolbarItemGroup`, erasing requested group boundaries. |
| Forms and unavailable states | Ordinary core child views, labels, buttons, sections internal to `Native_list` | No public Form, reusable native Section, LabeledContent, ContentUnavailableView, or general native text-selection modifier for diagnostic values. |
| Confirmations | Controlled sheets/popovers and `PresentationController`; host-service action chooser in `NativeHostDialogs.swift` | No public controlled native Alert or ConfirmationDialog. A host chooser rendered in a sheet is not either of these surfaces. |

Existing List visibility flattens section **rows**, excludes header/footer slots,
and reports a half-open range. Preserve that contract. The consumer's
`JournalListViewport.swift` counts its own supplied slots, including header slots;
that difference is an application mapping concern, not a reason to change the
framework's existing indices.

### Consumer evidence and replacement boundaries

| Consumer reference | Behavior to express through public APIs |
| --- | --- |
| `swift/JournalList.swift` | Plain List, hidden separators, full-width open control, status/delete swipe and context actions, explicit first-entry scrolling after capture, visible-range reporting. |
| `swift/JournalFavorites.swift` | Plain List, stable row identity, full-width open control, ordinary footer content, bounded pending open intent. |
| `swift/JournalOutline.swift`; `app/application.ml`, `Native_outline`; `app/journal_detail.ml` | Recursive disclosure labels/children, controlled expansion and loading, per-row delete actions, reveal appended child at bottom. Detail session scope already distinguishes replacement content. |
| `swift/JournalChrome.swift`; `app/journal_header.ml` | Journals/Favorites group, flexible toolbar space, separate Capture group, ordinary keyed OCaml controls. macOS intentionally chooses navigation/primary-action placements. |
| `swift/JournalForms.swift`; `app/application.ml`, `Native_form` | Grouped Form, Section, selectable labeled values, unavailable description/actions, inset-grouped iOS List and explicitly selected inset macOS List. |
| `swift/JournalConfirmation.swift`; `app/application.ml`, `Native_confirmation` | Application-controlled destructive confirmation; one logical response despite button and dismissal callback ordering. |

Replacing the listed standard portions does not prove that every registration can
be deleted. `JournalForms` also implements reading-density, feedback, and unlock
layouts; `JournalChrome` also implements sync feedback and title styling. Audit
those separately before claiming complete bridge removal. This work must not
modify the consumer to perform that removal.

The existing [NavigationLink admission decision](../../proposed/feature/2026-09-17-native-navigation-link-admission.md)
remains proposed and records implementation plus incomplete historical validation.
Its claim that Journal/Favorites consumed the helper is not the current consumer
source: both now use Buttons and a 250 ms pending-open deadline, retried every
50 ms. Preserve the evidence distinction; this document does not transition or
rewrite that decision, and does not treat historical tests as current results.

## Proposal

### Confirmed design decisions

The user selected Q1 B and Q2–Q4 A:

- Raise the framework's minimum iOS deployment version to 26; retain macOS 26.
- Use a tokenized optional Native_list scroll request with a typed terminal-result
  handler. Clearing the request cancels it; a new token permits the same target
  to be requested again.
- Give leaf and disclosure rows explicit swipe/context action slots, and remove
  the obsolete immediate Swipe_actions wrapper composition path.
- Return one token-scoped confirmation result, `Action key | Dismissed`, with
  button/dismissal arbitration owned by the framework.

These decisions resolve the user-facing choices. The engineering evidence below
is separate from design approval and does not establish iPhone behavior.

### Ownership and implementation boundaries

Keep graph state, pagination, expansion, mutation decisions, route acceptance,
editor drafts, and presentation state in OCaml. Swift owns native rendering,
native mount/visibility observations, action admission, and transient settlement.
Preserve the consumer's revisioned editor; do not replace it with an expandable
composer.

Prefer additions within existing public modules (`View` and `Event`) and their
production owners. This avoids adding OCaml compilation
units to explicit Dune module lists. Update protocol schema, generated constants,
codecs, and fixtures together when required, following `protocol/README.md`.
Remove obsolete paths; do not add legacy decoders, compatibility constructors,
fallback renderers, or migrations. An incompatible wire change requires the
documented protocol major-version change.

`ocaml/ui/view.mli` and `ocaml/runtime/host_effect.mli` are public interfaces outside
the protected `ocaml/spec/` directory. No protected change is currently identified
as necessary. Existing node IDs, keys, and event infrastructure are candidates
for reuse, not permission to bypass ownership. If implementation discovers an
unclear or unreasonable protected `.mli`, stop and report its exact declaration,
suggested amendment, and rationale. Do not change any Dune file without explicit
authorization; if a new target/module proves necessary, report that concrete
need instead of adding it silently.

### 1. Native List styles and platform contract

Add `Plain`, `Inset`, and `Inset_grouped` to a typed `Native_list.style`, with an
explicit style argument on `vertical`. Retain row/section separator arguments
and refresh behavior. Prefer an explicit style in focused examples and update
repository call sites coherently if the argument becomes required.

At inspection, `Package.swift` declared iOS 18 and macOS 26 minimums. The confirmed
decision raises the framework's iOS minimum to 26 and retains macOS 26. During
implementation, update the package, framework tooling's supported minimum and
defaults, generated-host deployment settings, examples, tests, and documentation
where they declare or enforce the old baseline. Identify all affected declarations
before editing; keep protected-spec and Dune restrictions in force. Do not modify
the consumer or add support paths for older iOS versions.

Apple documentation metadata and the installed Xcode 26.1 SwiftUI interface
establish availability on the selected baseline:

| Capability | iOS 26+ | macOS 26+ |
| --- | --- | --- |
| Plain / Inset List | Supported | Supported |
| Inset-grouped List | Supported | Unavailable |
| Bottom-bar placement | Supported | Unavailable |
| Native fixed/flexible ToolbarSpacer | Supported | Supported, at a supported placement |
| ContentUnavailableView | Supported | Supported |

Sources: [InsetGroupedListStyle](https://developer.apple.com/documentation/swiftui/insetgroupedliststyle),
[InsetListStyle](https://developer.apple.com/documentation/swiftui/insetliststyle),
[bottomBar](https://developer.apple.com/documentation/swiftui/toolbaritemplacement/bottombar),
[ToolbarSpacer](https://developer.apple.com/documentation/swiftui/toolbarspacer),
[ContentUnavailableView](https://developer.apple.com/documentation/swiftui/contentunavailableview).
No additional Apple platforms enter this scope.

On the selected baseline, reject unsupported requested capabilities through explicit native
validation before publishing the affected tree, with a capability/platform
diagnostic. A consumer can deliberately construct a different supported layout;
the framework must not turn Inset_grouped into Inset, Bottom_bar into another
placement, or ToolbarSpacer into an ordinary Spacer. No iOS 18–25 rendering or
deployment compatibility path is retained.

### 2. Stable-key explicit List scrolling

Use a List-local target containing section key and nonempty row ancestry path.
The flat case has one row key. This supports sibling-scoped keys without imposing
global row-key uniqueness and leaves a compatible target shape for hierarchical
rows introduced in batch 5. Bind a request to the current List owner incarnation;
neither another List nor replacement content with identical keys may receive it.

Confirmed public model: a declarative optional `Native_list.scroll_request`
on the List, containing a monotonically increasing request token, target,
`Top | Center | Bottom`, and `animated`; a typed completion decoder exposes token
and outcome through a handler. A new token is a distinct command even for the
same target. Re-rendering the same token does not repeat it; changing its payload
is invalid. Clearing the request cancels it. Do not add a parallel List-row
`Host_effect` command. Existing normalized scrolling for other containers remains
outside this new request model.

Candidate lifecycle:

| Event or condition | Required outcome |
| --- | --- |
| Valid request on the current List | Snapshot owner and target incarnation; enter pending. |
| Target absent from committed logical rows | Finish `Missing_target`; do not fetch data or wait for a future same-key insertion. |
| Target under a collapsed ancestor | Finish `Hidden_target`; do not expand on behalf of OCaml. |
| List temporarily awaiting an eligible presentation/layout commit | Wait within a bounded admission window; issue no native movement yet. |
| List/target identity replaced, removed, or disposed | Cancel old work, discard observers; no retargeting by key. |
| Newer request on the same owner | Finish old request as superseded and admit the new request. |
| Explicit cancellation, user scrolling, page deactivation, or app inactivity | Stop pending movement and settle cancellation once. |
| Observed requested alignment, or its reachable boundary-clamped equivalent | Finish success once for the matching request. |
| Native movement or observation cannot establish completion within its bound | Finish an explicit positioning failure, never a fabricated success. |

“Mounted target” needs a precise native experiment: a lazy List can have a
committed offscreen row without a materialized cell. Admission requires a mounted
List and a target registered in its committed native content, not an already
visible cell. Observe the actual target geometry once native scrolling realizes
it. If SwiftUI cannot issue/observe this reliably with the available APIs, record
the limitation before choosing an implementation. Waiting for an offscreen cell's
`onAppear` before issuing the first scroll can deadlock the feature.

Measure the target's top/center/bottom against the actual List viewport, including
native insets and clamping near content boundaries. Define the tolerance, large-row
behavior, observation stability, and admission/completion deadlines from hosted
experiments before the proposal is finalized. Visibility alone is insufficient
proof of alignment. A call to `scrollTo` is not success. Immediate movement and
Reduce Motion must suppress animation while retaining observed completion.

Settlement must survive handler rebinding only through exact request ownership;
it must never invoke a replacement request's handler. Deliver one terminal result
while the originating owner is live; disposal revokes callbacks and releases all
retained state. A transport retry must not replay native motion.

Capture completion targets the first journal **entry**, not the section header.
Append completion waits for OCaml to commit the new child and any expansion, then
submits a new token. No command is issued when returning from detail: keep the
existing native List instance and let it retain its own position. Ordinary
updates, push/pop, and sheets must not use a request token as the List's view ID.

### 3. Context menus and row action snapshots

Expose a typed native context-menu API with keyed actions, text titles, optional
SF Symbols, enabled state, `Normal`/`Destructive` roles, and ordinary OCaml
handlers. Native menu action descriptors may share implementation with Menu or
Swipe_actions, but must retain their own presented action snapshot.

At menu presentation, capture the owning row incarnation, action identity,
handler binding, and presentation generation. Selection must validate that exact
ownership. Removed, disabled, hidden, disposed, or replaced actions are rejected;
an old menu must not dispatch through a current handler just because its key
matches. Use the same discipline for retained swipe callbacks. Do not automatically
replay destructive actions after rejected admission.

For native List rows, menu and swipe content use explicit row-owned slots (see
batch 5), so both modifiers attach to the same label and not an expanded subtree.
A general context-menu modifier may wrap ordinary views, but cannot bypass the
List row grammar. Navigation, expansion, swipe, and menu gestures remain distinct.

### 4. Core NavigationLink and activation reliability

Expose a core `View.Navigation_link`-style constructor taking a stable key,
enabled state, an activation identity, ordinary label content, and an OCaml
activation handler. The enclosing Navigation_stack is the sole navigation owner.
Only the accepted OCaml path adds a destination. Retain the existing native Back
contract, and release admission after the exact activation event is settled even
when OCaml returns the unchanged route. No temporary destination or second stack.

Do not implement this as a generic retry around every Button. First reproduce
the consumer's short presentation-update admission gap at the narrow production
boundary, using a core link and real event pumping. Existing evidence shows
`NativeViewInstance.synchronize` can invalidate presentation/generation when
properties, bindings, or children change; it does not prove the same cause or
repair for core links. Include actual hosted native activation, since the earlier
decision records SwiftUI optimistic-path behavior invisible to pure owner tests.

Candidate contract for navigation-only pending intent:

- An intent captures a unique serial, stack/page/content incarnation, link node,
  logical activation identity, route snapshot, and originating handler snapshot.
  A reused key alone never establishes continuity. Changing logical meaning
  requires a new activation identity even if native layout identity is retained.
- Eligible updates retain the same owner, route, target, activation identity,
  enabled state, and semantic handler ownership, and only temporarily interrupt
  presentation readiness. A handler replacement with no proven continuity is
  ineligible. Do not look up and call the latest closure by row key.
- Store at most one undelivered intent per navigation owner. A later explicit
  activation supersedes an undelivered one; once admitted, prevent duplicate
  delivery until the exact event settles. Unrelated events cannot settle it.
- Retry on meaningful presentation/mount/commit readiness notifications. Use a
  bounded expiry as a final lifetime limit, with its duration selected from
  measured native behavior rather than copying 250 ms into controls. Do not poll
  indefinitely or retain intent through backgrounding or another destination.
- Removal, hiding, disablement, changed route/owner/activation identity,
  disposal, and content deactivation cancel the intent. Admission is checked
  again immediately before emission. Rejected route updates release admission
  for a new explicit click; they do not replay the old request.
- Distinguish captured, waiting, emitted, settled, and cancelled states. Verify
  duplicate prevention both before emission and after transport admission, and
  retain the framework's displayed-revision/handler validation.

The implementation mechanism for preserving an original handler across an
eligible revision remains an investigation gate: inspect
`ocaml/runtime/handler_registry.ml`, `event_dispatcher.ml`, and Swift event
settlement together. If exact snapshot retention cannot fit existing revision
ownership, propose a narrow explicit activation identity/admission handshake;
do not relax validation globally. Whether a stable semantic identity can permit
handler renewal needs evidence and a documented rule before implementation.

Use a real native NavigationLink with full-row hit area and native accessibility.
Verify taps outside text, VoiceOver activation, disabled presentation, and
repeated clicks. Native label layout, chevrons, and accessibility must not be
approximated by a decorated Button.

### 5. Explicit hierarchical native List structure

Confirmed row composition, expressed schematically rather than as final signatures:

```text
Native_list
  Section(key, header?, footer?, separators)
    Row(key, label, row_actions, separator)
    Disclosure_row(key, label, expanded, on_expanded,
                   row_actions, separator, child_rows)

row_actions = { swipe_actions; context_menu }
child_rows = independently keyed Row / Disclosure_row values
```

Expose `Native_list.disclosure_row` alongside leaf rows. It returns a row, not an
ordinary disclosure widget containing an opaque arbitrary subtree. Label,
controlled Boolean binding, action slots, and child rows have distinct ownership.
Sibling keys are unique within a section or parent; the section plus ancestry
path identifies a scroll target. Reparenting creates a different row identity.

Move native List swipe ownership to these explicit slots and remove the obsolete
immediate-wrapper composition path, updating framework call sites/examples/tests
in the same batch. Do not keep two row grammars for compatibility. Exact public
naming and descriptor reuse remain implementation design details within these
confirmed ownership boundaries. Update OCaml construction checks, wire
validation in `NodeStore.swift`, RenderTree input ownership, and SwiftUI rendering
as one change; merely adding allowed descendants to `ownedSwipeRows` is unsafe.

Attach parent actions to the parent's label. Render each child as its own native
row with its own label/action identity. Expansion dispatches only expansion;
child/parent/sibling actions dispatch exactly their respective row handlers.
Collapsed children have no input or accessibility admission. Their expansion
state and loaded data remain OCaml-owned. Retaining logical child state does not
mean a collapsed descendant is a valid scroll or action target.

Visibility becomes the depth-first sequence of currently expanded logical rows,
including disclosure parents and ordinary pagination rows. Exclude section
headers/footers and collapsed descendants. Specify this indexing explicitly and
test updates/collapse; the consumer maps it to its application slots. Do not make
the framework infer pagination or load descendants.

### 6. Keyed toolbar groups and native spacers

Replace placement-only item metadata with an ordered, keyed toolbar structure:
`Item`, `Group` of keyed items, and `Spacer` with `Fixed | Flexible` sizing and a
placement. Add `Bottom_bar`. Do not merge distinct groups that share placement.
“Fixed” means native fixed toolbar spacing, not an application-specified pixel
width. Group keys and child keys have explicit sibling scopes.

The required iOS 26 layout is:

```text
Group("journal-navigation", Bottom_bar, [Journals; Favorites])
Spacer("capture-gap", Bottom_bar, Flexible)
Group("journal-capture", Bottom_bar, [Capture])
```

SwiftUI owns materials, sizing, safe areas, and overflow. Preserve the original
body as a stable child and preserve item identity within an unchanged keyed group
across content/placement/reordering updates. Moving to a different group changes
ownership and must reject retained old callbacks. Verify ordinary child buttons,
menus, and focused inputs keep their established input ownership during eligible
updates. Do not rebuild a custom overlay toolbar.

Use the confirmed iOS 26/macOS 26 baseline. macOS can explicitly use Navigation and
Primary_action groups; it cannot receive Bottom_bar. Test group boundaries on
iOS 26 itself rather than treating a decoded toolbar descriptor as visual proof.

### 7. Standard forms, unavailable states, and confirmations

Expose native Form with explicitly keyed rows/sections, reusable native Section
with ordinary header/footer/child views, LabeledContent with label/value slots,
and ContentUnavailableView with label/description/action slots. Preserve native
Form sizing and typed viewport/body composition; Form must not accidentally
become a nested scroll view. A Section must render structurally as a native
section, not as a visual stack hidden inside one List row.

Add or expose native text selection for ordinary diagnostic text. Selectable
values must not become editable fields; their ownership remains application-side.
Use existing semantic button roles and child handlers. Verify actual native
Section structure through the framework's type-erased rendering boundary.

Expose controlled Alert and ConfirmationDialog attached to stable base content.
Each presentation has an explicit fresh token, keyed action descriptors, title,
message, semantic roles, enabled state, and one typed response handler. Keep
ordinary child views where the native surface supports them; do not claim SwiftUI
alerts can host unrestricted arbitrary layouts. The base content and supported
message/action content must retain OCaml ownership.

The confirmed response model is one `Action(action_key)` or `Dismissed` result per
token, with no independent button and dismissal commands. Capture token,
presenter incarnation, action identity, and handler snapshot. A button response
wins over its accompanying native dismissal. When the binding is cleared first,
defer dismissal arbitration until the matching native callback turn completes,
then settle once. Verify both callback orders; do not use a global `responded`
Boolean that can reset for a newer presentation while an old callback is queued.

The application remains authoritative for whether the presentation stays open
or closes after a response. Once resolved, the same token cannot emit again;
showing a new logical presentation requires a new token. Old closures after
re-presentation, replacement, hiding, or disposal cannot affect the new token.
Admission rejection must not convert a destructive selection into a replay on
new content. Integrate modal input blocking with existing presentation ownership
so background rows cannot activate through an alert/dialog.

### Dependency-ordered implementation and evidence plan

Q1–Q4 are resolved. Record the remaining native scrolling and activation
investigation outcomes, validate, and transition this document to proposed through
spec-dev-tool before production implementation. Use the
repository's TDD workflow for subsequent behavior changes. The batches below are
planning only; they do not authorize editing protected files or the consumer.

| Batch | Main production boundary | Exit evidence |
| --- | --- | --- |
| 1. Platform baseline and List styles | iOS deployment declarations/tooling, `ocaml/ui/view.ml/.mli`, protocol, `NativeList.swift`, node decoding | Consistent iOS 26 minimum; explicit style and availability checks; unchanged separator/refresh/visibility behavior. |
| 2. Row scrolling | Public request/result shape, List target ownership, native List geometry/lifecycle | Flat-row targeting, same-target new tokens, cancellation/replacement, observed alignment on a real List, return retention. |
| 3. Context menus | Public descriptors, event binding, native menu owner, row action attachment | Menu plus swipe on one flat row; stale callbacks never target changed handlers. Reserve explicit row slots for batch 5. |
| 4. Navigation links | Core View/events, `NativeNavigationStack.swift`, exact event admission/settlement | Reproduced update-gap test; accepted and unchanged routes; no duplicate delivery or temporary native destination. |
| 5. Hierarchy | Native_list row grammar, NodeStore/RenderTree, disclosure labels and target paths | Parent/child/sibling isolation, independent expansion, collapsed input rejection, appended-child scrolling. |
| 6. Toolbars | Toolbar descriptors/protocol, `NativeToolbar.swift`, child ownership | Distinct same-placement groups, native spacers, stable updates, unsupported-platform rejection. |
| 7. Forms/confirmations | Structural native containers and presentation owner | Selectable diagnostics, ordinary OCaml handlers, exactly-once token settlement and stale-callback fencing. |

Add focused public examples and documentation with each batch, preferably within
existing example/test targets to respect Dune restrictions. Relevant current
tests include `ocaml/test/core_surface_tests.ml`, `control_surface_tests.ml`,
`public_api_tests.ml`, `event_dispatch_tests.ml`, and Swift `NavigationLinkTests`,
`NavigationStackTests`, `SwipeActionsTests`, `DisclosureTests`, `ToolbarTests`,
`ScrollServiceTests`, `MenuTests`, and `NativeViewTests`. Reuse only tests at the
ownership boundary actually affected. Existing normalized-scroll tests do not
prove native List row scrolling.

Planned verification layers must be reported separately:

1. **Compilation and schema:** public OCaml examples, protocol generation/check,
   opposite-language fixtures, Swift package and iOS builds. Follow `Makefile`
   prerequisites (`make test`, `make protocol-check`, `make protocol-fixtures-check`,
   `make swift-test`) as relevant; do not claim a macOS build verifies iOS behavior.
2. **Deterministic behavior:** keys and owner incarnations, invalid structures,
   generation/handler replacement, missing/hidden targets, duplicate tokens,
   rejected admission, exact settlement, cancellation, disposal, and both dialog
   callback orders. Use public construction and the narrow production controller;
   avoid substituting a test-only model for the implementation.
3. **Hosted native interaction:** actual List top/center/bottom movement and
   observation, same-target requests, native full-row hits, gesture isolation,
   hierarchy action identity, empty-path/unchanged-route retry, Back and interactive
   pop with retained List position, toolbar groups, selectable text, native
   alerts/dialogs. Test input still works after returning, not just that a toolbar
   is visible. Capture evidence on each claimed platform/version.
4. **Physical device:** iPhone List movement, Reduce Motion, row/menu/swipe targets,
   repeated presentation updates, interactive Back followed by Capture, outline
   append reveal, native toolbar grouping/overflow, VoiceOver, and confirmation.
   Record commit, device/OS, scenario, and result. If unavailable, mark unverified.

Any later authorized commit/push must follow the repository rule: regenerate the
iOS SDK repository from the pushed framework commit, then commit and push that
SDK update separately. The implementation request does not authorize committing or publishing code.

## Decision

All seven public capability areas are implemented, documented and exercised
through the production OCaml/Swift runtime. The implementation intentionally
requires iOS 26 and wire protocol major 10; macOS remains 26. The standard bridge
replacement map, failed attempts and final evidence are recorded in the
[implementation report](../../../test-reports/2026-09-18-journal-native-public-ui/README.md).
The consumer was not migrated, and its application-specific layouts and
revisioned editor remain outside this implementation.

Physical iPhone 13 / iOS 26.7 acceptance passes all 12 new-API UI tests together,
plus two Mail runtime and two Mail UI tests. The final cases verify actual native
List positioning and zero-command retention after interactive Back, returned
Capture/page commands, toolbar groups and overflow, row link/menu/swipe isolation,
Sheet context menus, hierarchy targets, Form actions, and exactly-once native
confirmation responses. Device VoiceOver, device-wide Reduce Motion and diagnostic
text-selection gestures remain explicitly unverified.

Final regression ran after implementation of all capabilities: OCaml/protocol,
native bridge and platform checks pass. The complete Swift inventory was attempted
in 324 isolated invocations: 322 pass; Menu process completion and Sidebar modal
reopening failures reproduce on original HEAD. All four Menu tests pass separately.
Of 30 native-window scripts, 29 pass after two obsolete fixture accesses are
updated; the remaining AppBars resize failure also reproduces on original HEAD.
The aggregate full-suite invocation is not represented as passing. The final
isolated shutdown test passes all four native window modes.

The complete installed iOS dependency-closure audit remains limited by the local
switch installation and audit assumptions, separate from passing current source
application builds and device runs. No protected spec, Dune, consumer, or
bonsai_flutter source changed. No commit, push, SDK regeneration or SDK publication
was performed. There are no remaining implementation tasks under this decision;
unverified platform checks and unrelated baseline failures are disclosed limits.

## Alternatives considered

### Keep application-owned bridges or add another extension wrapper

Does not satisfy standard public OCaml APIs. Existing bridge implementations are
behavioral references, not framework dependencies or new standard registrations
carrying Journal-specific JSON/state.

### Replace List with ScrollView or a collection renderer

Loses native List styling, hierarchical semantics, swipe behavior, and native
position retention. Scroll_targets and normalized scroll_to remain useful for
their existing containers, but are not alternate List renderers.

### Restore position by issuing a command on navigation return

Conflates explicit user commands with native retention and may move a retained
List unexpectedly. Keep the List's identity across destination presentation.

### Replay every temporarily rejected input using the latest handler

Cannot distinguish valid navigation intent from a replaced command and is unsafe
for destructive actions. Explore bounded, owner-scoped navigation intent only;
context/swipe/confirmation actions retain exact presented identity.

### Wrap an entire disclosure in Swipe_actions

May attach parent actions to descendants and cannot express the current validator's
row ownership. Use a typed hierarchy and explicit label-action slots instead.

### Synthesize unsupported toolbar/style behavior

An HStack overlay, ordinary Spacer substitute, or silent style/placement mapping
violates native ownership and explicit platform availability. Either constrain
the capability or explicitly change the supported platform baseline.

## Acceptance criteria

- All seven capabilities have public OCaml contracts, explicit availability,
  focused documentation/examples, and behavior tests at their production owners.
- Framework deployment declarations, tooling, generated hosts, examples, and
  public documentation consistently require iOS 26 or later; macOS remains 26.
  Older iOS deployment targets are rejected explicitly, with no fallback path.
- Native List separators and row-only visibility indices remain correct, with
  hierarchy indexing explicitly documented. Repeated and section-scoped scroll
  requests succeed only after observed positioning; cancellation and failure are
  observable and stale completions cannot settle newer requests.
- Returning from detail retains the native List and its position with zero
  restoration commands, and the returned page still admits input.
- Navigation activation survives proved eligible short updates, succeeds at most
  once, releases on unchanged routes, rejects stale/foreign/inactive targets, and
  never creates an optimistic placeholder destination or another stack.
- Context menus and swipes coexist; every parent/child/sibling action retains its
  original row identity, and disclosure changes cannot trigger row actions.
- Toolbars preserve explicit group boundaries and child ownership. No unsupported
  feature silently changes rendering or placement.
- Forms, sections, unavailable actions, and diagnostic text preserve native
  semantics. Alert/dialog button-plus-dismissal sequences settle once per token;
  old callbacks have no effect on later presentations.
- No consumer/bonsai_flutter changes, graph/pagination/editor ownership transfer,
  compatibility paths, fallback renderer, protected-spec edits, or Dune edits.
- Final implementation reporting lists public APIs changed, replaceable bridge
  portions, each verification layer's actual results, and unresolved limitations.
  Missing physical evidence or unrelated baseline failures are disclosed, not
  counted as passes.

## Consequences

Consumers must adopt explicit List styles and row action slots, ordered toolbar
entries, iOS 26 deployment and protocol major 10 together. Old deployment targets
and wire shapes are rejected rather than migrated. Applications keep their graph,
pagination, expansion, navigation acceptance and editor state; native controls own
only rendering and scoped interaction settlement.

The Journal standard UI portions can now use public constructors. Removing its
bridges remains separate consumer work and requires auditing their extra layouts.
Validation limits and original-HEAD failures are retained in the report; this
implemented lifecycle does not assert an entirely green aggregate suite or
unperformed device accessibility checks. SDK publication remains a later explicit
commit/push operation governed by the repository's separate-update rule.

## Risks

- **Lazy List geometry:** native offscreen scrolling and accurate target alignment
  are not established by the existing ScrollView service. Probe native List
  behavior before freezing completion semantics or promising platform coverage.
- **Activation continuity:** displayed revisions, handler lifetimes, native
  generations, and semantic content lifetimes differ. A key-only retry can send
  an old command into new content; rejecting every revision can lose valid clicks.
  The continuity/admission investigation is a proposal gate.
- **Platform minimum:** raising the framework baseline to iOS 26 deliberately
  drops iOS 18–25 support, including for consumers that do not use the new toolbar.
  Package settings, tooling validation/defaults, and generated host declarations
  must agree; macOS-only placement/style restrictions still apply.
- **Structural native composition:** type-erased children can obscure native
  Section/disclosure/toolbar structure. Correct descriptors alone are insufficient;
  validate resulting native rows and group boundaries.
- **Presentation races:** alerts/dialogs may dismiss before button callbacks,
  and native navigation may optimistically mutate internal state. Pure tests need
  narrowly targeted hosted counterparts.
- **Scope:** standard portions of the consumer bridges are replaceable; unrelated
  custom layouts may remain. No whole-bridge deletion claim without an inventory.
- **Historical evidence:** the earlier navigation decision records unrelated
  baseline Swift failures and partial device work. None was rerun here or can be
  assumed to validate the new APIs.

### Engineering investigation, 2026-09-18

Environment: framework `d1c97bd`, macOS 26.6.2 (25G83), Xcode 26.1.1
(17B100). Temporary hosted probes were compiled outside the repository against
SwiftUI and, for activation, the current framework and real OCaml runtime fixture.

- A plain native List with a Section header and 100 variable-height rows started
  without row 80 materialized. ScrollViewReader realized it without waiting for
  its appearance. Top, center, bottom, repeated target, first/last boundary, and
  a 500pt row in a 300pt viewport were measured. Native coordinates put the
  ordinary label at y=4 for top, y=130 for center (40pt height), and y=256 for
  bottom; the native row includes 4pt top/bottom insets. The large row centered
  at y=-100. Boundary requests stopped at native content limits.
- SwiftUI named-coordinate row geometry was displaced by the 32pt Section header.
  It must not be used as uncorrected alignment evidence. Use a row-local native
  observation view to measure the enclosing native row against its actual scroll
  viewport, and use SwiftUI ScrollViewReader to issue the lazy realization.
  Native List remains the renderer. Require <=1pt error for the full native row,
  including native insets, stable for two samples at least 16ms apart. Admission
  has a 500ms bound; positioning has a 2s bound. These conservative limits exceed
  the observed sub-300ms settled samples; the probe did not measure a latency
  distribution. Both bounds result in explicit failure, never implied success.
- The real `native-link` OCaml fixture reproduced a presentation gap while the
  route remained empty and the handler binding remained identical: the shared
  core `onInteractionPermission` boundary rejected input before presentation and
  accepted it after presentation (34.6ms including a deliberate 30ms observation
  delay). The old registered-view closure remained invalid afterwards. Renewing
  the native snapshot reached the committed destination via real event pumping.
  This isolates shared presentation admission from extension-generation expiry;
  it is not yet the core-constructor regression required in batch 4.
- Preserve an intent only when its original handler ID remains identical across
  revisions. Reconciler retains that ID only for the identical Handler object;
  registry frames continue to own the same closure. Emit with the currently
  displayed revision only after checking that exact ID and owner again. No
  handler lookup by application key and no global revision-validation relaxation.
  Replacement handlers cancel pending intent. Core intents expire after 500ms,
  retry only on presentation/mount/commit notification, and are never replayed
  after transport admission. The core-constructor hosted regression remains a
  required RED test before implementing its retry controller.
- The native runtime prerequisite completed successfully. The focused existing
  NavigationLink run passed five tests; these cover existing behavior only.
- The paired iPhone 13 was reported unavailable by devicectl. iOS compilation,
  physical gestures, Reduce Motion, and VoiceOver remain unverified.

The probes and logs will be retained with implementation evidence after this
proposal transition. No protected spec or Dune modification is needed by the
selected design. All production behavior still requires the tests listed above.

## Questions

All user questions are answered; no further user choice is pending.

- **Q1 — Answer B:** raise the framework's minimum iOS version to 26. Retain macOS
  26 and explicitly reject unavailable macOS capabilities; add no fallback.
- **Q2 — Answer A:** use a tokenized optional Native_list request and typed
  terminal-result handler, with cancellation by clearing the request.
- **Q3 — Answer A:** use explicit leaf/disclosure row action slots and remove the
  obsolete immediate Swipe_actions wrapper composition path.
- **Q4 — Answer A:** use one token-scoped response, `Action key | Dismissed`,
  rather than separate public action/dismissal callbacks.

No further product choice is pending. Remaining production regressions and native
platform evidence are implementation acceptance work, not requests to reconfirm
the decisions above.

## Implementation progress

- Batch 1: explicit Native_list styles and iOS 26 deployment baseline implemented.
  Protocol is now major 10, including the native C ABI version declaration.
  The OCaml suite and viewport type checks pass; 14 focused native List, swipe,
  and system-control tests pass. iOS 26 module/example typechecks pass. The local
  iOS compiler was rebuilt; four real compiler/runtime-object checks pass.
- Core Navigation_link is implemented early to close the core-specific admission
  experiment before row-scroll callback lifetime work. Its hosted real-runtime
  regression reproduced missing readiness notification, then passed after wiring
  presentation readiness. Owner, exact settlement, expiration, supersession,
  transport rejection, and byte-distinct activation replacement have focused tests.
- Form, reusable Section, LabeledContent, ContentUnavailableView, and native text
  selection are implemented. Form is a keyed vertical viewport. The hosted
  regression compares native geometry/accessibility with a direct SwiftUI Form,
  and `Group(sections:)` observes two real sections with two and one rows through
  the existing erased renderer. The real OCaml fixture verifies action delivery,
  disabled input, and retained identities during reordering. Gallery and public
  documentation now demonstrate these constructors. Protocol node 136 remains
  retired; these surfaces use fresh nodes 140–144. iOS 26 typechecking passes;
  physical selection gestures remain unverified.
- Flat List row scrolling is implemented with positive monotonic tokens, byte-exact
  section/row target keys, original handler snapshots, 500 ms admission and 2 s
  positioning bounds. Native geometry requires stable one-point alignment;
  offscreen realization, variable/oversized rows, boundary clamping, original
  handler delivery after three real OCaml rebindings, and stopping animation at
  the current offset have hosted macOS regressions. Disposal and consumption are
  rechecked when invoking a previously validated terminal batch. The
  hierarchical row work has extended target registration to collapsed descendants.
- Hierarchical rows and explicit label/swipe/context slots are implemented. Old
  Swipe_actions wrapper composition is removed. Disclosure callbacks arbitrate
  label activation within the native callback turn; unacknowledged expansion does
  not expose child interaction/accessibility. Target lookup includes collapsed
  descendants, reports Hidden_target, and scrolls revealed offscreen descendants.
  Parent targets align their native label row, not the expanded subtree. Same-key
  reparenting creates new row/action-owner incarnations.
- Context_menu exposes keyed actions, ordinary handlers, Normal/Destructive roles,
  symbols, enabled state, an ordinary-view attachment, and native row slots.
  Hosted macOS tests exposed handler replacement while a SwiftUI contextMenu was
  already tracking. A cached SwiftUI menu builder cannot define presentation
  ownership. Native configuration now creates immutable snapshots: NSHostingMenu
  preserves SwiftUI action rendering on macOS; UIContextMenuInteraction/UIMenu
  owns the iOS menu. Noninteractive anchors preserve original label controls and
  scope native interaction to the window, label bounds and active content. The
  hosted replacement-during-tracking regression passes. iOS module/example
  compilation passes; iOS gestures and VoiceOver remain unverified.
- Toolbar implementation checkpoint: the ordered Item/Group/Fixed-or-Flexible
  Spacer API, Bottom_bar capability check, independent body/entry/child slots,
  binary codec, generated IDs and fixtures are implemented. Same-placement groups
  use distinct native ControlGroups inside keyed ToolbarItems. Dynamic recursion
  keeps a stable concrete ToolbarContent body type; changing an erased payload
  type at an existing level caused a reproduced SwiftUI runtime cast crash.
  Direct SwiftUI controls preserve native command discovery, including initial
  overflow. Retained native input attachments preserve actual plain/secure fields
  and multiline editors through entry/group-child reorder, placement changes and
  spacer insertion/removal. A 500 ms owner-scoped focus lease preserves local
  draft, selection and marked text, respects newer OCaml values/selections and
  user focus changes, and rejects disabled/hidden/rebound/replaced/disposed owners
  and expired leases. The whole-content hosting prototype was removed because
  initially overflowing controls never mounted and produced an empty native menu.
  Actual OCaml reparenting creates new action owners and invalidates old callbacks.
- Toolbar acceptance checkpoint: 29 affected tests across eight suites pass.
  Actual cold-window overflow dispatches Button, Toggle and nested Menu actions;
  forced borderless Menu styling was removed so native submenu discovery works.
  The standalone SwiftUI App verifies retained menu dispatch across reorder and
  rejection after removal/reintroduction. Repeated AXPress opening of an overflow
  in the hosted XCTest process remains a harness investigation, not verified UI.
- Controlled confirmations are implemented through public Confirmation.alert /
  dialog, a stable base child, node 152, event 60 and typed response handling.
  Positive tokens strictly increase per retained presenter to bound consumed-token
  history. Text titles/messages/action descriptors use the native surface's
  supported content. Controller tests cover both callback orders, snapshots,
  stale callbacks, rejected admission and unchanged-state settlement. Actual
  OCaml runtime tests verify modal input blocking and no-diff authority. Hosted
  macOS Alert/ConfirmationDialog tests verify native destructive/disabled buttons,
  stable base content, and restored consumed presentations after ignored responses.
  Cross-language fixtures, public-surface tests, codec tests and iOS 26 module /
  example compilation pass. Gallery uses the same ordinary public constructors.
- All seven implementation areas have production paths and examples. Final
  regression is in progress. Current iOS 26 Mail, Counter, SQLite Worker, Gallery,
  and shared native fixture objects build. Physical iPhone 13 tests verify Mail
  runtime/UI, List requests and retention, native Back, bottom toolbar groups and
  post-return commands, hierarchy actions, Form, and confirmation settlement.
  The earlier missing `datascript_ocaml` audit message came from a directory scan
  that did not follow an installed symlink. Full iOS 26 dependency-closure auditing
  remains separate from these current-application builds.
- Forms checkpoint focused verification: 29 tests across seven suites pass with completed
  Swift Testing reports. Whole-suite verification remains incomplete: the original
  HEAD reproduces early process exit after the retained native Menu test, and a
  run excluding that test later exits during the native window shutdown test.
  No workaround for those test harness exits is retained in production or tests.
- The user unlocked the paired device and enabled UI Automation. Exact physical
  attempts, failures, fixes and result bundles are recorded in the implementation
  report. VoiceOver and the device-wide Reduce Motion setting remain unverified.
  No consumer, protected spec, or Dune file changed. No commit or push performed.

- Testing cadence updated by the user: run only affected tests during development;
  defer the full test suite until all capabilities are implemented. Earlier full
  runs above predate this instruction and remain historical evidence.

- Physical navigation diagnosis: the OCaml List owner survived, but default
  SwiftUI value-link activation recreated the native List even though the path
  binding rejected the provisional route. The ordinary-button path retained it.
  Core links now route touch, accessibility default activation and keyboard
  activation into their captured controlled intent before native path mutation.
  A real interactive Back retains the same List instance and offset, without
  any restoration request, and Capture/page-group commands still work.
- Physical confirmation: iOS routes outside dismissal through a supplied Cancel
  action. That returns its action key; a dialog without a Cancel action returns
  `Dismissed`. The four-action/device sequence settles exactly once per token.

