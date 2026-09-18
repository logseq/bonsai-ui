# Prefer System SwiftUI Controls

## Problem

BonsaiSwiftUI sometimes exposes a standard control name while implementing its
presentation or interaction with custom drawing, gesture thresholds, or layout.
This creates work that the system control could own and can prevent applications
from receiving native interaction, accessibility, appearance, and performance.

The Logseq Journal iPhone standardization task identified five concrete areas:
progress, List row swipe actions, List refresh, ordinary date selection, and the
expanded composer's sheet action area. The user requested this exploration in
the bonsai-ui repository on 2026-09-17. The user requested implementation of this decision on 2026-09-17.

### Evidence and limits

- `swift/BonsaiSwiftUI/Sources/NativeProgressView.swift` applies a custom
  `NativeProgressStyle` to ProgressView. It uses TimelineView with a 1/30-second
  minimum interval and draws circular or linear progress itself.
- In the consumer's same-host macOS Debug comparison, replacing only its
  Connecting presentation with system ProgressView reduced idle CPU from
  21.12% to 2.02% on the initial page, 60.72% to 2.50% after scene reactivation,
  and 54.30% to 2.74% with 500 roots loaded. These are percentages of one core.
  This supports the consumer repair, not an iPhone benchmark or a conclusion
  that every SDK progress configuration has the same cost. The SDK progress
  implementation was not changed by that repair.
- Consumer evidence is recorded in the sibling repository at
  `logseq_journal/docs/agent-guide/implemented/bugfix/2026-09-17-use-system-sync-progress.md`
  and batch 26 of its native standardization implementation ledger.
- The other four areas are source-audit findings. They are not measured
  performance regressions. Rendering with UIKit/AppKit controls is not itself
  evidence of a hand-built imitation.

## Decision

Prefer system presentation and interaction for the five selected areas, while
retaining application-owned values, events, async completion, and stale-input
rejection. Keep the repository's established iOS 18+ and macOS 26+ baseline;
the consumer's iOS 26 minimum does not silently raise the SDK minimum.

Do not preserve backward compatibility. When a public contract is deliberately
changed, update its implementation, protocol, examples, and tests together and
remove the obsolete path. Do not introduce compatibility aliases, fallback
renderers, migrations, or hidden capability loss.

### Confirmed direction

On 2026-09-17, the user accepted both recommendations in this exploration:

- Standard controls adopt system-native semantics. Audit callers and remove
  unsupported options from those contracts; retain a separately named custom
  extension only for a concrete required use case. Existing options alone do
  not establish such a requirement, and no compatibility path is retained.
- Include a minimal native List/Section composition path as the shared
  prerequisite for native row swipe actions and refresh. Keep generic Collection
  and application pagination redesign outside this scope.

Both product questions are resolved. The user authorized implementation on
2026-09-17. This proposal is the implementation contract.

### 1. ProgressView and system styles

Public API: `View.progress`, `View.Progress_style` in `ocaml/ui/view.mli`.
Implementation: `swift/BonsaiSwiftUI/Sources/NativeProgressView.swift`.

- Make the system ProgressView and its automatic, linear, and circular styles
  the basis for ordinary progress presentation. Add an explicit automatic style
  if selected for the public contract.
- Avoid an SDK-owned TimelineView for standard indeterminate activity. Retain
  meaningful labels, determinate values, enabled accessibility semantics, and
  the surrounding system control size and tint.
- Establish platform behavior before changing the contract: a determinate
  circular indicator is not available in every system context, and uniform
  indeterminate linear behavior must not be assumed. Do not silently turn a
  percentage into indefinite activity. Apply the confirmed native-contract policy
  to these capability gaps and document the resulting platform matrix.

### 2. Native swipe actions on List rows

Public API: `View.Swipe_actions` in `ocaml/ui/view.mli`.
Implementations: `swift/BonsaiSwiftUI/Sources/SwipeActions.swift` and `SwipePan.swift`.

- For ordinary List rows, let SwiftUI swipeActions own gesture recognition,
  reveal layout, full-swipe behavior, and action presentation. Preserve semantic
  Button roles, meaningful labels, disabled state, and event admission.
- Current code translates content, measures and draws action panes, and manages
  pan gestures and group closing itself. A List-backed contract should not carry
  these layout and gesture details unless a concrete system capability needs them.
- The current API also permits vertical actions, arbitrary content containers,
  explicit action extents, and group policies. System list-row swipeActions is
  not a drop-in replacement for that full contract.
- Attach actions to the intended row, not an enclosing expanded subtree. Keep
  nested row target identity in the native acceptance cases.

### 3. Native pull-to-refresh on List

