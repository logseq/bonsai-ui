# Controlled native confirmations

`View.Confirmation.alert` and `View.Confirmation.dialog` attach SwiftUI Alert and
ConfirmationDialog to stable ordinary base content. OCaml owns the optional
request and its response handler. The native surface supports a text title,
optional text message, and keyed actions with text titles, enabled state and
`Button_role.Normal`, `Cancel`, or `Destructive`. These constructors do not expose
arbitrary alert layouts.

```ocaml
let open View.Confirmation in
let request =
  request ~token:next_token ~title:"Delete entry?"
    ~message:"This cannot be undone."
    [ action ~key:"delete" ~title:"Delete" ~role:Destructive ()
    ; action ~key:"cancel" ~title:"Keep entry" ~role:Cancel ()
    ]
in
alert ~key:(Key.string "delete-confirmation")
  ~request:(Some request) ~on_response base_content
```

A request has 1–64 actions, unique nonempty string keys and at most one Cancel
role. Titles must be nonblank. Tokens are positive Int64 values and strictly
increase within one retained presenter. Keeping the current token retains the
same logical request; clearing and reopening requires a newer token. This bounds
native settlement history without retaining every past token.

The handler receives `Event.Payload.Confirmation_response { token; result }`,
where `result` is `Action action_key` or `Dismissed`. An explicit Cancel action
returns its own action key, including when the system routes outside dismissal
through that Cancel action. A native dismissal without an action returns
`Dismissed`. Application code should match the token before changing its state.

The framework captures the presenter, token, action configuration and handler
when the presentation becomes eligible. A button wins over its accompanying
binding dismissal in either native callback order. Dismissal arbitration waits
until the native callback turn completes. Replacement, hiding, disposal and
handler rebinding invalidate retained callbacks. A rejected event consumes the
logical response and cannot replay a destructive choice on another owner.

After a response, OCaml remains authoritative. Clear the request to close it. If
the response produces no state change, the same request is restored and its
actions cannot emit again. Use a newer token for a new decision. While an active
confirmation remains requested, background controls cannot activate. The native
presentation's identity is separate from its base child, so opening, closing and
restoring it do not replace ordinary content or its editor ownership.

## Protocol

Node 152, `confirmation`, owns one ordinary base child. Its property mask is 31:
style u8 (0 Alert, 1 ConfirmationDialog), optional positive i64 token, title string,
optional message string, and a u16 action count followed by each action's key,
title, enabled byte and role u8 (0 Normal, 1 Cancel, 2 Destructive). A closed node
has no token, title, message, actions or response binding. An open node has exactly
one event-60 binding. Swift validates shape and token freshness before publication.

Event 60, `confirmation_response`, encodes the positive i64 token followed by an
optional action-key string; absence means Dismissed. The native-only response
serial and handler snapshot fence settlement but are not additional wire fields.
Input admission uses the captured handler and the exact displayed presenter.

## Verification

Gallery and the actual runtime fixture share the same public OCaml example.
Controller tests cover both callback orders, stale callbacks, disabled actions,
rejected admission, unchanged-state restoration and token freshness. Actual
runtime tests cover typed response delivery, ordinary background input blocking,
new logical presentations and no-diff response rejection. Hosted macOS tests
exercise real Alert and ConfirmationDialog buttons and retained base identity.
Physical iOS presentation, VoiceOver and gesture behavior require device checks;
module compilation alone does not establish them.
