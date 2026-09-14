# Material Only Overlapping Components

## Problem

The public OCaml UI surface currently offers three Material-oriented component
paths from both the renderer-independent `Widget` namespace and the `Material`
namespace:

| Generic path | Material path | Current relationship |
| --- | --- | --- |
| `Widget.button` | `Material.elevated_button` and the other Material button variants | Separate logical node kinds and renderer branches; the generic branch renders a Flutter `ElevatedButton` |
| `Widget.text_input` | `Material.text_field`, `Material.search_bar`, and `Material.Search_anchor` | Separate logical node kinds over the same retained text-editing state model |
| `Widget.Sliver.app_bar` | `Material.App_bar.sliver` | Exact alias; the generic declaration explicitly describes a Material 3 Expressive app bar |

These paths make the namespace boundary misleading. `Widget.button` appears to
be renderer-independent but selects a Material control in Flutter.
`Widget.Sliver.app_bar` exposes Material 3 Expressive variants, shapes, and
density from the generic sliver module. Applications must choose between two
entry points without a meaningful product distinction, and tests frequently
use the generic button simply as an event-bearing node.

The separate generic button and text-input paths also carry their own logical
node variants, kind tags, wire-schema entries, generated codec cases, renderer
builders, and tests. Keeping them after applications migrate would leave
unreachable protocol and renderer surface. The app-bar wire node remains
necessary, but its public OCaml ownership belongs to `Material.App_bar` rather
than `Widget.Sliver`.

## Proposal

Make `Material` the only supported public OCaml namespace for buttons, text
fields, search inputs, and Material 3 Expressive app bars.

Remove `Widget.button` from `widget.mli` and `widget.ml`. Product call sites
that require a visible button migrate to the appropriate `Material` button
variant. Runtime and reconciliation tests that require only a generic press
binding use `Widget.pressable`, which remains the design-independent primitive
for an arbitrary pressable child. Remove the generic `Button` logical node,
its kind tag and props, the `button` wire-schema entry, generated codec output,
and the Flutter `_buildButton` renderer branch after all consumers migrate.
Do not retain an alias, deprecated declaration, fallback, or compatibility
constructor.

Remove `Widget.text_input` from the public and implementation surfaces.
Applications and integration fixtures migrate to `Material.text_field`,
`Material.search_bar`, or `Material.Search_anchor` according to their visible
semantics. Add `?read_only:bool` and `?autofocus:bool` to
`Material.text_field`, both defaulting to `false`, before removing the generic
constructor. Carry both values through the Material text-field logical props,
wire schema, codec, and Flutter renderer. This preserves the existing ability
to select and copy non-editable text and to request initial focus without
retaining a generic component solely as a capability escape hatch. Once no
consumer remains, remove the generic `Text_input` logical node, its kind tag
and props, the `text_input` wire-schema entry, generated codec output, and the
default `TextInputHost` renderer branch. Keep the shared text-editing value,
revision, session, event, and renderer-resource machinery because every
Material text input still depends on those contracts.

Move the public scrolling app-bar API and its `variant`, `shape`, and `density`
types into `Material.App_bar`. Remove `Widget.Sliver.app_bar` and its app-bar
types from the public `Widget.Sliver` signature. `Material.App_bar.sliver`
should call an implementation-only constructor that returns
`Widget.Sliver.t`; it must no longer be an alias to a public generic
constructor. Retain the internal sliver-app-bar logical and wire node because
the Material component still needs a sliver-specific representation, but name
and document its private ownership as Material. Existing wire kind numbers
must not be reassigned to unrelated components.

Keep `Widget.text`, `Widget.icon`, layout containers, scrolling primitives,
`Widget.gesture`, and `Widget.pressable` unchanged. They express content,
layout, or design-independent interaction rather than a competing Material
component. Likewise, `Widget.decorated_box`, `Widget.overlay`, and generic
sliver lists remain compositional primitives even though callers can combine
them into card-like, dialog-like, or list-like experiences.

Migrate maintained examples, benchmarks, OCaml tests, Flutter integration
fixtures, and documentation in the same breaking change. Select replacements
by test or product intent instead of mechanically turning every generic button
into an elevated Material button. A visible product button uses the appropriate
`Material` variant. A test, benchmark, or compound widget that needs only an
arbitrary child and a press event uses `Widget.pressable`. Update generated
protocol artifacts from the schema source and remove tests that protect only
the deleted paths. No backward-compatible OCaml or wire decoding route is
introduced.

## Decision

Adopt Material-only ownership for the overlapping visible components. Remove
the generic button and text-input node families completely, retain
`Widget.pressable` as the design-independent interaction primitive, and make
`Material.App_bar` the sole public owner of the scrolling Material app bar.
Keep wire kind IDs 49 and 50 unused rather than introducing compatibility
decoders or assigning them to new components.

## Alternatives considered

### Keep both namespaces and document a preference

