# Native links in registered views

A registered SwiftUI view can request an application-owned destination through
`BonsaiNativeContext.navigationLink(to:label:)`:

```swift
context.navigationLink(to: RowEvent.open(blockID)) {
  context.children[rowIndex]
}
```

The label should contain display content rather than another Button. Put the
link in the existing core `View.Navigation_stack` hierarchy. SwiftUI supplies
the native NavigationLink appearance, accessibility and activation behavior.
Outside that hierarchy the link is disabled.

Activation submits the supplied typed native-view event through the existing
registration's encoder and handler. The OCaml handler updates its route and
publishes a `Navigation_stack.destination`; only that committed destination is
pushed. Loading or failure content therefore belongs to the application route.
No temporary destination or second navigation stack is created by the link.
Native Back still submits the stack's full remaining path.

The link captures its event, presentation snapshot, enclosing stack and current
path. Stale, hidden, disposed and foreign-stack activations cannot emit input.
Admission failure allows a retry. Successful admission prevents another link or
Back request until that exact native event is processed; an unchanged route also
releases the request, so an application veto does not leave navigation locked.
A local admission identity distinguishes the queued link from ordinary events
with identical application bytes. It is not added to the wire protocol. A queued
unrelated reply or observation does not settle the link.

Verification lives in `NavigationLinkTests.swift`: deterministic controller
admission cases, an AppKit-hosted native link, and a real OCaml runtime fixture
that keeps the route unchanged on the first request and opens it on the second.
This macOS host evidence does not replace iPhone gesture/device acceptance.
