# SwiftUI Picker

`View.Picker` is the controlled single-selection API. It replaces
`Material.Radio_group`; the old public constructor, private node and generated
wire names are removed. Gallery's single-selection segmented examples also use
Picker. [Multiple selection](swiftui-multiple-selection.md) uses keyed native
Toggle composition with a shared OCaml set; Picker does not reduce multiple
selection to one ID.

```ocaml
View.Picker.create
  ~label:"Layout"
  ~style:View.Picker.Segmented
  ~selected_id:(Some layout_id)
  ~on_select:select_layout
  [ View.Picker.option ~id:1L ~label:(View.text "List") ()
  ; View.Picker.option ~id:2L ~label:(View.text "Grid") ()
  ; View.Picker.option ~id:3L ~enabled:false ~label:(View.text "Unavailable") ()
  ]
  ()
```

The handler receives `Event.Payload.Int64`, naming the requested option. IDs
are signed 64-bit values, including zero and negative values; they are distinct
from positive runtime node IDs. Options must have unique IDs, and a selected ID
must name an option. At most 256 options are accepted. An omitted option label
uses its decimal ID; the control label defaults to `Choice` and must not be blank.

`selected_id = None` represents no selection. The user can choose an enabled
option; clearing selection is an OCaml state change rather than a synthetic
option ID. Programmatic state may select a disabled option, but a user cannot
choose it. `enabled = false` disables the entire control and publishes no input
binding. Empty option lists and lists with no enabled choices admit no selection.

Option IDs also own their label-node keys. Reordering options preserves the
corresponding OCaml/Swift render identities instead of reusing labels by index.
Labels describe choices; nested interactive descendants cannot dispatch through
a Picker owner.

## Native presentation

The styles are Automatic, Menu, Segmented and Inline. iOS uses the corresponding
SwiftUI Picker styles. On macOS, Automatic and Menu use NSPopUpButton, Segmented
uses NSSegmentedControl and Inline composes native radio buttons with SwiftUI
labels. These small NSViewRepresentable adapters participate in the same
SwiftUI tree and controlled selection binding.

Independent macOS 26 SwiftUI reference programs reproduced ignored per-option
`.disabled` modifiers for radio, segmented and menu styles. The adapters set the
actual menu-item, segment and radio enabled states; the session independently
rejects disabled or unknown choices. They restore the authoritative selection
when queue admission fails. Inline labels retain SwiftUI composition; native
menu/segment labels use their text and first SF Symbol with platform typography.
Radio accessibility labels are supplied at the SwiftUI representable boundary,
and native target/action references are released on teardown.

## Protocol and lifecycle

Node 116 carries an optional Int64 selection, a UInt16 option count, options
(Int64 ID, enabled flag, label-child flag), the control label, style byte and
enabled flag. Its complete property mask is 31. Label children follow option
order, omitting absent labels. Enabled nodes bind event 53 (`picker_selected`),
whose payload is one signed Int64. Disabled nodes have no bindings.

The transaction decoder rejects invalid selection membership, duplicate IDs,
excessive counts, malformed flags/styles/strings, truncated payloads, incorrect
child counts and binding mismatches. The OCaml constructor and codec apply the
same option and selection constraints.

The native controller retains the latest local selection until the corresponding
OCaml response. Consecutive choices for one node, handler and displayed revision
coalesce. Request serials prevent an old response from clearing a newer request.
An unchanged OCaml response restores the authoritative value, allowing another
attempt. Binding generations reject callbacks invalidated by option reordering,
configuration changes or disposal. An in-flight value echo alone does not reject
a subsequent intent. Session admission checks displayed ownership, enabled
options, configuration, handler identity and active page content.

## Evidence and remaining acceptance

`PickerTests.swift` covers malformed transactions, coalescing, stale bindings,
disabled choices and native presentation at a 360-point host width. Popup tests
inspect actual NSMenu item enablement and dispatch through the native control's
target/action; they do not claim physical menu-pointer acceptance.

`native/test/test_picker_window.py` runs the production Gallery Picker component
inside a real SwiftUI App. Native radio and segmented accessibility actions
verify accepted and rejected requests, selected-state restoration and disabled
choices at 640- and 360-point widths. These actions require the AppKit event loop:
running native cell tracking inside SwiftPM's bare async main loop queued a
`CFRunLoopStop` that ended the test process with status zero before completion.
The App test retains standard native control behavior. `make swift-test` also
requires a fresh, complete Swift Testing xUnit report; a successful process exit
alone cannot pass the gate.

The production Gallery `picker_component` contains all four styles, enablement,
request rejection, reordering and programmatic clearing. Its actual OCaml runtime
test verifies accepted/no-diff responses, the final intent across an unpresented
echo, option-label identity, disabled input and teardown. This integration first
exposed the missing event-dispatcher mapping and positional label reuse; both
were fixed before the scenario passed.

Physical iOS behavior, including per-option disablement, remains unverified.
The physical iOS SDK typecheck is a compilation gate, not native OCaml linking or
device interaction evidence. Menu pointer/keyboard interaction, VoiceOver and
complete Gallery visual acceptance remain open. No Simulator is supported.


## Selection strips

Material.Tabs is removed. Use Segmented Picker for a selection strip and View.Tabs
for application pages. Primary/Secondary Material variants have no replacement
flag. Gallery's four linked choice pickers now include native Label content with
SF Symbols and text. The native segmented-control regression verifies both label
and image fields, signed ID mapping, disabled choices, application-rejected
selection, reversed ordering and disabling the whole group. The standalone
Material Tabs catalog entry is consolidated into this stateful Gallery scenario.
