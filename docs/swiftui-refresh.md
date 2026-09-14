# Native SwiftUI Refresh

`View.Refresh.vertical` wraps a native vertical Scroll, Scroll_sections,
Collection or Scroll_targets viewport. Apply it before viewport padding, frames
or other decorations. The result remains a typed vertical viewport; horizontal
and arbitrary content are rejected. The modifier retains the underlying native
ScrollView and its collection/window controller during request updates.

```ocaml
View.Scroll.vertical content
|> View.Refresh.vertical
     ~request_token
     ~request_state
     ~on_request
```

OCaml owns request identity and completion. Each new request uses a distinct
signed 64-bit `request_token`. Ready admits a user action; the native host emits
`Event.Payload.Int64 request_token` exactly once and starts progress immediately.
Pending acknowledges that work is running. Completed releases the waiting native
async action. Replacing the token also releases the previous waiters. Duplicate
activation joins the same request; it never emits another event. A completed or
canceled token cannot be reused to start another request.

An optional `show_token` requests programmatic activation when its value changes.
It uses the same admission, event and completion path as the refresh button.
The request still needs Ready state and an active, presented owner. Application
work can also set Pending directly to show progress without asking the host to
emit an action. Applications must ignore results from superseded request tokens
before publishing their next state, just as for any asynchronous application job.

Rendering uses SwiftUI's [`refreshable(action:)`](https://developer.apple.com/documentation/swiftui/view/refreshable(action:))
and [`RefreshAction`](https://developer.apple.com/documentation/swiftui/refreshaction).
A labeled native button offers a keyboard/accessibility action on both platforms.
An indeterminate ProgressView remains visible while the request is pending.
Leading pull geometry arms at 72 points during native user interaction and fires
once on release. Reversing above the threshold disarms it; programmatic offsets
and nonfinite geometry do not trigger requests. Every native scroll container
consumes only its nearest refresh owner, clearing the owner from its content so
nested scrolling cannot trigger an ancestor's refresh. Material style variants,
M3ERefreshIndicatorController and the former component-23 renderer are removed.

Presentation checks reject input from hidden, inactive, replaced or removed
owners. Matching Pending frames preserve waiters rather than completing them.
Token changes, handler replacement, task cancellation and teardown release native
continuations. No native refresh task owns the OCaml job or performs network I/O.

Wire node 77 has request_token (i64), request_state (strict Ready=0/Pending=1/
Completed=2), and optional show_token (i64), with required property mask 7. It
requires exactly one supported vertical scroll child and one Refresh_request
binding (event 56, i64). Invalid states, child kinds/axes, bindings, masks and
truncations fail atomic staging. The previous Material component 23 is rejected
by OCaml encoding/decoding and has no SwiftUI compatibility implementation.

The Gallery has all four supported viewport families and controls for completing,
replacing and programmatically showing a request. Actual OCaml window tests check
single emission, Pending/Completed behavior, programmatic requests, hidden-owner
admission and retained native scroll identity. Protocol/controller tests cover
atomic rejection, async completion, cancellation, replacement and removal. These
are native macOS and source-level physical iOS checks. Actual mouse/trackpad and
iPhone pull gestures, appearance, VoiceOver and standalone Gallery acceptance
remain required; callback tests do not establish those device outcomes.
