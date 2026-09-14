# Native Per-Item Removal

`View.Removal.create` wraps one keyed item. Use it in an ordinary column/row or
inside a materialized Collection row. The parent layout and data source remain
application-owned. This replaces Material.Dismissible_list.column/horizontal;
there is no native list-owned item index, shared confirmation future or retained
Material component decoder.

```ocaml
View.Removal.create
  ~key:(Key.int item.id)
  ~request_token:item.request_token
  ~request_state:item.request_state
  ~on_request
  ~on_removed
  content
```

The required key preserves item identity. Optional `axis` chooses the drag axis
(default Horizontal); `collapse_axis` independently chooses the dimension that
shrinks after acceptance (default Vertical). `title` defaults to Delete and must
not be blank. `duration_ms` defaults to 180 and accepts unsigned 32-bit
milliseconds. The child supplies its normal intrinsic or explicitly framed size.
A surrounding fixed-extent Collection retains its declared row extent until the
application processes `on_removed` and removes the catalog key.

## Request and completion ownership

Each item receives a signed 64-bit request token and one of four states:

- Ready admits a new request. The native controller immediately suppresses
  duplicate activation and keeps the item visible while awaiting the OCaml frame.
- Pending acknowledges the request, retains the child and shows native progress.
  The item's content and removal command do not accept input while waiting.
- Rejected restores the retained item and its position. Supply a fresh token
  before allowing another request after an earlier accepted activation.
- Accepted animates opacity and the chosen layout extent to zero. After native
  completion, `on_removed` receives `Event.Payload.Int64 request_token` once.
  The application then removes the item from its data source.

`on_request` receives an Int64_pair containing token and direction. Decode it with
`Removal.request_of_payload`; a keyed handler already identifies the application
item. Start_to_end (0) and End_to_start (1) follow horizontal layout direction,
including RTL; Up (2) and Down (3) are physical vertical directions. A native
context-menu/accessibility command uses End_to_start horizontally and Up
vertically. The command and gesture use the same request admission path.

Changing the token cancels previous transient state and completion. Applications
must also reject obsolete asynchronous results before publishing their next
request state. Handler replacement, node removal and root-epoch replacement fence
old native callbacks. Replaying an unchanged Accepted frame cannot emit another
completion. If an already Accepted item mounts, it starts collapsed and reports
completion when mounted, active and presented.

## Native interaction and animation

The existing platform pan recognizer is shared through NativePanTarget. AppKit
and UIKit still own recognition, cancellation and input delivery; no second pan
adapter or Flutter direction decoder is introduced. Gesture admission requires
at least four points of movement and a 1.25-to-1 axis advantage. Releasing after
at least 45% of the item's drag-axis extent (minimum 44 points) requests removal.
Short or canceled drags restore the item. Text editors and native scalar sliders
retain the shared recognizer's existing interception exclusions.

The item remains mounted while SwiftUI interpolates its opacity and layout
extent. Only the selected collapse dimension shrinks; the other remains stable.
Token replacement restores the full extent while keeping the child's render
identity. Reduce Motion uses immediate completion. Scene inactivity settles a
running animation locally but defers the completion event until its owner is
active and presented again. No per-frame geometry crosses the OCaml bridge.

Wire node 78 carries request_token, request_state, vertical, collapse_vertical,
title and duration_ms with required mask 63. It owns one child and exactly two
bindings: Removal_requested (57, i64_pair) and Removal_completed (58, i64).
Invalid states, flags, title, masks, child counts, bindings and truncations reject
atomic staging. Old Material components 10 and 11 are rejected; their OCaml API,
Dart hosts, confirmation helpers and obsolete tests are removed.

## Verification boundaries

Gallery contains both drag axes with explicit accept/reject/replace controls.
Real OCaml window tests run in LTR/RTL, check pending duplicate suppression,
rejection identity, token replacement, accepted removal and single completion.
Native layout tests observe intermediate horizontal/vertical extents, cancel an
accepted animation, retain the child, exercise Reduce Motion and hidden/resumed
completion, and reject completion after root replacement.

`native/test/test_removal_window.py` launches an actual SwiftUI application linked
to the real OCaml fixture. Eight axis/layout-direction/swipe-direction cases post
mouse events through the normal native event loop. They reject cross-axis input,
verify the direction received by OCaml, preserve pending content and remove the
correct item only after acceptance. Gesture points stay inside the content area,
away from the window resize border. The shared swipe-action mouse acceptance
suite remains an independent regression for the recognizer refactor.

These tests do not replace physical iPhone/trackpad arbitration, VoiceOver,
performance or screenshot acceptance. The full standalone Gallery and remaining
migration work are still in progress.