Public API: `View.Refresh.vertical` in `ocaml/ui/view.mli`.
Implementation: `swift/BonsaiSwiftUI/Sources/NativeRefresh.swift`.

- The existing implementation already installs refreshable, but additionally
  tracks scroll offsets, uses a 72-point pull threshold, and prepends a Refresh
  button row. Ordinary native List refresh should use the system gesture and
  indicator instead.
- Retain the bridge between the async refresh action and OCaml's request token
  and completion. A gesture must submit once, wait for its own completion, and
  settle correctly on teardown; replacing the gesture does not remove this owner.
- Do not assume that applying refreshable to any arbitrary ScrollView supplies
  the same native affordance. A toolbar refresh action may be appropriate where
  the platform does not expose a pull gesture.
- Include the minimal native List/Section composition path shared with swipe
  actions: stable keyed rows, optional section headers/footers, native intrinsic
  sizing, and explicit row/section separator control. Keep data loading and
  pagination application-owned.

### 4. System DatePicker for ordinary date selection

Public API: `View.Date_picker` in `ocaml/ui/view.mli`.
Implementations: `swift/BonsaiSwiftUI/Sources/NativeCivilPicker.swift` and the
related date presentation in `NativeHostPickers.swift`.

- The current date UI assembles Year, Month, and Day menu Pickers even for an
  ordinary continuous range. Use a system DatePicker for that range and let it
  own native date presentation and locale-appropriate component ordering.
- Keep the date-only value model and explicit calendar/time-zone conversion
  correct. Verify that selection round-trips without shifting a civil date.
- The current selectable_dates whitelist can contain gaps. A standard DatePicker
  range cannot express arbitrary disabled dates; rejecting an already selected
  date is not equivalent to making it unavailable. Remove the whitelist from the
  standard date-picker contract; retain a separate custom extension only if the
  caller audit establishes a concrete requirement.
- Time selection already uses a system DatePicker and is not a replacement target.

### 5. Standard action placement in the composer sheet

Public API: `Native_widget.Expandable_message_composer` in
`ocaml/ui/native_widget.mli`; it shares content with `Message_composer`.
Implementations: `swift/BonsaiSwiftUI/Sources/NativeExpandableComposer.swift` and
`NativeMessageComposer.swift`.

- The outer sheet is already native and already exposes detents and a grabber.
  Its shared content adds a second transparent drag target, a custom downward
  dismissal threshold, a chevron close button, and a manually placed action row.
- Use a NavigationStack and cancellation/confirmation toolbar placement for the
  sheet, with the system sheet gesture as the dismissal mechanism. Represent
  action roles explicitly; do not infer Submit from a Filled button style.
- Keep inline composer expansion distinct from modal sheet dismissal. Preserve
  editor text, selection, composition, action identity, and existing draft
  ownership semantics through any composition change.
- Do not replace the native text adapter merely to replace sheet chrome. Final
  IME delivery, focus, save, and close ordering require native verification.

### Scope boundaries

This exploration does not include generic Collection virtualization, compact
Table redesign, arbitrary badge overlays, Range Slider, Removal, or a broader
Toolbar redesign. The minimal native List/Section prerequisite is included.
Graph draft storage, authentication, synchronization, mutation retry, and
Undo/Redo remain application concerns and are outside this decision.

Do not modify Dune files or protected spec files. The selected controls use the
ordinary UI interfaces and do not require protected spec changes.

## Alternatives considered

### Keep the current controls and patch individual symptoms

This minimizes immediate API changes, but leaves custom drawing and gesture
maintenance in ordinary system-control use cases. It does not address the
standardization goal. Targeted fixes may still be required before replacement.

### Replace every custom view with a similarly named system view

Rejected as a general method. Matching names do not establish matching contracts:
discrete date whitelists, sparse collections, editor composition, and vertical
swipe actions need explicit decisions. Native UIKit/AppKit adapters are not
automatically obsolete.

### Leave system-control composition entirely to applications

The consumer demonstrated this route, but it duplicates native List, refresh,
and composer composition across applications. Prefer reusable SDK composition
for the selected standard cases.

## Acceptance criteria

- Implement the confirmed native-contract policy and document the resulting
  capability and platform matrix, including any justified custom extension.
- Provide the minimal native List/Section prerequisite with stable row identity,
  intrinsic sizing, separator control, and native swipe/refresh composition.
- Each selected standard case uses the system control's presentation and
  interaction without the superseded SDK animation or gesture implementation.
- Public API changes are explicit, and obsolete paths are removed rather than
  retained for compatibility. No unsupported behavior is silently substituted.
- Validate progress with active/inactive transitions and comparable idle CPU
  intervals of at least 20 seconds. Reproduce the observed macOS consumer case;
  report iPhone measurements separately. Preserve truthful progress semantics.
