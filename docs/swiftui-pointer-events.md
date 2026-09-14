# Native pointer input and hover regions

Swift now encodes pointer enter, leave, down and up through the existing typed
event protocol. `View.hover_region` now connects AppKit/UIKit samples to the
SwiftUI renderer through a shared ownership router. UIKit capture is compiled
for physical iOS, not physically verified. Raw gesture rendering and physical
gesture arbitration remain unfinished.

`NativePointer` carries a pointer identifier, local and global coordinates,
device kind and button bitmask. Its device enum covers mouse, touch, stylus,
inverted stylus, trackpad and unknown. Device kinds have explicit wire values;
button data uses UInt32 to preserve every protocol bit. Zero is a valid pointer
identifier. Identifiers above signed Int64 maximum and any non-finite coordinate
are rejected before an event enters the native queue.

The four payloads use tags 5 through 8. Each record contains the pointer ID,
four IEEE-754 doubles, a one-byte kind and a four-byte button mask after the
common event envelope. NativeEventQueue preserves transitions, including
consecutive events with the same tag. Capacity rejection leaves queued events
unchanged. The runtime's sequence check prevents replay from repeating handlers.

## Verification

`PointerEventTests.swift` includes a real native runtime round trip. A fixture
component uses the public OCaml hover-region and gesture constructors and four
real Driver handlers. Swift finds their bindings in the initial frame, sends
24 events covering every device kind and transition, and checks the exact
ordered history returned by OCaml. The cases include zero and maximum supported
identifiers, negative and fractional coordinates, and zero/full-width button
masks. The fixture directly exercises frame transport because its raw gesture
node is not yet supported by the SwiftUI renderer.

Separate tests cover NaN and both infinities at every coordinate, identifier
overflow, exact queue byte limits, count limits and repeated transition tags.
The queue and round-trip tests failed with `invalidHeader` while pointer
encoding was unimplemented, then passed after encoding was added.

## AppKit cursor capture

