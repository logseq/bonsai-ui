# Sliver Wire Boundary Validation

## Problem

Several public sliver-related OCaml values are less constrained than their
wire representation or Flutter consumer:

- `overscan` is checked only for non-negativity, but the protocol stores it as
  `u32`.
- explicit `Scroll_view.cache_extent` is not checked for finiteness or
  non-negativity.
- automatic cache extent multiplies `overscan` by an item extent without
  checking that the result remains finite.
- `Sparse_extent_transition.t` exposes its record representation, allowing
  callers to bypass `Sparse_extent_transition.create` and provide durations
  outside `u32`.

These values can produce a valid-looking OCaml widget that fails only during
frame encoding, is rejected during host decoding, or reaches Flutter with an
invalid cache extent. Validation timing depends on which construction path was
used.

## Decision

Wire-safe values are enforced at every public OCaml construction boundary, with
codec checks for untrusted frames.

The contract is:

- `overscan` is in `0 .. 0xffffffff`.
- explicit and derived cache extents are finite and non-negative; zero remains
  valid and disables additional cache pixels.
- multiplying `overscan` by fixed or default item extent must yield a finite
  result.
- sparse transition durations are in `0 .. 0xffffffff`.

`Sparse_extent_transition.t` is abstract in the public interface, so valid
instances are created through `Sparse_extent_transition.create`. Independently
validate transition values inside `Sliver.varied_extent` and the codec as
defense in depth against private or decoded construction.

The OCaml and Dart codec encode/decode paths apply symmetric cache-extent
validation, and the renderer enforces the same contract. Protocol field types
are unchanged.

## Alternatives considered

### Validate only in the codec

Codec-only validation delays a local API error until frame production and
makes widget construction appear successful.

### Clamp values to the wire range

Clamping changes requested prefetch behavior silently. An out-of-range value
is a programming error and should be rejected explicitly.

### Keep the transition record public and document `create`

Documentation cannot enforce the invariant, and callers can continue to create
invalid records that fail later. The project does not require representation
compatibility for this type.

## Consequences

- Fixed and varied constructors reject overscan outside `u32`, transition
  construction rejects durations outside `u32`, and direct transition record
  construction is no longer public.
- Both `Scroll_view` constructors reject non-finite or negative explicit cache
  extents, and derived cache overflow fails before node creation.
- OCaml and Dart codec tests cover invalid cache values in both directions and
  exercise `0`, `0xffffffff`, and finite derived boundaries.
- Existing valid cache derivation and transition animation tests remain green.
- Abstracting `Sparse_extent_transition.t` removes direct record construction
  and field access; callers must use the constructor and any intentional
  accessors exposed by the API.
- Very large but technically finite cache extents remain capable of excessive
  memory or layout work. This decision enforces representation safety, not an
  application policy maximum.
