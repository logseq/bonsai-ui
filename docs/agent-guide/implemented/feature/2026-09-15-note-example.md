# Note Example

## Problem

The repository has no standalone note example that demonstrates a visually rich
document surface, a template browser, and floating document controls together.
The requested example should reproduce the UI effect of the supplied Craft
reference through the real BonsaiSwiftUI application and rendering path.

The reference is `/Users/rcmerci/Downloads/craft-1.jpeg`, supplied by the user on
September 15, 2026. It contains three iPhone views: a Templates sheet, a warm
Cornell note, and a cool reading document with a typewriter cover image. This
local reference is not a portable repository asset; the visual requirements
below preserve the relevant observations. Text inside the screenshot, including
the `/today` and Assistant hints, is sample UI content rather than an instruction
to implement those services.

This decision records the user's confirmed scope on September 15,
2026. Note is a UI capability demonstration with mocked data, not a note-taking
product. Implementation and acceptance evidence are recorded below.

## Decision

### Application and scope

Add a standalone `examples/note` demo named Bonsai Note. Target physical
iOS first for reference acceptance and retain a usable macOS application under
the repository's existing SwiftUI architecture. Current repository targets are
physical iOS/iPadOS 18+ arm64 and macOS 26+ arm64; Simulator is unsupported.

Use deterministic, bundled mock notes, templates, images and service results.
The user confirmed template selection, navigation, section expansion, theme
selection and limited text editing solely to verify UI capabilities. Keep only
the in-memory state needed to exercise those controls and reset fixtures on
relaunch. Persistence, accounts, sync, collaboration, AI, real export and a
general rich-text/block editor are outside scope. Do not add product workflows,
backend services or storage infrastructure to support the demonstration.

UI rendering and event handling must run through the real OCaml/Bonsai and
BonsaiSwiftUI path. Mock application data and service results, not the library
capabilities being verified. Whenever a required UI effect is unsupported,
extend bonsai-ui itself with a reusable public capability and native rendering
support. This is a requirement, not an optional follow-up or permission to lower
the visual target to the current API's limits.

### Visual contract

Reproduce all three reference states as reachable views of one application.
Do not render the supplied screenshot as the application UI. System status bars,
Dynamic Island, device bezel, clock and battery remain device-owned and are
excluded from visual matching.

| State | Observed reference | Proposed reproduction |
| --- | --- | --- |
| Templates | Large rounded, translucent light-gray sheet; title and circular close control; inset Search field; uppercase gray category headings; thumbnail previews and captions; fine dividers | A scrollable native sheet with a fixed title/search region, a single personal-template tile and a two-column catalog. Preserve generous spacing, portrait previews, warm paper colors and colored thumbnail borders. |
| Cornell note | Amber/brown soft background; cream document card; bold title; small trailing count ornament; darker inset sections; right-aligned date hint; disclosure rows; centered dot separators; keywords and bullets | A vertically scrolling document with the same hierarchy, tinted blocks and generous vertical rhythm. Keep the title, Lesson Title, Main notes, Key words / Concepts and dotted separators recognizable. The apparent count ornament is visual evidence only; its meaning is not established. |
| Reading note | Pink/lilac background; pale-blue rounded document; wide cropped typewriter image; bold Robert Pirosh title; divider and long left-aligned prose | A distinct reading fixture with a bundled typewriter-style cover, matching crop, text density, line spacing, insets and page tint. Use deterministic English sample prose; exact transcription is not an acceptance requirement. |
| Document chrome | Circular back button; top-right share/more capsule; two separate bottom capsules; small monochrome tools, multicolor ring and contrasting plus button; soft shadows/translucency | Shared chrome for both documents, tinted by the selected theme. Controls stay anchored while content scrolls; reserve enough scroll clearance to reveal the final content above the bottom capsules. |

Use the screenshot as a guide to proportions, not device-independent pixel
measurements. Initial tuning values, to verify on-device, are 16–20 pt outer
document margins, 16–24 pt inner padding, 18–24 pt document corners, approximately
28 pt bold document titles and 17–18 pt body text. Maintain at least 44 pt touch
targets even for small icons. Fix the initial demo to a light palette so the
reference colors remain stable under an inherited dark system appearance.

The visual priority is the overall silhouette and spacing, followed by the
warm/cool palettes, typography, cover crop, and translucent floating controls.
An opaque toolbar or flat monochrome background is not evidence that the final
reference effect is complete. Exact proprietary glass optics are not specified
by this still image; the achievable material treatment must be demonstrated.

