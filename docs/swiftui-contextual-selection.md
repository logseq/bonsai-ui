# Contextual selection through native controls

Material.Selection and Material.Selection.leading are removed. Use keyed
View.toggle controls and View.Toolbar in a Navigation_stack page. OCaml owns the
selected ID set, available items, action eligibility and navigation policy.
There is no index-based native selection controller or shared selection wrapper.

Each item's Toggle receives membership as its Boolean value. Bind a stable handler
to the item ID and apply the requested Boolean to the current OCaml set. Independent
changes in the same event batch then compose correctly. Do not capture a selected
array in a handler and replace the current set with that stale snapshot.

Use a composed Label with SF Symbols to show selected and unselected faces. The
Toggle remains keyed by item ID while its checked value or label changes. Material
flip animation is removed; native Toggle styling and accessibility expose its
checked and enabled states. Sorting changes presentation order without changing
identity. Disabled items do not accept selection requests.

Derive contextual Toolbar items from the selection:

- With no selection, present the ordinary idle title/content.
- With a selection, present the count and clear/batch commands.
- Include a select-all command when appropriate. Its handler derives eligible IDs
  from the current data source; omitting that item replaces show_select_all=false.
- Batch commands read the current selection when executed. A preceding queued
  item-selection intent must be included in the action.
- Item removal prunes the canonical selection. Action results and asynchronous
  rejection remain application state; Swift never deletes canonical data itself.

A native toolbar requires a navigation/window host; it does not reserve a fixed
height or impose a scrolling layout on the body. Rows may use ordinary stacks,
Scroll or Collection. Clear selection is an explicit command. The old implicit
Flutter PopScope back interceptor is removed: applications choose whether to
clear, retain or reject navigation through their Navigation_stack path handler.

The existing Toggle and Toolbar presentation, pending-value, disabled, hidden,
removal and stale-binding rules apply. Components 9 and 29 and event 35 are retired.
The Segmented_selection_changed event, Int64_list input payload and their OCaml
codec/dispatcher branches are removed. Native membership uses Value_changed with
a Boolean, and commands use Press. No replacement wire node or compatibility
decoder is added. Old component frames and event 35 are rejected.

## Gallery and verification

Contextual_selection_catalog.component is shared by Gallery and the real OCaml
runtime fixture native-contextual-selection. It includes two eligible signed-ID
items, one unavailable item, dynamic selected labels and toolbar, explicit request
rejection, reversal, enabling/disabling, item removal, reset and batch archive.
The Gallery hosts this native navigation page in a bounded 900-by-600 preview;
full standalone Gallery and physical-iOS acceptance remain outstanding.

ContextualSelectionTests.swift verifies concurrent membership requests, current-set
batch execution, select-all, clear, rejection restoration, disabled actions,
reordering identity, removal pruning, replacement nodes, hidden input and shutdown.
The test initially failed because the runtime entrypoint was absent. Protocol
retirement tests separately failed while component 9 and event 35 were accepted.

native/test/test_contextual_selection_window.py runs a real SwiftUI App linked to
the OCaml fixture at 900- and 640-point widths. Native accessibility actions press
item Toggles and actual window-toolbar controls, checking selected state, select-all,
clear, rejection, disabled controls and archive. Toolbar controls are discovered
from NSToolbar item views; the outer window accessibility proxy is not assumed to
implement the actual control action. The test drives public native accessibility
selectors, not the Bonsai controller's request method.

These results do not establish physical iOS touch, keyboard navigation, VoiceOver,
actual toolbar overflow or visual acceptance. The supported matrix remains
physical iOS 18+ arm64 and macOS 26+ arm64, without Simulator support.
