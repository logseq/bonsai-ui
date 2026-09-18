# Native runtime boundary

The [public C header](../native/src/bonsai_swiftui_native.h) defines native ABI
**4.0**. The renderer protocol is **BSFR 9.0**. `NativeRuntime.open` checks both
exactly before creating a runtime. Swift imports the header through
`CBonsaiSwiftUI`; no Flutter Native Assets package or Dart wrapper is involved.

## Exported surface

The public symbol family is `bs_*`: ABI/protocol version queries, runtime
creation, pump, presentation success/rejection, last-error retrieval,
output-buffer release, outstanding-buffer diagnostics and runtime destruction.
Status and error codes have fixed-width Int32 representations. No per-node
rendering operation crosses the C boundary. Complete-object and App-bundle
audits reject the retired `bf_*` exports.

`bs_output_buffer` contains the data pointer, byte length, presentation ID,
renderer revision, status and error code. Swift validates status agreement,
length/pointer consistency, configured bounds and Int64-bounded identities,
then copies bytes into owned Data. A deferred `bs_buffer_free` runs on success
and thrown validation errors. No native pointer escapes into a SwiftUI view.

A returned allocation belongs to its runtime until released. Destroy frees
remaining owned allocations and invalidates the raw C pointer. Raw pointer
reuse after destruction is invalid. The public Swift wrapper instead keeps
its state on the serial queue, clears the handle on closure, and makes repeated
or concurrent `close` calls safe without destroying the pointer twice.

## Startup and concurrency

The Swift wrapper accepts a nonempty UTF-8 entrypoint of at most 255 bytes,
without NUL, and an application payload of at most 1 MiB. It creates the
versioned `BSR1` startup envelope and asks the embedded entrypoint registry to
open the application. An occupied runtime slot or invalid/missing entrypoint
fails; another owner is not silently replaced.

All native calls run on a private process-wide serial DispatchQueue. A single
operation does not suspend while it owns native state. This keeps pumps,
presentation calls and closure ordered while MainActor owns UI presentation.
The optional Eio Worker Domain remains an internal OCaml service owner; it does
not call this Swift boundary.

## Presentation and monotonic time

A successful pump returns a positive presentation token, including no-diff
work. At most one token is outstanding. Success and rejection must match its
identity and revision; a second pump cannot skip that barrier. Native monotonic
time samples must be nonnegative and nondecreasing. Renderer revisions and
presentation identities are separate counters.

`BonsaiSession` stages output, coordinates native presentation and acknowledges
or rejects the exact candidate. Fatal native failures close the wrapper's
owned runtime. Session task identities prevent delayed cleanup or responses
from affecting a newly started session. See [lifecycle](lifecycle.md).

## Build and audit

Each example links its own OCaml complete object, runtime and extracted C
bridge into a SwiftUI App. `verify_complete_object.sh` validates platform,
architecture, minimum version, ABI symbols and the native startup symbol
before linker dead stripping. `verify_app_bundle.sh` validates the linked App,
privacy resource and permitted system dependencies. `verify_ios_bundle.sh`
additionally checks signatures and provisioning authorization. See
[Apple packaging](packaging.md).

The supported destinations are macOS 26+ arm64 and physical iOS/iPadOS 26+
arm64. Device and Mac objects are not interchangeable, and Simulator is
unsupported. Passing object or signature checks does not establish physical
interaction, performance or screenshot acceptance.


## Terminal shutdown transport

ABI 4.0 adds `bs_runtime_shutdown_pump` with the same clock/input/buffer ownership
conventions as `bs_runtime_pump`. Swift requires the exact ABI; there is no old
ABI fallback. A successful shutdown pump retires a pending presentation token
without acknowledgment and permanently disallows ordinary pumping. Its inputs
must be application events/responses naming the last displayed revision; UI,
environment and host-response records are rejected atomically.

The output reserves no presentation token. Its `presentation_id` is zero and
`revision` remains the last displayed revision. `data` contains `BSSD`, a
little-endian UInt32 count (zero or one), then an optional request record:
UInt64 positive request ID, UInt32 byte length, and at most 1 MiB opaque bytes.
ABI identity versions this private transport envelope. Swift validates the full
record before provider dispatch and frees every C-owned output buffer.

The runtime drains worker completions and Bonsai effects without renderer
reconciliation or after-display lifecycle calls. Application requests are
committed independently; host effects cannot gain presentation permission from
this operation. Raw callers must still destroy their handle when done. The
public application shutdown handle owns deadline, provider selection and final
reply delivery, then closes its serialized `NativeRuntime`.
