# Material Linear Progress Indicator

## Problem

`Bonsai_flutter_ui.Material` exposes
`circular_progress_indicator`, but it does not expose Flutter's Material
`LinearProgressIndicator`. Applications that need to communicate progress
across a bounded horizontal region must either use the circular presentation,
assemble a visual approximation from generic layout widgets, or add an
application-specific native widget. Those alternatives lose the standard
Material semantics, animation, theme integration, and platform behavior of the
native Flutter component.

The missing component is intentionally separate from the previously
implemented Material component expansion. That decision explicitly excluded
linear progress so the larger component release remained bounded. Adding it
now requires a small but complete cross-runtime feature: a public OCaml
constructor, a logical widget kind, a protocol identifier and property shape,
OCaml and Dart codec support, Flutter renderer registration, tests, gallery
coverage, and user-facing documentation.

Both Material progress indicators support the same two progress modes:

- omitting `value` creates an indeterminate indicator; and
- supplying a finite `value` in the inclusive range `0.0` to `1.0` creates a
  determinate indicator.

The existing circular constructor enforces that value contract in OCaml, but
the corresponding wire-boundary validation and reusable internal naming need
to remain coherent when a second progress shape is added.

## Proposal

Add a dedicated Material linear progress node and public constructor that maps
mechanically to Flutter's `LinearProgressIndicator`.

The selected public API mirrors the existing circular progress API:

```ocaml
val linear_progress_indicator
  :  ?key:Key.t
  -> ?value:float
  -> unit
  -> Widget.t
```

`value = None` means indeterminate progress. `Some value` means determinate
progress and must be finite and within `0.0 .. 1.0`, inclusive. Invalid values
are rejected before a logical frame is created. The Flutter wire boundary
repeats the same validation so malformed or non-OCaml producers cannot create
an invalid native widget.

The implementation adds `material_linear_progress_indicator` as a distinct
logical node kind with the next unused stable ID, `124`. Its only initial wire
property is `value : optional_f64`. The protocol minor version increments from
21 to 22, and all generated OCaml and Dart protocol artifacts are regenerated
from `protocol/schema.sexp`. No existing numeric ID is changed or reused.

The OCaml widget representation should keep circular and linear progress as
distinct typed node constructors so kind identity, reconciliation,
fingerprinting, debugging, and renderer dispatch remain explicit. Shared
private validation may be extracted to avoid duplicating the finite
`0.0 .. 1.0` check. Public constructors remain separate because circular and
linear progress have different layout behavior and correspond to distinct
Material component roles.

The Flutter renderer registers the new node kind and returns:

```dart
LinearProgressIndicator(value: props.value)
```

The node accepts no children or event bindings. Appearance comes from the
application's Material theme and Flutter's Material 3 defaults. In the current
theme surface, those defaults are derived from the configured `ColorScheme`;
the OCaml API does not yet expose `ProgressIndicatorThemeData`. The initial
component surface does not serialize per-instance styling, Flutter-only style
objects, or animation state.

The gallery adds both determinate and indeterminate linear examples in the
existing Material component section. `docs/material-components.md` documents
both progress modes and the accepted value range.

### Validation and testing

Implementation follows test-driven development and covers the observable
cross-runtime behavior before production code is added:

1. OCaml public-surface tests construct determinate and indeterminate linear
   indicators and identify the logical kind.
2. OCaml validation tests reject negative, greater-than-one, NaN, and infinite
   values while accepting both inclusive endpoints.
3. Widget equality, fingerprints, and reconciliation distinguish linear from
   circular progress and detect changes between absent and present values.
4. OCaml wire tests and Dart codec tests round-trip absent values, `0.0`,
   intermediate values, and `1.0`, and reject malformed non-finite or
   out-of-range wire values.
5. Flutter widget tests prove the renderer creates exactly one native
   `LinearProgressIndicator`, passes through determinate values, preserves
   `null` for indeterminate mode, and rejects children.
6. Protocol generation and cross-language fixtures include node kind 124 and
   protocol minor version 22.

## Decision

Adopt the proposal with the selected minimal public API. Material linear
progress is a dedicated logical node and wire kind with only optional `key` and
`value` inputs. Linear and circular progress retain distinct OCaml node
constructors, wire property variants, Dart property classes, and Flutter
renderer mappings while sharing private finite-range validation. Appearance is
derived from the current Material 3 theme and configured `ColorScheme`; no
per-instance styling, progress theme tokens, Flutter animation controller, or
compatibility path is added.

