# SQLite Worker Todo

SwiftUI hosts the application on physical iOS 18+ arm64 and macOS 26+ arm64.
Simulator is unsupported. OCaml/Bonsai owns UI state, and a dedicated OCaml
Worker owns all SQLite connections, statements, transactions and file operations.
Native Swift code prepares the application data directory and the versioned
`SWC1` startup payload; it does not operate on the database.

## Development

With the project opam environment active, run from the repository root:

```sh
python3 tool/build_swiftui_example.py sqlite_worker
open examples/sqlite_worker/apple/DerivedData/Build/Products/Debug/BonsaiSqliteWorker.app
```

The build discovers the target Apple SDK for Dune system-library lookup and
links the final application against system `libsqlite3`. It does not bundle
another SQLite implementation. The old Flutter host and configuration are
removed.

Run the actual OCaml tests and native persistence scenarios from the repository
root:

```sh
dune build @runtest native/test/libruntime_fixture.dylib
swift test --scratch-path _build/swift --filter actualSQLiteWorker
python3 native/test/test_sqlite_worker_window.py
```

The native window test launches two separate SwiftUI application processes
against one temporary directory containing Unicode path components. The first
adds a Unicode Todo, completes it, refreshes, exercises a missing-file error,
and writes/reads the deterministic 4 MiB file. The second restores the Todo,
reopens it and reads the same file. The test checks database integrity, persisted
rows, every file byte, absence of leftover temporary files, native field disposal
and a 360-point layout. Both processes use the actual production Worker service,
SQLite store and file implementation.

The native staging test also closes and reopens the same database in one
process. Existing OCaml tests cover transactional mutations, revisions,
idempotency, limits, cancellation, temporary-file cleanup, service lifecycle
and stale event rejection. Cancellation remains wired to the native Button;
the standalone window scenario verifies its disabled idle state, while the
controlled cancellation scenarios currently run through the OCaml test harness.

## Storage

Foundation resolves the platform Application Support location. The host creates
an application-specific child directory using its bundle identifier, and passes
absolute paths to the OCaml startup decoder:

- Database: `<Application Support>/<bundle identifier>/todos.sqlite3`.
- File demonstration: `<Application Support>/<bundle identifier>/eio-worker-demo.bin`.

The actual prefix follows the OS, user and sandbox container. The host does not
hard-code a home directory. Storage preparation failures produce a native
unavailable-content view. OCaml validates the startup envelope before opening
SQLite. Runtime shutdown closes the Worker session and SQLite before the next
runtime reopens the file.

The input field uses revision acknowledgments for ordinary typing. Add sends an
explicit correction to clear the title without replacing the native control or
overwriting a newer local edit. The application displays OCaml startup timing
for SQLite initialization, the initial Todo query and total service startup.

## File demonstration

Writes and reads use 64 KiB chunks with a 16 MiB upper bound. Each chunk yields
to Eio so control and cancellation remain runnable. A write uses a request-owned
temporary file and renames it only after success. Cancellation or failure removes
the temporary file and preserves any older completed file. Reads use a bounded
buffer and show a rolling checksum. File operations do not change the database
revision.

The [embedded Worker](../../docs/swiftui-worker.md) preserves host signal
ownership and provides no subprocess manager. It makes no iOS background
execution guarantee.

## Remaining acceptance

The actual OCaml program now cross-builds and links into a signed iOS 18 arm64
SwiftUI Release App, using the system SQLite library. Installation and device
behavior remain unverified; see
[example build evidence](../../docs/swiftui-example-builds.md). Production
CLI/SDK packaging, the old CI consumer/device contracts, physical-device
interaction, VoiceOver and screenshot acceptance remain open. Historical
Flutter/iOS 15 packaging and DataScript device results do not validate this
SwiftUI application.


## Native CLI consumer

This example owns `bonsai-swiftui.sexp`, its OCaml sources and `swift/`.
Prepare the source-checkout environment described in the [root README](../../README.md),
then run from this example directory:

```sh
"$BONSAI_SWIFTUI_CLI" build macos --profile debug
"$BONSAI_SWIFTUI_CLI" run macos --profile debug
"$BONSAI_SWIFTUI_CLI" sync-host --check
```

The CLI builds this example's `ocaml/native_embed.exe.o` as an independent Dune
project and generates the `apple/` Xcode host. Swift and OCaml sources remain
application-owned. See the [CLI guide](../../docs/swiftui-cli.md) for optimized
configurations, signing and physical-iOS builds with an explicit iOS 18 object.
The old OCaml package identifiers and installed SDK publication remain part of
the unfinished repository migration.
