# Native haptic feedback

`Host_effect.haptic_feedback` submits an interaction's feedback request after its
OCaml frame is presented and the application is active and visible. BSFR kind
12 carries one byte: light (0), medium (1), heavy (2) or selection (3). Both the
existing OCaml encoder and Swift decoder use these values. Invalid kinds,
truncated bodies and trailing data reject the complete frame atomically.

## Platform behavior

On iOS 18+, light/medium/heavy use the corresponding
[UIImpactFeedbackGenerator](https://developer.apple.com/documentation/uikit/uiimpactfeedbackgenerator)
style; selection uses UISelectionFeedbackGenerator. The generators attach to the
owned window's root View through the current
[view-based initializer](https://developer.apple.com/documentation/uikit/uifeedbackgenerator/init(view:)).
The host caches at most three impact generators and one selection generator per
View. Replacing the View or resetting its window removes those interactions and
clears the cache. No global key-window selection or deprecated initializer is used.

macOS uses
[NSHapticFeedbackManager.defaultPerformer](https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager)
with the generic pattern and immediate performance time. AppKit's native pattern
set has no impact weights or selection pattern; all four logical requests map
to generic feedback. Its alignment and pressure-level patterns represent other
interactions and are not used to imitate impact strengths. The native performer
accounts for the input device, accessibility settings and user preferences.

`Ok ()` means the native request was submitted, not that physical feedback was
observed. These APIs do not return a delivery acknowledgment. Unsupported
hardware or system settings may suppress feedback. The host does not override
preferences, substitute sound/vibration, or schedule repeated feedback.

## Cancellation and ownership

The service checks runtime ownership, successful presentation, activity,
visibility and the native window again immediately before submission. Missing
ownership returns a host error. Lost activity or native visibility returns
cancellation. A same-frame request/cancel pair is cancelled before its task can
submit feedback. Once a synchronous native request has been submitted, later
cancellation cannot retract physical output.

The existing dispatcher assigns request identities, returns a single bounded
response and rejects late completion after reset. Repeated valid requests retain
separate OCaml continuations; they are not merged. A hidden or closed application
cannot submit feedback through a retained callback from an earlier lifetime.

## Example and evidence

Host Effects has four native Buttons, `Haptic light`, `Haptic medium`, `Haptic
heavy` and `Haptic selection`. Its separate status reports, for example,
`Haptic: light requested`, expressing submission rather than physical delivery.
No request is triggered automatically at application startup.

The native runtime tests execute the real OCaml effect for each kind and eight
repeated selection requests. They cover presentation, inactive/hidden deferral,
same-frame cancellation, missing windows and restart. An execution-time test
checks native service admission after activity or actual window visibility has
changed. The standalone SwiftUI App presses each example Button and observes
its OCaml response. These tests call the system performer; they do not replace
it with a synthetic success provider or assert that a human felt feedback.

Verification at this checkpoint:

- OCaml `@all @runtest @fmt @install` passes.
- The related Swift run passes 11 tests in four suites in 0.691 seconds,
  with a fresh completed Swift Testing xUnit report after the UIKit refactor.
- The standalone Host Effects App passes its native service scenario in
  42.030 seconds, including all four haptic requests.
- Three platform checks pass in 22.550 seconds: iOS 18 module emission, all
  eleven Swift example entrypoints and rejection of unsupported targets.

```sh
swift test --scratch-path _build/swift --no-parallel --filter 'haptic|HapticWireTests|nativeHaptics|HostServicesTests'
python3 native/test/test_host_effects_window.py
python3 tool/test_swift_platforms.py
```

Physical-iOS interaction, generator reuse/teardown on a device, Force Touch
perception and system-preference behavior remain unverified. The previous full
Swift regression (462 tests) precedes this haptic change; the new behavior has
the scoped runtime, standalone-App and platform checks above. Final migration
acceptance still requires a complete current-source regression and device evidence.

All eleven OCaml example objects also cross-build for iOS 18 arm64. Target, ABI
and prohibited-process-import checks pass. Host Effects and Mail rebuild
through the public CLI as macOS Debug and signed iOS Release Apps; both iOS
bundles pass native App/privacy and provisioning/certificate authorization
checks. The staged iOS objects match their cross-build hashes. The remaining
nine example Apps retain earlier linking provenance. No physical execution or
new screenshot is claimed. `_build/validation/swiftui-haptics.json` records this
checkpoint and `_build/validation/swiftui-haptics-ios-objects.json` lists all
current objects.
