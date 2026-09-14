# Native GroupBox and Card Composition

`View.group_box ?key ?label content` renders SwiftUI `GroupBox` with an
optional native view label. Material Card elevation and Elevated/Filled/Outlined
variants are removed. Platform styling comes from GroupBox and its inherited
SwiftUI environment. There is no old Card constructor or decoder.

## Actions and collections

A group is a container and owns no event handler. Wrap a display-only group in
`View.button` to make the entire card selectable. For a group containing
interactive content, put a selection Button in its label and independent
controls in its body. Each Button has its own OCaml handler and enabled state.
This avoids nested Button ownership and lets native accessibility expose the
separate actions.

The former `Material.Card_list` finite, scrollable and sliver constructors are
removed. Use keyed groups/buttons inside `View.column`, a bounded `View.Scroll`
body or the shared `View.Collection` catalog/window API. The application owns
selection; item keys preserve logical identity during reordering. There is no
card-specific selection event or scrolling implementation.

```ocaml
let card ~key ~on_select ~on_action =
  View.group_box ~key
    ~label:(View.button ~on_press:on_select ~child:(View.text "Select") ())
    (View.button ~on_press:on_action ~child:(View.text "Open attachment") ())
```

## Protocol and state

Node 106 is `group_box`, with one Boolean `has_label` property and update mask
1. Content always occupies child slot 0; the optional label occupies slot 1.
This order preserves an unkeyed content node when a label is added or removed.
The node accepts exactly one or two children according to its flag and no
event bindings. Invalid flags, arity, graph ownership, truncated bytes and
trailing old Card payloads reject the whole staged frame.

SwiftUI uses its labelled or unlabelled native initializer. The retained
render-node controller owns an editor's draft and selection when the native
container structure changes. A removed label receives a fresh node identity
when recreated, following the common protocol identity contract.

## Verification scope

`GroupBoxTests` compares labelled and unlabelled rendering with independent
SwiftUI GroupBox expressions in both layout directions, checks atomic rejection
and exercises native editor draft/selection retention through label changes.
The actual OCaml Gallery component covers independent selection/body actions,
presentation fencing, disabling, label removal/restoration, keyed reordering
and session closure.

`native/test/test_group_box_window.py` runs that component in a standalone
SwiftUI App and presses actual accessibility Buttons at 640 and 360 points.
These macOS tests do not establish physical iOS interaction, VoiceOver
acceptance or complete Gallery/Mail visual acceptance. Those remain part of
the full backend migration.
