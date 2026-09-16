# Theme-owned defaults acceptance

This implements the [OCaml-owned UI defaults decision](agent-guide/implemented/architecture/2026-09-15-ocaml-owned-ui-defaults.md).
It supersedes the configuration ownership of the
[initial shared-default implementation](shared-ui-defaults-acceptance.md).

## Result

- OCaml `Theme.Defaults.Values` is the source for shared metrics, typography,
  semantic foreground selection and Surface recipe paint choices. The JSON
  source is removed. The generator evaluates the OCaml declarations to produce
  the native baseline; no separate handwritten Swift default table remains.
- `Theme.Defaults.create` is sparse. Each nested scope overrides only supplied
  fields. Widget constructors retain omission, including symbol rendering, text
  role and italic. Explicit values equal to the baseline stay explicit.
- Theme now owns Surface material, shape, background role, opacity and tint
  alpha; semantic shadow/material alpha; shadow X; default symbol rendering and
  text role; per-role foreground and italic. Raw platform color lookup, Dynamic
  Type, legibility and material drawing remain native platform behavior.
- Plain and rich text use scoped typography. Native fields/editors retain Body
  typography, input controllers, focus, draft, selection and marked text during
  theme changes.
- Protocol 8 carries the extended sparse Theme configuration and preserves
  inherited symbol/text attributes. Previous layouts are rejected. Surface
  remains version 3 because its explicit-property-mask payload is unchanged.
- Note uses the new OCaml location for four explicit image/decorative corner
  references. Application handlers, palettes, layout choices and presentation
  settings remain unchanged in this follow-up.

## Verification

- Red tests exposed frozen symbol/text constructor defaults, unsupported Theme
  paint choices, and rich text ignoring a scoped Body size. The implementation
  makes those behavior tests pass.
- 48 focused Swift tests in eight suites pass, including native runtime samples,
  explicit overrides, nested inheritance, invalid sparse payload rejection,
  input-state retention, Surface paint and rich/plain typography agreement.
- OCaml build/install and tests pass. A real reactive Driver test sends all new
  Theme fields through protocol encode/decode and verifies theme-only updates
  without widget replacements. Generation and protocol fixture checks pass.
- Six native runtime checks pass.

- Full Swift regression passes: **542 tests in 111 suites**.
- Note's real macOS window passes at normal and narrow widths, with editing,
  search and dismissal checks. Mail passes under both light and dark host
  appearance, including card expansion, archiving and mailbox switching.
- Three platform tests and the Swift generator test pass. The real Note OCaml
  object cross-compiles for physical iOS, and the complete generic iOS app builds
  and links successfully with code signing disabled.
- Formatting, generated-output freshness, diff whitespace and all decision
  documents pass validation.

[Evidence manifest](screenshots/theme-owned-defaults/evidence.json) records source,
object and capture hashes. Reviewed Note captures:
[normal window](screenshots/theme-owned-defaults/macos/macos-cornell.png),
[narrow window](screenshots/theme-owned-defaults/macos/macos-narrow.png), and
[edited title](screenshots/theme-owned-defaults/macos/macos-edited.png).

The physical iPhone was unavailable to both Xcode and CoreDevice during this
follow-up, so the new build could not be installed or exercised on the phone.
The earlier eight-group device result belongs to the prior Protocol 7 source
snapshot and is not claimed as a device test of this update.

## Reproduce

```sh
make protocol-generate protocol-fixtures-generate
dune build @all @install
dune runtest
make protocol-check protocol-fixtures-check
python3 tool/run_swift_tests.py
python3 native/test/test_note_window.py
python3 native/test/test_mail_window.py
python3 tool/test_swift_platforms.py
spec-dev-tool check --all
```

The public API and precedence are documented in [Shared UI defaults](theme.md).
No protected OCaml spec or Dune files were modified. No commit or push is included.
