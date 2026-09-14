# Controlled native popovers

`View.Popover.create` presents arbitrary content anchored to another View. It
replaces `Material.Tooltip.rich` through native presentation and ordinary Text /
Button composition. Titles, descriptions, actions, spacing and bounded content
size belong to the caller. Plain help uses [View.help](swiftui-help.md).

```ocaml
View.Popover.create
  ~presented:show_details
  ~on_presented_changed:dismiss_details
  ~content:
    (View.column
       [ View.text "Message details"
       ; View.text "Keep this message for later."
       ; View.button ~on_press:keep ~child:(View.text "Keep message") ()
       ; View.button ~on_press:close ~child:(View.text "Close details") ()
       ]
     |> View.padding ~insets:(Layout.Edge_insets.all 16.)
     |> View.frame ~width:280.)
  (View.button ~on_press:open_details ~child:(View.text "Show details") ())
```

OCaml owns `presented`. The anchor is a normal View: opening is an ordinary
Button action or another model change, without an implicit long-press gesture
that competes with its controls. Native dismissal reports `Event.Payload.Bool
false` through `on_presented_changed`. The model can accept or reject the request.
Programmatic closing does not generate a second dismissal request. The native
binding cannot request opening. Disabling an anchor Button does not invent a
separate enabled state for its already-presented content.

`edge` is Automatic (the default), Top, Bottom, Leading or Trailing. It maps to
SwiftUI's optional arrow edge and follows native layout direction and available
screen space. The renderer uses the standard `.popover` presentation, including
its native platform adaptation. It does not draw a Flutter overlay or manually
position a second window. Callers should constrain rich content where needed;
the presentation primitive adds no hidden padding or title/action slots.

## Ownership and lifecycle

The first child is the anchor and the second is presentation content. Both
remain in the logical OCaml/native tree while closed. Changing visibility
preserves child identity. Native view materialization follows SwiftUI's
presentation lifecycle; logical removal or epoch replacement disposes the
controller and its descendants.

A presentation is eligible only after the owning frame has been acknowledged,
its properties, children and event binding still match the displayed owner, its
ancestor content is active, and the session is visible and active. A separate
native appearance acknowledgment gates interaction inside the content. Closed,
not-yet-presented and disappearing content cannot receive actions, text focus,
hover collection or animation completion through the session's ownership checks.

A dismissal stages a local close until the matching OCaml response. Request
serials keep an older response from resolving a later request. A no-diff rejection
restores canonical visibility and the native popover reappears. Binding and
appearance generations fence callbacks after handler/content/configuration
replacement, hiding, or disposal. Each native binding captures an immutable
generation: reading an old binding cannot renew its dismissal authority. A
regression first demonstrated an extra OCaml dismissal when the old getter
renewed that authority after handler replacement; the fixed binding rejects it.
Hiding the session closes the native
presentation without changing OCaml visibility; resuming can present it again.

Node 72 (`popover`) encodes a Boolean visibility and edge byte 0–4 with full
property mask 3. It requires exactly two children and one `value_changed` binding.
The existing Boolean event payload is reused; session admission only accepts
false for this node. Invalid flags, edge values, child counts, bindings and
truncated updates cannot publish a partial tree. The obsolete Tooltip triggered
event 36 was removed without reusing its ID.

## Verification and remaining acceptance

`PopoverTests.swift` covers malformed staging and retained closed-content
identity. Its actual Gallery/OCaml integration uses a real native popover window:
its action Button updates OCaml twice; Escape cancellation requests dismissal;
a rejected dismissal reopens the native surface; a replaced handler fences the
old binding; hiding closes the surface without an extra model request; resuming,
accepted dismissal, programmatic closing and teardown preserve the intended
state. Closed/disposed content rejects retained action references. The tests
first failed on unsupported node 72 and the old expressive node 136 before the
replacement passed.

An isolated SwiftUI probe established native appearance and Escape cancellation
in the available application window before the runtime implementation. This
application-local evidence does not establish physical pointer/keyboard use,
VoiceOver, text-editor focus/IME behavior inside presentations, every arrow-edge
geometry, compact iOS adaptation or physical iOS execution. Those checks remain
outstanding along with the complete standalone Gallery and Mail screenshots.
Supported targets remain physical iOS 18+ arm64 and macOS 26+ arm64, with no
Simulator support.
