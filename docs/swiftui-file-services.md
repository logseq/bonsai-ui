# Native file import and export

`Host_effect.pick_files` returns every selected file in selection order. Set
`allow_multiple` explicitly; an empty list means the user cancelled. The old
`pick_file` entrypoint and optional-single-file import decoder are removed.
`Host_effect.save_file` returns an optional single destination; `None` means
the user cancelled.

SwiftUI owns presentation through `fileImporter` and `fileExporter`. Both use
explicit completion and cancellation callbacks. Requests execute only after
presentation acknowledgment against the session's own attached window. A
second file request fails while another is pending. Callback identities prevent
old dialogs from completing requests in a restarted session. Dismissal of the
SwiftUI binding does not itself resolve the request, because dismissal can
precede a successful completion callback.

## Imported files

The host coordinates reads and obtains security-scoped access to external
resources. It copies regular files into private session-owned directories on a
background task, preserving order and duplicate basenames through separate
per-selection directories. Failed or cancelled batches are removed as a unit.
Original files remain untouched. The returned records contain local paths and
no inline data. File contents can exceed the 1 MiB host-response budget; the
encoded list of paths must fit that budget before any copying starts.

Returned copies live until the runtime session closes. Applications must copy
or otherwise persist imports needed beyond that lifetime. Window detachment
cancels a pending chooser but keeps already returned imports alive. A delayed
copy completing after cancellation or reset is discarded.

## Exported files

The export document holds its own immutable copy of the request bytes and
writes a regular `FileWrapper`. Empty and opaque binary data are supported,
including files larger than 1 MiB within the 16 MiB wire-frame limit. Suggested
names must be nonempty basenames. SwiftUI's destination chooser performs the
save; cancellation never deletes an external destination.

## Verification boundaries

Focused tests verify malformed/truncated requests and responses, actual OCaml
multi-file callbacks, real filesystem copying, duplicate names, opaque and
large files, rollback, bounded responses, export byte ownership, concurrent
requests, cancellation and stale callbacks after restart. Native chooser
presentation/cancellation is a separate window test. Calling the completion
callback in an integration test does not establish actual chooser selection.

Actual macOS source selection, export destination selection and overwrite
confirmation now pass through the real Host Effects application, as recorded
below. Physical-iOS selection, scoped file-provider behavior and complete
both-platform visual acceptance remain required.
The project does not support Simulator.

The September 13 checkpoint passes 12 focused tests in 0.212 seconds and the
actual Host Effects native-window scenario in 32.841 seconds. The full regression
passes 405 Swift tests in 89 suites in 336.160 seconds with a fresh completed
xUnit report. OCaml build/test/format/install, generated-protocol freshness and
all three platform checks pass, including the full iOS 18 module and ten Swift
App entrypoints. See the [implementation ledger](swiftui-implementation.md) for
log paths and remaining migration requirements.


## Actual macOS chooser acceptance

The current source builds through the public CLI in Debug and runs as the real
BonsaiHostEffects application. CUA drives SwiftUI's system panels, without
invoking the application's completion callbacks directly. The September 14 run
verifies these outcomes:

- Multi-select a UTF-8 text file with a Chinese filename and a binary file.
  OCaml displays `Imported 2 files`; both private copies match their originals
  byte-for-byte, and the originals remain unchanged.
- Export to a new local destination. OCaml displays `File exported`, and the
  actual `Bonsai.txt` contains exactly the 26 bytes submitted by OCaml.
- Replace that generated test destination after deliberately changing its
  contents. The system presents its Replace confirmation; accepting it restores
  the exact export payload.
- Cancel a subsequent import and export. OCaml displays the corresponding
  cancellation state, while imported copies, original fixtures and the existing
  export remain intact.

[Original captures and reproduction steps](screenshots/swiftui-host-effects/file-services/README.md)
include the real selection, completion and overwrite UI. Their manifest records
source/binary hashes, copied-file hashes and the build log. The transient file
list initially did not select through CUA's text-cell click; native Down and
Shift-Down selected both files normally. No renderer change was required.
This closes the previously unverified macOS chooser-success path, not physical
iOS file-provider or complete lifecycle acceptance.
