# SF Symbols

`View.symbol` renders a system-provided SF Symbol using SwiftUI
[`Image(systemName:)`](https://developer.apple.com/documentation/swiftui/image/init(systemname:)).
Use the SF Symbols application to select a name available on every supported
deployment target. The host rejects unavailable names when validating a frame.

```ocaml
View.symbol ~name:"envelope" ()

View.symbol
  ~name:"person.crop.circle.badge.checkmark"
  ~size:32.
  ~color:(Style.Color.rgb ~red:32 ~green:96 ~blue:160)
  ~rendering:View.Symbol_rendering.Hierarchical
  ()
```

The rendering modes are `Monochrome` (the default), `Hierarchical`, and
`Multicolor`. Multicolor uses the symbol's native color treatment; it does not
guarantee that every system symbol contains multiple colors. These modes map
to SwiftUI's
[`symbolRenderingMode`](https://developer.apple.com/documentation/swiftui/view/symbolrenderingmode(_:)).

An omitted size inherits the surrounding font. An explicit size is a positive,
finite point size. An omitted color inherits the foreground style; an explicit
color uses its sRGB/alpha channels. Theme font-family names are not used to
look up system symbols.

Symbols are decorative content. Put the meaningful label on their surrounding
control or semantics wrapper, including icon-only buttons. The full native
accessibility implementation is still tracked in the
[implementation ledger](swiftui-implementation.md).

System names, sizes, colors and rendering modes are properties of an existing
node: changing them does not replace its identity. Invalid properties or
unavailable system names reject the candidate frame before renderer publication.

The Gallery `symbols_section` demonstrates all three modes and inherited
styling. Its native integration test uses the real OCaml source and bridge.
macOS rendering is verified; physical iOS rendering and availability checks
remain part of the device acceptance gate.
