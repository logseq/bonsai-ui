# Binary protocol

The active renderer protocol is **BSFR 5.0**. It is little-endian,
length-delimited and generated from [schema.sexp](../protocol/schema.sexp).
Swift and OCaml require an exact version match. There is no old-magic or
old-version decoder. Native ABI 3.0 is a separate contract.

## Frame header

Every frame starts with this fixed 48-byte header:

| Offset | Width | Field |
| ---: | ---: | --- |
| 0 | 4 | Magic `BSFR` (`0x52465342` as little-endian UInt32) |
| 4 | 2 | Protocol major, 4 |
| 6 | 2 | Protocol minor, 0 |
| 8 | 2 | Header size, 48 |
| 10 | 1 | Frame kind |
| 11 | 1 | Flags, zero |
| 12 | 8 | Runtime epoch |
| 20 | 8 | Base revision |
| 28 | 8 | Target revision |
| 36 | 4 | Payload byte length |
| 40 | 4 | Checksum field, zero |
| 44 | 4 | Reserved, zero |

The Swift output decoder accepts full snapshots and incremental frames. It
rejects wrong magic/version, noncanonical header fields, inconsistent lengths,
invalid identities, unsupported kinds, truncated data and excessive payloads.
The schema also identifies handshake, input event-batch and runtime-error frame
kinds; they are not interchangeable with output view frames.

## Bounds and primitive encodings

Current schema limits are 16 MiB per frame, 1 MiB per string or application
payload, one million operations and one million nodes. Individual view and
service schemas impose additional bounds. Counts and lengths are validated
before consuming their payloads.

Fixed-width integers use little-endian representation. Runtime identities and
revisions obey their positive/signed-Int64 bounds; semantic item IDs may use a
separate signed domain, such as Menu item Int64 values. Strings carry a UInt32
byte length and strict UTF-8. Booleans are exactly 0 or 1. Optional values use
the presence representation specified by their codec. Floating-point values
are validated by their typed property contract; a layout's unbounded maximum
uses an explicit limit case rather than an infinite floating-point payload.

## View transactions

Each operation contains a one-byte opcode, UInt32 body length and typed body.
Begin_frame must occur first and End_frame last; both have empty bodies.
Between them the active schema defines node creation, property/binding updates,
child/root assignment, node drops, host requests, runtime notifications,
application requests and application-theme updates.

`WireFrame` validates the envelope and operation order. `FrameState.staging`
and node/property decoders validate the complete candidate, including property
masks, bindings, child contracts, identity uniqueness, references, graph shape
and application metadata. No candidate mutation becomes visible on failure.
Full/incremental revision handling is tied to the last presented state.
Retired Material/Cupertino/Sliver node codecs are removed rather than treated as
aliases; the active schema and generated ID reference define accepted kinds.

New view capabilities use SwiftUI composition and typed payloads. Detailed
contracts cover [text](swiftui-text-input.md), [collections](swiftui-collections.md),
[navigation](swiftui-navigation-stack.md), [menus](swiftui-menu.md),
[presentation](swiftui-sheet.md), and the other families in the
[widget inventory](swiftui-widget-inventory.md).

## Inputs and asynchronous responses

Swift's production EventBatch encoder emits typed UI input, environment samples,
host responses and opaque application messages. Runtime-control messages use
their control ownership rather than pretending to be a node's event handler.
The OCaml decoder validates the complete batch before dispatching effects.
Stale epochs, revisions, handlers and sequences cannot address replacement
handlers. Coalescing is event-specific; action and control responses are not
silently collapsed into a single callback.

Host requests and responses retain monotonic request identities and bounded
payloads. They execute only after presentation acknowledgment. Cancellation and
runtime replacement fence pending work and late responses. See the
[host-service transport](swiftui-host-services.md) and
[application bridge](application-platform.md).

## Generation and verification

`make protocol-generate` updates OCaml/Swift IDs and the readable reference.
`make protocol-check` checks generated outputs without accepting stale files.
`make protocol-fixtures-generate` uses OCaml for output fixtures and the real
Swift encoder for input fixtures; `make protocol-fixtures-check` verifies both.
See [input fixtures](swiftui-input-fixtures.md). Historical Dart fixture
producers and their outputs have been removed.

Native runtime tests exercise real OCaml full/incremental frames, typed inputs,
presentation rejection/recovery, lifecycle and resource ownership. Malformed
transaction tests exercise validation and atomic rollback. A passing codec or
frame test alone does not establish native layout, interaction or device
acceptance for a widget.