Marking `Material` as preferred would not make `Widget.button`
renderer-independent, would leave the exact app-bar alias in two namespaces,
and would preserve duplicate node and renderer maintenance indefinitely.

### Remove only the public declarations

The generic button and text-input logical nodes, protocol kinds, renderer
builders, and tests would become unreachable implementation inventory. Keeping
those paths conflicts with the repository policy to remove obsolete paths
instead of adding compatibility layers.

### Implement Material components through generic nodes

A generic button or text-input node could accept Material style variants and
decoration fields. That would move design-system policy into `Widget`, make
generic props depend on Material evolution, and reproduce the current
namespace leak in the shared node model.

### Retain `Widget.text_input` as the sole low-level exception

This preserves an undecorated input escape hatch and avoids migrating the
standalone text-input example. It also leaves applications with two public
input component families and keeps an otherwise redundant logical, protocol,
and renderer branch. The proposal instead moves required behavior into
Material text components while retaining the shared non-widget text-editing
model.

### Remove `Widget.pressable` with `Widget.button`

`Widget.pressable` is an arbitrary-child interaction primitive with explicit
press feedback rather than a Material button component. Removing it would
prevent design-independent compound interactions and would broaden this
decision beyond overlapping Material components.

## Acceptance criteria

- The public `Widget` interface contains no `button`, `text_input`, sliver app
  bar constructor, or Material app-bar option types.
- `Material` is the only public OCaml namespace that constructs visible
  buttons, text fields, search inputs, and Material 3 Expressive app bars.
- Material input APIs preserve every capability explicitly selected in the
  answers below without depending on a public generic input component.
- The generic button and text-input logical nodes, kind tags, schema props,
  generated wire cases, renderer registrations/builders, and path-specific
  tests are absent. Their former numeric wire kind IDs are not reused for
  unrelated components.
- The sliver app-bar logical and wire representation remains available only
  through an implementation-only Material constructor returning
  `Widget.Sliver.t`; `Material.App_bar.sliver` is not a public alias back into
  `Widget.Sliver`.
- Repository searches find no maintained call site of `Widget.button`,
  `Widget.text_input`, or `Widget.Sliver.app_bar`.
- Examples, benchmarks, tests, and documentation use Material components for
  visible Material controls and `Widget.pressable` only for genuinely generic
  press interaction.
- Focused OCaml UI/runtime tests, Flutter renderer tests, integration tests,
  generated protocol checks, `dune build @all`, `spec-dev-tool check --all`,
  and `git diff --check` pass.

## Risks

- This is intentionally source-breaking for every application that uses one
  of the three generic paths. No deprecation window or compatibility alias is
  provided.
- Deleting the generic button and text-input wire kinds makes frames produced
  by old OCaml clients unsupported by the new renderer. The old IDs remain
  unavailable for reuse, but the old payloads are not decoded through a
  fallback.
- `Widget.text_input` currently exposes `read_only` and `autofocus`, while
  `Material.text_field` does not. Removing it before deciding whether to add
  those arguments would silently remove application capabilities.
- A bare generic text input can be useful for a custom design system. This
  proposal intentionally makes such a design system use a native extension or
  add its own explicit component family rather than treating a Flutter default
  input as renderer-independent.
- Core runtime tests that switch wholesale to Material controls could couple
  reconciliation and event tests to Material node details. Intent-based use of
  `Widget.pressable` avoids that coupling where visual component semantics are
  irrelevant.
- Moving the app-bar option types changes paths such as
  `Widget.Sliver.app_bar_variant` to Material-owned types and requires an
  atomic update of downstream annotations and constructors.

## Consequences

- `Material.text_field` is now the complete replacement for ordinary Material
  text entry, including read-only and autofocus behavior with backward-neutral
  defaults for existing Material callers.
- Visible application buttons now declare a Material variant instead of
  inheriting an accidental `ElevatedButton` from the generic namespace.
- `Widget.pressable` remains the canonical primitive for runtime tests,
  benchmarks, and compound controls whose contract is press interaction rather
  than Material button presentation.
- `Material.App_bar` now solely owns the public Material 3 Expressive app-bar
  vocabulary, while `Widget.Sliver` retains only design-independent sliver
  composition.
- The generic button and text-input protocol and renderer branches are deleted;
  shared event dispatch and text-editing infrastructure remain exercised
  through `Widget.pressable` and Material text inputs respectively.
- Downstream applications must update all three removed generic API paths in
  the same source-breaking release.

The complete OCaml test suite and build pass. The Flutter renderer package
passes analysis and all 496 tests, and the real OCaml FFI integration workspace
passes analysis and all 14 tests. Generated protocol and fixture checks,
viewport type checks, OCaml and Dart formatting for the changed files,
`spec-dev-tool check --all`, and `git diff --check` also pass.

## Questions

None. The user confirmed that `Material.text_field` must retain both
`read_only` and `autofocus`, and that generic press-only tests and benchmarks
must use `Widget.pressable` while visible business buttons use an appropriate
`Material` button variant.
