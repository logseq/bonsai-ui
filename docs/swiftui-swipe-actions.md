# SwiftUI swipe actions

`View.Swipe_actions.create` is the immediate content of a `Native_list.row`.
SwiftUI `.swipeActions` owns gesture recognition, reveal layout, cancellation,
RTL edge placement, full swipe and accessibility. There is no SDK pan recognizer,
action pane, group closing policy, vertical swipe or custom action extent.
See [native List composition](swiftui-native-list.md).

Each action supplies a nonempty title, optional SF Symbol, Start/End edge,
semantic Button role, enabled state, tint and OCaml Press handler. Actions have
no child subtree. The container's `allows_full_swipe` defaults to false; when
true the system selects the first action on the relevant edge. Applications own
all data mutation and removal. The Mail Trash action is destructive.

BSFR 9 node 42 owns content followed by at most 64 node-43 actions. Validation
rejects action nodes outside their owner, swipe containers outside immediate
native rows, invalid enums and malformed child counts before publication.

Only a discrete action crosses the bridge. Its displayed identity, handler and
owning row must still match. A pending request suppresses duplicate activation
until its exact OCaml response, including no-diff responses. Changed bindings,
configuration and disposal invalidate captured callbacks. Native Button closures
capture this generation; a stale closure cannot invoke a replacement handler.

`SwipeActionsTests.swift` checks admission, rejection, malformed composition,
exact response ownership and stale targets. Native window acceptance exercises
the platform row actions separately; controller tests do not certify gestures.
The Removal extension retains its own `RemovalPan` adapter and is outside this
standard-control contract.