### Mock interaction model

These confirmed demo behaviors exercise the reference UI. The screenshot alone
does not establish how Craft implements the corresponding controls. Each action
updates transient demo state or displays a deterministic mock result.

1. Launch into the seeded Cornell note. A template action in the more menu opens
   Templates. Search filters local titles; clearing restores categories; an
   empty result has a small explicit empty state.
2. Include Cornell and reading fixtures in the catalog so both reference
   documents are discoverable. Selecting a template loads a working copy of its
   mock fixture, closes the sheet and displays it. The close button and
   native sheet dismissal preserve the current note.
3. Back returns to the template browser so the other reference fixture is easy
   to open. No additional note library or note-management workflow is required.
4. Cornell disclosure rows expand and collapse independently. Keep the
   screenshot's initial collapsed state and use stable block identities.
5. The pencil toggles limited editing of the title and selected plain-text
   content. Done returns to the styled document and preserves session edits.
   This is not an inline WYSIWYG promise. Keyboard appearance must not obscure
   the active editor or its completion control.
6. The color ring selects warm or cool document themes. Plus opens
   paragraph/checklist choices that insert a mock block into transient state.
   Other tools use named demo actions in a menu; unidentified screenshot icons
   do not imply AI or collaboration. Share opens a mock preview/menu with no
   external effect. No visible enabled control silently does nothing, and no
   real service integration is needed to demonstrate its UI response.

### Existing capabilities and gaps

Repository evidence was read on September 15, 2026. Existing APIs establish
starting points, not completed visual acceptance for this example.

| Need | Existing evidence | Implementation and verification required |
| --- | --- | --- |
| Rounded cards, text and anchored chrome | `ocaml/ui/view.mli`: stacks, frames, padding, background, clip, overlay and safe-area padding; [layout guide](../../../swiftui-layout.md) and [page layout](../../../swiftui-page-layout.md) | Verify finite scrolling bounds, page insets and toolbar clearance on physical iOS. |
| Template presentation | `View.Sheet.create`; [sheet guide](../../../swiftui-sheet.md) | Validate large-sheet proportions, background treatment, drag dismissal, search focus and scrolling. Native defaults do not guarantee the reference's exact radius or translucency. |
| Document navigation | `View.Navigation_stack`; [navigation guide](../../../swiftui-navigation-stack.md) | Establish whether existing toolbar/navigation configuration can express the floating chrome without a duplicate native bar. |
| Cover and preview images | `View.image`, resource sources, Fill sizing and explicit clip; [image guide](../../../swiftui-images.md) | Verify actual example resource packaging on both platforms, crop and decoding. Bundle reusable assets; avoid runtime dependency on Downloads or network images. |
| Styled reading and limited editing | Styled display text and native `View.text_editor`; [editor guide](../../../swiftui-text-input.md) | The editor is plain text. Rich-text selection, inline formatting and block editing require a separate design if requested. |
| Background gradients, glass, blur and shadows | The inspected public `view.mli` and `style.mli` expose solid-color backgrounds but no dedicated gradient, blur, shadow or glass surface constructor | Verify the gap and implement the reusable bonsai-ui capabilities necessary to meet the agreed fidelity, including the public API and native renderer. Do not replace the target with opaque flat fills or hide the application in a Swift-only screen. |

OCaml/Bonsai owns notes, block IDs, selected note, template query, expansion,
theme and canonical edited text. Swift owns native rendering, transient input
sessions and presentation resources. Keep the application's Swift entrypoint
thin, following [Mail](../../../../examples/mail/README.md). Shared rendering
deficiencies belong in bonsai-ui rather than Note-specific renderer branches.
For every unsupported required effect, identify the missing public contract,
add its shared OCaml/API, bridge/protocol and native support as needed, then
exercise it from Note and verify it independently of Note's mock data. This
rule applies to all required UI behavior, including layout, presentation, input
and accessibility, not only gradients or material surfaces.
Any incompatible API change must replace the obsolete path; do not add
compatibility wrappers or legacy behavior.

### Implementation footprint

- `examples/note/ocaml/`: fixture data, model/actions, views and native entrypoint.
- `examples/note/swift/App.swift` and `bonsai-swiftui.sexp`: standalone host and
  application configuration; a `resources/` directory for bundled image assets.
