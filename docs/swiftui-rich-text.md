# Native Attributed Text

`View.rich_text` composes `Style.Text_span` values into one SwiftUI
`Text(AttributedString)`. Runs share line wrapping and baselines; they are not
separate labels in a stack. The previous string-only span API is removed.

```ocaml
View.rich_text
  [ Style.Text_span.create "Status: "
  ; Style.Text_span.create ~font_weight:Bold ~color:blue "Unread"
  ; Style.Text_span.create "\n"
  ; Style.Text_span.create ~italic:true "世界 👩🏽‍💻"
  ]
```

Each span accepts an optional positive finite base `font_size` in points (scaled relative to native body text), optional
`font_weight` and `color`, and `italic`, `underline`, and `strikethrough` flags.
Unspecified attributes inherit the surrounding font and foreground style.
The decoration flags add emphasis to that span. The configured application
font family applies to both plain and styled runs. Explicit sizes and weights
use the corresponding native SwiftUI font construction.

The text is literal Unicode content, including embedded newlines; it is not
parsed as Markdown or HTML. Empty spans and empty paragraphs follow native Text
semantics. The Swift host builds attributes from complete run strings, avoiding
UTF-16 offset conversions or splitting an emoji sequence to assign styles.
Apple documents SwiftUI attributes taking precedence over outer Text modifiers.
[Apple: Text with an attributed string](https://developer.apple.com/documentation/swiftui/text/init(_:))

Wire node 3 carries a bounded u16 span count. Each run contains a UTF-8 string,
optional font size, optional weight, optional ARGB color, and three strict
boolean flags. The complete update mask remains 1. Swift requires a leaf with
no children or bindings. Invalid sizes, weights, flags, UTF-8, truncation, or
extra fields reject the entire candidate frame. OCaml validates constructor
sizes and span counts and checks the same constraints during encoding/decoding.
The old string-only payload has no decoder.

The real Gallery `rich_text_section` demonstrates mixed emphasis, Unicode,
newlines, decorations, different font sizes, and natural wrapping. Its offscreen
capture gives the outer container an explicit unbounded vertical proposal with
`fixedSize(horizontal:false, vertical:true)` so ImageRenderer's final finite
height proposal does not compress a multiline sample. This is capture setup,
not a change to the renderer's native layout behavior.

`RichTextTests.swift` compares native raster references in both layout
directions and at narrow/wide widths. The integration fixture changes content,
size, weight, color and underline through a real OCaml Button handler without
replacing its renderer node. The Gallery images under `_build/validation/` are
component artifacts, not the required running Mail screenshots. Physical iOS
runtime rendering is still pending. Plain-text layout now uses the native
[Text API](swiftui-text.md).
