# Layout and content API review

The [inventory](swiftui-widget-inventory.json) now gives individual mappings for
49 additional values and 14 named constructors. This review covers rich text,
symbols, images, animated opacity, typed viewport/body wrappers, weighted
layout, layers, page composition, labels, cards, dividers and badges.

| Baseline surface | Current API | Deliberate change |
| --- | --- | --- |
| String-only rich text | `View.rich_text` with `Style.Text_span` | One native attributed paragraph; optional per-run styling. |
| Font code-point icons | `View.symbol` | SF Symbols names replace icon-font lookup; meaningful labels are explicit. |
| Network images | `View.image` | Typed remote/resource sources, separate frame/clip and explicit pixels-per-point scale. |
| Animated opacity | `View.animated_opacity` | Native interpolation with presented-generation completion ownership. |
| Flex fixed/flexible/expanded | `View.Weighted.fixed/share` | Floating weights and explicit fill intent replace integer flex and parent data. |
| Stack and positioned children | `View.stack`, frame, padding and offset | Native ZStack measurement; use a base-owned overlay for non-layout-contributing content. |
| Overlay list | `View.stack` or `View.overlay` | Choose measurement ownership explicitly. The old renderer ignored its dismissible field. |
| PreferredSize and Scaffold | Bounded Body, Toolbar and region-owned overlays | Native toolbar sizing and fixed header/footer composition replace Material slots and docking. |
| SafeArea wrappers | Native avoidance, `ignores_safe_area`, `safe_area_padding` | Directional edges and additive signed padding replace physical edges and minimum padding. |
| Body and Viewport wrappers | Corresponding typed `View` modules | Preserve axis evidence; positive finite extents are required when converting to ordinary content. |
| List tile, card, divider and badge | Label/control composition, GroupBox, Divider and Badge | Native appearance and directional alignment replace Material style/property bags. |

The image default changes from `Contain` to `Original`; applications that need
aspect-fit sizing must request `Fit`. The auxiliary `Style.Image_fit` contract
is outside the inventory's 175 constructors and is recorded separately:

| Old image fit | Current choice |
| --- | --- |
| Fill | Stretch |
| Contain | Fit |
| Cover | Fill, with explicit clipping if required |
| None | Original, using scale for pixels per point |
| Fit_width / Fit_height / Scale_down | Removed as dedicated modes; choose native sizing and parent frame proposals explicitly. Exact Flutter fitting formulas are not emulated. |

Safe-area padding adds to the inherited native inset; it does not calculate
`max(systemInset, minimum)`. Background does not imply clipping. Weighted
content-sized children can leave part of their share unused, and native default
spacing is not Flutter's fixed zero spacing. Leading/trailing placement follows
layout direction, including badges and the replacement for positioned layers.

The old Scaffold bottom-sheet slot was persistent layout content. Its
replacement is a fixed Body child; actual modal presentation is separately
controlled through Sheet. An overlay on a viewport follows that viewport's
bounds, while a Body overlay follows the complete bounded page.

## Evidence and limits

Mappings were checked against the baseline signatures and renderer, current
OCaml declarations/constructors, Swift renderer files and real Gallery fixture
registrations. Headless test metadata has no invented visual scenario. Shared
Gallery components demonstrate a family, not every wrapper/parameter combination.

The previous turn's complete macOS regression passed 482 tests in 106 suites.
The referenced Swift source and test hashes still match that run, so this review
does not repeat the suite. Existing tests cover native image sizing/loading,
attributed text, symbols, animation, layout, live page resize/scroll retention,
and actual OCaml callbacks. The separate typed viewport gate also passes: valid composition compiles,
while four axis/bounds violations and two unkeyed collection cases are rejected
for the intended type mismatch. Evidence is recorded in
`_build/validation/swiftui-layout-content-api-review.json`.

Physical-iOS rendering and interaction remain pending. These mappings do not
establish every image codec, parameter combination, accessibility behavior or
complete widget acceptance. No renderer implementation changed in this review.
