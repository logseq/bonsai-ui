# Synchronize Native iOS Scene Activation

## Problem

A physical iPhone Capture button callback occurs while UIKit applicationState and
its UIWindowScene.activationState are both active, but BonsaiSession.isActive is
still false. SwiftUI's scenePhase onChange arrives 14 ms after the rejected touch.
The original unchanged background/foreground regression fails before opening the
editor. This is native lifecycle delivery, outside the OCaml pure state owner.

## Decision

Use the existing UIKit window attachment to observe activation notifications from
its own UIWindowScene synchronously. Initialize activation from that scene when
attaching, disable on willDeactivate/disconnect/detach, and enable on didActivate.
Keep SwiftUI scenePhase ownership on macOS only. Do not relax input admission,
queue toolbar actions, or consult another window's activation state.

The regression is a hosted UIKit test of the existing environment attachment and
BonsaiSession active state. Use actual NotificationCenter scene events, a real
window and synchronous assertions; verify deactivation, activation, foreign scene
notifications and detachment. Keep the existing physical Journal acceptance as
integration validation, without adding OCaml or transport regression coverage.

## Alternatives considered

### Delay automated taps or admit input while inactive

Rejected: the captured callback occurs after UIKit has activated the actual
scene. Sleeping would conceal delayed lifecycle delivery; removing the fence would
admit input while a scene is genuinely inactive.

### Buffer each toolbar command

Rejected: lifecycle correctness belongs to the host, not every application button.

## Acceptance criteria

- Hosted UIKit regression fails before repair and passes after repair.
- Scene notifications update admission state synchronously and affect only their
  attached window; detachment retires observation.
- Existing native input typography tests and macOS session tests still pass.
- Current physical Journal background/foreground Capture checks pass on the
  uninstrumented build; retain all previous failures and diagnostic evidence.
- Restore isolated SDK diagnostics. No protected OCaml spec or Dune changes.

## Risks

- Multiwindow ownership must use windowScene identity, never application-wide
  activation or the first connected scene.
- SwiftUI scenePhase must not overwrite UIKit's newer state on iOS.

## Questions

- None. This repairs the native host defect reproduced in the authorized iPhone
  acceptance; no commit, push or SDK publication is requested.

## Regression execution

An initial test incorrectly broadcast an NSObject as a scene on the global
notification center, causing a UIKit selector exception. A second run started
before the hosted scene was active. Neither is counted as a valid red result.
The corrected test waits for the actual UIWindowScene to become active and uses
an injected private NotificationCenter on the existing attachment. It fails five
synchronous admission/detachment assertions before implementation, then passes
afterward (0.019 s). Existing native input typography/focus/selection coverage
also passes in that same hosted suite.

The iOS scenePhase writer is removed; the macOS writer remains. The window
attachment subscribes only to its own scene, samples its activationState on
attachment, and retires subscriptions plus admission when detached. The two
changed Swift source files are copied to the existing local installed framework
for Journal build/acceptance; no native ABI, package publication, commit or push
is performed.

## Final acceptance

The uninstrumented Journal host completes three consecutive physical
background/foreground Capture/save-to-top tests, now waiting for the actual scene
to become active before interacting. Journal/Favorites detail returns and the
installed production keyboard/rotation/Close smoke pass. Diagnostic SDK package
references are removed. Exact sources and installed binaries are recorded in
logseq_journal/docs/test-reports/2026-09-16-native-swiftui-standardization/batch57-artifacts.json.

All eight relevant existing macOS session/presentation/window/environment tests
complete successfully. A broader suite exits near MenuTests without a complete
xUnit report after 154 pass messages; that run is incomplete and not counted as a
pass. No menu failure is attributed to this iOS-only ownership change.

## Consequences

UIKit window-scene notifications are the sole iOS activation owner; macOS continues using SwiftUI scenePhase. Input lifetime fences remain intact, and detached windows cannot reactivate sessions.
