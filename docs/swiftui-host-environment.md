# Native host environment

`App.Context.environment` is a reactive Bonsai input. The SwiftUI application
boundary observes and publishes native environment snapshots on both macOS
and iOS. SwiftUI preference observation and the typed OCaml transport are shared;
iOS additionally reads window geometry and keyboard occlusion through a UIKit
adapter. Physical-iOS execution of that adapter remains unverified.

## Native macOS values

The observer is a non-interactive, accessibility-hidden background of
`BonsaiApplicationView`. It remains in the application's SwiftUI view graph and
does not introduce another hosting controller or affect its layout proposal.

| OCaml field | Native source and meaning |
| --- | --- |
| `viewport_width`, `viewport_height` | Application boundary geometry in logical points, updated when it resizes. |
| `device_pixel_ratio` | SwiftUI `displayScale` for that view's display. |
| `text_scale` | SwiftUI `ScaledMetric`, relative to Body, with a unit base value. This is a Body-relative scale, not a promise that every text style scales linearly. |
| `brightness` | The boundary's effective SwiftUI color scheme. |
| `platform` | `macos`. |
| `locale` | SwiftUI locale, encoded as a BCP 47 identifier. |
| `safe_area` | Geometry safe-area insets, translating leading/trailing into physical left/right using layout direction. |
| `keyboard_insets` | Zero on macOS, which does not apply UIKit software-keyboard safe-area avoidance. |
| `accessible_navigation` | SwiftUI VoiceOver enabled state. |
| `bold_text` | SwiftUI bold legibility weight. |
| `invert_colors` | SwiftUI accessibility invert-colors preference. |
| `disable_animations`, `reduced_motion` | Both reflect SwiftUI's Reduce Motion preference. |
| `high_contrast` | Increased SwiftUI color-scheme contrast. |
| `orientation` | Landscape when boundary width exceeds height; portrait otherwise, including a square boundary. |
| `pointer_kinds` | Host capability mask, not connected-device inventory: touch=1, mouse=2, stylus/eraser=4, trackpad=8. The AppKit host advertises mouse, tablet and trackpad capabilities (`0x0e`). |