## Alternatives considered

### Continue using circular progress or generic layout widgets

This leaves the reported capability gap unresolved. A hand-built bar would
duplicate Flutter animation and semantics behavior and would not automatically
track Material theme evolution.

### Replace both progress constructors with one shape parameter

A single `progress_indicator ~shape` constructor would reduce one public name,
but it would also erase useful component identity and require changing the
existing circular API. Circular and linear indicators have different layout
behavior and may gain different semantic options later. Separate constructors
and node kinds match Flutter's model and keep renderer dispatch explicit.

### Reuse the circular node kind with a shape property

Changing node kind 108 from implicitly circular to a shape-tagged node would
alter an existing wire contract and require every producer to emit a new
property. A new stable node kind is smaller, clearer, and avoids assigning two
native widget classes to one historical identity.

### Expose the full Flutter styling surface immediately

Flutter supports component-specific properties such as colors, minimum
height, border radius, track gap, and stop-indicator presentation. Serializing
all of them now would expand the protocol and couple the renderer-independent
OCaml API to Flutter details before concrete application requirements exist.
Color-scheme-driven defaults plus progress value are consistent with the
existing circular API. A future decision may add renderer-independent progress
theme tokens when an application requires customization across indicators.

## Acceptance criteria

- `Ui.Material.linear_progress_indicator` is available with only `?key` and
  `?value` optional parameters and renders Flutter's native
  `LinearProgressIndicator`.
- Omitting `value` produces indeterminate progress; values from `0.0` through
  `1.0` produce determinate progress without changing ownership away from
  OCaml.
- OCaml construction and Flutter wire decoding reject negative,
  greater-than-one, NaN, and infinite progress values.
- The component accepts no child nodes and no event bindings.
- Linear and circular indicators retain distinct logical kinds and renderer
  mappings.
- Protocol node kind 124 and its optional floating-point property are added by
  schema generation, and the protocol minor version is 22.
- OCaml construction, validation, equality, fingerprint, reconciliation, and
  codec tests pass.
- Dart codec, node-store, renderer, malformed-input, and child-validation tests
  pass.
- The gallery demonstrates determinate and indeterminate linear indicators,
  and Material component documentation describes their semantics.
- `dune build @all`, `dune runtest`, focused Flutter tests, protocol generation
  checks, formatting checks, and `spec-dev-tool check --all` pass after
  implementation.
- No file under `spec/`, no Dune file, and no compatibility alias or fallback
  renderer is added or modified.

## Consequences

- Applications can render determinate and indeterminate Material linear
  progress directly from OCaml without a native extension or visual
  approximation.
- Protocol 1.22 adds stable node kind 124 and a single optional floating-point
  property; generated IDs, readable protocol documentation, and all shared
  fixtures now carry the new minor version.
- OCaml construction and both wire decoders reject non-finite and out-of-range
  progress values instead of relying on Flutter's clamping behavior.
- Linear progress receives its width from normal parent constraints, and the
  gallery demonstrates bounded determinate and indeterminate presentations.
- Per-instance colors, geometry, stop-indicator options, theme tokens, and
  animation-controller ownership remain outside the public API.

## Risks

- An indeterminate native indicator continuously animates and therefore needs
  Flutter widget tests that avoid waiting for a fully settled frame.
- A horizontal indicator receives its width from parent constraints. Gallery
  and documentation examples must place it in a bounded layout so callers do
  not mistake parent-layout behavior for component sizing.
- Adding a node kind changes the protocol and iPhoneOS framework ABI release
  inputs. After the framework change is committed and pushed, the iOS SDK
  repository must be regenerated, committed, and pushed separately according
  to the repository workflow.
- Deferring styling keeps the first release small but means applications use
  the Material 3 appearance derived from the configured `ColorScheme`; neither
  per-instance overrides nor OCaml-owned progress theme tokens are in scope.

## Questions

- None. On 2026-08-25, the user selected an initial public API with only `?key`
  and `?value`, matching `circular_progress_indicator`. Per-instance styling
  and OCaml-owned progress theme tokens are deferred.
