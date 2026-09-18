# Bonsai Note

A standalone SwiftUI document demonstration with deterministic, in-memory notes.
OCaml/Bonsai owns selection, search, disclosure identities, themes, editing and
inserted blocks. The Swift host only opens `BonsaiApplicationView`. Relaunching
restores Cornell and clears session changes.

## Explore

- Launch into **Cornell Note Template**. Open **Templates** with Back or More.
- Search local template titles. Clear restores the categories. Close or native
  dismissal preserves the current working note. Choosing a template starts a
  fresh working copy and returns its scroll position to the top.
- Choose **Reading · Robert Pirosh** for the cool document and bundled cover.
- Expand **Key Points** and **Supporting Details** independently.
- **Edit note** opens a limited plain-text title/body editor. **Done** preserves
  session edits. The body maps to Cornell's Summary or the reading document's
  prose; it does not discard the styled Cornell sections.
- **Document theme** chooses warm/cool paper. **Insert block** appends a mock
  paragraph or checklist row. Document tools, style actions, More/About and
  Share show named local previews with no external effect.

Floating chrome uses shared native gradients, materials, shadows and borders.
The template sheet has a fixed heading/search area and independently scrolling
catalog. Its native search uses Plain field appearance inside one composed surface.
See [surfaces](../../docs/swiftui-surfaces.md) and
[image provenance](ASSETS.md). The example explicitly requests a light palette.

## Build and test

From the repository root with the project opam environment active:

```sh
dune exec examples/note/test/note_example_tests.exe
python3 tool/build_swiftui_example.py note
```

For the standalone CLI workflow, first build/install the local framework as
described in the root README, then run from this directory:

```sh
"$BONSAI_SWIFTUI_CLI" build macos --profile debug
"$BONSAI_SWIFTUI_CLI" sync-host --check
"$BONSAI_SWIFTUI_CLI" build ios --profile release --development-team "$IOS_DEVELOPMENT_TEAM"
```

Physical iOS 26+ arm64 and macOS 26+ arm64 are supported. Simulator is unsupported.
The iOS CLI requires its verified iOS SDK. A verified complete object from the
source-checkout iOS 26 cross-toolchain can instead be passed with `--native-object`.

The generated project includes `NoteRuntimeTests` (startup, presentation and
restart) and physical-iOS `NoteUITests` (reference captures, search, editing,
keyboard completion, theme and scroll clearance). Run the appropriate generated
scheme with `xcodebuild test` and a physical device destination. UI tests keep
screenshots and failure accessibility trees in the `.xcresult` bundle.

## Validation status

Physical-device captures, normalized reference comparisons, measured keyboard/scroll
clearance, accessibility settings and test-runner limitations are recorded in
[Note acceptance](../../docs/swiftui-note.md).
