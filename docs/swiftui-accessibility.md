# SwiftUI accessibility

`View.semantics` wraps one child with native SwiftUI accessibility metadata.
It preserves the child's renderer identity when metadata changes. Semantics
owns labels, hints, values, traits, grouping, hidden state, heading level,
sort priority, identifiers and named custom actions. Native controls own
activation, enabled state, editing, focus, toggle values and secure entry.

```ocaml
let archive = Ui.Semantics.Action.create ~id:41L ~label:"Archive" in
Ui.View.semantics
  ~on_action:accessibility_handler
  ~properties:
    (Ui.Semantics.create
       ~label:"Message from Alex"
       ~hint:"Open message details"
       ~identifier:"message-42"
       ~children:Ui.Semantics.Children.Combine
       ~actions:[ archive ]
       ())
  message_button
```

The handler receives `Event.Payload.Int64 41L`. An action ID must be positive
and stable; the label must be nonempty and supplied in the application's
language. IDs are unique within one semantics node, and each node supports
at most 1,024 named actions. A nonempty action list requires `on_action`;
a handler without declared actions is rejected. Custom actions preserve the
child Button's native primary action.

`Children.Combine` is the default and combines descendant accessibility
properties. `Contain` groups descendants while preserving their elements;
`Ignore` replaces the children's accessibility representation. `hidden`
removes the subtree from accessibility without hiding its visual content.
Roles are Generic, Button, Link, Image, Header, Toggle and Static_text.
`selected` adds or explicitly removes the selected trait. Heading levels are
1 through 6; finite sort priorities follow SwiftUI's higher-first ordering.
Optional labels, hints, values and identifiers leave the child's native
property in place when absent.

These meanings follow Apple's [accessibility child behavior](https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior)
and [accessibility fundamentals](https://developer.apple.com/documentation/swiftui/accessibility-fundamentals).

## Removed API

The fixed Tap/Long_press/Focus/Increase/Decrease/Copy/Cut/Paste/Dismiss enum and
its bitset are removed. Default activation, adjustment, focus and editing
remain responsibilities of the corresponding native controls. Application
specific auxiliary operations use named actions with explicit labels and IDs.
There is no old enum or wire-format decoder.

The generic enabled, checked, focusable and obscured property bag is removed.
Native Button, Toggle and text controls expose their actual state. Todo and
Gallery provide explicit status values where their surrounding semantics
previously duplicated checked state. `sort_key` becomes `sort_priority` with
SwiftUI ordering. Mail's existing labels, hints, headings and live-region
intent are retained.

## Events and announcements

Named actions enqueue tag 22 with a positive UInt64 action ID. They use the
same bounded event queue as other native inputs and are not coalesced.
BonsaiSession requires an active, visible session, the current retained node,
a presented node in the same epoch, a matching handler, and an action declared
in both the current and presented generations. Hidden nodes and descendants
of hidden semantics nodes cannot enqueue custom actions. `Ignore` also blocks
custom actions and live announcements from the ignored descendants. Removed actions and
stale callbacks are rejected without synchronous FFI from SwiftUI.

A `live_region` derives its announcement from the nonempty label and value,
joined with a comma. No announcement is made for the initial snapshot.
Changed or newly introduced live regions announce only after successful
presentation acknowledgment, once per changed region. Equal descriptions,
hidden subtrees and no-diff pumps do not announce. Restoring a hidden live
region announces its current description. iOS uses `UIAccessibility.post`;
macOS uses `NSAccessibility.post` with `announcementRequested`.

This timing inherits the host presentation contract. It does not turn a
renderer commit into proof of physical screen presentation.

## Verification and remaining acceptance

`SemanticsNodeTests` covers malformed/truncated frames, invalid enums, heading
and priority bounds, action identity/label/count validation, transaction
rollback, live-region history and hidden ancestors. A macOS NSHostingView
query verifies real SwiftUI accessibility labels, hints, values and selected
state while preserving the child's renderer object.

The actual Gallery `semantics_component` runs through the C/OCaml fixture.
Tests invoke its native accessibility primary action and the Archive custom
action, observe changed OCaml state, verify presentation-gated announcements,
and reject the captured custom action after hiding its element. Tests query
public accessibility selectors because SwiftUI virtual nodes do not declare
NSAccessibilityProtocol conformance. A real AX application request enables
SwiftUI's accessibility materialization; application-window screenshots are
not produced by these tests.

The announcement sink is injected during tests. Audible VoiceOver output,
VoiceOver navigation order, physical iOS accessibility gestures and the full
Mail accessibility experience remain device/application acceptance work.
The Gallery subtree is not a substitute for complete Mail screenshots.
