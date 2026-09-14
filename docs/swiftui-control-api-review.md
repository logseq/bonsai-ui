# Native control API review

The [inventory](swiftui-widget-inventory.json) records individual mappings for
29 control values and 42 presentation/selection constructors from the baseline.
Each value links its current declaration, renderer, tests and the native fixture
that embeds the corresponding real Gallery component.

| Baseline family | SwiftUI-oriented replacement | Behavioral change |
| --- | --- | --- |
| Material/Cupertino buttons and FABs | `View.button`, Label and control size | Unit actions remain; native style and parent layout own appearance and placement. |
| Checkbox, switches and Toggle_button | `View.toggle` | Controlled Boolean requests; the baseline has no mixed-state checkbox. |
| Radio and single segmented selection | `View.Picker` | Optional selected Int64, stable choice IDs and per-choice enablement. |
| Multiple segmented selection | Keyed Toggles bound to one OCaml set | Each requested Bool updates membership; the selection-array callback is removed. |
| Slider and range slider | `View.Slider` | Domain-unit step replaces divisions; axis replaces vertical visual variants. Continuous and final requests remain distinct. |
| Chips and tags | Button, Toggle and sibling removal Button | Selection requests carry Bool; removal remains a separate Unit action. |
| Progress and loading | `View.progress` | Optional fraction distinguishes determinate and indeterminate progress; Linear/Circular select shape. |
| Button groups | Stack/flow, Picker, Toggle, Scroll and Menu composition | Selection mode is represented by the chosen control instead of a group flag. |

Disabled controls publish no input binding. Picker selection can be absent;
signed IDs, including zero and negative values, are valid. OCaml owns accepted
selection and may reject a native request. Toggle handlers apply the requested
value rather than invert potentially stale state. Tag removal sits outside the
Toggle label so it remains an independent action.

Material tonal/elevated/connected geometry, wavy and centered tracks, group
shape flags and fixed FAB dimensions are deliberately removed. Applications
choose native style, semantic control size and ordinary layout. Flow wraps into
horizontal rows; the old axis-dependent vertical wrapping is not reproduced.
Contained loading uses background/padding composition. Slider labels are
required; range/domain validation occurs when constructing the slider, not
when creating its raw interval value.

Existing focused tests pass: 28 tests in seven suites, 17.732 seconds. They cover
native controls, disabled/admission behavior, selection requests, autofocus,
slider/progress semantics and actual OCaml/Gallery callbacks. This review adds
no renderer code and does not establish every layout variant or physical-iOS
interaction. Evidence and source hashes are in
`_build/validation/swiftui-control-api-review.json`.
