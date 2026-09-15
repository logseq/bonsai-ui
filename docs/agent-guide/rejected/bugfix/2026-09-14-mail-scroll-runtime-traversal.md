# Mail Scroll Runtime Traversal

## Problem

The user reports stuttering while scrolling the macOS Mail example. A ten-second
sample of the Debug application shows 2,191 of 8,101 main-thread samples inside
`updateFieldFocus` and `sampleCollectionRequests`. Both sort every rendered node
before filtering for their relevant controller. Refresh also traverses the whole
tree to update native extensions when none are present.

## Proposal

Build ordered field and collection indexes when RenderTree commits a frame.
Preserve native-extension ancestor order in its existing index. Consume these
indexes during refresh instead of sorting or traversing all decorative nodes.
Keep event ordering, presentation fencing, object identity and disposal intact.
Verify the actual Mail runtime with a focused refresh benchmark, existing native
control tests and a rebuilt application. Investigate remaining measured hotspots
if this change does not sufficiently reduce the main-thread cost.

## Questions

None. This is a bounded performance repair for the user-reported Mail scrolling
problem; no product behavior or public contract change is required.

## Container review checkpoint

The user requested a review of SwiftUI container choice and official best
practices before further diagnosis or implementation. The traversal optimization
above is deferred. No production code or tests have been changed.

The current Mail container is ScrollView plus CollectionWindowLayout and a
ForEach over an OCaml-supplied window. It already bounds materialized rows, but
owns virtualization, size refinement, anchor correction and request latency.
Each accepted native measurement rebuilds geometry and writes ScrollPosition.
MorphingSurface also lays out both compact and expanded content for each row.
These are architectural costs to evaluate, not proven causes of the reported hitch.

Apple documents List as a lazy, platform-standard data container, and lazy stacks
as the option for large custom scrollable content. Its performance guidance
emphasizes stable row identity and avoiding geometry-driven update cascades:

- https://developer.apple.com/documentation/swiftui/picking-container-views-for-your-content
- https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks
- https://developer.apple.com/videos/play/wwdc2023/10160/
- https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance

The existing List probe tests exact offscreen pixel geometry after sparse extent
changes. It does not compare real Mail scrolling and cannot establish that List
is unsuitable for Mail. Container evaluation should first test native List for
macOS mail semantics and ScrollView with LazyVStack for the custom card design.
Any prototype must account for the OCaml window protocol: changing the Swift
container alone does not make unavailable row descriptions synchronously available.
Keep business state in OCaml while evaluating native presentation ownership.
Use optimized builds and the same row content to compare hitches, body/layout
updates, retained state, memory, pagination and rapid direction changes before
selecting a production change.

## Acceptance criteria

- A regression exercises repeated no-diff refreshes of the actual Mail component.
- Field and collection refresh work uses ordered committed controller indexes.
- Native extensions retain ancestor-before-descendant presentation ordering.
- Relevant Swift tests, Mail window acceptance and macOS build succeed.
- Record before/after refresh timings and reopen the built Mail application.

## Risks

- Indexes must be replaced on every commit, including removal, epoch replacement and
closure, so they cannot retain or dispatch to obsolete nodes. Timing evidence is
machine-specific and is not a claim of guaranteed display cadence.

## Alternatives considered

### Only build Release

Compiler optimization can reduce the constant cost but leaves repeated whole-tree
sorting in a frequently executed main-thread path.

### Change collection geometry or replace the renderer

The sample identifies avoidable session work. Changing measured sizing or scrolling
semantics before proving a geometry defect would expand the scope unnecessarily.

## Rejection reason

Superseded by the agreed Mail Rendering Performance proposal, which includes the traversal repair and the measured layout, measurement, surface, and handler causes.