`AppKitHoverCapture` is a passive NSView with an NSTrackingArea. It requests
enter/leave events in the active application, follows the native visible
rectangle and enables enter events during mouse drags. These are public
[tracking-area options](https://developer.apple.com/documentation/appkit/nstrackingarea/options-swift.struct/enabledduringmousedrag).
It does not intercept hit testing. `HoverRouter` decides which overlapping
OCaml regions receive transitions.

The adapter represents AppKit's shared logical mouse cursor with pointer ID
zero and kind Mouse. It does not claim to identify the physical trackpad or
tablet behind that cursor. Tablet proximity/stylus capture is not implemented.
Button bits are sampled from `NSEvent.pressedMouseButtons` at callback time and
must fit the protocol's UInt32 field. This is distinct from using an event
number as a pointer identity or treating the changed button as the full mask.

Local coordinates are native view coordinates relative to its bounds origin.
Global coordinates are relative to the window content view's top-left corner,
in logical coordinates, not desktop screen coordinates or backing pixels.
Native conversion handles scaled bounds and flipped ancestors. Exit locations
may lie outside the view. Foreign-window callbacks, stale non-null tracking-area
identities and non-finite converted coordinates are rejected.

Tracking areas remain stable across ordinary updates. Disabling capture,
hiding the view, detaching it or disposing it invalidates router membership;
disposal also clears the callback and prevents re-enabling. Hidden or ordered-out
window callbacks are suppressed. BonsaiSession synchronizes capture enablement
with visibility/activity and active content; presentation acknowledgment gates
transition admission. The adapter emits raw samples only, so there is no second
per-view transition state that can disagree with overlap ownership.

`AppKitHoverCaptureTests.swift` sends native NSEvent objects to the actual NSView
callbacks. It checks coordinates, duplicate transition suppression, tracking
options and identity, hide/show, disable/re-enable, detach/reattach, disposal
and foreign-window rejection. A separate test routes the captured events
through EventBatch, NativeRuntime and the real OCaml fixture, verifying its
returned history. Initial tests failed with no area and no captured events;
follow-up tests exposed tracking-area replacement and lost re-entry after a
hidden callback. Both behavior failures are fixed.

These tests exercise native callbacks directly. They do not establish system
event dispatch, physical button-held crossings, occlusion or real cursor input.
The separate `tool/probe_appkit_hover.swift` uses an application's own SwiftUI
window, installs a tracking area and sends local mouse-moved events through
NSApplication. In the current session its window was not key and no tracking
callbacks appeared. This is an unresolved dispatch observation, not a passing
native-interaction gate or proof that the window's key state is the sole cause.
Compile it with `xcrun swiftc -parse-as-library tool/probe_appkit_hover.swift
-o /tmp/probe-appkit-hover` and run that executable to repeat the observation.

## UIKit adapter and shared input state

`UIKitHoverSource` installs two shared UIHoverGestureRecognizers per window:
one restricted to indirect-pointer input and one to Apple Pencil. Apple documents
[filtering Pencil hover by allowed touch type](https://developer.apple.com/documentation/uikit/adopting-hover-support-for-apple-pencil).
The shared logical cursor has ID zero and Mouse kind; Pencil hover uses ID one
and Stylus kind. This identifies logical input streams, not physical hardware
serial numbers. The adapter reads each recognizer's current button mask and
window-relative location. Individual `UIKitHoverCapture` views only convert
coordinates and determine geometric membership; they install no recognizers.

A custom window-attached UIGestureRecognizer also observes indirect-pointer
contact. Window attachment is necessary to observe a button-held crossing that
starts outside an individual region. The observer explicitly disables touch
cancellation and begin/end delays, declines to prevent or be prevented by other
recognizers, and permits simultaneous recognition. It never installs a global
input monitor. These settings express the intended passive behavior; actual
coexistence with native controls and scrolling has not been verified on iPad.

`HoverInput` merges both callback sources before geometric membership checks.
Mouse contact owns samples until every button is released. Hover callbacks during
that interval cannot restore stale coordinates or prematurely end the cursor.
A hover end with buttons still held is also ignored before the contact callback
arrives. Contact cancellation emits termination only for the mouse stream, leaving Pencil
independent. Invalid coordinates or IDs cannot release contact ownership.
HoverInput retains only the mouse-contact ownership flag; the router owns the
single coordinate cache and reprojects samples for layout changes. Disabling or
detaching one region preserves its window source while another region uses it.
Removing the final region disposes the source and resets its contact state.

`HoverTransitions` lives in the shared router. It emits enter/leave only when a valid
pointer changes membership, retains independent pointers and resets without
inventing exit events. The common NativePointer validator now protects both
transition state and the wire encoder. UIKit membership checks include the view
bounds, window bounds and rectangular clipping ancestors. Hidden/transparent
ancestors exclude a region from hover delivery. Layout updates re-evaluate retained samples;
renderer-level hidden branches also disable collection. Nonrectangular SwiftUI
clipping still requires integration and physical validation.

The new utility tests first failed with no state transitions or retained samples.
They now cover hover/contact priority, partial button release, resuming hover,
independent Pencil state, cancellation, reset and invalid inputs. An actual OCaml
round trip verifies a merged six-event history: mouse/Pencil enter, a button-held
mouse exit and re-entry, then separate exits, with every coordinate and mask.
Existing direct AppKit callback-to-OCaml tests still pass after using the shared
transition state.

The UIKit adapter has only been compiled for physical iOS 18. The callback
plumbing, recognizer state transitions, coordinate conversion, clipping,
hide/show, cancellation order and touch noninterference have not run on a device.
The shared-state tests do not substitute for those checks. Pencil contact/hover
transitions and AppKit tablet metadata remain unresolved.
Both platforms now share a window-source registry. Region registration, mounting
and geometry changes coalesce into one main-actor refresh, avoiding a full-region
scan for each registration. A regression mounts 128 real AppKit capture views
and checks that their registration creates one window source. This establishes
resource sharing and batching, not a complete frame-time or memory benchmark.

## Renderer ownership and lifecycle

The public API is `View.hover_region ?blocks_behind ~on_enter ~on_leave child`.
It replaces MouseRegion and its `opaque` flag without a compatibility alias.
Node kind 52 now decodes one Boolean property, exactly one child and exactly
the enter/leave handler bindings. Malformed updates are rejected atomically.
`blocks_behind` defaults to true. A front region excludes unrelated overlapping
regions behind it while preserving containing ancestors. False permits those
regions to receive hover too; it does not change Button hit testing.

RenderTree records preorder and subtree intervals in one iterative traversal.
The router uses them for front-to-back ownership, emitting departures before
arrivals and entering ancestors before descendants. Handler replacement resets
membership. Queue rejection does not advance transition state and cannot let a
new enter overtake an unaccepted leave. Hidden/unmounted regions discard their
membership without inventing removal exits. Invalid or unrelated-window samples
cannot reset another pointer's state. When no region can locate a sample, its
cached coordinate is removed so a later identical coordinate can re-enter.

BonsaiSession rejects hover before presentation acknowledgment, during pending
frames, for retired identities/bindings and after closure. Inactive sessions
discard cached coordinates. The SwiftUI background adapter is keyed by render
identity, so an epoch replacement mounts the new native view and dismantles
the old one while preserving the content's layout. AppKit has one local movement
monitor per participating window; it returns native events unchanged. Capture
controllers fence callbacks by generation and dispose retired native resources.

Gallery's actual OCaml hover component includes nested and overlapping regions,
pass-through, ordering, handler replacement, removal and a child Button.
`native/test/hover_window.swift` mounts it in a real SwiftUI application window,
posts a mouse-moved event to its own NSApplication queue and checks OCaml state through
each action, including the child Button's native accessibility action. This
proves native mounting, application-local event dispatch and model routing; it
does not prove physical pointer dispatch. The ImageRenderer test compares layout dimensions only because it
paints embedded native views as placeholders.

New regressions first failed for an unsupported node, then for retained native
capture after an epoch replacement, lost same-coordinate re-entry after window
hiding, and a foreign pointer resetting another pointer's membership. These
cases now pass through the renderer, AppKit callbacks and shared router.

## Shared window sources

`HoverWindowSources` retains a single AppKit monitor or UIKit recognizer group
for each participating window. Sources survive region reorder and handler
changes. The registry holds windows weakly and checks object identity as well
as the key, preventing an old source from surviving a recycled window address.
A generation check rejects retired callbacks, including callbacks produced
synchronously during native teardown. Losing the owner schedules source cleanup
on the main actor without retaining the window or reviving the registry.

Normal region changes are batched. Session inactivity and closure explicitly
clear the registry immediately, so a quick deactivate/reactivate cannot preserve
old mouse-contact state merely because both changes occurred before the next
layout. The native Gallery test first failed this requirement, then passed after
adding immediate session cleanup. It now also checks shared source counts,
reactivation and closure while sending the initial pointer through the app's
native event queue rather than directly calling a view's callback.

AppKit's local monitor passes events through unchanged. Apple specifies that
[local monitors do not receive events consumed by nested native tracking loops](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents%28matching%3Ahandler%3A%29).
The per-region tracking areas remain in place; button-held crossings during
native control/menu tracking still require physical verification. The older
tracking-area-only probe above remains a separate dispatch observation.

## Remaining work

The remaining native capture work must establish AppKit tablet data, UIKit
runtime behavior and physical button-held crossing behavior. A
Boolean hover callback alone does not supply all of the existing event data.
The public HoverRegion retains enter and leave handlers, with no move handler.
Nonrectangular clipping, large-region performance and
physical native-control/scroll coexistence still need acceptance evidence.

The installed iPhoneOS SDK's public `UIGestureRecognizer.h` exposes `buttonMask`
and view-relative locations. Its `UIHoverGestureRecognizer.h` documents that
hover recognition pauses while mouse buttons are held. Consequently, simply
forwarding that recognizer's begin/end callbacks cannot establish enter/leave
behavior during a button-held crossing. Native capture must resolve and test
that behavior before claiming parity. These header observations are not a
physical-device interaction result.

BonsaiSession continues to reject these payloads as text-editor input and admits
hover only for current, presented HoverRegion bindings. Raw pointer down/up
gesture admission, scroll arbitration, native mouse interaction and physical
iOS acceptance are still required.