- Verify native row action identity, cancellation, disabled state, and full-swipe
  policy. Verify refresh gesture admission and completion without an extra
  mandatory button row or SDK pull threshold on native List.
- Verify date boundaries, civil-date round-trips, locale ordering, and the
  explicitly selected whitelist policy.
- Verify composer native Close and confirmation actions, interactive dismissal,
  keyboard reachability, text/selection/IME preservation, and stale callbacks.
- Before adding a regression, identify its production owner and try deterministic
  reproduction through that owner's public state/events/completions. If native
  layout or gesture behavior is the missing boundary, test the narrow native
  host that executes it; do not inject a pre-corrupted result or duplicate the
  same regression across reducer, transport, persistence, and UI layers.
- Build supported platforms and record native accessibility, large text, RTL,
  Reduce Motion, and device limitations. Source review and successful compilation
  are not interaction or performance acceptance.

## Risks

- System controls can look and behave differently across supported platforms;
  standard appearance is the goal, not identical rendering everywhere.
- List adoption can change row identity, measurement, scrolling, and event timing.
  The prerequisite must stay bounded and must not silently replace sparse Collection.
- Narrowing contracts may remove capabilities used by gallery or consumer code.
  Audit call sites before deciding removals; do not hide losses behind a fallback.
- SwiftUI may deliver dismissal and action callbacks in different orders. Keep
  request ownership explicit and verify exact-once behavior at the correct layer.
- The progress CPU result is a macOS Debug consumer observation. The SDK repair
  requires its own controlled evidence and cannot inherit an iPhone performance claim.

## Consequences

Applications must rebuild against BSFR/BSIN 9 and expandable-composer schema 3.
Callers use native List rows for standard swipe actions and refresh, continuous
ranges for DatePicker, supported progress value/style combinations and explicit
composer toolbar roles. Removed options have no compatibility aliases or hidden
fallback renderers. The minimums remain iOS 18 and macOS 26.

The system owns ordinary appearance, gesture recognition and presentation.
OCaml retains values, effects, pagination and async request completion. Native
List supplies loaded rows; it does not replace the separate sparse Collection
contract. Physical interaction limits and the independently reproduced baseline
test failure remain recorded validation limits, not alternate production paths.

## References