The observation APIs are described in Apple's
[SwiftUI environment documentation](https://developer.apple.com/documentation/swiftui/environmentvalues).
Observing these preferences does not itself establish that every widget honors
every accessibility preference.

## Native iOS geometry

The iOS observer is mounted at the same application boundary. SwiftUI supplies
the preference fields listed above, with platform `ios` and the UIKit host
capability mask `0x0f` (touch, mouse, stylus and trackpad, not connected-device
inventory). The Body-relative ScaledMetric follows Dynamic Type.

A transparent, non-interactive window child measures logical viewport dimensions
and physical left/top/right/bottom safe-area insets from the owned UIWindow.
The viewport remains the full window while SwiftUI adjusts content for the
software keyboard. Safe-area values are independent of keyboard values and
require no leading/trailing conversion on UIKit.

The child owns a UIKeyboardLayoutGuide with `usesBottomSafeArea = false` and
`followsUndockedKeyboard = true`. Its constrained tracking child makes keyboard
layout changes participate in native layout. The guide produces local geometry;
no screen-coordinate notifications or another window's guide are modified.
Apple describes the hidden-guide safe-area behavior and tracking controls in
[Keep up with the keyboard](https://developer.apple.com/videos/play/wwdc2023/10281/).

`NativeKeyboardOcclusion` intersects the guide frame with the viewport. A
nonempty intersection spanning an entire boundary edge becomes that physical
edge's inset. A keyboard covering the complete viewport is represented once as
a bottom inset. Floating, partial-width, internal and offscreen rectangles yield
zero edge insets: the existing edge-inset contract cannot express a floating
obstruction rectangle. Empty geometry yields zero; nonfinite or negative-sized
rectangles are rejected and cannot replace the last valid environment sample.
No pixel tolerance or arbitrary minimum keyboard height is introduced.

Window layout/safe-area changes and SwiftUI preference changes schedule a
coalesced main-actor sample. There is no idle timer. Moving/removing the mounted
source removes its window child, ends source ownership and invalidates queued
callbacks. Weak references and source/generation checks prevent a retired
observer from publishing into another window or session.

## Delivery and lifecycle

Each mounted observer has a source identity. Replacing or removing the source
invalidates its pending sample; late callbacks cannot overwrite the current
source. Invalid numeric samples leave a valid sample from the same source
intact. An invalid replacement source cannot inherit the former source's
pending sample.

The session keeps the latest sample rather than accumulating resize events.
It publishes changes during an active, visible pump after the first frame has
been presented. Unchanged samples are deduplicated, and inactive or hidden
windows publish their latest sample when they resume. Runtime control events
use zero node/handler IDs and the current displayed revision. This retains the
normal runtime transaction and presentation ordering.

Closing the session clears source ownership and sent-sample state. A newly
mounted observer republishes its environment to a restarted OCaml runtime.
The AppKit presentation probe observes window visibility directly in addition
to expose/occlusion notifications, so ordering out an already-occluded window
still suspends the session.

## Verification and outstanding acceptance

### Interactive scoped theme

Gallery's `theme_component`, also embedded as `native-theme`, demonstrates
local appearance/tint override versus inheritance, optional Menlo font, all
five native control sizes and an explicit Light child scope. Separate inside
and outside Buttons keep their counters in OCaml. Native GroupBox surfaces
keep the samples readable as the local appearance changes.

`ScopedThemeTests.swift` drives those actual native accessibility Buttons and
verifies OCaml results, retained render identities, visibility/shutdown input
fences and scoped raster output against the corresponding native SwiftUI
environment composition. The outside sample remains unchanged. The test first
failed because the runtime entrypoint was absent, then passed after the shared
Gallery implementation was added; it does not substitute a Swift-only model.

The focused environment regression passes five tests in two suites (1.896 s),
and the complete Gallery startup/dispatch case passes separately (0.413 s).
OCaml `@runtest` and `@fmt`, the macOS Gallery complete object and the updated
physical-iOS Gallery object pass. The latter declares `IOS` with minimum 18.0.
This establishes compiled iOS availability, not physical theme/VoiceOver
interaction. Evidence is recorded in
`_build/validation/swiftui-scoped-theme.json`.

### Application boundary

The `native-environment` fixture renders every value from the actual
`App.Context.environment` input. Native tests mount `BonsaiApplicationView` in
real AppKit windows and verify initial values, resizing, locale, appearance,
legibility, unchanged snapshots, inactive/hidden updates and two successive
runtime lifetimes. Additional real-runtime tests cover initial presentation
ordering, malformed samples, source replacement, late callbacks and close/reset.
The environment is not represented by a Swift-only application model.

Read-only accessibility values are compared to the current native system
settings. Tests do not change system settings, and do not establish that system
preference toggles or moving windows between displays have been physically
exercised. Nonzero safe areas, right-to-left safe-area geometry, physical iOS,
keyboard avoidance and complete application accessibility still require their
respective acceptance checks. These tests produce no Mail screenshot.

```sh
swift test --scratch-path _build/swift --no-parallel --filter 'NativeRuntimeTests/nativeHostEnvironment'
python3 tool/test_swift_platforms.py
```

Checkpoint validation: seven targeted Swift tests in three suites pass in
9.725 seconds; three platform checks pass in 21.138 seconds; OCaml all/test/
format/install passes. The full serial Swift suite passes 443 tests in 97
suites in 424.977 seconds with a verified completed xUnit report.

## UIKit observation checkpoint

Keyboard geometry tests cover docked intersections on all four physical edges,
full-window overlap, nonzero viewport origins, floating/partial/internal/offscreen
rectangles, zero-size layouts and malformed geometry. The fresh-report Swift
run passes 12 tests in four suites in 9.625 seconds, including real OCaml source
ownership and native macOS observation. OCaml all/test/format/install passes.
The standalone Host Effects App passes its complete service scenario and the
new reactive environment status in 45.881 seconds. Three platform checks pass
in 23.081 seconds, including iOS 18 module emission and all eleven App entrypoints.

Host Effects now displays reactive platform, window size, keyboard bottom inset
and safe-area values. Its physical-iOS UI test focuses the real URL field,
checks the software keyboard and a nonzero OCaml-reported inset while viewport
size remains stable, clears focus, checks zero occlusion and restarts the App.
This test is not recorded as passing: the paired iPhone is currently unavailable.
Floating/split keyboard interaction, Stage Manager, rotation, screen changes,
Dynamic Type, accessibility settings and device teardown require further actual
acceptance. The previous full 471-test Swift result predates this UIKit addition.

The iOS UI test target also passes an unsigned generic-device `build-for-testing`
using iOS 18 arm64, in isolated `HostEffectsUIKitTesting` DerivedData. Its Mach-O
platform, architecture and deployment version pass verification. This is a
compile-only test product; executing the UI test requires a signed device-test
build and the connected device, as described in [the Xcode host guide](swiftui-xcode-host.md).
All eleven iOS complete objects were refreshed; Host Effects and Mail were
rebuilt as macOS Debug and signed iOS Release Apps. Both iOS Apps pass signing,
provisioning/privacy and exact staged-object checks. The generated hosts remain
canonical. `_build/validation/swiftui-uikit-environment.json` records the source,
logs and artifact identities. No new screenshot or device execution occurred.
