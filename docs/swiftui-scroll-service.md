# Native scroll service

`Host_effect.scroll_to` now operates on the presented scrolling container
identified by `node_id`. It supports `View.Scroll`, `View.Scroll_sections`,
`View.Collection` and `View.Scroll_targets` on their declared axis. It does not
interpret the identity as a child to reveal or as a Collection item key.

```ocaml
Host_effect.scroll_to ~alignment:0.5 ~animated:false host ~node_id
```

## Position and completion

The optional `alignment` defaults to zero. It must be finite and is clamped to
0 through 1 at execution. The target is this fraction of the current native
content extent minus the viewport extent, bounded below by zero. Zero means
the logical leading end, including horizontal right-to-left presentation.
Short content completes without travelling. Measurements come from the
container's SwiftUI scroll geometry rather than the whole application window.

Each renderer reuses its existing SwiftUI `ScrollPosition` binding. Ordinary
Scroll and lazy sections share their retention modifier's binding; Collection
uses its viewport binding. ScrollTargets exposes a point binding alongside its
existing item commands and native position observations. No additional hosting
graph or global native window lookup is introduced.

Apple's [point scroll API](https://developer.apple.com/documentation/swiftui/scrollposition/scrollto(x:y:))
clamps movement to the actual content. The service observes the resulting
geometry before reporting success; assigning a requested position is not
sufficient evidence of completion.

`animated` defaults to true. A monotonic 250 ms ease-in-out cubic transition
updates the same point binding at approximately 16 ms intervals. Reduce Motion
resolves the transition immediately. These point updates explicitly disable
implicit animation so there is one source of motion and cancellation can stop
it at the latest observed position. If an active native container does not
reach the target within two seconds, the request returns a bounded error.
An animation transaction's completion callback alone was insufficient in the
native tests: it could complete before the ScrollView moved.

## Ownership and cancellation

Requests use the existing host-effect presentation barrier, active/visible
session gates and bounded response queue. A deferred request does not move a
container until presentation has been acknowledged and the session is active.
The node resolver requires the current presented properties, bindings and
children. A missing, retired, non-scrollable or unmounted target returns an
error through the actual OCaml request result.

Each mounted scroll resource owns a binding and each operation owns a request
identity. A subsequent request replaces pending motion. Cancellation, native
user interaction, inactive content, axis changes, detachment and disposal
invalidate the operation. Its sleeping task checks cancellation and ownership
before every further position update. Closing the session clears the normal
host dispatcher and invalidates the render resources; old work cannot complete
into a restarted runtime.

Kind 8 contains a positive node identity, a finite Float64 alignment and one
Boolean animation flag. Malformed/truncated payloads fail decoding. As with
other host commands, the surrounding frame validator rejects trailing bytes
and stages commands atomically. There is no Flutter scroll-controller path or
legacy decoder for this service.

## Verification

`ScrollServiceTests.swift` sends application bridge events into a real OCaml
fixture. That fixture calls the public `Host_effect.scroll_to` API and renders
its completion status. Native NSScrollView geometry is measured independently
of the SwiftUI command binding.

The positional test covers all four container kinds, both axes and both layout
directions: 16 cases move to the middle, animate to the clamped trailing end,
and return to the clamped leading end. It verifies final travel within two
logical points, animation duration, and retained OCaml/native container
identities. RTL measurements subtract the actual initial native origin, so
ScrollTargets' content margins are not mistaken for travel.

Additional tests cover the presentation barrier, inactivity/resumption,
pre-cancelled and running requests, stopped motion, removed and non-scrollable
targets, restoration, session close, short content, finite values, invalid
flags/identities and every truncated command prefix. The initial actual-OCaml
and wire tests failed because kind 8 was unsupported. After implementation,
four tests in two suites pass in 28.524 seconds.

Physical iOS scrolling, touch interruption, Reduce Motion setting changes,
snapping-enabled ScrollTargets, simultaneous content/axis changes during a
request, and visual acceptance remain separate checks. Compilation does not
establish these behaviors. This checkpoint does not complete the remaining
host services or the full backend migration.

The complete serial Swift run passes 451 tests in 99 suites in 455.358 seconds;
the runner verifies its fresh completed xUnit report. All three platform checks
pass in 21.522 seconds, including the full iOS 18 Swift module and example
sources and explicit Simulator/Intel rejection. OCaml all/test/format/install,
protocol/fixture generation, strict Swift formatting and document checks pass.
These results do not establish physical iOS interaction or finish the goal.
