# Architecture

BonsaiSwiftUI renders OCaml/Bonsai applications with SwiftUI on physical
iOS/iPadOS 18.0+ arm64 and macOS 26.0+ arm64. OCaml owns application state;
Swift owns presentation and native resources. The Flutter/Dart source tree has
been removed. Package and OCaml module renaming remains unfinished: current
`bonsai_swiftui` library identifiers describe this worktree, not a second backend.

## Runtime pipeline

```text
OCaml Bonsai computation -> immutable View.t -> mounted identity/reconciliation
    -> BSFR 4.0 binary frame -> bs_* ABI 3.0 -> NativeRuntime serial queue
    -> BonsaiSession / validated FrameState -> SwiftUI view hierarchy
```

Typed events travel in the opposite direction. Swift sends runtime epoch,
node and handler identities, displayed revision, sequence and typed payload.
OCaml validates the batch, runs the relevant effects, flushes Bonsai and
reconciles the next candidate. Swift contains no Mail reducers or canonical
selection model.

There are three distinct structures: immutable OCaml views, the runtime's
mounted identity tree, and SwiftUI's native presentation hierarchy. A compatible
update retains native node resources; removal, incompatible replacement or a
new runtime lifetime disposes them. SwiftUI owns layout and rendering. AppKit
and UIKit adapters handle capabilities such as native text editing where a
plain SwiftUI binding cannot express the required contract.

## Native ownership and scheduling

One active application runtime and one application window are supported.
`NativeRuntime` serializes C calls on its private process-wide DispatchQueue.
`BonsaiSession` coordinates the visible view tree and native services on
MainActor. OCaml domain 0 owns the Driver, handlers and worker-client endpoint.
The optional OCaml Worker Domain owns Eio service work, SQLite resources and
bounded request/background fibers; it does not call SwiftUI or mutate Bonsai.
See [worker ownership](swiftui-worker.md).

Every successful logical pump reserves a presentation token, including a
no-diff pump. No subsequent logical pump is admitted until that token is
acknowledged or rejected. Renderer revision advances when a frame is emitted.
Native presentation probes coordinate observed layout/visibility with session
acknowledgment; decoding and committing a candidate are not themselves an
acknowledgment. Rejected candidates force recovery from the presented state.

The application view currently runs an asynchronous refresh task with a 16 ms
active/visible delay and a 250 ms inactive delay. The session prevents logical
pumping while hidden, inactive, busy or awaiting presentation. This is not a
promise of display-synchronized 60 Hz scheduling. Native monotonic samples
advance the OCaml time source during admitted foreground work. Background
execution and timers are not promised. See [lifecycle](lifecycle.md).

## Application and extension boundary

An application owns its OCaml component, native entrypoint, `swift/App.swift`,
resources and `bonsai-swiftui.sexp`. `App.create` receives the application
context and Bonsai graph and returns an `App.View` computation. The context
provides typed handlers, accepted environment values and asynchronous services.
The CLI generates Apple Xcode hosts and stages the selected complete object;
it preserves application-owned sources. See [packaging](packaging.md).

Typed `Native_widget` registrations pair an OCaml schema with a
`BonsaiNativeViews` Swift implementation. Opaque payloads remain bounded and
versioned. Swift owns local view/resources; events return through the same
revision- and lifetime-scoped path as core controls. Core rendering does not
import application modules. See [custom views](custom-widgets.md).

Host commands stage atomically with their frame and run after presentation
while active and visible. They resolve the owned window rather than choosing a
global key window. Responses, cancellation, queue bounds and late completion
fencing are described in [host services](swiftui-host-services.md).

## Library and identity boundaries

The current OCaml libraries separate UI definitions, protocol codecs, runtime,
FFI and test support. UI definitions do not depend on FFI or packaging; the
runtime owns reconciliation and Bonsai integration; FFI owns the C boundary.
Version-sensitive Bonsai operations remain in `Bonsai_runtime_adapter`.
The public facade and these libraries still need the agreed namespace rename.

The virtual spec library groups identities by ownership. Private primitive
representations require explicit category-specific constructors/accessors at
wire, ABI, persistence and diagnostic boundaries. Native ABI error codes and
renderer protocol errors are separate domains. Protected spec source changes
require the repository's explicit authorization.

## Validation and unfinished work

Swift validates complete frames before publishing mutations. Malformed
properties, graph references, epochs or revisions cannot partially apply.
Native output is copied into Swift-owned bytes and freed on all wrapper paths;
public Swift closure serializes destruction exactly once. See the
[wire contract](protocol.md) and [native boundary](ffi.md).

The migration remains in progress. UIKit keyboard/environment work, remaining
host services, per-widget physical/Gallery acceptance, Mail visual acceptance,
namespace cleanup and source/SDK publication remain required. The
[widget inventory](swiftui-widget-inventory.md) enumerates baseline public
entries; [implementation evidence](swiftui-implementation.md) records actual
results without treating compilation as physical-device acceptance.
