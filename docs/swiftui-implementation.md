# SwiftUI Backend Implementation Ledger

Historical iOS 18 validation below records earlier runs. The current framework minimum is iOS 26; that evidence does not validate the new baseline.

The governing decision is
[SwiftUI-Only Backend for iOS and macOS](agent-guide/proposed/architecture/2026-09-11-swiftui-only-apple-backend.md).
The full replacement is in progress. This ledger records measured progress,
not a reduced completion definition.
Implementation units below are chronological checkpoints; later entries
supersede earlier unresolved-status notes for the same capability.

Historical commands retain the switch name used when each checkpoint ran.
The host switch was renamed from `bonsai-flutter-v017-exact` to `bonsai-ui` on
2026-09-16. Use `--switch=bonsai-ui` when reproducing those commands today;
see [current testing commands](testing.md#local-commands).

## Latest complete Swift regression

`python3 tool/run_swift_tests.py` passes 482 tests in 106 suites on macOS
(456.630 seconds) after the UIKit keyboard and package-namespace changes. The
runner verifies a fresh completed Swift Testing xUnit report, and 420 recorded
source/binary hashes remain unchanged through the run. The log and hashes are
recorded in `_build/validation/swiftui-current-full-regression.json`.

This full-suite checkpoint predates the scoped-theme and Dropdown Gallery additions. The
later focused environment regression passes five tests in two suites, and the
complete Gallery startup/dispatch case passes separately. The complete suite
has not been rerun for these isolated example additions. Four focused Dropdown,
Gallery and selection tests additionally pass in 7.699 seconds. The full checkpoint
includes real OCaml integration but does not establish physical-iOS interaction, standalone Xcode
UI tests, the complete CI contract or publication. Earlier complete-suite counts
belong to their historical checkpoints.

## Required completion scope

Primary widget API mapping is complete: all 228 baseline public values and 175
named constructors have individual replacement/removal rationales. The final
[navigation/input review](swiftui-navigation-input-api-review.md) reuses the
source-matched macOS regression. Scoped-theme Gallery interaction is now covered
by an actual native-window test. The combined Dropdown scenario also passes at
360- and 620-point widths with real OCaml state and native input. Auxiliary contracts
and physical-device acceptance remain separate requirements.

The [collection measurement report](swiftui-collection-performance.md) adds
macOS timing and sampled-memory evidence for the real 10,003-record mixed
collection. Six fresh processes verify 1,326 updates and native scroll offsets;
measured updates retain at most 21 rows and 61 render nodes. The report separates
initial catalog loading, adjacent windows and distant windows, and states the
remaining physical-input, compositor, self-sizing and iOS limitations. No
runtime implementation or existing test was changed for this diagnostic.

| Workstream | Current state | Required evidence |
| --- | --- | --- |
| User decisions | Resolved | iOS 18+ physical arm64, macOS 26+ arm64, no Simulator; native adapters permitted; all eleven standalone examples; migration-scoped Dune authorization. |
| Native bridge extraction and ABI | macOS runtime and iOS linking verified | Real OCaml creation, frame lifecycle, buffer ownership, restart and new ABI exports pass native tests. Ten physical-iOS App bundles link verified complete objects. Mail now passes its real runtime startup/presentation/restart XCTest on iPhone 13; other device scenarios remain required. |
| iPhoneOS compiler and core runtime | Rebuilt and verified for iOS 18 arm64 | A worktree-local OCaml 5.1.1 cross-compiler passes configuration, compiled foreign-stub/complete-object, installed runtime-object and unsupported-target checks. The rebuilt dependency closure passes the full artifact audit, and ten SwiftUI examples cross-link and sign for physical iOS. Mail runtime execution now passes on a physical iPhone 13; broader device behavior and SDK publication remain unfinished. See [iOS toolchain](swiftui-ios-toolchain.md). |
| Swift runtime coordinator | Implemented and tested on macOS | Process-wide serialized C calls, singleton ownership, pending token barrier, clock validation, close/restart, copied outputs. |
| Startup configuration | Implemented | Only BSR1 1.0 is accepted; old magic, raw entrypoints, malformed lengths, and unsupported versions rejected. |
| Swift protocol generation | Implemented for current schema | Generated Swift compiles and executes; stale output detection works; Dart generation removed. |
| Swift frame transport and event encoding | Implemented for the initial event families | Real OCaml frames decode; malformed transport fails. Press and native text-edit events execute actual OCaml example handlers. Submission, focus and byte-limit payloads encode; a bounded mixed-event queue handles admission and consecutive text-edit coalescing. Visible-range intents encode and coalesce, execute actual Mail window/paging handlers in the native test, and are sampled by BonsaiSession for the public collection in Gallery. Named accessibility actions also execute the actual Gallery handlers through tag 22. Complete navigation-path requests execute actual OCaml handlers through tag 50, including unchanged responses that decline a request. Split column/selection state requests use tag 51 and preserve both fields when consecutive native changes coalesce. Tab selection uses tag 52, including request rejection, keyed reordering and hidden-page input fencing through the actual Gallery component. Picker selection uses signed Int64 tag 53, with disabled-choice rejection and consecutive-choice coalescing. Civil date/time values use tags 46/47 with native controlled selection. Menu actions use signed Int64 tag 54 and preserve every action, including repeated IDs. Animated-opacity completion uses tag 15, current presented bindings and a generation fence. Pointer enter/leave/down/up preserve identifiers, coordinates, device kind and button masks through actual OCaml handlers. Passive AppKit cursor capture is tested through native callbacks and OCaml. A UIKit adapter typechecks, with hover/contact merging tested through actual OCaml; HoverRegion now has presented-input admission, overlap ownership and native Gallery callback/action tests. UIKit runtime behavior, AppKit tablet capture, nonrectangular clipping, large-region performance and actual system dispatch remain unfinished. Remaining event families are unfinished. |
| SwiftUI view model and wire protocol 4.0 | Partial | `View` replaces the public `Widget` module. Button has native enabled/role/style semantics and presentation-gated autofocus. BSFR 4.0 requires exact versions. Swift stages the basic tree atomically; remaining schemas and complete cross-language fixtures are unfinished. |
| SwiftUI rendering and host lifecycle | Basic macOS window host tested | Empty, text, attributed text, SF Symbols, resource/remote images, frame, Spacer, directional padding, background, clip, opacity, row, column, stack, weighted stacks, overlay, native safe-area modifiers, Divider, native text editor, Button, Toggle, Progress, eager horizontal/vertical ScrollView, windowed collections on both axes, accessibility metadata, bounded NavigationStack pages, NavigationSplitView columns, native keyed TabView pages, morphing surfaces, swipe-action containers, controlled single-selection Picker, keyed Toggle groups for multiple selection, action/filter/removable-tag composition, five native control-size scopes, native wrapping Flow layout, native plane projection, animated opacity with completion, composed workflows, native DisclosureGroup, GroupBox, Label, Badge, HoverRegion, controlled civil Date/Time pickers, hierarchical Menu, keyed native toolbar composition, lazy native sections with pinned headers/footers and a leading hero, searchable choice/action composition and scoped environment render through SwiftUI. Picker uses small native AppKit adapters inside SwiftUI to preserve per-option disablement on macOS. Session and AppKit presentation acknowledgment are exercised in native window tests; UIKit adapter sources typecheck. Physical interaction, broader lifecycle scenarios, native services and rendering-performance measurements remain unfinished. |
| Widgets, text, lists, navigation | Initial controls and symbols implemented | Every constructor/variant still needs mapping to implementation, Gallery scenario, and both-platform behavior tests. The native plain-text editor passes SwiftUI/native-control/OCaml integration tests; plain/secure fields, search and both composer variants are implemented with macOS integration evidence; physical-device IME remains outstanding. The public collection catalog/window API, paired wire nodes, BonsaiSession sampling, stable-key anchors, eviction and rehydration pass actual Gallery integration tests. Sparse extents now animate locally with interruption, reduced-motion and session-visibility handling. Mail now uses the catalog/window API for its list, native Scroll for detail and sidebar, and native Tabs/Navigation_split for application navigation. Semantics now supports native metadata, grouping, custom actions and presentation-gated announcements. Progress now supports both styles and determinate/indeterminate modes; Mail uses native plain Buttons for its icon/text actions. Mail now stages its complete tree and passes native window expansion and Archive action tests. Self-sizing, physical gestures and accessibility acceptance remain outstanding. The Symbol subtree has a real OCaml/Gallery rendering test on macOS. |
| CLI, application packaging and public names | Native CLI and Xcode hosts implemented; release packaging incomplete | `bonsai-swiftui` initializes application-owned OCaml/Swift sources and schema-3 configuration, synchronizes generated hosts and builds/runs Apps. An independent generated application passes Debug/Profile/Release builds and actual OCaml state updates in its macOS window. Mail also builds/signs through the CLI with an explicit iOS 18 object. Public packages, modules, the tool directory and all eleven example packages now use bonsai_swiftui; external CLI consumer tests pass. The protected spec-module rename, installed SDK publication and complete CI acceptance remain unfinished. See [native CLI](swiftui-cli.md) and [Xcode hosts](swiftui-xcode-host.md). |
| Eleven standalone examples | Eleven native host builds; macOS Gallery tree/action gate passes; UIKit keyboard capture compiles; device acceptance pending | Counter, Text Input, Navigation, Mail, Clock, Todo, Network, SQLite Worker, Host Effects and Host Navigation have SwiftUI App entrypoints linked to their actual OCaml complete objects; their Flutter hosts/configurations are deleted. Native tests cover Mail inbox/expansion/archive, Navigation system Back, Clock timers, Todo editing/actions, Network TLS HTTP/WSS, SQLite/file persistence across App processes and Host Effects/Host Navigation native clipboard and Settings actions. All ten actual OCaml programs cross-build and their Swift Apps link/sign for physical iOS 18; checkpoint-specific evidence is recorded in the [build matrix](swiftui-example-builds.md). Gallery now has a native macOS App build and an unsigned physical-iOS Release build, and its complete-tree/presentation/toolbar test now passes on macOS after FocusScope and AppKit KeyboardListener implementation. UIKit KeyboardListener now compiles with shared sequence ownership and native window recognizers; its physical keyboard propagation and complete native page interaction/layout remain unfinished. See [Gallery acceptance](swiftui-gallery.md). Mail runtime XCTest now executes on iPhone 13, and its macOS window has actual interaction/capture evidence. Other physical-iOS scenarios and complete visual acceptance remain unfinished. |
| Host services | Clipboard, platform information, window services, URL opening, file dialogs, native text focus, layout measurement, normalized container scrolling, notifications, action menus, haptics and generic request lifecycle implemented; physical interaction incomplete | Typed commands stage atomically and execute after presentation while active; bounded replies reach the actual OCaml example. Native pasteboard tests cover Unicode, transfer limits, saturation, cancellation, delayed replies and restart. Window title and macOS content-size requests execute against the current presentation owner, with native cancellation/ownership regressions; iOS resizing returns an explicit unsupported response. URL requests reach actual registered macOS receiver Apps and share presentation, cancellation and closure fences; see [URL opening](swiftui-url-service.md). The application bridge now has real OCaml request/event, bounded input, cancellation and native-window evidence; see [application bridge](application-platform.md). File import/export now has SwiftUI presentation, scoped copies, byte ownership and actual OCaml callback evidence; see [file services](swiftui-file-services.md). Native focus and layout measurement use presented targets and actual native-control/OCaml tests; see [node services](swiftui-node-services.md). Action menus use a scrollable SwiftUI chooser with typed OCaml results, modal admission and lifetime fences; see [action menus](swiftui-host-menus.md). Other services remain unfinished; see [host services](swiftui-host-services.md) and [window services](swiftui-window-services.md). |
| Mail screenshots | Current macOS captures and physical-iOS Inbox reviewed | September 14 captures use the verified namespace build and explicit Light theme. Four complete macOS states show Inbox, expanded preview, detail and Archived after native actions; the reinstalled iPhone 13 Release App shows matching light navigation/content. The physical UI runner still requires the separate XCTest passcode authorization, so expanded/attachment/swipe iOS scenarios did not execute. Final published-source provenance remains outstanding. See [current capture evidence](screenshots/swiftui-mail/current/README.md). |
| Flutter deletion | Backend source removed; main source/package/module rename verified | The root `flutter/` tree and all eleven old example hosts/configurations are removed. Source discovery finds no Dart files or pubspec manifests; the bridge lives in `native/`. CI rejects restoration of the retired root. The main OCaml packages/modules and CLI directory are renamed without compatibility packages. Bonsai_flutter_spec remains the actual virtual-module name because a protected contract test still references it; three protected spec lines await explicit authorization. The checked-in published SDK snapshot still requires regeneration from pushed source. |
| SDK, source publication, final audit | Not performed | Full requirements audit and, when code is pushed, a separate generated SDK commit from that exact source revision. |

## Completed implementation units

### Native ownership and startup

The C boundary now lives in `native/src/`, with a Clang module named
`CBonsaiSwiftUI`. It exports `bs_*` names and native ABI 3.0; the old `bf_*`
exports are absent from the tested complete object. OCaml callback registration
uses the `bonsai_swiftui` namespace. Dune embeds these sources directly rather
than reading C code from a Flutter package.

`native/test/runtime_fixture.ml` embeds the real OCaml Counter through the
production bridge. `native/test/test_runtime.py` checks actual startup, output
contents, success/no-diff tokens, rejected-frame recovery, duplicate pump
rejection, invalid startup, repeated creation/destruction, and old export
removal. It does not mock the OCaml runtime.

`NativeRuntime.swift` routes all native calls through one process-wide serial
queue. A queued transaction does not suspend while accessing native state.
Every returned buffer is copied and freed before crossing the async boundary.
The wrapper prevents a second owner from replacing an active runtime and
rejects stale acknowledgments or another pump behind an unresolved token.

BSR1 startup envelopes use exact major/minor checks. Legacy BFR1 and raw string
decoding were deleted. Existing OCaml tests were updated to verify that an
invalid startup does not displace the active runtime.

### Generated Swift transport

`protocol/generator/render.ml` emits Swift declarations instead of Dart.
`test_swift_generator.py` runs the real generator in a temporary workspace,
compiles the output with `swiftc`, executes numeric/debug-name assertions,
checks keyword escaping, and verifies that `--check` rejects stale output.

`WireFrame.swift` validates framing, exact version, bounds, operation envelope
order, and known operation IDs. Property and tree validation live in
`NodeStore` and `FrameState`. Its tests decode real OCaml output and reject every truncated
prefix, corrupt header fields, unknown operations, invalid lengths, and
oversized frames. Nonzero-index Data slices are covered.

`EventBatch.swift` now encodes Press, Text_edit, Text_submit, Focus_changed and
Text_limit_reached events. See [native text input](swiftui-text-input.md)
for the text session and real-control/OCaml round trip. The test sends those bytes
through the real C runtime, observes `Count: 0` become `Count: 1`, and checks
that replaying the same event sequence does not execute it twice. A separate
byte-for-byte comparison uses the current shared fixture. Remaining event
payloads and fixture-producer replacement are still required.

### Semantic View API and initial SwiftUI tree

The public OCaml module is now `View`; the old `Widget` module and `pressable`
constructor are removed. `View.button` exposes enabled state, normal/cancel/
destructive roles and automatic/plain/bordered/prominent styles. Disabled
buttons publish no Press binding. Role and style changes participate in
reconciliation. The protocol encodes these properties directly instead of
Flutter overlay colors or release delays.

The active wire header is now BSFR 4.0, with exact major and minor checks in
both OCaml codecs and Swift. The schema still contains other obsolete node
families: version advancement does not mean the schema migration is complete.
OCaml-produced fixtures were regenerated. The seven historical Dart-produced
input fixtures have only had their transport headers updated; replacing their
producer with real Swift event encoders is outstanding. The existing Dart
fixture commands are therefore not a passing validation target.

`NodeStore.staging` constructs a candidate without mutating the displayed
tree. It decodes typed text and Button properties, validates complete property
masks and binding shapes, and rejects malformed identities, missing nodes,
duplicate parents, cycles, unreachable nodes, incorrect child counts and stale
revisions. Traversal is iterative. Unsupported nodes and obsolete parent data
are rejected rather than rendered as placeholders. Application metadata and
host operations are retained explicitly for separate validation; the eventual
host must validate them before publishing the candidate.

`RenderTree` preserves observed node objects across text updates and keyed
reordering, and replaces identity on epoch changes. The first renderer uses
SwiftUI Text, HStack, VStack, ZStack and Button. Tests exercise native
ImageRenderer output and object identity. These are foundational checks, not
the full typography/accessibility/widget visual acceptance suite. Counter's
real OCaml frames stage in this model, and a Swift-encoded Press updates its
text while preserving the Button node. The standalone host implementation is
described below; full renderer performance and widget coverage remain required.

### SwiftUI environment replacement

`Theme.create` now defines color-scheme mode, optional tint and font family,
and native control size. Application roots and local `View.theme` scopes use
the same `Theme.t` and wire structure. Material seed palettes, typography
role bags, density, tap-target sizing and shape contracts were removed from
the theme API and codec. Callers in all examples, runtime helpers and tests
use the new interface; no old theme aliases or decoding paths remain.

The OCaml theme codec round-trips every mode and control size with present
and absent optional values. Swift `FrameState` stages the tree, application
metadata and runtime statistics as one candidate. Missing or duplicate
application metadata, malformed font names, invalid enums and truncated
payloads reject the candidate without changing the previous state. Host and
application service requests are currently rejected explicitly; their typed
decoders and execution remain part of the unfinished service workstream.

`SwiftUIEnvironmentModifier` applies native color scheme, tint, control size
and inherited font selection. The native image test confirms that a descendant
receives dark mode, large controls and its configured font family. Scoped
environment nodes use this same modifier and validate their single child.

The real Counter frame also passes through `FrameState`, `RenderTree` and
SwiftUI ImageRenderer. Its inspected development artifact is
`_build/validation/counter-environment.png`; regenerate it with
`BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation swift test --scratch-path _build/swift --filter realCounterIncludes`.
This is an offscreen render of real OCaml output, not a standalone application
window capture or the required Mail screenshot.

### Application session and native window host

`BonsaiSession` stages complete frames and owns the outstanding presentation
token. It stops additional pumps behind that token, captures Press events from
the displayed revision and handler bindings, retains queued input, and fences
callbacks by a session UUID, runtime epoch, presentation ID and revision.
Visibility and scene activity gate pumping and acknowledgment. A no-diff
transaction acknowledges the unchanged displayed tree without another layout.
Closing invalidates callbacks and clears renderer state before closing the
owned native runtime; restart receives a new session identity.

`BonsaiApplicationView` hosts the native tree and environment. Its view-owned
task pumps while visible and active, reduces polling while inactive, and
closes the runtime on view removal. macOS window titles follow validated
application metadata. Fatal host errors end the session and show a generic
failure state.

`PresentationProbe` uses small AppKit/UIKit representables. A visible native
view schedules a callback after layout and a Core Animation transaction, then
rechecks its captured ticket and visibility before acknowledgment. Successful
tickets are not delivered twice. AppKit window tests cover ticket replacement,
hidden-window suppression and automatic Counter presentation. UIKit is only
typechecked so far; neither these tests nor transaction completion prove
physical-device display timing or mouse interaction.

`tool/build_swiftui_example.py counter` builds the example's own
`native_embed.exe.o`, compiles the local Swift library, links a standalone
arm64 macOS 26 application, and performs ad-hoc signing plus strict signature
verification. The output is `_build/swiftui/counter/BonsaiCounter.app`.
Counter is now included in the root Dune workspace and has SwiftUI native
aliases. Its old Flutter source tree and `bonsai-flutter.sexp` were removed.
The helper is currently a macOS development workflow, not the finished
multi-example CLI or iPhoneOS packaging workflow.

Rendering-performance follow-up remains necessary: object identity is tested,
but whole-tree invalidation under frequently changing presentation tickets and
action closures has not been measured. Use a stable action sink if measurements
show that parent closure changes invalidate otherwise unchanged node views.

`PlatformSupport.swift` rejects Simulator, Catalyst, unsupported operating
systems and non-arm64 architectures at compile time. The platform test
typechecks the gate for physical iOS 18 and macOS 26, and verifies the explicit
Simulator and Intel rejection diagnostics. It also typechecks all current
Swift module sources against the iPhoneOS SDK with an arm64 iOS 18 deployment
target. It does not link the complete OCaml runtime for iPhoneOS or prove
physical-device execution.

The native test dylib is now a declared Dune output. Previously, the shell
script wrote an undeclared file inside Dune's build directory; a later Dune
build removed it and caused Swift linking to fail. The declared rule fixes
that reproducibility issue, assigns an `@rpath` install name, and is enabled
only in the default host context.

### SF Symbols and example integration

`View.symbol ~name` replaces `View.icon`; the old code-point and font-family
arguments, `Icon` node, and its protocol properties were removed. The new
`Symbol` node carries a system name, optional positive point size, optional
ARGB foreground color, and monochrome/hierarchical/multicolor rendering mode.
The OCaml constructor and both wire-codec directions reject malformed names,
invalid sizes and rendering modes. Swift also checks native symbol availability
before accepting the transaction. A missing symbol fails explicitly rather
than producing an empty image.

The renderer uses `Image(systemName:)`, preserves the inherited font and
foreground when overrides are absent, and leaves semantic labels to the
surrounding control or semantics wrapper. Symbol content is decorative.
Native Semantics rendering is now implemented and tested separately; the
symbol tests alone do not establish completed accessibility behavior.

Mail and Gallery now use semantic SF Symbols names throughout their OCaml
views. Gallery includes a dedicated section for all three rendering modes and
inherited styling. The native integration fixture compiles that actual Gallery
source, sends its section through the OCaml/C frame pipeline, and renders the
result in SwiftUI. A separate real OCaml Button test changes star outline to
fill, size, color and rendering mode after a Swift-encoded Press, retaining the
same Swift node object.

Mail and Gallery were removed from the root Dune `data_only_dirs` exclusion,
so the root workspace now builds their OCaml sources and runs Mail's existing
behavior tests against the current framework. Their complete SwiftUI hosts
remain unfinished. No Flutter host or legacy icon decoder was added to keep
these checks passing.

See [the Symbol API notes](swiftui-symbols.md). The inspected artifact
`_build/validation/gallery-symbols.png` shows the actual Gallery section from
its OCaml frame. Regenerate it with
`BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation swift test --scratch-path _build/swift --filter actualGallerySymbolSection`.
It is an offscreen component render, not a Gallery application-window capture
or one of the required Mail screenshots.

### Native frame and Spacer layout

`View.frame` replaces `align`, `center`, `sized_box` and `constrained_box`.
Their node variants and OCaml protocol decoding paths were deleted, along with
`Layout.Box_constraints` and child-size factor properties. The new frame has
optional fixed width/height, min/ideal/max values, nine directional alignments
and an explicit `Layout.Frame_limit.Fill` maximum. Fixed and flexible values
cannot be mixed on the same axis; supplied bounds must be ordered, finite and
non-negative. The wire encodes Fill as a tag, never as an infinite float.

`NativeFrameModifier` applies the native fixed and flexible SwiftUI modifiers.
It adds no Flutter constraint solver or implicit clipping. OCaml reconciliation
updates frame properties in place. The real `frames` application fixture
changes a fixed top-leading frame into a flexible bottom-trailing frame after
a Swift Press and preserves both frame and symbol node objects.

Native layout inspection exposed an important migration difference: an
`EmptyView` remains omitted even inside a fixed frame. A native HStack with an
EmptyView framed to 100 points and a 20-point marker measured only 20 points.
`View.spacer` now exposes SwiftUI Spacer, including its optional non-negative
minimum length. Mail's blank gaps and decoration content, Gallery's blank
layout base and native action-label gaps use explicit zero-minimum spacers.
The native OCaml integration test verifies that a framed spacer reserves the
intended 100-point gap. Empty itself retains native EmptyView semantics.

Gallery's actual `frames_section` covers nine alignments, Fill, min/ideal/max
dimensions and a flexible spacer. Its OCaml source is compiled into the native
fixture and rendered through the production frame pipeline. The inspected
`_build/validation/gallery-frames.png` is a component render, not a standalone
application screenshot. Regenerate it with
`BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation swift test --scratch-path _build/swift --filter actualGalleryFrameSection`.
See [the frame and Spacer API notes](swiftui-layout.md).

These primitives are implemented and rendered in the macOS host; physical
iOS behavior and Mail's layout migration as a whole remain unverified.
Stack positioning, Body/Viewport, Sliver,
transform and presentation surfaces still require replacement. Swift rejects
unsupported node families and parent data rather than treating them as no-ops.

### Native padding, background, clipping, and opacity

`View.background ~color ?corner_radius` replaces `decorated_box` and the
Style.Decoration object. Background is a required ARGB color and continuous
rounded rectangle; it neither changes measurement nor implicitly clips.
`View.clip ?corner_radius ?antialiased` replaces the Clip behavior enum and
save-layer variants. Opacity is a native scalar modifier. Directional
`Layout.Edge_insets.only` uses leading/trailing rather than left/right.
Mail and Gallery callers, typed nodes, reconciliation, driver, schema, generated
protocol, and both OCaml codec paths now use these properties. The old
constructors and enum types are removed without aliases.

The Swift decoder requires finite signed padding, non-negative corner radii, opacity in 0..1,
strict boolean tags, complete update masks, exactly one child, and no bindings.
The native renderer applies the corresponding SwiftUI modifiers. Tests compare
both background orders in LTR and RTL, rounded and rectangular clipping with
antialiasing enabled and disabled, alpha-bearing backgrounds and opacity
boundaries. Invalid or truncated updates cannot publish partial tree changes.
A real OCaml Button changes all four modifiers and verifies native output while
retaining every observed node object.

Gallery's actual `modifiers_section` is rendered in both layout directions.
The inspected component images are
`_build/validation/gallery-modifiers-ltr.png` and
`_build/validation/gallery-modifiers-rtl.png`. The asymmetric inset and leading
alignment mirror in RTL. These are offscreen component artifacts, not Mail
application screenshots. See [the surface modifier API notes](swiftui-modifiers.md).

### Native stack properties, layout priority, and offset

Row/column now carry native optional spacing and axis-appropriate alignment.
The Flutter main-axis alignment/size, cross-axis alignment and text-direction
property declarations have been removed from those schema entries. Stack has
explicit nine-way alignment. The unused Flex/Positioned protocol kind constants
were also removed. The public `View.row` and `View.column` constructors expose
the native properties, and `View.stack` accepts ordinary view children.
`View.layout_priority` and `View.offset` map directly to SwiftUI modifiers.

Row and Column have distinct wire property records and update kind IDs;
the old shared Linear_props form was removed. Spacing, priority and offsets
must be finite, with negative values allowed by these native APIs. Strict
alignment domains and complete property masks are enforced before a candidate
is committed. Priority/offset are event-free single-child nodes. The same
native alignment conversion is used by frames and stacks.

The real `stacks` OCaml fixture changes Row, Column, Stack, priority and offset
in one update. Native image comparisons and object-identity assertions pass.
The actual Gallery `stacks_section` renders in both directions, producing
`_build/validation/gallery-stacks-ltr.png` and
`_build/validation/gallery-stacks-rtl.png`. These are component artifacts.
Positioned parent-data producers and the Body/Viewport API remain unfinished.
Weighted allocation is implemented by the following unit; neither layout
priority nor offset stands in for that contract.

### Native weighted allocation and Flex removal

`View.Weighted.fixed` and `View.Weighted.share ?weight ?fills` describe the
children of a weighted row or column. The container owns its allocation list;
children carry no Flex parent data. Weights are positive finite floats, with
default 1. Shares can fill their proposed main-axis extent or shrink with their
content. Fixed children measure intrinsically. With a finite proposal, remaining
space is divided proportionally after fixed children and gaps. Normalizing by
the largest weight prevents overflow when summing large finite weights.

`NativeWeightedLayout` uses SwiftUI Layout, native adjacent-view spacing and
alignment guides, including first/last text baselines. SwiftUI performs RTL
mirroring; an initial manual mirror was removed after native comparison tests
showed that it double-reversed the layout. EmptyView remains omitted. Unbounded
measurement follows the native proposal received in each pass rather than
freezing a prior measurement when the parent subsequently provides a finite
proposal. All passes are linear in the materialized child count.

The public Flex module, private Flex nodes, integer flex factors and loose/tight
parent-data tags were removed from UI/runtime/protocol code. Mail, Gallery,
Todo and SQLite worker calls now use Weighted. Body's still-pending typed slots
use native weighted allocation with `~weight`; their scroll/presentation nodes
remain unsupported until those families are ported. Positioned parent data has since been removed by the overlay replacement below.

Strict wire decoding checks weights, flags, spacing, alignment, item count,
child count and empty bindings before publication. Real OCaml integration
changes 1:2 shares to 3:1 while reversing keyed children, and verifies native
geometry with every observed node retained. Gallery renders actual horizontal
and vertical weighted compositions in LTR and RTL. The artifacts are
`_build/validation/gallery-weights-ltr.png` and
`_build/validation/gallery-weights-rtl.png`; they are offscreen component renders.

## Verification recorded on 2026-09-11

Completed TDD cycles for the native export/lifecycle boundary, Swift runtime
wrapper, BSR1-only startup, Swift generator, frame transport, and Press encoding:
tests were written first, observed failing for the missing behavior, followed
by implementation, passing tests, formatting, and re-verification.

The following checks passed:

- `dune build @all`
- `dune runtest`, including the existing OCaml/runtime/worker/protocol tests,
  seven network spike tests, and 87 current tool tests. These existing tool
  tests still describe the old CLI and do not prove SwiftUI tooling completion.
- `make swift-test`: five real C/OCaml integration tests, eleven Swift tests,
  generated-file freshness, and the compiled Swift generator integration test.
- `make ci-sanitizers`: the extracted low-level C bridge tests under UBSan.
- Targeted OCaml formatting checks, `git diff --check`, and
  `spec-dev-tool check --all`.

The Xcode 26.1.1 AddressSanitizer runtime stalled before `main` on this host.
A process sample showed recursive ASan initialization through malloc and dyld,
ending in `StaticSpinMutex::LockSlow`. The owned test process was terminated
after this diagnosis. No application test ran under ASan, so ASan is not a
passing check. The current explicit sanitizer selection defaults to UBSan;
`make ci-sanitizers SANITIZERS=address,undefined` is the ASan invocation when a
working host runtime is available. This is a tooling limitation, not evidence
of application memory safety.

The View/Button and basic tree-renderer batch additionally passed:

- The new OCaml disabled-button and reconciliation checks after their observed
  failures; `dune build @all` and `dune runtest` after the API/protocol changes.
- Five real C/OCaml tests and eighteen Swift tests, including typed tree
  staging, malformed graph rollback, real Counter state updates, observed node
  identity and SwiftUI ImageRenderer output.
- The compiled Swift protocol generator test and three platform checks,
  including the full current Swift module's physical-iOS typecheck.
- The native bridge UBSan suite after the ABI/wire-version changes, targeted
  OCaml and Swift formatting, `git diff --check`, and the decision-document
  validator.

The protocol fixture producer and the complete application host are still
outstanding; passing these checks must not be reported as full cross-language
event coverage or completed iOS/macOS applications.

## Verification recorded on 2026-09-12

The environment replacement completed failing-then-passing checks for blank
font rejection, atomic metadata/tree staging, scoped environment decoding,
real Counter metadata, and descendant SwiftUI environment propagation. The
native environment probe initially rendered its failure color and rendered
its success color after the modifier was implemented.

- `dune build @all` and `dune runtest` passed after removal of the old theme
  API and wire structures.
- `make swift-test` passed: five real C/OCaml tests, twenty-three Swift tests,
  the compiled protocol-generator test and three platform checks.
- The entire current Swift module typechecked for physical arm64 iOS 18;
  Simulator and Intel rejection checks also passed.
- `dune exec protocol/generator/generate_fixtures.exe -- --check` passed for
  OCaml-produced fixtures. This excludes the unfinished Swift input producer.
- The real Counter offscreen image was generated and visually inspected. It
  shows the expected Counter text, zero count and purple native Increment
  button without missing content or clipping.

At the end of the environment batch, the host window and presentation adapter
were still outstanding. The following batch addresses their initial macOS
implementation; service execution, broader widget coverage and Mail captures
remain unfinished.

The subsequent window-host batch passed:

- `dune build @all`, `dune runtest`, and `make swift-test` with twenty-seven
  Swift tests, five native C/OCaml tests, the generator test and three platform
  checks.
- Session presentation barriers, stale callbacks, hidden-state deferral,
  queued presses, concurrent pump exclusion, close/restart and no-diff tokens.
- Native AppKit window tests for one-time current-ticket delivery, window
  title publication, automatic Counter presentation/update, and runtime
  shutdown when the SwiftUI host is removed.
- Building and strictly verifying the ad-hoc-signed standalone Counter bundle.

A standalone Counter launch created the expected process. Computer Use could
not inspect it because the Mac was locked and automatic unlock failed. The
user has been asked to unlock manually. The initial process was stopped before
rebuilding the final bundle in this batch; mouse clicks and window screenshots
remain unverified. Do not substitute the earlier offscreen image for that gate.

The subsequent Symbol replacement passed its failing-then-passing constructor,
native renderer, malformed-transaction and OCaml interaction checks. The
Gallery integration test also failed for its missing native entrypoint before
the real Gallery section was connected. The final checks for this batch were:

- `dune build @all @runtest`, including the newly included Mail behavior tests
  and Gallery source build.
- `make swift-test`: thirty-one Swift tests in seven suites, five real
  C/OCaml tests, compiled protocol-generator validation and three platform
  checks. The whole module typechecks for physical arm64 iOS 18; symbol
  availability and rendering have only been exercised on macOS 26 so far.
- Native image comparisons against SwiftUI Image for each rendering mode,
  explicit RGB overrides and inherited font/foreground. Named SwiftUI colors
  are semantic colors, so explicit wire RGB values are compared with explicit
  sRGB reference colors, not `Color.red`/`Color.blue`.
- Targeted OCaml/Swift formatting, generated-file freshness,
  `git diff --check` and `spec-dev-tool check --all`.

The symbol work does not establish complete image-resource handling,
accessibility, Mail rendering, or physical-device behavior. Those gates remain
open in the full migration scope.

The frame/Spacer batch exercised native size proposals, fixed/flexible axis
combinations, zero dimensions, all nine alignments in left-to-right and
right-to-left environments, malformed bounds and transactional rollback.
Real OCaml integration covers incremental frame changes, blank gap sizing and
the actual Gallery section. Each missing constructor, renderer/entrypoint and
Spacer behavior was tested before its implementation.

Repeated native raster comparisons found one antialiased edge pixel differing
by one 8-bit level in two channels. Five diagnostic runs reproduced the same
one-level difference in three runs; the images were inspected. Frame tests
therefore compare exact dimensions and canonical sRGB pixels with at most one
level of per-channel quantization tolerance. Larger differences still fail and
write diagnostic PNGs. This is an observed rasterization tolerance, not a
relaxed layout or identity requirement.

The final frame/Spacer checks passed:

- `dune build @all @runtest native/test/libruntime_fixture.dylib`, including
  Mail behavior tests against the new frame/Spacer API.
- `BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test`:
  thirty-eight Swift tests in eight suites, five real C/OCaml tests, the
  compiled generator test and three platform checks. The current Swift module
  typechecks for physical arm64 iOS 18.
- Generated OCaml fixture freshness, targeted OCaml/Swift formatting,
  `git diff --check`, and `spec-dev-tool check --all`.

The final Gallery frame artifact was regenerated and inspected after Spacer
was added. No standalone Mail window or physical iOS screenshot was produced
in this batch. Protected sources under `ocaml/spec/` remain unchanged.

### Surface modifier verification

The surface modifier TDD cycle first failed with the unimplemented OCaml
background constructor, unsupported Padding/Background nodes in Swift, and
missing native entrypoints. The final batch passed:

- `dune build @all @runtest native/test/libruntime_fixture.dylib`, including
  Mail behavior tests against the new APIs.
- `BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test`:
  forty-three Swift tests in nine suites, five real C/OCaml tests, the compiled
  Swift generator test and three platform checks. The Swift module typechecks
  for physical arm64 iOS 18; physical-device runtime behavior is not verified.
- Generated fixture freshness, source formatting, `git diff --check`, and
  `spec-dev-tool check --all`.

An existing Symbol test failed once when comparing PNG bytes (1571 versus
1567 bytes). Five isolated and eleven full-suite diagnostic reruns did not
reproduce it, so the original pixel difference was not captured or diagnosed.
Symbol comparisons now reuse the frame/modifier raster helper: exact dimensions,
canonical sRGB RGBA pixels, and the previously measured one-level per-channel
quantization tolerance. Transparent symbol backgrounds are retained. Larger
differences save actual/expected PNGs. This improves the comparison basis;
it does not establish the cause of that unreproduced failure.

Both final Gallery modifier images were inspected. No standalone Mail or
physical iOS screenshot was produced, and protected sources under
`ocaml/spec/` remain unchanged.

### Stack and layout modifier verification

The stack batch first failed on unsupported property layouts, missing modifier
nodes, and missing real OCaml entrypoints. After implementation:

- `dune build @all @runtest native/test/libruntime_fixture.dylib` passed,
  including the actual Mail behavior tests and regenerated transport fixtures.
- `BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test` passed:
  forty-eight Swift tests in ten suites, five real C/OCaml tests, one compiled
  generator test and three platform checks. The current module typechecks for
  arm64 iOS 18; Simulator and Intel macOS targets are rejected.
- Tests compare every supported stack alignment in both layout directions,
  default/negative/zero/positive spacing, layout priority under compression,
  offset placement, transactional rejection of malformed updates, and the real
  OCaml multi-container update with stable node identities.
- Final Gallery LTR/RTL component renders were inspected. The constrained row
  retains the primary label and wraps the lower-priority secondary label.
- Fixture freshness, targeted OCaml/Swift formatting, `git diff --check`,
  `spec-dev-tool check --all`, and an empty protected-source diff passed.

The full migration, physical-device execution and Mail screenshots remain
incomplete. The new native containers do not make the legacy Flex/Positioned,
Body/Viewport or collection contracts complete.

### Weighted layout and complete consumer source verification

The weighted tests first failed for unsupported nodes and missing native
entrypoints. The final batch passed:

- `dune build @all @runtest native/test/libruntime_fixture.dylib` and the
  Viewport compile-fail checks after replacing the old Flex API and renaming
  the weighted-child rejection fixture.
- `BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test`:
  fifty-five Swift tests in eleven suites, five real C/OCaml tests, one compiled
  generator test and three platform checks. The module typechecks for physical
  arm64 iOS 18; physical-device execution remains unverified.
- Native geometry checks for fixed and proportional shares, content-sized
  shares, explicit unbounded proposals, zero remaining space, large finite
  weights, empty subviews, native default spacing, baseline/cross alignment,
  and both layout directions. Malformed weighted transactions cannot publish
  partial updates. Real OCaml weight changes and keyed reorders retain children.
- Final Gallery horizontal/vertical weighted images were inspected in LTR/RTL.
  The vertical example explicitly fills its cross axis instead of expecting
  Spacer to provide cross-axis size.

The example source exclusion file `examples/dune` has been removed. All eleven
consumer OCaml libraries and their existing tests are now included in the root
workspace. The expanded `dune build @all @runtest` passed, including the actual
Mail/SQLite worker regressions and all forty-four network policy, TLS, HTTP,
WebSocket, service and example tests. This proves compatibility with the current
source API, not completion of their standalone SwiftUI hosts or native services.

Generated fixture freshness, targeted OCaml/Swift formatting, whitespace,
decision-document validation and the empty protected-source diff also passed.
The full migration and Mail application screenshots remain incomplete.

### Overlay and parent-data removal verification

`View.overlay ~overlay base` and `View.Body.overlay ~overlay body` now use
SwiftUI's two-child overlay modifier. The base determines measurement; the
other child receives its proposal and native alignment. All nine alignments,
oversized content, empty views and both layout directions match direct native
SwiftUI raster references. Signed finite padding supports inset stretch and
outside badges. Non-finite insets still fail validation.

The obsolete positioned Stack module, child wrapper record, parent-data types,
reconciler remount checks, mounted-tree fields and wire tag are removed. Create
payloads end after bindings. Appending the obsolete tag is rejected, and invalid
alignment, child counts or truncated updates cannot publish a partial tree.
The unused Overlay dismissible field and separate navigation alignment enum
are removed. Mail connectors/header actions, Gallery examples, typed Body
consumers and transport fixtures now use native composition.

The tests first failed on unsupported Overlay, negative insets and missing
real OCaml entrypoints. A later Gallery test found the legacy Card wrapper;
the new section now uses native Column. Final validation passed:

- Root `dune build @all @runtest native/test/libruntime_fixture.dylib`.
- `BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test`:
  sixty-one Swift tests in twelve suites, five real C/OCaml tests, one compiled
  generator test and three platform checks, including physical arm64 iOS 18
  source typechecking and rejection of Simulator/Intel targets.
- Real OCaml alignment and signed-inset updates retain every observed node.
  The actual Gallery subtree renders badges, inset regions and corner labels.
  Both `gallery-overlays-ltr.png` and `gallery-overlays-rtl.png` were inspected.

These images are offscreen component renders. Full Mail application execution,
physical iOS validation and the required screenshots remain incomplete.

### Attributed text verification

`Style.Text_span.create` replaces string-only rich-text runs with optional font
size, weight and ARGB color plus italic, underline and strikethrough emphasis.
The existing `View.rich_text` now takes those typed spans. Node 3 contains one
native `Text(AttributedString)`; Unicode/newlines and mixed styles wrap within
one paragraph. Unspecified attributes inherit the native environment. The old
string-list payload is removed. See [native attributed text](swiftui-rich-text.md)
for the API and wire contract.

Initial tests failed on unsupported node 3 and missing real OCaml entrypoints.
An additional isolated invalid-child test exposed a leaf-arity omission; an
exhaustive node-property validation switch now rejects children on rich text.
Final checks passed:

- `dune build @all @runtest native/test/libruntime_fixture.dylib`, including
  constructor validation, styled-run full/update codec round trips, invalid
  sizes and oversized span counts, plus existing consumer regressions.
- `BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test`:
  sixty-six Swift tests in thirteen suites, five C/OCaml tests, one compiled
  generator test and three platform checks. The complete Swift module
  typechecks for physical arm64 iOS 18.
- Native raster comparisons cover mixed styles, Unicode/emoji, wrapping,
  newlines, inherited font/color, empty content and LTR/RTL. Malformed flags,
  sizes, weights, UTF-8, truncated payloads and removed string-only payloads
  reject atomically. Real OCaml updates retain all observed nodes.
- Both final Gallery rich-text renders were inspected. An initial capture
  compressed multiline samples under ImageRenderer's final finite-height
  proposal. The capture now explicitly preserves an unbounded vertical
  proposal; the focused Gallery test passed and all intended text is visible.
  No renderer layout workaround was introduced.

The Counter macOS bundle was rebuilt against the current wire format and Swift
sources with `python3 tool/build_swiftui_example.py counter`; ad-hoc signing and
strict signature verification passed. Generated fixture freshness, root source
formatting, Viewport type checks, whitespace checks, all 49 decision documents,
and an empty protected-source diff passed. No source/SDK commit or push occurred.

The plain-text overflow/line-height vocabulary, input/IME, collections and
remaining widget families still need migration. These component tests do not
complete the Mail application or physical-device screenshot requirements.

### Native plain-text layout verification

`View.text` now uses optional `line_limit`, native Tail/Head/Middle truncation,
and point-based `Text_style.line_spacing`. Font and foreground style inherit
when omitted; explicit weights modify the inherited font. Plain and attributed
text share one font resolver. Flutter overflow modes, fade masking, special
visible painting and line-height multiplication have been removed. Mail and
Clock use explicit point distances. The native API and rationale are recorded
in [text layout](swiftui-text.md).

Tests first demonstrated wrong truncation, zero-spacing rejection, unwanted
font/color overrides and missing OCaml fixtures. The final batch passed:

- `dune build @all @runtest native/test/libruntime_fixture.dylib`, including
  all current consumer source and behavior tests. Plain-text full/update codec
  round trips cover all three truncation tags and absent/zero/positive spacing;
  invalid point distances fail encoding and constructor validation.
- `BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test`:
  seventy-two Swift tests in fourteen suites, five real C/OCaml tests, one
  compiled generator test and three platform checks. The current Swift module
  typechecks for physical arm64 iOS 18 and rejects Simulator/Intel targets.
- Native text raster comparisons cover LTR/RTL, unlimited/one/two lines,
  truncation placement, all paragraph alignments, point spacing, font and color
  inheritance, custom font family and alpha. Invalid enums, counts, sizes,
  spacing and truncated updates cannot publish partial state.
- The actual OCaml fixture updates size, weight, color, line spacing, alignment,
  line limit and truncation without replacing any renderer node. Both final
  Gallery text images were inspected; the intended truncation examples,
  Unicode lines and literal text are visible.

Counter was rebuilt against the current sources; ad-hoc signing and strict
signature verification passed. Generated fixture freshness, source formatting,
Viewport type checks, whitespace and all 49 decision documents passed. Protected
sources remain unchanged, and no source or SDK commit/push was performed.

Plain text and attributed text are implemented on macOS at the component level.
Image resources, input/IME, virtual collections, native services, navigation and
other widget families remain unfinished. No Mail application or physical-device
screenshot is claimed by this batch.

### Native image resource verification

`View.image` now exposes typed resource/remote sources, Original/Stretch/Fit/Fill
sizing and pixels-per-point scale. Size and clipping use existing modifiers;
the old Flutter fit modes and image width/height bag are removed. The node-owned
loader performs bounded asynchronous URLSession loading and ImageIO decoding,
applies orientation, retains same-source resources during updates and reorder,
and cancels obsolete work on source change, removal or session close. A stale
completion cannot replace the current image. Animated images use native-local
monotonic timing and respect Reduce Motion. See [image resources](swiftui-images.md)
for contracts, limits and remaining format/packaging coverage.

Initial image wire tests failed on unsupported node 5. Loading tests exposed
delayed URLSession delivery for one-byte unfinished responses; the final
unfinished-stream tests use a larger partial response and verify rejection
without waiting for the body to finish. A real local TCP server confirms that
rejected streams close their connections. Final checks passed:

- `dune build @all @runtest native/test/libruntime_fixture.dylib`, including
  image constructor validation and create/update codec round trips for both
  source kinds, all sizing modes and multiple scales.
- `BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test`:
  87 Swift tests in 17 suites, five C/OCaml tests, one compiled generator test
  and three platform checks. Current sources typecheck for physical iOS 18.
- Image tests compare native sizing in LTR/RTL, reject malformed/truncated
  properties atomically, exercise cancellation and resource retention,
  validate GIF timing and JPEG orientation, and update image properties
  through the actual OCaml runtime without remounting or reloading.
- The real Gallery image section loads five resources. Both generated PNGs
  were inspected: intrinsic/stretch/fit/fill examples, explicit clipping and
  the animation's first frame are visible. These are offscreen component
  renders, not Mail application screenshots.

The Counter macOS bundle was rebuilt and its strict signature check passed.
Deterministic Gallery assets, generated protocol fixtures, source formatting,
whitespace and all 49 decision documents passed freshness/validation checks.
Protected sources remain unchanged. No source or generated SDK commit/push
was performed. Production resource packaging, iPhoneOS execution, input/IME,
collections, services, navigation and other widget families remain unfinished.

### Native separator verification

`View.divider ()` now renders SwiftUI `Divider`. The parent stack determines
orientation; directional padding supplies spacing and indentation. Native
appearance supplies thickness. `Material.divider`, its orientation type and
all five geometry properties are removed from the active OCaml API and wire
model. Mail, Gallery and catalog callers use the new constructor. Node 105 has
no property payload, children or events. See [layout](swiftui-layout.md).

Tests first failed because node 105 and the Gallery fixture were unsupported.
The focused native tests now pass for row/column/stack orientation, light/dark
appearance, LTR/RTL, padded separators, retained identity on reorder, and atomic
rejection of old payloads, event bindings and children. The actual OCaml Gallery
section renders three separators. Both component captures were inspected;
the row separator, full-width horizontal separator and directional inset are
visible. This does not establish standalone Mail or physical-device rendering.

Final regression checks passed: `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib`; `BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation
make swift-test` (91 Swift tests in 18 suites, five C/OCaml tests, the compiled
generator test, and three platform checks); generated fixture freshness;
Viewport type checks; deterministic image assets; and all 49 decision documents.
Physical iOS sources typecheck, and unsupported Simulator/Intel targets remain
rejected. No protected source edits or source/SDK publication occurred.

### Native editing contract and controller prototype

The input spike now uses one Swift `TextSession` and AppKit/UIKit controllers.
UTF-16 ranges preserve scalar boundaries and exact UTF-8 text; Swift canonical
String equality cannot suppress a document edit. Ack preserves local echo and
composition. Correction applies only at the matching local revision, forced
replacement keeps same-session local revisions monotonic, and repeated/older
updates cannot roll back later typing. A new session resets native state even
when its text is identical.

Native tests found that selection outside marked text ends composition. The
public value constructor and property/event codecs now require nonempty
composition to contain the selection. The proposal records this UI-contract
adjustment; protected ID definitions are unchanged. A second test found that
AppKit notifies composition termination and selection change separately.
Grouping native selection operations now emits the final value once.

`NativeTextController` handles marked-text edits, commits, remote updates,
selection, Return submission outside composition, focus, read-only state,
UTF-8 limits and disposal. Tests drive actual NSTextView APIs and verify
controller release after draining the native autorelease pool. The native
input client sends its encoded edit through the real C bridge to the existing
OCaml text-input example; the canonical value and Ack return unchanged.
Repeated local revisions produce no frame or renderer-revision advance.

The Press-only encoder and API were replaced with typed `NativeEvent` payloads.
This currently covers five event families. The native controller is a tested
prototype; the public field/search/composer APIs, SwiftUI representables,
RenderTree ownership and bounded mixed-event queue are not yet integrated.
The test helper reads the existing example's editing contract directly; it
adds no production Material-node decoder or compatibility path. UIKit sources
are typechecked, not physically exercised. See [native text input](swiftui-text-input.md)
for the exact contract and remaining acceptance work.

The final native-editing batch passed `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib` and
`BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test`:
105 Swift tests in 21 suites, five C/OCaml tests, one compiled generator test
and three platform checks. Current UIKit/controller sources typecheck for
physical arm64 iOS 18; Simulator and Intel targets remain rejected. Generated
fixture freshness, Viewport type checks, whitespace and all 49 decision
documents passed. Counter was rebuilt with the current sources and passed
ad-hoc signing plus strict signature verification. Protected sources remain
unchanged; no source/SDK commit or push occurred.

### Native text editor and standalone Text Input

`View.text_editor` now mounts the retained native editing controller through
SwiftUI. Node 6 encodes the complete native session contract plus editable,
read-only, Return and UTF-8-limit configuration. The decoder validates every
field and required binding before publication. BonsaiSession also prevalidates
remote snapshots against local controller revisions so an invalid future Ack
cannot partially publish a tree.

The mixed event queue bounds both event count and encoded bytes. Adjacent full
edits coalesce only within one node/session/handler/displayed-revision context;
other events preserve barriers. Rejected native edits restore the previous
value and local revision. The actual OCaml example is mounted in NSHostingView:
three composing changes produce one canonical document advance acknowledging
local revision 3, without replacing the native control or its marked text.
Read-only updates, retained identity, invalid snapshots and disposal also pass.

Text Input has a standalone SwiftUI App entrypoint. Its macOS 26 arm64 build
links the example's complete OCaml object and passes ad-hoc signing plus strict
signature verification. The old Flutter host and configuration are removed.
Physical iOS packaging, actual keyboard/IME execution and real-window captures
remain outstanding. Desktop access was checked again and remains locked.
See [native text input](swiftui-text-input.md) for the current public capability
and remaining input migration work.

The editor integration passed `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib` and
`BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test`: 110 Swift
tests in 23 suites, five C/OCaml tests, one compiled generator test and three
platform checks. Physical iOS 18 arm64 sources typecheck; Simulator and Intel
macOS remain rejected. Generated fixture freshness, Viewport type checks,
deterministic image assets and all 49 decision documents also passed.
Protected sources remain unchanged; no source or SDK commit/push occurred.

### Windowed collection geometry and actual Mail paging boundary

The native List experiment is reproducible through
`tool/probe_swiftui_list.swift`. A fixed minimum aligned fixed-height rows, but
an offscreen sparse extent change left the cached table geometry unchanged on
the tested macOS SDK. The proposal now selects a SwiftUI ScrollView with an
explicit layout of only the asynchronously materialized window. This is a
single virtual collection path; generic swipe actions and self-sizing remain
required capabilities. See [windowed collections](swiftui-collections.md).

`CollectionGeometry` validates sparse extents and computes visible/overscan
ranges without constructing every row. `CollectionViewport` records native
geometry and preserves the top row plus intra-row offset across metric updates.
Its owner can supply a relocated index after resolving stable identity. Native
window tests verify a jump to row 7,500 in 10,000 items with only 23 row views,
exact content offsets, offscreen expansion, paging, resize, relocation and
empty-state clamping. No FFI occurs in geometry callbacks or layout.

Typed visible-range events now use the bounded event queue with same-owner
consecutive coalescing. The native test embeds actual `Mail.app` and proves
20 initial rows narrow to an 11-row window. A bottom-range request produces
loading state, retains it at 700 ms, and reaches 40 records with 15 materialized
rows at 800 ms; later clock advancement does not repeat the page. A test-only
helper inspects the current Mail collection descriptor. It is not a production
Sliver decoder and must be removed when Mail moves to the new collection API.

This is the collection prototype and runtime boundary evidence. It does not
complete the public API/schema, production BonsaiSession collection scheduling,
full stable-key/eviction lifecycle, self-sizing, gesture arbitration, animated
expansion, accessibility, physical iOS execution or Mail screenshots.

The batch passed `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib` and
`BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test`: 117 Swift
tests in 26 suites, five C/OCaml tests, the compiled generator test and three
platform checks. Current sources typecheck for physical iOS 18 arm64;
Simulator and Intel macOS remain explicitly rejected. Protected sources remain
unchanged, and no source/SDK commit or push occurred.

### Public collection catalog, window and Gallery integration

`View.Collection.Catalog` validates immutable stable keys, default height,
sparse extent overrides and overscan. `Window.create` bounds the materialized
range; an empty visible range remains empty. `Collection.vertical` requires
keyed row roots matching the declared catalog slice and returns a vertical
viewport. Catalog and window use separate wire nodes, so scrolling publishes
only the materialized window rather than repeating all item metadata.

Swift stages both nodes atomically, including structural ownership, exact
UTF-8 key identity, slice bounds and child counts. The retained collection
controller preserves the top key and intra-row offset when the catalog
changes. Removing that key chooses a surviving neighbor. BonsaiSession samples
mounted collection geometry after presentation, admits typed visible-range
requests through the bounded queue, and retries rejected requests. Layout and
geometry callbacks do not call the OCaml runtime.

The actual Gallery collection component starts with an empty window over
10,000 logical rows. Native integration tests mount it in SwiftUI, hydrate
the first window after presentation, jump to row 7,500, and retain only 23
row views. Scrolling emits a frame below 16 KiB without a catalog operation.
Deleting the first logical row preserves the visible row object and offset;
evicted rows receive new render identities on reentry. Clearing currently
visible content triggers another request instead of suppressing it as a
duplicate. This integrates the public collection path; the full Gallery and
Mail standalone interfaces still require their remaining widget families.

Validation passed `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib` and
`BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test`: 121 Swift
tests in 27 suites, five C/OCaml tests, one compiled generator test and three
platform checks. Current sources typecheck for physical iOS 18 arm64;
Simulator and Intel macOS remain explicitly rejected. Generated fixture
freshness and Viewport type checks also passed. Protected sources remain
unchanged; no source or SDK commit/push occurred. No Mail screenshot or
physical-device execution is claimed by these native window tests.

### Native sparse extent animation through the public collection

The catalog now carries separate expansion and collapse durations. Both OCaml
and Swift use all six catalog properties (mask 63); old four-property payloads
are not accepted. Constructor/codec tests validate unsigned duration bounds
and round-trip nonzero timing through the actual wire representation.

`CollectionAnimation` interpolates sparse heights with direction-specific
cubic timing. New targets begin at displayed heights, independently completing
expanding and collapsing rows. `CollectionViewport` keeps a logical anchor
across samples rather than accumulating native pixel-rounding changes. Native
window tests cover an offscreen expanding row, reversal, the retained visible
row, exact final offsets, reduced motion and removal. SwiftUI scroll phases
identify user movement; rapid physical gestures still need acceptance tests.

Gallery exposes a keyed expandable row with 240 ms expansion and 190 ms
collapse. Its actual OCaml component sends the target once; the native test
withholds subsequent pumps and presentation acknowledgment while Swift finishes
the animation. Session inactivity, hiding and teardown settle to the target
and stop obsolete interpolation. Changing keys, count or default height also
resolves immediately. The locally sampled task does not complete the remaining
foreground display-driver requirement.

See [windowed collections](swiftui-collections.md) for the current API,
interruption policy and remaining acceptance scope. At this checkpoint Mail
still used its previous collection constructor; the following unit replaces
that caller. Its native screenshot gates remain open.

The batch passed `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib` and
`BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test`: 125 Swift
tests in 28 suites, five C/OCaml tests, one compiled generator test and three
platform checks. Physical iOS 18 arm64 sources typecheck, while Simulator and
Intel macOS remain rejected. Generated fixtures, Viewport type checks,
deterministic Gallery assets and all 49 decision documents passed. Protected
sources remain unchanged; no source or SDK commit/push occurred. Actual iOS
execution, standalone Mail rendering and screenshots remain unverified.

### Mail collection migration and ordinary SwiftUI scrolling

Mail's message list now uses `View.Collection` directly. Ordered message keys
and a separate loading-row key define the catalog; sparse overrides carry the
expanded card height with 240/190 ms timing. A Bonsai cutoff reuses the catalog
when only the requested range changes. The bounded keyed window is shared by
row materialization and rendering, with a separate owner key for each mailbox.

The actual Mail tests retain three-page loading, overlapping row identity,
accordion expansion/collapse, nested actions, filtering and detail behavior.
Additional checks compare catalog/window key slices through loading, append and
archive. The Swift boundary test uses the production catalog/window decoders;
the old test-only Sliver property parser is removed. It proves range-only
updates omit the catalog and preserves the 700/800 ms loading boundary. This
still does not stage Mail's complete tree, whose remaining controls are not
implemented by the native renderer.

`View.Scroll.vertical` and `.horizontal` now represent an eager ordinary
subtree in SwiftUI ScrollView. Node 9 validates the axis, indicator flag,
exactly one child and no bindings. The actual Gallery sample scrolls both
axes, grows content, changes indicators and resizes while retaining native
scroll views and offsets. Mail detail, Clock and Todo use this API, with their
Sliver wrappers and inert scrolling handlers deleted. The active source of
these three examples has no Sliver/Scroll_view/Sparse_extent calls. Other
consumers, including Gallery's header, still require migration before global
removal of the obsolete surface.

The Viewport compile checks now exercise native Scroll and Collection. They
retain rejection of unbounded axis/slot placements and require `Keyed.t`
collection items. See [native scroll containers](swiftui-scroll.md) and
[windowed collections](swiftui-collections.md) for the public contract and
remaining platform/interaction scope.

Validation passed `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib` and
`BONSAI_RENDER_ARTIFACT_DIRECTORY=_build/validation make swift-test`: 127 Swift
tests in 29 suites, five C/OCaml tests, one compiled generator test and three
platform checks. Current sources typecheck for physical iOS 18 arm64;
Simulator and Intel macOS remain rejected. Generated fixtures, updated
Viewport type checks, deterministic Gallery assets and all 49 decision
documents passed. Protected sources remain unchanged. No source/SDK commit or
push occurred; physical execution and complete Mail screenshots are still open.

### Native SwiftUI accessibility

Semantics now uses SwiftUI metadata and named actions instead of a fixed
Flutter-shaped action bitset and a generic native-control state bag. The public
API exposes Combine/Contain/Ignore grouping, hidden state, labels/hints/values,
roles, selection, headings, sort priority and identifiers. Actions have stable
positive IDs and nonempty labels, with a 1,024-action limit and duplicate-ID
rejection. The protocol uses a strict twelve-field schema and custom events
carry tag 22 plus the action ID. Mail keeps its existing labels and live-region
intent; Todo and Gallery now express duplicated checked status as explicit
values while native controls own their actual state.

SwiftUI metadata updates retain child renderer identity. BonsaiSession checks
both current and presented action declarations, handler identity, session
visibility/activity and ancestor accessibility visibility. Hidden and ignored
descendants cannot dispatch stale actions or issue live announcements. Live
regions announce changed label/value descriptions after presentation
acknowledgment; initial snapshots and no-diff pumps do not announce.

The actual Gallery accessibility component runs through C and OCaml. Native
NSHostingView tests query SwiftUI accessibility properties, invoke the primary
and Archive custom actions, observe OCaml updates, verify presentation-gated
announcement ordering, and reject the captured action after hiding its owner.
SwiftUI virtual nodes implement public accessibility selectors without formal
NSAccessibilityProtocol conformance; the test helper queries those selectors
and uses a real AX application request to materialize the tree. Tests create
and close their own windows. They do not deliver Mail screenshots or verify
audible VoiceOver output. See [SwiftUI accessibility](swiftui-accessibility.md)
for the API, removed fields, event rules and remaining physical acceptance.

Validation: `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib` passed. The complete native/Swift suite
passed 131 Swift tests in 30 suites, five C/OCaml tests, one compiled generator
test and three platform checks, including typechecking the complete Swift
module for physical iOS 18 arm64. The follow-up ignored-descendant regression
first failed with an unwanted announcement, then passed after visibility
propagation was corrected. The final complete suite passed the same 131 Swift tests in 30 suites and
all C/generator/platform checks. Generated fixtures, Viewport compile checks,
Gallery assets, all 49 decision documents and `git diff --check` passed. No protected source, source/SDK commit or
push was made. Full Mail rendering and physical screenshots remain unfinished.

### Native progress and Mail buttons

`View.progress` replaces Material circular/linear progress and expressive
loading indicators in every current OCaml consumer. The single Progress node
retains its keyed identity across value, style and determinate/indeterminate
mode updates. Value bounds remain strict. The old dedicated Material node
IDs and constructors are removed; Material-specific wavy/contained appearance
is replaced by SwiftUI styles and ordinary composition.

A native ProgressViewStyle supplies percentage-correct circular progress and
indeterminate linear activity on both platforms. It uses scoped tint and
native control size, fills linear progress from the leading edge, and keeps
its 1.4-second activity animation entirely in SwiftUI. Session/scene activity,
view disappearance and Reduce Motion control timeline activity. Native macOS
accessibility retains numeric progress, range and localized percentage,
switching to a busy-indicator role for unknown progress.

The actual Gallery component cycles through 25%, 75%, unknown and 100% using
OCaml handlers. Native tests verify accessibility, identity, painted fractions,
right-to-left fill and activity animation. Window pixel captures show animation
while active and a stable activity mark when the session is inactive; the
presented OCaml revision stays unchanged between those captures. System Reduce
Motion toggling, physical iOS execution and VoiceOver speech remain unverified.
The shared accessibility test support now also serves Semantics tests.

Mail paging uses the new native Progress. All of Mail's ordinary icon/text
buttons use the existing native plain Button surface. The Mail regression
suite verifies the list, preview and detail contain native Buttons without
Material button nodes, in addition to the preserved behavioral tests. Full
Mail still requires native navigation, generic swipe, morphing and remaining
wrapper integration before standalone execution and screenshots.
See [SwiftUI progress](swiftui-progress.md) for public API and wire details.

Validation passed `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib` and the complete `make swift-test` suite:
135 Swift tests in 31 suites, five C/OCaml tests, one compiled generator test
and three platform checks. The complete Swift module typechecks for physical
iOS 18 arm64, while Simulator and Intel remain rejected. Generated fixtures,
Viewport type checks, deterministic Gallery assets, all 49 decision documents
and `git diff --check` passed. No protected source was modified, and no
SDK/source commit or push occurred.

### Native safe-area ownership and transparent modifiers

`View.ignores_safe_area` and `View.safe_area_padding` replace the old SafeArea
node and constructor. Region choices are Container, Keyboard and All; edges
form a directional set. Default native avoidance no longer needs a wrapper.
Padding adds signed finite distances rather than reproducing Flutter minimum
insets. Typed Body and Viewport wrappers preserve their existing axes.
The strict wire nodes reject invalid regions, edges, distances and child or
binding shapes atomically. Mail uses native default avoidance for drawer and
detail and explicit edge extension for content and bottom navigation.

Gallery's actual OCaml component runs through five region/padding states in a
native macOS window. Tests observe real titlebar insets, activate the native
button, compare blue content bounds, resize the window and retain node objects.
Additional native comparisons cover asymmetric and negative padding in both
layout directions. Physical keyboard/home-indicator behavior remains open.
See [Native Safe Areas](swiftui-safe-area.md) for the complete public contract.

A failing native raster regression exposed an existing Spacer layout defect:
conditional view containers, per-node ID wrappers and single-child ForEach
wrappers could turn an expanding Spacer into empty painted content. Runtime
node selection now returns the selected native expression directly, and
single-child modifiers compose their child without a collection wrapper.
Frame modifiers similarly avoid a conditional view boundary. Stateful native
controls and actual child collections retain their explicit identity.
The overlay reference test was also corrected to compare unwrapped native
expressions; its former conditional Group discarded an empty base's overlay.

Validation passed `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib` and the complete `make swift-test` suite:
139 Swift tests in 32 suites, five C/OCaml tests, one compiled generator test
and three platform checks. The complete module typechecks for physical iOS 18
arm64; Simulator and Intel macOS remain rejected. Fixture freshness, Viewport
compile checks, Gallery assets, all 49 decision documents and `git diff --check`
also passed. No protected source was modified; no source/SDK commit or push
occurred. These results do not complete Mail rendering or physical screenshots.

### Native stack paths and the Navigation application

`View.Navigation_stack` adds a typed destination path with titles, stable page
keys and native back policy. The root is outside the path. Ordinary navigation
has its own strict wire nodes, without the old page transition/restoration
fields. A native back operation requests a complete remaining path in one
bounded event. Swift checks prefix membership, every removed destination's
policy, both presented/current ownership and handlers, and session activity.

The retained controller supplies local path feedback only after queue admission
and prevents overlapping unresolved requests. A fresh OCaml path reconciles
that state; an unchanged response restores it. Native bindings capture their
source path so stale transition callbacks cannot pop replacement destinations.
Route identity preserves exact UTF-8 keys alongside runtime/node identity;
canonical-equivalent Unicode replacements are not collapsed by Swift equality.

The Navigation example now uses only native Stack/Destination, Button, Text
and Frame nodes. Its macOS application links its actual complete OCaml object
and passed ad-hoc signing and strict signature verification. The old Flutter
host and configuration were deleted. Its physical-iOS entrypoint exists, but
iPhoneOS packaging and execution are still required.

Actual OCaml integration tests cover push/back, presentation fencing, preserved
root identity, multi-page paths, inactivity and declined requests. Native
window content tests cover destination/root visibility. A separate SwiftUI App
test exercises the system Back toolbar control through its public hosted view
and observes the actual OCaml example return to its root. NSHostingController
alone did not produce scene navigation chrome for either the renderer or a
minimal native reference, so those content tests are not used as toolbar proof.
See [Native Navigation Stack](swiftui-navigation-stack.md) for contracts,
verification commands and the remaining navigation scope.

Validation passed `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib` and the complete `make swift-test` suite:
147 Swift tests in 34 suites, five C/OCaml tests, one compiled generator test,
three platform checks and the new standalone SwiftUI system-Back test. The full
Swift module typechecks for physical iOS 18 arm64; Simulator and Intel macOS
remain rejected. Fixture freshness, Viewport compile checks, Gallery assets,
all 49 decision documents and `git diff --check` passed. Navigation's standalone
bundle also passed strict signature verification. Protected sources remain
unchanged; no source/SDK commit or push occurred. Mail and device screenshot
gates remain open.

### Native split columns and Gallery state ownership

`Navigation.Split_state` and `View.Navigation_split` now describe three native
columns, visibility intent, preferred compact column and an optional selection
key. A strict node and event carry that state directly rather than reproducing
the old drawer shell protocol. Native callbacks carry both column fields and
the observed selection, and consecutive requests coalesce without losing either
field. Responses restore declined changes without a synthetic renderer frame;
an older response cannot clear a newer pending request.

Gallery's actual split component supports selection, clearing, sidebar requests
and declining column changes. Real OCaml tests verify accepted/declined changes,
presentation fencing, retained nodes and teardown. Additional tests cover
malformed fields, exact Unicode key identity, queue rejection, coalescing and
retained bindings. SwiftUI retains split bindings across selection updates, so
freshness is checked against the last getter read. Construction-version checks
incorrectly rejected real system sidebar clicks and were replaced after an App
test exposed the issue. Native Automatic visibility also compares equal to a
concrete case; callback mapping now chooses concrete values first.

The standalone navigation App test runner now compiles once and executes both
system-Back and Gallery sidebar scenarios in separate processes. The sidebar
scenario selects a message, hides/restores the sidebar through its native system
control, observes OCaml state updates and retains selection during resize.
These are actual SwiftUI scene tests, not Mail screenshots or physical compact
navigation evidence. See [Native Navigation Split View](swiftui-navigation-split.md).
Mail's subsequent shell replacement is described in [Mail navigation](swiftui-mail-navigation.md).

Validation passed `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib` and the complete `make swift-test` suite:
153 Swift tests in 36 suites, five C/OCaml tests, one compiled generator test,
three platform checks and two standalone SwiftUI App scenarios. The complete
Swift module typechecks for physical iOS 18 arm64; Simulator and Intel macOS
remain rejected. Fixture freshness, Viewport compile checks, deterministic
Gallery assets, all 49 decision documents and `git diff --check` passed.
Protected sources remain unchanged. No source/SDK commit or push occurred;
Full Mail rendering and physical screenshot gates remain open.

### Native application tabs

`View.Tabs` now supplies keyed items with literal titles, SF Symbols and bounded
`Body.t` content. The public constructor validates unique nonempty keys, a valid
selection and one to 256 items. It supports typed Scroll/Collection bodies
without exposing an unrestricted viewport conversion. Nodes 31 and 40 represent
the controlled TabView and its directly owned pages; event 52 requests a selected
page key. Both language boundaries validate the new properties.

SwiftUI renders `TabView` and `Tab`, with exact UTF-8 selection identity and
retained logical pages. Queue admission precedes native state changes. Local
request serials prevent an older response from clearing a newer request for the
same page; unchanged OCaml responses restore declined selection. Removing a page
invalidates its pending request and stale binding reads.

Actual Gallery integration exposed hidden pages accepting captured callbacks.
The session now checks every enclosing tab against both native selection and
the presented OCaml tree before admitting input. The regression demonstrates
that hidden pages and both sides of an unconfirmed switch cannot change either
counter. Accepted switching, locked rejection, reordering and teardown retain
expected logical identities and state.

The standalone SwiftUI App scenario activates the system tab radio controls,
observes accepted and declined selections through OCaml, and retains Mail's
counter while reordering. The complete native run initially exposed a sidebar
test affected by window restoration. Separate scenario window identifiers and
an explicitly established wide split size fix the test's geometry requirement;
all three standalone App scenarios passed at that checkpoint. A later recurrence
at the correct wide size exposed an additional unchanged-echo binding issue,
resolved in the Mail navigation implementation unit below.

Validation: `dune build @all @runtest @fmt native/test/libruntime_fixture.dylib`
passed, as did 159 Swift tests in 38 suites, five C/OCaml tests, the compiled
protocol-generator test, all three platform checks and all three standalone App
scenarios. Physical iOS 18 arm64 typechecking passed; Simulator and Intel macOS
remain rejected. Protocol fixture freshness, typed Viewport checks, Gallery asset
freshness, all 49 decision documents and `git diff --check` passed. Protected
sources remain unchanged. See [Native Tabs](swiftui-tabs.md).

Mail now composes tabs and bounded split columns; see [Mail navigation](swiftui-mail-navigation.md).
Native scroll-position and focus/IME preservation across tabs, tab animation
suspension, physical iOS interaction, full Mail rendering and Mail screenshots
remain acceptance work. No source/SDK commit or push occurred.

### Mail tabs, bounded split columns and obsolete shell removal

Mail now renders its four logical application pages through `View.Tabs` and
composes mailbox, list and detail columns with `View.Navigation_split`. Split
slots consume `Body.t`, like tab pages, so both scrolling axes and collection
viewports remain typed and bounded. The previous plain-view split signature
was replaced without an overload. Gallery and the Viewport fixture use the new
signature.

OCaml derives the split selection key from the selected message. Mailbox changes
clear old detail and expansion while invalidating stale pagination; application
tab changes retain Mail state. Native returns clear detail only for a matching
observed key, while visibility-only changes preserve selection. The detail has
a placeholder when unselected. Mail no longer uses a combined extension shell,
custom bottom bar, Scaffold/page wrappers, manual root safe-area exceptions or
a 720-point root cap. Unused Navigation_shell OCaml API and body-slot helper,
Dart implementation/export/registration and its obsolete tests were deleted.

The actual Mail behavior suite now uses typed tab/split test events and native
navigation assertions. Existing paging, identity, message actions, expansion,
outline and attachment tests remain. Native Gallery split and tabs still cover
the corresponding SwiftUI renderer through real OCaml handlers.

The complete native run exposed intermittent sidebar rejection even with the
correct 1200-point window. Accepting an unchanged native echo advanced the
binding generation, although SwiftUI had no new value to read; a subsequent
system action then looked stale. Timing-independent tests reproduced this in
both Split and Tabs controllers. Synchronization/resolution now preserve read
generation when visible state is unchanged (and tab page identities remain the
same), while external changes, removed pages and declined requests still fence
stale reads. The system-sidebar App test repeats three hide/show cycles.

The native Mail entrypoint now has a macOS window and iOS WindowGroup. Its
complete-object target has no Flutter environment gate and uses native aliases.
`tool/build_swiftui_example.py mail` builds and strictly verifies the ad-hoc
signed `BonsaiMail.app` against the actual OCaml object. The old Mail Flutter
host and configuration are deleted. This is packaging evidence; the application
cannot yet stage its full view tree.

A second timing issue was isolated with a pure SwiftUI reference window and
native event traces. SwiftUI can report intermediate column states followed by
its final state while an earlier OCaml echo awaits presentation. Requiring exact
column/selection property equality between current and displayed frames dropped
that final intent. Split now fences selection identity, titles, children and
handler; Tabs fences its page identities/metadata, children and handler. Echo
values may differ while the event keeps the actual displayed revision and waits
for acknowledgment. Page-content events require agreement between native,
current and presented tab selection, including a reversal to the original tab.
Two real-runtime regressions prove the final intent is retained without opening
hidden or unconfirmed page input. Temporary diagnostic logging was removed.

Final validation passed `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib`, the complete `make swift-test` suite with
163 Swift tests in 38 suites, five C/OCaml tests, the compiled generator test,
three platform checks and three standalone App scenarios. The sidebar scenario
performs three hide/show cycles and retains its selected message after resize.
The iOS 18 physical target typechecks; unsupported platforms remain rejected.
Fixture freshness, typed Viewport checks, deterministic assets, all 49 decision
documents and `git diff --check` pass. The Mail bundle was rebuilt after the
navigation fixes and passed strict signature verification.

At this navigation checkpoint, Slidable and Morphing_surface were the remaining
renderer gaps. The surface replacement is recorded below. Full Mail native rendering, swipe/morph acceptance, retained native
scroll offset and focus, physical iOS interaction and screenshots remain open.
See [Mail navigation](swiftui-mail-navigation.md). No source or SDK publication
has occurred; protected OCaml sources remain unchanged.

### Native morphing surface and hidden editor input

`View.Morphing_surface` now replaces the built-in native extension kind 5 with
node 41, two retained branches and explicit transition durations. Mail and
Gallery use the new API; the old OCaml extension, Dart implementation,
registration and obsolete transition tests are deleted. The headless Handle
selects the active branch through typed properties. Native runtime tests execute
the actual Gallery component, including retained counters and presentation
fencing. SwiftUI hosting tests cover measured height, accessibility, continuous
reversal, zero duration, Reduce Motion and inactive scenes.

A new regression reproduced native editor input remaining enabled in a hidden
branch. The adapter now consumes the inherited SwiftUI enabled state and
releases focus while preserving its controller, draft and selection. The
reversal regression also exposed replacement advancing the previous animation
beyond its last published value; retargeting now starts at that published value.
See [native morphing surfaces](swiftui-morphing-surface.md) for the precise
contract and physical-IME limitation.

Validation passed the complete Dune build/test/format gates and native fixture
build, then `make swift-test`: 168 Swift tests in 39 suites, five C/OCaml tests,
the compiled generator test, three platform checks and three standalone App
scenarios. The complete Swift module typechecks for physical iOS 18 arm64.
All 49 decision documents and `git diff --check` pass. The Mail app bundle
was rebuilt with the surface replacement and passed strict ad-hoc signature
verification; complete Mail rendering is still unverified.

At that checkpoint, Slidable was the remaining unsupported Mail consumer. Full Mail rendering,
swipe behavior and actual Mail screenshots remain required. No source or SDK
publication has occurred; protected OCaml sources remain unchanged.

## Outstanding prerequisites and next work

The connected-device inventory listed a registered iPhone 13 as unavailable.
Its identifier and signing material are not stored here. Physical-device
execution and screenshots remain unverified; macOS implementation can proceed.

An additional authorization request is pending for three protected source
edits needed by the final rename:

- `ocaml/spec/test/id_contract_tests.ml:3`: replace the module reference
  `Bonsai_flutter_spec.Id` with `Bonsai_swiftui_spec.Id`.
- `ocaml/spec/id.mli:143`: change the local-revision comment from Flutter to
  SwiftUI.
- `ocaml/spec/id.mli:190`: change the host-effect identity comment from Flutter
  to Apple.

No protected source was modified. These edits do not change ID types or their
contracts. Other independent implementation work can continue while the
request is pending.

Next, complete scroll-versus-swipe arbitration and exercise scrolling during extent
transitions, self-sizing and complete Mail accessibility. Finish the remaining
controls, field/search/composer input capabilities, their Gallery scenarios and
native services. Extend standalone packaging to all eleven examples and physical
iOS, then remove the remaining Flutter integration fixtures, hosts, tooling and
dependencies. Mail's complete tree now stages, but that does not complete the
full widget migration, physical interaction or screenshot gates.

### Core swipe actions and Mail native window

[SwiftUI swipe actions](swiftui-swipe-actions.md) documents core nodes 42/43,
public composition and native state ownership. The old Slidable extension
modules, Dart renderer, dedicated Dart tests and package dependency are removed.
Gallery now includes horizontal and vertical containers. Real native Gallery
tests exposed a missing Press route in BonsaiSession; native action emission now
uses the same displayed-revision activation checks as Buttons. Accepted actions,
duplicate suppression, unchanged OCaml responses, disabling and stable identity
pass through the real C runtime.

The actual Mail App window passes inbox rendering, expansion and Archive removal
checks. Native split columns now have useful minimum/ideal widths, including a
340-point minimum Mail content column. The previous development bundle was
rebuilt after the missing create-node encoder was fixed. Native mouse gesture
acceptance remains failing and is documented explicitly in the swipe capability
document. No complete Mail desktop screenshot or physical iOS evidence exists.

The current swipe checkpoint passes `dune build @all @runtest @fmt`,
`make swift-test` (175 Swift tests across 40 suites, native bridge tests, the
compiled protocol generator, physical-iOS source typechecking and four standalone
App scenarios), `spec-dev-tool check --all`, and `git diff --check`. The separate
synthetic mouse acceptance script still fails all three direction/axis scenarios
and remains outside that passing gate. Native accessibility geometry regressions
now verify proportional action sizes and correct RTL placement.

### Unified Boolean controls

[SwiftUI Toggle](swiftui-toggle.md) replaces the Checkbox, Material/Cupertino
Switch and expressive Toggle button OCaml APIs with one controlled core node.
The obsolete node variants, codec branches and schema entries are removed.
Todo and Gallery now construct Toggle labels explicitly; the Gallery includes
all four native styles and accepted/ignored change modes.

Real native tests exposed missing Switch accessibility labels and a disabled
Switch still reporting enabled after label combination. Combining its label
and control before applying the disabled modifier fixes both while preserving
checked state. The native tests exercise all styles, real OCaml responses,
unchanged-response recovery, disabling, retained identity, final intent during
unpresented echoes and stale binding rejection. Remaining Flutter integration
copies are obsolete and still scheduled for deletion with the old backend.

The Toggle checkpoint passes `dune build @all @runtest @fmt`, `make swift-test`
(179 Swift tests in 41 suites, native bridge and generator checks, complete
iOS 18 source typechecking, and four standalone navigation/Mail App scenarios),
`spec-dev-tool check --all` and `git diff --check`. Protected OCaml spec sources
remain unchanged. Physical device, native swipe recognition and screenshot gates
are still open; the migration is not complete.

### Native scalar and interval sliders

[SwiftUI Sliders](swiftui-slider.md) replaces Material scalar/range APIs and old
wire nodes with `View.Slider` and core nodes 45/46. Steps are expressed in domain
units, labels are required, and native appearance replaces Flutter wavy/centered
variants. Both languages validate finite ordered domains and representable
steps. Scalar and interval events use the native queue, presentation fencing
and actual OCaml acceptance/rejection. Gallery includes both controls, a vertical
end-only scalar and accepted/ignored modes.

The native accessibility regression initially exposed scalar adjustments
changing a value while reporting failed actions. A native Slider accessibility
representation fixes the result and retains step semantics. A second regression
exposed overflow preventing adjustment to a finite extreme endpoint; clamping
before arithmetic fixes both positive and negative domains.

The interval now has two keyboard focus targets. Tests traverse the AppKit focus
loop and send native key events through NSWindow. Four axis/direction cases
exercise both endpoints and reverse adjustment. Direct first-responder keyDown
calls bypassed SwiftUI dispatch; correcting the test path and temporarily
removing the implementation demonstrated all four cases failing before the
focus/key implementation was restored. Actual Gallery accessibility operations
verify end-event counts, accepted changes, ignored scalar/range changes,
disabling and retained identity.

Mouse acceptance is not complete. `native/test/test_slider_window.py` runs a
standalone SwiftUI App and requires both successful exit and an explicit PASS
marker. Its four collapsed-interval drag cases currently fail with no input
events. The Swift Testing runner's early exit during queued mouse dispatch is
not counted as success. This separate failing gate remains outside the passing
unit/integration command. Collapsed-thumb drag arbitration, pointer focus and
physical iOS interaction remain outstanding. No Mail screenshot was produced;
the desktop was still locked at the latest user-requested capture check.

The Slider checkpoint passes `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib` and `make swift-test`: 184 Swift tests in
42 suites, five native bridge tests, the compiled protocol generator, all three
platform checks including the complete physical-iOS 18 module typecheck, and
four standalone navigation/Mail App scenarios. All 49 decision documents and
`git diff --check` pass. The separate Slider mouse gate and earlier swipe mouse
gate remain failing; physical-device and screenshot acceptance is incomplete.
Protected OCaml spec sources remain unchanged. No source or SDK commit/push
has occurred, and the full migration remains in progress.


### Native mouse delivery, interval dragging and swipe recognition

The earlier mouse failures were investigated with a pure SwiftUI DragGesture
reference. SwiftUI's window hosting view includes the titlebar; test coordinates
must include the measured content-frame origin. The inactive test windows also
need to explicitly accept activation clicks. Both standalone harnesses now use
these measured coordinates and post events through the normal application event
loop. This is local AppKit event dispatch, without system input injection or
unlocking the user's desktop.

Correct delivery exposed three interval defects: coincident thumbs always chose
the upper endpoint, release-position changes were discarded, and explicit RTL
points were mirrored again by SwiftUI positioning. The implementation now chooses
a coincident endpoint from initial logical travel, keeps it fixed during that
drag, applies the release position and positions the already-mirrored points on
an LTR surface while retaining label direction. Eight App scenarios each perform
six drags and verify exact selection and end-event counts.

Swipe delivery then exposed NSPan reporting zero translation in its should-begin
callback during the first drag event. Its macOS subclass now measures complete
mouse travel before invoking the system handlers; the system recognizer retains
its event-delay and lifecycle responsibilities. All three axis/direction
scenarios pass cross-axis rejection and one full Archive action. The two mouse
scripts are now required by `make swift-test` rather than excluded from it.

Physical iOS, interrupted drags, scroll-versus-swipe arbitration, composed range
controls nested in swipe containers, VoiceOver and actual Mail screenshots remain
open. These local mouse checks do not complete the entire gesture or migration
acceptance contract.

Validation of this checkpoint passed the expanded `make swift-test`: 184 Swift
tests in 42 suites, five C/OCaml bridge tests, the compiled generator, all three
platform checks including the complete physical-iOS 18 source typecheck, three
Navigation App scenarios, the actual Mail window scenario, three Swipe mouse
scenarios and eight interval Slider mouse scenarios. The Swipe cases also assert
that cross-axis input leaves the reveal offset at zero. All 49 decision documents
and `git diff --check` pass; protected OCaml sources remain unchanged. No source
or generated SDK commit/push has occurred.

`tool/build_swiftui_example.py mail` rebuilt the standalone Mail bundle after the
mouse fixes. Strict ad-hoc signature verification passed. Screenshot acceptance
remains pending; no compositor-complete image was captured in this checkpoint.

### Bounded application roots and the Clock example

[Bounded application bodies](swiftui-application-body.md) replaces the ordinary
View argument to `App.View.create` and `Driver.View.create` with `View.Body.t`.
The application window supplies the root bounds. Active applications, tests and
fixtures explicitly wrap plain content with `Body.static`; there is no overload
or alternate legacy path. This allows scrolling roots to shed Material Scaffold
without introducing a replacement slot protocol. Internal body extraction
preserves the existing native tree and axis-specific viewport constraints.

Clock now uses that root body with a heading, native vertical scroll content,
native Buttons, accessible sections and styled containers. Its OCaml-owned exact
and approximate clocks, manual sample, one-shot timers, all four recurring lanes,
restart, frame waits and history are retained. The old Flutter host, managed
adapter and configuration are deleted, and the complete-object target is enabled
without a Flutter environment gate. A SwiftUI App entrypoint replaces the host.

The real-runtime test first failed at the unsupported Scaffold node. After the
view migration it verifies explicit monotonic advances, all timer families,
nonzero starts/completions for each recurring lane, approximation updates,
restart and native presentation acknowledgment. The actual Clock window test
then exposed accessibility combining the whole scroll area into one Button;
using `Children.Contain` preserves the native controls and timer texts. The App
scenario now presses native Buttons and observes presentation waits and a real
three-second sleep through OCaml. It is required by `make swift-test`.

The native clock starts at wall time, so the next absolute five-second boundary
is tested within its proper window instead of assuming runtime creation aligns
with a UTC boundary. Physical iOS packaging and device evidence, the remaining
standalone examples and the complete package/CLI rename remain unfinished.


This checkpoint passes `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib` and the expanded `make swift-test`: 185 Swift
tests in 42 suites, C/OCaml bridge and generator tests, all three platform checks
including the complete physical-iOS 18 module typecheck, Navigation/Mail/Clock
App scenarios and the existing Swipe/Slider mouse scenarios. Viewport compile
accept/reject checks, protocol fixture freshness, `spec-dev-tool check --all`
and `git diff --check` pass. The standalone `BonsaiClock.app` builds through the
shared helper and passes strict ad-hoc signature verification. Five of eleven
examples now have macOS development bundles. No protected spec edits, source
commit/push or generated SDK publication occurred. Mail screenshots and the
remaining migration requirements are still outstanding.

### Native single-line fields and Todo

[Native text fields](swiftui-text-fields.md) introduces public `View.text_field`
and `View.secure_field` constructors, wire kinds 47/49, OCaml frame encoding and
decoding, native staging, retained render controllers and displayed-generation
input admission. The controls use NSTextField/NSSecureTextField and UITextField;
they share the revisioned TextSession contract with the multiline editor.

The first native adapter tests exposed missing event synchronization. Subsequent
checks exposed deferred-only byte-limit rejection and missing theme font-family
propagation. AppKit now validates partial strings before installing ordinary
edits, and the SwiftUI representable applies the scoped font. UIKit uses native
delegate validation and secure-entry mode. Selection capture is deferred until
marked-text mutations finish; acknowledgments preserve native draft/marked state,
corrections replace it, and rejected input restores the previous session.

Renderer tests first failed on unsupported field nodes, then verified retained
fields across keyed reversals, label/prompt updates, invalid-frame rejection,
future-acknowledgment rejection before publication and disposal. Real OCaml
applications initially rendered only multiline editors; after integration, both
field kinds verify pre-presentation rollback, Unicode edit acknowledgment and
submission through the production bridge and BonsaiSession.

Todo's real application initially failed staging at Scaffold. It now uses a
bounded application body, native text fields, Toggles and Buttons. An explicit
Select action and field focus select the item; the native controls are no longer
nested inside an outer row Button. Stable outer row keys retain the same field,
selection and first responder after Reverse. Delete releases the removed field.
The existing OCaml item model and add/edit/complete/reverse/delete behavior remain.

A 360-point window test exposed a title field only 6.5 points wide. Moving each
field above its action row fixes narrow layouts. Both 360- and 800-point windows
exercise Unicode edits, focus/selection, reversal, completion, Add, selection and
Delete. The Todo SwiftUI App entrypoint replaces its deleted Flutter host and
configuration; its native complete-object build no longer needs the Flutter gate.

Validation passes `dune build @all @runtest @fmt
native/test/libruntime_fixture.dylib`, 192 Swift tests in 44 suites, five native
bridge tests, generator checks, all three platform checks including physical-iOS
18 module typechecking, Navigation/Mail/Clock App scenarios, three Swipe mouse
scenarios and eight Slider mouse scenarios. Protocol fixture freshness and typed
viewport acceptance/rejection checks also pass. The new field tests include
ordinary and secure input, native preflight limits, read-only/disabled state,
marked text, revision acknowledgment/correction, submission and font inheritance.

The old Material field API and its remaining consumers still need replacement,
along with keyboard/input-action/autofocus configuration, search and composer
surfaces. Five other standalone examples, remaining widget families, services,
package/CLI/SDK renaming and Flutter removal remain unfinished. UIKit behavior is
not device-verified. The Mac was locked during the latest screenshot check, and no
complete Mail screenshot has been delivered. Protected OCaml spec sources remain
unchanged; no source or SDK commit/push has occurred.

`tool/build_swiftui_example.py todo` generated the standalone BonsaiTodo.app;
strict deep ad-hoc signature verification passed. Six of eleven examples now
have macOS development bundles. All 49 decision documents and `git diff --check`
pass. The bundle compiler still reports existing unused-result warnings in the
accessibility-trait construction; this is not a warning-free Swift build claim.

### Field input traits, presentation-gated autofocus and Material field removal

Native fields now expose `Text_editing.Keyboard` and `Text_editing.Submit_label`
plus a one-shot autofocus request. UIKit maps keyboard and return-key appearance
to native UITextField properties. macOS retains physical-keyboard behavior.
Submit labels describe the key; application submit handlers own actions and focus
navigation. Multiline input remains a separate TextEditor surface.

Autofocus tests first failed because no focus request reached the native control.
Controllers now defer requests until enabled, mounted in a visible window and
admitted by the application presentation. A false-to-true autofocus transition
rearms the request; blur, activation changes and repeated acknowledgments do not.
The real-runtime test then demonstrated that controller support alone was not
enough: BonsaiSession must enable the request only after a matching presentation
acknowledgment. Tests cover that ordering, inactive application rejection,
disabled deferral, rearming and disposal for ordinary and secure controls.

Field wire properties now include keyboard, submit label and autofocus; the full
update mask is 16383. Malformed enum/boolean values, truncated updates and invalid
text snapshots reject atomically. The public OCaml constructors and both native
field kinds share these properties. Plain and secure field runtime tests and the
Todo narrow/wide identity tests continue to pass.

Gallery, Network and SQLite now call `View.text_field`. Their retained text session
and editing callbacks remain intact. Network's WebSocket test first failed because
the headless input helper recognized only Material_text_field; helpers now support
native plain/secure fields and multiline editors. The WebSocket revision and
bounded-transcript scenario passes with the native field.

The Material TextField public/private constructors, variant type, logical node,
wire record, codecs, schema entry and generated identifiers are removed. Existing
incremental-edit, byte-limit, surrogate-range and marked-selection tests now
exercise native field payloads. The protocol fixture is renamed to
`ocaml_bounded_text_field.hex`, and its obsolete predecessor is deleted. The
experimental catalog expresses its former multiline field as TextEditor with
separate heading/adornment/supporting text and an explicit height.

This checkpoint passes the complete OCaml build/test/format gates, native runtime
fixture build, 194 Swift tests in 44 suites, C bridge and generator tests, all
three platform checks including the complete physical-iOS 18 module typecheck,
Navigation/Mail/Clock App scenarios and the three Swipe/eight Slider mouse
scenarios. Protocol fixture freshness, typed viewport checks, all 49 decision
documents and whitespace checks pass. Todo's standalone macOS bundle is rebuilt.

Search and composer integration, five remaining standalone examples, remaining
widget/service families, package/CLI/SDK renaming and the complete Flutter tree
removal remain unfinished. Historical Flutter files are not an alternate supported
renderer. iOS keyboard behavior, manual IME and VoiceOver still need physical
acceptance. The latest desktop check again found the Mac locked; no complete Mail
screenshot was captured. Protected OCaml spec files remain unchanged. No source
or generated SDK commit/push occurred.

### Network SwiftUI port and embedded Worker signal ownership

Network now uses native Buttons and a revisioned TextField in a bounded SwiftUI
ScrollView. Its production OCaml Worker, HTTPS/TLS/WebSocket providers, request
cancellation, endpoint policy, bounded preview/transcript and draft revisions
remain in place. The previous Flutter host and consumer configuration are
removed. The native fixture embeds the actual Network module and a separate
loopback entrypoint with test endpoints and a fixture trust anchor.

The real window test first rejected the old Scaffold node. After replacing the
view composition, it exposed a field-disablement defect: SwiftUI overwrote
NSTextField.isEnabled during mounting. Native field nodes now propagate their
enabled state into SwiftUI's environment. The window scenario covers initial
and disconnected disablement, connection-driven enablement, Unicode WSS echo,
retained native field identity and a 360-point layout, along with HTTP success,
cancellation of an incomplete response and protocol failure.

Linking the actual TLS closure exposed unresolved GMP symbols. The shared
macOS development linker now stages static libgmp.a into the complete object and
rejects unresolved GMP symbols before linking the final application or test
runtime. The Network providers do not depend on a host GMP dynamic library.

The first complete Swift regression then crashed in caml_interrupt_self on a
foreign main thread. Eio's command-line entrypoint installed a process-wide
SIGCHLD handler. A separate-process native ABI probe reproduced the crash for
both default and custom host signal dispositions. The embedded Worker now
assembles the pinned Eio backend without that handler or a subprocess manager;
its public environment retains the other service capabilities. SIGPIPE is
blocked on the owned Worker thread rather than ignored process-wide. See
[embedded Worker](swiftui-worker.md) for ownership and dependency details.
Both foreign-thread signal scenarios now pass during and after runtime lifetime.

A Worker fairness test also assumed that sixteen producer sends would fill two
batches before the concurrent consumer emptied the queue. It now preloads that
workload behind its existing Hold barrier and retains the ordering and yield
assertions. Ten separate-process runs pass after this synchronization change.

The final checkpoint passes `dune build @all @runtest @fmt` and the native
fixture build, all 195 Swift tests in 44 suites, six native ABI tests, generated
Swift protocol validation and three platform checks including the complete
physical-iOS 18 Swift module typecheck. Navigation's three App scenarios,
Mail/Clock/Network window scenarios, three Swipe mouse scenarios and eight
Slider mouse scenarios pass. Network's standalone BonsaiNetwork.app is built and
passes strict deep ad-hoc signature verification, macOS 26 deployment metadata,
unresolved GMP/OpenSSL symbol checks and system-only dynamic dependency checks.
Seven of eleven examples now have macOS development bundles.

Protocol fixture freshness, typed viewport checks, all 49 decision documents and
whitespace validation pass. Protected OCaml spec files remain unchanged. The
bundle build still reports the existing accessibility-trait unused-result
warnings; no warning-free build is claimed. Four standalone example ports,
remaining widgets/services, package/CLI/SDK naming, old CI consumer contracts,
complete Flutter removal and physical iOS acceptance remain open. The requested
Mail screenshots are still missing because the Mac is locked and no physical
phone is available. No source or generated SDK commit/push occurred.

### SQLite Worker SwiftUI port and system SQLite linking

SQLite Worker now has a bounded SwiftUI body with native Buttons, a revisioned
TextField, native progress and separate Todo/startup/file panels. Foundation
prepares the application-specific support directory and SWC1 payload; database
and file operations continue to run in the actual OCaml Worker service. The old
Flutter host and configuration are removed. Native tests embed the production
SQLite example, service, store and file implementation rather than a replica.

The initial native staging test rejected the old Scaffold node. After the view
port, the actual window test found that Add cleared the OCaml title but left the
native input unchanged: the old application sent an acknowledgment for a remote
text replacement. Add now emits Correction, and subsequent edits return to Ack.
The window test retains the same native control and verifies the corrected value.

Two separate App processes exercise Unicode paths and titles, insert/complete/
refresh/reopen actions, a missing-file error and writing/reading the deterministic
4 MiB file. The test checks SQLite integrity and persisted completion state after
each process, compares every file byte, rejects leftover temporary files, checks
field disposal and verifies a 360-point layout. Existing controlled OCaml tests
continue to cover file cancellation and cleanup; the native window scenario
checks disabled idle cancellation, not an in-flight cancellation gesture.

The new native fixture initially failed to locate libsqlite3 during complete-object
linking, then exposed unresolved SQLite symbols at the final dynamic link. Dune
now discovers the supported target's Apple SDK and emits its system-library
search flag. The native staging/build helper selects system libsqlite3 when the
object requires SQLite. The development helper also includes each example's
Swift support files alongside App.swift, allowing startup preparation to remain
application-owned rather than becoming a framework-specific SQLite API.

The physical-iOS Swift gate now emits the framework module and typechecks all
available standalone App entrypoints against it, including SQLite startup code.
This checks Swift SDK availability and imports; it does not establish native
OCaml cross-linking or any physical-device execution.

The final SQLite checkpoint passes the full OCaml build/test/format gates and
native fixture build, 196 Swift tests in 44 suites, six native ABI tests,
generated protocol validation and all three platform gates. Navigation's three
App scenarios, Mail/Clock/Network window scenarios, the two-process SQLite
persistence scenario, three Swipe mouse scenarios and eight Slider mouse
scenarios pass. All eight standalone Swift entrypoints typecheck against the
physical-iOS 18 framework module. Protocol fixture freshness, typed viewport
acceptance/rejection, all 49 decision documents and whitespace checks pass.

BonsaiSqliteWorker.app passes strict deep ad-hoc signature verification,
macOS 26 metadata checks and system libsqlite3 linkage verification. Eight of
eleven examples now have macOS development bundles. Existing accessibility-trait
unused-result warnings remain. Gallery, Host Effects and Host Navigation,
remaining widgets/services, package/CLI/SDK naming, CI consumer/device contracts,
complete Flutter removal, physical iOS native acceptance and requested Mail
screenshots remain unfinished. Protected OCaml spec files remain unchanged.
No source or generated SDK commit/push occurred.

### Host Effects SwiftUI port and native clipboard lifecycle

Host Effects now uses native Buttons and a bounded scrolling status panel. Its
standalone SwiftUI App embeds the original OCaml host-effect request flow; the
old Flutter host/configuration are deleted. Swift stages typed clipboard
requests and cancellation alongside the complete view transaction, rejecting
malformed, unsupported or duplicate commands before any effect executes.
Accepted request IDs retain a bounded high-water mark across same-epoch resyncs.

Commands execute only after successful presentation acknowledgment while active
and visible. The dispatcher bounds outstanding work, emits typed cancellation
and error replies, and fences late completions across cancellation and runtime
restart. Host responses use zero UI identities and never coalesce. Replies that
finish while a newer frame awaits presentation are rebased to the displayed
revision before the next pump; ordinary UI events retain their original revision.

Initial real-runtime staging rejected the obsolete Scaffold node and unsupported
host operation. Focused tests first failed for command handling, native service
execution and response encoding. After those paths were implemented, an exact
1 MiB Unicode clipboard read exposed a second failure: adding a status prefix
overflowed the rendered text limit. The example now limits its preview to 4096
UTF-8 bytes without splitting a code point; the full host transfer limit remains
1 MiB.

Native tests use real named NSPasteboards and the production OCaml example.
They cover empty/Unicode/boundary transfers, oversized rejection, saturation,
same-frame cancellation without mutation, delayed replies across presentation,
close/restart and presentation/activity gating. The native App window scenario
presses Read and Write and verifies OCaml status at normal and 360-point widths.
Named test pasteboards are released without accessing the user's general one.
See [host services](swiftui-host-services.md) for the full contract and remaining
service families.

The Host Effects checkpoint passes the OCaml build/test/format and native fixture
gates, 206 Swift tests in 47 suites, six native ABI tests, generated Swift protocol
validation and three platform gates. All nine available standalone Swift App
entrypoints typecheck against the physical-iOS 18 framework module. Navigation's
three App scenarios, Mail/Clock/Network/Host Effects windows, the two-process
SQLite persistence scenario, three Swipe mouse scenarios and eight Slider mouse
scenarios pass. Protocol fixture freshness, typed viewport checks, all 49 decision
documents and whitespace validation pass. Protected OCaml spec files remain
unchanged.

BonsaiHostEffects.app passes strict deep ad-hoc signature verification, macOS 26
metadata checks and system-only dynamic dependency inspection. Nine of eleven
examples now have standalone macOS development bundles. Existing accessibility
trait unused-result warnings remain. Gallery and Host Navigation, other widgets
and host services, the application bridge, package/CLI/SDK naming, old CI/device
contracts, complete Flutter deletion and physical iOS native acceptance remain
unfinished. The requested complete Mail screenshots are still missing; the most
recent desktop check confirmed a locked Mac. No source or generated SDK
commit/push occurred.

### Host Navigation SwiftUI port and covered-page input fencing

Host Navigation now uses native Buttons, an OCaml-owned NavigationStack path
and the shared clipboard service. The standalone app and native test fixture
embed the same exported production App. The old Flutter host/configuration and
embedding environment gate are removed. Settings retains the OCaml-owned stack
and inline information content through native text, a divider and a column.
The old Material alert had no actions or presentation state; this port does not
establish the still-required modal presentation behavior.

The initial real-runtime test rejected the old node kind 66. After replacing the
page tree, it exposed a shared navigation bug: controls on the covered home page
still admitted input, as did both departing and newly revealed content during
an unacknowledged native pop. Four assertions reproduced those failures. The
session now walks navigation ancestors and requires content to belong to the
top page in both the presented tree and the native path, with matching ownership
and destination properties. Async host responses remain independent of visible
page content.

The production example regression verifies a delayed Unicode clipboard read
while entering Settings, retained home/control identity after Close, native Back,
hidden-page and speculative-pop input rejection, empty/maximum-size reads,
oversized native errors and restart. The displayed preview is bounded to 4096
UTF-8 bytes without splitting code points. Its App window scenario presses Read,
Open settings, Close settings and the actual system Back toolbar control at
640- and 360-point widths. After Back, it waits for OCaml to remove the destination
and acknowledge presentation, rather than accepting optimistic native path
feedback as evidence. The named test pasteboard is released without touching the
user's general clipboard.

BonsaiHostNavigation.app passes strict deep ad-hoc signature verification,
macOS 26 deployment metadata and system-only dynamic dependency inspection.
Ten of eleven examples now have standalone macOS development bundles. The
OCaml build/test/format and fixture gates pass; 207 Swift tests in 47 suites,
six native ABI tests, generated protocol validation and three platform checks
pass, including all ten App entrypoints against the physical-iOS 18 Swift module.
The complete native App window regression passes: Navigation's three scenarios,
Mail, Clock, Network, the two-process SQLite persistence scenario, Host Effects,
Host Navigation at both widths, three Swipe mouse scenarios and eight Slider
mouse scenarios. Protocol fixture freshness, typed viewport checks, all 49 agent
documents and whitespace checks pass. Protected OCaml spec files remain unchanged.

Gallery, remaining widgets/services, application bridge, package/CLI/SDK naming,
old CI/device contracts, complete Flutter deletion, physical iOS native acceptance
and complete Mail screenshots remain unfinished. No source or generated SDK
commit/push occurred.


### Core Picker and complete Swift test reporting

`View.Picker` replaces `Material.Radio_group` and the single-selection Gallery
segmented controls. Automatic, Menu, Segmented and Inline share signed option
IDs, optional initial selection, stable keyed label children, per-option
permission and controlled OCaml responses. The old public constructor, private
node and generated wire names are removed. Node 116 and event 53 carry the new
contract; multi-selection remains a separate outstanding replacement.

macOS reference controls reproduced ignored per-option disabled modifiers in
SwiftUI Picker. Small NSViewRepresentable adapters now supply NSPopUpButton,
NSSegmentedControl and radio buttons inside SwiftUI. Native targets restore
selection after rejected admission and release their references on teardown.
The production Gallery section exercises all four styles, rejection, disabling,
option reordering and clearing. Actual OCaml integration first exposed a missing
event-dispatch mapping and positional label reuse; both were fixed. It also
verifies final intent across an unpresented response, stale callbacks and close.

The App window acceptance presses native radio and segmented accessibility
choices at 640- and 360-point widths and verifies accepted/rejected requests,
selected-state restoration and disabled options. Popup tests inspect actual
NSMenu item enablement and invoke the native control target/action. Physical
menu-pointer and keyboard acceptance are not implied by these tests.

Native cell tracking in a bare SwiftPM async main loop queued CFRunLoopStop and
ended the process with exit status zero before the suite completed. Tracing
located the exit in the native cell accessibility press path. Those interaction
tests now run under a real SwiftUI App event loop, preserving standard native
controls. The full Swift suite subsequently completed: 212 tests in 48 suites.
`tool/run_swift_tests.py` also requires the fresh Swift Testing xUnit report,
matching completed case counts and no failures/errors. It rejects absent,
truncated, inconsistent, all-skipped and unrelated XCTest reports; an old report
cannot mask early exit. Ten subprocess regression tests first reproduced the
missing completion guard and now pass.

The complete `make swift-test` gate passes with the report guard enabled: 212
Swift tests in 48 suites, six native ABI tests, generated Swift protocol checks,
three platform checks including all ten physical-iOS App entrypoints, and every
native App window scenario including Picker. The OCaml build/test/format,
generated fixture and typed viewport gates pass. All 49 decision documents and
whitespace checks pass. Mail was rebuilt from the current sources and passes
strict deep ad-hoc signature verification, macOS 26 deployment metadata and
system-only dynamic dependency inspection. Physical iOS per-option behavior
remains unverified. Ten standalone macOS
examples are available; Gallery still needs its complete port. Other widgets,
services, application bridge, package/CLI/SDK naming, obsolete CI/device paths,
complete Flutter removal, physical iOS native acceptance and complete Mail
screenshots remain unfinished. Protected OCaml spec files remain unchanged.
No source or generated SDK commit/push occurred.


### Multiple selection through native Toggle composition

The remaining multi-selection segmented capability now uses keyed native
Toggle groups with shared OCaml membership state. Single selection stays in
Picker. Each choice handler applies its Boolean request to current state;
independent choices in the same batch or across a pending presentation do not
replace one another with a captured selected-ID array. Button and Checkbox
styles share the same set, accept SF Symbol/text composition, preserve identity
when reordered and independently disable unavailable choices.

`Material.Segmented_button`, its private view node, wire node 125, segment
metadata and dedicated property encoder/decoder are deleted. Its constructor-
and codec-specific tests are removed with the obsolete contract; the actual
Gallery regression replaces their controlled-selection coverage. Event 35 still
serves unported expressive controls, so it remains until those capabilities are
replaced. Multiple selection uses the existing core Boolean event and has no
new wire node, adapter or parallel state controller.

The production Gallery section is included in its combined view and exported
to the native fixture. The initial actual-runtime test failed on unsupported
node 125. Its replacement verifies simultaneous independent choices, final
intent across an unpresented response, agreement between styles, stable keyed
control/label identity after reversal, repeated rejected requests, disabling,
stale callbacks, clearing and close. An additional failing assertion ensured
that icon/text labels were restored before the scenario passed. The App window
test drives native buttons and checkboxes at 640 and 360 points and checks
multi-selection, deselection, rejection restoration and disabled elements.

The OCaml build/test/format, generated fixtures and typed viewport gates pass.
The complete `make swift-test` gate passes: 213 Swift tests in 48 suites with
fresh completion reporting, six native ABI tests, generated protocol checks,
platform checks and every native App window scenario, including the new
multi-selection scenario with composed labels. Physical iOS module and all ten
App entrypoint typechecks pass; this is not physical-device behavior or native
OCaml linking evidence. All 49 decision documents and whitespace checks pass. See [multiple selection](swiftui-multiple-selection.md).

The standalone example count remains ten of eleven. Full Gallery, other
widgets/services, application bridge, package/CLI/SDK naming, obsolete CI/device
paths, complete Flutter removal, physical iOS native acceptance and requested
Mail screenshots remain unfinished. The Mac was last confirmed locked; no new
complete screenshot is available. Protected OCaml spec sources remain unchanged.
No source or generated SDK commit/push occurred.


### Native actions, filters and removable tags

The Material Chip family is replaced by ordinary Button and Toggle composition.
Actions use native Bordered/Prominent Buttons; selected actions and filters use
Button-style Toggles. A selectable input tag is a keyed row with a Toggle and,
when removable, a sibling removal Button. The removal target stays outside the
Toggle label, so input ownership does not turn removal into selection. Labels
compose SF Symbols and text. OCaml owns membership, selected state, enablement,
request acceptance and restoration.

The public Chip constructors, four private nodes, wire kinds 119–122, property
codecs and dedicated Delete event 34 are removed. Removal now uses ordinary
Press. Obsolete constructor/codec tests and the unused temporary Material
expressive catalog source are deleted with the removed contracts. No Chip
wrapper, native adapter or special state controller was introduced. The real
Gallery tag section is included in its combined view and native test fixture.

The initial integration test failed on unsupported node 119. Its replacement
verifies action counts, independent Boolean choices, keyed control/label identity
on reversal, repeated rejected selection/removal, disabled and stale callbacks,
selection and removal in one batch, unaffected sibling state, restoration and
close. Restoring a deleted tag produces a new runtime identity and does not
reactivate its old callbacks. One tag intentionally has no removal action.

The App test exercises actual native controls at 640 and 360 points. An initial
failure was traced to the test reading static text from accessibility label;
macOS exposes that text through accessibility value. Correcting the test query
allowed the native scenario to verify action counts, selected state, independent
deletion, request rejection, disabled elements and restoration. Both widths
pass with composed symbol/text labels. See [tags](swiftui-tags.md).

The OCaml build/test/format, generated-fixture and typed viewport gates pass.
The complete `make swift-test` gate passes: 214 Swift tests in 48 suites with
fresh completion reporting, six native ABI tests, generated protocol validation,
three platform checks and every native App window scenario, including tags.
The physical-iOS Swift module and all ten App entrypoint typechecks pass. These
are not device behavior or native OCaml linking evidence. All 49 decision
documents and whitespace checks pass. Protected OCaml spec sources remain
unchanged.

The standalone example count remains ten. Full Gallery, remaining widgets and
services, the application bridge, package/CLI/SDK names, obsolete CI/device paths,
complete Flutter deletion, physical iOS acceptance and complete Mail screenshots
remain unfinished. No source or generated SDK commit/push occurred.


### Native control-size scopes and core button consolidation

`View.control_size` now supplies the five SwiftUI control sizes to a subtree.
Nested scopes override inheritance; changing the scope preserves mounted button
and label identities. Node 55 validates a required bounded enum and one child,
with atomic rejection of invalid values, arity and truncated updates. No new
input event or state controller is needed.

The dedicated Material icon-button constructor and the public Cupertino module
are deleted, together with private nodes, wire kinds 100/112, property codecs,
exports and obsolete constructor-specific tests. Their actual Gallery uses now
compose core Buttons with text or explicitly labeled SF Symbols. The remaining
Material buttons and floating-action families still expose autofocus and are
not yet migrated. A temporary native focus probe could not obtain a key window
in the locked desktop session; a local FocusState flag did not establish Space
activation. No production button-focus implementation or keyboard acceptance is
claimed by this checkpoint.

The new size tests first failed on unsupported node 55; the actual Gallery
integration first failed on old Cupertino node 112. Native macOS measurements
now match equivalent SwiftUI Buttons for all five sizes and nested overrides.
The real OCaml integration verifies activation, size changes, stable identity,
disabling, hidden input and close. A native App scenario presses Automatic,
Bordered, Prominent and icon-only Refresh controls forty times across five
sizes and two window widths, and checks accessibility labels and disabling.
See [control size and buttons](swiftui-control-size.md).

The complete `make swift-test` gate passes with 217 Swift tests in 49 suites
and a fresh completion report, six native ABI tests, protocol generation, three
platform checks and every native App scenario. The final Slider scenario
completed successfully and no test process remains. OCaml build/test/format,
generated fixture and typed viewport checks pass. Mail was rebuilt from the
current sources.
The physical-iOS Swift module and all ten application entrypoints typecheck;
this does not establish physical-device behavior or native OCaml linking.
Control-size coverage establishes native macOS Buttons, not every custom
UIKit/AppKit adapter's response to that environment.

Ten standalone macOS examples remain available. Full Gallery, other widgets
and services, the application bridge, package/CLI/SDK names, obsolete CI/device
paths, complete Flutter removal, physical iOS acceptance and complete Mail
screenshots remain unfinished. The desktop is still locked. Protected OCaml
spec sources remain unchanged. No source or generated SDK commit/push occurred.


### Native wrapping layout for finite control groups

`View.flow` now composes finite keyed children through a custom SwiftUI Layout.
It uses the proposed width to form top-aligned rows, with separate item and line
spacing and native Leading/Center/Trailing alignment. A long child label can
wrap within its proposed width; fixed oversized items occupy a row without
implicit clipping. Empty, zero-width and unconstrained cases are defined.
The layout performs linear passes over materialized children and retains each
child measurement for placement. It adds no scroll state or input controller.

Wire node 56 uses required spacing, line spacing and horizontal alignment.
The OCaml constructor and wire encoder validate finite non-negative spacing;
the Swift decoder validates the same contract before atomic publication.
Gallery's existing keyed tag rows now share one flow container. Native resizing
reflows the same controls without an OCaml event. The former tag action and
selection/removal behavior remains in its existing OCaml handlers.

The initial four renderer tests failed on unsupported node 56, and the actual
Gallery integration failed because its tree contained no flow. The real App
geometry test also failed: Work and Personal still occupied separate rows at
640 points. Renderer tests now compare exact width boundaries, mixed heights,
all alignments and both layout directions with explicit native stack rows.
They cover empty/unconstrained/zero-width/oversized content, multiline labels,
identity on property updates and malformed transaction rejection. The actual
Gallery test retains state, rejection, reordering and disposal coverage. Native
accessibility frames now prove shared rows at 640 points and wrapping at 360,
while the same App scenario exercises selection, deletion and disablement.
See [native wrapping layout](swiftui-flow.md).

The complete regression gate passes: 221 Swift tests in 50 suites with a fresh
completion report, six native ABI tests, generated protocol checks, three
platform checks and all native App scenarios, including the updated tag
geometry acceptance. OCaml build/test/format, generated fixture and typed
viewport checks also pass. All 49 decision documents validate and whitespace
checks pass. Physical-iOS module and all ten application entrypoint typechecks
pass; actual device, VoiceOver and visual acceptance are not implied. No standalone example was added by this layout change; the count
remains ten, with the full Gallery port unfinished. Remaining widgets/services,
production packaging and naming, Flutter deletion, physical iOS acceptance and
complete Mail screenshots still prevent overall completion. Protected spec
sources remain unchanged; no source or generated SDK commit/push occurred.


### Native projection effects

`View.projection_effect` and `Style.Projection` now describe SwiftUI's native
plane projection. Identity, scale and translation helpers and arbitrary nine-
coefficient matrices map directly to ProjectionTransform. The old public
Transform API, four-by-four arrays, private node names, schema field and generated
identifiers are removed. Node 29 now requires the native nine-value payload;
there is no old matrix decoder. Drawing changes without changing layout extent,
and modifier nesting defines composition order.

The new Gallery component cycles identity, scaling, perspective and translation
while retaining a composed symbol/text Button and its OCaml action count. It is
included in both the actual runtime fixture and the combined Gallery view.
Initial renderer and real-OCaml integration tests failed on unsupported node 29;
the initial native App could not display its first result. Native raster tests
now match independent SwiftUI/CATransform3D reference expressions for affine and
perspective transforms, reflection, rotation and both layout directions. Each
render must contain visible colored content. Tests verify noncommuting modifier
order, unchanged measurement and rejection of truncated, non-finite, oversized
or structurally invalid updates without partial publication.

Real OCaml updates retain projection and Button identity, restore initial
coefficients after a complete cycle and fence callbacks on close. A native App
presses the actual accessibility control through all four projection modes at
640 and 360 points and receives all eight actions in OCaml. This verifies native
accessibility activation, not pointer hit testing at projected coordinates.
Semantic animation/completion callbacks, VoiceOver and physical-device checks
remain outstanding. See [projection effects](swiftui-projection.md).

The complete `make swift-test` gate passes with 225 Swift tests in 51 suites
and a fresh completion report, six native ABI tests, generated protocol checks,
three platform checks and every native App scenario, including projection.
The physical-iOS module and all ten App entrypoint typechecks pass. OCaml
build/test/format, generated fixtures and typed viewport checks pass. All 49
decision documents and whitespace checks pass. The desktop was rechecked after
regression completion and remains locked, so no complete Mail capture was taken. Ten standalone macOS
examples remain available. The full Gallery, remaining widgets/services,
production CLI/package/SDK work, complete Flutter deletion, physical iOS
acceptance and complete Mail screenshots remain unfinished. Protected spec
sources remain unchanged; no source or generated SDK commit/push occurred.


### Animated opacity and native completion ownership

Animated opacity now renders through SwiftUI withAnimation and returns the
current semantic animation ID through event 15. Initial mount has no completion;
changed target/intent properties create a new generation. Presentation and
current-binding checks gate starts and completion admission. A native animation's
removed-completion callback hops to MainActor and checks generation before it
can emit. Logical removal, kind/epoch replacement and close dispose the controller.

The renderer retains an unadmitted completion when the bounded queue is full.
A newer intent supersedes that retained completion; successful admission clears
it once. Inactive/detached content settles its renderer target and defers its
completion until mounted, active and presented. Lifecycle events can originate
inside control labels while ordinary pointer/selection isolation remains in
place. The actual Gallery animation now lives inside a disabled Toggle label.

Initial renderer and OCaml integration tests failed on unsupported node 71.
Native raster and validation tests now verify initial opacity/layout and atomic
rejection of invalid target, ID, curve, binding, child or payload. A real queue
capacity test retains and supersedes blocked completions, then admits only the
latest once. The OCaml/NSHostingView integration holds a frame unpresented longer
than the animation duration and proves that it starts only after acknowledgment,
then completes once after its native duration. The control-label parent remains
present throughout that test.

The actual SwiftUI App covers all curves, duration, interrupted/repeated targets,
zero duration, removal/remount, a reduced-motion signal, hiding/restoration and
two window widths. An attempted outer transaction override did not reliably
substitute for the read-only OS Reduce Motion environment. The acceptance test
instead supplies the production controller's environment signal without changing
system settings. Actual OS changes, mid-animation Reduce Motion, rapid
reactivation before the old duration expires and frame-by-frame visual settling
remain unverified and required. See [animated opacity](swiftui-animated-opacity.md).

The complete `make swift-test` gate passes with 229 Swift tests in 52 suites
and a fresh completion report, six native ABI tests, generated protocol checks,
three platform checks and every native App scenario, including animated opacity
in a disabled Toggle label. The physical-iOS module and all ten App entrypoints
typecheck. OCaml build/test/format, generated fixture and typed viewport checks
pass. All 49 decision documents and whitespace checks pass. The controller
currently stores a target opacity, so logical settling alone is not proof of
mid-flight visual cancellation; native presentation progress remains a required
follow-up measurement. Ten standalone macOS
examples remain available. Full Gallery, remaining widget/service families,
production CLI/package/SDK work, complete Flutter deletion, physical iOS and
complete Mail screenshots remain unfinished. Protected spec sources remain
unchanged; no source or generated SDK commit/push occurred.

### Interrupted opacity now replaces native interpolation

A companion SwiftUI AnimatableModifier reproduced the cancellation gap described
above. After a two-second fade had reached an intermediate value, mid-flight
Reduce Motion, rapid visibility restoration, a repeated target and a zero-duration
replacement all admitted completion while native interpolation continued. The
regression checks the interpolated coordinate both shortly after cancellation
and when completion is admitted; it does not read the controller's target back.
An attempted NSView bitmap capture was blank and was discarded as evidence.

The controller now starts a zero-duration SwiftUI animation for forced settling
and waits for its removed-animation completion. A second animatable coordinate
changes even when the target alpha is unchanged; only the first coordinate
affects opacity. This preserves the child view structure. Tests demonstrate
that a nil animation with the second coordinate still fails, and a zero-duration
animation without the second coordinate still fails unchanged-target cases.
The complete solution also passes multiple visibility changes in one UI update,
retains logical node identities, and emits no duplicate after the old duration.

The actual Gallery App acceptance scenario now switches its production Reduce
Motion signal during an animation and restores visibility after 80 milliseconds,
before the old duration expires. The companion test checks a 40-millisecond
restoration. These tests do not change the OS setting or capture compositor
pixels. Actual framebuffer settling, OS accessibility changes and physical iOS
remain acceptance requirements. The Mac was rechecked and remains locked;
complete Mail screenshots are still unavailable.

The full `make swift-test` gate passes with 230 Swift tests in 52 suites and a
fresh completion report, six native ABI tests, protocol generation checks,
three platform checks and all native App scenarios. Physical-iOS sources and
ten App entrypoints typecheck. Strict Swift formatting, all 49 decision
documents and whitespace checks pass. Protected spec sources remain unchanged.
The standalone Mail App was rebuilt from the current source; strict deep
signature verification passes, its minimum is macOS 26.0, its executable is
arm64, and its dynamic dependencies are system libraries/frameworks only.
Existing unused-result warnings in Semantics.swift remain in that build log.
No source or generated SDK commit/push occurred. Full Gallery, remaining
widgets/services, production CLI/package/SDK work, complete Flutter deletion,
physical iOS acceptance and the required Mail screenshots remain unfinished.

### Native workflow composition replaces the legacy Stepper

`Workflow` now expresses the existing multi-step capability with keyed native
Button headers, Pending/Editing/Complete/Disabled/Error markers, accessibility
status and selection metadata, retained bodies and Continue/Back controls.
Vertical layout interleaves headers and bodies; horizontal headers wrap with
Flow. Each step owns a normal Press handler. Noncurrent bodies retain identity
and cannot receive input or accessibility actions. Reordering within a layout
retains headers and bodies; changing layout changes view structure.

The Material.Stepper public module, node 132, private/protocol types, codecs and
three dedicated events are removed, including generated identifiers and the
obsolete protocol fixture. Existing validation checks now target Workflow and
include empty workflows and blank action labels. Both the full Gallery's
section list and the actual native fixture use the new API. Full Gallery root
and other Material families remain unfinished.

The initial real-OCaml test failed with unsupportedNode(132), and the initial
native App could not display its first result. The replacement passes native
integration for current-step updates, action counts, disabled controls, inactive
body rejection, identity after selecting another step and reordering, layout
changes, hidden sessions and closure. At 640 and 360 points, the actual SwiftUI
App verifies all five accessibility state values, enabled/selected traits,
Continue/Back, header selection, hidden-body accessibility and both layouts.

That native App exposed a separate existing MorphingSurfaceLayout crash when
one branch was EmptyView: SwiftUI omitted the empty branch's layout slot. A
focused regression reproduced the fatal out-of-range access. Both branches now
use stable ZStack layout slots, preserving their relative indexing even when
empty. Empty compact, expanded and both-branch cases now pass height checks
across expansion/collapse, together with existing editor-state retention and
native animation tests. See [workflows](swiftui-workflow.md).

The complete `make swift-test` gate passes with 232 Swift tests in 52 suites and
a fresh completion report, six native ABI tests, protocol generator checks,
three platform checks and every native App scenario, including Workflow.
OCaml build/test/format, generated fixtures and typed viewport checks pass.
Physical-iOS sources and all ten App entrypoints typecheck; no physical-device
execution is established. All 49 decision documents, strict formatting for the
changed Swift files, whitespace checks and the unchanged protected-spec check
pass. The desktop was rechecked and remains locked, so no complete Mail
screenshot was taken. Full Gallery, remaining widget/service families,
production CLI/package/SDK work, full Flutter deletion and physical-device/
visual acceptance remain unfinished. No source or generated SDK commit/push
occurred.

The standalone BonsaiMail.app was rebuilt against the current complete OCaml
object and SwiftUI source. Strict deep signature verification passes; its
minimum is macOS 26.0, the executable is arm64 and all dynamic dependencies are
system libraries/frameworks. This updated artifact is ready for the pending
window captures after the desktop can be accessed.

### Controlled native DisclosureGroup replaces expansion lists

`View.disclosure_group` now renders SwiftUI DisclosureGroup with a composed label
and body. Individual Boolean states and shared single/multiple expansion policy
belong to OCaml. The Gallery embeds a live component in both its section list
and the actual native runtime fixture. Its policy transition preserves an
existing expanded item, requests can be rejected without a new render frame,
and reordering preserves the disclosure and body node identities.

The former Expansion_panel_list and Expandable_list public modules, their panel
payload/types/codecs, header-tap option and expansion event are removed. Node
133 now has only expanded/enabled flags and uses the common Boolean change event.
Finite, scrolling and windowed composition use existing layout/Scroll/Collection
contracts. Toggle and DisclosureGroup share BooleanControlController pending
request, stale binding, rollback and disposal logic; their native presentation
and label/content ownership remain distinct.

Input into disclosure content requires matching expanded displayed/current
states, native expansion and enabled ownership. Header descendants cannot emit
input. A native editor regression found that retained collapsed content could
still accept edits. Explicit content disabling, hit-test exclusion and
accessibility hiding now release focus, reject hidden edits, and preserve the
local draft and selection on reopening. Animation lifecycle callbacks retain
their existing exception for visible disabled content.

Initial tests failed on unsupported node 133. Native raster comparisons now
match independent SwiftUI expressions in both expansion states. Malformed flags,
truncated/trailing payloads, invalid child counts and bindings reject staged
updates atomically. Real OCaml tests cover single/multiple policy and policy
changes, accepted/rejected requests, disabled and hidden inputs, presentation
fences, reordering and closure. The native App exercises actual disclosure
indicators, explicit collapse/reopen, rejected optimistic state, native expanded
values and disabled headers/body controls at 640 and 360 points. Shared Toggle
regressions also pass. See [disclosure groups](swiftui-disclosure.md).

The complete `make swift-test` gate passes with 236 Swift tests in 53 suites,
a fresh completion report, six native ABI tests, protocol generator checks,
three platform checks and every native App scenario, including DisclosureGroup
and the updated shared-Boolean-control consumers. OCaml build/test/format,
generated fixture checks and typed viewport checks pass. Physical-iOS sources
and all ten App entrypoints typecheck; device execution is still unverified.
All 49 decision documents, strict formatting for the changed Swift sources and
whitespace checks pass. Protected spec sources remain unchanged. The Mac was
rechecked and remains locked, so complete Mail screenshots are still unavailable.
Full Gallery, remaining widget/service families, CLI/package/SDK replacement,
complete Flutter deletion and physical/visual acceptance remain unfinished.
No source or generated SDK commit/push occurred.

The standalone BonsaiMail.app was rebuilt from the current OCaml complete object
and SwiftUI source. Strict deep signature verification passes, the executable
is arm64 with a macOS 26.0 minimum, and its dynamic dependencies are system
libraries/frameworks only. It is ready for the still-pending window captures.

### Native GroupBox replaces Card and CardList

`View.group_box ?key ?label content` now renders a native GroupBox with the
content in child slot 0 and optional label in slot 1. Adding/removing a label
preserves the existing unkeyed content identity. The former Material Card API,
elevation/variant properties, payload types and node decoder are removed;
node 106 now carries only a `has_label` Boolean. CardList is removed in favor of
keyed GroupBox/Button composition in the common finite/Scroll/Collection
containers. Groups own no events; each composed Button has its own handler and
enabled state. See [GroupBox](swiftui-group-box.md).

The Gallery section helper now uses GroupBox. Its live group component is
included in both the combined section list and the native runtime fixture.
One card exposes separate selection/header and content Buttons; a display-only
card is wrapped in a Button. It exercises selection, independent body actions,
label removal/restoration, disabling and keyed reordering.

Initial Swift tests failed because node 106 was unsupported and the native
entrypoint was missing. Tests now compare both native GroupBox initializers in
LTR/RTL, reject invalid flags/arity/bindings and truncated/trailing bytes
atomically, and preserve a native editor's draft, UTF-16 selection and controller
through label changes. The label test uses fresh identities for recreated
labels, as required by the common no-reuse contract. Actual OCaml integration
covers presentation fencing, independent actions, disabling, reorder retention
and session closure. A standalone native App presses real accessibility Buttons
at 640 and 360 points and passes these interaction scenarios.

The complete `make swift-test` gate passes with 240 Swift tests in 54 suites,
a fresh completion report, six native ABI tests, protocol generator checks,
three platform checks and all native App scenarios, including GroupBox. OCaml
build/test/format, generated fixture checks and typed viewport checks pass.
Physical-iOS sources and all ten App entrypoints typecheck; device execution
is still unverified. All 49 decision documents, strict formatting for changed
Swift sources and whitespace checks pass. Protected spec sources remain
unchanged. The desktop was rechecked and remains locked, so no complete Mail
screenshot was taken. Full Gallery, remaining widget/service families,
production CLI/package/SDK replacement, full Flutter deletion and physical/
visual acceptance remain unfinished. No source or generated SDK commit/push
occurred.

The standalone BonsaiMail.app was rebuilt from the current OCaml complete object
and SwiftUI sources. Strict deep signature verification passes, the executable
is arm64 with a macOS 26.0 minimum, and dynamic dependencies are system
libraries/frameworks only. Complete Mail window captures remain pending.

### Native Label replaces ListTile

`View.label ?key ~title ~icon ()` renders SwiftUI Label with two native view
slots and inherited styling. Node 57 has no properties, update mask 0, exactly
two children and no event bindings. Invalid child ownership, arity, bindings,
truncated updates and extra payload bytes reject the staged transaction. The
old `Material.list_tile` API is removed; headline, supporting text and overline
are keyed Text composition, main activation is a Button, selected state belongs
to OCaml and trailing actions are sibling Buttons with independent handlers.
See [native labels](swiftui-label.md).

The actual Gallery section is included in both the combined component and the
`native-labels` entrypoint. It exercises optional details/icons, selection,
disabled main actions, independently enabled accessories, removal/restoration
and reordering. A native accessibility-frame regression found that an intrinsic
main Button left most of the row unused. A filling label frame and weighted
row now assign the available width to the main action while retaining a fixed
accessory. A native render comparison also found missing selected presentation;
selected rows now use prominent Buttons and previous selections return to
bordered presentation, alongside native selected accessibility metadata.

The native Label expressions match independent SwiftUI renders standalone and
inside Buttons in both layout directions. Real OCaml tests cover presentation
barriers, disabled primary actions, independent accessories, retained headline
and Button identity, removed callback rejection and closure. Selected and
unselected row renders match the corresponding independent SwiftUI compositions
after switching selection. Native App checks cover full-width action bounds,
composed accessible titles, selected/enabled state and actual actions at 640
and 360 points.

The complete `make swift-test` gate passed with 243 Swift tests in 55 suites,
six native ABI tests, protocol generation, three platform checks and every
native window scenario. After the final Gallery selection-presentation change,
the OCaml build/test/format gate and the full Swift suite were rerun with a fresh
completion report; all 243 tests still pass. The final native Label window
scenario also passes. All 49 decision documents validate. Physical iOS module sources and all ten App entrypoints
typecheck; no physical execution is established. Generated fixtures, typed
viewport checks, changed Swift formatting and whitespace checks pass. Protected
spec sources remain unchanged.

CoreDevice currently lists one paired physical iPhone 13, but its connection
tunnel is unavailable and developer services are unavailable. Its reported OS
metadata is cached, not proof of a live device session. No device deployment
was attempted. The Mac desktop was rechecked and remains locked; complete Mail
window screenshots remain unavailable. Full Gallery, remaining widgets and
services, production CLI/package/SDK work, complete Flutter deletion and
physical/visual acceptance remain unfinished. No source or generated SDK
commit/push occurred.

The standalone BonsaiMail.app was rebuilt against the current complete OCaml
object and SwiftUI sources. Strict deep signature verification passes; its
minimum is macOS 26.0, its executable is arm64 and dynamic dependencies are
system libraries/frameworks only. Complete Mail screenshots remain pending.

### Native Button focus investigation and Badge migration

The remaining Material Button/FAB APIs still expose autofocus. An isolated
SwiftUI focus probe could not establish native Button focus in the current
session: its own window was not key, keyboard navigation was off, FocusState
returned false and a Space event went to the field instead of the Button.
Normal and explicit activation-focus variants were tried, including activation
of the probe's own application. No user keyboard settings were changed. This
is framework evidence, not successful OCaml autofocus acceptance; the APIs
remain unchanged and uncompleted. The reproducible probe and outstanding
presentation, hidden/disabled, retry and lifecycle requirements are recorded
in [Button focus](swiftui-button-focus.md). Independent widget work continued.

`View.badge` replaces the old Material badge API with directional native
SwiftUI overlays. Count data uses an exact non-negative integer rather than
the former generic floating-point property; the transport accepts through
signed Int64 maximum and the public constructor uses OCaml's int domain.
Omission is a dot, zero displays zero, and visibility hides only decoration.
The badge owns no action or accessibility element; the underlying control
supplies meaningful count semantics. Its content remains mounted and follows
its own enabled state. See [Badge](swiftui-badge.md).

Node 58 validates optional count, alignment and visibility with mask 7, one
child and no event bindings. Initial tests failed on the unsupported node and
missing actual Gallery entrypoint. Tests now cover malformed flags/counts,
arity/bindings, truncation/trailing bytes and transactional rejection. Native
raster comparisons cover dot, zero, ordinary and maximum counts at all three
directional anchors in LTR/RTL. They caught alignment-guide propagation through
conditional view structure; a stable overlay child with type-erased decoration
now preserves the anchors and uses opacity for visibility. Every comparison
matches the independent native expression, including undecorated content when
hidden.

The actual Gallery badge section is included in the combined component and the
native fixture. It preserves the content Button identity across count, position
and visibility changes, fences pre-presentation/disabled/closed input and lets
hidden decoration leave content actionable. The standalone native App verifies
exact maximum OCaml count semantics, dot/zero values, visibility, alignment and
Button actions at 640 and 360 points. Targeted Swift/native tests, OCaml
build/test/format, generated fixtures and typed viewport checks pass.

The complete `make swift-test` gate passes with 246 Swift tests in 56 suites,
a fresh completion report, six native ABI tests, protocol generator checks,
three platform checks and all native App scenarios, including Badge. Physical
iOS sources and all ten SwiftUI App entrypoints typecheck; device execution is
still unverified. All 49 decision documents, changed Swift/probe formatting and
whitespace checks pass. Protected spec sources remain unchanged. The desktop
was rechecked and remains locked, so no complete Mail screenshot was taken.
Button autofocus, the remaining widget/service families, full Gallery,
production CLI/package/SDK replacement, complete Flutter deletion and physical/
visual acceptance remain unfinished. No source or generated SDK commit/push
occurred.

The standalone BonsaiMail.app was rebuilt from the current OCaml complete object
and SwiftUI sources. Strict deep signature verification passes, the executable
is arm64 with a macOS 26.0 minimum, and all dynamic dependencies are system
libraries/frameworks. Complete Mail window screenshots remain pending.

### Native pointer event transport

Swift encodes pointer enter, leave, down and up with complete identifiers,
local/global coordinates, six device kinds and full-width button masks. The
encoder rejects identifier overflow and non-finite coordinates before queue
admission. Transition events do not coalesce, and both byte and count limits
preserve the previously queued events on rejection. See
[native pointer events](swiftui-pointer-events.md).

A fixture using the actual public OCaml mouse-region and gesture constructors
receives 24 ordered events through NativeRuntime and the production C bridge.
Every field and kind is checked in the resulting OCaml history, including zero
and maximum identifiers and button masks. Replaying the batch produces no new
change. The test works at the transport boundary; it does not stage unsupported
nodes through BonsaiSession or substitute placeholder views. BonsaiSession
still rejects pointer events as text-editor input.

After formatting, the OCaml build/test/format gate and native fixture build
pass. The full Swift suite passes with a fresh completion report: 249 tests in
57 suites. Three platform checks pass, including physical iOS module and all
ten App entrypoint typechecks, plus explicit Simulator/Intel rejection. Swift
formatting, whitespace and all 49 decision documents validate. The native App
scenario gate was not rerun for this transport-only change; its previous Badge
checkpoint remains the latest complete native-window gate.

The desktop was checked again and remains locked, so no complete Mail screenshot
was captured. Native pointer collection, MouseRegion rendering, nested ownership,
button-held hover crossings and physical interaction remain unfinished. The
installed UIKit public header documents that UIHoverGestureRecognizer pauses
while buttons are pressed, so its callbacks alone cannot prove those crossings.
Protected spec sources remain unchanged. No source or SDK commit/push occurred.

### Passive AppKit hover capture

`AppKitHoverCapture` now owns a native tracking area for cursor enter/leave
events. It requests native visible-rectangle tracking and enter events during
mouse drags, preserves the tracking-area identity across ordinary updates and
does not intercept hit testing. Captured positions use logical local coordinates
and window-content top-left global coordinates, with native conversion through
flipped and scaled views. The logical AppKit cursor uses ID zero and Mouse kind;
its button mask is read from AppKit. This is not tablet or UIKit capture.

Tests initially failed because there was no tracking area or captured event.
The implementation then passed direct native NSEvent callback tests and a real
captured-enter/leave-to-OCaml history check. Additional lifecycle tests exposed
unnecessary area replacement and stale inside state after hidden callbacks;
the adapter now retains the area and resets inactive transition state. Tests
also cover duplicate events, foreign windows, disable/re-enable, hide/show,
detach/reattach, disposal and coordinates outside the region on exit.

The complete Swift suite passes with 252 tests in 58 suites and a fresh
completion report. All three platform checks pass, including the physical iOS
module and ten App entrypoints. Changed Swift and probe formatting passes.
No OCaml source changed in this unit; the preceding OCaml build/test/format
checkpoint remains current. The full native App scenario gate was not rerun
because the capture layer is not yet connected to the renderer.

An independent application-window dispatch probe installed a tracking area and
sent local mouse-moved NSEvents through NSApplication. Its window was not key
and no tracking callbacks were observed. The saved
`tool/probe_appkit_hover.swift` is an investigation tool, not a passing acceptance
gate. This does not prove that key-window state is the sole cause. Direct
callback tests cannot establish system dispatch or physical button-held
crossings. See [pointer capture evidence](swiftui-pointer-events.md).

Renderer staging/admission, region overlap and opaque behavior, UIKit/tablet
capture and physical acceptance remain unfinished. Complete Mail screenshots
are still absent. No source or generated SDK commit/push occurred.

### UIKit hover adapter and shared contact handoff

`UIKitHoverCapture` now installs window-local mouse/Pencil hover recognizers and
a custom indirect-pointer contact observer. Window attachment allows observing
a button-held crossing that began outside the individual region. Mouse contact
uses the complete native button mask; a partial release keeps contact ownership
until the remaining buttons are released. The adapter disables touch delays and
cancellation, declines recognizer prevention and permits simultaneous recognition.
It converts window-relative positions into local coordinates and checks bounds
and rectangular clipping ancestors. These UIKit behaviors are implemented and
typechecked, but have not run on a physical device.

`HoverInput` gives contact samples precedence during a held-button interval,
ignores stale hover samples/termination from that interval, preserves independent
Pencil samples and handles cancellation and reset. `HoverTransitions` handles
per-pointer enter/leave transitions for both AppKit and UIKit. NativePointer's
validity check is shared with the wire encoder. The new tests failed before
these behaviors were implemented, then passed for handoff order, full and partial
release, invalid samples, pointer independence and lifecycle reset.

A real NativeRuntime/OCaml fixture verifies the merged six-event history for
mouse/Pencil enter, button-held mouse exit/re-entry and separate exits. Existing
AppKit NSEvent callback-to-OCaml tests still pass after using the shared transition
state. These establish the state and transport boundary, not UIKit callback
delivery or physical gesture coexistence. See [pointer input](swiftui-pointer-events.md).

The full Swift suite passes with a fresh completion report: 259 tests in 60
suites. Three platform checks pass after the final changes, including physical
iOS 18 module compilation and all ten App entrypoint typechecks. Changed Swift
formatting and whitespace checks pass. No OCaml source changed in this unit,
so the preceding OCaml build/test/format checkpoint remains current. Native
App scenario tests were not rerun for the still-unconnected capture layer.

UIKit capture remains physically unverified. MouseRegion renderer admission,
overlap/opaque ownership, nonrectangular SwiftUI clipping, Pencil contact
transitions, AppKit tablet capture and actual mouse/trackpad/Pencil acceptance
are outstanding. Each UIKit capture currently installs its own window recognizers;
sharing and performance require work during renderer integration. Full Mail
screenshots and the rest of the backend replacement remain unfinished. Protected
spec sources are unchanged; no source or SDK commit/push occurred.


### HoverRegion renderer, ownership and native lifecycle

The public constructor is now `View.hover_region ?blocks_behind ~on_enter
~on_leave child`, with no MouseRegion/opaque alias. OCaml reconciliation, wire
properties, generated protocol names and existing callers use the new API.
The Swift decoder validates its Boolean property, one child and exact enter/leave
bindings before publication. The actual Gallery section now exercises a parent,
overlapping children, pass-through, reordering, handler replacement and an
independent native Button. The section is included in the full Gallery source
and in the `native-hover` runtime fixture; this does not finish standalone Gallery.

`HoverRouter` owns per-pointer transitions and uses RenderTree preorder/subtree
intervals to preserve ancestors while excluding unrelated regions behind a
blocking front region. Exits precede enters. Rejected queue writes do not advance
membership and cannot let an enter overtake a pending exit. BonsaiSession admits
only current, presented HoverRegion bindings, rejects inactive/hidden/retired
input and discards previous-activation coordinates. Capture adapters now publish
raw samples only; their duplicate local transition paths have been removed.
Native controllers fence captured callbacks by generation and dispose retired
views. AppKit movement observation is local to participating application windows.

Regression tests first failed for missing node support, then exposed stale native
view mounting after an epoch replacement, lost same-coordinate re-entry after
window hiding and one window's sample resetting another pointer. Keying the
background representable by render identity mounts the replacement view while
leaving content layout intact. Unlocatable samples discard only their pointer's
membership; when no region can locate a sample, its cached coordinate is removed.
The native lifecycle and ownership regressions now pass.

The complete Swift suite passes with a fresh completion report: 267 tests in
62 suites. The three platform checks pass, including the physical iOS 18 module
and all ten SwiftUI App entrypoints. The OCaml `@all @runtest @fmt` build passes
after formatting the new Gallery section. Protocol fixture and viewport type
checks pass. The complete `make swift-test` gate passes: six native ABI tests,
fresh Swift completion checks, the generator test, platform checks and all native
application scenarios, including Mail and the new Hover window test. Changed
Swift formatting, whitespace and all 49 agent documents validate.

The Mail development bundle was rebuilt with this framework using
`opam exec --switch=bonsai-flutter-v017-exact -- python3
tool/build_swiftui_example.py mail`. `_build/swiftui/mail/BonsaiMail.app` passes
strict/deep signature verification, contains only arm64 code, declares macOS
26.0 in both Info.plist and its Mach-O build command and links only system
shared libraries. Existing unused-insert-result warnings in Semantics.swift
remain; the build succeeds but is not warning-free.

Reproducible validation commands for this checkpoint are:

- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- tool/check_viewport_types.sh`
- `opam exec --switch=bonsai-flutter-v017-exact -- make swift-test`
- `spec-dev-tool check --all`
- `git diff --check`



The native Hover window scenario uses actual Gallery code, native capture
callbacks and native accessibility Button actions. It does not establish system
mouse dispatch, physical button-held crossings or UIKit callback delivery.
Nonrectangular clipping, recognizer sharing/performance, tablet/Pencil details
and physical interaction remain outstanding. A fresh desktop check still reports
a locked Mac; complete Mail screenshots are absent. Protected spec sources are
unchanged. No source or generated SDK commit/push occurred.


### Shared hover sources and immediate session cleanup

AppKit movement monitors and UIKit mouse/Pencil/contact recognizers now belong
to a shared per-window source registry. UIKit's passive region views only
perform native coordinate conversion and membership checks; they no longer
install their own recognizers. The router owns the single coordinate cache,
while HoverInput retains only mouse-contact ownership for source arbitration.
Region registration and geometry changes now coalesce before scanning the
current region set, removing repeated full scans during a mounting batch.
A native regression mounts 128 real AppKit regions and verifies one window
source, retention while another region remains and release of the final source.
This is resource-count evidence, not a frame-time/memory performance result.

The registry preserves existing sources when a window remains present, holds
windows weakly and fences callbacks with a generation. It removes entries before
native teardown, preventing synchronous disposal callbacks from reaching the
router. It also compares window object identity to reject reused addresses.
Owner release schedules remaining disposal on the main actor. The new tests
first failed for missing sharing and immediate scanning, then exposed source
reuse after a replaced window identity; these cases now pass.

The actual Gallery window test now posts its initial mouse movement to the
application's own NSApplication queue and observes the real OCaml transitions.
It still covers overlap, pass-through, reorder, native child actions, handler
replacement and removal. New checks initially failed because inactive sessions
kept their source until the next layout. BonsaiSession now immediately discards
sources and pointer state on inactivity and closure, preserving this guarantee
even when deactivate/reactivate occur before the next layout. The native window
scenario passes after that correction.

The Swift suite passes with a fresh completion report: 271 tests in 64 suites.
The three platform checks pass for the final source changes, including the
iOS 18 module and ten App entrypoints. The complete `make swift-test` gate passes,
including all native application scenarios, six ABI checks, generator checks and
the fresh Swift completion-report check. A lint-only cleanup in the resource test
was followed by the four lifecycle tests and strict formatting checks. No OCaml
or protocol source changed in this unit, so the previous OCaml build/test/format
and fixture checkpoint remains current.

UIKit recognizer delivery and physical pointer/control/scroll coexistence still
require physical-device acceptance. AppKit's own event-queue test does not prove
physical device dispatch or delivery inside native tracking loops. General
routing/frame/memory performance, nonrectangular clipping, tablet/Pencil details
and Mail screenshots remain outstanding. No source or SDK commit/push occurred.


Mail was rebuilt after the shared-source changes. Its standalone development
bundle passes strict/deep signature verification, arm64-only inspection,
macOS 26.0 minimum checks in Info.plist and Mach-O, and system-only shared-library
inspection. Existing Semantics.swift unused-result warnings remain. Strict Swift
formatting and whitespace checks pass, and all 49 agent documents validate.
A fresh desktop check still reports a locked Mac, so no complete Mail screenshot
was captured in this unit.

### Independent civil date and time controls

`View.Date` / `View.Time` and `View.Date_picker.create` /
`View.Time_picker.create` now replace the Material calendar and dial APIs. All
OCaml callers were ported and the expressive-node civil hooks removed. Nodes 59
and 60 have independent properties, masks, codecs, tree validation and event
bindings. The date domain retains years 1 through 9999, inclusive bounds and
restricted selectable dates; the time domain retains every minute with system,
12-hour and 24-hour display choices. There are no old constructor aliases.

Native SwiftUI menu Pickers select civil year/month/day without Foundation's
historical calendar cutover. A native SwiftUI time DatePicker uses an explicit
UTC environment and a fixed carrier day. Shared civil value tests cover historical
dates, leap rules, all 1440 clock minutes, invalid and overflow-sized integers,
partial months, sparse allowed lists, list canonicalization and locale metadata.
See [civil date and time selection](swiftui-civil-selection.md) for the API,
component-clamping policy and Foundation probe.

The native controller preserves the final pending request, reconciles OCaml echoes
and restores rejected selections, including no-diff responses. Presented input
admission checks configuration, node identity, bindings, enabled/visible/active
content and domain membership. A regression first demonstrated that a replaced
handler still accepted its old native binding; replacement now clears pending
selection and invalidates that binding. Disposal and configuration changes also
fence stale callbacks. Cross-kind date/time payloads are rejected.

The actual Gallery component covers acceptance, repeated ignored requests,
restricted dates, disabling and handler replacement. It is included in the
existing Picker section and available independently to native integration tests.
A real NSHostingView window invokes the SwiftUI year menu item's action and the
native time control's action, then verifies the resulting OCaml state and the
native time zone. The year menu dispatches through NSMenuItem rather than an
NSPopUpButton target/action. This is application-local native action evidence,
not physical interaction or visual acceptance.

Initial tests failed on unsupported expressive node 136 and absent controlled
selection behavior. They now pass with independent nodes. OCaml property round
trips exposed reversed field reads in the shared civil readers; explicit sequential
reads fixed the date/time wire order. The full Swift suite passes with a fresh
completion report: 290 tests in 67 suites. OCaml build, tests and formatting pass.
Three platform tests pass, including iOS 18 module compilation and all ten App
entrypoints. Native Picker and Mail application-window scenarios pass, alongside
six ABI/runtime tests, Swift protocol generation, both generated-artifact checks,
viewport compile checks and strict changed-file Swift formatting.

Commands for this checkpoint:

- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `python3 tool/run_swift_tests.py`
- `python3 tool/test_swift_platforms.py`
- `python3 native/test/test_picker_window.py`
- `python3 native/test/test_mail_window.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/test_native_runtime.sh`
- `python3 protocol/generator/test_swift_generator.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`

Physical iOS interaction, accessibility usability, the large-year-menu performance
budget and full visual acceptance remain outstanding. The full Gallery root and
remaining Flutter controls/tooling still require migration. A fresh desktop check
again reports a locked Mac; no complete Mail screenshot was captured. Protected
spec sources remain unchanged, and no source/SDK commit or push occurred.

Mail was rebuilt with this checkpoint's framework. The development bundle passes
strict/deep signature verification, arm64-only inspection, macOS 26.0 minimum
checks in Info.plist and Mach-O, and system-only shared-library inspection.
Existing Semantics.swift unused-insert-result warnings remain. Whitespace checks
pass, and all 49 agent decision documents validate.

### Hierarchical native menus and action composition

`View.Menu` replaces Material Menu, SplitButton and FAB menu. Their old public
modules and OCaml implementations are deleted, and all in-repository OCaml
callers use the new API. A primary action with secondary options is a normal
Button/Menu row; the former FAB menu uses a labeled symbol anchor and icon
entries. Material placement and alternate collapse-icon flags are removed in
favor of application layout and SwiftUI's menu presentation. Button autofocus
remains a separate unfinished capability; no focus setting or locked-desktop
behavior was changed to force its acceptance.

Menu node 61 encodes bounded hierarchical entries and enabled state. Labels are
ordinary keyed View children, including SF Symbol composition. The public API and
both codecs reject empty menus, duplicate IDs across the whole tree, invalid
shapes, more than 1024 entries and depth above 32. Section and divider identities
are explicit. Event 54 carries a signed ID; menu actions are never coalesced.
Native choices temporarily display their requested state, then reconcile OCaml
acceptance or no-diff rejection. Configuration, binding and label-child identity
changes invalidate retained action closures. Session admission also checks
presented configuration, active visible ownership and enabled ancestors.

Initial tests failed because menu nodes were unsupported. The actual Gallery
runtime then exposed a missing event-payload conversion branch; adding it made
repeated signed actions and checked-state updates reach the OCaml model. The
full OCaml gate also caught a missing event mapping in the test-support handle,
which is now exhaustive. Tests cover disabled descendants, non-action IDs,
repeated rejection, input while an echo awaits presentation, replaced handlers,
hidden sessions and closure disposal.

The native menu lazily populates when opened. Opening it inside Swift Testing
caused an early status-zero exit without a completed test report. Native menu
acceptance therefore runs in its own SwiftUI App, with a required PASS marker
and process completion. Its menu tracking loop is closed by an application-local
timer before invoking native item actions. The App verifies group/submenu
structure, symbol images, Open and nested PDF actions, checked values and rejected
checkmark restoration at 640- and 360-point widths. On this Mac, disabled submenu
containers remain expandable while their descendants are disabled; the renderer
propagates availability explicitly and rejects those descendant actions. No
production AppKit introspection or replacement menu was added to change this
native presentation. See [native menus](swiftui-menu.md).

The full Swift suite passes with a fresh completion report: 294 tests in 68 suites.
OCaml build, tests and formatting pass. Three platform tests pass, including the
iOS 18 module and all ten App entrypoints. Native Menu, Picker and Mail window
scenarios pass. Six ABI/runtime tests, Swift generator validation, both generated
artifact checks, viewport compile checks and changed-file Swift formatting pass.
`make swift-test` now includes the standalone Menu scenario; the full Make target
was not rerun in this unit because its relevant constituent checks were executed
individually.

Commands for this checkpoint:

- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `python3 tool/run_swift_tests.py`
- `python3 tool/test_swift_platforms.py`
- `python3 native/test/test_menu_window.py`
- `python3 native/test/test_picker_window.py`
- `python3 native/test/test_mail_window.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/test_native_runtime.sh`
- `python3 protocol/generator/test_swift_generator.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`

Physical mouse/keyboard/VoiceOver and iOS acceptance, maximum-size menu performance
and full visual acceptance remain outstanding. The complete Gallery root and the
remaining widget, host-service and tooling work still require migration. The Mac
remains locked on a fresh desktop check; complete Mail screenshots are absent.
Protected spec sources remain unchanged. No source or SDK commit/push occurred.

Mail was rebuilt with the current framework. Its standalone development bundle
passes strict/deep signature verification, arm64-only inspection, macOS 26.0
minimum checks in both Info.plist and Mach-O, and system-only shared-library
inspection. Existing Semantics.swift unused-result warnings remain. Whitespace
checks pass, and all 49 agent decision documents validate.


## Searchable choice and action composition (2026-09-13)

Removed Material Button_group and Dropdown_menu public constructors, implementations,
static callers and Dart rendering branches. The actual Gallery now includes
`Selection_catalog.component`, which composes core Picker, keyed Button-style
Toggles, Menu, Flow, bounded Scroll and native text input. Single and multiple
selection remain canonical OCaml state through filtering, loading, empty and
failed content. A retry keeps the current query and selection. Ordinary actions
remain separate from selection policy and preserve repeated identical clicks.
Material group shape/type/style flags are replaced by native control styles and
composition; no compatibility API or new generic wire node was added.

The first three native integration tests failed against unsupported legacy node
136 and passed after the actual OCaml component used native composition. They
exercise search, layout and content changes, disabled and removed controls,
no-diff rejection, reordering, canonical state and Unicode marked text. A further
ordering test verifies that a choice hidden by an earlier search edit in the same
batch cannot change canonical state. Native field-editor capture runs after the
completed mutation; the test waits for that capture before queuing later choices,
without pumping OCaml in between.

All five control sizes were checked on actual AppKit segmented, popup and radio
controls, including their intrinsic heights. SwiftUI already forwards the
control-size environment through these adapters, so no adapter implementation
change was needed. The original Picker regression now selects its four controls
by their catalog labels and also verifies independence of the additional catalog.

A separate native SwiftUI App exercises actual accessibility/menu actions and
field-editor mutations, checks the resulting OCaml model, and requires a PASS
marker plus successful process exit. It covers single/multiple selection,
repeated actions, search, no results, error retry and retained selection. Its
menu composition fits a 360-point window, with disabled entries and rejected
checkmarks restored. AppKit segmented accessibility may return false after
actually dispatching an action; the test checks the resulting canonical state.
`make swift-test` now includes this standalone application. See
[choice composition](swiftui-choice-composition.md).

The full migration remains incomplete. A fresh desktop query still reports the
Mac locked; no Mail screenshot was captured. Physical iOS, system keyboard/IME,
VoiceOver and visual acceptance remain open. No protected spec source was edited
and no source or SDK commit/push occurred.

Validation for this checkpoint: the full Swift suite passes with a fresh
completion report, 299 tests in 68 suites. After annotating the new recursive
native-view test helper with MainActor, its five-size test passes again without
the new concurrency warning. OCaml build/tests/formatting, native selection
catalog, Picker and Mail window scenarios, strict changed-file Swift formatting,
whitespace checks and all 49 decision-document checks pass. The complete Make
aggregate was not rerun; its affected checks were run individually. iOS source
and App entrypoints were unchanged in this unit; their previous compile results
do not establish physical-device runtime acceptance.

Mail was rebuilt against the current source. The arm64-only development bundle
requires macOS 26.0 and passes strict/deep signature verification. Existing
Semantics.swift unused-result warnings remain. This is a built application,
not a captured screenshot.

Commands used for the checkpoint:

- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `python3 tool/run_swift_tests.py`
- `swift test --scratch-path _build/swift --filter choicePickerAdaptersFollow`
- `python3 native/test/test_selection_catalog_window.py`
- `python3 native/test/test_picker_window.py`
- `python3 native/test/test_mail_window.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py mail`
- `codesign --verify --deep --strict _build/swiftui/mail/BonsaiMail.app`

## Controlled native scroll targets (2026-09-13)

Removed Material Carousel and its Dart rendering branch. The public replacement
is `View.Scroll_targets.horizontal` / `.vertical`, with bounded typed Viewports,
keyed arbitrary children, signed IDs, OCaml-controlled position, item fractions,
spacing, directional anchors, native snapping, disabled scrolling and indicators.
Ordinary card Buttons preserve independent and repeated actions. Gallery now
embeds `Carousel_catalog.component` in its scroll section, and the native fixture
runs that exact component through the `native-carousel` entrypoint.

Node 62 and event 55 carry the new properties and Int64 position notifications.
Constructor, OCaml codec and Swift staging enforce matching IDs, positions,
children and bindings, along with finite fraction/spacing and valid flags.
Position-event coalescing, optimistic request serials, no-diff rejection and
binding generations share the existing runtime/presentation boundary.

The original native and actual-runtime regressions failed on unsupported node
62 and the old expressive node 136 before the implementation passed. Native
alignment checks exposed incorrect lazy-stack estimates and RTL margins. The
renderer now uses eager native stacks, explicit directional content margins and
ScrollViewReader restoration. Geometry preferences report the focal item from
actual viewport movement. All 36 combinations of both axes, LTR/RTL, three
alignments and first/middle/last initial positions pass native window geometry
checks. Large-catalog performance is not established.

A standalone SwiftUI App changes its actual NSClipView viewport and verifies the
resulting OCaml state on both axes. Position updates, independent card actions
and rejected-position restoration pass. A further regression first failed
because an off-anchor 345-point viewport was snapped to 292 points even with
snapping disabled. The renderer now distinguishes observed pending positions
from canonical scroll commands, preserving free scrolling. This App test passes
and is included in `make swift-test`. It requires both a PASS marker and a
successful exit; it does not simulate physical mouse/trackpad momentum or prove
snapping physics. See [scroll targets](swiftui-scroll-targets.md).

The full Swift suite passes with a fresh completion report: 305 tests in 69
suites. OCaml build/tests/formatting, generated artifacts, Swift generator round
trip, viewport type checks and strict changed-file Swift formatting pass. The
complete Swift module and all ten example entrypoints compile for physical
iOS 18 arm64; supported/unsupported target checks also pass. This is not evidence
of native OCaml cross-linking, signing or physical-device execution.

Commands used for this checkpoint:

- `python3 native/test/test_carousel_window.py`
- `python3 tool/run_swift_tests.py`
- `python3 tool/test_swift_platforms.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `python3 protocol/generator/test_swift_generator.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`

The overall migration remains incomplete. Physical gestures, iOS runtime,
VoiceOver, visual acceptance and large-catalog performance remain outstanding.
A fresh desktop query reports the Mac locked, and real Mail screenshots remain
absent. No protected spec source was edited and no source or SDK commit/push
occurred. The complete Make aggregate was not rerun in this unit.

Mail was rebuilt against this checkpoint and passes the native inbox/expand/archive
window regression. The development bundle passes strict/deep signature checks,
arm64-only inspection and macOS 26.0 minimum checks in both Info.plist and Mach-O.
Existing Semantics.swift unused-result warnings remain. This is a verified build,
not a screenshot. The obsolete Dart Carousel regression was removed after its
replacement native tests passed. Whitespace checks and all 49 decision documents
validate.

- `python3 native/test/test_mail_window.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py mail`
- `codesign --verify --deep --strict _build/swiftui/mail/BonsaiMail.app`
- `spec-dev-tool check --all`


## Native plain help text (2026-09-13)

Replaced `Material.Tooltip.plain` with `View.help ~message child` and removed the
old plain Dart rendering branch. Node 63 carries one string property, one child
and no event bindings. The Swift renderer applies native `.help(Text(verbatim:))`
without adding activation behavior or interpreting OCaml text as a localization
key. The actual Gallery help section is also the `native-help` fixture, covering
Unicode hint updates, repeated independent actions and enabled-state changes.

Two native staging/window tests first failed on unsupported node 63. The actual
OCaml fixture first failed on the former expressive node 136. After migration,
all three pass: native accessibility help updates without replacing the child or
swallowing activation; malformed transactions retain the previous committed
revision; actual OCaml counts change through native accessibility actions and
respect disabling. A further domain regression exposed Swift's broader Unicode
whitespace trimming. The Swift decoder now matches OCaml String.trim's ASCII
whitespace set, preserving other valid UTF-8 consistently. Constructor tests
cover blank rejection and Unicode preservation.

The complete Tooltip family is not finished. `Material.Tooltip.rich` still needs
a native presentation with title, message, interactive actions and explicit
opening/dismissal ownership. Plain help is not its substitute. Physical macOS
hover, VoiceOver and physical iOS acceptance also remain open. See
[native help](swiftui-help.md). A fresh desktop query reports the Mac locked;
real Mail screenshots remain absent. Protected spec sources are unchanged,
and no source or SDK commit/push occurred.

Validation: the full Swift suite passes with a fresh completion report, 308 tests
in 70 suites. OCaml build/tests/formatting, generated protocol and fixture checks,
viewport compile checks, strict changed-file Swift formatting and whitespace
checks pass. The complete Swift module and all ten example entrypoints compile
for physical iOS 18 arm64; supported and unsupported target checks pass. These
compile checks do not establish OCaml cross-linking or device interaction. Mail
was not rebuilt in this unit; its last verified bundle is the preceding scroll
targets checkpoint. The complete Make aggregate was not rerun.

- `swift test --scratch-path _build/swift --filter HelpTests`
- `python3 tool/run_swift_tests.py`
- `python3 tool/test_swift_platforms.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`
- `spec-dev-tool check --all`


## Controlled popovers and rich help (2026-09-13)

Added `View.Popover.create` with OCaml-controlled presentation, an optional native
arrow edge, an ordinary anchor View and arbitrary retained content. Gallery's
actual `popover_component` composes the former rich Tooltip's title, description
and independent actions from Text and Buttons. Removed `Material.Tooltip.rich`,
the remaining Tooltip module and Dart rendering branch, and the unused triggered
event 36. The complete Tooltip public family now uses core help/presentation
composition without a compatibility alias.

Node 72 carries visibility and edge with property mask 3 and exactly two children.
Native dismissal reuses Boolean event 18 but only false is admitted for popovers;
opening remains an OCaml action. Displayed-owner matching and native appearance
both gate content input. A dedicated presentation controller stages dismissal,
restores rejected requests and invalidates callbacks after binding/content/edge
changes, hiding or disposal. Session inactivity suppresses native presentation
without generating a model dismissal. Closed content retains logical identity
while its native view follows SwiftUI's presentation lifecycle.

An isolated native SwiftUI probe established popover appearance and Escape
cancellation in the available application window. Initial staging and actual
OCaml integration tests failed on unsupported nodes 72 and 136. The replacement
passes native popover-window tests for repeated actions, rejected/accepted Escape
dismissal, obsolete dismissal bindings, hidden-session restoration, programmatic
closing, retained child identity and teardown. Hidden/disposed content rejects
retained action references. Removing the old Tooltip constructor also required
removing its corresponding legacy constructor-kind expectation before the OCaml
surface regression passed. See [controlled popovers](swiftui-popover.md).

The full Swift suite passes with a fresh completion report, 310 tests in 71
suites. OCaml build/tests/formatting, generated protocol/fixture checks, viewport
compile checks, strict changed-file Swift formatting, whitespace checks and all
49 agent decision documents pass. The complete Make aggregate was not rerun.

Physical pointer/keyboard interaction, VoiceOver, editor focus/IME inside
presentations, every arrow-edge geometry and physical iOS behavior remain
unverified. The overall widget/tooling/example migration is incomplete. A fresh
desktop check still reports the Mac locked and no real Mail screenshot was
captured. No protected spec source changed and no source or SDK commit/push
occurred.

Commands used for this checkpoint:

- `swift test --scratch-path _build/swift --filter 'PopoverTests|actualPopover'`
- `python3 tool/run_swift_tests.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`
- `spec-dev-tool check --all`

A strengthened stale-binding regression exposed a dismissal leak after the old
binding getter was read again following handler replacement. The request reached
the new OCaml handler and changed its dismissal count. Popover bindings now
capture an immutable generation; getter reads cannot renew obsolete ownership.
The native integration passes after this correction. The final full Swift rerun
also passes all 310 tests in 71 suites. The complete Swift module and all ten
example entrypoints compile for physical iOS 18 arm64 after the fix; supported
and unsupported target checks pass. These are compile checks, not native OCaml
cross-linking or physical-device execution.

Mail's native inbox/expand/archive window regression passes with the presentation
ownership changes. Mail was rebuilt after the final binding fix and its
arm64-only macOS 26.0 development bundle passes strict/deep signature checks;
Info.plist and Mach-O agree on the minimum version. Existing Semantics.swift
unused-result warnings remain. This verified application build is not a
screenshot.

- `python3 tool/test_swift_platforms.py`
- `python3 native/test/test_mail_window.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py mail`
- `codesign --verify --deep --strict _build/swiftui/mail/BonsaiMail.app`

## Native sheets and dialog composition (2026-09-13)

Added `View.Sheet.create` and `View.Sheet.full_screen`. The former uses native
SwiftUI sheets with medium/large detents on iOS; the latter uses an iOS
fullscreen cover and a native sheet on macOS. OCaml owns presentation and
accepts or rejects native dismissal through Boolean event 18. Native detent
selection remains local presentation state. Titles, descriptions, choices and
actions are ordinary Views. Removed the Material Dialog, Bottom_sheet and
Side_sheet surface modules, old dialog wire nodes 134/135, event 45 and their
Dart rendering branches. The separate legacy modal routes and Scaffold slots
remain unfinished.

Sheet node 73 validates six properties, exactly two children and its dismissal
binding. Constructors reject empty or duplicate detents and an initial detent
outside the selected set. Swift rejects invalid flags, unsupported detents,
invalid fullscreen configurations, missing bindings, wrong child counts and
truncated payloads before committing a tree. Closed content retains logical
identity while native presentation owns its view lifecycle.

Popover and Sheet now share `PresentationController`, preserving immutable
callback generations across handler replacement and rejected dismissal.
Presentation eligibility requires matching displayed ownership and native
appearance. An active native sheet blocks both its presenter subtree and
same-window sibling actions outside that subtree. Hiding a session suppresses
presentation without changing canonical OCaml state or inventing a dismissal.

Gallery's actual `Sheet_catalog.component` provides five presentations: alert
content, account choices, bottom content, inspector content and fullscreen
content. Native-window tests execute repeated actions, reject disabled choices,
retain the chosen account between presentations, exercise a nested popover,
lock interactive dismissal, reject and accept Escape dismissal, replace handlers,
reject stale bindings, hide/resume and shut down. Background and sibling action
handlers deliberately mutate the model if reached, making input leaks observable.
Initial tests failed on unsupported nodes 73 and 136 before implementation.
See [native sheets](swiftui-sheet.md).

The full Swift suite passed 312 tests in 72 suites after the shared controller
and Sheet implementation. After strengthening the Gallery fixture with the
outside sibling action and retained-account assertion, the two targeted Sheet
tests passed again; the full suite was not rerun after that fixture-only change.
OCaml build/tests/formatting passed after the fixture change. The complete Swift
module and all ten example entrypoints compile for physical iOS 18 arm64;
supported-target and explicit unsupported-target checks pass. Mail's native
inbox/expand/archive window regression also passes with the Sheet changes.

These checks do not establish physical iOS OCaml cross-linking, signing or
execution. Physical detent dragging, fullscreen behavior, focus/IME, VoiceOver,
concurrent/nested sheet arbitration and performance remain open. Complete
standalone Gallery, remaining widget/tooling migration and real Mail screenshots
are still required. The latest desktop check reports the Mac locked. No protected
spec source changed, and no source or SDK commit/push occurred.

Commands used for this checkpoint:

- `swift test --scratch-path _build/swift --filter 'SheetTests|actualSheets'`
- `python3 tool/run_swift_tests.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `python3 tool/test_swift_platforms.py`
- `python3 native/test/test_mail_window.py`
- `spec-dev-tool check --all`

Mail was rebuilt against the Sheet implementation and passes strict/deep
signature verification. The binary is arm64-only; Mach-O and Info.plist both
specify macOS 26.0. Existing Semantics.swift unused-result warnings remain.
Generated protocol and fixture checks, viewport compile checks, strict Swift
formatting of the presentation implementation/tests, all 49 agent decision
documents and whitespace checks pass. The complete Make aggregate was not rerun.

- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py mail`
- `codesign --verify --deep --strict _build/swiftui/mail/BonsaiMail.app`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`
- `spec-dev-tool check --all`
- `git diff --check`


## Native sizing and retired Flutter routes (2026-09-13)

`View.Sheet.create` now accepts Automatic/Fitted/Form/Page sizing, mapped directly
to SwiftUI presentation sizing. iOS detents still own sheet height; Fitted is
not an automatic content-height iPhone detent. Fullscreen covers do not accept
size overrides. Node 73 now carries seven properties with mask 127. Unknown
sizing codes and nonautomatic fullscreen sizing fail transactional validation.
Gallery's five presentations retain their action/dismissal checks while its
ordinary sheets exercise the four sizing policies.

The initial extended tests failed because the old decoder did not consume the
new field and the original Gallery sheets used the same size. After adding the
native policy, the first geometry expectation incorrectly assumed form/page
would always be taller than fitted. Actual native windows demonstrated otherwise:
the fitted proposal produces the supplied 360 by 420 point ideal size, while
form/page honor the available window and the content's 360 point minimum height.
The corrected behavioral assertions verify those constraints and distinct native
policy effects. The complete Swift suite passes 312 tests in 72 suites with a
fresh completion report.

No retained example calls the old Navigator/Page constructors. Removed
`View.navigator`, `View.page`, `Navigation.Modal_bottom_sheet`, Modal_dialog,
Modal_side_sheet and the legacy page transition/presentation types. Removed
wire nodes 66/67, their property codecs, route-pop event 16 and its dispatch/test
helpers. A captured formerly valid Page update first failed the rejection test
because the old decoder accepted it; the final test now requires the precise
Unknown_node_kind error. The old generated modal fixture is removed. Destination
paths use Navigation_stack/Navigation_split and native dismissal uses Sheet;
application actions and OCaml state own returned values.

Removed the unused Flutter navigation host, modal route implementation, route
widget harness and registry branches. The remaining Dart route-pop payload
codec and its round-trip case are removed as well. Other Flutter/Dart protocol,
widget and build files still require migration/removal; no Dart validation was
claimed. The testing guide now documents current SwiftUI checks and distinguishes
them from the unfinished legacy packaging targets.

Old tests for arbitrary Material barriers, route timing/receding geometry,
restoration IDs and custom detent-handle semantics describe intentionally removed
framework-specific controls. Their deletion does not establish the replacement's
focus, keyboard avoidance, VoiceOver, scroll/detent gesture arbitration, nested
sheet behavior or physical-device acceptance. These remain explicit requirements.
Scaffold's persistent bottom slot, remaining widgets, full standalone Gallery,
production tooling, physical iOS integration and real Mail screenshots are still
unfinished. No protected spec source was edited; no source or SDK commit/push
occurred.

Validation after removal: OCaml @all/@runtest/@fmt pass, including the retired
wire rejection. The full Swift suite passes, the complete Swift module and all
ten example entrypoints compile for physical iOS 18 arm64, and unsupported targets
are explicitly rejected. Standalone native Back, sidebar and Tabs window tests
pass through the actual OCaml Navigation/Gallery components. The complete Make
aggregate was not rerun.

- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec ocaml/test/protocol_tests.exe`
- `python3 tool/run_swift_tests.py`
- `python3 tool/test_swift_platforms.py`
- `python3 native/test/test_navigation_window.py`


Mail's native inbox/expand/archive regression passes after route removal, and
Mail has been rebuilt with the final sizing implementation. Its development
bundle passes strict/deep signature verification; the executable is arm64-only
and both Mach-O and Info.plist require macOS 26.0. This is an application build,
not an actual screenshot. The last desktop query reported a locked Mac, and the
required runtime captures remain absent.

Generated protocol/fixture checks and viewport compile checks pass. Strict Swift
formatting, whitespace checks and all agent decision document checks pass. The
old Flutter modal fixture consumer and keyboard/profile harness were also removed
with their dead links; physical SwiftUI keyboard and performance gates remain
explicitly outstanding in the replacement testing guide. The obsolete Dart
navigation/property implementation elsewhere remains part of the larger Flutter
cleanup, not a supported renderer.

- `python3 native/test/test_mail_window.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py mail`
- `codesign --verify --deep --strict _build/swiftui/mail/BonsaiMail.app`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`
- `spec-dev-tool check --all`
- `git diff --check`


## Bounded page composition and Scaffold removal (2026-09-13)

Removed Material.scaffold, the private Scaffold constructors, floating-action
location enum, node 96, its slot property record, encoder/decoder and renderer
registry branch. No replacement Scaffold node or compatibility wrapper was added.
Gallery's root now returns View.Body directly: fixed header/footer children
surround the bounded scrolling catalog and an ordinary native New Button uses
a viewport overlay. Its AppBar/navigation controls and other remaining sections
still need migration before the combined Gallery can stage and run standalone.

Added typed overlays to both Viewport axes using the existing overlay renderer.
Attaching a floating action to the scrolling region follows that region's bounds
without repeating footer-height arithmetic. Body.with_size supplies finite positive
bounds before embedding a Body as ordinary content; Gallery uses it for its
480 by 400 point page-layout demonstration. Application bodies continue to take
bounds from their actual window. The generated viewport-body fixture now starts
at an ordinary overlay instead of a Scaffold wrapper.

The actual Page_layout_catalog.component is included in Gallery and embedded
as native-page-layout. Its native regression first failed at unsupported node 96.
With ordinary Body/Scroll/Button/overlay composition, repeated header actions,
footer actions, a floating action and row actions reach real OCaml state. A footer
increase from 60 to 100 points reduces the allocated scroll region by 40 points.
Scrolling leaves the footer stationary; footer changes and native window resizing
preserve logical nodes, the native scroll object and a 400-point scroll offset.
Hidden/disposed sessions reject retained actions.

The full Swift suite passed 313 tests in 72 suites with a fresh completion report.
After refactoring the floating action from a whole-body overlay with explicit
footer-height compensation to a typed viewport overlay, the final page-layout
and existing two-axis native-scroll regressions both passed again. OCaml
@all/@runtest/@fmt pass after that refactor. The first aggregate attempt required
formatting the expanded Gallery Dune module list; no behavioral OCaml regression
failed. See [native page layout](swiftui-page-layout.md).

The old native-local composer interface documentation now identifies its pending
SwiftUI replacement instead of directing callers to a deleted Scaffold slot.
Its draft/selection/focus retention and reduced-motion behavior remain required.
This unit does not complete AppBar/toolbars, navigation bars, remaining controls,
full Gallery, physical-device keyboard/VoiceOver/performance acceptance, tooling
or Mail screenshots. Protected spec sources are unchanged. No source or SDK
commit/push occurred.

- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `python3 tool/run_swift_tests.py`
- `swift test --scratch-path _build/swift --filter 'actualPageLayout|actualGalleryScrollsInBothAxes'`


Final checks: the full Swift module and all ten current application entrypoints
compile for physical iOS 18 arm64, and unsupported target probes fail explicitly.
Generated protocol/fixture checks, viewport compile checks, strict Swift formatting,
whitespace checks and all agent decision documents pass. Mail was rebuilt after
the final OCaml layout changes; its development bundle passes strict/deep signature
verification and is arm64-only with macOS 26.0 in both Mach-O and Info.plist. Mail's
separate window regression was not rerun in this unit; the full Swift runtime
suite and OCaml behavior tests passed as recorded above. No new screenshot was
captured, and the complete Make aggregate was not rerun.

A fresh read-only physical-device inventory reports a paired iPhone 13 with
cached iOS 26.6.1 metadata, developer mode enabled, an unavailable connection
tunnel and unavailable DDI services. This is not a currently usable device
execution path. The keychain reports two valid Apple Development signing identities; their
presence alone does not prove application provisioning, device signing or
installation. Physical OCaml cross-linking and the required device/runtime
screenshots remain incomplete; no Simulator path was added.

- `python3 tool/test_swift_platforms.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`
- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py mail`
- `codesign --verify --deep --strict _build/swiftui/mail/BonsaiMail.app`
- `xcrun devicectl list devices --json-output /tmp/swiftui-physical-devices.json --timeout 10`
- `security find-identity -v -p codesigning`
- `spec-dev-tool check --all`
- `git diff --check`

## Native two-column navigation split (2026-09-13)

Added View.Navigation_split.two_columns alongside the three-column create
constructor. It accepts bounded sidebar/detail bodies directly and uses SwiftUI's
native two-column initializer. No empty content column is inserted. Content title
is now an optional wire string: absence represents two columns, presence represents
three. The property mask remains 63; the old required-string encoding is removed.
Both OCaml property encoding/decoding and Swift staging reject Content as the
preferred compact column when there is no middle column. The public constructor
rejects that state before constructing a view. Child counts must match the mode.

RenderTree synchronizes the column structure into its retained split controller.
Changing that structure clears pending native state and invalidates bindings that
have not observed the new structure. Session admission independently rejects
missing-Content requests and retains the existing displayed/current owner,
selection, title, handler and child checks. Gallery now contains both configurations;
the actual OCaml component runs as native-split and native-split-two-columns.

The new native-window test first failed because the old decoder could not read
the optional content title. The two-column runtime entrypoint was initially absent.
After implementation, real OCaml selection/clear actions, accepted visibility
changes, declined changes, stale/disposed events and node retention pass. A
three-to-two-column update preserves the root/controller while clearing a pending
Content request and removing the old middle child. Malformed properties and child
counts reject the candidate without changing the original tree.

The full Swift suite passed 316 tests in 72 suites with a fresh completion report.
OCaml @all/@runtest/@fmt pass; the first aggregate required only formatting the
changed Gallery/view/fixture sources. All four standalone navigation scenarios
pass: system Back, three-column sidebar, two-column sidebar, and system Tabs.
Both sidebar scenarios repeat three hide/show cycles, verify actual native column
counts and NSSplitViewItem.isCollapsed, and preserve selection after window resize.
Initial extra geometry assertions were invalid for automatic SwiftUI styling:
visible sidebars can overlay main columns, and NSSplitView.isSubviewCollapsed does
not reflect the retained item wrapper's state. The final check inspects the public
native split item instead of inferring collapse from column origins or widths.

- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `python3 tool/run_swift_tests.py`
- `python3 native/test/test_navigation_window.py`

This completes the missing two-column navigation primitive, not the remaining
Material rail/drawer/bar and Tabs replacements. Full Gallery, remaining widgets,
Flutter/tooling cleanup, physical iOS runtime acceptance and Mail screenshots
remain outstanding. A fresh desktop query still reported a locked Mac; no runtime
screenshot was captured. Protected spec sources are unchanged. No source or SDK
commit/push occurred.

Final platform checks pass for physical iOS 18 arm64 and macOS 26 arm64; the full
Swift module and all ten current application entrypoints typecheck for iOS.
Mail's separate native-window inbox/expand/archive regression passes after the
wire change. Its final rebuilt development bundle passes strict/deep signature
verification, contains only arm64, and requires macOS 26.0 in both Info.plist and
Mach-O. Generated protocol/fixture and viewport checks, strict Swift formatting,
whitespace and agent decision checks pass. The complete Make aggregate was not
rerun; this is not physical-device or screenshot acceptance.

- `python3 tool/test_swift_platforms.py`
- `python3 native/test/test_mail_window.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py mail`
- `codesign --verify --deep --strict _build/swiftui/mail/BonsaiMail.app`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`
- `spec-dev-tool check --all`
- `git diff --check`

## Sidebar composition and Rail/Drawer retirement (2026-09-13)

Removed Material.Navigation_rail and Material.Navigation_drawer, their descriptor
families, Gallery's legacy calls and Flutter expressive renderer cases 17/18.
The remaining shared expressive node still serves other unmigrated components;
its OCaml encoder and decoder now reject the retired sidebar component IDs.
A protocol regression first failed because the old decoder accepted component 17.
It now requires Invalid_props for both retired IDs in both directions, while a
still-active component decodes successfully.

Added the actual Sidebar_catalog.component to Gallery and the native-sidebar
runtime fixture. It composes keyed native Buttons/Labels and selected semantics,
Mailboxes/Account groups, a bounded destination scroll, independent Compose/help
actions and optional fixed trailing content. OCaml owns destination selection,
per-destination detail counts, enabled policy, selection rejection, ordering,
visibility and modal presentation. Embedded navigation uses the native two-column
NavigationSplitView; modal navigation uses Sheet with a bounded sidebar body.
The old collapsed icon-rail appearance and Standard/Modal descriptor enum are
removed; native visibility/compact intent and explicit Sheet composition express
the new architecture. See [sidebar composition](swiftui-sidebar-composition.md).

The native regression first failed with unsupported legacy node 136. The
replacement passes actual native row and modal Button actions, accepted/rejected
selection, disabled destinations and Compose, per-destination count retention,
stable nodes under reordering/window resize and independent action history.
Native accessibility-frame measurements verify trailing help moves upward after
the destination groups and returns to its original pinned footer position.
Split requests preserve selected context. Native Sheet dismissal/reopening retains
modal controls and fences background/hidden input; presentation-structure changes
invalidate old controls. Hidden sessions and shutdown reject retained actions.

OCaml @all/@runtest/@fmt pass. The full Swift suite passes 317 tests in 72 suites
with a fresh completion report, including the final sidebar geometry assertions.
No production Swift renderer changed in this unit; the separate platform and
standalone navigation/Mail window checks from the previous two-column unit were
not rerun. The full Swift runtime suite and OCaml Mail behavior tests did run.

- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `swift test --scratch-path _build/swift --filter actualSidebarOwns`
- `python3 tool/run_swift_tests.py`

The complete Gallery, Material Tabs/navigation bars, remaining widgets, Flutter
and tooling cleanup, physical-device input/accessibility/performance acceptance,
and Mail screenshots remain outstanding. A fresh desktop query still reported a
locked Mac. No actual screenshot was captured. Protected spec sources remain
unchanged; no source or SDK commit/push occurred.

Mail was rebuilt after the final OCaml removals. Its development bundle passes
strict/deep signature verification, remains arm64-only, and requires macOS 26.0
in Info.plist and Mach-O. Generated protocol/fixture checks, viewport checks,
strict Swift formatting, whitespace and all agent decision documents pass. The
complete Make aggregate was not rerun; physical iOS execution remains unverified.

- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py mail`
- `codesign --verify --deep --strict _build/swiftui/mail/BonsaiMail.app`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`
- `spec-dev-tool check --all`
- `git diff --check`

## Tab metadata and Material Tabs retirement (2026-09-13)

View.Tabs.item now accepts optional literal badge text and an independent
accessibility label. Node 40 appends the two optional strings to key/title/symbol
and uses mask 31; the former three-property encoding and mask 7 are removed.
OCaml construction and both wire boundaries reject blank present metadata using
matching ASCII whitespace rules. Zero, the largest signed OCaml integer string,
and a bullet indicator survive the wire literally. Swift uses native TabContent
badge(Text?) and accessibilityLabel modifiers; no custom badge renderer or float
conversion was introduced. Both modifiers were first typechecked for iOS 18.

Gallery's actual tabs scenario cycles absent metadata, zero, a large count, a
bullet indicator and restored defaults. The native runtime regression verifies
retained page nodes and selection fencing while a metadata update awaits
presentation. Protocol and Swift staging tests exercise metadata round trips,
blank values, truncated updates and retention through metadata changes. The new
wire test first failed on the old three-property decoder, and the initial runtime
test found the metadata action absent. The final implementation passes both.

Material.Tabs, its Primary/Secondary appearance enum, tab descriptors and Flutter
expressive case 16 are removed. The linked choice-Picker catalog replaces the
static legacy selection-strip demonstration. First/Second now have composed
native Labels with SF Symbols. A real NSSegmentedControl test first failed because
these icon fields were absent. It now verifies label and image fields, signed ID
mapping, rejected and disabled choices, reversed ordering, whole-group disabling
and teardown. Existing Picker control/identity tests pass with the composed labels.
The expressive protocol regression now rejects retired component IDs 16/17/18
in encoding and decoding while retaining the still-active Toolbar fixture.

OCaml @all/@runtest/@fmt pass. The full Swift suite passes 320 tests in 72 suites
with a fresh completion report. The final targeted run also passes the segmented
control, existing Gallery Picker, metadata retention and unpresented-selection
regressions. Native tab accessibility-label changes and restoration were verified
through actual system controls in a standalone SwiftUI App.

A separate diagnostic that queried NSToolbarItem.badge returned no values: the
macOS native tab bar is hosted inside one toolbar item, rather than a group of
individual tab toolbar items. That query does not establish the badges within
its tab control, so it was not retained as a purported badge-appearance test.
Badge text transport and native modifier use are verified; badge appearance and
VoiceOver announcements still require visual/physical acceptance. No screenshot
was captured by that diagnostic. See [native tabs](swiftui-tabs.md).

- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `swift test --scratch-path _build/swift --filter 'actualSegmentedNavigation|actualGalleryPicker|badgeAndAccessibility|actualTabMetadata'`
- `python3 tool/run_swift_tests.py`

Material.navigation_bar and node 115 remain pending, along with the remaining
widgets, full Gallery, Flutter/tooling cleanup, physical-device acceptance and
Mail screenshots. Protected spec sources remain unchanged. No source or SDK
commit/push occurred.

Final verification: all four standalone navigation scenarios pass, including
four metadata cycles with real system-tab accessibility-label changes and
restoration. The full Swift module and all ten current application entrypoints
compile for physical iOS 18 arm64; unsupported targets fail explicitly. Mail's
separate inbox/expand/archive native-window regression passes after the new tab
encoding. Mail was rebuilt with the final code and passes strict/deep signature
verification, arm64-only architecture, and macOS 26.0 Info.plist/Mach-O minimums.
Generated protocol/fixture checks, viewport checks, strict Swift formatting,
whitespace and all agent decision documents pass. The complete Make aggregate
was not rerun. A fresh desktop query still reported a locked Mac; physical iOS
execution and all required actual screenshots remain outstanding.

- `python3 native/test/test_navigation_window.py`
- `python3 tool/test_swift_platforms.py`
- `python3 native/test/test_mail_window.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py mail`
- `codesign --verify --deep --strict _build/swiftui/mail/BonsaiMail.app`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`
- `spec-dev-tool check --all`
- `git diff --check`

## Native TabView replaces NavigationBar (2026-09-13)

Material.navigation_bar, its destination descriptors and Material-specific bar
style enums are removed from the public and private OCaml view APIs. Node 115
is removed from the schema, generated protocol IDs, wire properties, runtime
conversion, encoder and decoder. The obsolete Flutter registry entry and builder
are removed. The remaining Flutter tree is still pending full deletion; this
unit does not claim that its old tests are a valid migration pipeline.

The replacement is the existing native TabView composition: stable page keys,
OCaml-owned selection, bounded page bodies, SF Symbols, literal badge text and
independent accessibility labels. Applications can derive symbols from their
selection state; SwiftUI owns native selected appearance and platform layout.
Arbitrary icon-view slots and Material layout, sizing, visibility, density and
shape switches are removed. See [native tabs](swiftui-tabs.md) for the final API.
Gallery's redundant constant-selection bars are consolidated into its interactive
tabs scenario, while persistent bottom content remains a fixed Body child.

Before removal, a regression captured a valid node-115 incremental update with
destination labels, selected-icon flags, count and dot badges, accessibility and
bar properties. The old decoder accepted it and the rejection test failed. The
final decoder rejects those same bytes as Unknown_node_kind. Compilation also
identified an optional-u32 reader used only by that node; it is removed. The
shared destination-selection event remains for other active components.

OCaml @all/@runtest/@fmt, protocol and fixture generation checks, and viewport
checks pass. The full Swift suite passes 320 tests in 72 suites with a fresh
completion report. All four standalone system navigation scenarios pass,
including the actual Gallery's native tabs, two-/three-column sidebars and
NavigationStack Back. Badge visual acceptance remains outstanding.

- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `python3 tool/run_swift_tests.py`
- `python3 native/test/test_navigation_window.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`

Mail's standalone native-window test also passes inbox rendering, expansion and
Archive dispatch through the actual OCaml runtime. Platform checks pass for the
full Swift module and all ten application entrypoints on physical iOS 18 arm64;
Simulator and Intel macOS remain explicitly unsupported. This is a compile check,
not a claim of physical-device execution. A fresh desktop query still reports a
locked Mac, so no actual Mail screenshot was captured.

- `python3 native/test/test_mail_window.py`
- `python3 tool/test_swift_platforms.py`

The final Mail macOS bundle is rebuilt and ad-hoc signed. Strict/deep signature
verification passes; Mach-O is arm64 with minimum macOS 26.0, matching Info.plist.
Whitespace and all agent decision document checks pass. The complete Make
aggregate was not run. Remaining widgets, full standalone Gallery, complete
Flutter/tooling deletion, physical-device acceptance and required screenshots
remain open. Protected spec sources are unchanged, and no source or SDK commit
or push occurred.

- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py mail`
- `codesign --verify --deep --strict _build/swiftui/mail/BonsaiMail.app`
- `spec-dev-tool check --all`
- `git diff --check`

## Native toolbar composition and Material Toolbar retirement (2026-09-13)

View.Toolbar and Body.toolbar attach keyed core view subtrees to native SwiftUI
ToolbarItemGroups. Nine semantic placements cover automatic, principal,
navigation, primary/secondary, status, confirmation, cancellation and destructive
content. Keyed ForEach views inside each group support physical iOS 18 without
newer dynamic ToolbarContent APIs. Native placement and overflow replace the
Material floating/docked, axis, max-inline and expansion property bags. Buttons,
Toggles, Pickers and Menus own their individual command and selection semantics.
No new action dispatcher or shared index event is introduced.

Node 74 carries a bounded placement list and owns content followed by keyed
items. OCaml construction validates unique item keys, the 256-item limit and a
single principal item. Both wire boundaries validate the placement range and
principal/count limits. Swift staging additionally validates exact child count,
empty binding set and full update framing before publishing. Current and
presented toolbar properties/children must agree before command input is
admitted. The content child retains its ordinary input rules.

Material.Toolbar, its icon/action/FAB descriptors, component-19 renderer and icon
mapping helper are removed. The retired-navigation regression first confirmed
that component 19 decoded; it now rejects 16/17/18/19 in encoding and decoding
while an active AppBar fixture still decodes. The shared expressive node remains
for unmigrated components. Protected spec sources are unchanged.

Toolbar_catalog is shared by the Gallery preview and native-toolbar fixture.
It contains a principal title, action Button, controlled Pin Toggle and secondary
Menu with an unavailable action. OCaml controls the action count, selected state,
item ordering, placement, enablement and visibility. It replaces Gallery's old
static Material toolbar. The full Gallery application remains unfinished.

The initial Swift tests failed because node 74 and the actual native entrypoint
were absent. The standalone App also reported an unavailable entrypoint before
implementation. Final staging and runtime tests verify retained identity,
placement/reordering updates, removal to empty, malformed/truncated frames,
repeated actions, disabled controls, unpresented input, removal/reinsertion,
stale callbacks, Toggle/Menu actions, hidden sessions and shutdown. The first
native-window run verifies actual toolbar Button actions, native disablement,
removal/restoration, stale activation and state retention across window resize.

OCaml @all/@runtest/@fmt pass. The full Swift suite completes 323 tests in 73
suites with a fresh completion report. Generated protocol/fixtures and viewport
checks pass. See [native toolbar composition](swiftui-toolbar.md).

- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `swift test --scratch-path _build/swift --filter 'ToolbarTests|actualToolbar'`
- `python3 tool/run_swift_tests.py`
- `python3 native/test/test_navigation_window.py NavigationWindowTests.test_native_toolbar_reaches_actual_gallery`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`

Final platform checks pass for the complete Swift module and all ten current
application entrypoints on physical iOS 18 arm64. Unsupported Simulator and Intel
macOS targets fail explicitly. All five standalone window scenarios pass; the
final toolbar scenario also activates the actual native Pin Toggle in both
directions and observes the resulting OCaml text. A fresh desktop query reports
a locked Mac, so actual Mail screenshots remain unavailable. Physical iOS
execution, native overflow interaction and keyboard/VoiceOver acceptance remain
outstanding.

- `python3 native/test/test_navigation_window.py`
- `python3 tool/test_swift_platforms.py`

Mail's separate native-window inbox/expand/Archive regression passes after the
new toolbar renderer. Its final macOS bundle is rebuilt and ad-hoc signed;
strict/deep signature verification passes, and arm64/Mach-O minimum macOS 26.0
matches Info.plist. Strict Swift formatting, whitespace and all agent decision
documents pass. The complete Make aggregate was not run. AppBar/scrolling headers,
remaining controls, full Gallery, Flutter/tooling deletion, physical acceptance
and required screenshots remain open. No source or SDK commit/push occurred.

- `python3 native/test/test_mail_window.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py mail`
- `codesign --verify --deep --strict _build/swiftui/mail/BonsaiMail.app`
- `spec-dev-tool check --all`
- `git diff --check`

## Bounded navigation pages and top/bottom AppBar retirement (2026-09-13)

NavigationStack root and destination parameters now accept Body.t, matching the
bounded slots already used by Tabs and NavigationSplitView. The ordinary-View
page parameters are removed. Static pages use Body.static; typed scroll and
collection regions use the appropriate Body fill child. The stack still returns
View.t for composition inside a native container. No new wire node, fixed-height
workaround or implicit viewport conversion is introduced. Navigation, Host
Navigation, Toolbar catalog and the path fixtures use the new signature. The
viewport compilation fixture includes vertical-root and horizontal-destination
bodies.

Material.App_bar.top and .bottom and expressive renderer cases 30/15 are removed.
The old center-title/safe-area flags and bottom FAB slot are replaced by native
navigation titles, semantic Toolbar placements and fixed bottom Body content.
Ordinary core Buttons own actions and semantics. Scrolling AppBar and search
remain separate work. The retired-component regression first failed because the
old decoder accepted component 15; the final codec rejects 15/16/17/18/19/30 in
both directions while a remaining Refresh fixture still decodes.

Gallery's root now uses a bounded NavigationStack page, a native increment-counter
toolbar command and fixed bottom status. The old static bottom bar example is
consolidated into App_bar_catalog, shared by Gallery and native-app-bars. It
composes independent leading/top/bottom/Compose actions, a resizable bottom
region and a scrollable detail destination with its own toolbar and Close action.
The Compose icon has an explicit native accessibility label and help text.

The actual-runtime test verifies independent actions, retained root nodes,
covered-page input rejection, stale destination callbacks after closing, hidden
sessions and shutdown. It first failed on the missing native entrypoint. The
standalone SwiftUI App also initially reported the missing application. Its final
native controls reach OCaml; root toolbar commands are absent on the destination.
Bottom controls remain fixed while scrolling, increasing their height by 40
points reduces the viewport by 40 points, window resizing updates available width,
and the actual system Back control restores the root at its prior scroll offset.
Root and destination ScrollViews receive finite page constraints.

OCaml @all/@runtest/@fmt and the focused actual-runtime and native-window tests
pass. See [native page bars](swiftui-app-bars.md).

- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
- `swift test --scratch-path _build/swift --filter actualAppBars`
- `python3 native/test/test_navigation_window.py NavigationWindowTests.test_native_app_bars_reach_actual_gallery`

The full Swift suite completes 324 tests in 73 suites with a fresh completion
report. All six standalone window scenarios pass, including page bars, Toolbar,
NavigationStack Back, two-/three-column sidebars and Tabs. Generated protocol and
fixture checks, viewport compilation checks, strict Swift formatting and
whitespace checks pass. A fresh desktop query still reports a locked Mac; no
actual Mail screenshots were captured.

- `python3 tool/run_swift_tests.py`
- `python3 native/test/test_navigation_window.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- dune exec protocol/generator/generate_fixtures.exe -- --check`
- `opam exec --switch=bonsai-flutter-v017-exact -- sh tool/check_viewport_types.sh`

Final platform checks pass for the full Swift module and all ten current App
entrypoints targeting physical iOS 18 arm64; this does not establish device
linking, installation or execution. Mail's native-window inbox/expand/Archive
regression passes. Navigation, Host Navigation and Mail are rebuilt from the
updated source; all three ad-hoc signed bundles pass strict/deep signature,
arm64-only and Info.plist/Mach-O minimum macOS 26.0 checks. All agent decision
documents and whitespace checks pass. Protected spec sources remain unchanged;
no source or SDK commit/push occurred. The complete Make aggregate was not run.
Scrolling AppBar, search, remaining controls, full Gallery, Flutter/tooling
cleanup, physical-device acceptance and required screenshots remain open.

- `python3 tool/test_swift_platforms.py`
- `python3 native/test/test_mail_window.py`
- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py navigation`
- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py host_navigation`
- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py mail`
- `spec-dev-tool check --all`
- `git diff --check`

## Native scroll sections and scrolling AppBar retirement (2026-09-13)

View.Scroll_sections now returns typed vertical/horizontal viewports containing
keyed native sections. SwiftUI ScrollView, LazyVStack/LazyHStack and Section own
layout and pinning. Optional headers and footers have stable wrapper slots ahead
of keyed rows. A finite positive-height hero may lead a vertical container and
uses local native visualEffect geometry for optional stretching. Reduce Motion
disables that visual effect; physical elastic overscroll and its appearance are
not yet accepted. Section keys, row keys, spacing, counts, placement and ownership
are validated. The public API has no Flutter floating/snap/elevation flags.

The new root/section nodes 75/76 use masks 31/15. Their properties and graph
structure stage atomically. Current/presented section configuration and child
identity gate control activation, including pinning changes and removed headers.
Sliver AppBar and PreferredSize nodes 38/39, OCaml constructors, codec cases,
generated properties, Material entrypoint and Flutter renderer builders/host are
removed. Captured valid retired frames now fail with Unknown_node_kind; that
regression first failed while the old decoder still accepted the frame. The old
fixture is replaced with ocaml_scroll_sections.hex containing native updates.

Gallery's outer header uses a leading hero and pinned section header. Its obsolete
scroll handler is removed; scroll observer capability remains a migration
requirement. Scroll_sections_catalog supplies both axis previews and two actual
OCaml entrypoints. This does not finish the standalone Gallery: other unsupported
widget families remain. The remaining Sliver/Scroll_view APIs are still pending
horizontal virtual collections, remaining-space fill and native scroll observers.
They are not rendered by a compatibility path in SwiftUI.

The native test first failed because node 75 and the runtime entrypoints did not
exist. Final tests cover atomic malformed input, retained node identities, actual
header/footer pin rectangles, independent actions, row reordering, a 40-point
hero resize, stretch state, pinning presentation fences, header removal/recreation,
window resizing, hidden sessions and shutdown. Both axes pass in LTR and RTL.
The public OCaml contract test covers stable slots, duplicate keys, invalid
spacing and invalid hero heights/placement. See
[native scroll sections](swiftui-scroll-sections.md).

Verification completed:

- OCaml @all/@runtest/@fmt, generated protocol/fixture checks and viewport type
  checks pass.
- The full Swift run completes 327 tests in 74 suites with a fresh completion
  report; the four native section axis/direction cases pass.
- All six existing native navigation window scenarios pass. Mail's actual window
  regression still renders the inbox, expands a card and archives through OCaml.
- The complete Swift module and all ten current App entrypoints typecheck for
  physical iOS 18 arm64. Simulator and Intel macOS remain explicitly rejected.
- Mail is rebuilt and ad-hoc signed. Strict/deep signature, arm64 architecture and
  Info.plist/Mach-O minimum macOS 26.0 checks pass.
- Strict Swift formatting, whitespace and agent document validation pass.

Commands and authoritative logs for this checkpoint:

- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
  (`/tmp/scroll-sections-ocaml-final.log`)
- `python3 tool/run_swift_tests.py` (`/tmp/scroll-sections-swift-full.log`)
- `python3 native/test/test_navigation_window.py`
  (`/tmp/scroll-sections-navigation-windows.log`)
- `python3 native/test/test_mail_window.py` (`/tmp/scroll-sections-mail-window.log`)
- `python3 tool/test_swift_platforms.py` (`/tmp/scroll-sections-platforms.log`)
- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py mail`
  (`/tmp/scroll-sections-mail-build.log`)

A fresh desktop query still reports a locked Mac. No real Mail PNGs were produced;
window-test results and offscreen diagnostics are not screenshot acceptance.
Physical iOS linking/signing/installation/execution, complete widgets and Gallery,
Flutter/tooling deletion, production packaging and final source/SDK publication
remain unfinished. Protected spec sources are unchanged. No source or SDK commit
or push occurred, and the complete Make aggregate was not run.

## Horizontal collections and logical resize anchors (2026-09-13)

View.Collection.horizontal now shares the key catalog, sparse geometry,
materialized window, controller and animation path with vertical collections.
Public sizes are default_extent and extent; the former height-only names are
removed from the API, protocol and all consumers. Mail remains vertical and its
behavior tests assert that axis. The collection catalog adds a strict vertical
flag as field seven and requires mask 127. The old six-field mask is rejected;
there is no old payload decoder or constructor alias.

CollectionGeometry and CollectionAnimation now use axis-independent extent names.
Native layout assigns each item its exact width or height and uses the enclosing
cross-axis proposal, removing the old fixed-width fallback. SwiftUI mirrors Layout
placement in RTL. Viewport range calculation and stable-key relocation use the
logical leading offset. Changing axis retains the controller, viewport and
logical anchor and resolves any running extent transition immediately.

The actual-runtime horizontal test first failed because its entrypoint was
missing. Gallery now includes an interactive horizontal 10,000-item catalog in
addition to the vertical one. It uses 120-point items, a 400-point expanded item,
and the same window-loading, expansion and first-key-removal model. At a 600-point
viewport it initially loads nine items and loads thirteen after jumping to item
7,500. Its native tests verify the 120-point key relocation correction and disposed
row identities on eviction/reentry, as well as animation without extra OCaml
frames and immediate settlement on session inactivity/hiding.

The expanded native geometry tests exposed an RTL resize defect: a 200-point
window growth shifted a 40-point catalog from item 100 to item 95. The viewport
now restores its leading logical item when its scroll-axis size changes outside
user scrolling, clamping to content bounds. The regression checks actual native
offsets and the seven-point intra-item anchor, not only model state. Both axes in
LTR/RTL pass distant jumps, exact row placement, bounded materialization, sparse
expansion, interruption/reversal, reduced motion, paging, resizing, relocation and
empty-state clamping. Axis updates and retired-mask rejection have separate
staging/controller coverage. The public and viewport compilation fixtures include
horizontal collections. See [windowed collections](swiftui-collections.md).

Final verification:

- OCaml @all/@runtest/@fmt passes, including Mail behavior and both-axis protocol
  round trips. Generated protocol/fixture and viewport type checks pass.
- The focused collection run passes 16 tests in six suites. The full Swift run
  completes 328 tests in 74 suites with a fresh completion report, including all
  four axis/direction variants of the actual Gallery window and animation tests.
- The complete Swift module and all ten current App entrypoints typecheck for
  physical iOS 18 arm64. Unsupported Simulator and Intel macOS diagnostics pass.
- The actual Mail window renders the inbox, expands a card and archives through
  OCaml. Mail is rebuilt and its strict/deep ad-hoc signature, arm64 architecture
  and Info.plist/Mach-O macOS 26.0 minimum checks pass.
- Strict Swift formatting, whitespace and agent decision validation pass.

Commands and authoritative logs:

- `opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
  (`/tmp/horizontal-collection-ocaml-final.log`)
- `swift test --scratch-path _build/swift --filter Collection`
  (`/tmp/horizontal-collection-swift-final.log`)
- `python3 tool/run_swift_tests.py` (`/tmp/horizontal-collection-swift-full.log`)
- `python3 tool/test_swift_platforms.py` (`/tmp/horizontal-collection-platforms.log`)
- `python3 native/test/test_mail_window.py` (`/tmp/horizontal-collection-mail-window.log`)
- `opam exec --switch=bonsai-flutter-v017-exact -- python3 tool/build_swiftui_example.py mail`
  (`/tmp/horizontal-collection-mail-build.log`)

A fresh desktop query still reports a locked Mac; no real Mail screenshots were
captured. Physical iOS linking, signing, installation, gestures, accessibility and
performance acceptance remain open. Remaining scrolling work includes fill of
remaining space, native scroll observers, explicit initial/end positioning and
mixed-content composition before the remaining Sliver/Scroll_view surface can be
retired. Self-sizing and the full widget/Gallery migration, Flutter/tooling cleanup,
production packaging and final source/SDK publication also remain unfinished.
Protected spec sources are unchanged. No source or SDK commit/push occurred.
The complete Make aggregate was not run.

### Ordered native scroll observations

`View.Scroll`, `View.Scroll_sections`, `View.Collection` and `View.Scroll_targets`
now accept optional `on_scroll` on both axes. Each native ScrollView owns a stable
observer, even when its binding is absent. Collection visible-range and target
position bindings retain their separate contracts. No property IDs or legacy
phase decoder were added; tag 13 carries the existing finite pixels/delta pair.

Native geometry establishes a baseline, then reports movement in points from
logical leading (including horizontal RTL). Native phase changes flush pending
movement before a zero-delta boundary. Binding/axis changes, hidden or unmounted
content, and disposal invalidate callback generations. Session admission checks
current presented ownership and active content; callback toggles retain the same
NSScrollView and offset. Nested native scroll views do not share observations.

The queue compacts only adjacent nonzero same-direction increments from the same
node, handler and displayed revision. It preserves reversals, zero boundaries,
intervening input and finite-sum overflow as separate records. Pending runs are
bounded at 1,024; a valid scroll event exceeding capacity explicitly fails the
session. Copied pump batches cannot change when new callbacks arrive.

The real runtime test first failed for all eight missing Gallery entrypoints.
The queue regression separately failed for lost compaction and acceptance of a
1,025th record. `Scroll_observer_catalog` now provides all eight standalone
fixture entries and bounded previews in Gallery. Its horizontal status panel has
an explicit width: changing status text previously resized the target viewport
and correctly produced an extra native alignment movement. RTL test movement
uses the initial native clip origin, since Scroll_targets content margins make
plain document-width subtraction an incorrect logical origin.

Verification includes 16 actual window combinations (four containers, both axes,
LTR/RTL), forward/reverse travel, observer disable/enable, hidden/resumed lifetime,
stale callbacks and native identity. The nested fixture independently scrolls
inner and outer viewports, then saturates the real session queue. Pure observer
checks cover phase ordering, invalid numeric input, rebinding and disposal;
atomic tree checks preserve each container's required range/position bindings
and reject scroll bindings on ordinary nodes. Queue tests compare every flush
boundary of the 24-point reference streams and preserve copied batch bytes.

The completed full Swift run passes 336 tests in 76 suites with a fresh xUnit
completion report (`/tmp/scroll-observers-swift-full.log`). OCaml @all/@runtest/@fmt
passes (`/tmp/scroll-observers-ocaml.log`). Physical iOS 18 module and ten App
entrypoint typechecks pass, as do explicit Simulator/Intel rejection checks
(`/tmp/scroll-observers-platforms.log`). Mail window acceptance renders inbox,
expands a card and executes Archive through OCaml
(`/tmp/scroll-observers-mail-window.log`).

A subsequent Mail build exposed a Swift actor-isolation warning in the existing
stretching Section hero: its nonisolated visual-effect closure read the
Reduce Motion environment. The view now captures that boolean on the main actor
before constructing the closure, retaining the same effect calculation. Focused
Section validation and final platform/Mail rebuild results follow this capture
change; their logs use the `scroll-observers` prefix.

The desktop was checked again and is still locked. CoreDevice lists the paired
iPhone 13 as unavailable. No real Mail screenshot, physical-device runtime
acceptance or source/SDK publication is claimed. Remaining-space fill,
initial/end positioning and mixed-content composition still precede global
Sliver/Scroll_view removal. Self-sizing collections, remaining widgets, standalone
Gallery, Flutter/tooling/package deletion, production packaging and the complete
physical/visual acceptance scope remain unfinished. Protected spec sources are
unchanged; migration Dune edits remain within the user's authorization.

Final checks after the Section environment capture change:

- Focused Section staging and all four native axis/RTL window cases pass
  (`/tmp/scroll-observers-sections-final.log`, three tests in two suites).
- All three platform checks pass (`/tmp/scroll-observers-platforms-final.log`),
  including the complete physical iOS 18 module and ten App entrypoints.
- Mail window acceptance passes (`/tmp/scroll-observers-mail-window-final.log`).
  The final Mail development build succeeds
  (`/tmp/scroll-observers-mail-build-final.log`) without the actor-isolation
  warning. Strict/deep codesign verification passes; the executable is arm64,
  and both Mach-O and Info.plist require macOS 26.0. Existing Semantics unused
  insert-result warnings remain.
- Generated protocol and fixture `--check`, viewport compile checks, strict
  formatting, whitespace and `spec-dev-tool check --all` pass.

No compiler or test process was left running at this checkpoint. The full Make
aggregate and physical-device/UI screenshot acceptance were not completed.

### Native viewport minimum and Sliver fill retirement

`Scroll.vertical` and `Scroll.horizontal` now expose `fill_viewport`, defaulting
to false. A native Layout measures the content with an unspecified scroll-axis
proposal, then offers the larger of the intrinsic extent and the viewport when
filling is enabled. Existing Weighted fixed/share items distribute that space;
there is no extra Sliver-like child type or viewport measurement event through
OCaml. The same GeometryReader/ScrollView/Layout hierarchy remains mounted when
filling is toggled. Node 9 now requires three strict booleans and property mask 7;
the old mask 3 is rejected.

The actual Gallery component has fixed 80/40-point header/footer items, an
interactive filling child and length/fill toggles. Native window tests first
failed on missing entrypoints, then pass in both axes and LTR/RTL. They check
short content fills precisely, window resizing recomputes the remaining extent,
the action reaches OCaml, 900-point long content produces 1,020-point scrollable
content, and scrolling plus filling-mode changes retain offset and native
identity. The horizontal short minimum is 120 points so its text's intrinsic
width fits; the vertical minimum is 60 points. Turning filling off restores
those intrinsic extents. Existing eager-scroll resizing/offset checks also pass.

The public `Sliver.fill` constructor, private variants, wire node 34, generated
IDs, OCaml codecs/driver and residual Dart enum/props/codecs/renderer/debug/store
entries are removed. Padding coverage now uses an ordinary Sliver box. Before
removal, the protocol test encoded a real Sliver_fill frame and the rejection
assertion failed because it was accepted; the captured literal now requires
Unknown_node_kind. Atomic Swift tests also reject node 34, the previous Scroll
mask, malformed fill booleans and every truncated property prefix.

Focused validation passes three tests in two suites (four fill axis/RTL cases
plus existing eager scrolling and atomic validation), recorded in
`/tmp/scroll-fill-runtime-final.log`. OCaml @all/@runtest/@fmt passes in
`/tmp/scroll-fill-ocaml-final.log`. Generated protocol/fixtures were regenerated;
strict changed-Swift formatting, whitespace and decision validation pass.
See [native scroll content](swiftui-scroll.md#filling-a-viewport-with-ordinary-content).
Full Swift and platform/Mail verification results follow below.

The first full Swift run found a cross-axis regression in the actual Todo window:
its text editor remained 155 points wide at both 360- and 800-point window widths.
ScrollView can probe a custom Layout with an unspecified cross-axis proposal;
forwarding that proposal made the fill frame choose its intrinsic width. The
native layout now supplies the enclosing viewport's finite cross-axis extent
for both intrinsic and expanded measurements, leaving only the scroll axis
unspecified. This preserves the existing Scroll cross-axis fill contract. The
failed full run is `/tmp/scroll-fill-swift-full.log`; subsequent results are
recorded separately rather than treating that run as passing.

Final verification after fixing the cross-axis proposal:

- The focused Todo, fill and ordinary-scroll window run passes
  (`/tmp/scroll-fill-cross-axis.log`). The subsequent completed full Swift run
  passes 337 tests in 76 suites with a fresh xUnit report
  (`/tmp/scroll-fill-swift-final.log`).
- Three platform checks pass (`/tmp/scroll-fill-platforms.log`), including the
  full physical iOS 18 Swift module and ten current App entrypoints. Simulator
  and Intel macOS remain explicitly unsupported.
- The actual Mail window renders inbox, expands a card and executes Archive
  through OCaml (`/tmp/scroll-fill-mail-window.log`). The Mail development
  bundle is rebuilt (`/tmp/scroll-fill-mail-build.log`); strict/deep codesign
  verification passes, it is arm64, and Info.plist/Mach-O require macOS 26.0.
- Generated protocol and fixture checks, viewport compile checks, strict Swift
  formatting, whitespace and agent decision validation pass. Existing Semantics
  unused insert-result and OCaml native-link warnings remain.

A fresh desktop query still reports a locked Mac, so no actual Mail screenshot
was captured. Physical iOS link/sign/install/runtime and visual acceptance remain
unfinished, as do initial/end positioning, mixed virtual-content composition,
remaining widgets and standalone Gallery, complete Flutter/tooling/package
removal, production packaging and final source/SDK publication. Protected spec
sources are unchanged. No source or SDK commit/push occurred, and the full Make
aggregate was not run. All build/test processes at this checkpoint are terminal.

## Explicit initial scroll positions

Scroll and Scroll_sections now accept `initial_anchor` with logical Start/End.
Collection accepts `Initial_position.Start`, End or Item of a stable catalog key.
An unknown initial key is rejected before encoding; the immutable catalog keeps
its existing construction-time key set for constant-time membership checks.
Sparse prefix geometry determines an item's coordinate before the native
viewport mounts. The materialized window's first index is not an implicit
initial position. Changing initial configuration on an established viewport
does not replay scrolling or interrupt an active extent animation.

The protocol adds required anchor fields and the Collection optional key field.
Current masks are 15 for Scroll, 63 for Scroll_sections and 511 for Collection;
all previous shapes are rejected without compatibility decoders. OCaml tests
cover both axes, valid anchors and invalid key/anchor combinations. Swift atomic
staging tests reject malformed updates and previous masks without publishing
partial state. The controller test verifies metadata-only changes preserve the
viewport, its current offset and its in-flight animation generation.

The real Gallery fixture exercises ordinary, sectioned and virtual containers
in both axes and layout directions. Start/End and the distant Collection key
7,500 cover 28 actual window runs. Collection checks the first requested visible
range and keeps fewer than 200 materialized nodes for a 10,000-item catalog.
Changing configuration, appending, resizing and hiding/resuming preserve native
identity and an established logical offset. A further assertion changes initial
configuration before manual scrolling, so user scrolling cannot mask replay.

The first native run failed because fixture entrypoints did not exist
(`/tmp/initial-scroll-runtime-red.log`). After implementation, initial placement
passed but horizontal RTL append/resize drifted by 800/80 points
(`/tmp/initial-scroll-runtime.log`). A defaultScrollAnchor size-change role did
not correct it (`/tmp/initial-scroll-size-role.log`) and was removed. Native
geometry now corrects the logical leading point on viewport resize; ordinary
Scroll also corrects content-size changes, while lazy sections retain their own
keyed content anchoring. Corrections suspend during active user scrolling.

The 28-window run then passed (`/tmp/initial-scroll-retention.log`). The two
atomic/controller tests pass (`/tmp/initial-scroll-contract.log`), and OCaml
@all/@runtest/@fmt passes (`/tmp/initial-scroll-ocaml-final.log`). Strict formatting
of the twelve changed Swift source/test files passes. The completed full Swift
run, including the additional before-user-scroll assertion, passes 340 tests in
77 suites with a fresh xUnit report (`/tmp/initial-scroll-swift-full.log`). Three
platform checks pass (`/tmp/initial-scroll-platforms.log`), including the complete
physical iOS 18 module and all ten current App entrypoints. Mail verification
and rebuild for this exact source state follow below.

Final verification for explicit initial positions:

- The standalone Mail native window renders Inbox, expands a card and executes
  Archive through OCaml (`/tmp/initial-scroll-mail-window.log`). The Mail
  development application is rebuilt against the current runtime and Swift
  sources (`/tmp/initial-scroll-mail-build.log`). Strict/deep signature
  verification passes; both Info.plist and Mach-O require macOS 26.0 and the
  executable is arm64.
- Generated protocol and fixture checks and viewport compile checks pass
  (`/tmp/initial-scroll-final-checks.log`). Whitespace and agent decision
  validation pass. The existing Semantics unused insert-result warning remains.
- A fresh desktop query still reports a locked Mac. CoreDevice lists the paired
  iPhone 13 as unavailable. No runtime screenshot was captured, and physical iOS
  link/sign/install/runtime acceptance is still incomplete. The supported scope
  remains physical iOS 18+ and macOS 26+; Simulator remains unsupported.

Initial positioning is complete at the tested native macOS and source-level
physical iOS boundary. The overall migration remains in progress: mixed virtual
content and complete Sliver/Scroll_view retirement, remaining widget families,
self-sizing collection acceptance, full standalone Gallery, complete Flutter
and tooling/package removal, production Apple packaging, physical interaction
and accessibility acceptance, required Mail screenshots and final source/SDK
publication are still outstanding. Protected spec sources are unchanged. No
source or SDK commit/push occurred. All build/test processes for this checkpoint
have completed.

## Native refresh requests

Material.Refresh_indicator is replaced by View.Refresh.vertical, a typed wrapper
for the four native vertical viewport families. The modifier uses a SwiftUI
async refresh action, a labeled refresh button, an indeterminate ProgressView
and leading pull/release observations. The owner is cleared from scroll content
so nested viewports cannot issue its requests. Container identity is retained
while refresh state changes. Material appearance variants and the M3E controller,
component-23 renderer and its obsolete Dart test are removed. Both residual Dart
and OCaml codecs now reject the retired component.

OCaml supplies a signed request token, Ready/Pending/Completed state and optional
programmatic show token. A native request emits event 56 with the token once,
then waits through Pending acknowledgment until Completed or token replacement.
Duplicate activation shares the request. Generation checks fence old actions;
binding changes, task cancellation, hiding and removal release native waiters.
The native host does not own or cancel application network work. Node 77 admits
one supported vertical scroll child, one refresh binding and strict mask 7.

Before implementation, actual runtime tests failed for the missing entrypoints
and Swift atomic staging rejected unknown node 77 (`/tmp/refresh-swift-red.log`).
The OCaml retirement test also failed because component 23 was still decoded
(`/tmp/refresh-protocol-red.log`). The first cross-language implementation run
found a missing i64 refresh entry in the OCaml event batch codec; adding only the
UI tag/dispatcher had not made the transport understand it. The subsequent
window run verified requests but exposed a test assumption: native indeterminate
progress has AXBusyIndicator role, unlike determinate AXProgressIndicator.
The assertion now checks the actual indeterminate accessibility contract.

The four actual Gallery window cases cover ordinary Scroll, Scroll_sections,
Collection and Scroll_targets. They check one request across repeated activation,
Pending and Completed behavior, programmatic show, replacement while pending,
hidden admission and retained native ScrollView identity. Native lifecycle tests
also wait for matching completion, cancel a waiting Swift task, hide an owner,
replace the root and reject an old-generation request. Pull admission tests
cover threshold, reversal, non-user offsets, one release and stale/nonfinite
input. The focused run passes four tests in three suites
(`/tmp/refresh-swift-contract.log`), including four real OCaml window cases.
These do not establish physical trackpad/touch pull behavior or visual acceptance.

OCaml @all/@runtest/@fmt passes (`/tmp/refresh-ocaml-final.log`). Strict formatting
of the ten changed Swift source/test files, whitespace and decision validation
pass. The subsequent complete Swift run passes 344 tests in 79 suites with a
fresh xUnit report (`/tmp/refresh-swift-full.log`). Three platform checks pass,
including the full physical iOS 18 module and all ten current App entrypoints
(`/tmp/refresh-platforms.log`). Mail verification follows below. See
[native refresh](swiftui-refresh.md) for the API and completion ownership.

Final refresh verification:

- Mail passes its actual native Inbox/expansion/Archive window test
  (`/tmp/refresh-mail-window.log`) and is rebuilt from the current production
  source (`/tmp/refresh-mail-build.log`). Strict/deep ad-hoc signature verification
  passes; the executable is arm64 and both Mach-O and Info.plist require macOS
  26.0. This remains a development application rather than production packaging.
- Generated protocol/fixture checks, protocol tests, viewport compile checks and
  final formatting pass (`/tmp/refresh-final-checks.log`). The protocol retirement
  test uses an active generic Material frame as its mutation base; its error
  message no longer misnames that base as Selection. This message-only test edit
  was checked by rerunning the protocol executable.
- A fresh desktop query still reports a locked Mac; CoreDevice again lists the
  paired iPhone 13 as unavailable. No screenshots were captured. Physical iOS
  linking/signing/install/runtime and actual refresh gesture, empty/short-content
  pull, keyboard/VoiceOver and visual acceptance remain open.

The overall migration is not complete. Remaining work includes mixed virtual
content and Sliver/Scroll_view retirement, the other unported widgets and host
extension/composer services, self-sizing collections, full standalone Gallery,
Flutter/Dart/tooling/package removal, production Apple packaging, physical
interaction and accessibility acceptance, Mail navigation-return acceptance,
required Mail PNGs/manifest and final source/SDK publication. Protected spec
sources are unchanged. No source or SDK commit/push occurred. All build/test
processes for this checkpoint have completed.

## Native per-item removal

View.Removal.create replaces Material.Dismissible_list.column/horizontal with
one keyed child per wrapper. The application owns the surrounding layout and
item data source. Each item carries its own request token and
Ready/Pending/Accepted/Rejected state. Requests report token and logical direction;
accepted native collapse reports the same token once through on_removed before
OCaml removes the item. Drag and collapse axes are independent. Components 10/11,
their OCaml constructors, Dart hosts, confirmation helper and obsolete tests are
removed. Both residual wire decoders reject these retired Material components.
See [native per-item removal](swiftui-removal.md).

Node 78 requires mask 63, one child and exactly request/completion bindings 57/58.
Atomic staging rejects malformed state, flags, title, children and truncations.
The platform pan adapter is shared with SwipeActions through NativePanTarget;
there is no second gesture recognizer implementation. Native context-menu and
accessibility commands share gesture admission. Token/binding/root replacement,
inactive presentation and queue admission fence stale requests and completions.

Before implementation, the focused Swift tests failed for unsupported node 78
and missing runtime entrypoints (`/tmp/removal-swift-red.log`). The OCaml wire
retirement test failed because component 10 still decoded
(`/tmp/removal-protocol-red.log`). After implementation, two tests in two suites
pass (`/tmp/removal-swift-first.log`), including four real OCaml window cases for
both drag axes and layout directions. They verify duplicate suppression while
pending, rejection with retained child identity, token replacement, accepted
removal of the matching item and single completion after hide/resume.

The new standalone native mouse gate posts events through NSApplication, rather
than invoking gesture controller methods. Its first run passed six of eight
cases; two horizontal drags started at the window resize border and never
reached the content recognizer. Diagnostic state remained Ready with zero offset.
The test now asserts that its drag points are inside the window content area,
with a 24-point horizontal inset. All eight axis/layout/swipe-direction cases
pass (`/tmp/removal-native-inset.log`), including cross-axis rejection, logical
RTL direction received by OCaml, pending content preservation and confirmation.
The shared SwipeActions native mouse gate also passes all three cases
(`/tmp/removal-swipe-regression.log`). No production recognizer change was needed
for the window-border test issue.

Native layout measurements cover both collapse dimensions
(`/tmp/removal-collapse-first.log`): accepted animation reaches an intermediate
extent, replacement restores the full extent and retains the child, Reduce
Motion settles immediately, hidden completion waits for resumed presentation,
and root replacement suppresses old completion. The test supplies the native
controller's Reduce Motion environment signal; physical settings/VoiceOver and
trackpad/touch acceptance remain open.

After formatting and removal of the unused Dart confirmation helper,
`opam exec --switch=bonsai-flutter-v017-exact -- dune build @all @runtest @fmt`
passes (`/tmp/removal-ocaml-final.log`). The subsequent complete Swift regression,
physical-iOS compilation and current Mail rebuild are being verified separately.

Final per-item removal verification:

- Complete Swift regression passes 347 tests in 80 suites, with a fresh completed
  Swift Testing xUnit report (`/tmp/removal-swift-full.log`, 298.565 seconds).
- Three platform checks pass (`/tmp/removal-platforms.log`), including physical
  iOS 18 module and all ten current App entrypoints; Simulator and Intel macOS
  remain explicitly rejected.
- Mail passes its actual native inbox/expansion/Archive gate
  (`/tmp/removal-mail-window.log`) and the standalone Mail application rebuilds
  (`/tmp/removal-mail-build.log`). Strict/deep signature, arm64 architecture,
  Mach-O minimum macOS 26.0 and Info.plist minimum 26.0 checks pass.
- Generated protocol/fixtures, viewport compile checks and whitespace checks pass
  (`/tmp/removal-final-checks.log`). Changed Swift files pass strict formatting;
  all 49 agent documents pass decision validation.

A fresh desktop query still reports a locked Mac. This run additionally used the
existing Mail window-content exporter. Two real-runtime diagnostic PNGs now exist
under `docs/screenshots/swiftui-mail/diagnostics/`, with provenance and reproduction
steps in the [capture README](screenshots/swiftui-mail/README.md). Visual inspection
found missing sidebar content and incomplete native/background layer capture;
these are not accepted full-window screenshots. They show the current inbox and
expanded card but do not resolve whether each visual issue is an export limitation
or an application defect. Required full macOS and all physical iOS captures remain
incomplete. The PNGs are unedited output from the real OCaml-backed application.

The overall migration remains in progress: mixed virtual content, remaining
widget families, self-sizing collection acceptance, full standalone Gallery,
complete Flutter/Dart/tooling/package removal, production packaging, physical iOS
execution and accessibility, Mail navigation-return acceptance and reviewed
screenshots remain outstanding. Protected spec sources are unchanged. No source
or generated SDK commit/push occurred. All processes for this verification
checkpoint have completed.

## Native contextual selection composition

Material.Selection and Selection.leading now use keyed native Toggle labels and
View.Toolbar inside a Navigation_stack page. Contextual_selection_catalog is
shared by Gallery and the actual OCaml runtime fixture. OCaml owns membership,
eligible IDs, selected count, idle/contextual commands and archive results.
Select-all derives current eligible IDs; independent membership intents compose
against current state; batch commands include preceding queued membership
changes. Native controls retain identity across selected-label changes and
reordering. Item removal prunes selection and retires its old callbacks.
See [contextual selection](swiftui-contextual-selection.md).

The old Material constructors, component-9 Selection host/controller, component-29
leading renderer and related Dart tests are removed. The unused Selection event
35, its OCaml Int64_list input payload, codec/dispatcher cases and private helper
parameter are also removed. Protocol artifacts are regenerated. The leftover
Dart segmented-button renderer and expandable-list renderer using event 35 are
deleted; the whole historical Flutter integration tree remains part of the
unfinished Flutter removal. No replacement node, event, alias or decoder is added.
Material flip presentation and implicit PopScope back interception are removed;
application navigation policy and an explicit clear-selection command replace
the implicit behavior.

RED evidence:

- `/tmp/contextual-selection-swift-red.log`: the actual runtime regression fails
  with startupFailed because native-contextual-selection does not yet exist.
  Initial missing `try` syntax in the test was corrected before this RED result.
- `/tmp/contextual-selection-protocol-red.log`: component 9 still decodes.
- `/tmp/contextual-selection-window-red.log`: the standalone App shows Unable to
  open application instead of the expected selected-set status.
- `/tmp/contextual-selection-event-red.log`: event 35 fails as malformed payload
  rather than Unknown_event_tag, proving that its obsolete decoder still exists.

The implemented runtime regression passes
(`/tmp/contextual-selection-swift-first.log`). It verifies signed IDs, disabled
items, two queued choices, clear, ignored requests, select-all, disabled actions,
reordering identity, data-source removal, batch removal, replacement nodes, hidden
input and shutdown. A batch action queued after a second membership request
archives both selected IDs, proving that the handler uses the current model.

The first native window run could not press Select all items because its query
selected the outer toolbar accessibility proxy. Existing native toolbar tests
query NSToolbar item views. Using that same actual-control boundary, the new
window gate passes at 900- and 640-point widths
(`/tmp/contextual-selection-window-toolbar.log`, 23.239 seconds). It presses
native Toggles and toolbar controls, verifies checked state, select-all, clear,
rejection restoration, disabled controls and archive. It does not invoke Bonsai
controller methods. Keyboard/VoiceOver, physical touch, actual overflow and visual
acceptance remain open.

After cleanup and formatting, OCaml @all/@runtest/@fmt, generated protocol and
fixture checks, viewport compile checks, whitespace and all 49 decision-document
checks pass (`/tmp/contextual-selection-final-checks.log`). Complete Swift and
platform verification follows separately below.

Final contextual-selection verification after event retirement:

- Complete Swift regression passes 348 tests in 80 suites with a fresh completed
  Swift Testing xUnit report (`/tmp/contextual-selection-swift-full.log`,
  295.853 seconds).
- Three platform checks pass (`/tmp/contextual-selection-platforms.log`), including
  the physical iOS 18 module and ten current App entrypoints. Simulator and Intel
  macOS remain explicitly rejected. This is compilation evidence, not physical
  device execution.
- The standalone contextual-selection App passes again after generated protocol
  changes (`/tmp/contextual-selection-window-final.log`, 23.259 seconds), covering
  native Toggle and contextual toolbar operations at both widths.
- Changed Swift tests/harness pass strict formatting. Final whitespace and
  decision-document checks pass. No protected spec source changed.

No new Mail capture was taken in this unit. The previous real-runtime diagnostic
PNGs and their known incomplete layer/sidebar output remain documented in the
[capture README](screenshots/swiftui-mail/README.md); they do not satisfy full
screenshot acceptance. Mail's latest standalone build/window evidence remains
that recorded in the per-item-removal checkpoint.

The full migration is still incomplete. Remaining work includes search, DataTable,
button/focus and host-extension/composer capabilities, mixed virtual composition
and Sliver/Scroll_view retirement, self-sizing collection acceptance, standalone
Gallery, complete Flutter/Dart and tooling/package removal, production Apple
packaging, physical iOS interaction/accessibility and complete reviewed Mail
screenshots. No source or generated SDK commit/push occurred. All build/test
processes for this checkpoint have completed.

## Native search composition and text-limit delivery

Search_catalog.component now provides inline search, anchored Popover search and
full-screen search using the existing native text field, suggestion Buttons and
presentation primitives. The full-screen search command lives in the native
Toolbar. OCaml owns query filtering, suggestion eligibility, submitted text,
selection, idempotent opening, rejected/accepted closing and retained query state.
Gallery embeds all three real-runtime scenarios. See
[native search](swiftui-search.md).

The first native harness passed bare numeric mode arguments. macOS treated those
as files to open and never created the initial SwiftUI Window. All three processes
timed out; these were test setup errors, not functional RED. A sample of the last
live process showed only the idle NSApplication run loop
(`/tmp/search-red-sample.txt`). After switching to --inline/--anchored/--fullscreen,
all three windows launch and fail on the absent Search: Closed state
(`/tmp/search-window-red-flags.log`). The protocol retirement test separately
fails because event 48 is still accepted (`/tmp/search-protocol-red.log`).

After the first implementation, all three native scenarios reach query filtering,
CJK/emoji marked text, UTF-16 selection and submission, but fail at Limits: 1
(`/tmp/search-window-first.log`). Additional state diagnostics show Limits: 0 in
every presentation (`/tmp/search-window-diagnostic.log`). The shared OCaml event
dispatcher had no Text_limit_reached tag or Unit-payload conversion, even though
the field and codec already emitted/decoded that event. Adding those two missing
conversions fixes delivery for ordinary and search text fields alike.

All three native scenarios then pass (`/tmp/search-window-limit-fixed.log`,
32.365 seconds). The actual AppKit field editor and native accessibility controls
verify suggestion filtering, empty results, disabled suggestions, stale removed
controls, marked text and selection, retained field identity, submission,
UTF-8 limits, clear-query replacement, read-only/enabled state, rejected close,
selection effects and reopening with the same canonical query. Physical iOS,
VoiceOver, native interactive-dismiss gestures and visual acceptance remain open.

The public Material search constructors are removed. Their departure leaves no
producer of generic Material expressive nodes, so node 129 and node 136 are
removed completely from the OCaml view, private APIs, driver, wire properties,
encoders/decoders and schema. Events 48/49, private expressive text editing,
legacy keyboard_type/input_action enums and corresponding wire enums are removed.
Modern Text_editing.Keyboard and Submit_label remain. Generated protocol and
fixtures are updated. All former expressive components now fail as an unknown
node kind; no per-component compatibility decoder remains. Related Dart registry,
codec branches and obsolete tests are deleted. Historical Flutter model/debug
and integration files remain part of the unfinished whole-tree deletion.

During deletion, the compiler caught a leftover local search-value expression in
Gallery and an unused Material test helper. Both were removed. OCaml @all/@runtest
passes (`/tmp/search-ocaml-tests.log`), followed by @all/@runtest/@fmt, generator,
fixture, viewport and decision validation (`/tmp/search-final-checks.log`). That
final command first stopped only on whitespace left by deleted schema forms;
cleaning those lines gives passing generator/fixture/whitespace/Swift-format
checks (`/tmp/search-checks-clean.log`). Dart's formatter parsed the three changed
runtime files; its missing flutter_lints package warning is not claimed as a Dart
analysis or Flutter build pass. Complete Swift/platform verification follows.

Final search verification after protocol deletion:

- Complete Swift regression passes 348 tests in 80 suites with a fresh completed
  xUnit report (`/tmp/search-swift-full.log`, 296.350 seconds). The three new search
  scenarios run in the separate native App gate rather than increasing that
  Swift Testing count.
- Three platform checks pass (`/tmp/search-platforms.log`), including the physical
  iOS 18 module and all ten current App entrypoints. Simulator and Intel macOS
  remain explicitly rejected.
- All three search App scenarios pass again after node/event deletion
  (`/tmp/search-window-final.log`, 31.667 seconds).
- Mail passes actual native inbox, card expansion and Archive
  (`/tmp/search-mail-window.log`). Its standalone application rebuilds
  (`/tmp/search-mail-build.log`) and passes strict/deep ad-hoc signature, arm64,
  Mach-O minimum macOS 26.0 and Info.plist minimum 26.0 verification
  (`/tmp/search-mail-verification.log`). This is a development bundle.

A fresh desktop check still reports a locked Mac; CoreDevice lists the paired
iPhone 13 as unavailable (`/tmp/search-devices.log`). No new screenshot was taken.
The earlier real-runtime content exports remain diagnostic only, with their
missing sidebar/background capture documented in the
[capture README](screenshots/swiftui-mail/README.md). Complete macOS window captures
and all physical iOS execution/interaction/screenshots remain outstanding.

The overall migration is not complete. Remaining work includes buttons/FAB and
DataTable, focus/keyboard and host-extension/composer capabilities, mixed virtual
content and Sliver/Scroll_view retirement, self-sizing collection acceptance,
full standalone Gallery, entire Flutter/Dart and tooling/package removal,
production Apple packaging, physical acceptance, Mail navigation-return acceptance
and reviewed screenshots. Protected spec sources are unchanged. No source or
SDK commit/push occurred. All build/test processes for this checkpoint have
completed.

## Table API feasibility

The next Table migration unit now has a reproducible independent Apple API probe
in `tool/probe_swiftui_table.swift`, driven by `tool/test_swiftui_table_api.py`.
This is exploratory verification, not a production implementation or an observed
RED/GREEN cycle for the Bonsai Table. See [the investigation](swiftui-table.md).

An initial direct `if/else` between sortable and non-sortable columns fails
typechecking because their comparator types differ (`ProbeSort` and `Never`).
Using two mutually exclusive optional columns in a typed TableColumnBuilder
compiles and renders exactly the ordered metadata columns. The native App probe
verifies selection eligibility, an actual cell Button action on the ineligible
row, multi-selection binding, rejected selection/sort restoration, canonical
data order despite sorting intents, stable selection across row reorder, and
dynamic column changes without native Table recreation. Property setters drive
the selection/sort callbacks; this does not establish mouse or keyboard behavior.

Both the actual macOS 26 arm64 executable and physical iOS 18 arm64 typecheck
pass (`/tmp/table-api-platforms.log`, two checks, 3.199 seconds). The SwiftUI
header API accepts Text rather than arbitrary View content, so the replacement
must explicitly compose richer header/help capabilities. Native Table remains
the selected regular-width presentation; the compact iOS row/detail composition
and full OCaml/transport/controller integration remain unimplemented.

No production runtime, OCaml, protocol, Dune or protected spec source changed in
this investigation. The full 348-test Swift result remains the previous Search
checkpoint; it was not rerun or claimed as new Table integration evidence. No
Mail screenshot, source commit/push or generated SDK update occurred.

## Controlled native Table and compact rows

View.Table now provides a finite Body with native Table at regular width and
complete labeled rows at compact width. Columns carry native text titles,
optional help/rich details, alignment and sortability; rows carry eligibility
and ordinary cell content. OCaml owns the canonical selected set and business
sort. The real Gallery Table_catalog scene supplies sort/selection acceptance
and rejection, independent cell actions, select-all/clear, row removal, column
reorder, empty data and reset. See [native Table](swiftui-table.md).

The first real-runtime native/compact window tests fail on missing initial state
before the feature exists (`/tmp/table-window-red.log`, both scenarios). The
retired-node test separately proves node 131 is still decoded instead of rejected
(`/tmp/table-protocol-red.log`). After the first implementation, the native test
reaches rejection but assumes a particular number of membership events; native
selection can submit more than one delta, so it now waits for an increase rather
than a fixed count. That was a test assumption, not a production correction.

The first compact scenario crashes in NativeTable.child during delayed lazy-cell
rendering (`/tmp/table-window-first.log`; the TableWindowAcceptance crash report
at 09:56:12 identifies the call). Capturing the children array corresponding to
each immutable Table property snapshot prevents old row builders from indexing
new shorter arrays. Both real-runtime scenarios then pass
(`/tmp/table-window-snapshot.log`, 25.619 seconds).

The lifecycle integration test subsequently exposes activation of collapsed rich
header content (`/tmp/table-lifecycle-red.log`). The controller now owns the
DisclosureGroup expansion state and the session gates header-child input on
that state and the presented table configuration. The test passes
(`/tmp/table-lifecycle-green.log`), including invalid/disabled intents, stale
bindings and removed cell actions, full queue rejection, hidden application and
disposal. Native window tests additionally open/close details and check an action
counter to prove retained input after closing has no effect. Both scenarios pass
(`/tmp/table-window-final.log`, 26.568 seconds).

Protocol Table node 79 replaces node 131. Old Material constructors, duplicate
row selection and cell flag bags are removed. Events 39/40 are retired after an
observed rejection-test failure (`/tmp/table-events-red.log`); application Button
commands replace table-specific select-all and cell activation. Sort and row
membership retain semantic events 37/38. A separate protocol test catches an
encoder accepting a selected non-sortable column
(`/tmp/table-sort-validation-red.log`); the shared encode/decode validator now
rejects it, matching the public API and native decoder.

The related Dart registry, codec and event branches are removed. Historical
Flutter model/integration files still await whole-tree deletion. Dart's formatter
parses the four edited files but reports the existing missing flutter_lints
package; this is not a Flutter analysis/build pass. Generated protocol and
fixtures are updated. OCaml @all/@runtest/@fmt passes
(`/tmp/table-ocaml-final2.log`). An existing shallow equality test initially
compared the new outer Frame instead of the underlying Table; the test now
unwraps Body for its intended Table-properties equality assertion.

Table metadata indexes avoid repeated row/column scans for cell lookup and
selection admission. Native selection submits eligible membership deltas in
stable ID order and stops when queue admission fails. Complete Swift and final
platform/window checks follow below. Physical iOS, mouse/header/keyboard and
VoiceOver acceptance remain outstanding. The full migration remains incomplete;
no Mail screenshot, source commit/push or generated SDK update occurred.

Final Table checkpoint after metadata indexing:

- Complete Swift regression passes 349 tests in 80 suites with a fresh completed
  xUnit report (`/tmp/table-swift-full.log`, 296.399 seconds).
- Both real OCaml Table window modes pass again
  (`/tmp/table-window-refactor.log`, 25.811 seconds), including the details action
  counter after closing. This supersedes the earlier pre-refactor window run.
- All three platform checks pass (`/tmp/table-platforms.log`, 17.274 seconds):
  the physical iOS 18 module and ten App entrypoints compile; Simulator and Intel
  macOS remain explicitly rejected.
- Mail's actual native inbox, expansion and Archive test passes
  (`/tmp/table-mail-window.log`, 21.729 seconds). Its standalone development
  bundle rebuilds (`/tmp/table-mail-build.log`) and passes strict/deep ad-hoc
  signature verification. Its executable is arm64 and both Mach-O and Info.plist
  require macOS 26.0 (`/tmp/table-mail-*.log`). Existing Semantics.swift unused
  insert-result warnings remain; this is not production packaging/signing.
- Generated protocol/fixtures, Swift strict formatting, viewport typing,
  whitespace and all 49 decision documents validate. Protected OCaml spec
  sources are unchanged. All compilation/test processes for this checkpoint
  have completed.

The overall migration remains in progress. Remaining work includes buttons/FAB,
focus/keyboard and host-extension/composer capabilities, mixed virtual content
and Sliver/Scroll_view retirement, self-sizing collection acceptance, standalone
Gallery, complete Flutter/Dart/tooling/package removal, production Apple packaging,
physical iOS acceptance, Mail navigation-return acceptance and complete reviewed
screenshots. No source or generated SDK commit/push and no new screenshot occurred.

## Mixed catalog composition and RTL empty-state recovery

Gallery now includes `Mixed_collection_catalog` in both axes: a keyed header,
3,000 fixed rows, an interlude, 7,000 varied rows and a keyed footer. The real
application owns flattening, declared extents, group reorder, header changes,
visible-window records and actions. Catalog construction excludes window-only
state. The runtime fixture exposes the same component as `native-mixed-v` and
`native-mixed-h`; it does not duplicate the application model in Swift.

The initial NSHostingView test allowed its intrinsic content to resize the host,
producing a zero-width horizontal viewport. Bounding the test host corrected
that harness issue and exposed a separate reproducible horizontal RTL failure:
clearing the catalog and restoring it caused repeated ScrollPosition work on
the main thread. The sampled helper was terminated after confirming it remained
live at approximately 99% CPU; observation timeouts were not treated as process
completion. Temporary phase/geometry instrumentation was removed after diagnosis.

The independent SwiftUI App regression also timed out after 30 seconds only
for horizontal RTL (`/tmp/mixed-app-red.log`); the other three direction cases
passed. GeometryReader now supplies the finite viewport size to a minimum
content frame, preserving a valid leading coordinate for an empty or short
document while retaining declared item extents. All four independent App cases
pass reset and a native accessibility action through OCaml after this change
(`/tmp/mixed-app-green.log`, 23.403 seconds).

Focused final evidence (`/tmp/mixed-final.log`, 23.896 seconds) includes two
tests, with four native-window cases. It checks item 7,500, bounded materialization,
offscreen expansion, header resize/removal, group reorder, native window resize,
interlude crossings, footer actions, empty/reset, stable overlapping row identity
and rejection of an evicted header action. The native wire test verifies that a
visible-window update does not republish the catalog and stays below 16 KiB.
OCaml `@all @runtest @fmt` passes (`/tmp/mixed-ocaml-final.log`), with existing
linker warnings. Protected OCaml spec sources remain unchanged.

The complete Swift run passes 351 tests in 80 suites with a fresh completed
xUnit report (`/tmp/mixed-swift-full.log`, 316.172 seconds). All three platform
checks pass (`/tmp/mixed-platforms.log`, 17.093 seconds), including physical
iOS 18 module/App source compilation and explicit Simulator/Intel rejection.
Strict Swift formatting, whitespace and all 49 decision documents validate.
The actual Mail window passes inbox, expansion and Archive again
(`/tmp/mixed-mail-window.log`, 22.821 seconds). Its development App rebuilds
from the current sources (`/tmp/mixed-mail-build.log`) and passes strict/deep
ad-hoc signature verification. The executable is arm64; both its Mach-O minimum
and Info.plist minimum are macOS 26.0. Existing Semantics.swift unused-result
warnings remain. All test and build processes for this checkpoint have ended.
The desktop was rechecked for complete Mail screenshot capture and remained
locked; diagnostic PNGs from the earlier checkpoint are still not accepted
full-window images.

This unit does not retire the remaining Sliver/Scroll_view surface, implement
self-sizing or pinned virtual headers, or establish physical iOS/pointer/keyboard
acceptance. Full Gallery packaging, other remaining widget families, complete
Flutter/Dart/tooling/package removal, production Apple packaging, Mail acceptance
and reviewed screenshots remain required. No source/SDK commit or push and no
new Mail screenshot occurred in this unit.

## Retire the OCaml Sliver and Scroll_view surface

The public/private Sliver and Scroll_view constructors, the Sparse_extent_override
and Sparse_extent_transition modules, cache derivation and implicit-anchor bags
are deleted. The driver, Wire_frame types, binary encoders/decoders, schema and
generated OCaml/Swift declarations no longer contain nodes 30, 32, 33, 35, 36 or
37. Fixed/sparse collections use the existing catalog/window path; eager content
uses Scroll. No alias, compatibility constructor or old decoder is retained.

Before deletion, extending the protocol rejection test to node 30 failed because
the decoder still recognized that node and attempted to read its old payload
(`/tmp/retire-scroll-red.log`). After deletion the same test passes with
Unknown_node_kind. Swift publication checks also require unsupportedNode for
these IDs and the previously retired fill node 34
(`/tmp/retire-scroll-swift-green.log`).

The keyed overlap reconciliation test now uses a Collection catalog and retains
its create/drop/identity assertions. Duplicate materialized keys are rejected at
the new constructor boundary. The canonical root-key/test-ID/fingerprint test,
leading/middle/trailing overscan clamps, empty windows and visible-range callback
checks use Collection. Typed body and eager-content tests use Scroll. Obsolete
cache/primary/reverse/transition-bag tests are removed; existing Collection
validation, geometry, animation and native runtime tests cover the new contracts.
Native extension and composer tests are retained, including their dial fixture.

The primary-scroll fixture is removed and the bounded-body fixture now carries a
catalog/window pair. Virtual-list and viewport guides describe the current API,
including empty initial windows, explicit initial positions and finite Body
allocation. The custom-widget guide points to the core collection contract.

OCaml `@all @runtest @fmt` passes (`/tmp/retire-scroll-ocaml-final.log`). Generated
protocol/fixture checks and viewport compile-failure checks pass. Handwritten
Swift formatting, whitespace and all 49 decision documents validate. The
generator's canonical Swift output uses its own formatting; running the default
Swift formatter against it reports style differences, so it is validated through
the generator's exact-output check rather than edited by hand. Protected OCaml
spec sources remain unchanged.

This removes the old scroll API from the OCaml/SwiftUI path. Legacy Flutter source
deletion, remaining widget families, self-sizing/physical-device acceptance,
standalone Gallery, tooling/package replacement, Apple production packaging and
complete Mail screenshots remain unfinished. No source or SDK commit/push occurs
in this unit.

The full Swift regression after scroll API retirement passes 351 tests in 80
suites with a fresh completed xUnit report (`/tmp/retire-scroll-swift-full.log`,
316.304 seconds). All three platform checks pass
(`/tmp/retire-scroll-platforms.log`, 18.051 seconds), including the physical
iOS 18 module and ten App entrypoints. The actual Mail window again passes
inbox, expansion and Archive (`/tmp/retire-scroll-mail-window.log`, 21.908 seconds).
The desktop was rechecked for formal Mail capture and remains locked; no new
screenshot or visual acceptance is claimed.

Mail's standalone development App rebuilds from the current OCaml object
(`/tmp/retire-scroll-mail-build.log`) and passes strict/deep ad-hoc signature
verification (`/tmp/retire-scroll-mail-signature.log`). Its executable is arm64,
with macOS 26.0 recorded in both Mach-O and Info.plist. Existing Semantics.swift
unused-result warnings remain. All processes used for this checkpoint have
completed; no native test or compilation is left running.


## Application SwiftUI view registration

`BonsaiNativeViews` is a startup-only value registry for node 128/event 21.
Registrations carry one exact kind/version, capabilities, typed property/event
codecs, a SwiftUI content factory and per-node resource creation/disposal.
`BonsaiApplicationView` accepts the registry and copies it into its session.
Unknown kinds, wrong versions, unsupported capabilities and decoder failures
reject the complete candidate frame before resources are allocated. Compatible
updates preserve the resource and SwiftUI identity. Kind replacement, epoch
replacement, removal and session closure dispose each instance exactly once.
There is no global mutable registry, version fallback or placeholder view.

`Native_view_catalog` supplies the real OCaml scene. The main Gallery now uses
its exported card definition instead of defining a second schema. The original
wire test failed with unsupportedNode(128) (`/tmp/native-view-wire-red.log`).
Native windows now dispatch typed SwiftUI events and keyed OCaml child actions
through the actual OCaml model. The integration checks cover property, handler,
child and kind replacement, hidden children, visibility changes, retained local
SwiftUI @State, resource identity/disposal, rejected frames, invalid events and
noncoalesced queue admission through 1,024 events. Seven focused tests pass
(`/tmp/native-view-final-focused.log`, 2.402 seconds).

A nine-instance nested scene exposed presentation ordering: dictionary traversal
enabled the outer instance but left inner instances unable to dispatch after one
acknowledgment (`/tmp/native-view-nested-red.log`). The session now establishes
parent ownership before visiting descendants. The focused regression requires
all nine events to reach OCaml after a single presentation acknowledgment.

The independent App window also passes native activation, OCaml child activation,
SwiftUI local-state retention, removal/reinsertion and final session disposal
(`/tmp/native-view-window.log`, 22.943 seconds, before the final nested-scene
addition). The standalone compiler initially rejected a main-actor default
argument in Swift 5 language mode; the empty value registry initializer is now
nonisolated, while registration and ownership remain on the main actor. A Swift
compiler assertion in a nested Testing macro was resolved by binding the required
closure before invoking it; neither setup failure is counted as behavioral RED.

The custom-widget guide now documents the SwiftUI API and removes its obsolete
Dart registration and retired built-in examples. The remaining composer migration,
full Gallery, button/focus work, final Flutter/tooling/package deletion, physical
iOS acceptance, production packaging and reviewed Mail screenshots are still
required. The desktop was rechecked and remains locked. No new screenshot,
source/SDK commit or push is claimed.


The final full regression passes 358 tests in 81 suites with a fresh completed
xUnit report (`/tmp/native-view-swift-full.log`, 317.291 seconds). Physical iOS 18
module and ten App entrypoint compilation, supported-platform checks and explicit
Simulator/Intel rejection all pass (`/tmp/native-view-platforms.log`, 17.606
seconds). The independent registered-view App was rerun against the final source
and passes (`/tmp/native-view-window-final.log`, 21.974 seconds). OCaml
`@all @runtest @fmt` passes (`/tmp/native-view-ocaml-final.log`); existing linker
warnings remain. Handwritten Swift formatting, whitespace and all 49 decision
documents validate. Protected OCaml spec sources are unchanged.

The actual Mail window passes inbox, expansion and Archive again
(`/tmp/native-view-mail-window.log`, 22.178 seconds). Its standalone development
App rebuilds (`/tmp/native-view-mail-build.log`) and passes strict/deep ad-hoc
signature verification. The executable is arm64; both Mach-O and Info.plist
require macOS 26.0. Existing Semantics.swift unused-result warnings remain.
Generated protocol/fixture exact-output checks and viewport compile-failure
checks pass. All build and test processes for this checkpoint have completed.
No new screenshot or production-signing acceptance is claimed.


## Standard SwiftUI message composer

The ordinary kind-6/version-1 composer now uses one SwiftUI surface and an
explicitly ephemeral native draft, backed by NativeTextController/TextSession.
The standard registration is installed per render tree and reserved against
application replacement. Typed registration child-count validation runs before
publication, even when properties are cached. The composer requires one
noninteractive decorative child for each action and rejects malformed payloads
without replacing the current tree. No alternate decoder or fallback is added.

The real Composer_catalog scene is part of Gallery and the native runtime
fixture. The initial integration tests fail with unregisteredKind(6)
(`/tmp/composer-red.log`); the reserved-registration check also demonstrates
that replacement was previously accepted (`/tmp/composer-validation-red.log`).
The implementation retains draft, selection, composing ranges and native editor
identity across metadata changes, supports native actions and collapse, and
rolls back edits rejected by queue/byte limits. Sending retains the exact raw
draft. A keyed replacement or disposal releases native callbacks/delegates.

The separate App window verifies native autofocus, five-line/three-line sizing,
collapse/re-expansion, raw actions, whitespace visibility and identity/reset
(`/tmp/composer-window.log`, 23.792 seconds). This is programmatic AppKit focus,
not physical keyboard/touch acceptance. The shared text-editor representable only
uses adaptive height when a composer supplies maximumLines; ordinary editor
sizing stays on its existing path. UIKit requires an explicit nil drawing
context for NSString measurement; the platform check exposed and verified that
platform-specific call (`/tmp/composer-platforms-final.log`, three checks,
17.737 seconds).

The first full run passes 362 tests in 81 suites with a completed xUnit report
(`/tmp/composer-swift-full.log`, 321.710 seconds). Subsequent inspection found that
Swift String equality would skip a text observation for canonically equivalent
but byte-distinct spellings. The new real-editor regression fails because OCaml
receives only one change (`/tmp/composer-unicode-red.log`). UTF-8 element comparison
fixes it; all five focused composer tests now pass
(`/tmp/composer-focused-final.log`, 2.882 seconds). The final full-source verification is recorded below.

OCaml @all/@runtest/@fmt passes (`/tmp/composer-ocaml-final.log`). The user-facing
composer/native-view guides and governing proposal document the ephemeral draft,
shared byte limit, standard registration and required remaining work. Protected
OCaml spec files are unchanged. Expandable composer presentation, physical input
acceptance, remaining widget families, standalone Gallery, complete Flutter and
tooling/package deletion, production packaging, physical iOS and reviewed Mail
screenshots remain unfinished. The desktop was rechecked and remains locked.
No screenshot, source/SDK commit or push is claimed in this unit.


The final source passes 363 Swift tests in 81 suites with a fresh completed
xUnit report (`/tmp/composer-swift-final.log`, 321.771 seconds). All three platform
checks pass against the final source (`/tmp/composer-platforms-current.log`,
17.753 seconds), including the physical iOS 18 module and ten App entrypoints,
plus explicit Simulator/Intel rejection. The separate composer App window also
passes again (`/tmp/composer-window-final.log`, 22.786 seconds). The earlier
AppKit/UIKit signature mismatch was a platform compilation issue, not a behavioral
RED result. The actual behavioral failures are the missing standard registration
and skipped Unicode text observation recorded above.

The actual Mail window passes inbox, expanded preview and Archive
(`/tmp/composer-mail-window.log`, 22.709 seconds). Mail's standalone development
App rebuilds from the current sources (`/tmp/composer-mail-build.log`) and passes
strict/deep ad-hoc signature verification (`/tmp/composer-mail-signature.log`).
Its executable is arm64, with macOS 26.0 recorded in Mach-O and Info.plist.
Existing Semantics.swift unused-result warnings remain. Generated protocol and
fixture exact-output checks, viewport compile-failure checks, handwritten Swift
formatting, whitespace and all 49 decision documents validate. All compilation
and test processes for this checkpoint have completed. This remains a development
bundle; no new screenshot or physical-device acceptance is claimed.


### Expandable composer through a native SwiftUI Sheet

The standard kind-7/version-2 registration reuses the ordinary composer surface
and native editor resource. Compact/Extended launchers use their configured
animation; zero duration and reduced motion skip the explicit animation. The
Sheet uses platform presentation and keyboard avoidance without a second card.

Presentation leases are independent of property generations. Close immediately
fences editor actions and keeps background input blocked until native dismissal.
Reopening retains text/selection and requests focus. Configuration updates keep
the Sheet/editor mounted; disablement leaves Close available. Key replacement,
removal, epoch replacement and closure dispose the native resource.

Native extension contexts now expose a synchronous current-interaction query.
The session checks identity, presented metadata, visibility, modal ownership and
snapshot generation before a local presentation action. Native modal ownership
is included in all core input admission checks. Decorative launcher/action
children do not mount independent handlers.

`Expandable_composer_catalog` is included in Gallery and the real runtime fixture.
The initial tests failed on missing kind 7 and allowed reserved-kind override
(`/tmp/expandable-red.log`). Eight focused ordinary/expanded tests now pass
(`/tmp/expandable-focused.log`, 11.750 seconds), including marked text, raw action
bytes, selection/editor retention, disabled presentation, stale binding/action
rejection, background isolation, reset/removal/restart and invalid frames.
The independent SwiftUI App passes autofocus, Escape dismissal, reopening and
five-/three-line sizing (`/tmp/expandable-window.log`, 25.470 seconds). OCaml
`dune build @all @runtest @fmt` passes (`/tmp/expandable-ocaml.log`); existing
native linker stub warnings remain.

The full regression passes 366 Swift tests in 81 suites with a completed xUnit
report (`/tmp/expandable-swift-full.log`, 330.646 seconds). All three platform
checks pass (`/tmp/expandable-platforms.log`, 18.324 seconds), including the
physical-iOS module and ten example entrypoints. A subsequent closure-formatting
correction has no behavioral change. All three independent windows pass against
that source (`/tmp/expandable-native-windows.log`, 70.996 seconds): expanded
composer, ordinary composer and Mail inbox/expansion/Archive.
Physical iOS input/keyboard/VoiceOver/performance, full standalone Gallery and reviewed
Mail screenshots remain unfinished. The Mac is still locked when checked through
computer use; no new complete screenshot is claimed. No source or SDK publication
was performed. See [composer behavior and evidence](swiftui-composer.md).


The final focused run passes all eight composer tests
(`/tmp/expandable-focused-final.log`, 12.123 seconds). The Mail macOS development
bundle is rebuilt from this worktree (`/tmp/expandable-mail-build.log`), verifies
with deep/strict ad-hoc signing, and reports arm64 with minimum macOS 26.0.
Protocol generation, shared fixtures, viewport compile-failure checks, strict
handwritten Swift formatting, `git diff --check` and agent document validation
pass. The protected `ocaml/spec/` tree is unchanged. Existing linker and
`Semantics.swift` unused-result warnings remain; no warning-free build is claimed.


### Typed generic gesture events and Gallery prerequisites

The combined Gallery still contains Material Button/FAB and generic Gesture,
FocusScope and KeyboardListener nodes that lack complete SwiftUI implementations.
The latter interaction section must not be omitted merely to make Gallery start.

Tap and Double_tap now encode four finite point coordinates and the existing
pointer-kind enum. Long_press retains its Unit contract. Repeated gesture
notifications do not coalesce; invalid coordinates fail queue admission without
changing prior events. The real `native-gesture-events` OCaml fixture verifies
all six kinds, negative/fractional coordinates, repeated long presses and replay
fencing. The initial RED run failed valid admission/runtime delivery because the
new event encoder was unimplemented (`/tmp/gesture-events-red.log`). The first
related regression passes 15 tests in seven suites (`/tmp/gesture-events-green.log`).

The native recognizer probe confirms that the installed SDK has SwiftUI's
recognizer-representable APIs, but the locked desktop produced no callbacks from
direct or application-queued clicks. This is unresolved runtime evidence, not a
passing native recognition test. Computer use rechecked the lock; the user has
been asked to unlock manually while independent work continues. The Gesture
renderer, native input ownership and all interaction acceptance remain unfinished.
See [gesture contract, probe and remaining work](swiftui-gestures.md).


The final related event regression passes 16 tests in seven suites
(`/tmp/gesture-events-final.log`, 0.090 seconds), including the actual OCaml
pointer/text handlers. OCaml `@all @runtest @fmt`, strict handwritten Swift
formatting, whitespace checks and agent document validation pass. The final
queued recognizer probe exits 1 and reports `recognitions=0 active=false
keyWindow=false`; it is retained as unresolved acceptance evidence, not a green
test. The full Swift suite was not repeated for this transport-only checkpoint;
its last completed run remains the preceding 366-test composer checkpoint.


All three platform checks pass (`/tmp/gesture-platforms.log`, 18.478 seconds),
including physical iOS 18 module/example compilation and explicit unsupported
target rejection. The protected spec tree is unchanged. No new Mail screenshot,
source commit/push or generated SDK publication was produced at this checkpoint.


### Native platform information through Host Effects

`NativeHostService` replaces the clipboard-only service class and implements the
existing platform-information request alongside clipboard read/write. It encodes
three native strings (Apple OS identifier, Foundation OS-version display string
and current locale identifier) through the existing typed response. Values are
read when the acknowledged request executes; the service does not cache startup
values, access clipboard contents for this request or change user preferences.

Host Effects now exposes `Read platform information`; OCaml invokes the existing
Host_effect API and owns the displayed result/error. Tests initially failed with
an unrecognized host operation and a missing production button
(`/tmp/platform-info-red.log`); the independent App also failed to find that
button (`/tmp/platform-info-window-red.log`). The implemented service/example
passes 12 related tests in five suites (`/tmp/platform-info-green.log`, 0.178
seconds), covering actual Foundation values, typed OCaml decoding, cancellation,
presentation/activation gates, delayed reply/restart fences and unchanged named
pasteboard contents. The command suite checks empty request payloads and rejects
trailing bytes transactionally. OCaml `@all @runtest @fmt` passes, with existing
native linker stub warnings (`/tmp/platform-info-ocaml.log`). Both independent windows pass (`/tmp/platform-info-native-windows.log`, 47.586
seconds): Host Effects reads platform information at compact width, and Host
Navigation retains clipboard/Settings/Close/system Back behavior. The full Swift regression passes 371 tests in 83 suites with a fresh completed
xUnit report (`/tmp/platform-info-swift-full.log`, 331.039 seconds), including
both this platform-information unit and the preceding Gesture event transport.
All three platform checks pass (`/tmp/platform-info-platforms.log`, 18.223
seconds), including physical iOS 18 compilation and explicit Simulator/Intel
rejection. Physical-device runtime acceptance remains unfinished.

Other host-service variants and physical iOS acceptance remain required. No
complete Mail screenshot or source/SDK publication is claimed by this unit.


The Host Effects and Mail macOS development bundles are rebuilt from this
worktree (`/tmp/platform-info-build-host.log` and
`/tmp/platform-info-build-mail.log`). Both pass deep/strict ad-hoc signature
verification and report arm64 with minimum macOS 26.0. Protocol generation,
shared fixtures, viewport compile-failure checks, strict handwritten Swift
formatting, whitespace checks and agent-document validation pass. The protected
spec tree is unchanged. Existing native linker and `Semantics.swift` unused-result
warnings remain. The Mac is still locked on the final computer-use check; no new
complete Mail screenshot, source push or generated SDK publication is claimed.

### Native CLI prerequisites and framework assets

Framework discovery now requires the Swift package manifest, native C bridge,
Clang module map, Swift application view and Apple toolchain support files.
Flutter-only directories, incomplete native directories and directories used
in place of asset files are rejected. `BONSAI_SWIFTUI_SOURCE_ROOT` is the sole
explicit override; invalid or empty overrides produce an error instead of
silently searching elsewhere. The package install instructions stage `native/`,
`swift/` and `Package.swift` and no longer copy Flutter packages. Package and
executable renaming remain part of the unfinished production-tool migration.

`doctor` no longer requires an application configuration. It checks real opam,
Dune, Xcode, the selected SDK and its Swift compiler from the current directory.
The default is macOS; `--target iphoneos` selects the physical-device SDK.
It does not invoke Flutter or write project files. These checks report tool
availability; they do not establish complete-object linking, signing,
provisioning or physical-device execution.

Three new filesystem tests first failed on native-root rejection, Flutter-root
acceptance and ignored invalid overrides (`/tmp/swiftui-assets-red.log`), then
passed (`/tmp/swiftui-assets-green.log`). CLI integration first reproduced the
unwanted configuration requirement (`/tmp/swiftui-doctor-red.log`), followed by
actual Flutter invocation after removing that prerequisite
(`/tmp/swiftui-doctor-flutter-red.log`). Three integration tests now pass against
the installed Apple tools (`/tmp/swiftui-doctor-green.log`): default/macOS/iPhoneOS
diagnostics in an empty directory with a Flutter invocation trap, an invalid
Xcode selection, and Simulator target rejection. The package passes `opam lint`.

The complete OCaml `@all @runtest @fmt` gate passes
(`/tmp/swiftui-tool-ocaml.log`), including all 90 CLI tests. The Apple-tool
integration is rerunnable with `python3 tool/test_swiftui_doctor.py` after
building `bonsai_flutter_tool/bin/main.exe` in the active opam environment.
Agent-document validation and whitespace checks pass; the protected spec tree
is unchanged. Swift implementation sources are unchanged by this checkpoint,
so the previous 371-test Swift result is historical evidence, not a new run.

The old host generation, synchronization, profile/cache and build/run paths are
still coupled to Flutter and remain unfinished; do not use their installed
commands as evidence of native application packaging. The macOS development
helper remains the currently verified way to build the migrated examples.


### Xcode application hosts and packaged Mail runtime

`tool/swiftui_xcode_host.py` generates deterministic native Xcode projects using
`XCLocalSwiftPackageReference` to the existing Swift package. The development
helper's direct `swiftc` bundle assembly is removed. Each host has separate
macOS 26 arm64 and physical iOS 18 arm64 application targets, shared schemes,
Debug/Profile/Release configurations, explicit plists and entitlements, resource
build phases and SDK/configuration-specific native objects. macOS signs locally;
iOS requires an explicit device object and development team. A native verification
phase rejects incorrect architecture, minimum OS, platform and bridge exports.
No Flutter command or package is used by this pipeline.

Initial end-to-end tests failed because the helper did not generate Xcode hosts
(`/tmp/swiftui-xcode-red.log`). Real Xcode builds then exposed an incorrect
DerivedData output-path assumption; the helper now uses the standard
`DerivedData/Build/Products` layout. A relocation test caught absolute checkout
paths and unstable source IDs (`/tmp/swiftui-xcode-portability-red.log`); generated
files now use relative paths and stable IDs. Five tests pass
(`/tmp/swiftui-xcode-final.log`, 38.289 seconds), including both platform settings
in all configurations, retained application-owned files, repeatable generation,
checkout portability, wrong-platform object rejection, real signing and nested
resource directory contents. Mail's XCTest must actually report its runtime case
as passed, not merely return a successful build exit code.

All ten existing Swift App entrypoints now have generated `examples/<name>/apple/`
projects and successful Xcode Debug macOS builds: Clock, Counter, Host Effects,
Host Navigation, Mail, Navigation, Network, SQLite Worker, Text Input and Todo.
Per-example logs are in `_build/validation/xcode-hosts/`. Each build verifies the
native complete object and the final App's deep/strict ad-hoc signature. Network
embeds static GMP; SQLite links the Apple SQLite library. Generated projects and
schemes are source artifacts; `Native/` and `DerivedData/` are ignored outputs.
Active example READMEs point to the new App locations.

Mail's application-owned XCTest opens the actual `mail` OCaml entrypoint through
the packaged `NativeRuntime`, checks its initial message frame, acknowledges
presentation, pumps again, closes and repeats startup. This hostless native test
runs without desktop automation. It does not replace complete-window visual
acceptance or physical input tests. See [Xcode host instructions](swiftui-xcode-host.md)
for generation, builds, tests and the remaining production pipeline work.

The generic CLI/configuration/package rename, integrated cross-toolchain builds,
iOS linking/signing/installation/runtime, distribution archives, combined
Gallery and final screenshot requirements remain unfinished. No generated iOS
project or build-settings check is treated as physical-device acceptance.


Release verification exposed Xcode attempting an Intel slice for the Swift
package even though the App target specified arm64. The new optimized-build test
reproduced the failure in both Release and Profile
(`/tmp/swiftui-xcode-optimized-red.log`). Project-level architecture settings alone
were insufficient. Schemes now explicitly match the run destination for the whole
build graph, including Swift packages; the native platform guard is unchanged.
Mail's Release and Profile applications now build as arm64, sign successfully,
and pass the actual packaged runtime XCTest
(`/tmp/swiftui-xcode-optimized-final.log`, 70.347 seconds). The generated scheme
uses dependency ordering rather than deprecated manual target ordering.

The retained Mail project also passed its Debug XCTest, reporting one executed
runtime test with zero failures (`/tmp/swiftui-xcode-mail-runtime.log`, 0.016
seconds for the test). Xcode retains the result bundle in
`examples/mail/apple/DerivedData/Logs/Test/`. This is runtime/build evidence,
not complete-window or physical-device acceptance. The desktop remained locked
on the latest computer-use check, and no new complete Mail screenshot is claimed.

The final generator integration run passes all six tests against the current
implementation (`/tmp/swiftui-xcode-complete.log`, 138.320 seconds). This includes
real Debug, Profile and Release Mail builds and executed XCTest cases, with the
architecture override active. All ten repository-local generated projects have been
regenerated from that implementation. Swift formatting, whitespace checks and
agent-document validation pass; the protected spec tree is unchanged.


The retained Mail Release and Profile bundles also build and pass deep/strict
signature verification (`_build/validation/xcode-hosts/mail-release-final.log`
and `mail-profile-final.log`). The final OCaml `@all @runtest @fmt` gate passes
(`/tmp/swiftui-xcode-ocaml-final.log`). These outputs and generated projects are
uncommitted worktree artifacts; no source push or generated SDK update occurred.


### Isolated physical iOS 18 compiler and core runtime

The installed global iOS compiler was still hard-coded to 15.0 in both its
`ios-cc` wrapper and OCaml configuration. Three tests reproduced the mismatch
in real compiler flags, a newly compiled C foreign stub and the allocation object
extracted from `libasmrun.a` (`/tmp/swiftui-ios18-compiler-red.log`). The Simulator
setup rejection already passed. This evidence rules out treating a changed
`VER` environment variable as a rebuilt iOS 18 compiler/runtime.

`tool/ios/toolchain.lock` now selects minimum 18.0 and the corresponding arm64
triple, with new compiler/runtime recipe revisions. Unused Flutter/Dart version
locks are deleted. The OCaml overlay describes physical iOS arm64 and restricts
its build host to Apple Silicon macOS. Setup records a SwiftUI recipe identity
and executes the actual cross-compiler tests before reporting success.

A fresh isolated opam root and local switch were created under `_build/ios/`.
The host OCaml 5.1.1 compiler, locked cross-compiler recipe and iOS core runtime
were built from source (`/tmp/swiftui-ios18-toolchain-setup.log`). The user's
existing global switches were not modified. All four tests passed during setup
(1.373 seconds) and through the deployment-target gate afterward
(`/tmp/swiftui-ios18-compiler-green.log`, 0.359 seconds). Tests compile a real
OCaml callback and C foreign stub into a complete object, verify IOS/arm64/18.0
Mach-O metadata and runtime/stub symbols, inspect an installed runtime object,
and reject Simulator setup. No device execution is implied.

`tool/test_ios_deployment_target_contract.sh` now runs these artifact checks.
Its old Flutter project/pubspec text scans and fixed iOS 15 assertions are
removed. The broader legacy CI/SDK contract scripts remain to be migrated.
The assembled cross-compiler opam overlay passes lint with the existing missing
`dev-repo` warning; the partial vendor template alone is not a complete opam
package until the locked upstream files are assembled.

The full native dependency closure still needs rebuilding for this compiler,
followed by the actual framework/Mail cross-link and physical-device signing,
installation, interaction and screenshots. Existing generated SDK metadata is
left as its published source snapshot; source and generated SDK publication
remain separate later steps. See [physical iOS toolchain](swiftui-ios-toolchain.md).

Repeating the compiler bootstrap succeeds without reinstalling the matching
compiler (`/tmp/swiftui-ios18-toolchain-repeat.log`) and reruns its real artifact
checks. The normal macOS OCaml `@all @runtest @fmt` gate passes
(`/tmp/swiftui-ios18-ocaml.log`), as do shell syntax, whitespace and all agent
document checks. The protected spec tree is unchanged. No source/SDK publication,
physical-device run or new Mail screenshot occurred in this compiler checkpoint.

### Physical iOS dependency preparation and archive audit

The isolated switch now contains the locked host dependency tools, including
Bonsai/Core/network/SQLite build dependencies. The obsolete framework host row
was removed from `vendor/opam-ios/supported-closure.lock`, and its counts and
SHA-256 body digest were recomputed. Lock validation passes for 103 target
packages, 128 host packages, two target build dependencies and 146 components.
All 105 target source archives are staged under `_build/ios/swiftui-runtime/`
and verified against their locked SHA-256 values. No earlier framework package
or iOS 15 target binary was installed into the new runtime closure.

New real-artifact tests reproduced five audit failures: the verifier expected
15.0 for valid new objects, accepted iOS 15 and macOS foreign objects inside
archives, and accepted missing declared `.cmxa` or `.a` artifacts. The verifier
now reads the toolchain deployment target, checks declared native artifacts,
and audits every static archive member in addition to loose objects. It uses
individual findlib archive paths, preserving directories containing spaces,
and deduplicates artifacts from overlapping component directories. Unsafe or
duplicate archive member names are rejected before extraction.

`/tmp/swiftui-ios18-closure-audit-red.log` records the five reproduced failures.
`/tmp/swiftui-ios18-closure-audit-green.log` records all three test methods passing
(0.999 seconds), using actual newly compiled OCaml and C artifacts. Shell syntax
and supported-lock validation pass. Full target dependency compilation has
started, but no completed closure audit, framework cross-link, physical-device
run or new screenshot is claimed by this checkpoint.

The complete 105-item target build subsequently finished successfully
(`/tmp/swiftui-ios18-target-closure.log`). The first full installation audit
then found a concrete gap: `datascript_ocaml`'s virtual library had only public
interfaces, with all 27 concrete native modules missing from its installation.
`/tmp/swiftui-ios18-virtual-library-red.log` reproduces the 54 missing `.cmx`/`.o`
files. The generic virtual-library recipe now builds each concrete native
module named by the installed host inventory, using only cross-built files as
installation inputs. Rebuilding Datascript succeeds, and the artifact test
checks all expected files and IOS/arm64/18.0 metadata for every object
(`/tmp/swiftui-ios18-virtual-library-green.log`). The full closure audit is
rerunning after this fix; successful package builds alone are not acceptance.

The next audit correctly exposed a separate verifier defect: Digestif is an
interface-only virtual library and should not manufacture native objects.
Regression tests also showed that checking for any `.cmx` allowed one missing
Datascript module to go unnoticed. The verifier now checks each expected virtual
module filename from the selected host installation while auditing only target
bytes. Interface-only packages are accepted; any missing concrete module is
rejected. `/tmp/swiftui-ios18-virtual-audit-red.log` records both failures and
`/tmp/swiftui-ios18-virtual-audit-green.log` records all five artifact tests passing
(1.836 seconds). Full installed archive/member verification is now running after
these fixes.

### Rebuilt iOS closure and actual Mail application link

The final full dependency installation audit passes
(`/tmp/swiftui-ios18-target-audit-complete.log`): 103 target packages, 128 host
packages, 146 components, 166 static archives and 1,129 checked Mach-O objects.
The corrected virtual-library recipe was applied to the actual Datascript
installation before this audit. The closure build includes 105 target build
items, including its two native build dependencies.

The current framework and actual Mail application now cross-build into
`_build/ios/swiftui-framework/default.ios/examples/mail/ocaml/native_embed.exe.o`
(`/tmp/swiftui-ios18-mail-cross-build-relative.log`). The object passes all
required SwiftUI ABI/OCaml startup symbol checks, physical IOS/arm64/minimum
18.0 metadata and prohibited host-path/obsolete Flutter ABI rejection
(`/tmp/swiftui-ios18-mail-object.log`). The Dune command takes the source-relative
example target with `-x ios`; passing an absolute build-output path as the target
was rejected before compiling anything.

Xcode successfully builds the actual SwiftUI Mail Release iOS App linked to that
complete object (`/tmp/swiftui-ios18-mail-xcode-build.log`). This first link uses
`CODE_SIGNING_ALLOWED=NO` to establish compilation and linking independently of
provisioning. The resulting executable is IOS/arm64/minimum 18.0, and its plist
contains minimum 18.0 and only iPhoneOS in supported platforms. It is not a signed,
installed or runtime-verified device build. The original Mail project's saved
Development Team is being checked separately for signing.

The separate signing build also succeeds
(`/tmp/swiftui-ios18-mail-sign-build.log`). It uses the original Mail project's
Development Team through an Xcode command-line override, preserving generated
project portability. The final Release-iphoneos bundle passes deep/strict
codesign verification and includes an unexpired provisioning profile. This is
an actual signed SwiftUI App linked to the cross-built OCaml Mail program.
The freshly queried paired iPhone 13 remains unavailable, so installation,
XCTest execution on device, interaction and physical-device screenshots are
still unverified. The desktop also remains locked; no complete macOS screenshot
was added.

The normal macOS OCaml `@all @runtest @fmt` gate passes
(`/tmp/swiftui-ios18-closure-ocaml.log`), and existing closure lock/feature/
dependency tests pass (`/tmp/swiftui-ios18-closure-lock-tests.log`). All five
artifact-audit regressions and the concrete virtual-module artifact test pass.
Protected spec files remain unchanged. Source and SDK publication have not
occurred; the architecture decision remains proposed and the migration remains
unfinished.

The GMP target-build archive lives outside the findlib component directories.
A separate full extraction/member audit verifies all 525 objects as
IOS/arm64/minimum 18.0 (`/tmp/swiftui-ios18-gmp-audit.log`), in addition to the
166 component archives checked by the closure verifier. Document validation
passes for all 49 decision documents and `git diff --check` is clean.

### All ten available Swift App examples build for physical iOS

The current worktree cross-builds the actual OCaml programs for Clock, Counter,
Host Effects, Host Navigation, Mail, Navigation, Network, SQLite Worker, Text
Input and Todo in one Dune iOS Release invocation
(`/tmp/swiftui-ios18-all-examples-cross-build.log`). All ten complete objects
pass physical IOS/arm64/minimum 18.0, required SwiftUI ABI/OCaml runtime exports
and obsolete Flutter ABI/prohibited host-path checks
(`/tmp/swiftui-ios18-all-examples-objects.log`).

Each object is staged into its own generated Xcode host and linked with the
actual SwiftUI package/application entrypoint. All ten Release iOS Apps build
successfully with the original Mail project's development team supplied as an
Xcode override. Every final executable passes IOS/arm64/minimum 18.0 checks,
every bundle passes deep/strict signature verification and includes a
provisioning profile, and all plists declare iPhoneOS only, minimum 18.0 and
both iPhone/iPad device families. Existing macOS Debug bundles were rechecked
for deep/strict signatures and MACOS/arm64/minimum 26.0.

`_build/validation/ios-examples/manifest.json` records per-example bundle paths,
IDs, native-object/executable SHA-256 values, tested configuration/platform and
log paths. It explicitly records unverified device execution and the
uncommitted-worktree source state. Network's final executable has no unresolved
GMP symbols; SQLite Worker links `/usr/lib/libsqlite3.dylib`. Neither observation
substitutes for actual network/filesystem behavior on iOS.

Mail's iOS Release test target also passes `build-for-testing`
(`/tmp/swiftui-ios18-mail-build-for-testing.log`). Its actual XCTest bundle
passes physical IOS/arm64/minimum 18.0 and deep/strict signature checks. Xcode
produces `BonsaiMail-iOS_iphoneos26.1-arm64.xctestrun`; the test bundle has not
executed on a device.

The latest device inventory still reports the paired iPhone 13 unavailable,
and the desktop remains locked on a fresh computer-use check. No new complete
Mail screenshot, installation, physical-device interaction or iOS test execution
is claimed. Gallery remains the eleventh unfinished standalone example, and its
remaining widgets, Button focus acceptance, CLI/SDK/package migration and final
source/SDK publication remain open. See `docs/swiftui-example-builds.md` for the
current build matrix and exact tested scope. No implementation source changed
in this checkpoint; all 49 decision-document checks and whitespace checks pass,
and protected spec files are unchanged.

### Native window host services and Mail mailbox acceptance

Window-title and content-size host requests now execute against the calling
session's presentation window. They retain the same presentation, visibility,
cancellation and shutdown boundaries as the clipboard service. macOS uses
NSWindow title/content size; iOS uses the attached scene title and returns an
explicit unsupported-operation response for resizing. The Host Effects example
exposes both requests and renders OCaml success/error state.

The initial native window and wire regressions reproduced the absent controls
and unsupported request kinds (`/tmp/swiftui-window-host-native-red.log` and
`/tmp/swiftui-window-host-wire-red.log`). A supplemental two-probe regression
then reproduced a stale probe acknowledging the replacement owner's ticket and
marking its session invisible (`/tmp/swiftui-window-host-owner-red.log`).
Presentation scheduling, layout and completion now require current window
ownership. Detaching old probes cannot clear newer ownership or visibility;
closing the session conditionally restores the original native title without
overwriting external changes.

All 16 related tests pass (`/tmp/swiftui-window-host-owner-green.log`), as do
the independent Host Effects/Mail window regressions
(`/tmp/swiftui-window-host-native-regression.log`) and all three platform
compilation/rejection checks (`/tmp/swiftui-window-host-platforms-final.log`).
The full Swift run passes 376 tests in 84 suites in 330.938 seconds
(`/tmp/swiftui-window-host-full-final.log`). OCaml `@all @runtest @fmt` passes
(`/tmp/swiftui-window-host-ocaml-green.log`). Both affected macOS Debug Apps
were rebuilt and strictly signature-verified from the updated sources
(`/tmp/swiftui-window-host-macos-build.log` and
`/tmp/swiftui-window-host-mail-macos-build.log`).

The Mail native window test now additionally finds the five mailbox buttons and
detail placeholder, enters Archived after archiving Mara Vale, verifies the
message there, and returns to Inbox without restoring it. Its final run passes
in 24.776 seconds (`/tmp/swiftui-mail-sidebar-final.log`). An initial test-ID
lookup failure was corrected to query exposed native button labels; no
production fix is claimed for that test error. Diagnostic exports now record
effective appearance, backing scale and content dimensions and include the
post-action Archived state. These exports still omit sidebar pixels/native
background composition. Mounted, working controls do not establish correct
visible pixels. A fresh desktop check reports the Mac locked, and a fresh device
inventory reports the paired iPhone 13 unavailable. Full macOS/iOS screenshot
and physical-device acceptance therefore remain incomplete.

Host Effects' changed OCaml program was also cross-built again for iOS 18
(`/tmp/swiftui-window-host-ios-object.log`). Host Effects and Mail both rebuilt
as signed physical-iOS Release Apps. A final audit verifies all four affected
macOS/iOS App signatures, executable architectures and deployment minima,
plus both iOS plists, provisioning profiles and staged object identities
(`/tmp/swiftui-window-host-bundle-audit.log`). The iOS example manifest refreshes
these two records with their current hashes/checkpoint; the other eight Apps
and the Mail XCTest bundle still describe the earlier checkpoint. No device
execution, source push or generated SDK publication occurred.

### Remove managed aliases from the native CLI build path

The previous goal turn made progress by extending real Mail mailbox acceptance,
refreshing diagnostic captures and rebuilding/auditing the affected App bundles.
This checkpoint proceeds with the CLI foundation while desktop and device
capture prerequisites remain unavailable.

Native build plans now request the configured `.exe.o` target directly, without
Flutter-specific aliases or an embedding environment gate. Debug maps to Dune
`dev`; Profile and Release map to `release` while retaining distinct artifact
directories. Target validation rejects absolute/traversing paths, aliases and
option-like names. Targets are encoded as S-expression atoms because actual
Dune commands otherwise misparse filenames containing spaces.

Scaffolding no longer appends, validates, repairs or migrates managed aliases.
Existing Dune files remain application-owned on repeated initialization and
adoption, and newly emitted complete-object stanzas have no embedding gate.
The obsolete `sync-project` command, managed blocks in all eleven examples and
the old integration consumer, and stale shell-CI alias assertions are removed.

Three new integration tests run actual Dune commands. They build an ordinary
OCaml complete object in all three profiles inside a space-containing project
path, check the actual selected profile, verify unchanged-build timestamps,
and rebuild after a source change. They also build, verify and stage the real
SwiftUI Counter complete object under a space-containing target filename,
preserving both the staged artifact and application Dune file on repeat runs.
These tests replace the old alias-generation/repair/alias-only checks; useful
SDK, dependency closure, artifact, locking, process and signal tests remain.

Behavioral RED logs record the missing alias/preflight and scaffold injection
failures (`/tmp/swiftui-cli-native-direct-red-final.log` and
`/tmp/swiftui-cli-native-scaffold-red.log`). Removing aliases exposed the actual
Dune target encoding failure (`/tmp/swiftui-cli-native-direct-green.log`). All
three new integration tests and 86 existing CLI/library tests pass after the
fix (`/tmp/swiftui-cli-native-suite.log`). The final repository
`@all @runtest @fmt` gate also passes (`/tmp/swiftui-cli-native-all.log`).

Counter's direct build in the isolated physical-iOS workspace passes after
alias removal (`/tmp/swiftui-cli-native-ios-direct.log`), and the complete
object passes IOS/arm64/minimum 18.0 and SwiftUI ABI checks
(`/tmp/swiftui-cli-native-ios-audit.log`). The CLI help confirms `sync-project`
is gone. Protected spec files are unchanged.

The CLI configuration, generated Swift App, production build/run/exec flow,
package rename and installed-SDK discovery still require migration. No finished
SwiftUI CLI, full legacy shell-CI success, device execution, screenshot, source
push or SDK publication is inferred from the native-builder checkpoint. See
`docs/swiftui-cli-native-build.md` for exact scope and evidence.


### Native SwiftUI CLI and application-owned Xcode hosts

The executable is now `bonsai-swiftui`, and project discovery accepts only
schema-3 `bonsai-swiftui.sexp`. Configuration selects an Apple host directory,
bundle identifier, complete-object target and optional network/SQLite features,
with physical iOS 18 and macOS 26 arm64 minima. Validation precedes creation;
old schemas, Dart host fields and unsupported destinations are rejected.

Initialization emits a real OCaml counter and application-owned Swift App.
Repeated initialization/adoption preserves existing Swift, OCaml and Dune
sources. The shared Python Xcode generator supports independent application
roots and compares all generated bytes before read-only `sync-host --check`;
normal synchronization writes only changed generated files. Flutter creation,
Dart adapters, pub-get, Native Assets profile injection and Flutter argument
forwarding are removed from the CLI pipeline.

Builds verify and stage complete objects, generate native hosts, invoke Xcode
with explicit configuration/destination and verify App metadata, architecture
and signatures. An explicit complete object enters the same verified pipeline,
including macOS network GMP handling. Invalid objects fail before staging.
SDK paths use `BONSAI_SWIFTUI_APPLE_SDK_ROOT`, because ambient `SDKROOT` was
observed contaminating the host assembler during a cross-build regression.
Debug App checks account for Xcode's debug dynamic library; ABI verification
is performed on the input object rather than assuming every export lives in
the App's main executable.

macOS run launches the App executable; physical-iOS run requires a device ID
before building and uses devicectl installation/launch with signing. `exec`
preserves literal arguments, working directory, child status and interrupts,
while exposing verified native-object/configuration environment values.
Selected-platform cleanup removes its native/Xcode products and retains the
other platform. Full project cleanup preserves application sources. Parent
symlinks are validated before any deletion, and external referents survive.

Tests first reproduced missing native initialization, invalid-config writes,
retained Xcode cleanup output and absent parent validation. The independent
external application builds in Debug/Profile/Release and its native SwiftUI
window presses Increment, observing Count 0 become Count 1 through OCaml.
The final seven-test CLI suite passes in 126.764 seconds
(`/tmp/swiftui-cli-apple-integration-final.log`), covering source ownership,
read-only checks, wrong-platform rejection, actual build/run, exit 17 and
interrupt status 130, argument fidelity and cleanup boundaries. Fifty retained
CLI/library tests and three direct-native integration tests preserve the useful
SDK/closure/artifact/configuration contracts. The repository
`@all @runtest @fmt @install` gate passes
(`/tmp/swiftui-cli-apple-repository-continuation.log`).

The new CLI additionally builds and verifies a signed iOS 18 Release App from
the actual Mail Swift entrypoint and cross-compiled OCaml complete object
(`/tmp/swiftui-cli-mail-ios-build.log`). Evidence and hashes are recorded in
`_build/validation/swiftui-cli-mail-ios-h4jc0d0s/validation.json`; this explicit
object route does not establish installed-SDK publication or device execution.
The root README now documents native SwiftUI development and removes obsolete
Flutter setup, adapter, icon-font and CLI instructions.

A fresh desktop inspection still reports the Mac locked, so complete Mail
window capture remains outstanding. Gallery, remaining widgets/services,
independent example consumer metadata, package naming, installed SDK release,
full CI migration, physical-device acceptance and source/SDK publication remain
open. No completion or source push is inferred from these CLI gates. See
[the native CLI guide](swiftui-cli.md) for commands and detailed evidence.


The subsequent shared-generator regression passes all six tests in 272.299
seconds (`/tmp/swiftui-cli-apple-xcode-regression.log`): actual Mail App builds
and packaged OCaml XCTest execution in Debug/Profile/Release, Apple destination
settings, wrong-platform rejection, relocatable projects and nested resources.
The 49 decision-document checks and whitespace check pass at this checkpoint.


### Standalone example CLI configuration and library-owned Apple link flags

All ten examples with Swift App entrypoints now own `bonsai-swiftui.sexp` and
can be discovered from their root or nested source directories. Network and
SQLite Worker declare their explicit features. The CLI compiles each example's
own `ocaml/native_embed.exe.o`; its application-owned Swift/OCaml sources are
preserved. Each example README documents the native CLI commands. Gallery
remains unfinished and is not represented as a completed eleventh consumer.

The two-test integration suite copies the actual examples into independent
space-containing directories. It first reproduced missing configuration for
all ten examples and Mail's build (`/tmp/swiftui-example-cli-red.log`). Adding
configuration exposed SQLite Worker's source-tree-relative include of the
framework's generated linker flags (`/tmp/swiftui-example-cli-green.log`).
A CLI-only path correction then exposed missing system SQLite search paths
when building the repository directly (`/tmp/swiftui-example-cli-repository.log`).

Apple library search flags now belong to the native backend library's
`c_library_flags`. Its Dune rule resolves the correct Apple SDK for the target
context; installed OCaml archive metadata propagates the flags to consumers.
SQLite Worker, Network and the runtime fixture no longer carry explicit link
flags or include framework files from outside their own source tree. This
supports both direct Dune builds and independent applications without a
source-relative include, per-example script or legacy SDK environment variable.

The final repository `@all @runtest @fmt @install` gate passes
(`/tmp/swiftui-example-cli-repository-final.log`). The subsequent integration
suite passes both tests in 66.893 seconds
(`/tmp/swiftui-example-cli-library-flags-final.log`): all ten independent native
builds pass their real artifact verification and source-preservation checks;
the actual Mail App also builds through the CLI and runs its packaged OCaml
startup/presentation/restart XCTest through `exec` from a nested directory.
This is additional macOS application/build evidence, not complete Mail pixel
acceptance or iOS device execution.


Network and SQLite Worker also cross-build again through the isolated iOS 18
workspace after moving the flags (`/tmp/swiftui-example-cli-ios-cross.log`).
Both actual complete objects pass IOS/arm64/minimum 18.0 and SwiftUI ABI checks
(`/tmp/swiftui-example-cli-ios-network-audit.log` and
`/tmp/swiftui-example-cli-ios-sqlite_worker-audit.log`). Inspecting the native
backend `.cmxa` metadata confirms that the installed host archive carries the
macOS SDK library directory and the cross-built archive carries the iPhoneOS
SDK directory. The source-tree workaround is absent from both consumers.
These are refreshed object checks; they do not refresh previous App-bundle
manifests or establish physical-device execution.


The actual worktree Mail example was then built through the new CLI, without
substituting a prebuilt object (`/tmp/swiftui-mail-example-cli-macos.log`). Its
Debug App is at `examples/mail/apple/DerivedData/Build/Products/Debug/BonsaiMail.app`
and passes deep/strict signature and macOS 26 arm64 metadata checks.
`_build/validation/swiftui-mail-cli-macos.json` records the bundle, configuration,
Swift source, executable and staged-object identities, the uncommitted source
checkpoint and incomplete full-window capture status. The final 49 decision
document checks and whitespace checks pass; protected spec files are unchanged.
No source/SDK commit, physical-iOS execution or new complete screenshot occurred.


### Native URL host service and editable Host Effects action

The previous goal turn completed the ten-example CLI configurations and fixed
library-owned Apple system link flags, with actual standalone Mail execution.
This checkpoint advances the remaining host-service coverage while complete
window capture is unavailable.

Host request kind 3 now decodes its length-prefixed UTF-8 URL as part of atomic
frame staging. The native service checks an absolute scheme and the transfer
limit, opens through NSWorkspace asynchronously on macOS or UIApplication on
iOS, and returns the existing unit/error response. macOS native errors return to
the caller without an additional error/authentication panel; Gatekeeper behavior
is not changed. Cancellation is checked before dispatch and after completion.
A native open already accepted by the OS cannot be undone by cancellation;
operation/session identities suppress late responses without misreporting an
external App as closed.

Host Effects now owns a revisioned URL editor and Open URL/Go action in OCaml.
Native edits preserve UTF-16 selection/composition, acknowledge local revisions
and reject stale edits. The example dispatches the actual Host_effect request
and renders success/failure through its existing OCaml state.

Tests first reproduce unsupported request decoding and the missing native URL
field (`/tmp/swiftui-url-host-red-final.log` and
`/tmp/swiftui-url-host-window-red.log`). An initial test-only WireReader label
error was corrected before this behavioral RED. The receiver fixture then
exposed a registration-location problem: the OS did not resolve its App from
the system temporary directory. A separate native query resolved the same
kind of receiver in the worktree build directory. Fixtures now build/sign under
`_build/validation/url-receivers/`, wait for actual Launch Services resolution,
and unregister/remove only their own unique App after each test.

All 15 related Swift tests pass in five suites in 1.994 seconds
(`/tmp/swiftui-url-host-receiver-location.log`). Real NSApplication delegates
receive both ordered encoded-Unicode URLs; invalid/unhandled URLs fail;
same-batch cancellation prevents launch; cancellation and reset after native
delivery suppress late replies. The actual Host Effects native window also
passes in 28.556 seconds (`/tmp/swiftui-url-host-window-green.log`), including
field editing, no launch while inactive, exact URL receipt after resumption,
the OCaml result, invalid input and no request dispatch after closure. Existing
clipboard, platform and window actions remain part of the scenario.

The OCaml `@all @runtest @fmt` gate passes
(`/tmp/swiftui-url-host-ocaml-green.log`). A fresh computer-use check still reports
the Mac locked. No complete Mail screenshot or physical-iOS URL execution is
claimed; remaining host services, widgets/Gallery, package cleanup/publication
and the full migration acceptance scope remain open. See
[native URL service](swiftui-url-service.md) for API semantics and reproduction.


The full Swift gate passes 380 tests in 85 suites in 330.458 seconds with a
fresh completed xUnit report (`/tmp/swiftui-url-host-full.log`). All three
platform gates pass in 18.554 seconds (`/tmp/swiftui-url-host-platforms.log`),
including compilation of the complete module and ten Swift entrypoints for
physical iOS 18, plus explicit Simulator/Intel rejection. Strict formatting
of the changed Swift sources, whitespace checks and all 49 decision-document
checks pass; protected spec files are unchanged. Device URL dispatch and full
Mail screenshots remain unverified.


Host Effects and Mail were rebuilt through the native CLI as macOS Debug and
signed physical-iOS Release Apps. Host Effects' changed OCaml program was
cross-built again for iOS 18 (`/tmp/swiftui-url-host-ios-object.log`). All four
bundles pass architecture, minimum-version, metadata and deep/strict signature
checks (`/tmp/swiftui-url-host-bundle-audit-final.log`). The iOS Apps retain
iPhone/iPad families and embedded provisioning profiles. Their current hashes
and source checkpoint are in `_build/validation/swiftui-url-host-bundles.json`;
the iOS example manifest refreshes these two records and leaves the other eight
at their recorded earlier checkpoints. Mail's macOS CLI identity record is
also refreshed.

The final artifact check exposed test-only receiver cleanup skipped by the
native window process's direct `exit` call. The success path now closes the
fixture explicitly before exiting; the window scenario passes again in 28.786
seconds (`/tmp/swiftui-url-host-window-final.log`) and the receiver directory is
empty afterward. An earlier manual Mach-O audit invocation transposed its last
two arguments; correcting that invocation did not require a production change.
The final OCaml `@all @runtest @fmt @install` gate passes
(`/tmp/swiftui-url-host-ocaml-final.log`).

A fresh physical-device inventory still reports the paired iPhone 13 unavailable
(`/tmp/swiftui-url-host-devices.json`). No iOS installation/URL execution, full
Mail screenshot, source push or generated SDK publication occurred.

### Application-owned Swift request and event bridge

`BonsaiApplicationBridge` now connects application-owned async Swift handlers
and native event subscriptions to `Host_effect.Application_platform`. No protected
spec or application wire-schema change was necessary. Operations 11 and events
25/26/27 are decoded/encoded with their existing bounds and typed errors.
Requests retain an independent monotonic high-water mark across same-epoch
resyncs, and malformed frames cannot dispatch a partial request set.

`BonsaiSession` connects the provider after its first presentation acknowledgment,
stages later requests until presentation, pauses dispatch while inactive and
closes its connection once at teardown. The event sender copies bytes before
returning and reports closure, oversize or recoverable queue backpressure.
Completed replies survive a full input queue. Individual application replies
occupy separate native pumps: an OCaml cancellation or duplicate-response error
cannot discard adjacent queued UI input or valid application traffic. Controller
completion bookkeeping now uses only the input prefix actually pumped.

The actual OCaml fixture renders payload lengths and MD5 checksums, allowing
binary and exact 1 MiB round trips without exceeding text-property limits. Tests
cover every error code, 4096-byte Unicode errors, out-of-order completion,
borrowed-buffer mutation, cancellation, duplicate responses, inactive/resumed
sessions, full-queue recovery, provider admission and close/restart fencing.
The NotificationCenter integration registers and removes its own observer and
verifies ordered payloads in actual OCaml-rendered state.

Initial behavior RED evidence is `/tmp/swiftui-application-transport-red-final.log`
and `/tmp/swiftui-application-session-red.log`. Provider/lifecycle RED evidence
is `/tmp/swiftui-application-bridge-red-behavior.log`, with saturation separately
in `/tmp/swiftui-application-bridge-saturation-red.log`. Earlier test harness
errors (mutating Swift Testing macros, an unsafe assertion-followed-by-index,
and a non-Sendable Notification capture) were corrected before recording the
behavior-only runs. Thirteen focused tests then passed in 1.720 seconds
(`/tmp/swiftui-application-bridge-green.log`).

Host Effects now owns its two-byte version/tag codec and native Swift helper.
Its OCaml state requests the actual bundle identifier and subscribes to native
time-zone changes. The native-window test first failed because the application
button was missing (`/tmp/swiftui-application-example-red.log`), then passed the
new bridge actions plus pasteboard, window and URL regressions in 29.852 seconds
(`/tmp/swiftui-application-example-green.log`). The obsolete Dart-facing
`docs/application-platform.md` is replaced with the actual Swift API and lifecycle.

This checkpoint does not complete other host services, Gallery, the full widget
inventory, physical iOS execution, Mail's complete screenshots, namespace cleanup
or source/SDK publication.

The completed full Swift gate passes 393 tests in 86 suites in 331.503 seconds
with a fresh xUnit report (`/tmp/swiftui-application-bridge-full.log`). The OCaml
`@all @runtest @fmt @install` gate passes
(`/tmp/swiftui-application-bridge-ocaml.log`). All three platform gates pass in
18.810 seconds, including the complete physical-iOS module, all ten Swift App
entrypoints and explicit Simulator/Intel rejection
(`/tmp/swiftui-application-bridge-platforms.log`). Strict formatting of this
checkpoint's Swift sources passes; protected spec files remain unchanged.

Fresh desktop and device checks still find the Mac locked and the paired iPhone
13 unavailable (`/tmp/swiftui-application-bridge-devices.json`). No physical-iOS
execution or complete Mail screenshot is inferred from compile/test results.

Host Effects and Mail subsequently rebuilt as macOS Debug and signed physical-iOS
Release Apps through the current native CLI. The changed Host Effects OCaml
program cross-built again with the isolated iOS 18 compiler. The initial CLI
invocation omitted the documented source-development `OCAMLPATH` overlay and
resolved the old globally installed UI library; using the README's existing
source-root and install-overlay environment corrected that invocation without a
production change (`/tmp/swiftui-application-host_effects-environment.log`).
The successful build logs are `/tmp/swiftui-application-{host_effects,mail}-{macos,ios}.log`;
the cross-build log is `/tmp/swiftui-application-ios-object.log`.

All four bundles pass executable and complete-object ABI/Mach-O verification,
minimum-version and bundle-identifier checks, and deep/strict signature checks.
The staged and Xcode-consumed object hashes agree. iOS bundles retain iPhone/iPad
families and embedded provisioning profiles. No native URL receiver fixture is
left registered in the fixture directory. Final evidence is
`/tmp/swiftui-application-bundle-audit.log` and
`_build/validation/swiftui-application-bridge-bundles.json`. The main iOS example
manifest refreshes these two Apps to `application-swift-bridge`, preserving the
other eight records; Mail's macOS CLI identity record is refreshed as well.
No source or SDK commit/push occurred.

### Native file import/export checkpoint

The OCaml import API now returns a list through `Host_effect.pick_files`; request
kind 4 and its generated declaration use the same name. The old singular API
and optional-single-file import decoder are removed. Save retains an optional
single destination. Swift decodes both commands atomically before executing
them through session-owned SwiftUI `fileImporter` and `fileExporter` modifiers.

Imports coordinate scoped reads on a background task, copy every selected
regular file in order, preserve duplicate basenames and roll back incomplete
batches. The path-list response budget is checked before copying. Returned
copies live until session closure; cancelled late work is discarded separately
without deleting other committed imports or originals. Exports hold an owned
copy of opaque bytes and use a regular `FileWrapper`. Binding dismissal retains
the pending callback identity; busy requests, cancellation and restart cannot
replace or accidentally complete another dialog. See [file services](swiftui-file-services.md).

Behavioral RED evidence includes `/tmp/swiftui-files-contract-red-final.log`,
`/tmp/swiftui-file-import-red.log`, `/tmp/swiftui-file-limits-red-final.log`,
`/tmp/swiftui-file-dialogs-red.log`, `/tmp/swiftui-file-export-red.log` and
`/tmp/swiftui-file-window-red.log`. The final focused run passes 12 tests in four
suites in 0.212 seconds (`/tmp/swiftui-files-final-focused.log`). It includes real
OCaml import/export completions, filesystem reads/writes, malformed protocol
data, limits, cancellation and restart. Callback-driven success tests do not
claim actual system chooser selection.

The actual Host Effects example now exposes Import files and Export file.
Its native window test opens both SwiftUI system panels, checks multiple import
selection and the suggested export name, cancels each and observes the OCaml
status. That test passes in 32.841 seconds
(`/tmp/swiftui-files-window-green.log`). Complete native chooser selection,
physical-iOS file-provider behavior and destination overwrite interaction remain
unverified. The Mac was still locked when checked at this checkpoint, so no
new complete Mail screenshot is claimed.

The completed regression passes 405 Swift tests in 89 suites in 336.160 seconds
with a fresh completed xUnit report (`/tmp/swiftui-files-full.log`). OCaml
`@all @runtest @fmt @install` and generated-protocol freshness pass
(`/tmp/swiftui-files-ocaml.log`, `/tmp/swiftui-files-generator.log`). All three
platform checks pass in 20.621 seconds, covering the full iOS 18 module, ten
Swift App entrypoints and explicit Simulator/Intel rejection
(`/tmp/swiftui-files-platforms.log`). This checkpoint's handwritten Swift files
pass strict formatting; protected spec files remain unchanged.

Host Effects and Mail subsequently rebuilt through the native CLI for macOS
Debug and physical-iOS Release, using the isolated iOS 18 cross-compiler and
the documented host source-root/install-overlay environment. All four Apps
pass deep/strict signing, exact architecture/minimum-version, complete-object
ABI and staged/consumed-object hash checks. iOS Apps also match the cross-built
objects and retain their iPhone/iPad families and provisioning profiles.
Evidence is `/tmp/swiftui-files-app-audit.log` and
`_build/validation/swiftui-file-services-bundles.json`; the main iOS manifest
updates these two Apps to `native-file-services`. The other eight example
records remain at their earlier checkpoints. See [build evidence](swiftui-example-builds.md).
The failed native-panel probe's uniquely identified temporary file fixture was
verified and removed. No source or generated SDK commit/push occurred.

### Native focus and layout checkpoint

Host requests 6, 7 and 14 now execute against the requesting session's owned
window and presented node identities. Focus uses the existing plain, secure and
multiline native controls; disabled, detached, removed or non-text targets fail
explicitly. Clear-focus is idempotent and preserves another window's first
responder. SwiftUI geometry supplies four logical-point Float64 values relative
to application content. Geometry sampling adds no sizing view, OCaml update or
observable view invalidation; its local attachment fences disappearance.
See [node services](swiftui-node-services.md).

The actual OCaml fixture issues host requests from its application event channel
and renders their decoded results. Its native SwiftUI window checks all three
text-input families, disabled/removed targets, another window, presentation
deferral and window detachment. Geometry tests verify 120-by-40-point dimensions
and unchanged content coordinates after moving the window on screen. Behavioral
RED is `/tmp/swiftui-node-services-all-red.log`; four focused tests pass in
0.904 seconds after refactoring (`/tmp/swiftui-node-services-refactor.log`).
Earlier compiler failures in the fixture and Swift Testing assertion were
corrected before recording the behavior-only RED run.

Host Effects exposes Clear focus next to its URL field. Its native App scenario
first fails because the button is missing
(`/tmp/swiftui-node-services-window-red.log`), then passes in 32.799 seconds after
the OCaml action is added (`/tmp/swiftui-node-services-window-green.log`). It
checks the actual URL editor resigns and reruns file panels, application bridge,
clipboard, window and URL operations. Scroll-to remains a separate unfinished
container-offset integration. Physical-iOS focus/IME, detached modal/toolbar
geometry, complete screenshots and performance acceptance remain open; this
checkpoint does not add an application-side reference API.

The initial full Swift regression then found 22 assertions in Spacer, Divider,
layout-priority and weighted-stack parity tests
(`/tmp/swiftui-node-services-full.log`). A stateful per-node geometry modifier
had changed native subview semantics. It is replaced by primitive bounds-anchor
preferences, preserving descendant anchors, with geometry resolved only at the
application root. Root-owned records clear on missing anchors or disappearance
without observable invalidation. All 35 related tests in seven suites now pass
in 1.681 seconds (`/tmp/swiftui-node-services-anchors-green.log`), including
actual OCaml layout changes and native measurement/focus. SwiftPM and Python
generated cache directories are now ignored; no generated cache was deleted or
added to source control.

The corrected full Swift run completes 409 tests in 90 suites in 319.794 seconds
(`/tmp/swiftui-node-services-full-final.log`), superseding the earlier failed
409-test run. All three platform checks pass in 19.363 seconds, including the
complete iOS 18 module, ten App entrypoints and Simulator/Intel rejection
(`/tmp/swiftui-node-services-platforms-final.log`). The independent Host Effects
window regression passes again with root anchor sampling in 32.278 seconds
(`/tmp/swiftui-node-services-window-final.log`). OCaml `@all @runtest @fmt
@install` passes (`/tmp/swiftui-node-services-ocaml.log`); current handwritten
Swift formatting, whitespace checks and agent-document validation pass. The
protected spec tree remains unchanged.


### Complete macOS captures and physical-device preflight

Host Effects and Mail pass fresh CLI builds and four App-bundle audits at the
`native-node-services` checkpoint. Mail's rebuilt macOS App was launched and
operated through CUA: inbox, inline expansion, third-column detail, Archive,
and Archived selection. Four complete window captures retain their original
bytes and verified pixel-identical PNG encodings, with 290 compiler-input
source hashes and audited executable/native-object hashes. See
[Mail capture evidence](screenshots/swiftui-mail/README.md).

A connected iPhone 13 reports iOS 26.6.1 (23G83), with Developer Mode enabled.
The signed Mail App installs successfully (`/tmp/swiftui-mail-device-install.json`).
Its launch request is rejected because the phone is locked
(`/tmp/swiftui-mail-device-launch.json`); iPhone Mirroring independently asks
for Mac login authentication. No device execution or screenshot is claimed.

The first physical XCTest attempt fails before execution because the generated
iOS test target has no host App (`/tmp/swiftui-mail-physical-runtime-20260913.log`).
This invalidates the earlier implication that a successfully compiled test
bundle is ready for physical execution. A dedicated empty host must let tests
own their OCaml runtime without competing with the application UI session.
The generator regression builds an actual iOS test product and inspects the
Xcode-produced run manifest and host executable.


### Physical iOS runtime test host and first device screenshot

The generator now adds a minimal SwiftUI host App only for iOS applications
with XCTest sources. It links neither BonsaiSwiftUI nor the OCaml object; the
XCTest bundle owns the real runtime. A target dependency, `TEST_HOST` and
`BUNDLE_LOADER` make the bundle executable on physical devices. macOS retains
tool-hosted tests, and applications without test sources acquire no host.
The real iOS build regression fails on the old tool-hosted manifest in
44.643 seconds (`/tmp/swiftui-ios-test-host-red.log`) and passes in 43.115 seconds
(`/tmp/swiftui-ios-test-host-green-final.log`). An intermediate test-harness
assertion incorrectly treated Xcode's App-bundle path as an executable path;
that assertion was corrected to read `CFBundleExecutable` from the actual plist.

After the user unlocked the iPhone, Mail launched successfully. The rebuilt
iOS Release XCTest passed `testPackagedMailStartsPresentsAndRestarts` in
0.109 seconds on iPhone 13, iOS 26.6.1 (23G83): one test, zero failures and zero
skips. The xcresult confirms the physical destination, and the host and nested
test bundle pass deep/strict signatures plus IOS/arm64/minimum-18 metadata.
Evidence: `/tmp/swiftui-mail-physical-runtime-hosted-20260913.xcresult`, its
adjacent log, and `_build/validation/swiftui-mail-physical-runtime.json`.
This supersedes the earlier device-lock and tool-hosted execution failures;
it does not establish iOS 18 runtime behavior or visual/interaction acceptance.

Xcode Devices captured the actual Mail App on the same phone at 1170×2532
pixels. The original PNG is preserved without editing as
`screenshots/swiftui-mail/diagnostics/mail-ios-mailboxes-dark.png`. The phone's
Dark appearance exposes hard-coded dark Mail text against black system
backgrounds, with inadequate contrast. The initial capture shows Mailboxes,
although the OCaml initial compact-column preference is Content; compact
navigation also requires investigation. Neither issue is hidden by the passing
runtime test. Mirroring still requests Mac login authentication, so interactive
phone navigation has not yet been verified. No system appearance was changed.


The full Xcode host integration suite passes all seven tests in 349.698 seconds
(`/tmp/swiftui-ios-test-host-regression.log`), covering both-platform settings,
actual device-test products, macOS Debug/Profile/Release runtime tests, resource
preservation, no-test applications, portability and wrong-platform rejection.
No protected spec files changed; Python compilation, whitespace and agent-doc
checks pass.

Capture provenance review found that Xcode's hosted-test build had rebuilt the
local Mail App after the initial installation. The first Mailboxes screenshot
therefore has an unverified installed-executable identity; its metadata now
labels the binary hash as local only. The current signed App was re-audited,
reinstalled and freshly launched, then captured by Xcode at 21:30:18 +08:00.
That complete original PNG shows Inbox, which does not reproduce the earlier
suspected initial-column problem. Its exact executable/native-object and source
hashes are recorded beside `screenshots/swiftui-mail/mail-ios-inbox.png`, with
install and launch evidence. The bundle manifest advances only Mail iOS to
`physical-ios-runtime-test-host`. Dark native chrome and explicit light Mail
surfaces still require visual refinement. Earlier Mailboxes contrast remains
a diagnostic finding, not proof of a persistent initial-navigation defect.


### Physical Mail UI test runner

The next device gate adds application-owned UI test sources under
`examples/mail/apple-ui-tests/ios/`. The generator discovers per-platform
`apple-ui-tests/<platform>/` sources and creates a separate Xcode UI-testing
bundle that targets the actual App. The runner links no BonsaiSwiftUI package
or OCaml complete object; runtime XCTest retains its existing ownership.
Mail scenarios cover inbox, inline expansion/collapse, the attachment-bearing
message, and swipe Archive/Trash presentation plus Archive execution. All
screenshots are original XCUITest attachments from the actual application.

The initial real-build generator regression fails because Xcode's device run
manifest omits the application-owned UI tests
(`/tmp/swiftui-mail-ui-host-red.log`, 39.212 seconds). The first implementation
build exposed Swift 6 isolation errors in synchronous XCTest setup/teardown;
the harness now uses asynchronous lifecycle overrides. These compiler errors
are not counted as behavioral RED evidence. Physical behavior and screenshot
acceptance remain unproven until the test actually executes and images are
inspected.


The generated UI test products pass the real iOS build/manifest check in
39.497 seconds (`/tmp/swiftui-mail-ui-host-green-verified.log`). The first
physical run builds and signs both test families, and the real runtime
startup/presentation/restart test passes again in 0.078 seconds. UI testing
fails before case execution: the runner times out while enabling automation
mode (`/tmp/swiftui-mail-ui-device-first.xcresult` and its adjacent log).
The device reports no lock-screen passcode requirement, but a direct Xcode
screenshot confirms a separate system prompt asking for the iPhone passcode
for XCTest's Enable UI Automation. The user was asked to complete that prompt.
No authentication setting or passcode was changed by the agent. This is an
authorization prerequisite, not behavioral RED for Mail and not evidence of
passing UI scenarios. Local host regression continues independently.

The current signed App, UI runner and nested UI test bundle pass signature
verification. Symbol inspection confirms that only the App exports
`bs_runtime_create`; neither the runner nor UI bundle embeds the OCaml runtime.
The application-owned UI bundle has IOS/arm64/minimum-18 Mach-O metadata.
Xcode supplies its own prebuilt runner executable with a minimum-13 load
command, and its runner plist also reports iOS 13. The application-owned UI test
bundle requires iOS 18. This vendor test
tool is distinct from the distributed App target; no SDK executable metadata
was patched. `_build/validation/swiftui-mail-ui-runner.json` records the
artifact hashes, limits and zero executed UI cases at this checkpoint.

All eight Xcode host integration tests now pass in 389.647 seconds
(`/tmp/swiftui-mail-ui-host-regression.log`). Coverage includes actual iOS
runtime/UI test products, separate runtime ownership, Mac Debug/Profile/Release
Mail runtime tests, no-test application resources, platform settings, relocation
and wrong-platform object rejection. Swift UI-test source formatting, Python
compilation, whitespace and all 49 agent documents validate. Physical Mail UI
cases still await the observed XCTest passcode authorization; no new Mail UI
screenshot or interaction success is claimed by these local build tests.


### Unlocked native gesture and Button focus probes

The macOS gesture probe now sets its own accessory activation policy. With
`--activate`, queued application-local mouse events produce one recognition,
with an active application and key window
(`/tmp/swiftui-native-gesture-active-verified.log`). A separate CUA click also
recognizes, and the sibling Button activates independently. This is framework
feasibility evidence, not OCaml integration or nested-control acceptance.

Button focus probes now run with a usable key window. Ordinary and activation
focus variants still fail to retain focus with keyboard navigation off. Edit
interaction variants focus the SwiftUI wrapper, but Space produces no Button
action. The verified logs are recorded in `swiftui-button-focus.md`. No system
keyboard or accessibility settings changed. Generic Gesture implementation,
FocusScope, KeyboardListener and Button/FAB replacement remain incomplete.


### Physical UI runner after unlock

After the user reported unlocking, both a test-without-building run and a full
build/test retry installed and started the signed UI runner. Both fail before
Mail case execution: the XCTest DTX peer refuses the driver interface channel,
then the runner exits with code 74 before establishing its IDE connection.
The result bundles are `/tmp/swiftui-mail-ui-device-unlocked-20260913.xcresult`
and `/tmp/swiftui-mail-ui-device-reconnect-20260913.xcresult`. These runs no
longer report the earlier timeout enabling automation mode. The underlying
connection failure is not yet diagnosed and must not be presented as a Mail
assertion failure or a confirmed authorization problem. Neither Mail UI case
executed and neither produced a screenshot attachment.

The device remains connected in Xcode. iPhone Mirroring separately still shows
a Mac-login prompt, so that interaction route is unavailable. A device-state
capture showed unrelated foreground content and was not copied into project
artifacts. Existing Mail images remain four reviewed macOS captures and the
verified physical-iOS Inbox capture. No source/test behavior was changed to
hide this runner failure. The unlocked framework-probe documentation and all
49 agent documents validate; whitespace checks pass.


### Native Generic Gesture foundation

Gesture node 48 now stages with one child and any subset of the five supported
bindings. The real OCaml staging regression verifies successful creation and
atomic rejection of malformed child/binding updates. `NativeGestureContent`
attaches system click/tap and press recognizers plus a passive pointer observer.
The controller fences callback generations on handler replacement, unmounting,
presentation loss and disposal; Session admission checks current displayed
ownership. A named application-root coordinate space fixes the observed macOS
title-bar offset in native recognizer global coordinates.

The actual native window test first fails because the Gesture node cannot be
presented (five scenarios, 31.095 seconds); the independent staging test fails
with `unsupportedNode(48)`. After implementation, all five macOS scenarios pass
in 43.184 seconds (`/tmp/swiftui-gesture-window-green-root.log`). Coverage spans
single/double-click precedence, long press, primary pointer metadata/order,
nested Button isolation, drag cancellation, binding replacement, removal and
inactivity/reactivation. Earlier unbundled-window timeouts and unmaterialized
accessibility labels are harness corrections, not behavioral RED.

All three platform checks pass in 22.384 seconds
(`/tmp/swiftui-gesture-platforms.log`). The native window test is part of
`make swift-test`. Full Swift regression is running separately. Physical iOS
execution, multi-contact UIKit pointer observation, scroll-view competition,
transformed/nested targets and secondary buttons remain unfinished; these are
not covered by the five passing macOS scenarios. Gallery and remaining
FocusScope/KeyboardListener/Button migration are still incomplete.


The initial full Swift run completes 410 tests in 90 suites in 329.729 seconds
with one failure in the pre-existing MorphingSurface intermediate-animation
assertion (`/tmp/swiftui-gesture-full.log`). The actual Gesture staging and
transport tests pass. The animation test waits for accessibility/layout work
during a 500 ms transition, while unrelated suites also use the same AppKit
application. The unchanged assertion passes in isolation in 1.468 seconds
(`/tmp/swiftui-gesture-animation-focused.log`). A complete follow-up run uses
explicit `--no-parallel`; the testing-helper process confirms that argument is
forwarded to Swift Testing, and suites execute sequentially. The failed run is
retained and is not counted as a passing gate. No animation assertion or
production animation implementation was weakened to obtain a result.


The complete serial run passes all 410 tests in 90 suites in 402.910 seconds
(`/tmp/swiftui-gesture-full-serial.log`), including the unchanged MorphingSurface
assertion (1.408 seconds) and the new actual Gesture staging test.
`tool/run_swift_tests.py` now uses the exact verified `--no-parallel` command:
these native UI fixtures share an AppKit application and run loop. All ten
fresh-report completion checks still pass. OCaml `dune build @all @runtest
@fmt @install` and generated protocol checking pass
(`/tmp/swiftui-gesture-ocaml.log`); pre-existing native-linker stub warnings
remain. Swift formatting, Python compilation, whitespace and 49 agent docs
validate. Protected spec sources are unchanged. No new Mail screenshot, source
commit/push or SDK publication was produced in this Gesture checkpoint.

The next pointer audit must correct the AppKit `pointingDeviceType` read on a
tablet-point event: the SDK permits that property only on proximity events.
It must also unify Gesture mouse identity with Hover and implement shared
UIKit contact identity/multiple concurrent contacts. See the explicit follow-up
audit in `swiftui-gestures.md`; the passing mouse tests do not prove those
remaining behaviors. The full migration goal remains active.


### AppKit Gesture/Hover pointer metadata

The new native-packet regression exposes loss of tablet identity/kind in the
existing Hover source: 16 assertions fail in 0.065 seconds
(`/tmp/swiftui-pointer-source-red.log`). `AppKitPointerDevices` now shares native
device information across Hover captures, window sources and Gesture
coordinators. Ordinary mouse ID is 0; tablet IDs occupy a distinct range.
Only proximity events supply `pointingDeviceType`, fixing the earlier invalid
read from tablet-point packets. Enter/leave proximity and application inactivity
update or clear the state. Leases keep one application-local observer alive
while needed and release it on final disposal.

The inactivity regression separately fails when the application retains old
proximity kinds after resigning active (`/tmp/swiftui-pointer-inactive-red.log`),
and passes with lifecycle invalidation. The combined regression initially
assumed no other test-owned leases were alive. Its own device scope now tests
final-lease cleanup and shared-observer preservation independently, without
forcing all live scopes to discard metadata whenever any observer closes.
Nineteen related tests in seven suites pass in 0.423 seconds
(`/tmp/swiftui-pointer-related-final.log`). The tests use native AppKit packets
and this process's event dispatch; no global input is generated.

The real OCaml Gesture window fixture now includes a combined Hover/pointer
scenario with two tablet IDs and proximity changes, and checks mouse ID 0.
The current window run stops at its active-key-window prerequisite in all six
scenarios because the Mac has locked again. CUA independently confirms the
lock, and an asynchronous unlock request remains pending. These setup failures
are not behavioral RED. Physical pointer input, the updated full window run,
UIKit multi-contact identity, scroll competition and root-coordinate consistency
remain unfinished. The migration goal remains active.

The complete serial Swift regression passes 411 tests in 91 suites in
408.067 seconds (`/tmp/swiftui-pointer-full.log`). All three platform checks
pass in 19.957 seconds (`/tmp/swiftui-pointer-platforms.log`), including physical
iOS 18 arm64 compilation and unsupported-target rejection. OCaml `@all`,
`@runtest`, `@fmt`, `@install` and generated-protocol checking pass
(`/tmp/swiftui-pointer-ocaml.log`). Strict formatting of the changed Swift
sources, Python compilation and all ten completion-report checks pass.
After the user reports unlocking, another CUA request still reports the Mac
locked; clarification distinguishes the Mac Studio desktop from the connected
iPhone. No updated native window run, new Mail screenshot or source/SDK
publication is claimed by this checkpoint.


### UIKit shared pointer contacts

The passive UIKit recognizer previously kept one UITouch and a per-recognizer
counter. It now consumes a shared contact-identity scope and per-observer edge
queue. Mouse/Pencil reserve IDs 0/1 to match UIKit hover; direct or unknown
contacts receive distinct bounded IDs. Weak keys compare object identity, so
separate objects with equal values cannot share a contact accidentally. Active
contacts and pending edges retain the native object until their own delivery,
cancellation or reset. One observer resetting does not clear another observer's
contacts or shared identity.

Each edge preserves that contact's kind, position, button mask and controller
generation. The recognizer processes all touches and queues multiple edges
before its target action drains them; ending a finger leaves remaining fingers
active. Cancellation and reset discard pending work without synthetic releases.
Per-sample SwiftUI coordinate conversion replaces the single recognizer location
for this pointer path. The adapter allows mixed touch types and enables multiple
touches on the attached view during update/first admission.

Four utility tests and an actual native OCaml batch round-trip test fail against
the empty contract scaffold (five tests, eight assertions, 0.033 seconds,
`/tmp/swiftui-contact-red.log`) and pass with the implementation (0.019 seconds,
`/tmp/swiftui-contact-green.log`). They cover two simultaneous contacts, reversed
observer order, distinct equal-valued objects, reserved device IDs, duplicates,
unknown transitions, cancellation, reset and weak lifetime. This is contract
and transport evidence; it is not a physical UIKit multi-touch RED/GREEN.
All three platform checks pass in 20.028 seconds
(`/tmp/swiftui-contact-platforms.log`), including the full physical iOS 18 Swift
module and retained example entrypoints.

Physical multi-touch delivery, mixed Pencil/finger dispatch, native view
attachment timing, coordinate correspondence and scroll/child-control
arbitration remain required. The current native desktop window prerequisites
and separate iPhone UI-runner connection failure remain unresolved. No new
Mail screenshot, source commit/push or SDK publication is claimed.


The complete serial Swift run passes 416 tests in 92 suites in 409.270 seconds
(`/tmp/swiftui-contact-full.log`). Strict Swift formatting, all ten fresh-report
completion tests, Python compilation, whitespace checks and 49 agent documents
pass. Protected spec sources remain unchanged. No OCaml implementation changed
in this checkpoint; its previous build/test/protocol result is retained rather
than presented as a newly executed gate. Physical UIKit acceptance and the
remaining migration requirements remain open.


### Keyboard event transport

Swift now encodes keyboard event tag 9 using bounded nonnegative-int64 logical
and physical IDs, a closed down/up/repeat action enum and the complete UInt32
modifier mask. The existing event queue keeps every repeat and action boundary;
invalid IDs or exceeded budgets do not discard admitted events. The unrelated
text-editor event admission switch explicitly rejects this new payload.
KeyboardListener rendering and native key/focus admission remain unsupported.

Three tests fail with seven issues while the encoder rejects the new payload
(`/tmp/swiftui-key-red-final.log`, 0.022 seconds); earlier compiler/harness
failures are not counted as behavioral RED. All three pass after implementation
(`/tmp/swiftui-key-green.log`, 0.018 seconds). The new actual OCaml listener
fixture returns a complete history for twelve keyboard records, including zero
and Int64.max identifiers, UInt32.max modifiers, repeated keys and replay
fencing. It is a native transport fixture, not a rendered keyboard input test.

The adjacent event/queue/text-editor/gesture regression passes 28 tests in nine
suites in 0.133 seconds (`/tmp/swiftui-key-related.log`). Three platform checks
pass in 20.151 seconds (`/tmp/swiftui-key-platforms.log`). OCaml `@all`, `@runtest`,
`@fmt`, `@install` and generated-protocol checks pass
(`/tmp/swiftui-key-ocaml.log`). The prior full 416-test Swift run remains evidence
for its pointer-contact checkpoint; this isolated encoding change uses the
relevant regression rather than presenting that older full run as current.

Native capture/mapping, KeyboardListener rendering and focus/key-policy
semantics remain unfinished, along with the other full-migration gates.
Protected spec sources are unchanged. No new Mail screenshot, source commit,
push or SDK publication was produced. See `swiftui-keyboard.md` for scope and
acceptance requirements.


### Swift-generated input fixtures and native environment encoding

All seven input fixtures now come from the production Swift EventBatch encoder.
The Dart producer and its dart-prefixed outputs are removed; Swift and OCaml
tests use the swift-prefixed files. OCaml cross-language, protocol and dispatch
tests pass with the new producer's bytes. Public Make generation/check commands
now call the native generator, which requires a fresh successful Swift Testing
report and the complete seven-file output set before writing or comparing.

The environment fixture exposes the missing tag-20 encoder. Its typed Apple
snapshot now preserves dimensions, scales, locale, insets, accessibility flags,
orientation and pointer kinds. Invalid nonfinite values, negative dimensions
and nonpositive scales fail before queue mutation. This is encoding only;
native environment observation/publication remains unfinished. Fixture and
validation tests initially fail with 39 issues in 0.010 seconds, then pass in
0.003 seconds, including all seven fixture cases. The Make command contract
also changes from two failing subcases to success.

Actual corrupted/missing-output checks both exit 1 without modifying the
supplied files. Exact restoration passes. Relevant Swift regression passes
19 tests in eight suites in 0.163 seconds; three platform checks pass in
20.239 seconds. OCaml build/test/format/install, generated protocol execution,
fresh-report checks and the actual Make fixture-check command pass. Swift
formatting, Python compilation, whitespace and 49 agent documents validate.
Protected spec sources and historical screenshot provenance remain unchanged.

The full CI baseline is still failing: the physical iOS cross-compiler gate
passes all four tests (0.481 seconds), then the network iOS contract reports
18 obsolete expectations for deleted Flutter hosts, version-2 config, removed
presentation APIs and the older virtual-library build layout
(`/tmp/swiftui-ci-before-cleanup.log`). This is evidence for the next CI cleanup,
not a passing full-CI gate. Remaining Flutter/Dart Makefile/CI paths still need
replacement. No new screenshot, source commit/push or SDK publication occurred.
See `swiftui-input-fixtures.md` for reproduction and scope.

### Runtime privacy resources and the Network native CI contract

The Swift package now copies its runtime privacy manifest into
`BonsaiSwiftUI_BonsaiSwiftUI.bundle`. The declarations preserve the former
runtime File Timestamp and System Boot Time reasons; applications retain their
own privacy declarations. Real macOS and physical-iOS build-product assertions
fail before the resource is added, then pass alongside the isolated iOS runtime
XCTest host build: three tests in 97.851 seconds
(`/tmp/swiftui-privacy-package-green.log`). The macOS RED is in
`/tmp/swiftui-privacy-package-red.log`; the separate iOS UI build-product RED is
in `/tmp/swiftui-privacy-ios-red.log`. An earlier isolated runtime-host build in
the first RED selection already passed and is not counted as a failing case.
These are packaging builds, not physical UI executions. `make xcode-test` now
runs the Xcode host suite as a dependency of `make swift-test`.

The Network iOS contract uses the schema-3 SwiftUI configuration and generated
Xcode hosts. It checks actual destination settings, concrete virtual-library
modules and iOS object/archive artifacts rather than deleted Flutter hosts or
an obsolete native-directory rejection. Missing declared native artifacts and
wrong platform/minimum versions remain rejected. Dependency ownership, static
GMP, TLS, entropy and SDK constraints remain enforced. The Network contract
passes (`/tmp/swiftui-network-contract-native.log`).

The full CI rerun passes physical-iOS cross-compiler, Network and SDK layering
gates, then fails on its next obsolete expectation:
`missing examples/clock/bonsai-flutter.sexp`
(`/tmp/swiftui-ci-after-network.log`). Consumer configuration, the remaining
Flutter/Dart targets and other CI checks still need migration. This is not a
passing full-CI result. After the user's latest unlock notice, CUA still reports
the test Mac locked; no new window-test or screenshot evidence was produced.
Source changes remain uncommitted, and no SDK update was published.

### Native CI dispatch and system SQLite dependency isolation

The Makefile removes Dart tests/analyzers, Flutter test/CI, and the old Flutter
integration-host commands. `ci-swift` combines the native and Swift suites,
Xcode host tests, window tests, fixture verification and host synchronization.
macOS and physical-iOS build loops include all eleven consumers and Debug,
Profile and Release. The device launch recipe now passes its selected device
to preflight and requires an explicit development team. The preflight script's
own remaining Flutter dependency is still an unfinished migration item.

The previous `make -n ci-swift` exits 2 because the target does not exist
(`/tmp/swiftui-ci-target-red.log`). The new native dispatch is verified by
executing the actual expanded Make shell loops against a recording CLI
boundary: 33 build invocations per platform and 11 host-check invocations.
An injected failure at Gallery exits 17 immediately after the first Gallery
invocation (seven platform build calls or three host checks), with no later
dispatch. All five obsolete Make targets are unavailable. This validates
scheduling and failure propagation, not the complete App build matrix
(`/tmp/swiftui-ci-command-matrix.json`).

While preserving CI dependency checks, the audit found that the generated
Xcode host unconditionally linked system SQLite, including into Counter.
One actual App-build regression covers Counter and SQLite Worker on macOS
Debug and physical-iOS Release. Counter fails the dependency-absence assertion
on both platforms before the change (two failures in 123.518 seconds,
`/tmp/swiftui-sqlite-link-red.log`); SQLite Worker already links successfully.

The native verification phase now derives a fresh, target-local linker
response file from the verified complete object's undefined symbols. SQLite
is selected only for `sqlite3_*` imports; the system dylib is never bundled.
All four actual build cases pass in 124.739 seconds
(`/tmp/swiftui-sqlite-link-green.log`). The separate Mail macOS runtime XCTest
and isolated physical-iOS runtime-test host build pass in 83.090 seconds
(`/tmp/swiftui-link-runtime-hosts.log`). These tests do not execute physical UI.
All ten existing example Xcode hosts have been regenerated with this rule.

The root CI contract now checks native commands, SwiftUI consumer configuration
and generated hosts, and native linkage/fixture ownership while preserving the
locked OCaml dependencies, source/patch restrictions, iOS closure and SDK
layering gates. README, packaging and upstream-baseline documentation now
describe native Apple builds and their actual acceptance limits. Gallery,
remaining widget/service work, device/bundle tooling cleanup, legacy source
deletion and source/SDK publication remain required.

The complete contract rerun now passes the compiler, Network, SDK layering,
dependency/source/patch, native command and native linkage checks, then exits 1
at `missing examples/gallery/bonsai-swiftui.sexp`
(`/tmp/swiftui-native-ci-contract-final.log`). This is a real unfinished
consumer, not a passing full-CI result. An earlier rerun incorrectly matched
the repository basename `bonsai_flutter` as a Flutter host path; narrowing the
command-path pattern fixes that check error without allowing Flutter commands.
All ten existing generated hosts separately pass `sync-host --check`.
The actual native UBSan target and fixture command check pass. Shell/Python
syntax, whitespace and the 49 agent documents also validate. No new screenshot,
source commit/push or generated SDK publication was produced in this unit.

### Gallery native hosts and full-page acceptance

Gallery now owns schema-3 configuration, a SwiftUI App, native card registration
and generated macOS/iOS hosts. Its complete-object target no longer requires
the old embedding flag and explicitly declares its Bonsai/UI dependencies.
The old Flutter source host/configuration is removed. The host directory was
moved to an ignored recovery directory after the shell rejected forced deletion;
it is not an active source, build or compatibility path.

The new standalone-copy CLI test initially fails with no native configuration
(`/tmp/swiftui-gallery-host-red.log`, 0.016 seconds). It now builds an actual
macOS App and verifies its PNG/GIF resources in 31.091 seconds
(`/tmp/swiftui-gallery-host-green.log`). The common standalone-native test now
covers all eleven examples and preserves their application-owned source bytes;
it passes in 19.700 seconds (`/tmp/swiftui-eleven-native-examples.log`). Gallery's
cross-built complete object passes IOS/arm64/minimum 18.0 and native ABI checks,
then its unsigned physical-iOS Release App builds successfully
(`/tmp/swiftui-gallery-ios-object.log`, `/tmp/swiftui-gallery-ios-build.log`).

The new complete-page test uses the actual `Gallery.component`, full session
staging/presentation and the toolbar counter callback. Its first run rejects
EnvironmentBoundary node 70 (0.254 seconds). The old renderer only copied the
current MediaQuery value, so the wrapper API, private/wire variants, schema,
driver and codec mappings are removed rather than implemented as a passthrough.
The protocol retirement check initially recognizes 70 and fails while parsing
properties instead of returning Unknown_node_kind; after removal it passes.
Native environment inheritance, theme scopes and safe areas remain; observation
and publication of native environment changes are still unfinished.

Full-page staging next rejects Material Button node 98 (0.250 seconds).
Gallery's default Material Button/FAB samples now use native Button styles,
Label and ControlSize. The complete-page test advances to KeyboardListener
node 53 and remains failing (0.249 seconds,
`/tmp/swiftui-full-gallery-after-buttons.log`). FocusScope node 51 also needs
implementation. Neither node is hidden, substituted or accepted without a
renderer. This is not a runnable complete Gallery. The application card UI's
interaction also remains unverified; the full-page test provides an extension
registration fixture, not an end-to-end test of that App-owned registration.

Related environment/safe-area/button regression passes ten tests in four suites
in 3.396 seconds. Three platform checks, including every App's iOS compilation,
pass in 20.557 seconds. OCaml `@all @runtest @fmt @install`, the actual fixture
generation/check pipeline and compiled Swift protocol-generator test pass.
The first OCaml build exposed missing direct dependencies in the previously
disabled Gallery entrypoint; a later gate required formatting two edited files.
Those build/format issues are not counted as behavioral RED.

`make ci-contract` now passes its main contract and iOS closure-lock gates, then
fails on three DataScript Worker expectations: runtime recipe 5 instead of 6,
and startup/disposal markers in an already removed Dart file
(`/tmp/swiftui-gallery-ci-contract.log`). The full Swift suite is not claimed
green while the complete Gallery test fails. Protected spec sources and existing
capture provenance are unchanged; no new screenshot or source/SDK publication
was produced. See [Gallery evidence](swiftui-gallery.md).

### Native physical-device preflight

Removed Flutter discovery from `tool/ci/ios_device_preflight.sh`. The script
uses CoreDevice's documented JSON interface, checks exact selected identity,
physical iOS 18+ and arm64 support, pairing, Developer Mode and DDI services,
then requires a current unlocked response. Removed the `bootState` requirement:
that property is absent from the observed Xcode 26.1.1 details schema.

Signing checks now resolve CoreDevice UUIDs to hardware UDIDs and inspect only
exact membership in the provisioning profile's device array. Certificate,
team, bundle, debug entitlement and expiration requirements remain enforced.
Eight regression tests pass through the real script and parsing/signing tools
with replayed device/keychain boundaries. These tests are included in
`make ci-contract`; they do not certify physical readiness or CMS trust.
The full command passes the new gate, main CI contract and iOS closure lock,
then fails on the three already identified DataScript Worker expectations:
recipe revision 5 instead of 6 and startup/disposal markers in the deleted
Dart host. Those device lifecycle requirements still need a native probe.

The separate live iPhone check failed correctly because DDI services were
unavailable, despite pairing and Developer Mode being enabled. No application
launch or screenshot is claimed. The complete Gallery acceptance test,
DataScript Worker contract migration and remaining full-scope requirements
remain unfinished. See [device preflight](swiftui-ios-toolchain.md#native-physical-device-preflight).

### DataScript Worker native probe and iOS process isolation

The DataScript Worker device path now uses a dedicated SwiftUI runtime probe
and the actual SQLite Worker/typed DataScript/Yojson/RRB sources. Separate
native macOS processes pass persistence, restoration, stale-result removal and
Worker/runtime shutdown; corrupt storage cannot produce success. The iOS 18
arm64 object and unsigned Release SwiftUI App also build. The updated bundle
verifier checks the actual executable, system SQLite, privacy and dSYM instead
of the deleted Flutter framework. See [native DataScript probe](swiftui-datascript-worker.md).

Binary inspection found that the extracted iOS process stubs were not included
in the new native backend. The physical-iOS embedding unit now includes them;
actual object checks reject process imports and verify that macOS keeps its
native process APIs. Previously built iOS examples must be rebuilt for final
acceptance. This checkpoint does not establish physical-device execution,
complete application rendering, or completion of the full SwiftUI migration.

The full `make ci-contract` now passes, including the DataScript native-process,
cross-object, actual iOS App build and bundle checks. OCaml all/test/format/install
also pass. Running the updated physical-device script stopped at the initial
preflight because DDI services were unavailable; no installation or launch was
attempted. The complete Gallery test and remaining full-scope acceptance are
still unfinished.

### Native keyboard mapping

Added a shared Unicode/HID identity contract and native AppKit/UIKit adapters
for the existing keyboard event transport. Actual NSEvent packet tests cover
layout normalization, independent modifier edges, Caps Lock physical versus
toggled state, repeat/up identity and reset. Mapped packets execute the real
OCaml keyboard handler and return the expected complete history. Seven tests
and three platform checks pass; see [native keyboard mapping](swiftui-keyboard.md#native-key-mapping).

This mapping checkpoint does not implement native capture or listener focus
ownership. KeyboardListener, Button autofocus and complete Gallery acceptance
remain unfinished; FocusScope progresses in the checkpoint below.

### Native FocusScope

FocusScope now renders in the existing SwiftUI graph and returns native focus
transitions to OCaml. Actual AppKit field-editor tests cover nested scopes,
within-scope transitions, hidden/inactive sessions and retained layout anchors.
Native autofocus waits for the matching presentation, mount and enablement and
does not steal focus after consumption. Handler replacement, disposal and malformed
wire frames are covered. Six focus tests, 17 related tests and three platform
checks pass; OCaml all/test/format/install passes. See [FocusScope](swiftui-keyboard.md#focusscope).

KeyboardListener and full Gallery acceptance remain unfinished. iOS focus is
typechecked but still requires physical acceptance. The desktop connection still
reported a locked Mac and the physical iPhone preflight still reported unavailable
DDI services; this checkpoint adds no screenshots, installation or publication.


### macOS KeyboardListener capture and propagation

KeyboardListener now renders and receives native AppKit window events, preserves
physical/logical key identities and applies deepest-first handled/ignored policy.
Actual native-window/OCaml tests verify callback history, normal text insertion
for ignored events, suppression for handled events, repeats/releases, autofocus,
hidden-session and unrelated-window isolation, and layout-anchor preservation.
Native regressions retire held keys on handler replacement, field-editor owner
changes, immediate focus clearing and rapid refocus. Removed nodes reject input.

The focused run passes 19 tests in four suites in 6.502 seconds. The complete
macOS Gallery tree/presentation/toolbar test now passes in 0.321 seconds; it uses
a native-card fixture and does not establish full native page interaction or the
App's own card behavior. See [macOS keyboard capture](swiftui-keyboard.md#macos-keyboardlistener).

UIKit capture, keyboard ownership/propagation and physical keyboard/IME/modal/
accessibility acceptance remain unfinished. iOS NodeStore still rejects node 53
explicitly. This checkpoint does not claim a working iOS KeyboardListener, new
screenshots, a completed widget inventory or source/SDK publication.


Final verification for this checkpoint: 440 Swift tests in 97 suites pass in
414.612 seconds through the completed-xUnit-report gate. OCaml all/test/format/
install and strict Swift format lint pass. This removes the known macOS full-tree
Gallery test failure while preserving the outstanding UIKit and native-page
acceptance requirements. Evidence: `_build/validation/swiftui-keyboard-listener-macos.json`.


### Signed SwiftUI iOS bundle checkpoint

The signed-bundle wrapper now audits the actual SwiftUI App without requiring
an obsolete Flutter framework. It forwards dSYM and SQLite requirements together
and checks the real signature, profile-authorized certificate, Team ID,
wildcard or exact App ID, bundle identifier, UTC expiration and typed debug
entitlements. Nine real development-signing tests pass in 13.050 seconds; four
native executable/resource/dSYM regressions pass in 1.756 seconds. No signing,
CMS or Mach-O tools are mocked; the expiry test changes only its audit
subprocess clock. See [signed native bundle audit](testing.md#signed-native-bundle-audit).

This does not establish positive distribution signing or physical execution.
After the user's unlock notification, desktop access still reported a locked
Mac and the selected iPhone still reported unavailable DDI services. No new
screenshot, device install/launch or source/SDK publication occurred. Existing
Mail captures retain their earlier checkpoint provenance. The full migration
remains unfinished.


### macOS host environment checkpoint

The application boundary now observes native geometry, display scale,
Body-relative text scaling, color scheme, locale, safe-area geometry and
accessibility preferences. Changes reach the actual OCaml environment input
through the typed control-event transport. The session coalesces updates,
respects initial presentation and inactive/hidden state, and invalidates old
observation sources on replacement or close. Native window tests also found
and fixed missed visibility updates when ordering out an already-occluded
AppKit window. See [native host environment](swiftui-host-environment.md).

Seven targeted Swift tests in three suites pass in 9.725 seconds, including
three real-runtime environment tests. Three platform checks pass in 21.138
seconds; OCaml all/test/format/install passes after formatting the native test
fixture. Automatic iOS environment observation, nonzero/RTL safe-area geometry,
system preference toggles and cross-display movement remain unverified or
unfinished as described in the environment guide. This checkpoint does not
complete UIKit KeyboardListener, other remaining widgets/effects, physical
acceptance, final Mail captures or source/SDK publication.


The final complete serial Swift run passes 443 tests in 97 suites in 424.977
seconds; the runner verifies the fresh completed xUnit report. No new physical
device run or screenshot is claimed by this checkpoint.


### Material Button/FAB surface removal

The remaining public `Material` module, root re-export, private constructors,
node variants and protocol codecs are removed. Retired kinds 98, 99, 109, 110,
111 and 114 now fail with `Unknown_node_kind`. No legacy alias or decoder is
retained. The schema and generated OCaml/Swift protocol sources are updated;
fixture buttons use core Button properties, and the additional native fixture
has a native name. See [native replacements](material-components.md).

The surface catalog now exercises native Button roles/styles and ControlSize
composition. Handler-dependency and application-request regressions still run
against the real OCaml driver, selecting their separate native Buttons by
label. External OCaml compilation verifies both public entrypoints accept
`View.button` and reject the removed Material/FAB module.

OCaml all/test/format/install and protocol/fixture generation checks pass.
Twelve related Swift tests pass in 2.591 seconds, including complete Gallery
startup and native Button state/actions/identity. The separate native Button
window test passes in 32.847 seconds at both widths and across five sizes;
three platform checks pass in 21.158 seconds. This checkpoint did not repeat
the earlier complete 443-test Swift run.

Core Button autofocus and its native keyboard/lifecycle acceptance remain
unfinished. Removing the obsolete surface does not claim that missing behavior
has been replaced or waive it from the full goal. UIKit KeyboardListener,
physical acceptance, remaining host services, final Mail captures and complete
Flutter/package/SDK cleanup and publication also remain outstanding.


### Native Button autofocus

The public core Button now accepts `autofocus`, defaulting to false. A shared
SwiftUI focus modifier waits for mount, enablement and matching presentation,
consumes the request after native focus succeeds, and activates an admitted
Space down exactly once. Repeat/up and command-modified input cannot duplicate
an action. Moving focus into a native editor does not trigger another request.
See [native Button autofocus](swiftui-button-focus.md).

The actual OCaml fixture reproduced lost focus while replacing a handler and
waiting for the new frame acknowledgment. The fix retains already-owned native
focus during that interval while admission pauses actions. Tests verify the
new handler after acknowledgment, disable/re-enable, false-to-true rearming,
removal/recreation and session close. The required fourth Button wire property
has no compatibility decoder; malformed and old payloads fail atomically.

Four targeted tests in two suites pass in 2.366 seconds. OCaml
all/test/format/install and protocol/fixture generation checks pass. Physical
iOS keyboard, IME, VoiceOver and modal-focus acceptance remain unverified.
This checkpoint does not finish UIKit KeyboardListener, remaining host effects,
final Mail screenshots, Flutter/package cleanup or source/SDK publication.

The complete serial Swift regression passes 447 tests in 98 suites in 427.833
seconds, with the runner validating the fresh completed xUnit report. Its first
run exposed a stale three-property parser in the Counter event test; that test
now reads the required autofocus property and its real OCaml increment/replay
checks pass. No new Mail screenshot or physical-device run is claimed.

The standalone native Button window test passes in 32.943 seconds across two
widths and five sizes. All three platform checks pass in 21.071 seconds,
including the full physical-iOS Swift module and example sources, and explicit
Simulator/Intel rejection. These compile checks do not establish iOS keyboard
behavior.


### Native normalized scroll service

Host request kind 8 now resolves a presented scrolling container and converts
its finite, clamped alignment into a native logical offset. Scroll, lazy
sections, Collection and ScrollTargets use shared SwiftUI point bindings.
The service advances animated requests with a monotonic 250 ms ease-in-out
transition, honors Reduce Motion, waits for observed positioning, and fences
cancellation, replacement, inactive ownership and disposal. It does not add a
second hosting graph or retain the Flutter controller path. See
[native scroll service](swiftui-scroll-service.md).

Four targeted tests in two suites pass in 28.524 seconds. The actual OCaml
fixture exercises all four kinds, both axes and both layout directions (16
positional cases), presentation and activity gates, cancellation, retired and
non-scroll targets, restoration and short content. The tests found both the
unsupported request and premature animation completion. Physical iOS, touch
interruption, snapping-enabled targets and concurrent structural changes still
need their respective acceptance checks.

Automatic UIKit environment observation remains unfinished. A new attempt to
launch the existing Mail bundle failed because CoreDevice could not find the
selected physical device. No Simulator, new screenshot or device acceptance is
claimed. The remaining host services, final widget/physical acceptance,
Flutter/package cleanup and source/SDK publication remain in the full goal.

The complete serial Swift run passes 451 tests in 99 suites in 455.358 seconds;
the runner verifies its fresh completed xUnit report. All three platform checks
pass in 21.522 seconds, including the full iOS 18 Swift module and example
sources and explicit Simulator/Intel rejection. OCaml all/test/format/install,
protocol/fixture generation, strict Swift formatting and document checks pass.
These results do not establish physical iOS interaction or finish the goal.


### SwiftUI notification checkpoint

`Host_effect.show_notice` replaces the Snackbar API with native SwiftUI bottom
safe-area presentation. FIFO requests, visible-time timeout, action/dismiss/swipe
results, cancellation and retired-view fencing now pass actual OCaml/macOS
tests. The rapid-restart test exposed delayed view-task cleanup closing a new
session; task-owned startup identities now fence that cleanup. Five targeted
Swift tests pass in 2.458 seconds, and the standalone native swipe App passes
in 28.518 seconds with an explicit completion marker. See
[notification contract](swiftui-notices.md).

The Host Effects example controls, full regression after this checkpoint and
physical iOS/VoiceOver acceptance remain open. The previously recorded 451-test
full regression predates notifications. CUA still reports the Mac locked after
the user's unlock notification, and CoreDevice lists the iPhone as unavailable.
No new screenshot or device acceptance is claimed; the existing Mail captures
remain from the earlier recorded build.

Final related regression passes 10 tests in two suites in 2.673 seconds,
including session removal/presentation and the actual Mail tree and bounded
materialization checks. All three platform checks pass in 21.897 seconds.
OCaml all/test/format/install, protocol and input-fixture generation checks,
strict Swift formatting and all 49 decision documents pass. Full Swift
regression and physical interaction acceptance remain outstanding.


### Notification example and full regression

Host Effects now exposes notification action, timeout and cancellation controls.
The standalone App passes these flows at normal and 360-point widths together
with its existing native services in 40.256 seconds. Its macOS Debug bundle
rebuilds successfully. The complete serial Swift regression passes 456 tests in
100 suites in 457.371 seconds, and the runner verifies a fresh completed xUnit
report. OCaml all/test/format/install passes. These results close the earlier
notification example and full-regression gaps; physical acceptance remains open.

The [widget inventory](swiftui-widget-inventory.md) now enumerates 228
public values and 175 named sum constructors from the four baseline UI
signatures. Every value has a family-level replacement direction and guide;
individual implementation, Gallery, interaction and variant acceptance still
require review. All rows remain pending those checks. This inventory does not
waive any component or replace the complete acceptance criteria.


### Retired backend source removal


A later active-source audit removed the remaining root Dart lint configuration
and Flutter hot-restart driver. Runtime error ID 10 is now named
`swiftui_renderer_exception` in the schema and regenerated OCaml/Swift bindings;
its numeric meaning is unchanged. Runtime trace directions, public comments
and native probe bundle identifiers use SwiftUI. The rrbvec probe checker now
reads the iOS minimum from `toolchain.lock`: its old iOS 15 expectation failed
against an actual iOS 18 object before the fix. The cross-compiler probe plist
also declares iOS 18. Both probes and protocol generation/fixture checks pass.
Protected spec OCaml files and the historical published SDK remain separate
pending requirements. The complete CI contract reaches the expected missing
published-SwiftUI-SDK failure after its compiler, Xcode, virtual-library and
artifact subchecks pass. The same SDK prerequisite now runs first and reports
that failure in 0.457 seconds without launching those expensive checks.
This preserves the release gate; the overall CI contract is not passing.
`_build/validation/swiftui-remaining-backend-paths.json` records the evidence.

The root `flutter/` tree is removed, including the old renderer, native package
hooks, Dart tests and aggregate Flutter integration host. The baseline tree
contained 256 tracked files. Current source discovery finds no Dart files or
pubspec manifests. Dedicated Flutter ignore rules are removed too. The C bridge
already lives in `native/`, and the Apple application builds use it directly.

The CI contract first fails on the retired root's presence, then passes after
removal. OCaml all/test/format/install passes after removal. The first CI run
identified a generated Host Effects project carrying the explicit signing-team
override from the iOS build; `sync-host` restores canonical generated settings,
and the complete CI contract then passes. The signed built App remains valid.
The 456-test Swift regression covers the unchanged Swift implementation before
the inactive source tree was deleted.

Architecture, lifecycle, wire and ABI documentation now describe SwiftUI, BSFR
4.0 and native ABI 3.0. Old renderer performance numbers remain explicitly
historical and do not establish SwiftUI budgets. The current eleven physical
iOS complete objects pass target/ABI-export audits and contain no prohibited
process imports; Host Effects additionally has a verified development-signed
iOS Release bundle. Physical execution, package/module renaming, remaining
services/widgets, final captures and source/SDK publication remain required.

### Asynchronous SwiftUI action menus

Host request 11 now decodes into a scrollable SwiftUI sheet with native Buttons.
The real OCaml callback receives the selected UTF-8 identity or dismissal;
cancellation and lost active/visible ownership close the chooser. Native
presentation and request UUIDs fence old actions across close and restart.
Menu and file-dialog requests share modal admission, and the chooser blocks
background input and temporarily pauses notification interaction and timeouts.

OCaml public validation and both wire codecs enforce the same bounded choice
domain. Byte identity preserves canonically equivalent but differently encoded
Unicode IDs. IDs reserve five bytes for the optional-string response prefix so
accepted values fit the 1 MiB response budget. Host Effects exposes Choose action
and renders the actual typed result. See [the contract](swiftui-host-menus.md).

Ten baseline menu/FAB/split-button values now have individual API and parameter
mappings in the widget inventory. This is a separate API review of inline menu
composition, and it does not claim physical acceptance or replace the complete
widget inventory gates.

The action-menu checkpoint passes the full Swift regression: 462 tests in 101
suites, 469.588 seconds, with a fresh completed Swift Testing xUnit report.
OCaml all/test/format/install also passes. Both checks include the final
optional-string response-size bound. No new Mail capture or device execution
is claimed by these regression results.

The standalone Host Effects window scenario passes in 40.996 seconds with
actual menu selection and existing native services. Three platform checks pass
in 22.264 seconds, including iOS 18 module emission and all eleven Swift example
entrypoints. Host Effects and Mail macOS Debug bundles rebuild, pass deep/strict
signatures and arm64/macOS 26 object checks, and retain canonical generated
projects. iOS native-object/App records remain from earlier checkpoints. The
rebuilt Mail still cannot be captured through CUA because the Mac reports locked.


### Native haptic feedback checkpoint

Host request 12 now validates and submits the four typed haptic intents through
UIKit impact/selection generators or AppKit generic feedback. The service
rechecks owned active presentation at execution time. Native submission returns
an empty success response; physical output remains controlled by the system.
Repeated requests, cancellation, hidden/inactive state, missing ownership and
restart execute through actual OCaml in the runtime tests. Host Effects exposes
four native Buttons and renders their typed results. UIKit view interactions
are bounded to four cached generators and removed on window reset or View
replacement. See [the haptic contract](swiftui-haptics.md).

The standalone native App passes its menu, haptic and existing service scenario
in 42.030 seconds. Three platform checks pass in 22.550 seconds. OCaml
all/test/format/install passes. All eleven current physical-iOS complete objects
cross-build and pass arm64/IOS/18.0 and ABI checks, with no prohibited process
imports. Host Effects and Mail build through the public CLI as signed iOS
Release and macOS Debug Apps. Both iOS Apps pass native bundle/privacy and
provisioning/certificate authorization checks.

The first macOS CLI invocation found the installed pre-migration UI library;
prepending this worktree's `_build/install/default/lib` to OCAMLPATH resolves the
example against the current public API. The user's installed switch is unchanged.
The generated projects remain canonical because signing is a build override.
Physical feedback, UIKit generator lifecycle on-device, remaining services and
widgets, final Mail captures, full current-source regression and publication
remain unfinished. The earlier 462-test full run predates this haptic addition.

The final scoped regression passes 11 tests in four suites in 0.691 seconds,
with a fresh completed Swift Testing xUnit report after the UIKit cache change.
The two generated projects pass `sync-host --check`, and staged iOS object hashes
match the cross-built artifacts. `_build/validation/swiftui-haptics.json` records
source, logs and all four App identities. Protected spec files remain unchanged.

### Shared civil host dialogs

The [civil host picker contract](swiftui-host-pickers.md) now covers BSFR request
kinds 16–18 and the public date/date-range/time host APIs. Menus and selectors
share `NativeHostDialogs`; the former menu-only controller and presenter are
removed. Initial values, inclusive bounds and civil validity are checked in
OCaml and Swift. Material entry-mode/current-day/dial fields are removed;
clock formatting has System/12/24 choices. Native forms keep draft edits until
Save and preserve cancellation, background input blocking, modal contention,
inactivity and request/presenter identity fences.

The real native control test exposed reversed OCaml response reads caused by
argument evaluation order. Sequential reads now preserve date components,
ordered range endpoints and clock fields. Regression tests cover Gregorian
cutover dates, leap-year clamping, range repair, UTC midnight, default selection,
all three forms' cancellation and retained callbacks after restart.

Verification at this checkpoint:

- `dune build @all @runtest @fmt @install` passes, including public invalid-value
  rejection and both OCaml codec directions.
- The fresh-report scoped Swift run passes 34 tests in seven suites in 36.642
  seconds, including the existing menu and civil selection checks.
- The standalone Host Effects window passes in 45.504 seconds. It presses
  Choose date, Choose date range and Choose time, saves each native sheet and
  reads the resulting OCaml status, alongside existing service scenarios.
- Three platform checks pass in 22.664 seconds, including iOS 18 module emission,
  all eleven Swift application entrypoints and explicit unsupported targets.

The inventory now contains exact API/parameter reviews for four civil widget
values and explicit dispositions for their four old page/hour-format variants.
Their overall acceptance stays pending. Physical iOS UI, accessibility and final
Mail captures remain outstanding. Protected spec files were not changed; no
source or SDK publication occurred. The current-source full Swift run passes 471 tests in 103 suites in 487.769
seconds, with a fresh completed Swift Testing xUnit report. This includes the
haptic checkpoint and shared menu/picker lifecycle changes.

All eleven iOS 18 complete objects were rebuilt after the host picker change and
passed architecture, deployment, ABI and prohibited-process-import checks.
The public CLI rebuilt Host Effects and Mail as macOS Debug and signed iOS
Release Apps. Both iOS bundles passed provisioning/privacy validation, and
their staged objects exactly match the current cross-build hashes. Both generated
hosts pass `sync-host --check`. Other example App bundles retain earlier linking
provenance; the eleven current complete objects are independently recorded.
No new physical run or screenshot is claimed. The source remains uncommitted.

### Automatic UIKit environment observation

The [host environment guide](swiftui-host-environment.md) now covers iOS window
geometry, physical safe areas, SwiftUI preferences and keyboard edge occlusion.
A non-interactive window child owns its keyboard layout guide, keeping full
viewport dimensions independent of SwiftUI's keyboard avoidance. Floating and
partial-width occlusion is not encoded as a whole-edge inset. Scheduled samples
coalesce on the main actor; source teardown removes the window child and fences
queued callbacks. UIKit keyboard event capture is still a separate missing
implementation.

Host Effects renders the actual reactive OCaml environment. A new iOS UI test
focuses its URL field, checks nonzero keyboard occlusion with stable viewport
size, clears focus and checks zero occlusion, then relaunches. The paired device
is unavailable, so this physical test has only been built, not run.

Verification:

- OCaml all/test/format/install passes.
- The final fresh-report Swift run passes 12 tests in four suites in 9.625
  seconds, including keyboard geometry and existing native/OCaml observation.
- The standalone Host Effects App passes the environment status plus existing
  service scenario in 45.881 seconds.
- Three platform checks pass in 23.081 seconds, including iOS 18 module emission,
  all eleven Swift entrypoints and rejection of unsupported targets.
- The generic iOS 18 arm64 UI-testing target builds successfully without signing
  in isolated DerivedData; its test binary passes platform/deployment checks.
- All eleven iOS complete objects pass architecture, ABI and import audits.
  Current Host Effects/Mail macOS Debug and iOS Release Apps pass signing checks;
  both iOS Apps also pass provisioning/privacy and staged-object identity checks.
  Both generated Xcode hosts pass sync-host --check.

`_build/validation/swiftui-uikit-environment.json` records this checkpoint.
The last full 471-test Swift run predates these changes. No device interaction,
new screenshot, source commit/push or SDK publication is claimed. Protected spec
files remain unchanged; remaining widget/variant/device and release gates stay
open.

### Current Mail screenshots after namespace and appearance changes

On September 14 the desktop and iPhone became accessible. Mail binary hashes
matched the verified namespace-build checkpoint before a fresh macOS launch
and physical-iOS installation. Four original macOS application-window JPEGs
now show Inbox, expanded preview, detail and Archived. Actual native actions
mark Mara Vale read and move it into Archived through the OCaml model. A fresh
Xcode Devices PNG from the signed Release App on iPhone 13 confirms light
navigation chrome and light content together. No image pixels or system
appearance/accessibility settings were changed.

[Current captures and provenance](screenshots/swiftui-mail/current/README.md)
record these five images, source/binary hashes and the device launch result.
The physical UI test attempt completed with exit 65 before either scenario:
XCTest timed out enabling automation mode, and an actual device screenshot
showed the separate passcode authorization prompt. Its result summary is
retained with the captures. Do not count this as an application test failure
or passing expansion/attachment/swipe behavior. No automatic retry is needed
until the device authorization changes. Source/SDK publication, remaining
widget acceptance and final release captures are still open.


### SwiftUI SDK repository generation

SDK generation now starts from explicit dependency metadata in
`vendor/opam-ios/sdk-packages`, the current physical-iOS compiler template and
pinned upstream repositories. It reads `bonsai_swiftui.opam` from the locked
framework Git commit instead of reusing the previous generated repository or
current working tree. The framework and its `conf-ios`/`conf-pkg-config`
dependencies now appear explicitly in the package universe. A fully staged
repository replaces the entire destination, so obsolete packages disappear;
failed source validation and `--check` leave existing output intact.

The manifest and generated framework build recipe receive iOS 18.0 from the
toolchain lock. The local `conf-ios` recipe also fixes iOS 18 arm64. Both
source closure headers now use the current SwiftUI format; the old headers
were rejected by the current verifier before the fix. No legacy decoder or
package alias was introduced.

Verification includes two real Git/filesystem integration tests, empty-output
bootstrap, exact locked metadata despite later HEAD and dirty source changes,
repeatable generation, stale-output detection/removal and preservation after
missing source metadata. `make ios-sdk-repository-test` also validates both
source closure locks. A separate full-dependency fixture generates 247 package
universe records and 14 local packages from the pinned default/cross metadata;
`--check` reproduces the output and `opam lint` passes (existing upstream
metadata-field warnings remain). Logs and input hashes are recorded in
`_build/validation/swiftui-sdk-generator.json` and the full-generation manifest.

This is repository assembly evidence. The temporary framework Git fixture is
not a published archive and was not compiled as an installed SDK. The current
source lock correctly fails before generation because its previous revision
has no `bonsai_swiftui.opam`. The checked-in published SDK snapshot and protected
OCaml spec files remain unchanged. Final source commit/push, archive identity,
installed-SDK validation and the separate generated-SDK commit/push remain
required.


### Installed SwiftUI CLI acceptance

The installed-prefix gate now runs the existing real external counter scenario
against physically installed Dune packages and the tool's declared opam asset
installation commands. It removes `BONSAI_SWIFTUI_SOURCE_ROOT`, restricts
`OCAMLPATH` to the temporary prefix and invokes the copied `bonsai-swiftui`
executable from an unrelated application directory. The generated Xcode project
references the installed Swift package. Debug/Profile/Release builds, strict
signatures, native button-to-OCaml Count: 0 -> Count: 1, and child-command
argument/exit propagation pass in 85.552 seconds. The test is available through
`make installed-cli-test` and included in `integration-test`.

The existing package resource declarations were sufficient; this checkpoint
adds boundary evidence without changing runtime or package implementation.
No user opam switch was changed. The test executes the declared installation
steps in isolation; it does not establish opam solving, a registered installed
package, published source or an installed iOS SDK. The log is
`/tmp/swiftui-installed-cli.log`; `_build/validation/swiftui-installed-cli.json`
records test/recipe hashes and scope.


### Foundational widget API review

[The foundational review](swiftui-core-api-review.md) maps 15 baseline values
for identity, test metadata, empty/text content, stacks, frames and modifiers
to their current declarations and parameter semantics. The JSON inventory now
has 29 individual API reviews. Exact declaration references and named fixture
entrypoints were checked; the existing 14 review line numbers remain valid.
The removed center factors, Fade overflow and save-layer selection are explicit
native API choices. Headless helpers have no invented visual Gallery scenario.

Current scoped verification passes 18 native layout/paint/validation tests and
10 actual OCaml/Gallery integration tests. No renderer implementation change
was needed. `_build/validation/swiftui-core-api-review.json` records hashes,
counts and logs. All overall acceptance fields remain pending, including
physical iOS, remaining variants and the unreviewed public surface.


### Control API review and current acceptance status

[The control review](swiftui-control-api-review.md) adds explicit API mappings
for 29 values and 42 named constructors. Declaration references, renderer/test
files and fixture-to-Gallery component links were validated. The inventory now
contains 58 individual value reviews; full interaction acceptance remains open.
Existing focused verification passes 28 tests in seven suites (17.732 seconds),
with no renderer change. Source hashes and scope are recorded in
`_build/validation/swiftui-control-api-review.json`.

The governing decision's acceptance preamble now reflects implemented UIKit
keyboard/environment observation, all host-service dispatch paths, current
Mail captures and the current SDK metadata blocker. Historical checkpoints
remain historical; they no longer imply these implementations must be repeated
or that the full CI contract currently passes. The completion requirements
are unchanged.


### Layout and content API review

[The layout/content review](swiftui-layout-content-api-review.md) adds 49 value
mappings, 14 named-constructor dispositions and a separate seven-case Image_fit
review. The inventory totals are 107 values and 56 primary constructors. Native
sizing, safe-area, weighting and layer-ownership changes are explicit; source
inspection confirms the old overlay dismissible field had no renderer behavior.

The referenced Swift source/test hashes match the current 482-test regression,
which was reused without rerunning it. The separate viewport type gate passes
valid composition and all six expected compile failures. No renderer code was
changed. `_build/validation/swiftui-layout-content-api-review.json` records this
scope; complete physical-device and remaining surface acceptance remain open.


### Actual macOS file chooser completion

The public CLI rebuilt Host Effects from current source in Debug. CUA then
selected two generated files in the actual system importer, exported OCaml
bytes through the actual destination panel, confirmed replacement of a changed
test file, and cancelled subsequent import/export panels. OCaml displayed each
success/cancellation result. Filesystem checks confirmed exact imported/exported
bytes, unchanged source fixtures and preservation after cancellation. No direct
callback injection or renderer change was involved.

[File-service captures](screenshots/swiftui-host-effects/file-services/README.md)
retain original UI pixels and source/binary/file hashes. This closes the macOS
chooser selection/overwrite evidence gap; physical iOS file-provider interaction
remains open. The build log is `/tmp/swiftui-file-panel-build.log` and detailed
results are in `_build/validation/swiftui-file-panel-current.json`.


### Native extension API review

[The extension review](swiftui-extension-api-review.md) accounts for all 39
baseline Native_widget values and 36 constructors. It maps retained generic
registrations and composers, and the Slidable, auto-close, Morphing_surface and
Navigation_shell capabilities that became typed core controls. Event identity,
native draft ownership and removed Flutter presentation parameters are explicit.
The inventory totals are now 146 individually reviewed values and 92 constructors.

The expandable composer public comment now describes its existing kind-7,
version-2 SwiftUI registration. Reconstructing its previous comment reproduces
the exact signature-file hash from the complete 482-test regression, confirming
that this source edit is comment-only. Referenced Swift/test hashes still match
that run; no runtime suite was repeated. Formatting and document checks pass.
`_build/validation/swiftui-extension-api-review.json` records the evidence;
physical interaction and remaining inventory acceptance are not closed.


### Scroll and list API review

[The list review](swiftui-list-api-review.md) adds 39 value mappings and 28
constructor dispositions for scrolling, catalogs/windows, list composition,
Table, removal, refresh and contextual selection. The inventory now records
185 reviewed values and 120 constructors. Parameter changes include explicit
catalog geometry, per-item requests, native disclosure membership, separate
Carousel position/actions and removal of Flutter visual/controller flags.

References were checked against current declarations, native renderer/test files
and actual Gallery fixture registrations. Swift source/test hashes match the
complete 482-test regression, so it was not repeated. Existing mixed-catalog
checks cover 10,003 records with fewer than 64 materialized items; they do not
supply a frame-time/memory budget. Stale guide statements claiming mixed virtual
content and Sliver retirement were unimplemented have been corrected.
`_build/validation/swiftui-list-api-review.json` records scope and hashes.
Physical interaction, self-sizing/Dynamic Type and remaining performance/widget
acceptance remain open. No runtime implementation changed.