- `examples/note/README.md` and focused behavior/native interaction coverage.
- Example registration in `Makefile`, `tool/test_swiftui_example_cli.py`, and
  other enumerated build/generator consumers discovered during implementation.
- Shared OCaml/protocol/Swift changes only for confirmed missing capabilities,
  accompanied by their public contract and reusable verification.

On September 15, 2026, the user
explicitly authorized creating or modifying the Dune configuration required to
register and build `examples/note` and its focused tests. Do not request that
authorization again. This is not blanket authorization for unrelated build
changes. Protected OCaml files under `spec/` must not be changed; an unclear or
unreasonable protected `.mli` contract requires stopping and reporting the exact
issue and suggested change. Do not assume permission to modify protected specs
from the authorization to extend the library or adjust Note's Dune configuration.

If future implementation includes committing and pushing code, follow the
repository rule to regenerate the iOS SDK from that pushed source commit and
commit/push the generated SDK update separately.

## Alternatives considered

### A single static reading screen

This reduces scope but omits the template browser and Cornell composition shown
in the supplied reference. It is useful as an early visual checkpoint, not the
recommended completed example.

### A full note-taking product

Persistence, rich block editing, AI and collaboration would dominate the work
and do not serve the confirmed UI capability demonstration. All application
data and service results are mocked; those product features are excluded.

### Restrict the demo to today's public UI API

This could leave unsupported visual effects approximated or omitted. The user
explicitly requires extending bonsai-ui itself wherever the reference UI needs
missing capabilities, so this alternative is rejected.

### A Swift-only mockup or screenshot-backed page

These could approximate the image quickly but would not demonstrate the real
OCaml application and BonsaiSwiftUI rendering path. Neither is recommended.

## Acceptance criteria

- The actual standalone Note application builds for macOS and physical iOS
  using the agreed repository example workflow.
- Templates, Cornell and reading states are reachable through the documented
  flow with deterministic mock data and no network or backend requirement.
  Relaunch restores the initial fixtures; no persistence or product workflow
  is required for acceptance.
- Capture all three states from the running application on a physical iPhone.
  Record source revision, device, OS, viewport and fixture state. Compare
  app-content crops against the corresponding reference panel at the same
  normalized width; exclude device hardware and varying system indicators.
- Review the sheet outline/search/grid, Cornell block hierarchy, reading
  image/title/body, both palettes and anchored translucent controls side by
  side. Record visible deviations and resolve them before claiming visual
  completion; mockups, offscreen component renders and build success alone
  do not satisfy this criterion.
- Verify local search/empty state, selection/dismissal, back navigation,
  independent disclosures, theme switching, insertion and the agreed edit
  flow through the actual OCaml model. Edits and mock block insertion affect
  the current working fixture without mutating the deterministic seed data.
  Mock service controls display their defined UI result without external effects.
- Verify scrolling to the final paragraph, bottom toolbar clearance and
  keyboard avoidance on-device. A narrower phone and a resized macOS window
  must remain usable without horizontal clipping or hidden actions.
- Controls have meaningful accessibility names and usable hit targets. Larger
  text remains readable; Reduce Motion and reduced-transparency behavior must
  be checked if new animated/material surfaces are introduced.
- Every unsupported required UI effect is implemented as a reusable bonsai-ui
  capability and consumed by the example through its public API. Note-specific
  native rendering branches, screenshot substitutes and omitted effects do not
  satisfy this requirement.
- New shared capabilities have focused behavior and native rendering checks.
  Run relevant example/build checks and `spec-dev-tool check --all`; record
  any device-dependent acceptance that remains unverified.

## Consequences

- Note demonstrates the three reference states and agreed mock interactions
  through the actual OCaml/Bonsai and native SwiftUI path on both supported
  platforms. Its fixtures reset on relaunch and require no external service.
- Other applications can compose the same gradients, materials, borders,
  shadows, native sheet paint and plain native fields through public APIs.
- The field payload uses Protocol 6. Native applications and the framework must
  be rebuilt together; no compatibility or migration layer is retained. A
  future source push must be followed by the separate generated iOS SDK update.
- Reference captures and source hashes make visual review reproducible.
  Native OS presentation differences, 44-point disclosure targets and the
  permitted original mock image/prose are described in the acceptance report.
- XCTest bootstrap failures and the pre-existing missing generated SDK files
  remain visible in the report. They are not reported as passing tests. The
  independent physical native acceptance and signed source-built app supply
  the device evidence required for this implementation.


