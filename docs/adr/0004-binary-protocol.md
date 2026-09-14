# ADR 0004: Generated transactional binary protocol

- Status: Accepted
- Date: 2026-07-25

## Context

The hot path needs compact incremental frames, deterministic cross-language
decoding, and validation of untrusted native buffers. JSON, Marshal, raw OCaml
values, S-expressions, and string-keyed property maps do not satisfy these
requirements.

## Decision

Maintain one declarative schema in `protocol/schema.sexp`. Generate numeric
kind, property, event, operation, host-effect, and error IDs plus OCaml and
Dart codecs and documentation tables.

Frames use a fixed 48-byte little-endian header with magic, major/minor
version, header size, frame kind, flags, runtime epoch, base and target
revisions, payload length, optional CRC32C, and a reserved field.

Payload operations are length-delimited and kind-specific. Property updates
carry a generated changed-field bitset followed by fields in schema order.
The first frame is a full snapshot. Normal frames are incremental and require
an exact base-revision match.

Dart applies a complete decoded frame to a shadow `NodeStore`, validates it,
then commits once. Any failure rolls back the entire frame. Revision mismatch
requests a full snapshot.

## Consequences

Schema regeneration is a required clean-tree CI check. Unknown required kinds
or fields fail safely; capability negotiation prevents unsupported native
extensions from entering normal frame application.

Readable S-expression and JSON dumps remain available only for fixtures and
debugging. They are not accepted by the production C ABI.

