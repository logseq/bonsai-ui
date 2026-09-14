# Native Wrapping Layout

`View.flow` places finite, ordinary child views in horizontal rows and starts a
new row when the next child would exceed the proposed width. It is a SwiftUI
`Layout`, shared by tag groups and other finite control compositions. It does
not create a scroll surface or an OCaml collection window.

```ocaml
View.flow
  ~key:(Key.string "tags")
  ~spacing:12.
  ~line_spacing:12.
  ~alignment:Layout.Horizontal_alignment.Leading
  keyed_tags
```

Both spacing values default to eight points and must be finite and non-negative.
Alignment defaults to Leading and also accepts Center and Trailing. Each row
aligns its children at the top. Native layout direction applies to row order
and leading/trailing alignment; OCaml does not reverse the child list for RTL.

The layout measures each child's ideal width, proposes at most the available
width to that child, and preserves its measured height. This lets a long text
label wrap within an item. A child with a fixed width can still exceed the
proposal; it occupies its own row and is not implicitly clipped. A row whose
items exactly fit stays on one line. An unspecified or infinite width measures
one row. Empty content measures zero; zero-width proposals remain finite.

Available width belongs to SwiftUI layout. Resizing the window changes row
placement without an OCaml event or a node rebuild. Stable application keys
retain child identity across changes to membership, order or spacing. The
layout performs linear passes over its materialized children, retaining
measurements within each placement plan.

Wire node 56 carries required spacing, line spacing and horizontal alignment
with update mask 7. It accepts ordinary children and no event bindings.
The OCaml constructor and encoder reject invalid spacing; the native decoder
also rejects invalid alignment, non-finite or negative spacing and malformed
updates before publishing the transaction.

## Verification

`FlowLayoutTests.swift` initially failed on unsupported node 56. It now compares
the production renderer against explicit native HStack/VStack rows for exact
wrapping boundaries, mixed heights, all three alignments and LTR/RTL. Further
cases cover unconstrained, empty, zero-width and oversized content, multiline
text, identity across property updates and atomic rejection of invalid updates.

Gallery's actual tags now use a keyed flow container around their existing
Toggle/removal-Button rows. Its actual OCaml integration checks the flow node
and retains selection, removal, rejection, disabling, reordering and disposal
coverage. The native App acceptance originally failed because tags remained in
separate rows in a 640-point window. It now measures the actual accessibility
frames: Work and Personal share a row at 640 points and occupy different rows
at 360 points. The same scenario continues to exercise the native controls.

These are macOS renderer and running-App checks. Physical iOS behavior,
VoiceOver and full Gallery visual acceptance remain separate requirements.