## Risks

- Reference-quality translucent surfaces may require shared API and renderer
  work, with different achievable results across the supported OS range.
- A still image does not reveal navigation, editing behavior or icon semantics;
  the confirmed mock interactions demonstrate UI behavior without claiming to
  reproduce Craft's product semantics.
- Font metrics, safe areas and aspect ratio vary by device. Matching a single
  resized photo exactly must not make other supported sizes unusable.
- Plain-text editing cannot preserve arbitrary inline formatting. The limited
  edit mode must have an explicit content model rather than discard styling
  accidentally.
- The reference photograph is not a runtime asset. The bundled original cover
  has recorded provenance; visually similar imagery and exact reference imagery
  remain different deliverables.
- Native image packaging and presentation require physical-device coverage.
  The Note acceptance report supplies device captures and exact source hashes.

## Confirmed decisions

All scope questions were answered by the user on September 15, 2026:

1. **Interaction scope — resolved:** Use the recommended basic interactions
   and limited plain-text editing to verify UI capabilities. All application
   data is mocked; this is not a real note-taking product.
2. **Visual fidelity and shared scope — resolved:** Reproduce all three panels
   with visually similar bundled imagery and physical iPhone visual acceptance.
   Any unsupported required UI capability must be added to bonsai-ui itself.
3. **Build configuration — resolved:** Creating or modifying the Dune
   configuration needed for Note's build and focused tests is authorized.
   Protected spec modifications are not included in that authorization.

No unanswered scope questions remain. The user requested implementation after
confirming these decisions.

## Implementation evidence

**Material correction:** The user identified a flat, opaque Templates panel in
the original comparison. The earlier visual-completion claim was premature.
Physical testing traced the opacity to the iOS 26 Large detent: the sheet's RGB
was identical over warm and cool documents. The public `View.Sheet.Fraction`
now maps directly to SwiftUI's fractional detent, and Note selects 0.98 with a
single standard ultra thin material at 40% opacity and zero tint alpha over a
clear presentation backing. This retains
the native inset floating sheet and its live blurred backdrop. No custom UIKit
blur or application-specific native renderer is needed. The backdrop regression
passes with a 15-level RGB response; all eight physical groups and 17
focused Swift tests pass. Standard Large and Medium keep their existing meanings.

Search editing follows the standard iOS 26 presentation behavior: keyboard
avoidance grows the sheet, and full-height sheets become opaque. Decorative
Surface opacity does not override the system's full-height backing. The final
implementation removes experimental keyboard-height compensation and lifecycle
changes. Device acceptance checks retained focus with a visible keyboard and
restoration of the translucent sheet after keyboard dismissal. See the focused
and restored captures in [the acceptance report](../../../swiftui-note.md).
The shared Surface contract uses schema version 2, supports Ultra thin material
and background opacity, and forces material opacity to 1 under Reduce Transparency.

Implemented on September 15, 2026 in `examples/note`, with standalone macOS and
physical-iOS hosts, deterministic fixtures, local search, native presentation,
independent disclosures, limited editing, themes, insertion and named previews.
OCaml/Bonsai owns all application state. The bundled original typewriter image
has recorded provenance in `examples/note/ASSETS.md`.

Missing rendering capabilities are shared public APIs: `Native_widget.Surface`
provides native gradients, tinted materials, borders, shadows and sheet paint;
`Text_editing.Field_appearance` provides retained Rounded/Plain native fields.
Protocol 6 replaces the previous field payload. No protected spec or unrelated
Dune file changed.

[Note acceptance](../../../swiftui-note.md) records actual physical iPhone
captures, normalized reference comparisons, source/object hashes, fixture and
accessibility settings, narrow layout, keyboard and scroll measurements, and
macOS interaction verification. The latest device run passes all eight groups.
Swift's full suite passes 525 tests; all five focused Surface tests, OCaml tests,
protocol generation/fixtures and standalone CLI packaging also pass.

The physical XCTest runners could not bootstrap, so the report explicitly
records that failure and the independent onscreen native acceptance mechanism.
The repository-wide CI contract also remains blocked by nine generated SDK
files already absent from the unchanged base commit. The signed source-built
iOS app and its real target libraries were verified directly. These limitations
are recorded separately from the completed Note implementation and acceptance.
No source commit/push or SDK publication was performed as part of this task.