- [Apple: ProgressViewStyle](https://developer.apple.com/documentation/swiftui/progressviewstyle)
- [Apple: Circular progress behavior](https://developer.apple.com/documentation/swiftui/progressviewstyle/circular)
- [Apple: List](https://developer.apple.com/documentation/swiftui/list)
- [Apple: Swipe actions](https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:))
- [Apple: Refreshable](https://developer.apple.com/documentation/swiftui/view/refreshable(action:))
- [Apple: DatePicker](https://developer.apple.com/documentation/swiftui/datepicker)
- [Apple: Presentation drag indicator](https://developer.apple.com/documentation/swiftui/view/presentationdragindicator(_:))

## Questions

1. **Nonstandard capabilities — resolved on 2026-09-17:** The user accepted the
   recommendation to use system-native contracts for standard controls and
   retain separately named custom extensions only for concrete required use
   cases. Audit callers, remove unsupported standard options, and add no
   compatibility paths.
2. **List prerequisite — resolved on 2026-09-17:** The user accepted including
   minimal native List/Section support in this scope for swipeActions and
   refreshable. Generic Collection and application pagination redesign remain
   excluded.

No unresolved product questions remain.

## Implementation

The five selected surfaces now use system SwiftUI controls. The shared
Native_list/Section path supplies stable keyed rows, intrinsic sizing, section
labels, separators and coalesced visible-range observations. Mail uses this path
with its existing application paging reducer; generic Collection is unchanged.

The portable capability matrix is:

| Surface | iOS 18+ | macOS 26+ |
| --- | --- | --- |
| Progress | Automatic activity/determinate, linear determinate, circular activity | Same; unsupported combinations reject |
| List/Section | Keyed intrinsic rows, headers/footers and separators | Same |
| Swipe actions | Native horizontal gesture and full-swipe policy | Native trackpad row actions; mouse dragging is not substituted |
| Refresh | Native List pull gesture and async indicator | Native List async action and toolbar button in a toolbar-capable scene |
| DatePicker | Continuous Gregorian/UTC range, inherited locale ordering | Same, with bounds 1582-10-15 through 9999-12-31 |
| Expanded composer | System sheet/detents/grabber and toolbar roles | Fitted system sheet and toolbar roles |

BSFR/BSIN major version is 9. Progress adds Automatic and rejects indeterminate
Linear/determinate Circular combinations. Swipe actions require native List
rows and retain semantic Button roles and a container full-swipe policy; their
manual gestures, pane geometry, grouping and arbitrary action children are
removed. Refresh accepts the native List path only and retains exact async token
ownership without a button row or pull threshold.

DatePicker uses one continuous Gregorian/UTC range, removes discrete whitelists,
and rejects bounds before 1582-10-15 because Foundation cannot round-trip earlier
cutover dates without normalization. Civil date values themselves retain years
1–9999. This explicit narrowing applies to inline and host date/range pickers.

Expandable composer kind 7 moves to version 3, with explicit
Action/Confirmation/Cancellation roles in a native NavigationStack toolbar.
Closing ends editing before retiring event admission so final IME delivery is
preserved. Inline composer collapse remains separate. The Removal extension
retains its own renamed pan adapter; it is not a standard swipe fallback.

The [acceptance report](../../../../_build/validation/system-controls-benchmark/report.md)
contains the platform/capability matrix, native tests, benchmark method and
remaining interaction limits. The [raw measurement summary](../../../../_build/validation/system-controls-benchmark/summary.json)
preserves all six processes and twenty-four intervals. In the isolated actual
Journal Debug host, median active CPU changes from 21.14% to 2.18% on the initial
64-root page, 19.26% to 1.90% after reactivation, and 19.96% to 2.22% at 500 roots.
All nine candidate active intervals meet the predeclared 10% gate; each interval
lasts at least twenty seconds. This is a controlled native-view comparison in the
consumer's existing runtime, not a BSFR 9 consumer integration or iPhone claim.

No protected spec or Dune file changes. Physical iPhone interaction/performance
is unmeasured because the device is unavailable; native trackpad full swipe,
VoiceOver, large text and system Reduce Motion interaction remain explicit
acceptance limits. Compilation and source use of system controls do not certify
those interactions. No compatibility layer or speculative custom extension is
retained.

### Final validation

- OCaml build/tests/formatting, generated protocol and shared fixtures, viewport
  compile-failure tests, and supported-platform compilation pass.
- All 38 focused control tests pass; independent Mail, native List/Refresh toolbar,
  expandable composer and eight-direction Removal window scenarios pass.
- The broad Swift run completes 550 tests in 115 suites: 549 pass. The remaining
  Sidebar modal-reopen failure reproduces with the identical six assertions on
  an unmodified HEAD snapshot and its separately rebuilt BSFR 8 native runtime.
  No Sidebar change is included in this feature.
- Two unchanged Menu/Shutdown window cases terminate the Swift runner before its
  xUnit document completes; they are excluded from that broad run and remain
  explicit validation limitations. Fresh standalone runs subsequently pass both
  with completed xUnit reports (five Menu tests and four Shutdown modes). The
  unmodified HEAD snapshot also passes them independently. This is not an
  unconditional green shared-process full suite.
- Three independent baseline/candidate performance pairs pass the declared active
  CPU budget, with raw intervals and source/binary identities retained outside
  tracked source. No physical-iPhone or presented-frame-rate result is claimed.

### Local package installation

On 2026-09-17, the user requested a local framework and iOS SDK update.
All three host packages (`bonsai_swiftui`, `bonsai_swiftui_test`, and
`bonsai_swiftui_tool`, version `0.1.0~dev`) were rebuilt in `bonsai-ui` using
explicit path pins, including uncommitted worktree sources. The active switch
remains `bonsai-ui`. All 715 installed resource files match the worktree;
protocol major 9 and removal of `SwipePan.swift` were verified.

Framework SDK `0.1.0~dev.44` and its matching host UI library were installed in
`bonsai-swiftui-ios`; runtime SDK `0.1.0~dev.7` is unchanged. The SDK source
archive is stored under
`~/.local/share/bonsai-swiftui/releases/2026-09-17-system-controls-source/`, with
SHA-256 `9d8d35b013c89300bc4171bc054a471530062411f533f6b050bf6f56550f917a`.
The final package archive, including generated SDK metadata, is under the
sibling `2026-09-17-system-controls-final/` directory, with SHA-256
`b5832088d075fbb80939f27a610f13bc08bb9325f98a1bbbdd59c534ce586bd3`.
These are local immutable archive identities, not published Git commits.

SDK repository reproducibility and installed toolchain verification pass.
Both installed iOS consumer tests pass in 38.302 seconds: an independent
unsigned Release App and Zarith linking. A separate unsigned macOS Debug App
also builds successfully using installed resources. These checks use neither
a framework source override nor an OCAMLPATH override. Logs are preserved in
the final local release's `validation/` directory. No commit, push or device
launch was performed for this local update.
