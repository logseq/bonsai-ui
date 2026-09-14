# SwiftUI-Only Backend for iOS and macOS

## Problem

The project currently makes Flutter the rendering target of an OCaml/Bonsai
application. The requested direction replaces that target entirely with
SwiftUI, supports only iOS and macOS, replaces every supported widget
capability, and allows public widget APIs to change to suit SwiftUI. The final
implementation must port Bonsai Mail and deliver screenshots of the running
application.

This is a backend replacement, not an additional renderer. Keeping Flutter's
widget vocabulary, layout rules, Material themes, Dart runtime coordinator, or
packaging would leave the new backend organized around the framework it is
supposed to remove.

This document records the agreed proposal. Implementation is in progress;
the migration, mail port, and screenshots remain the deliverables specified
below. See [the implementation ledger](../../../swiftui-implementation.md)
for completed work, verification, and outstanding requirements. Baseline
repository observations are from commit `39c4862` on 2026-09-11.

### Baseline implementation evidence

| Area | Current source and consequence |
| --- | --- |
| Public UI | `ocaml/ui/widget.mli`, `material.mli`, `cupertino.mli`, `theme.mli`, and `native_widget.mli` expose Flutter-shaped layout, controls, themes, and extensions. |
| Wire model | `protocol/schema.sexp` declares protocol `3.0`, including Material, Cupertino, Sliver, and native-widget nodes. `material_expressive` multiplexes additional controls, so counting node kinds alone misses public capabilities. |
| Renderer | `flutter/packages/bonsai_flutter/lib/src/` owns transactional node storage, rendering, navigation, text input, host effects, scheduling, and resource disposal. |
| Native boundary | `flutter/packages/bonsai_flutter_native/src/` contains reusable C runtime and bridge code as well as Flutter package infrastructure. `ocaml/ffi/` embeds the OCaml runtime. Deleting the Flutter directory must not accidentally delete the only native bridge. |
| Runtime | `ocaml/runtime/` owns application state, handlers, reconciliation, clock advancement, presentation tokens, and the optional Eio Worker Domain. These responsibilities remain useful. |
| Tooling | `bonsai_flutter_tool/lib/{config,host,scaffold,plan,build_system,artifact,assets,sdk,toolchain}.ml` couples native compilation to Dart hosts, pubspec, Native Assets hooks, and Flutter commands. |
| Apple SDK | `tool/ios/sdk_repository.lock` and `tool/ios/opam-repository/0.1.0/` separate the immutable compiler/dependency closure from the replaceable framework SDK. |
| Mail | `examples/mail/ocaml/mail.ml` owns data and behavior; its Flutter host adapter is mechanical. `examples/mail/test/mail_example_tests.ml` covers behavior alongside assertions tied to current widget structure. |
| Platforms | Current configuration is macOS 26.0+ arm64 and physical iPhoneOS 15.0+ arm64. The tool has no iOS Simulator target. |

Local read-only preflight found Xcode 26.1.1. `xcrun simctl list devices
available` returned no available devices. This does not establish whether a
usable physical iPhone or development signing identity is available.

## Proposal

### Fixed requirements and selected direction

The following requirements are already supplied by the user and are not open
questions:

- Make SwiftUI the sole UI backend, supporting only iOS and macOS.
- Replace all currently supported widget capabilities with SwiftUI versions;
  changing names, composition, layout, and platform presentation is allowed.
- Remove Flutter and Dart code, dependencies, runtime paths, and tooling.
- Add no compatibility aliases, dual renderers, migration machinery, or old
  protocol decoders.
- Port the mail example and provide actual runtime screenshots after the
  implementation is complete.
- Do not spend migration work on fine-grained example UI polish. Prioritize
  backend behavior, build/distribution correctness and required acceptance.
- The user temporarily removed the physical iPhone on September 14. Pause
  device-dependent work until it is available again; continue macOS, source and
  packaging work. Interrupted device runs are not passing evidence.

Use the project/module/package family `bonsai_swiftui`, the Swift module
`BonsaiSwiftUI`, the CLI `bonsai-swiftui`, and consumer configuration
`bonsai-swiftui.sexp`. Rename in-repository active identifiers together, without
old command wrappers or package aliases. Renaming the remote GitHub repository
is outside this implementation; its existing URL can remain the source origin.

The user selected iOS/iPadOS 18.0+ arm64 on physical devices and macOS 26.0+
arm64. iOS Simulator is explicitly unsupported.
iPad is an iOS application destination, not another backend. Exclude Android,
Linux, Windows, Web, Catalyst, watchOS, tvOS, visionOS, Intel Mac, and universal
builds. Keep one active runtime and one application window initially; do not
accidentally turn SwiftUI scenes into unsupported multiple OCaml drivers.

