# Native Text Layout

`View.text` renders literal Unicode through SwiftUI Text. Its layout properties
use the native paragraph model:

```ocaml
View.text
  ~style:(Style.Text_style.create
            ~font_size:18.
            ~font_weight:Semi_bold
            ~line_spacing:8.
            ~color:blue
            ())
  ~text_align:Style.Text_align.Start
  ~line_limit:2
  ~truncation:Style.Text_truncation.Middle
  "A longer message subject"
```

`line_limit` is optional and positive. Omission permits unlimited lines.
`Text_truncation` selects Tail (the default), Head, or Middle. SwiftUI determines
whether the available proposal requires truncation and places the ellipsis at
the chosen position. Alignment defaults to Start and follows layout direction.
[Apple: Text.TruncationMode](https://developer.apple.com/documentation/swiftui/text/truncationmode)

`Text_style.line_spacing` is an optional, finite, non-negative distance in
points between lines. Zero is valid. It is not multiplied by font size.
Omission inherits the surrounding native line spacing.
[Apple: lineSpacing](https://developer.apple.com/documentation/swiftui/view/linespacing(_:)),
[Apple: lineSpacing environment value](https://developer.apple.com/documentation/swiftui/environmentvalues/linespacing)

Omitted font size and weight inherit the native font, and omitted color
inherits the foreground style. An explicit weight modifies the inherited font
when no size or family is specified. The application font family applies through
the same font resolver used by attributed runs. Explicit font size must be
finite and positive; it is a base point size scaled by SwiftUI's
`ScaledMetric(relativeTo: .body)`. Custom font families use native relative font
scaling once. Omitted sizes continue to inherit the surrounding font. macOS
keeps its native behavior; a Dynamic Type category override does not imply
larger text on macOS. ARGB colors retain alpha.

The Flutter Text_overflow enum, overflow argument, line-height multiplier and
plain-text max_lines name have been removed. Fade masks and special visible
paint paths are absent. Clipping and sizing belong to view composition;
`View.clip` explicitly clips content, while the native parent proposal, frame,
paragraph line limit and truncation determine text layout. Text input still has
its separate, pending max_lines contract; this change does not port editing.

Wire node 2 retains five property slots and a complete update mask of 31:
value, optional text style, alignment, optional line limit and truncation.
Truncation tags are Tail=0, Head=1 and Middle=2. The style's optional spacing
field carries point distances. Both OCaml codecs and the Swift decoder reject
invalid spacing, sizes, line counts, enum values and malformed payloads. There
is no compatibility branch for the removed semantics.

Mail now supplies 6pt spacing for its detail subject and 8pt for message body;
Clock's caption uses 4.5pt. These are direct application style choices, not a
runtime conversion layer. Gallery's `text_section` demonstrates each truncation
position, line spacing, directional alignment and literal Markdown characters.

`TextTests.swift` compares the renderer with direct native SwiftUI expressions
at multiple line limits and in both layout directions. It also covers inherited
font/color/spacing, all four weights, a configured font family, alpha, malformed
updates, and real OCaml state changes without remounting. The Gallery artifacts
under `_build/validation/` are offscreen component renders. Physical iOS text
rendering and the final running Mail screenshots remain separate requirements.
