# Shared UI defaults acceptance

Implementation of [Shared UI Defaults](agent-guide/implemented/feature/2026-09-15-shared-ui-defaults.md).
The public contract is documented in [Application themes](theme.md) and
[Native decorative surfaces](swiftui-surfaces.md).

This report records the initial Protocol 7 implementation and its source/capture
hashes. The [subsequent Theme-owned defaults update](theme-owned-defaults-acceptance.md)
records the current Protocol 8 implementation and verification.

## Note configuration reduction

Baseline: commit `651e514`, `examples/note/ocaml/note.ml`. Counts are source
occurrences, including each helper definition once; helper call counts are not
multiplied. The following eight categories are disjoint:

| Numeric configuration category | Before | After |
| --- | ---: | ---: |
| Explicit symbol/text point sizes (`~size`, `~font_size`) | 32 | 12 |
| Numeric size defaults in helpers | 2 | 0 |
| 44-point minimum width/height arguments | 8 | 0 |
| Standard corner literals (8, 10, 20, 28, 30) | 9 | 0 |
| Decorative border-width literals | 3 | 0 |
| Action-group shadow radius/Y arguments | 2 | 0 |
| Translucent paint-opacity literal | 1 | 0 |
| Two-point spacing arguments | 3 | 1 |
| **Total** | **60** | **13** |

This removes **47 numeric configuration occurrences (78.3%)** from these
categories. Named corner references are counted as removing numeric literals,
not as removing the corresponding clipping operation. The remaining two-point
spacing belongs to the document's date block.

Five policy helpers were removed: `label`, `column`, `symbol`, `glass`, and
`italic_hint`. Note now selects **15 semantic text roles** and **8 surface
recipes**. Ordinary symbols, actionable bounds, column spacing, material borders,
shadows and paint opacity resolve through shared configuration. The warm/cool
palette is supplied once per scope through `shared_theme`.

The source file changes from **983 to 1009 lines (+26)** after formatting. Explicit
typed style calls and the shared palette declaration add lines while removing
local default policies. Business handlers, fixture data, cover dimensions, grid
columns, reading-body spacing, miniature document typography, disclosure arrows
and the 26-point color swatch remain application choices.

## Validation

- OCaml build and tests pass, including reactive theme-only updates that emit no
  widget replacement, sparse-configuration validation, protocol round trips and
  Note's existing application behavior tests.
- Forty-eight focused rendering regressions pass after updating native reference
  views for the intentional 17-point Body, 19-point symbol and 16-point column
  defaults. Nineteen input tests pass, including changing a live theme while
  preserving the focused field, draft, selection and marked Chinese text.
- The full Swift regression run passes: **537 tests in 111 suites**, including
  native rendering, lifecycle, input, host requests and the shared-default tests.
- Protocol generation/fixture checks and native runtime/platform checks pass.
  Protocol 7 and Surface version 3 reject previous layouts.
- Note's native macOS window passes at 520 and 320 points, with visible controls,
  native editing, search, clear and sheet dismissal. The baseline is built from
  the source commit above and passes the same window checks.
- Mail's real native window passes under both light and dark host appearance,
  including sidebar/inbox/detail, expanding a card, resizing, archiving and
  switching mailboxes. The actual Gallery symbol section renders successfully.
- All four standalone CLI tests pass: Gallery packaging, packaged Mail and Note
  startup/presentation/restart, and independent native builds of all 12 examples
  without source mutation.
- Physical iPhone 13 / iOS 26.6.1: all **8 acceptance groups pass** on the final
  implementation. Buttons meet 44-point bounds; native search, scrolling,
  disclosures, title/body editing and theme/menu actions work. At 320 points,
  content height grows from **938.33 to 1396.67 points** with larger text and
  remains within the available width.
- The editor ends **16 points above the software keyboard**. Full-height focused
  sheets retain native opacity (backdrop response 0); leaving search restores
  the material with **RGB restoration error 0**. The normal sheet distinguishes
  the warm/cool backdrop by 15 RGB levels.

The device has Bold Text enabled. Both the unmodified system-legibility capture
and the host's regular-legibility capture are retained. Reduce Transparency is
verified through native paint tests; the phone's global setting remains off.
The device host exercises actual application controls and UIKit editors; it does
not claim finger-driven OS gesture automation.

## Capture review

[Evidence manifest](screenshots/shared-ui-defaults/evidence.json) records source,
object and capture hashes. The earlier physical capture manifest's Note source
hash matches the baseline commit. macOS captures use a live native app window;
iOS captures use the active device UIWindow.

| View | Before | After |
| --- | --- | --- |
| macOS, 320 points | [Before](screenshots/shared-ui-defaults/before/macos-narrow.png) | [After](screenshots/shared-ui-defaults/after/macos-narrow.png) |
| macOS, 520 points | [Before](screenshots/shared-ui-defaults/before/macos-cornell.png) | [After](screenshots/shared-ui-defaults/after/macos-cornell.png) |
| iOS, system legibility | [Before](screenshots/swiftui-note/cornell-system.png) | [After](screenshots/shared-ui-defaults/after/ios-cornell-system.png) |
| iOS, narrow larger text | [Before](screenshots/swiftui-note/narrow-large-text.png) | [After](screenshots/shared-ui-defaults/after/ios-narrow-large-text.png) |
| iOS, keyboard | [Before](screenshots/swiftui-note/editing-keyboard.png) | [After](screenshots/shared-ui-defaults/after/ios-editing-keyboard.png) |
| iOS, material restored | [Before](screenshots/swiftui-note/templates-after-keyboard.png) | [After](screenshots/shared-ui-defaults/after/ios-templates-after-keyboard.png) |

Visual review confirms smaller native macOS action groups, preserved iOS target
sizes, height-derived capsules and readable narrow layouts. Body and hint text
now respond visibly to Bold Text. Removing universal reading line spacing makes
ordinary labels more compact; the reading body keeps its four-point spacing.
The color swatch keeps explicit 26-point bounds so its decorative overlay fits
inside the compact macOS group.

## Reproduce

```sh
dune build @all @install
dune runtest
make protocol-check protocol-fixtures-check
python3 tool/run_swift_tests.py
python3 native/test/test_note_window.py
python3 native/test/test_mail_window.py
python3 tool/test_swiftui_example_cli.py
spec-dev-tool check --all
```

For physical-device build and capture commands, use the existing
[Note acceptance instructions](swiftui-note.md#reproduce), with a Protocol 7
complete object built from the current checkout. `BONSAI_NOTE_CAPTURE_DIRECTORY`
selects the macOS screenshot destination. No protected `ocaml/spec/` or Dune
files are changed. No source commit or push is made as part of this work;
the separate SDK publication requirement applies after a future source push.
