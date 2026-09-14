# SwiftUI window host services

`Host_effect.set_window_title` and `Host_effect.set_window_size` now use the
window owned by the calling `BonsaiApplicationView`. They never select
`NSApp.keyWindow`, `UIApplication.shared` window lists or another application's
window. Successful requests return an empty unit response to the actual OCaml
handler; unavailable windows and unsupported operations return a typed failure.

## Binding and lifetime

Each `BonsaiSession` owns a `NativeWindowHost`. Its presentation probe attaches
the actual NSWindow or UIWindow and identifies the presenting native view as
the owner. Window and view references are weak. A removed old probe cannot
detach a newer owner. Moving to another window releases the old binding before
capturing the new window's original title. View dismantling and session closure
release ownership; detached requests fail instead of choosing another window.
Visibility notifications and presentation acknowledgments also require the
current owner. A replaced probe cannot hide the new owner or acknowledge a
frame from its obsolete view. The current owner reports disappearance before
releasing its binding.

Requests share host-service presentation/visibility/activity gates, request IDs,
bounded responses, cancellation and session shutdown. A request in an
unacknowledged frame cannot mutate the window. Same-frame cancellation prevents
the operation from starting, and session close cancels queued operations before
releasing the window binding.

## Titles

The native targets are `NSWindow.title` on macOS and `UIWindowScene.title` on iOS.
iOS requires an attached scene; an unattached UIWindow cannot report success.
Titles use the existing bounded UTF-8 string transport, including empty strings.

An imperative title remains effective through ordinary view updates when the
application's declared title is unchanged. A changed declarative application
title replaces the imperative override. Detach/reset restores the inherited
title only if the current title is still owned by this host; it does not undo
an unrelated external title change.

## Sizes

macOS requests set the native window's **content size** in points, using
`NSWindow.setContentSize`. Window decoration is excluded and native window
constraints remain applicable. Width and height must be finite and strictly
positive; invalid geometry rejects the frame before any effect executes.

iOS returns `Window resizing is not supported on iOS` through the normal
Host_effect failure path. The selected UIKit SDK's
[`GeometryPreferences.iOS`](https://developer.apple.com/documentation/uikit/uiwindowscene/geometrypreferences/ios)
provides orientation preferences rather than a width/height scene-size request.
Changing the content view's frame would not establish a resized system window.
No Catalyst, visionOS or Simulator API is substituted for the supported iOS
target. This platform result does not close physical-device acceptance.

## Example and evidence

Host Effects exposes **Rename window** and **Resize window**. OCaml requests a
Unicode title and a 760-by-560 content size, and renders success or the native
error. The application remains responsive to subsequent host operations.

The native window regression first reproduced the absent action
(`/tmp/swiftui-window-host-native-red.log`). The frame test independently
reproduced unsupported valid window requests
(`/tmp/swiftui-window-host-wire-red.log`). Related tests cover actual NSWindow
mutation, two-window isolation, owner replacement, original-title restoration,
invalid input, cancellation, pre-presentation/inactive deferral and shutdown.

A supplemental two-probe test reproduced two stale callback failures: the old
probe acknowledged the replacement's frame and reported it invisible when
removed (`/tmp/swiftui-window-host-owner-red.log`). Ownership checks now fence
scheduled visibility/layout callbacks, presentation completion and dismantling.
All 16 related tests pass (`/tmp/swiftui-window-host-owner-green.log`).

The standalone actual OCaml/SwiftUI App test passes
(`/tmp/swiftui-window-host-native-final.log`): native buttons change the title,
the title survives a subsequent platform-information response, and the actual
content rect becomes 760 by 560 points. It uses an isolated pasteboard and its
own window, without requiring desktop keyboard focus.
The final Host Effects and Mail window regressions both pass
(`/tmp/swiftui-window-host-native-regression.log`). The iOS 18 module/example
compilation and explicit Simulator/Intel rejection checks pass
(`/tmp/swiftui-window-host-platforms-final.log`).
The complete Swift regression run passes all 376 tests in 84 suites
(`/tmp/swiftui-window-host-full-final.log`, 330.938 seconds). Host Effects and
Mail were rebuilt as macOS Debug and signed physical-iOS Release Apps after
these changes. Their executables pass arm64/minimum 26.0 or 18.0 checks, and
all four bundles pass deep/strict signature verification
(`/tmp/swiftui-window-host-bundle-audit.log`). Host Effects' changed OCaml
program was cross-built again before staging its iOS object
(`/tmp/swiftui-window-host-ios-object.log`).

```sh
python3 native/test/test_host_effects_window.py
```

iOS scene-title behavior and the resize failure response still require device
execution. No new complete Mail screenshot is implied by these window tests.
