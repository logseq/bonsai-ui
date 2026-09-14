# Native Morphing Surfaces

`View.Morphing_surface.create` replaces the removed
`Native_widget.Morphing_surface` extension. Mail's inline message cards and
Gallery now use the typed SwiftUI node. Its two child slots are compact and
expanded content; OCaml owns the selected branch. Swift owns interpolation.
There is no Dart registration, extension payload, no-op event handler, or
compatibility constructor for this capability.

## Composition and lifetime

Both logical branches stay mounted with their existing keyed identities.
SwiftUI retains both child views while changing opacity, expansion offset,
surface corner radius, shadow and outer insets. The expanded endpoint has
8-point horizontal and 6-point vertical insets and a 16-point corner radius.
The collapsed endpoint has no inset, corner radius or shadow. Native system
background styling follows the surrounding appearance.

A custom SwiftUI `Layout` measures each branch at the proposed content width
without compressing it into an intermediate height. With an unspecified height,
the container interpolates between measured branch heights. With a finite
height proposal it fills that height and clips its content. Mail now uses the unspecified-height path inside a measured Collection row.
The collection caches the surface's interpolated intrinsic height and owns
scroll anchoring; the surface owns its visual transition.

The default expansion duration is 240 ms with an ease-out cubic curve;
collapse takes 190 ms with an ease-in-out cubic curve. Both durations accept
unsigned 32-bit milliseconds, including zero. A changed target retargets from
the last published native progress, without advancing the previous animation
at replacement time. Unchanged-target updates, including duration changes,
do not restart the current transition. New durations govern the next target
change. Initial mounting uses the target endpoint without an entrance animation.

Reduce Motion, inactive scenes, session invisibility and disappearance finish
the current transition at its target. Returning to visibility does not replay
it. Logical removal disposes the controller and invalidates pending animation
tasks. Swift's local task samples progress; animation frames do not call OCaml.
This surface has no completion event. Mail's collection and surface receive
the same expansion intent and default timings, but the surface does not infer
its visual progress from collection row height. Changes to notice content or
row measurement therefore do not become additional surface transitions.

## Input and accessibility

Only the selected child permits hit testing, native control interaction or
accessibility exposure, including while the two branches are fading. The
validated tree propagates hidden accessibility state into the inactive branch,
so custom actions and live announcements follow the same rule. BonsaiSession
also checks every surface ancestor against both current and successfully
presented trees; a branch switch awaiting presentation admits neither branch.
Nested tab selection checks remain in force.

The native text adapter now observes SwiftUI's inherited `isEnabled` value.
An inactive surface branch disables editing, rejects insertion and submission,
and releases the native first responder. Returning retains the same text
controller, local draft and selection. This is separate from destroying the
logical editor. Physical-device IME composition during branch switching still
requires acceptance testing; the macOS regression covers an unmarked local
draft and a nonempty selection.

## Protocol and verification

Node 41 has three properties: expanded boolean, expansion duration and collapse
duration. It requires exactly two children and no bindings. The decoder rejects
invalid booleans, truncated updates, extra bindings and malformed child graphs
before publishing a tree. Property updates use mask 7. The old built-in native
extension kind 5 and its test-only payload decoder are removed.

The tests use real SwiftUI/AppKit hosting views to verify intrinsic endpoint
height, native accessibility visibility, retained node identity, interpolation,
continuous reversal, zero duration, Reduce Motion and scene inactivity. A
focused native editor regression demonstrates focus release and rejection of
hidden edits while retaining the draft and selection. A real OCaml Gallery
entrypoint exercises both branch counters and presentation-gated input through
the C bridge, without a renderer-side application reducer.

Mail now uses [core swipe actions](swiftui-swipe-actions.md), and its native
window test verifies inbox rendering, card expansion and Archive action dispatch.
Mail screenshots, actual swipe interaction, complete collection/surface alignment,
physical iOS behavior and VoiceOver acceptance remain outstanding.

The composition uses Apple's [Layout](https://developer.apple.com/documentation/swiftui/layout),
[Reduce Motion environment](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)
and [hit-testing modifier](https://developer.apple.com/documentation/swiftui/view/allowshittesting(_:)).
