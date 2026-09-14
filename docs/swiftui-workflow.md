# Native Workflows

`Workflow` replaces Material's multi-step Stepper with native Button headers,
SF Symbol status markers, keyed layout, and retained content surfaces. It is a
controlled workflow rather than SwiftUI's numeric Stepper. OCaml owns the current
step and every application action.

```ocaml
Workflow.create
  ~current_step_id:current
  ~on_continue
  ~on_back
  [ Workflow.step ~id:1L ~title:(View.text "Edit") ~content:editor
      ~state:Workflow.Editing ~on_select:select_edit ()
  ; Workflow.step ~id:2L ~title:(View.text "Review") ~content:review
      ~state:Workflow.Complete ~on_select:select_review ()
  ] ()
```

A workflow requires nonempty steps, unique signed 64-bit IDs, and a current ID
that names a step. State is Pending, Editing, Complete, Disabled, or Error.
Titles, subtitles, annotations and content are ordinary views. Disabled headers
cannot be selected; an absent selection handler also disables that header.
Each step has its own normal Press handler, so no selected-ID wire event or
callback remapping is needed. Continue and Back use ordinary Press handlers;
missing handlers disable the corresponding button. Their labels can be supplied
with `continue_label` and `back_label` and must not be blank.

The current step supplies the selected accessibility trait. Each header supplies
its status as an accessibility value in addition to its visible marker. These
default status descriptions are currently English. Application text and action
labels remain caller supplied.

Vertical layout puts each header above its own retained body. Horizontal layout
wraps headers through the native Flow layout and places the active body below
them. A layout change changes structure; reordering within a layout preserves
keyed headers and bodies. Both layouts keep inactive bodies in the logical and
native trees, with zero-height compact content, and exclude them from input and
accessibility actions. The retained surface uses zero-duration transitions.
Body state survives selecting another step and returning to it.

## Verification

The initial real-OCaml regression failed on unsupported legacy node 132; the
initial native App could not display its first state. The Gallery now uses
`Workflow`, both in its combined view and the independently runnable native
fixture. OCaml checks cover empty workflows, duplicate IDs, absent current IDs
and blank action labels. Native integration checks selection, Continue/Back,
disabled controls, hidden-content input rejection, node identity after selecting
another step and after reordering, layout changes and session closure.

The native App executes actual accessibility controls at 640 and 360 points.
It checks all five state descriptions, disabled state, current-step selection
traits, hidden-body accessibility, reordering, both layouts, and Continue/Back.
These checks do not establish pointer, keyboard, VoiceOver or physical iOS
acceptance, or replace visual inspection of the full Gallery.

The first native App run also exposed an existing retained-surface bug:
SwiftUI omitted EmptyView from Layout subviews, causing an out-of-range access.
Each surface branch now has a stable ZStack layout slot. Focused tests cover
an empty compact branch, an empty expanded branch and two empty branches, in
both states. Existing animation, native input isolation and editor-state
retention tests continue to pass.

The Material.Stepper API, private node 132, Step_selected/Step_continue/Step_cancel
events, payload types, codecs and protocol fixtures are removed. There is no
legacy decoder or compatibility constructor. Other Material families and the
combined standalone Gallery remain separate migration work.
