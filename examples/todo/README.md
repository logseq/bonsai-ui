# Todo

Todo keeps its keyed items, selected item, edits, insertion, completion, deletion
and reversal in OCaml. SwiftUI is the sole host, targeting physical iOS 26+ arm64
and macOS 26+ arm64; Simulator is unsupported.

Each title uses `View.text_field` with a stable application key and text session.
The native control retains its draft, selection and focus across acknowledgments
and keyed reversals. Removing an item disposes its native editor. Native Toggle
and Button controls sit outside the text entry surface. Selecting an item is an
explicit action, and focusing a title also selects that item.

Cards place their title above a horizontal action row so narrow windows retain a
usable editing area. A bounded application body supplies the list's scroll area.

With the project opam environment active, build the macOS development bundle:

```sh
python3 tool/build_swiftui_example.py todo
open examples/todo/apple/DerivedData/Build/Products/Debug/BonsaiTodo.app
```

`TodoTests` runs the actual OCaml application inside SwiftUI at widths of 360 and
800 points. It edits Unicode text, reverses items while retaining the focused
native field and selection, changes completion, adds/selects/deletes items and
checks that removed fields release their delegates. Run it with:

```sh
swift test --scratch-path _build/swift --filter actualTodo
```

The old Flutter host and its configuration are deleted. Physical iOS packaging,
device interaction, VoiceOver and visual screenshot acceptance remain open.


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
configurations, signing and physical-iOS builds with an explicit iOS 26 object.
The old OCaml package identifiers and installed SDK publication remain part of
the unfinished repository migration.
