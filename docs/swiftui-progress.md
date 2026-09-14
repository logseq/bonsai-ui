# SwiftUI progress

`View.progress` represents determinate or indeterminate activity with one
SwiftUI `ProgressView` and a native SwiftUI style. The default style is Linear;
Circular is explicit. A provided value must be finite and in `0..1`, including
both endpoints. Omit the value for activity whose completion fraction is not
known. The control has no children or event handlers.

```ocaml
Ui.View.progress ~value:0.25 ~style:Ui.View.Progress_style.Circular ()
|> Ui.View.semantics
     ~properties:(Ui.Semantics.create ~label:"Downloading attachments" ())
```

The application owns progress and completion. Updating the fraction, switching
to indeterminate activity, or changing between Linear and Circular updates the
same keyed node; it does not create a replacement node or a completion event.

## Rendering and accessibility

The renderer uses `ProgressViewStyle` with SwiftUI shapes. This is necessary to
preserve determinate circular progress on both supported platforms: Apple's
[built-in circular style](https://developer.apple.com/documentation/swiftui/progressviewstyle/circular)
may use indeterminate presentation when a determinate style is unavailable.
The common style also provides an animated indeterminate linear bar on both
platforms. There is no runtime style fallback or Flutter layout implementation.

Linear progress fills from the native leading edge, including right-to-left
layout. Circular progress starts at the top and advances clockwise. Both use
the scoped tint. Native control size determines circular diameter and linear
thickness; the linear control accepts available width and has a 160-point
ideal width. Use ordinary Frame and environment modifiers to place and style
the control.

Indeterminate activity uses a SwiftUI TimelineView with a 1.4-second period and
a minimum update interval of 1/30 second. No animation tick calls OCaml.
Determinate values draw directly. The timeline pauses when its view disappears,
the session becomes inactive or invisible, the scene is inactive, or Reduce
Motion is enabled. A paused indeterminate control retains a static activity
mark rather than claiming a completion percentage.

The outer ProgressView preserves native accessibility semantics. On tested
macOS, determinate controls expose AXProgressIndicator, the numeric fraction,
a zero-to-one range and a localized percentage description. Indeterminate
controls expose AXBusyIndicator with no percentage description. Use Semantics
for an application-specific label or live status; a changing progress value
does not independently enqueue announcements.

## Removed surface

The Material circular_progress_indicator, linear_progress_indicator and
loading_indicator APIs are removed. All current OCaml consumers use
`View.progress`. Flat/Wavy progress variants and contained/uncontained loading
variants are removed as Material presentation choices; native progress style
and ordinary background/padding composition replace that appearance. There
are no old constructor aliases.

Wire node 10 has two properties: optional f64 value and a circular boolean.
Its update mask is 3. Values outside `0..1`, non-finite values, invalid flags,
children, event bindings and malformed payloads are rejected. The old dedicated
Material progress node IDs 108 and 124 are absent from the active schema and
OCaml/Swift codecs.

## Verification and outstanding acceptance

OCaml tests cover bounds, logical equality, fingerprints, stable keyed updates
across styles and modes, and protocol round trips with invalid encode/decode
cases. Swift tests reject malformed frames atomically and measure actual
painted progress at 0%, 25%, 75% and 100%, including right-to-left leading-edge
behavior.

The actual Gallery `progress_component` runs through the C/OCaml runtime and
cycles 25%, 75%, indeterminate and 100%. Native window tests verify accessibility
values and mode changes, retained renderer objects, moving indeterminate
pixels and frozen pixels after session deactivation, without advancing the
presented OCaml revision during animation. The full Swift module is also
checked against the physical iOS 18 arm64 SDK.

These tests do not verify physical-device execution, system VoiceOver speech,
or toggling the system Reduce Motion setting. The latter is read directly
from SwiftUI's environment and still needs system-setting acceptance. Test
window pixel captures are internal assertions, not the requested Mail
screenshots.

Mail now uses the native Progress control for paging and native plain Buttons
for its icon/text actions. Its existing headless behavior suite still covers
paging, expansion, nested actions, mailbox changes and details. Mail's full
native navigation, generic swipe interaction, remaining wrappers, packaging
and real runtime screenshots remain unfinished.
