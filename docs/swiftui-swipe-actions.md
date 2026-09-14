# SwiftUI Swipe Actions

`View.Swipe_actions` replaces the Slidable and auto-close extension families
with typed core nodes. The content is an ordinary SwiftUI subtree, including
the existing Mail collection rows; no Flutter extension or Dart package is
used for this capability.

## Public composition

`action` supplies a title, Start/End side, enabled state, Button role,
background, custom label subtree, extent, auto-close policy, optional full-swipe
activation, and a normal OCaml Press handler. Titles must be nonempty and
extents finite between 44 and 4096 points. Actions retain their configured
proportions when the pane is capped at 80% of the row's width or height.
A container owns its content and at
most 64 actions, with at most one full-swipe action on each side.

`create` requires a stable key. Horizontal Start/End follow layout direction;
vertical Start/End mean top/bottom. Group identity compares exact UTF-8 bytes.
Opening or tapping another row can close peers in the same group. Scroll
activity closes open panes when `close_on_scroll` is enabled. Native context
menus and named accessibility actions expose the same handlers as the pane
Buttons. OCaml owns data changes and row removal.

## Native ownership

BSFR node 42 owns one content child followed by action nodes. Node 43 owns
one label child and its enabled Press binding. Invalid ownership, enum values,
duplicate full-swipe actions, child counts, property masks, truncated payloads
and invalid geometry reject the candidate frame before publication. Label
descendants cannot dispatch independent input; native action Buttons own their
accessibility labels and activation.

Swift owns drag distance, direction arbitration, reveal position and settling.
The native pan adapters use NSPanGestureRecognizer and UIPanGestureRecognizer.
The macOS subclass records full mouse travel before calling the system event
handlers. NSPan's translation is zero inside the should-begin callback even
when the triggering event is a drag; testing that value rejected every swipe.
Both direction arbitration and final full-swipe distance now use the recorded
travel. The system recognizer still owns event delay, recognition and reset.
Native text-editing and native scalar slider descendants are excluded from
interception. Arbitration with the composed interval Slider still needs a
nested interaction test. Open
containers disable content interaction; closing restores the retained content.
Scene inactivity, removal, changed action identity, changed configuration and
size changes clear transient reveal state. Reduced Motion disables settling
animation.

Only a discrete action crosses the C boundary. Its currently displayed handler
and action ownership must still match. A per-container pending request suppresses
duplicate activation until the OCaml pump resolves, including a no-diff
response. Raw action-node activation bypassing its owning controller is rejected.
Content updates preserve keyed nodes and their native resources.

Only the currently exposed side mounts its SwiftUI action pane. The retained
render nodes and action ownership remain in the controller while closed.
Physical iOS testing found that keeping zero-opacity action panes mounted left
Archive buttons from closed rows in XCTest's hittable accessibility results.
Conditional mounting prevents these hidden action views from participating in
native accessibility and hit testing; custom accessibility actions and context
menus remain available through the owning row.

## macOS Button arbitration

The real Mail window exposed a separate macOS defect: dragging its collapsed
Button row expanded the message instead of revealing actions. The Button's
press recognizer began on mouse-down and prevented the pending native pan
before it received any dragged event. A Mail event-loop regression reproduces
this in both light and dark host appearances.

`SwipePanRecognizer.canBePrevented` now keeps the pan eligible until its
directional admission check accepts or rejects mouse travel. It can then
cancel the Button press for an admitted swipe; an ordinary click still reaches
the Button. Text editors and sliders retain their existing hit-test exclusions,
and cross-axis rejection still belongs to `canBegin`. No private recognizer
class names or application-specific gesture rules are used.

The Mail regression passes in both host appearances (22.780 seconds), including
one exposed Archive button, no accidental row expansion, pane closure and a
subsequent ordinary mouse click. The standalone LTR, RTL and vertical swipe
scenarios also pass cross-axis rejection and full-swipe actions (35.975 seconds).
All eight directional removal scenarios pass (42.510 seconds), and the focused
Swift run passes ten tests in three suites (25.695 seconds). This macOS change
does not establish the pending physical-iOS acceptance.

## Evidence and outstanding validation

- `SwipeActionsTests.swift` exercises malformed frames, native accessibility
  reveal and activation, rejected input admission, grouped closing, disabling,
  stale Buttons and retained content identity. Native accessibility frames
  verify unequal action extents, proportional compression in both axes and
  leading-pane placement under both layout directions. These tests exposed and
  fixed equal-width allocation and an RTL pane offset outside the row.
- The real Gallery `swipe_component` contains horizontal and vertical examples,
  controlled enabled state, action counting and an option to ignore actions.
  Its native test sends accessibility actions through the C bridge and actual
  OCaml handlers, verifies duplicate suppression, repeated unchanged responses,
  disabling, and node identity across accepted changes.
- `native/test/test_mail_window.py` runs the actual Mail model in a standalone
  SwiftUI App. It checks a list width of at least 340 points, expands a message,
  invokes that row's native Archive action, and verifies removal from the inbox.
- `native/test/test_swipe_window.py` now passes and is part of `swift-test`.
  Its standalone SwiftUI App measures the global content frame, permits test
  window activation clicks and posts mouse events through the normal event loop.
  The LTR, RTL and vertical cases reject cross-axis reveals/actions, then verify
  exactly one full-swipe Archive action. Fixing test delivery exposed the native
  translation lifecycle defect described above. No controller calls substitute
  for mouse input. Physical scroll arbitration, interruption/cancellation and
  nested interactive controls still require acceptance evidence.

The physical Mail UI test now passes inbox expansion/collapse and attachment
detail navigation (16.595 seconds), with three system screenshots saved in
`screenshots/swiftui-mail/physical-interaction`. The swipe test revealed the
hidden-pane issue above. The fix passes seven focused macOS tests and the
standalone LTR/RTL/vertical mouse-input scenarios (34.063 seconds). Its physical
retest was interrupted when the user removed the iPhone; device verification of
the fix remains open. VoiceOver interaction and scroll-versus-swipe measurements
also remain outstanding. Optional NSView bitmap
exports from the Mail test omit native compositor content and are diagnostics,
not accepted screenshots.
