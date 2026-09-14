# Sliver App Bar Construction Validation

## Problem

`Widget.Sliver.app_bar` accepts values that the wire contract rejects. In
particular, the OCaml constructor currently accepts `toolbar_height = 0.`
because it checks for a finite non-negative value, while both protocol
decoders require a strictly positive toolbar height. It also accepts a pair
where `collapsed_height > expanded_height`, while the Dart and OCaml protocol
decoders reject that ordering.

The failure is delayed until frame encoding or host decoding instead of being
reported at the public OCaml construction boundary. A value that appears to be
a valid `Sliver.t` can therefore invalidate presentation of the containing
frame. The public constructor, OCaml wire encoder and decoder, Dart wire encoder
and decoder, and Dart renderer do not currently enforce one shared invariant.

## Decision

The public OCaml constructor is the first authoritative validation boundary,
and keep wire and renderer validation as defense in depth.

The shared contract is:

- `toolbar_height` is finite and strictly positive.
- `expanded_height` and `collapsed_height`, when present, are finite and
  non-negative.
- when both heights are present, `collapsed_height <= expanded_height`.
- `collapsed_height`, when present, is at least `toolbar_height`.
- `elevation`, when present, is finite and non-negative.
- `snap = true` requires `floating = true`.
- `bottom`, when present, is created by `Widget.preferred_size`.

Invalid public inputs raise `Invalid_argument` before a widget node is created.
Equivalent checks apply when encoding and decoding untrusted wire values so
private or foreign frame construction cannot bypass the contract.
This decision does not expand the `SliverAppBar` property surface.

## Alternatives considered

### Rely on the Dart decoder

The Dart decoder already rejects some invalid combinations, but this turns a
local OCaml programming error into a rejected renderer frame and leaves the
public constructor contract misleading.

### Clamp or normalize invalid heights

Silently converting zero toolbar height or raising `expanded_height` to
`collapsed_height` would hide application mistakes and create behavior that
differs from the declared values. Invalid inputs should be rejected.

## Consequences

- OCaml construction rejects zero, negative, NaN, and infinite toolbar heights,
  invalid explicit-height ordering, invalid elevation, and `snap` without
  `floating`.
- OCaml and Dart codec tests exercise the height invariants in encode and decode
  directions, while renderer validation uses the same inequalities.
- Valid app-bar combinations still round-trip through both codecs, and existing
  rendering and multi-slot tests remain green.
- Applications relying on zero toolbar height or inverted explicit
  heights will fail at construction and must express the intended layout with
  supported widgets.
- Repeating checks across construction, codec, and renderer layers requires a
  focused test matrix to prevent future drift.