The selected iOS minimum makes modern scroll-position APIs available without
an older-OS implementation. Apple documents `ScrollPosition` as available from
iOS 18 and macOS 15. Keeping the existing macOS minimum avoids claiming a wider
OCaml runtime support matrix merely because SwiftUI supports it.
[Apple: ScrollPosition](https://developer.apple.com/documentation/swiftui/scrollposition)

[SwiftUI swipe actions](../../../swiftui-swipe-actions.md) records the current
core replacement and real Gallery/Mail action evidence. Native mouse tests now
pass cross-axis rejection and full actions in LTR, RTL and vertical scenarios.
Physical scroll arbitration, interrupted gestures, physical-device checks and
Mail screenshots remain outstanding.

[Native pointer event transport](../../../swiftui-pointer-events.md) preserves
enter/leave/down/up metadata through Swift encoding and actual OCaml handlers.
Passive AppKit cursor capture also passes native callback-to-OCaml tests.
Shared hover/contact state also passes actual OCaml round-trip tests, and a
UIKit adapter typechecks for physical iOS. `View.hover_region` replaces
MouseRegion with explicit `blocks_behind` behavior. Its renderer now gates
presented input, routes overlap while retaining ancestors and preserves child
Button actions. Root-epoch replacement and hidden-window re-entry have native
regressions. Window input sources are now shared, registration scans are batched
and session inactivity/closure immediately releases sources. The native Gallery
scenario also passes a movement event through its own application queue.
UIKit runtime behavior, AppKit tablet capture, nonrectangular
clipping, performance and physical interaction remain unfinished; callback tests
alone do not establish widget completion.

### Physical iOS runtime test hosting

The [native DataScript Worker probe](../../../swiftui-datascript-worker.md)
replaces the separate Dart device probe with a SwiftUI host and the production
Swift runtime. It preserves typed persistence/restoration, generated JSON, RRB
and shutdown evidence. Its unsigned App build and macOS process tests are
separate from physical-device execution and complete application rendering.
The probe also exposed missing iOS process-import isolation; the extracted
process stubs are now included in physical-iOS complete objects, so older iOS
App artifacts must be rebuilt before final acceptance.

Physical-device preflight now consumes CoreDevice JSON directly, requires the
selected UUID or hardware UDID and iOS 18+ arm64 readiness, and uses the resolved
UDID for exact provisioning-profile membership. Flutter discovery and the
nonexistent CoreDevice `bootState` requirement are removed. See
[native device preflight](../../../swiftui-ios-toolchain.md#native-physical-device-preflight)
for replayed regression coverage and the separately recorded live-device result.

The physical-device XCTest attempt exposed a gap in the initial Xcode host:
tool-hosted tests can compile for iPhoneOS but cannot execute on a device.
Generate a separate minimal SwiftUI test-host App for iOS when an application
provides `apple-tests` sources. The host does not link BonsaiSwiftUI or the OCaml
complete object; its XCTest bundle owns the runtime under test. This prevents
competition with the actual Mail UI session while retaining startup, frame,
presentation and restart coverage of the real application complete object.
macOS retains tool-hosted XCTest. No Simulator path is added. See
[Xcode host evidence](../../../swiftui-xcode-host.md).

### Application-owned native UI tests

Discover platform-specific UI test sources under `apple-ui-tests/ios/` and
`apple-ui-tests/macos/`. Generate an Xcode UI-testing bundle for each platform
that has such sources, targeting the actual application. The UI test runner
must not link BonsaiSwiftUI or the OCaml complete object; it drives the separate
App through system accessibility and gestures. Keep runtime XCTest and UI test
bundles distinct in each platform scheme. No Simulator scheme or shared
Swift-only application fixture is introduced.

Mail's physical-device scenarios must launch its real local OCaml program,
expand and collapse inline previews, open the attachment-bearing message, and
reveal and execute swipe actions. Retain original XCUITest screenshot
attachments and inspect them before claiming screenshot acceptance. App-hosted
runtime XCTest remains a separate lifecycle gate.

### Source package namespace checkpoint

The source packages, CLI directory, public findlib names, ordinary OCaml modules
and all eleven example packages now use the `bonsai_swiftui` family. Build
recipes, SDK schema names and active application templates use the same names;
there are no old public-package or command aliases. Following the user's
three-line protected-source authorization, the virtual spec library now has
the internal module name `Bonsai_swiftui_spec`. Its public package remains
`bonsai_swiftui.spec`; the implementation, contract test and ordinary source
references use the new internal name. Two protected comments now use native
and SwiftUI terminology. ID types and behavior are unchanged.

The renamed source passes the OCaml all/test/format/install gate and protocol
and fixture generation checks. All eleven iOS complete objects rebuild and pass
iOS 18/arm64 verification with new spec symbols and no old spec symbols. A fresh
installed CLI prefix contains no obsolete Flutter library artifacts; its external
application passes Debug/Profile/Release builds and real OCaml counter updates
(86.276 seconds). The physical UIKit editor test also passes with the renamed
object (10.716 seconds), covering marked text, Unicode selection, commit and
unmount/remount. Evidence is recorded in
`_build/validation/swiftui-spec-namespace.json`.
Existing immutable SDK snapshot metadata has not been regenerated or
published. Its source revision/checksum still identify the previous snapshot;
regeneration must use the final pushed source, and distribution is not complete.

### UIKit keyboard capture

KeyboardListener now shares focus/presentation admission and key-sequence
ownership across both Apple renderers. UIKit uses a window-owned passive press
observer and an interceptor that ignores unhandled presses, retaining native
HID identifiers. Node 53 no longer fails iOS decoding. Shared sequence and actual
AppKit/OCaml tests pass; physical UIKit propagation, hardware repeats, IME and
modal/accessibility acceptance remain required. See
[native keyboard evidence](../../../swiftui-keyboard.md).

### Application ownership and host structure

Mail retains its fixed light palette and requests `Theme.Light` at the application
root so native navigation and tabs use the matching appearance. The actual
macOS Mail window scenario passes with both light and dark inherited AppKit
environments. This is an application preference, not a system-setting change
or a renderer-wide restriction. Physical-iOS appearance and updated screenshots
remain required; see [Mail capture evidence](../../../screenshots/swiftui-mail/README.md).

The application root now accepts `View.Body.t` through `App.View.create`.
Ordinary content uses `Body.static`; scrolling content receives its bounds from
the application window without a Scaffold. Existing consumers use the explicit
body contract, and the actual Clock example exercises it through native timer
and window tests. See [bounded application bodies](../../../swiftui-application-body.md).

```text
OCaml/Bonsai application and typed SwiftUI-oriented view description
                         |
              OCaml reconciliation and handlers
                         |
              versioned binary frame and C ABI
                         |
             serialized Swift runtime coordinator
                         |
           MainActor validated renderer transaction
                         |
              SwiftUI view and modifier hierarchy

SwiftUI interaction -> typed event batch -> coordinator -> OCaml/Bonsai
OCaml UI domain <-> bounded messages <-> OCaml Eio Worker Domain
```

OCaml continues to own business data, selected values, expanded items, route
identity, application navigation, asynchronous work, and semantic animation
intent. Swift owns rendering, native layout, accessibility, gesture progress,
focus/IME sessions, temporary editing echo, scroll position, interpolation,
and native resource lifetimes. The Swift renderer must not import Mail or
implement a second mail reducer.

SwiftUI `Binding` setters enqueue typed intents carrying epoch, node, handler,
and displayed revision; they do not call OCaml synchronously while evaluating
`body`, laying out views, or processing a native delegate callback. Local
optimistic state must have a defined reconciliation rule against the next
accepted OCaml value. Navigation cancellation and stale selection changes
must not produce duplicate actions or re-open a dismissed destination.

Use an owned serial executor or dedicated host thread for native calls. A
plain Swift actor is not sufficient evidence of fixed thread affinity or
non-reentrant session ordering across `await`. Verify OCaml foreign-thread
registration, lock acquisition, startup-once behavior, and exact-once shutdown
against the existing C bridge. Preserve the internal Worker Domain boundary.

Decode and validate candidate frames before publishing a single committed
renderer generation on `MainActor`. Reject malformed references, cycles,
invalid properties, stale epochs, and incompatible versions without publishing
partial state. Keep node-level observation and stable identity based on
`(runtime_epoch, node_id)`, with keyed children in SwiftUI collections. Resource
cleanup follows logical node removal, kind replacement, epoch change, or
shutdown; temporary view disappearance must not reset a still-mounted editor.

Dynamic OCaml trees cannot become arbitrary statically generic Swift types.
Use a finite typed node enum and renderer dispatch, with type erasure only at
the necessary recursive or extension boundary. Measure invalidation and row
identity rather than assuming that wrapping every node in `AnyView` is cheap.

### Public API and complete widget capability mapping

Replace the `Widget`/Material/Cupertino organization with an OCaml `View` API
organized around content, layout containers, modifiers, controls, lists,
navigation, presentations, and environment. Native registration becomes typed
Swift view registration. The names below are proposed concepts, not already
available functions.

Use native semantics instead of preserving exact Material appearance. Merge
overlapping constructors into one semantic control with styles. Preserve
actions, validation, disabled/selected states, stable identity, and
accessibility. A composition is a full implementation of a capability, not an
unsupported placeholder.

The inventory must cover public constructors and their variants in addition
to protocol kinds. The following mapping includes the existing primitive,
Material expressive, Cupertino, and six built-in native extension families.

| Current capability | SwiftUI-oriented replacement |
| --- | --- |
| Empty, Text, RichText | `EmptyView`, `Text`, and attributed/styled text runs. |
| Icon, Image | SF Symbols by semantic name and bundled/image resources; delete Material font codepoints and icon-font packaging. |
| Row, Column, Flex, Stack, Positioned | `HStack`, `VStack`, `ZStack`, `Spacer`, alignment, layout priority, and explicit custom `Layout` where weighted or positioned composition is necessary. |
| Padding, Align, Center, SizedBox, ConstrainedBox, PreferredSize | Ordered padding/frame/alignment modifiers and layout proposals. Remove Flutter parent data and preferred-size protocols; express toolbar sizing as toolbar content. |
| DecoratedBox, Clip, Opacity, Transform, AnimatedOpacity | Background/overlay/shape/clip/opacity/transform modifiers and semantic SwiftUI animation transactions. |
| Body, axis-specific Viewport, ScrollView | Typed content slots and horizontal/vertical `ScrollView`; document bounded sizing through SwiftUI layout rules. No `RenderBox`/viewport emulation. |
| Sliver box/list/fill/padding/fixed extent/varied extent and sparse transitions | Sections, lazy containers, explicit fill behavior, and the collection contract below. Preserve fixed/sparse sizing as collection policies where useful, removing the Sliver public type. |
| SliverAppBar and top/bottom AppBar | Navigation titles, toolbars, safe-area content, and pinned section headers. Custom collapsing/stretching header composition where the supported interaction needs it; remove Flutter `floating`/`snap`/elevation property bags. |
| Gesture, Pressable, FocusScope, MouseRegion, KeyboardListener | SwiftUI gestures, `ButtonStyle`, focus, hover, keyboard commands, and typed input events. Keep nested-control isolation and scroll-versus-press arbitration. |
| Semantics and test IDs | Accessibility labels, values, traits, actions, grouping, and identifiers backed by the same OCaml headless query concepts. |
| SafeArea, EnvironmentBoundary, Theme | Safe-area modifiers and scoped environment values for color scheme, semantic colors, typography, contrast, layout direction, and Dynamic Type. Delete Material seed-palette and density contracts. |
| Navigator, Page, Overlay | OCaml-controlled `NavigationStack`/`NavigationSplitView`, destination identity, overlay alignment, and typed presentation state. |
| Scaffold and NavigationShell | Root navigation composition, toolbar slots, `TabView`, sidebar/split navigation, and persistent bottom content. Delete the Scaffold/FAB slot protocol. |
| Elevated/Filled/Tonal/Outlined/Text/Icon/Cupertino buttons, FAB and FAB menu | One `Button` family with roles, label styles, size, prominence, and action `Menu`; app-level primary actions use toolbar or an explicit floating composition. |
| Checkbox, Material/Cupertino switch, ToggleButton | `Toggle` with supported native or composed styles. Boolean state stays controlled; no Flutter-shaped duplicate constructors. |
| RadioGroup, SegmentedButton | `Picker` for single selection; a SwiftUI group of selectable controls for multiple/optional selection, retaining stable selected-ID set semantics. |
| Slider and RangeSlider | Native `Slider` and a composed two-thumb interval control, including bounds, discrete steps, change/end events, and accessible adjustment. |
| Action/Filter/Choice/Input chips | Button/toggle/token compositions with wrap layout, optional removal, and the corresponding action/selection contracts. |
| TextField, SearchBar, SearchAnchor, AppBar search | Native text-entry surface and `.searchable` or a composed search field/suggestions surface, with revisioned editing, focus, submission, and length limits. |
| ListTile, Divider, Card, Badge, Tooltip | `Label`/row composition, `Divider`, native `GroupBox`, badge modifiers/overlays, and help/accessibility descriptions appropriate to the platform. |
| Circular/Linear progress and expressive LoadingIndicator | `ProgressView` and a SwiftUI loading style, retaining determinate/indeterminate state and accessible progress. |
| DataTable | Native `Table` where suitable and adaptive row/detail composition on compact iOS, preserving row selection and sort intents. |
| Stepper workflow | A composed multi-step flow with current/completed/error states and next/back actions. Do not confuse this existing workflow widget with SwiftUI's numeric `Stepper`. |
| ExpansionPanelList and ExpandableList finite/scrollable/sliver | Controlled `DisclosureGroup`/section compositions supporting single or multiple expanded IDs. |
| Simple/Fullscreen dialogs and modal dialog routes | `confirmationDialog`, custom sheet content, and platform-appropriate modal presentation with OCaml-owned dismissal intent. macOS need not mimic an iOS full-screen cover. |
| BottomSheet, SideSheet, modal detents and surfaces | Sheet, popover, or inspector-style composition. iOS supports native detents; macOS preserves presentation actions and content without simulating a mobile bottom sheet. |
| Menu, SplitButton, DropdownMenu | Hierarchical `Menu`, primary-action-plus-menu composition, and single/multiple pickers with loading/empty/error/search states. |
| ButtonGroup | Control groups or composed stacks/wrap layout with selection, overflow, and disabled states; collapse Material-only shape/style enums. |
| DatePicker and TimePicker | Linked native `Picker` fields for proleptic Gregorian dates and native `DatePicker` for wall-clock time. Preserve inclusive bounds, selectable-date rules and year selection, without the Material dial or calendar page modes. |
| Carousel | Horizontal/vertical scroll composition with selection, alignment, snapping where applicable, and layout-change reporting. |
| CardList finite/scrollable/sliver | Keyed GroupBox/Button compositions in finite or lazy collections under the common collection API; label/body actions have independent handlers. |
| Selection and Selection.leading | Controlled selected IDs, selection affordances, select-all and contextual actions. |
| DismissibleList column/horizontal | A request-driven removal composition retaining request token and ready/pending/accepted/rejected behavior. |
| Tabs, NavigationBar, NavigationRail, NavigationDrawer | `TabView`, segmented navigation, and sidebar/split navigation with stable destination IDs and selected state. |
| Toolbar and RefreshIndicator | Native toolbar placement/overflow with explicit commands; refreshable collection with OCaml-controlled request completion. |
| Native Slidable and SlidableAutoCloseBehavior | Native list swipe actions or a SwiftUI swipe container for arbitrary child content; preserve discrete actions, full-swipe intent, and one-open-group behavior where exposed. |
| Native MorphingSurface | SwiftUI animation/transition composition with stable identity, retained interaction state, and reduced-motion handling. |
| Native MessageComposer and ExpandableMessageComposer | One composer surface and a presentation wrapper, with draft ownership, button visibility, focus, limits, expansion/dismissal, and keyboard avoidance explicitly defined. |
| Generic NativeWidget extensions | Versioned typed props/events and a Swift factory registry, with explicit lifecycle and capabilities. Unsupported registration fails at initialization. |

[Button autofocus investigation](../../../swiftui-button-focus.md) remains open.
A foreground native focus test could not establish Button focus in the current
locked desktop session with keyboard navigation off. The remaining Material
Button/FAB APIs are not yet removed or marked complete.

[Native badges](../../../swiftui-badge.md) replace the Material badge helper
with directional SwiftUI overlays and exact integer counts. Visibility retains
content ownership; accessible count meaning belongs to the underlying control.

[Native labels](../../../swiftui-label.md) replace ListTile with native Label,
keyed text composition, selection semantics and independently enabled primary
and accessory Buttons. Native window checks verify action bounds and state at
two widths; physical iOS and complete Gallery acceptance remain required.

[Native text fields](../../../swiftui-text-fields.md) now provide plain and secure
revisioned entry through native Apple controls. Todo uses these fields with a
bounded SwiftUI body, native Buttons and Toggles, stable row identities and a
narrow-window layout. Native field/runtime/Todo tests cover acknowledgment,
submission, marked text, focus, selection, reversal and disposal. Native keyboard,
submit-label and presentation-gated autofocus configuration are now exposed.
Material TextField's OCaml API and wire node are removed, and Gallery, Network and
SQLite use the native constructor. Search/composer migration, physical iOS and
screenshot evidence still require work; this does not complete the full text-input
or example migration.

Network now uses a bounded SwiftUI body, native Buttons and a revisioned native
field, with HTTPS/TLS/WebSocket logic retained in the OCaml Worker. Its actual
macOS window test uses local TLS endpoints to exercise HTTP success, cancellation
and failure, Unicode WSS echo, disconnect, field identity and narrow layout.
The standalone development linker now stages static GMP for the TLS dependency
closure. Network's old Flutter host/configuration are deleted. Physical iOS,
production CLI/SDK packaging and CI consumer contract migration are still open.

The [embedded Worker](../../../swiftui-worker.md) now assembles the pinned Eio
backend without taking ownership of the SwiftUI host's SIGCHLD handler. Its
public environment retains file/network/clock/random/stream/domain capabilities
and removes the subprocess manager. A foreign-host-thread regression first
reproduced OCaml 5.1 signal-handler crashes, then passed with both default and
custom host handlers. The actual Worker backend now cross-links into signed
iOS Release examples; physical-device Worker behavior remains unverified.

SQLite Worker now uses a bounded SwiftUI body, native Buttons and a revisioned
field. Foundation prepares its application-specific support directory and SWC1
payload; the actual OCaml service owns SQLite and bounded file I/O. Its native
window test persists Unicode Todos and a deterministic 4 MiB file across two
separate app processes, checks database integrity and retained field behavior,
and verifies a narrow layout. Add now sends a text correction to clear the
native field; ordinary edits remain acknowledgments. The old Flutter host and
configuration are removed. Dune discovers the Apple SDK for system-library
lookup, and the native linker resolves SQLite against system libsqlite3.
SQLite Worker's actual iOS Release App now links and signs successfully against
the system SQLite library. Device execution, manual cancellation/VoiceOver and
visual acceptance remain open. See the
[SQLite Worker example](../../../../examples/sqlite_worker/README.md).

The native Semantics replacement is now described in
[SwiftUI accessibility](../../../swiftui-accessibility.md). It uses native
metadata, grouping, heading/sort/identifier modifiers and named custom actions.
Native controls own activation, enabled, checked, focus and secure-entry state.
The fixed action bitset is removed. Actual Gallery tests exercise native
accessibility actions through OCaml and gate live announcements on successful
presentation acknowledgment. Physical VoiceOver acceptance and the complete
Mail accessibility experience remain unfinished.

[Native Progress](../../../swiftui-progress.md) now replaces the three Material
progress/loading constructors with one keyed node and SwiftUI ProgressViewStyle.
Determinate circular and indeterminate linear behavior is explicit on both
platforms. Actual Gallery tests cover native accessibility, painted fractions,
mode updates and local animation suspension. Mail's ordinary icon/text buttons
now use native plain Buttons; complete Mail rendering remains in progress.

[Native safe areas](../../../swiftui-safe-area.md) now replace the old
SafeArea wrapper with explicit SwiftUI region/edge selection and additive
safe-area padding. Actual Gallery tests cover real macOS titlebar insets,
region changes, directional padding, resizing and retained nodes. Mail uses
the new composition; physical keyboard/home-indicator acceptance remains open.

[Native Sliders](../../../swiftui-slider.md) now replace Material scalar/range
constructors with `View.Slider`, explicit domain-unit steps and required end
events. Native accessibility and keyboard focus tests cover both endpoints,
horizontal/vertical layouts and RTL; actual Gallery events reach OCaml,
including ignored responses and a vertical end-only control. Eight native mouse
scenarios now pass for collapsed-thumb direction selection, collision, release
position and domain bounds across both axes and layout directions. Interrupted
drags, nested interaction and physical iOS acceptance remain required; these
controls are not yet fully accepted.

Apple's custom `Layout` protocol supports proposal-based measurement and
placement; it is a suitable basis for the composed layouts above, not a reason
to reproduce Flutter's constraint solver.
[Apple: Layout](https://developer.apple.com/documentation/swiftui/layout)

### Collections, mail expansion, and native gestures

Separate item data, stable item identity, requested materialization, and
renderer scroll state. The Swift host reports coalesced visible ranges or
materialization requests; OCaml supplies keyed content asynchronously. SwiftUI
must never synchronously call FFI from a row builder or layout pass.

Keep a bounded materialized OCaml window and cached renderer content around
the viewport. Mail's existing 24-row window is the initial measurement target;
an explicit visible-plus-overscan policy may replace that constant. It must
remain bounded independently of loaded message count. Fixed/sparse extents
can size unloaded gaps; self-sizing rows require measured-height caching and
stable anchor restoration. Define estimation, invalidation on width/Dynamic
Type changes, and noninteractive gaps before declaring self-sizing complete.

Prototype a native `List` first for mail's adaptive rows and system actions.
The prototype must prove bounded OCaml materialization, rapid jumps to unloaded
ranges, paging, expansion anchoring, and retained scroll position. `onAppear`
alone is not a precise visible-range contract. If `List` cannot meet those
requirements, select a SwiftUI `ScrollView` plus lazy layout and explicit
geometry/anchor coordination before finishing the implementation. This is an
exploration choice; the final API must have one documented collection path
per actual semantic need rather than runtime fallbacks for the same behavior.

The native List experiment is now recorded in
[windowed SwiftUI collections](../../../swiftui-collections.md). On the tested
macOS SDK, matching the minimum height made fixed rows exact, but an offscreen
sparse-height change did not update the cached table geometry. Select SwiftUI
ScrollView with an explicit window layout for this virtual collection path.
Only the asynchronously materialized window enters the SwiftUI row hierarchy;
the layout computes unloaded space from declared extents. Do not add a runtime
List fallback. This choice preserves the full requirements for stable identity,
self-sizing measurement, anchoring, paging and generic swipe actions. Native
geometry and actual OCaml Mail paging tests pass. The public catalog/window
API, wire nodes and BonsaiSession scheduling now pass actual Gallery runtime
tests. Sparse extent timing now crosses the public protocol and animates locally
with anchor retention, interruption and reduced-motion handling. Mail now stages
its complete tree and passes standalone window expansion and Archive checks.
Native measured sizing now has a public catalog mode, key-based extent cache,
width/Dynamic Type invalidation, stale-callback rejection and native anchor
restoration. Actual Gallery runtime tests cover both axes and LTR/RTL, including
a distant jump and deletion before the visible key. Native layout tests cover
shrinking text without a ScrollPosition feedback loop. Mail now uses measured rows, minimum content heights and wrapping outline text.
Body-relative font scaling and an accessibility row layout accompany the native
cache. The macOS window test exercises actual column resizing, collapse,
re-expansion and Archive. Physical gesture acceptance remains unfinished.
Collection now supports both axes using one key/extent catalog, logical anchors
and bounded window implementation. Public sizes use default_extent and extent;
the height-only argument/field names are removed. Native macOS LTR/RTL tests
verify distant window placement, sparse transitions, resize anchoring and actual
OCaml range feedback. Further physical iOS acceptance remains open; see
[windowed collections](../../../swiftui-collections.md).

Mail now emits catalog/window nodes and uses native Scroll for detail; the old
Mail Sliver parser is removed from tests. The eager horizontal/vertical Scroll
API also runs through actual Gallery tests and replaces Clock/Todo wrappers.
All four native scroll containers now expose optional ordered `on_scroll`
observations, independent of collection range and target-position bindings.
Native tests cover four containers, both axes and RTL, toggling, hidden/resumed
lifetimes, nested source isolation and explicit queue backpressure. Phase zeros,
reversals and intervening input remain lossless; adjacent same-direction runs may
compact. Ordinary content now fills the remaining viewport through optional
Scroll.fill_viewport and existing Weighted stacks. Both axes retain larger
intrinsic content, resize and toggle without replacing the native ScrollView;
Sliver.fill and node 34 are deleted. Initial positions are now explicit:
Scroll/Scroll_sections accept logical Start/End, while Collection also accepts a
stable catalog key. Initial configuration changes do not replay a scroll, and
native corrections preserve logical offsets through RTL viewport-size changes.
Mixed virtual-content composition now passes both axes and directions. The old
Scroll_view/Sliver public API, OCaml driver and wire paths, and generated node
declarations have been removed. Legacy Flutter source deletion remains part of
the overall repository cleanup.
See [native scroll containers](../../../swiftui-scroll.md).

Apple defines `.swipeActions` for rows in a list. Do not assume it implements
the generic current Slidable extension on arbitrary `ScrollView` children.
A custom SwiftUI swipe composition needs its own drag/scroll arbitration,
accessibility actions, group-closing state, and keyboard/context-menu access.
[Apple: swipeActions](https://developer.apple.com/documentation/swiftui/view/swipeactions(edge:allowsfullswipe:content:))

### Text input, navigation, animation, and presentation completion

[SwiftUI Toggle](../../../swiftui-toggle.md) records the unified Boolean control,
removed Material/Cupertino constructors and actual Gallery/native-control tests.
Other control families and physical-device interaction remain unfinished.

Preserve the meaning of revisioned editing: OCaml owns canonical documents;
native editing owns local echo, selection, and marked-text composition until
acknowledgment. Test UTF-16 boundaries, emoji, CJK marked text, selection,
stale corrections, submission, byte limits, and focus changes.

The native editing prototype establishes one additional value invariant:
a nonempty composing range must contain the complete selection, including a
caret at either boundary. Moving the selection outside marked text causes
NSTextView to end composition. Reject contradictory remote values in the
public constructor and both protocol directions instead of retaining a marked
range that the native control has already ended. Empty composing ranges still
normalize to no composition. This adjusts the editable UI value contract;
it does not change any protected ID definition.

Within one editing session, local revisions remain monotonic across forced
replacement. A new session resets that counter to its accepted revision.
Repeated remote snapshots and older document revisions cannot overwrite later
local typing. Ack advances the known document revision without replacing local
echo; Correction replaces it only at the matching local revision. Non-forced
acknowledgments of a future local revision are invalid.

Use narrowly scoped `UIViewRepresentable`/`NSViewRepresentable` text
adapters when SwiftUI's public text bindings do not expose enough IME state.
These integrate native Apple controls into the SwiftUI hierarchy; they do not
introduce another renderer or host application framework. The user authorized
these adapters; document and test each use. Apple supplies these protocols for
native control creation, updates, coordination, and teardown.
[Apple: UIViewRepresentable](https://developer.apple.com/documentation/swiftui/uiviewrepresentable),
[Apple: NSViewRepresentable](https://developer.apple.com/documentation/swiftui/nsviewrepresentable)

Unify composer editing with the text-session model where practical. Existing
composers retain a native-local draft; that fact must not silently become a
second canonical application document. Specify whether the new draft is
OCaml-controlled or explicitly ephemeral, and test retention across
presentation-style changes and dismissal.

The ordinary message composer keeps an explicitly ephemeral native draft. Reuse
NativeTextController/TextSession for UTF-16 selection, marked text, admission
rollback and the shared one-MiB UTF-8 limit. OCaml receives observations and exact
raw-text action events; those observations do not overwrite the draft. A stable
node retains draft/selection through configuration changes; key/epoch replacement
or disposal resets ownership. Sending does not implicitly clear the draft. Text-change detection must compare
UTF-8 bytes so canonically equivalent Unicode spellings remain distinct observations.

Install the standard kind-6/version-1 SwiftUI registration in each render tree;
reserve that kind against application replacement. Add typed child-count
validation to registrations and run it before publication, including when
properties can be reused. Composer action children are decorative native labels,
so their nested handlers must not dispatch independently. Use one editor surface,
logical leading/trailing actions, explicit enabled/visibility rules, adaptive
line height, a native collapse control and a dedicated drag handle. Keep editor
selection/scroll gestures outside that handle. Draft limits must be observable
when reached. The expandable composer will reuse this surface and controller;
its Sheet/presentation migration remains a separate acceptance gate.

The ordinary composer is now implemented through the standard registration and
is included in Gallery. Real OCaml/native tests cover raw actions, selection and
marked-text retention, decorative child isolation, disabled states, limits,
queue rollback, malformed frames and disposal. A separate App verifies native
autofocus, adaptive height, collapse and editor identity. The Unicode observation
regression now compares UTF-8 bytes. The expandable Sheet wrapper and physical
keyboard/touch/VoiceOver acceptance remain required. See
[composer evidence](../../../swiftui-composer.md).

The expandable composer uses the standard kind-7/version-2 registration and the
same ComposerController/editor surface as the ordinary composer. SwiftUI Sheet
owns presentation, native keyboard avoidance and system dismissal; the content
has no second card background. The launcher retains Compact/Extended styles and
maps its existing duration/curve to SwiftUI animation, including zero duration
and reduced motion. Sheet presentation itself uses the platform transition.

Keep local presentation leases separate from property generations. Configuration
and launcher-style changes retain a mounted Sheet/editor; closing fences input
immediately and keeps background input blocked until native dismissal finishes.
Reopening creates a new presentation lease while retaining draft/selection.
Disablement leaves the Sheet mounted and dismissible. Key replacement, removal,
epoch replacement and session closure dispose the resource and invalidate leases.
Native extension contexts expose a synchronous interaction-permission query for
local presentation actions, and modal resources participate in session-wide
input ownership. Decorative launcher/action children must not dispatch their own
handlers. Test actual open/close/reopen, native focus, raw events, stale bindings,
background input, configuration changes and all disposal paths.

The expanded composer now has its standard SwiftUI registration and Gallery
catalog. Actual OCaml/native Sheet tests pass draft/selection/marked-text
retention, raw actions, Compact configuration updates, stale presentation
bindings, modal background fencing, disablement, key replacement/removal and
session restart. An independent SwiftUI App passes native autofocus on first
open and reopen, Escape dismissal and five-/three-line height limits. The
ordinary and expanded composer focused regression passes eight tests. Physical
iOS keyboard avoidance, touch/drag dismissal, VoiceOver and full screenshots
remain required; see [composer evidence](../../../swiftui-composer.md).

SwiftUI navigation bindings report requested path/selection changes to OCaml.
Transient interactive-back progress stays native. Preserve stale-pop
filtering, route identity, cancellation, detail selection, and return-to-list
state. `NavigationSplitView` supports column-based navigation and collapses
for compact layouts; use that behavior for adaptive mail navigation.
[Apple: NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview)

[Native NavigationStack](../../../swiftui-navigation-stack.md) now implements
ordinary destination paths and complete remaining-path requests. The Navigation
example has a standalone macOS SwiftUI bundle and a separate App test that
activates the system Back control through the actual OCaml runtime. Stale
bindings, exact UTF-8 route identity, multi-page requests and declined requests
are covered. Root and destination content now accept typed Body values; the
actual Gallery page-bar scenario verifies native scrolling and system Back.
Modal integration, full standalone Gallery and physical gesture/cancellation
acceptance remain open.

[Native NavigationSplitView](../../../swiftui-navigation-split.md) now provides
controlled column visibility and compact-column preference with an observed
selection key. Both native two-column sidebar/detail and three-column
sidebar/content/detail structures are available. Missing Content preferences
are rejected in two-column mode; changing column structure clears pending
native state. Gallery exercises both public constructors through OCaml. A standalone
SwiftUI App test activates the system sidebar control and verifies hide/show
requests and retained selection after resize. Native binding retention and
concrete visibility mapping are covered. Physical compact navigation remains
unverified.

[Native sidebar composition](../../../swiftui-sidebar-composition.md) now replaces
NavigationRail and NavigationDrawer with grouped native Buttons, selected
semantics, bounded scrolling and independent action/trailing content. Shared OCaml
destination state supports embedded split and modal Sheet presentations. Legacy
constructors, renderer cases and component IDs 17/18 encoding/decoding are removed.
Legacy navigation bars now use native TabView pages with stable selection keys,
SF Symbols, badge text and accessibility labels. The standalone bar constructor,
destination descriptors, Material style switches and node 115 are removed; a
formerly valid wire frame is rejected as an unknown node kind. Material Tabs now
uses native segmented Picker; its Primary/Secondary variants and component 16 are
removed.

[Native TabView](../../../swiftui-tabs.md) now provides keyed application pages
with OCaml-controlled selection and bounded, typed page bodies. Tab items now
accept literal badge text and independent accessibility labels. Metadata changes
preserve page identity and fence unpresented input. Actual system tab controls
verify accessibility-label updates and restoration; badge appearance remains an
outstanding visual acceptance item. Gallery exercises
accepted and declined selections, counters retained across switches, keyed
reordering and hidden-page input fencing through the native runtime.

[Native toolbar composition](../../../swiftui-toolbar.md) now attaches keyed
core Buttons, Toggles, Menus and labels through nine semantic placements.
The system owns overflow; OCaml owns each command and its selected state.
Material.Toolbar, its icon enum and floating/docked/expansion property bag are
removed, and component 19 is rejected in encoding and decoding. The actual Gallery
fixture verifies retained commands, placement changes, disabling, removal and
stale input through the native runtime. Top/bottom AppBar now uses
[native page bars](../../../swiftui-app-bars.md): navigation titles, page toolbar
items and fixed bottom controls. NavigationStack root/destination arguments now
accept bounded Body.t values, including typed scroll viewports. Components 15/30
and the old top/bottom constructors are removed. The actual Gallery fixture
verifies covered-page command rejection and retained root state after returning.
Scrolling headers now use native lazy sections with pinned headers/footers and
an optional stretching hero. Sliver AppBar and PreferredSize nodes are removed.
Both axes pass actual-runtime macOS layout and input tests in LTR/RTL; physical
elastic overscroll and Reduce Motion appearance remain unverified. See
[native sections](../../../swiftui-scroll-sections.md). Search and physical
toolbar acceptance remain separate work.

[Mail navigation](../../../swiftui-mail-navigation.md) now composes all four tabs
and bounded split columns, with stale-selection filtering and mailbox/detail
state transitions. Its combined native extension shell, Scaffold/page wrappers,
custom tab bar and phone-width cap are removed. The [native morphing surface](../../../swiftui-morphing-surface.md) now replaces
Mail's old card extension, retaining both branches and fencing hidden input.
The full Mail tree stages with native swipe-action containers and morphing
surfaces; its standalone window test verifies inbox rendering, expansion and
Archive dispatch through OCaml. Native scroll/focus preservation, physical iOS
interaction and screenshots remain acceptance work.

Animation intent includes identity, target, timing, and completion policy.
Interpolation stays native, without per-animation-frame FFI. Reduced motion
and zero duration resolve to the target. Animations with an explicit completion
handler emit one completion; replacement or cancellation must not invoke the
old handler. Implicit collection and morphing-surface transitions have no
completion binding.

Replace Flutter's frame loop with an Apple foreground display driver and
scene/window visibility coordination. Preserve monotonic time, bounded event
queues, coalescing rules, the unresolved-token barrier, and suspended-scene
behavior. A renderer commit and actual screen presentation are distinct.
Neither SwiftUI `body` evaluation nor a blind `DispatchQueue.main.async` is
proof that a frame was presented.

Before selecting the final lifecycle contract, prototype a generation-bound
host commit acknowledgment after the view update/layout and a display
opportunity. Establish exactly what Bonsai presentation waits guarantee.
If public Apple APIs cannot preserve the existing guarantee, explicitly revise
that contract and its tests in the proposal; do not silently rename a store
assignment to `presentation_succeeded`. No later logical pump may release
handlers for the still-unresolved generation. Cover no-diff tokens, rejection,
background/resume, teardown, and interrupted animations in this spike.

### Protocol, native bridge, and host services

Keep bounded binary frame/event exchange and the reusable OCaml runtime.
Replace schema node/property definitions with the new view vocabulary and
generate Swift and OCaml artifacts plus cross-language fixtures. Remove Dart
generation and obsolete fixtures. Replace the generic expressive payload
switch with typed semantic control cases or typed extension schemas.

Use wire protocol `4.0` to identify the incompatible UI model. Rename
the public C symbols/header and bootstrap identities to the new project
namespace and publish native ABI `3.0`; remove the
old exports. This ABI change is due to the deliberate exported interface
change, not merely because the caller language changes. Keep renderer protocol
and native ABI checks independent and exact. Regenerate the SDK ABI manifests
and symbol audits consistently.

Extract the reusable C bridge from its current Flutter package location before
deleting that package. Swift imports its declarations through a Clang module,
copies native output into owned bytes, and frees every buffer on every result
path. Test pointer/length bounds, malformed/truncated bytes, integer ranges,
alignment-independent decoding, errors, use after dispose, and process restart.

Replace Dart adapters/plugins with Swift host services for bootstrap payloads,
Application Support paths, application bridge requests/events, clipboard,
URLs, haptics, focus, accessibility, locale/direction, safe-area/keyboard
environment, and lifecycle. Audit all existing host-effect variants rather
than only those Mail uses. Keep SQLite/network/Eio business services in OCaml.

The current implementation stages typed clipboard/platform-information/URL requests and cancellation
atomically with the view, executes them after presentation acknowledgment while
active, and returns bounded control events to OCaml. Native pasteboard tests
cover delayed replies across presentation, saturation, cancellation and restart.
Host Effects now has a standalone SwiftUI macOS bundle and native window tests;
its Flutter host/configuration are deleted. Its Swift entrypoint also typechecks
against the physical iOS 18 module. The example bounds Unicode read previews so
a maximum-sized valid response cannot overflow a rendered text property. The
platform-information action returns actual Foundation OS/version/locale values
through OCaml with presentation, cancellation and restart tests. Other host requests
and physical-device acceptance remain unfinished. See [host services](../../../swiftui-host-services.md).

The [application bridge](../../../application-platform.md) now uses an
application-owned `BonsaiApplicationBridge` and a runtime-scoped event sender.
Opaque requests stage atomically and run after presentation; bounded responses
and ordered events reach the actual OCaml runtime. Application replies use
individual pumps so local cancellation or duplicate replies cannot discard
neighboring UI input or valid responses. Tests cover all wire error codes,
1 MiB boundaries, Unicode error limits, borrowed-buffer ownership, inactive
queues, 1024-event backpressure, 256-task admission, closure and restart fencing.
Host Effects reads its actual native bundle identifier through this bridge and
receives time-zone notifications through its own byte codec. Its real macOS
window passes both actions together with the existing native services. Physical
iOS execution remains outstanding.

Window title and size requests now bind to the calling session's actual native
window through its presentation probe. They share presentation, cancellation
and shutdown fences and never look up a global key window. Imperative titles
survive unchanged declarative titles; a new declarative title supersedes them.
Detach/reset conditionally restores the original title and old probes cannot
detach replacement owners. Stale probes also cannot acknowledge replacement
presentation tickets or publish visibility after losing window ownership; the
two-probe regression reproduces and verifies both boundaries. macOS changes
content size in points; iOS changes
the scene title but returns an explicit failure for width/height resizing,
which the selected iOS geometry API does not support. Actual NSWindow tests and
the standalone OCaml Host Effects window verify these behaviors on macOS.
Physical-iOS behavior and screenshots remain unverified. See
[window services](../../../swiftui-window-services.md).

Add platform-information requests to the native host service and Host Effects
example. Each request reads the native operating-system identifier (`macos` or
`ios`), `ProcessInfo.operatingSystemVersionString` and the current Foundation
locale identifier. Encode the existing three-string response, preserving its
typed OCaml decoder. Read values when the acknowledged request executes rather
than caching them at session startup. Reuse presentation/activation gating,
cancellation, response bounds and restart fencing; this request must not mutate
the clipboard or change system preferences. Validate actual native values
through the real OCaml example and its independent SwiftUI window.

[Native URL opening](../../../swiftui-url-service.md) now uses NSWorkspace on
macOS and UIApplication on iOS. Actual macOS receiver Apps observe URL delivery,
with native errors and cancellation/lifetime fences tested. The Host Effects
window edits a native URL field, executes its OCaml action, defers dispatch while
inactive and suppresses a request after closure. Physical-iOS URL execution and
foreground activation acceptance remain outstanding.

Host Navigation now uses the same native clipboard service and an OCaml-owned
NavigationStack path. Settings' former inline Material alert is a native text,
divider and column composition; the old example had no modal presentation or
dismissal state. Its native window scenario exercises Settings, Close and system
Back at 640- and 360-point widths. A real-runtime regression exposed input from
covered pages and speculative-pop content; the shared session now requires the
top page to agree with both the presented tree and native path. Delayed clipboard
completion retains the home model without changing navigation. This does not
complete the separate modal presentation or application bridge requirements.

Single selection now has a core View.Picker API with Automatic, Menu, Segmented
and Inline styles, signed option IDs, initial empty selection and disabled
choices. The old Radio_group constructor and wire names are removed; Gallery's
single segmented examples also use Picker. macOS reference programs reproduced
ignored per-option disabled modifiers in SwiftUI Picker. Small AppKit adapters
therefore supply native menu, segmented and radio controls within the SwiftUI
tree. Real Gallery integration covers request rejection, final intent across
presentation, stable labels on reorder and disposal. A real SwiftUI App window
verifies native radio/segmented accepted and rejected choices at 640- and
360-point widths. Swift test success now requires a completed xUnit report,
preventing premature status-zero exits from passing the gate. Physical iOS
disabled-item behavior and complete visual acceptance remain open.
See [Picker](../../../swiftui-picker.md).

Multiple selection uses keyed native Toggle groups with a shared OCaml set.
Button and Checkbox presentations accept arbitrary composed labels, and each
choice handler applies a Boolean membership request to current state. The old
Segmented_button API, dedicated node 125 and codec are deleted. Actual Gallery
integration covers independent choices queued together and across presentation,
rejection, disabling, stable keyed reordering and clearing. A real App scenario
checks both presentations at 640 and 360 points. See
[multiple selection](../../../swiftui-multiple-selection.md).

The Chip family now uses native Buttons for actions, Button-style Toggles for
selection and sibling Buttons for optional tag removal. Dedicated nodes
119–122, their property codecs and Delete event 34 are removed. Gallery's actual
OCaml/native-control tests verify rejection, independent deletion, stable
reordering, restored identities and disabled input. The native App scenario
passes at 640 and 360 points. Keyed tag rows now use `View.flow`; native frame
checks verify shared rows in a wide window and wrapping when narrowed. The
custom SwiftUI Layout also verifies exact width boundaries, RTL, directional
alignment, multiline text and oversized items. See [flow](../../../swiftui-flow.md)
and [tags](../../../swiftui-tags.md).


Core Buttons now inherit five native sizes through `View.control_size`, with
nested scopes and stable identities. Cupertino buttons and the dedicated
Material icon-button constructor, private nodes and wire kinds are removed.
Gallery uses composed core labels, including an accessible icon-only action.
Native macOS measurements match equivalent SwiftUI Buttons; actual App tests
exercise styles, actions and disabling at both widths. The Material button and floating-action APIs are now removed. Native Button
autofocus and keyboard/focus acceptance are still required. See
[control size](../../../swiftui-control-size.md).

`View.projection_effect` now applies a native 3×3 plane projection. The old
Transform module/constructor and sixteen-value wire payload are removed. Native
raster comparisons verify affine/perspective drawing, layout extent and modifier
order; actual Gallery integration and App accessibility actions retain the
same control through projection changes at both widths. Projected-coordinate
pointer acceptance remains outstanding. See [projection](../../../swiftui-projection.md).

Animated opacity now uses local SwiftUI animation and a generation-fenced
completion event. The current properties/binding must be presented and active
before an intent starts or completion is admitted. Initial mount, interruption,
repeated targets, zero duration, removal/remount, queue saturation and hidden
session restoration have native tests, including a disabled Toggle label.
Mid-animation Reduce Motion, rapid reactivation and immediate replacement now
pass a companion native interpolation regression; cancellation uses an
invalidating coordinate and a zero-duration SwiftUI animation. Actual
framebuffer settling, physical iOS and OS accessibility signals still require
acceptance. See
[animated opacity](../../../swiftui-animated-opacity.md).

`Workflow` now replaces the old Stepper workflow with native Button headers,
state markers, wrapped or vertical layout and retained bodies. Real OCaml and
native App tests cover next/back, selection, disabled and hidden controls,
accessibility state, reordering and both widths. Legacy node 132 and its three
specialized events are removed. Full visual and device acceptance remain
outstanding. See [workflows](../../../swiftui-workflow.md).

`View.disclosure_group` now replaces the expansion-panel and expandable-list
families. SwiftUI owns the native disclosure presentation; OCaml owns individual
Boolean states and shared single/multiple expansion policy. Native tests cover
rejection, hidden/disabled input, presentation fences, editor retention and
reordering. The old panel payload and dedicated event are removed. Full visual
and physical-device acceptance remain outstanding. See
[disclosure groups](../../../swiftui-disclosure.md).

### Native focus and layout services

Node host services resolve identities against the calling session's current
presented tree and active content, never a global window or another session.
Focus requests target mounted native text inputs; disabled, detached, removed
or non-focusable nodes fail explicitly. Clearing focus affects only the owned
window and reports native refusal. Layout measurement uses SwiftUI geometry in
logical points relative to the application content origin, independent of the
window's screen position. Geometry is attached to the mounted view lifetime;
stale or absent measurements fail instead of returning cached layout for a
removed view. Preserve the existing four-Float64 response shape. Validate actual
OCaml requests against native controls and SwiftUI layout on both platforms.
The separate scroll request represents a normalized container offset, not a
child-item identifier, and still requires integration with native scroll state.

### Native file selection and export

Replace the contradictory single-file result of `Host_effect.pick_file` with
`Host_effect.pick_files`, returning a list. The existing multiple-selection
option must retain every selected file; cancellation returns an empty list.
Request kind 4 is named `pick_files` and its response is a UInt32 file count
followed by the existing path/data file records. Remove the old entrypoint and
optional-single-file response decoder from this request; do not add an alias or
legacy-response branch. `save_file` retains its optional single-file result.
These public runtime/protocol interfaces are outside the protected spec tree.

Use SwiftUI file import/export presentation with explicit completion and
cancellation callbacks. Imported external resources need scoped native access
and application-readable copies before the response can be delivered. Import
all selected files atomically, preserve selection order and duplicate basenames
from different directories, and clean up failed/cancelled work. Returned copies
belong to the runtime session and are deleted when it closes; applications must
persist files they need beyond that lifetime. Window detachment cancels pending
dialogs but does not invalidate already returned copies. Preflight the encoded
path-list response limit before copying; file contents are not constrained by
that response limit. Export uses the application-owned bytes
and a native destination chooser; a cancelled request must not delete a user's
existing destination. Tests must distinguish native presentation/cancellation,
actual file I/O and protocol round trips from real chooser selection, which
remains a separate interaction gate when the desktop or device is unavailable.

### Build, packaging, deletion, and other examples

Proposed destinations are `swift/BonsaiSwiftUI/` for the Swift package,
`native/` for the C boundary, `bonsai_swiftui_tool/` for the CLI, and
`examples/<name>/apple/` for generated or application-owned Apple hosts. These
Swift and native paths now exist. Xcode host generation now builds the ten
examples with existing Swift App entrypoints on macOS and produces signed
physical-iOS Release bundles. The native CLI now initializes external applications
and builds/runs their SwiftUI hosts; installed-SDK publication and physical-device
execution remain unfinished. Generated hosts provide actual application targets, resource phases, plists,
entitlements and signing settings; Mail also has native XCTest targets. See
[Xcode hosts](../../../swiftui-xcode-host.md) for measured evidence and remaining
physical-device requirements.

Native prerequisite discovery now recognizes Swift package and C bridge assets
instead of a Flutter pubspec. The explicit source override is
`BONSAI_SWIFTUI_SOURCE_ROOT`; the old override is removed. `doctor` runs without
a project configuration and checks Python 3.9+, opam, Dune, Xcode, the selected macOS or
physical iOS SDK, and its Swift compiler, without invoking Flutter. Installation
stages `Package.swift`, `swift/` and `native/` instead of Flutter packages.
The executable is now `bonsai-swiftui`, with schema-3 `bonsai-swiftui.sexp`
configuration, application-owned Swift/OCaml sources and generated native Xcode
hosts. Dart adapters, pub-get, Flutter command forwarding and profile injection
are removed from its build/run/exec pipeline. Library/package identifiers and
the installed SDK release still require replacement; this does not establish
finished SwiftUI packaging. See the [native CLI](../../../swiftui-cli.md).

The native builder now targets the configured complete object directly and
encodes its Dune target argument as an S-expression atom. Platform alias
generation/repair, embedding gates in generated native stanzas, repository
managed alias blocks and the `sync-project` command are removed. Debug maps to
Dune `dev`, while Profile/Release map to `release` with separate artifact
directories. Actual Dune and Counter-object staging regressions cover spaces,
profile selection, incremental source changes and unchanged application Dune
files. The new CLI also builds an independent generated application in all three
Xcode configurations, launches its native window and verifies a real OCaml state
change. A signed iOS 18 Mail App builds through the same CLI using its verified
cross-compiled complete object. Physical-iOS execution remains unverified. See
[direct native builds](../../../swiftui-cli-native-build.md) and the
[native CLI](../../../swiftui-cli.md).

The ten existing Swift App examples now also own native CLI configurations.
Independent source copies pass actual native builds without source modification;
Mail additionally builds and executes its packaged OCaml XCTest through the CLI.
Apple system-library search flags are carried by the native backend's installed
OCaml archive metadata, so consumers no longer include a generated file from
the framework source tree. Gallery and public package naming remain unfinished.

The pipeline becomes OCaml/Dune complete object -> target-specific native
library/artifact -> Swift package and Xcode app -> install/run/test. Generate
deterministic host files without application reducers. Replace `pub get`,
Native Assets hooks, Flutter profile injection, hot-restart assumptions,
icon-font retention, and Flutter-specific cache fingerprints. Preserve useful
Debug/Profile/Release build intents through explicit OCaml and Xcode settings.

The worktree-local OCaml 5.1.1 compiler and core native runtime have now been
rebuilt for iOS 18 arm64. Tests inspect actual compiler flags, foreign-stub and
complete-object Mach-O metadata, and an installed runtime allocation object.
The previously installed global iOS 15 toolchain fails these checks and remains
untouched. See [physical iOS toolchain](../../../swiftui-ios-toolchain.md).

The isolated host dependency installation and checksum-verified target source
staging are complete. The runtime lock excludes the obsolete framework host
package. Artifact audit regression tests now reject wrong-platform or old-minimum
objects inside static libraries and missing declared native artifacts; valid
iOS 18 libraries pass. All 105 target build items subsequently completed, and
the full installation audit passes for 146 components, 166 static archives and
1,129 Mach-O objects. This required fixing concrete native module staging for
virtual libraries and distinguishing interface-only libraries in the audit.
The actual framework and Mail complete object now cross-build and pass IOS,
arm64, minimum 18.0 and SwiftUI ABI validation. The actual SwiftUI Mail iOS Release
App also links and builds with automatic development signing; its bundle passes
deep/strict signature verification and includes a valid provisioning profile.
Installation and runtime acceptance remain separate gates: the paired physical
iPhone is unavailable, and no physical-device screenshot is claimed.

All ten currently available standalone Swift App examples now cross-build their
actual OCaml complete objects and link into signed iOS 18 arm64 Release Apps.
Their final plists, executable platform/minimum, provisioning presence and
deep/strict signatures pass validation. Existing macOS Debug bundles also pass
fresh metadata/signature checks. Gallery is still unfinished, and no device
runtime or screenshot acceptance is inferred from these builds. See
[example build evidence](../../../swiftui-example-builds.md) for the exact scope,
artifact manifest and remaining configurations.

Build and audit the iOS OCaml/compiler/dependency closure against `iphoneos`
with the selected iOS 18.0 deployment target. Do not add an `iphonesimulator`
toolchain, artifact, application destination, or test lane. Reject Simulator
targets explicitly. Keep iPhoneOS and macOS target cache keys and SDK artifacts
distinct.

Keep the immutable runtime SDK / replaceable framework SDK split. Rename
active package metadata and regenerate it from the exact pushed framework
source revision. When implementation code is committed and pushed, update,
verify, commit, and push the generated iOS SDK update separately, following
the repository rule. This document-only change does not commit or push anything.

Remove active Flutter/Dart packages and host trees, pubspec/lock files,
`material_ui`/Slidable dependencies, Dart protocol/binding generation, Flutter
integration harnesses, Flutter commands, obsolete platform targets, assets,
and live documentation. Port valuable tests before deleting their harnesses.
Historical decision records can remain explicitly historical; they must not
act as active Flutter build instructions. Remove ignored generated build
artifacts through scoped cleanup, without altering unrelated user files.

Mail and Gallery are mandatory: Mail is the behavioral proof and Gallery
demonstrates every replacement control, including controls absent from Mail.
Port all eleven existing consumers: clock, counter, gallery,
host_effects, host_navigation, mail, navigation, network, sqlite_worker,
text_input, and todo. The user selected retaining every consumer as a
standalone SwiftUI application. Remove all Flutter hosts and leave no broken
example, manifest, or test target; do not retire the other nine applications
in favor of integration-only scenarios.

### Mixed collection ownership

Use one keyed heterogeneous application catalog for a scroll surface that mixes
ordinary content, fixed-size rows and varied-size rows. A header, separator or
footer is an ordinary keyed catalog item with an explicit extent; padding is
ordinary content within that extent. The application owns flattening its domain
groups into this ordered sequence and maps the one global visible range back to
its records. Keep one native viewport and one stable-key anchor instead of
reintroducing independently scrolling Sliver children or implicit competing
initial anchors. A catalog has one declared sparse-animation timing policy.
Use native Scroll_sections separately when pinned headers are required; this
does not claim that a virtual catalog supports pinned headers.

Before retiring the remaining Sliver surface, verify a real OCaml scene with
10,000 fixed/varied rows, header/interlude/footer content, distant jumps, bounded
materialization, offscreen extent changes, header resizing/removal and group
reordering on both axes and in both layout directions. The catalog must be
reused on window-only changes. Keep actual Collection identity/window protocol
coverage when replacing old Sliver-specific tests; remove cache/primary/reverse
and sparse-transition bags rather than introducing compatibility constructors.

The real `Mixed_collection_catalog` scene now exercises this composition in
Gallery and the native runtime fixture. Both axes and layout directions pass
the mixed-content checks, including interlude crossings, footer actions and
clear/reset. A separate SwiftUI App reproduces and verifies the RTL empty-to-full
regression through native accessibility actions. Its ScrollView document now
has a viewport-sized minimum, preserving valid leading coordinates while empty;
catalog extents and per-item placement remain unchanged. See
[mixed collection evidence](../../../swiftui-collections.md#mixed-content-in-one-catalog).
The Sliver/Scroll_view API retirement is now implemented for the OCaml/SwiftUI
path: public and private constructors, old sparse-transition records, driver
mappings, wire models/codecs and schema declarations for nodes 30, 32, 33, 35,
36 and 37 are removed. OCaml rejects these IDs as Unknown_node_kind; Swift
rejects them as unsupported nodes. Keyed overlap, canonical keyed roots, window
clamping and range callback checks use Collection, and eager body tests use
Scroll. The primary-scroll fixture is deleted; the bounded-body fixture uses
catalog/window nodes. No compatibility constructor or decoder is added.
The legacy Flutter source trees have since been removed. Adaptive Mail now uses
measured rows, passes native macOS column-width and expansion checks, and has
physical iPhone coverage for Dynamic Type growth and shrinkage. Physical gesture,
IME and host-service acceptance remain incomplete.

### Application SwiftUI view registration

Provide a startup-only typed SwiftUI registry for the existing application
extension envelope (node 128, event 21). A registration identifies one kind and
one exact schema version, declares its supported capability bits, decodes opaque
properties into a Swift type and encodes a Swift event type into a bounded event
ID/payload. It supplies a SwiftUI content factory and optional per-node resource
creation/disposal. Copy the completed registry into the application session;
there is no mutable global registry, version fallback or Dart factory.

Decode every changed extension before publishing the candidate frame. Unknown
kinds, wrong versions, unsupported capabilities and decoding failures reject the
frame atomically. Do not allocate resources during validation. Compatible
property/child updates retain the resource and SwiftUI identity; kind replacement,
epoch replacement, removal and session closure dispose it exactly once.
Registry resource construction is synchronous and nonthrowing; fallible domain
work belongs inside the application's resource and typed view state.

Context events name the current native instance and property/binding/child
generation. Require a mounted, active, presented view and route every accepted
event through the OCaml queue. Invalidate retained callbacks across metadata
changes, hiding/unmounting and disposal. Bound opaque payloads by the transport
frame limit and preserve explicit queue-admission failure. Supply keyed native
child views with mount tracking so children omitted by the factory cannot keep
accepting stale input. Test the actual OCaml Gallery extension, native child
actions, typed events, retained local state/resources, rejected frames and all
shutdown paths before claiming this capability implemented.

The typed startup registry is now implemented as `BonsaiNativeViews`, passed into
`BonsaiApplicationView` and copied into its session. It validates node 128,
prepares typed properties before publication, owns per-instance resources and
encodes event 21 through the OCaml queue. Native child mount tracking fences
omitted content. The real Gallery card shares its OCaml definition with
`Native_view_catalog`; its test scene exercises property, handler, child, kind
and visibility changes. A separate SwiftUI App verifies native button and child
actions, retained SwiftUI state and resource disposal. The nine-instance nested
scene exposed dictionary-order presentation gating; parent-first traversal now
enables every instance in one acknowledgment. This does not implement the
remaining composer built-ins or establish standalone Gallery completion. See
[application view registration](../../../custom-widgets.md).

### Table ownership

Material.Data_table is replaced with a native Table boundary. The native API
experiment verifies dynamic mixed sortable/non-sortable columns, canonical row
ordering, selection-disabled rows with interactive cells, and column mutation
against the installed Apple SDK.
The independent native diagnostic is not a Bonsai integration test and cannot
establish that DataTable has been migrated.

The Xcode 26.1.1 SwiftUI interface exposes Text column-header initializers rather
than arbitrary View header initializers. The new public column API therefore
needs explicit native header text; header help and richer content need an
explicit composition with equivalent discoverability, not silently ignored
legacy fields. Cell content remains arbitrary Bonsai views. Prefer ordinary
Button actions for cell activation and an application-owned select-all Toolbar
command over table-specific action flags and events. Use one canonical selected
row ID set instead of independent per-row and table-level selected state.

The platform contract remains native Table on macOS and regular-width iOS, with
an explicit compact-iOS row/detail presentation that exposes every column.
Neither a first-column-only compact presentation nor a Swift-owned business sort
satisfies the migration. The OCaml application owns order, selection policy and
accepted/rejected changes; native interactions submit intents.

[The native Table investigation](../../../swiftui-table.md) now verifies mixed
dynamic columns through a typed builder with mutually exclusive optional
columns; the ordinary mixed-comparator `if/else` does not compile. The macOS
probe also verifies native selection eligibility without disabling cell actions,
selection by stable row ID across reorder, canonical row order under sort
intents, rejected binding restoration, and column insertion/removal/reorder
without recreating the table. The same view typechecks for physical iOS 18.
These results resolve native API feasibility, not the OCaml protocol, asynchronous
event lifecycle, compact layout, gesture or accessibility acceptance gates.

Implement `View.Table` as a finite `Body.t`, with explicit column ID/title,
optional help and arbitrary details content, numeric alignment and sortability.
Rows carry a stable ID, selection eligibility and ordinary cell Views. Preserve
rich header content in a discoverable Column details disclosure above the native
Table; show every named cell and explicit selection/sort commands in compact
width. Placeholder styling and edit affordances use ordinary cell compositions.
The wire node is Table (79), replacing Material_data_table (131), with native
column/row metadata and keyed child content. Keep semantic sort and row-membership
intents; retire table-specific select-all and cell-activation events in favor of
application-owned commands. Do not retain a decoder or constructor for node 131.

The implementation now supplies this public API, node 79 and the real-runtime
Gallery scene. Native and forced-compact macOS tests pass selection, sort intents,
rejected changes, independent cell actions, row/column mutation and rich details.
The runtime test also covers pending queue admission, stale/hidden/disposed input
and the details expansion gate. Delayed native cell builders retain the matching
child snapshot to avoid indexing newer row arrays after removal. Physical iOS,
keyboard/header gestures and VoiceOver acceptance remain open; the migration as a
whole is still proposed and in progress.

### Search composition ownership

See [native search](../../../swiftui-search.md) for the implemented composition,
retired protocol and three actual native-window scenarios. Physical iOS and
visual acceptance remain open.

Replace Material.search_bar, Search_anchor and App_bar.search with composed native
View.text_field, keyed suggestion Buttons and explicit application-owned search
presentation. Use an inline field/results region, an anchored Popover, or
Sheet.full_screen (fullScreenCover on iOS and a sheet on macOS). Navigation-page
search commands and other actions use View.Toolbar. Leading/trailing content
uses ordinary row/label composition; native window/navigation layout replaces
Material centering and slot-count flags.

Keep revisioned text, UTF-16 selection and composing ranges, keyboard/submit
configuration, read-only/enabled state, autofocus and UTF-8 limits through the
existing text-field adapter. OCaml owns query filtering, enabled suggestions,
selection effects and idempotent open/close transitions. Suggestion handlers
validate against current visible enabled results, so a queued edit can invalidate
a later queued choice. Presentation dismissal is a Boolean request and can be
rejected by the application; explicit close commands use the same state policy.
Do not add search-specific native events or a separate editing protocol.

After the search consumers move, remove node 129 and the now-unproduced generic
Material expressive node 136, their property bags/codecs and Search_opened/closed
events 48/49. All former expressive component IDs then fail at the node-kind
boundary; do not keep a per-component compatibility decoder. The required
replacement runtime/native-window tests precede this deletion.

### Contextual selection ownership

See [contextual selection](../../../swiftui-contextual-selection.md) for the
implemented composition and real-runtime/native-window verification boundaries.
Physical iOS, keyboard/VoiceOver and visual acceptance remain open.

Replace Material.Selection and Selection.leading with keyed native Toggle labels
and a contextual View.Toolbar inside the application's navigation page. OCaml
owns the selected ID set and applies each Boolean membership request to its
current state. The application derives its idle title, selected count, select-all,
clear and batch actions from that set. Full-set and batch commands operate on
current eligible IDs, including after item removal or reordering; no native
index mapping or captured selected-ID snapshot owns canonical state.

Use composed SF Symbol/text labels for unselected and selected affordances.
Material flip visuals and the implicit PopScope selection-clear interceptor are
removed. Applications choose navigation behavior explicitly through their
Navigation_stack path handler and expose a clear-selection command. Disabled,
rejected, hidden and stale inputs retain the existing Toggle/Toolbar lifecycle.
Remove components 9/29, their OCaml API, Dart host/controller and obsolete tests
once real runtime selection and contextual command scenarios pass. Remove the
now-unused event 35 and Int64_list input payload across the OCaml boundary. No new
wire node, event or compatibility wrapper is needed.

### Per-item removal ownership

See [native per-item removal](../../../swiftui-removal.md) for the implemented
API, request lifecycle and tested boundaries. Native mouse and collapse tests
pass; physical touch/trackpad and visual acceptance remain open.

Replace Material.Dismissible_list with `View.Removal.create` around each keyed
item. The application chooses its surrounding ordinary or virtual layout.
Each item owns a request token and Ready/Pending/Accepted/Rejected state; requests
report the token and logical swipe direction, so a keyed application handler can
identify its item without a list-owned index or global pending future. Rejected
requests restore the retained content. Accepted requests animate the item away,
then emit the token through `on_removed`, allowing OCaml to remove it from the
data source after native completion. Token replacement invalidates older requests
and animation completions. Drag axis and collapse axis are independent so the
same item works in a vertical list or a horizontal shelf. Native Reduce Motion,
scene activity, typed input admission and stable identity remain required.

Reuse the existing platform pan recognizer through a small gesture-target
protocol; do not duplicate UIKit/AppKit event recognition. Keep native context
and accessibility removal commands, both horizontal directions with RTL, and
both vertical directions. Remove the old components 10/11, OCaml constructors,
Dart hosts and tests once the replacement integration tests pass.

### Refresh request ownership

See [native refresh](../../../swiftui-refresh.md) for the current API and
request lifecycle. Native tests pass; physical pull acceptance remains open.

Replace Material.Refresh_indicator with `View.Refresh.vertical`, a typed
vertical viewport modifier. It wraps one native Scroll, Scroll_sections,
Collection or Scroll_targets without replacing that viewport. Native rendering
uses SwiftUI's async refresh action, a labeled refresh button and progress
indicator, and leading pull/release geometry on the owned vertical ScrollView.
Nested scroll content cannot trigger the outer refresh owner. Material style
variants are removed rather than mapped to arbitrary native appearances.

OCaml supplies a request token, Ready/Pending/Completed state, an optional
programmatic show token and the request handler. A native action emits the
request token once and awaits matching completion or token replacement. Pending
acknowledgment does not finish the async action. Repeated activation coalesces;
a new request requires a new token. Programmatic show changes use the same path.
Hidden/inactive/removed owners and canceled Swift tasks release native waiters;
stale callbacks and completions cannot affect replacement requests. Source and
window tests cover request admission, acknowledgment, completion, replacement,
programmatic activation, native viewport identity and teardown. Physical pull
interaction and visual acceptance remain separate device gates.

### Mail port and screenshot delivery

Preserve the local fictional data and the OCaml business behavior:

- Twenty deterministic initial messages; subsequent 20-message pages after
  the existing local 750 ms delay, with deduplicated requests and stable keys.
- Inbox, Starred, Archived, Trash, and the Settings placeholder; Mail, Chat,
  Spaces, and Meet destinations with the existing explicit placeholders.
- Read/unread, star/unstar, archive/trash, attachment detail, and reply notices.
- Single-open two-level inline preview; expanding does not mark a message
  read. Open marks it read and opens detail. Reply, star, open, and collapse
  remain independently operable.
- Return from detail preserves expansion and scroll position; mailbox or tab
  changes preserve the corresponding application state.
- Paging and row expansion remain responsive while gestures and animations
  run locally, including rapid activation and reduced motion.

On iPhone use compact native navigation, toolbar actions, and tab destinations.
On macOS use a resizable sidebar/list/detail composition with keyboard and
context-menu access to the same actions; iPad can use regular-width columns.
Replace Material icons and fixed phone-width framing with SF Symbols,
semantic typography, native surfaces, and adaptive sizing. Do not expand scope
to real email, accounts, search, compose, or persistence merely because a
native control makes those features easy to draw. Preserve the current search
placeholder semantics clearly.

Screenshots must come from the running SwiftUI app linked to the real OCaml
runtime. Do not substitute mockups, SwiftUI Preview fixtures, Flutter captures,
or a Swift-only mail replica. Capture at least these states:

| Platform | Required captures |
| --- | --- |
| iOS | Initial inbox; expanded inline preview; available swipe actions; message detail with attachment. |
| macOS | Sidebar/inbox/detail layout at a documented window size; expanded preview; non-Inbox mailbox after an action. |

Save PNGs under `docs/screenshots/swiftui-mail/` with a README recording source
revision, Xcode/runtime version, physical device model, window/viewport
size, display scale, appearance, fixture state, and reproduction steps.
Include image links in the implementation completion report. Use XCUITest
attachments from a physical device or direct device screenshots for iOS,
and a real application-window capture
for macOS; inspect the images for clipping, missing icons, overlap, and wrong
state. PNGs and their manifest are created during implementation, not here.

iOS execution tests and screenshots require an available physical device
running iOS 18 or later and a working development signing path. Verify those
prerequisites before the device gate; no such availability has been established
by this exploration. An unsigned build is useful packaging evidence but does
not satisfy execution or screenshot acceptance. If the device gate is blocked,
report the missing prerequisite and leave those deliverables incomplete; do
not add Simulator support as a substitute.

The extended macOS Mail window scenario verifies all five mailbox buttons, the
detail placeholder and native Archived/Inbox selection after archiving a
message. Updated diagnostic exports record Aqua appearance, 2x scale and a
1200 by 760 point content size, and add the Archived state. Sidebar/native
background pixels remain incomplete in NSView cache exports. Native control
existence and action success do not replace the complete-window capture gate.

### Implementation sequence

1. Record the resolved user decisions and transition this document to proposed
   through `spec-dev-tool` before implementation. The platform, adapter,
   example, and Dune authorization decisions below govern every stage.
2. Prove a minimal OCaml -> C -> SwiftUI counter on macOS and a physical iOS
   device, including interaction, shutdown/restart, clocks, and
   generation acknowledgment. Resolve lifecycle, IME, and bounded-list spikes
   before expanding the renderer.
3. Introduce the new public view model, protocol/ABI, Swift node store, event
   bridge, host services, and build pipeline. Replace generated artifacts and
   add meaningful OCaml/Swift cross-language tests.
4. Complete every widget family in the inventory and its Gallery scenario.
   Verify keyboard/accessibility behavior and platform-specific compositions.
5. Port Mail end to end and migrate all remaining standalone examples.
   Rewrite structural Flutter assertions around the new
   contracts while preserving application behavior regressions.
6. Delete obsolete Flutter surfaces, run the complete relevant gates, launch
   Mail on both platforms, capture and inspect the required images, and update
   live documentation. After code commit/push, perform the separate generated
   SDK commit/push required by the repository.

Stages describe a single replacement. They do not introduce a supported
dual-backend release or compatibility layer.

## Decision

Adopt this proposal with the following explicit user decisions:

- Target physical iOS/iPadOS 18.0+ arm64 and macOS 26.0+ arm64. Do not support
  Simulator or add a simulator toolchain, destination, or validation lane.
- Permit narrowly scoped `UIViewRepresentable`/`NSViewRepresentable` adapters
  for demonstrated SwiftUI API gaps, including revisioned text/IME handling.
  Document and test each adapter while keeping application composition in
  SwiftUI and removing Flutter completely.
- Port all eleven examples as standalone SwiftUI applications. Mail behavior
  and real-device/macOS runtime screenshots remain required deliverables;
  Gallery supplies coverage for every replacement widget capability.
- Authorize modification of the root, library, generator, tool, test, and
  affected consumer `dune`/`dune-project` files needed to replace package names,
  native aliases, generated outputs, and build targets for this migration.

On September 14, the user explicitly authorized the three-line protected-source
patch: change two comments in `ocaml/spec/id.mli` from Flutter to native/SwiftUI
terminology, and change `ocaml/spec/test/id_contract_tests.ml` to reference
`Bonsai_swiftui_spec.Id`. No type or behavior change is authorized by this patch.
Other protected `ocaml/spec/*.mli` definitions remain unchanged. If such a
definition blocks development, stop and report the
exact issue, proposed change, and rationale before requesting specific
authorization. The list, IME, and presentation prototypes are implementation
verification work; they are not unanswered product-scope questions. A finding
that requires a material contract change must be recorded explicitly.

## Alternatives considered

### Add SwiftUI while retaining Flutter

This would preserve portability but double rendering and testing surfaces. It
conflicts with the requested removal and is not selected.

### Translate the existing Flutter widget protocol literally

This would initially reduce OCaml changes but retain Sliver constraints,
Material tokens, Scaffold slots, and Flutter gesture contracts indefinitely.
It is not selected; functional capabilities are preserved through native
semantics and explicit compositions instead.

### Rewrite Mail directly in Swift

This can produce screenshots quickly but would not demonstrate that the
framework has a functioning SwiftUI backend. It loses the OCaml/Bonsai
ownership boundary and is not selected.

### Replace the entire runtime with Swift state management

The renderer change does not require discarding Bonsai computation, typed
handlers, reconciliation, headless tests, Eio workers, or binary boundary
validation. Replacing those would be a different project and is not selected.

### Restrict implementation to stock SwiftUI controls

Stock controls do not by themselves reproduce every existing semantic
capability, such as arbitrary-child swipe actions or revisioned IME sessions.
Use SwiftUI compositions and the authorized small native-control adapters.
Do not silently drop the difficult capabilities to keep the implementation
stock-only.

`View.Menu` now replaces the Material Menu, SplitButton and FAB menu APIs with
hierarchical SwiftUI menus and primary-action-plus-menu composition. Menu choices
remain controlled by OCaml; native action and rejection scenarios run in a
standalone SwiftUI App. On macOS, disabled submenu containers may remain
expandable while their descendants are disabled. Physical interaction, complete
visual acceptance and maximum-size performance remain outstanding. See
[native menus](../../../swiftui-menu.md).

The date/time implementation now uses independent native nodes and public
`View.Date_picker` / `View.Time_picker` constructors. Linked date fields preserve
the proleptic Gregorian domain, and the native time DatePicker uses UTC clock
fields with system or explicit hour cycles. Gallery covers controlled selection,
rejection, restricted dates and handler replacement; macOS native actions reach
the actual OCaml model. Physical iOS interaction, visual acceptance and large-year
menu performance remain outstanding. See [civil date and time selection](../../../swiftui-civil-selection.md).

ButtonGroup and DropdownMenu now compose core Picker, keyed Toggle groups,
Menu, Flow/Scroll layouts and native text input. Their Material constructors and
old Dart rendering branches are removed. Search and ready/loading/empty/error
presentation preserve canonical OCaml selections. Material connected/shape/style
knobs are replaced by native styles and ordinary composition. The actual Gallery
catalog exercises filtering, repeated actions, rejection, disabled choices,
layout changes, all five control sizes and Unicode marked-text acknowledgment.
No additional wire node or compatibility alias is introduced. Physical-device
and visual acceptance remain outstanding. See
[choice composition](../../../swiftui-choice-composition.md).

Carousel now uses `View.Scroll_targets` with bounded horizontal/vertical native
scrolling, explicit item fractions, directional alignment and native snapping.
Card actions remain ordinary Buttons, separate from OCaml-controlled position.
The Material constructor and Dart branch are removed. The actual Gallery catalog
and standalone App verify position reporting, independent repeated actions,
free scrolling, rejection restoration and obsolete-input fencing. Native geometry
checks cover 36 axis/direction/alignment/initial-position combinations. Physical
gestures, iOS runtime, visual acceptance and large-catalog performance remain
outstanding. See [scroll targets](../../../swiftui-scroll-targets.md).

Plain Tooltip now uses `View.help` and native SwiftUI help/accessibility text.
The old plain constructor and Dart rendering path are removed. Native windows
and the actual Gallery component verify changing hints, retained child identity
and independent enabled/disabled actions. Rich Tooltip now composes
`View.Popover`, text and ordinary Buttons. Native appearance, rejected/accepted
dismissal, obsolete callbacks, hidden-session restoration and content-action
ownership pass actual OCaml/native-window regressions. The remaining Material
Tooltip constructor, Dart branch and unused triggered event are removed. Physical
interaction, editor focus/IME inside presentations, VoiceOver, arrow-edge geometry
and iOS runtime acceptance remain open. See [native help](../../../swiftui-help.md)
and [controlled popovers](../../../swiftui-popover.md).

Dialog and Bottom_sheet / Side_sheet surfaces now compose `View.Sheet` or
`View.Sheet.full_screen`, text, dividers and independent Buttons. Five actual
Gallery presentations pass native-window action, disabled-choice, modal-input,
nested-popover, rejection, hiding and teardown checks. Popover and Sheet share
the same generation-fenced presentation controller. Old Material surface APIs,
dialog nodes 134/135 and event 45 are removed. Native sizing now supports
Automatic/Fitted/Form/Page proposals. The unused Navigator/Page and Modal_* APIs,
wire nodes 66/67 and route-pop event 16 are removed, with a regression rejecting
the old Page payload. Persistent Scaffold slots now use bounded Body and viewport
overlay composition; the Scaffold API and node 96 are removed. The actual Gallery
page-layout catalog verifies independent actions, footer/window resizing and
retained scroll identity. Physical iOS detents/fullscreen, focus/IME, VoiceOver
and complete visual acceptance remain outstanding. See [native sheets](../../../swiftui-sheet.md).

### Generic gesture integration and remaining acceptance

Preserve the typed Gesture contract: Tap and Double_tap carry finite local/root
point coordinates and pointer kind; Long_press has a Unit payload. Repeated
actions must not coalesce. Native pointer transitions retain contact identity
and button state. Invalid coordinates must not disturb admitted events.

Gesture node 48 now validates and renders through
`NSGestureRecognizerRepresentable` (macOS 26) and
`UIGestureRecognizerRepresentable` (iOS 18). Native click/tap and press
recognizers determine timing, failure dependencies and movement tolerance.
A node-owned controller resets recognizers and fences callbacks when bindings,
presentation or lifetime changes. Session admission checks the displayed node,
its bindings/children and active content ownership.

Use the App's named root coordinate space for event global coordinates.
The macOS integration test exposed a title-bar offset in the recognizer's
built-in global coordinate space; explicit root conversion matches the existing
layout measurements. Do not compensate with hard-coded title-bar dimensions.

Five actual OCaml/macOS window scenarios now pass, covering single/double-click
precedence, long press, primary pointer ordering/coordinates/buttons, nested
Button isolation, drag cancellation, binding replacement, removal and session
inactivity/reactivation. Full iOS 18 module/example compilation also passes.
These checks do not establish physical iOS gesture behavior or scroll-view
competition. The initial UIKit passive recognizer tracks one contact; multiple
simultaneous contacts, transformed/nested targets, secondary buttons and actual
scroll cancellation remain acceptance work. The combined Gallery is unfinished.

AppKit Gesture and Hover now share pointer-device metadata: ordinary mouse ID
0, native tablet IDs in a separate numeric range, and kinds learned only from
valid proximity events. A leased application scope observes proximity across
windows, invalidates metadata on application inactivity, and releases its local
monitor when no observers remain. Native-packet regressions cover pen/eraser,
two devices and scope lifetime. The combined real-window pointer scenarios
still need an unlocked Mac run; the latest attempt was prevented by a locked
desktop. Actual hardware acceptance remains incomplete.

The UIKit adapter now shares weak native-touch identities between observers and
queues every contact's down/up edge with its own coordinates, kind and binding
generation. Mouse/Pencil IDs agree with the UIKit hover source; ending or
cancelling one finger preserves others. Four utility tests and an actual OCaml
batch round-trip test pass after an input-contract RED; physical iOS 18 module
and example compilation also pass. This replaces the single-contact code but
does not prove system multi-touch delivery, attachment timing or transformed
coordinate conversion on a device. Those runtime gates remain mandatory.

Button focus probes acquire wrapper focus with edit interactions while keyboard
navigation is off, but Space does not activate the Button. Button autofocus remains unfinished. The obsolete Material Button/FAB
constructors, private nodes and codecs have since been removed.
FocusScope and macOS KeyboardListener have since been implemented; UIKit
KeyboardListener and physical interaction acceptance remain unfinished. See
[gesture integration](../../../swiftui-gestures.md) and
[Button autofocus](../../../swiftui-button-focus.md).

The [keyboard event transport](../../../swiftui-keyboard.md) now encodes tag 9
with bounded logical/physical identifiers, typed down/up/repeat actions and all
modifier bits. An actual OCaml listener fixture verifies field preservation,
repeated events and replay fencing; the related 28 tests and physical-iOS
compile checks pass. That checkpoint established transport only. The later
macOS capture checkpoint
implements listener rendering, focus, event policy and presentation admission
together; UIKit still requires the corresponding capture implementation.

## Acceptance criteria

Current evidence is summarized here; the requirements below remain the full
completion gate. Earlier implementation checkpoints elsewhere in this document
record historical states and do not override this section.

- The latest complete macOS Swift package regression passes 489 tests in
  107 suites (486.197 seconds), including actual OCaml/native integration,
  scoped theme, Dropdown, measured Mail rows, conditional swipe panes and the
  final macOS Button/pan arbitration fix at runtime source `11d75d4`.
  Fresh xUnit completion and input hashes are recorded in
  `_build/validation/swiftui-final-macos-404ae17.json`. This is separate
  from standalone Xcode UI tests and physical-iOS acceptance. The
  macOS Button/pan arbitration fix also passes the real Mail mouse regression under
  two host appearances, three swipe-direction scenarios, eight removal-direction
  scenarios and ten focused Swift tests.
- All eleven standalone examples have native source/host configurations and
  complete-object build evidence. Gallery stages its complete OCaml tree and
  dispatches its toolbar action. Native keyboard nodes now decode on both
  platforms; UIKit keyboard capture and environment observation are implemented
  and compile for physical iOS. Their physical interaction checks remain open.
- The [widget inventory](../../../swiftui-widget-inventory.md) records 228 values
  and 175 named constructors. Individual API mapping now covers all 228 values
  and 175 constructors. The [navigation/input review](../../../swiftui-navigation-input-api-review.md)
  records the final mappings. Scoped theme now has interactive Gallery/native
  regression evidence; combined Dropdown behavior also passes native-window
  regressions at two widths. Auxiliary
  contracts and both-platform behavioral evidence remain
  required; mapping completion or successful Gallery startup is insufficient.
- All declared [host services](../../../swiftui-host-services.md) have dispatch
  paths. Native macOS evidence and outstanding physical chooser/device checks
  are recorded per service; there is no remaining unnamed service stub implied
  by the older checkpoints.
- [Collection measurements](../../../swiftui-collection-performance.md) now
  record real OCaml/Swift/native-window update timing and sampled RSS for
  10,003 records on macOS. Six fresh processes verify 1,326 updates. This is
  a Debug diagnostic with synthetic range events, not compositor frame-rate,
  physical input, self-sizing, maximum-size or iOS performance acceptance.
- The [input fixture pipeline](../../../swiftui-input-fixtures.md) uses the
  production Swift encoder for all seven canonical input samples and verifies
  OCaml decoding/re-encoding. Dart generation and active backend paths are gone.
  The spec module now uses its new name under the explicit three-line source
  authorization. The published SDK snapshot still awaits source publication and
  regeneration from the exact pushed commit.
- Native CI dispatch covers all eleven examples in three configurations on
  each platform. The 33-dispatch checks establish scheduling, not completed
  builds of every matrix entry. Installed CLI macOS Debug/Profile/Release
  execution is verified separately. The complete CI contract currently fails
  its early SDK metadata check; its historical success is not current evidence.
- [Committed-source Mail captures](../../../screenshots/swiftui-mail/committed-source/README.md)
  contain five macOS states from `11d75d4`: Inbox, expanded preview, attachment
  detail, mouse-revealed swipe actions and the resulting Archived message.
  The [earlier captures](../../../screenshots/swiftui-mail/current/README.md)
  also contain the physical-iPhone Inbox. The newer
  [physical interaction captures](../../../screenshots/swiftui-mail/physical-interaction/README.md)
  add a passing system UI test for expansion/collapse and attachment detail.
  Device UI Automation authorization was completed. The swipe scenario exposed
  hidden action panes in the UIKit accessibility tree; its conditional-pane fix
  passes focused macOS and mouse-input tests and a generic iOS Release build.
  Physical retesting was interrupted when the user removed the iPhone.
  Verified physical Archive, a fresh swipe capture and final published-source
  provenance remain open.

- The sole active backend is SwiftUI. Supported build targets exactly match
  the decided Apple matrix; unsupported platforms fail clearly.
- The platform matrix is physical iOS/iPadOS 18.0+ arm64 and macOS 26.0+
  arm64. Simulator targets are rejected and have no toolchain or test lane.
- Public modules, CLI, configuration, protocol, bridge, packages, SDK metadata,
  resources, and current documentation use the new names. There are no old
  aliases, parallel Flutter targets, or legacy decoders.
- An implementation inventory maps every current public widget constructor and
  variant to its new API, Swift implementation, both-platform Gallery scenario,
  and meaningful interaction test. Consolidated capabilities are explicit;
  no component is marked complete merely because it compiles or renders a
  placeholder. Obsolete Flutter-only presentation knobs are documented as
  removed rather than implemented as no-ops.
- OCaml remains the application source of truth. Swift cannot mutate canonical
  mail data or execute mail business rules independently of OCaml handlers.
- OCaml/Swift fixture tests cover full and incremental frames, typed input,
  malformed payloads, version rejection, transactional rollback, native buffer
  ownership, stale events, resource lifetime, and exact-once shutdown.
- Runtime integration tests establish serialized native calls, foreground
  clock behavior, presentation-token completion semantics, rejection recovery,
  background/resume, and Worker Domain operation.
- List tests establish bounded materialization at large logical counts,
  unloaded-range recovery, retained keys, paging deduplication, Dynamic Type
  and window-resize layout, and stable anchors during expansion and deletion.
  Record measured frame/update and memory behavior without inventing budgets
  from unmeasured assumptions.
- Text tests cover selection and marked text across Unicode edits and stale
  acknowledgments. Navigation and animation tests cover canceled back,
  duplicate actions, reduced motion, and stale completion filtering.
- Mail preserves the behavior listed above, runs through the real native
  runtime on iOS and macOS, and delivers all required reviewed screenshots
  with a reproducible capture manifest.
- All retained examples build. Relevant OCaml tests, Swift tests, Xcode UI
  tests, generated-artifact checks, target/ABI symbol audits, SDK regeneration
  checks, `spec-dev-tool check --all`, and `git diff --check` pass. Record exact
  commands and actual tested configurations in the implementation evidence.
- Code/SDK commits, when pushed, use the required two-step source-then-generated
  SDK sequence. Source-only documentation work does not regenerate SDKs.
- Dune changes stay within the migration authorization recorded above.
  Protected spec changes stay within the separately authorized three-line
  comment/reference patch. No protected ID type or behavior is changed.

## Risks

- This spans the entire backend, not just a Swift package. Shipping only Mail
  would leave most widget, worker, tooling, and extension coverage unproven.
- SwiftUI collection identity, self-sizing content, and observation can cause
  broad invalidation or lost local state if the dynamic renderer is designed
  as a whole-tree replacement.
- A precise presentation acknowledgment and deterministic foreground clock
  driver require an early prototype. Store commit alone is insufficient
  evidence for the existing lifecycle contract.
- iOS runtime tests and screenshots depend on an available physical iOS 18+
  device and development signing. Their availability is not yet verified;
  Simulator is outside the selected scope and cannot replace this gate.
- SwiftUI text entry may not expose enough marked-text state for the current
  editing contract. The authorized native adapters must prove that contract;
  an incompatible editing contract must be reported rather than hidden.
- Native lists do not automatically guarantee a bounded OCaml tree, and lazy
  row appearance does not prove an accurate visible-range report.
- Native navigation and Material navigation do not have identical interaction
  or appearance. The migration intentionally gives up Material visuals,
  Flutter layout guarantees, Dart extensions, hot reload, and non-Apple
  portability, while preserving the requested functional capabilities.
- Public names, wire bytes, ABI exports, and consumer configuration break
  together. External consumers must adopt the new release directly; this
  repository will not provide compatibility layers or migration tools.
- Dune modification is explicitly authorized for this migration. Protected
  `.mli` definitions remain outside that authorization. No unclear protected
  definition has been identified during exploration; if one blocks development
  later, stop and report the exact definition, suggested change, and rationale
  as required by `AGENTS.md`.

## Questions

None. The user resolved Q1 by selecting iOS 18+, macOS 26+, and no Simulator,
then accepted the recommendations for Q2-Q4: native adapters, all eleven
standalone examples, and migration-scoped Dune modification. The Decision
section records these answers. Device/signing availability remains a runtime
validation prerequisite, not an unresolved platform decision.

### Native keyboard identity mapping checkpoint

The [native key mapping](../../../swiftui-keyboard.md#native-key-mapping) now
normalizes Apple key data to Unicode logical identities and HID physical
identities. AppKit packet tests execute the actual OCaml keyboard handler;
UIKit adapters typecheck for physical iOS. Independent modifier edges, Caps
Lock physical state, held-key identity and reset are covered. Native capture,
focus ownership, listener rendering, propagation and complete Gallery/window/
device acceptance remain required; mapping does not substitute for them.

### Native FocusScope checkpoint

[FocusScope](../../../swiftui-keyboard.md#focusscope) now uses SwiftUI native
focus state without splitting the view graph. Real native-window tests execute
the OCaml handlers for nested scopes and AppKit field editors, preserve root
layout anchors and verify hidden/inactive admission. Autofocus waits for matching
presentation, mount and enablement, then stops requesting focus after success.
Binding replacement, disposal and malformed frames are covered. Six focus tests,
17 related tests, three platform checks and OCaml all/test/format/install pass.

This does not finish KeyboardListener, Button autofocus, physical iOS focus or
complete Gallery acceptance. Desktop access still reports a locked Mac; iPhone
preflight still reports unavailable DDI services. No new screenshot, physical
installation or source/SDK publication is claimed by this checkpoint.


### macOS KeyboardListener checkpoint

The [native AppKit listener](../../../swiftui-keyboard.md#macos-keyboardlistener)
now captures window events and applies nested handled/ignored propagation while
preserving normal native text input for ignored events. Real OCaml/native-window
tests cover key identities, down/repeat/release, autofocus, visibility, unrelated
windows, shared field editors, rapid refocus, handler replacement and disposal.
The targeted run passes 19 tests in four suites in 6.502 seconds, including the
complete macOS Gallery tree/presentation/toolbar regression (0.321 seconds).

UIKit raw capture and listener ownership/propagation remain unfinished; iOS
still rejects node 53. Neither the macOS test nor iOS typechecking establishes
physical keyboard, IME, modal, accessibility or complete page acceptance. The
full migration goal remains active, with no new screenshot or publication from
this checkpoint.


The final full Swift run passes 440 tests in 97 suites in 414.612 seconds, with
its successful completed xUnit report verified by the runner. OCaml all/test/
format/install also passes. These checks do not establish physical iOS keyboard
capture or completion of the remaining full-migration acceptance criteria.


### Signed SwiftUI iOS bundle checkpoint

The signed-bundle wrapper now audits the actual SwiftUI App without requiring
an obsolete Flutter framework. It forwards dSYM and SQLite requirements together
and checks the real signature, profile-authorized certificate, Team ID,
wildcard or exact App ID, bundle identifier, UTC expiration and typed debug
entitlements. Nine real development-signing tests pass in 13.050 seconds; four
native executable/resource/dSYM regressions pass in 1.756 seconds. No signing,
CMS or Mach-O tools are mocked; the expiry test changes only its audit
subprocess clock. See [signed native bundle audit](../../../testing.md#signed-native-bundle-audit).

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
AppKit window. See [native host environment](../../../swiftui-host-environment.md).

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
has a native name. See [native replacements](../../../material-components.md).

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
See [native Button autofocus](../../../swiftui-button-focus.md).

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
[native scroll service](../../../swiftui-scroll-service.md).

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
[notification contract](../../../swiftui-notices.md).

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

The [widget inventory](../../../swiftui-widget-inventory.md) now enumerates 228
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

### Asynchronous action menu implementation checkpoint

Host request 11 now uses a scrollable SwiftUI action sheet. Selection, dismissal,
cancellation, active/visible ownership, modal contention and retained callbacks
run through the actual OCaml runtime in macOS tests. File dialogs and action
menus share an owned-window modal admission gate. The public OCaml API and both
wire codecs validate the bounded domain, preserve exact UTF-8 identity and
reserve the optional-string prefix within the host response budget. Host Effects
exposes Choose action and its typed result. See [action menus](../../../swiftui-host-menus.md).

The baseline widget inventory additionally records exact API and parameter
mappings for ten Menu/Fab_menu/Split_button values. These mappings remain pending
complete interaction, variant, performance and physical-iOS acceptance. Haptics,
civil-picker host services, UIKit capabilities, final Mail captures, package
cleanup and source/SDK publication remain open. Protected spec files remain
unchanged pending explicit authorization.

The full serial Swift regression passes 462 tests in 101 suites in 469.588
seconds, with a fresh completed xUnit report. OCaml all/test/format/install
passes with the same menu-domain and response-size constraints. These checks
leave the remaining full-migration and physical-capture requirements intact.

The actual Host Effects native window scenario passes in 40.996 seconds,
and three platform checks pass in 22.264 seconds. Host Effects and Mail macOS
Debug bundles rebuild and pass signature, target and generated-project checks.
The current iOS Swift module and all eleven example entrypoints compile; native
iOS object/App records retain their earlier provenance. CUA still reports the
Mac locked when selecting the rebuilt Mail, so no fresh capture is claimed.


### Haptic feedback implementation checkpoint

Host request 12 now submits iOS impact/selection or macOS generic feedback after
validated active presentation, with cancellation, repeated-request and lifetime
coverage through actual OCaml. UIKit view interactions are reused and removed
on reset. Native submission is distinguished from physical delivery. Host
Effects exposes all four requests; its standalone native service scenario
passes in 42.030 seconds. Three platform checks pass in 22.550 seconds, and
OCaml all/test/format/install passes. See [haptics](../../../swiftui-haptics.md).

All eleven current iOS complete objects cross-build and pass target/ABI/process
import checks. Host Effects and Mail rebuild through the CLI as macOS Debug and
signed iOS Release Apps; native bundle/privacy and provisioning authorization
checks pass. The macOS source-build environment uses this worktree's installed
libraries via OCAMLPATH. No device execution, new screenshot or publication is
claimed. Civil-picker host services, UIKit capabilities, physical acceptance,
remaining widget/variant review, final captures and package cleanup remain open.
The complete Swift regression must run again for the final migration source;
the previous 462-test result precedes haptics.

The final scoped regression passes 11 tests in four suites in 0.691 seconds,
with a fresh completed Swift Testing xUnit report after the UIKit cache change.
The two generated projects pass `sync-host --check`, and staged iOS object hashes
match the cross-built artifacts. `_build/validation/swiftui-haptics.json` records
source, logs and all four App identities. Protected spec files remain unchanged.

### Civil host picker checkpoint

[SwiftUI civil picker services](../../../swiftui-host-pickers.md) replaces the
remaining Flutter-shaped host date/range/time parameters and payloads. Menus
and all three selectors now share one SwiftUI sheet owner. The runtime tests
edit native controls and confirm values through real OCaml requests, including
historical dates, leap-day clamping, cancellation and modal contention. Physical
iOS picker acceptance remains pending, along with the broader migration gates.

### UIKit environment observation checkpoint

[Native host environment](../../../swiftui-host-environment.md) now includes an
iOS application-boundary observer, sharing SwiftUI preferences and OCaml event
transport with macOS. A window-owned UIKit adapter publishes full viewport,
safe areas and keyboard layout-guide edge occlusion. Source teardown and queued
callbacks retain the existing ownership rules. Host Effects exposes the reactive
values and has a physical-iOS keyboard show/hide/restart UI scenario. Shared
geometry/native macOS tests and iOS compilation pass; physical execution remains
pending because the device is unavailable. UIKit KeyboardListener remains a
separate missing implementation; this checkpoint does not close that requirement.


### Current Mail capture checkpoint

[September 14 captures](../../../screenshots/swiftui-mail/current/README.md)
now use the verified SwiftUI namespace build with the explicit Light theme:
four complete macOS states and a fresh physical-iOS Inbox. Native macOS
expansion, detail, Archive and mailbox selection were exercised. The physical
UI runner still stops at XCTest passcode authorization before its two scenarios
execute. Remaining iOS interaction captures, full widget acceptance and final
published-source/SDK provenance remain required.


### SwiftUI SDK generation checkpoint

The [packaging guide](../../../packaging.md) now records fresh SDK repository
assembly from explicit dependency inputs and exact locked framework metadata.
Generation no longer depends on an old framework package directory; it stages
and replaces the complete output. The generated manifest/build recipe and
local cross configuration use iOS 18, and source closure headers match the
SwiftUI verifier. Git/filesystem regression tests and a full pinned dependency
metadata generation pass. The old published snapshot remains untouched pending
source publication. Installed-SDK compilation and separate SDK publication
are not established by this checkpoint.


### Installed CLI boundary checkpoint

The [installed CLI gate](../../../swiftui-cli.md#installed-cli-acceptance)
now builds and runs an external OCaml/SwiftUI application from a temporary
installed prefix with no source-root override. Three build profiles and actual
native counter updates pass. Existing asset declarations required no changes.
This verifies the package installation layout; dependency solving, published
source and installed iOS SDK acceptance remain separate requirements.


### Foundational API review checkpoint

The [foundational API review](../../../swiftui-core-api-review.md) records 15
additional value mappings and their intentional native parameter changes.
There are now 29 individually reviewed public values. The current scoped
macOS checks pass 18 native tests and 10 actual OCaml/Gallery integration tests.
Overall widget acceptance remains open; this checkpoint neither adds a
compatibility layer nor treats API mapping as physical-device completion.
