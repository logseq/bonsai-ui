# Native Label and List Row Composition

`View.label ?key ~title ~icon ()` renders SwiftUI `Label` with view content for
both slots. It inherits native label styling and environment from its context,
including when used as a Button label. It owns no selection or action handler.
Node 57 has no properties, uses update mask 0 and requires exactly two children:
title first, icon second. Event bindings, extra payload bytes and invalid child
graphs reject the staged frame atomically.

The old `Material.list_tile` constructor is removed. Compose its capabilities
using the shared view primitives:

| Capability | SwiftUI composition |
| --- | --- |
| Headline, supporting text and overline | Keyed native Text children in a leading-aligned column used as the Label title. |
| Leading icon or view | Label icon slot; use Empty for an absent decoration. |
| Main activation and enabled state | Button wrapping the display Label. |
| Selected state | OCaml state, `View.semantics` selected metadata and native prominent/bordered Button appearance. |
| Trailing display or action | A sibling view in the row; an accessory Button has its own handler and enabled state. |
| Full-width main action | A filling frame inside the Button label, with a shared-width item beside the fixed accessory in `View.Weighted.row`. |
| Reordering and optional text | Stable row and child keys preserve existing title/control identity. |

There is no replacement API that copies the Material property bag. Applications
choose title content and action placement directly. In particular, an
interactive trailing accessory is a sibling of the main Button, so it remains
independently actionable when the main Button is disabled. The native Label
title/icon slots are display content when the Label is used inside a Button.

## Gallery and verification

The actual Gallery component includes Inbox and Archive rows, optional
overline/supporting text and SF Symbols, selection, independent info actions,
disabling, detail removal/restoration and keyed reordering. It is included in
the combined Gallery sections and the `native-labels` runtime entrypoint.

`LabelTests` compares standalone and Button-contained Label rendering to
independent SwiftUI expressions in LTR and RTL. It rejects malformed frames
atomically and exercises the real OCaml component's presentation barrier,
disabled main actions, independent accessories, retained title identity and
rejection of removed accessory/session callbacks. Selected and unselected rows
also match independent native Button renders after changing the selected row.

The standalone native App test checks accessible composed titles, selected and
enabled state, actual Button activation, removed accessories and action bounds
at 640 and 360 points. Its initial layout check found a content-sized main
Button; the row now assigns the remaining width to that Button while keeping
the accessory separate.

These macOS checks do not establish physical iOS touch, VoiceOver or complete
Gallery visual acceptance. Device execution and the broader backend migration
remain required.
