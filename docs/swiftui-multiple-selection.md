# Multiple selection through native Toggle composition

Multiple selection is a keyed group of `View.toggle` controls sharing an
OCaml selection set. Use the Button or Checkbox style and ordinary stack
composition. Single selection uses `View.Picker`. There is no control that
switches between unrelated single- and multiple-selection protocols.

`Material.Segmented_button`, its private node, wire node 125 and its property
encoder/decoder are removed. The old selected-ID array, segment metadata and
multi-selection mode flag are not retained as a compatibility contract. The
Toggle composition uses the core Boolean Value_changed event. Event 35
and its Int64_list input payload are now removed after the remaining
[contextual selection](swiftui-contextual-selection.md) consumer was replaced.

```ocaml
View.toggle
  ~key:(Key.int64 choice_id)
  ~style:View.Toggle_style.Button
  ~enabled:choice_enabled
  ~value:(List.mem choice_id selected_ids)
  ~on_changed:choice_handler
  ~label:(View.row [ View.symbol ~name:"list.bullet" (); View.text "List" ])
  ()
```

Bind a stable handler to each choice ID. Its `Event.Payload.Bool` adds or
removes that ID using a functional OCaml state update. Apply the requested
Boolean; do not blindly invert membership or replace the selection with an
array captured when the handler was constructed. Independent choices received
in one event batch then compose against the current selection. The application
can enforce domain rules or decline a request. An empty set is valid.

Keys belong to the choices, not their current indices. Reordering preserves
the Toggle and composed-label identities. Choice IDs can be signed, including
negative values. Each control owns its native pending value and request serial;
the shared Toggle/session implementation handles acknowledgment, rejected
requests, disabling and disposal. Labels support ordinary SwiftUI composition,
including decorative SF Symbols. Disabled choices cannot emit input.

## Gallery and evidence

The production `multiple_selection_component` shows Button and Checkbox groups
sharing one set, including an unavailable choice. It includes enable/disable,
request rejection, reversal and programmatic clearing. The complete Gallery
composition includes this section; Gallery's standalone port remains unfinished.

`MultipleSelectionTests.swift` executes the actual OCaml component through the
native bridge. It verifies two choices queued together, deselection, subsequent
independent intents across an unpresented response, both groups agreeing on the
result, stable identity after reversal, repeated rejected requests, stale
bindings after disable/re-enable, programmatic clearing and disposal. The initial
test failed on unsupported legacy node 125 before the replacement was made.

`native/test/test_multiple_selection_window.py` drives the same component under
a real SwiftUI App event loop. At 640- and 360-point widths it presses native
Button-style and Checkbox-style Toggles, verifies both groups' checked states,
checks rejection restoration and disabled accessibility elements, and clears
the set. SF Symbol/text labels are included in the native scenario.

Physical iOS interaction and complete visual/VoiceOver acceptance remain open.
The physical-iOS Swift module typecheck does not establish device behavior.
The supported targets remain physical iOS 26+ arm64 and macOS 26+ arm64, with no
Simulator support.
