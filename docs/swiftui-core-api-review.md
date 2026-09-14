# Foundational widget API review

This review compares 15 baseline `Widget` values at commit `39c4862` with the
current public declarations, OCaml implementation, Swift renderer and relevant
Gallery scenarios. Exact declaration lines, parameter dispositions and test
sources are recorded per value in the [inventory](swiftui-widget-inventory.json).
It establishes API mapping, not complete physical-device acceptance.

| Baseline API | Current API | Principal change |
| --- | --- | --- |
| `Keyed.create` | `View.Keyed.create` | Root identity remains in OCaml; no wrapper is added. |
| `with_test_id` | `View.with_test_id` | Headless query metadata; native automation uses `Semantics.identifier`. |
| `empty` | `View.empty` | Native EmptyView is omitted; a framed Spacer reserves blank space. |
| `text` | `View.text` | Native line limit, truncation and point-based line spacing. |
| `row` | `View.row` | HStack proposals, spacing and baseline alignment. |
| `column` | `View.column` | VStack proposals, spacing and directional alignment. |
| `padding` | `View.padding` | Leading/trailing insets replace physical left/right. |
| `align` | `View.frame` | Alignment is combined with explicit native sizing proposals. |
| `center` | `View.frame` | Center alignment; measured-child size factors are removed. |
| `sized_box` | `View.frame` | Fixed dimensions retain native overflow and empty-view behavior. |
| `constrained_box` | `View.frame` | Direct min/ideal/max fields replace the constraint record. |
| `decorated_box` | `View.background` | Color and corner radius; clipping remains independent. |
| `clip` | `View.clip` | Rounded clipping and antialiasing; SwiftUI owns layer allocation. |
| `opacity` | `View.opacity` | Finite 0–1 drawing opacity; logical content remains mounted. |
| `transform` | `View.projection_effect` | Native 3×3 plane projection replaces the Matrix4 payload. |

The removed center factors, Fade overflow and explicit save-layer selection
are deliberate API changes. The new APIs do not emulate those Flutter layout
or painting rules. Applications choose native frame proposals, clipping and
truncation directly. Frame omission and `Fill` have different meanings, and a
background does not imply clipping. The inventory records these distinctions
instead of treating similarly named operations as equivalent.

## Evidence

Source inspection covers `View.Keyed`, test metadata, constructor validation,
`Layout` alignment/inset/frame types, `Style` text/projection types,
`NativeFrameModifier`, `NativeTextView` and the relevant `RenderTree` cases.
Existing OCaml tests cover root-key replacement and test-ID queries, including
the real counter update. They passed in the preceding full OCaml check.

The current focused macOS run passes 18 tests in FrameTests, StackTests,
ModifierTests, TextTests and ProjectionTests (1.057 seconds). These compare
renderer output with native SwiftUI expressions and reject invalid updates.
A separate run passes all 10 integration cases from those files in
NativeRuntimeTests (0.218 seconds), including actual OCaml updates, Gallery
rendering, node identity and projection control activation. See
`_build/validation/swiftui-core-api-review.json` for source hashes and logs.

Physical-iOS rendering, accessibility and interaction acceptance remains open.
No inventory entry is promoted to fully accepted by this API review. Rich text,
images, symbols, animations, collections and other controls retain their
separate review and acceptance requirements.
