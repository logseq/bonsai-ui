# Actions, filters and removable tags

The former Material Chip family uses ordinary SwiftUI control composition.
`Material.Chip`, the four dedicated node kinds 119–122 and the Chip Delete event
34 are removed, including their schemas, property codecs and event dispatch.
There is no renamed Chip wrapper or compatibility renderer.

| Former purpose | SwiftUI-oriented composition |
| --- | --- |
| Assist or suggestion action | `View.button`, with a native Bordered or Prominent style and an ordinary composed label. |
| Selected action, filter or suggestion | `View.toggle` with Button style and an OCaml-controlled Boolean. |
| Selectable input tag | A keyed row containing a Button-style Toggle for the tag. |
| Optional tag removal | A sibling Button whose Press handler removes the tag from OCaml state. Omit that Button for non-removable tags. |

Stateful actions use the requested Boolean from `Event.Payload.Bool`; effects
can run in the same handler. Stateless actions and removal use ordinary Press.
Native control styles replace Material Flat/Elevated appearance. Labels accept
text, SF Symbols and composed content without separate avatar slots.

```ocaml
View.row
  ~key:(Key.int64 tag_id)
  ~spacing:8.
  [ View.toggle
      ~style:View.Toggle_style.Button
      ~enabled
      ~value:is_selected
      ~on_changed:select_tag
      ~label:(View.row [ View.symbol ~name:"briefcase" (); View.text "Work" ])
      ()
  ; View.button
      ~enabled
      ~on_press:remove_tag
      ~child:(View.text "Remove Work")
      ()
  ]
```

Removal belongs beside the Toggle, outside its label. Label descendants cannot
dispatch independent input through a Toggle owner. This structure gives each
action its own native hit target, accessibility element and enablement. The
application removes both membership and selected state for a deleted tag.
Stable row keys retain other tags when the list changes. A restored tag receives
a fresh runtime identity, so callbacks from its removed controls stay invalid.

Use [View.flow](swiftui-flow.md) around the keyed tag rows to wrap the group
within the available width. Native window resizing changes row placement while
retaining the existing controls and OCaml state.

## Gallery and verification

The production Gallery `tag_component` demonstrates ordinary/prominent actions,
controlled Filter and Suggested Toggles, two removable tags, one non-removable
tag, SF Symbol labels, enablement, rejected requests, reversal and restoration.
Its native fixture uses the same component included in the combined Gallery.

`TagTests.swift` runs the real OCaml application through the native bridge. It
verifies action counts, independent Boolean changes, stable identities after
reordering, repeated rejected selection/removal, disabled and stale callbacks,
selection followed by removal in one batch, unaffected sibling selection,
restoration and disposal. It first failed on unsupported legacy node 119.

`native/test/test_tag_window.py` exercises native controls inside a SwiftUI App
at 640- and 360-point widths. It verifies action counts through displayed text,
selection, request rejection, independent deletion, optional removal controls,
disabled native elements and restoration. Native accessibility-frame checks
also verify a shared row at 640 points and wrapping at 360 points. Static text is read from its macOS
accessibility value; Buttons and Toggles are identified by their labels.

Physical iOS interactions, full Gallery visual acceptance and VoiceOver remain
unverified. Compilation against the physical-iOS SDK is not device acceptance.
The migration still targets physical iOS 26+ arm64 and macOS 26+ arm64 only.
