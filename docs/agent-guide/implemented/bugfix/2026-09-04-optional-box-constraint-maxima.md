# Optional Box Constraint Maxima

## Problem

`Ui.Layout.Box_constraints.create` currently defaults omitted `max_width` and
`max_height` values to `Float.max_float`. The value is serialized as a required
`f64`, decoded by Dart as `double.maxFinite`, and passed directly to Flutter's
`BoxConstraints`.

Flutter distinguishes a finite maximum from an unbounded maximum. Consequently,
a descendant such as `Align` can expand to approximately `1.8e308` rather than
remaining shrink-wrapped. In a vertical scroll view containing a constrained box
with only `min_height`, this can place visible text and semantics near `9e307`,
far outside the viewport even though the nodes exist.

The public model cannot currently distinguish an omitted maximum from an
explicit finite maximum. Using the largest finite float as a sentinel leaks an
incorrect layout meaning across the protocol boundary.

## Proposal

Represent both maximum constraints explicitly as optional finite floats across
the complete OCaml-to-Flutter path:

- change `Layout.Box_constraints.t`, `Widget.Constrained_box`, and
  `Wire_frame.Constrained_box_props` so `max_width` and `max_height` are
  `float option`;
- make omission produce `None` and retain `Some value` for an explicit finite
  maximum;
- encode and decode each maximum with the existing optional-`f64` wire format,
  including incremental property patches;
- reject negative, NaN, or infinite present maxima and reject a present maximum
  below its corresponding minimum;
- model the maxima as nullable doubles in Dart and map `null` to
  `double.infinity` only when constructing Flutter `BoxConstraints`; and
- remove every `Float.max_float`/`double.maxFinite` fallback for constrained-box
  maxima rather than preserving the old representation.

Increment the renderer protocol minor version from `2.26` to `2.27` because the
constrained-box payload and patch bytes change incompatibly. Regenerate all
schema-derived protocol artifacts and update version assertions and protocol
documentation. Keep native ABI version `2.0` and `SDK_ABI_VERSION=2` unchanged:
the C ABI and native entry-point contract do not change, and the independently
validated renderer protocol version identifies this wire incompatibility.

Cover public construction, validation, logical equality/reconciliation,
full-frame and patch round trips in OCaml and Dart, renderer conversion, and a
widget regression shaped as vertical scroll view -> constrained box with only a
minimum height -> align -> text. The regression must prove finite rendered
geometry and text within the viewport.

## Decision

Implement the proposal exactly as written. Optional maxima are the only
unbounded representation, protocol `2.27` is the compatibility boundary, and
native ABI `2.0` remains unchanged because no C entry point or ownership
contract changes.

## Alternatives considered

### Preserve `Float.max_float` and translate it in Dart

The renderer could special-case `double.maxFinite` as infinity. That retains a
sentinel in the public and wire models, makes an explicitly requested maximum
indistinguishable from omission, and leaves malformed/non-OCaml producers with
an undocumented magic value. It is not selected.

### Serialize `double.infinity`

Encoding infinity would more closely resemble Flutter's internal value but
would violate the protocol's finite-number validation and allow non-finite data
through layers that deliberately reject it. Optional finite maxima keep absence
separate from numeric values.

### Add a compatibility decoder for protocol 2.26

Accepting both required and optional encodings would require version-dependent
property decoding and preserve an obsolete sentinel path. The renderer and
native producer require an exact protocol-version match, so the protocol minor
bump is the intended incompatibility boundary.

## Acceptance criteria

- `Box_constraints.create ()` contains `None` for both maxima, while explicit
  finite maxima remain `Some value` through logical-node construction.
- OCaml and Dart full-frame and property-patch codecs round-trip absent and
  present maxima, including `None <-> Some` patch transitions.
- OCaml construction and both wire decoders reject negative, NaN, infinite, or
  minimum-exceeding present maxima.
- The Flutter renderer maps nullable maxima to `double.infinity` and preserves
  explicit finite maxima.
- A vertical-scroll regression with a minimum-height-only constrained box,
  `Align`, and text produces finite render geometry with text inside the
  viewport; no render tree value approximates `1.7976931348623157e+308`.
- Protocol version `2.27`, schema-generated artifacts, cross-language fixtures,
  public documentation, focused tests, full relevant OCaml and Flutter checks,
  `spec-dev-tool check --all`, and `git diff --check` pass.
- No compatibility fallback, migration path, or Dune-file change is added.

## Risks

- Protocol `2.27` is intentionally incompatible with constrained-box payloads
  emitted for `2.26`; exact version negotiation must reject mixed components.
- Optional fields add presence bytes to full constrained-box payloads and can
  change property-patch sizes.
- Public OCaml callers that directly inspect private constraint values must
  handle `float option`; this source break is intentional and has no
  compatibility shim.
- The layout regression depends on Flutter render-object geometry and must avoid
  assertions tied to font rasterization or platform-specific pixel details.

## Consequences

- Omitted OCaml maximum constraints now remain absent through widget identity,
  reconciliation, frame encoding, Dart decoding, and store updates.
- Flutter receives `double.infinity` only at `BoxConstraints` construction;
  explicit finite maxima pass through unchanged.
- Full-frame and incremental constrained-box payloads use optional-`f64`
  encodings and reject invalid present maxima on both sides of the wire.
- Protocol identifiers and generated fixtures now declare version `2.27`, while
  the independently validated native ABI stays at `2.0`.
- Public, codec, reconciliation, renderer-geometry, protocol-generation,
  complete OCaml, complete Flutter, native package, static-analysis, and native
  bridge tests pass. The repository-wide Dart formatting audit still reports
  the pre-existing unrelated `test/mail_outliner_transition_test.dart`; every
  file changed by this decision passes its targeted format check.

## Questions

None. The objective fixes the public representation, wire semantics, version
boundary, renderer mapping, and required regression coverage.
