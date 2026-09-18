# UIKit input regression tests

These XCTest sources exercise the UIKit representable boundary in a real hosted
application. They are separate from the AppKit-only Swift Package test target.
No OCaml session, persistence or transport operation is started. The text reducer
cannot reproduce font-category defects because it does not own font metrics or
SwiftUI environment inputs.

Generate an isolated host using `tool/swiftui_xcode_host.py`: put a minimal
SwiftUI `@main App` in a temporary application's `swift/App.swift`, copy these
`*.swift` tests into that application's `apple-tests/`, and choose this repository
as `--framework-root`. Use a unique bundle identifier and the normal physical-iOS
host configuration. Stage a current SDK-compatible arm64 iPhone complete object
at `apple/Native/iphoneos/Release/runtime.complete.o` for the generated link check.
The empty test host does not start that runtime; it only hosts native XCTest.

Run the generated iOS scheme on the device with `ENABLE_TESTABILITY=YES` so the
SDK's internal native view boundary is available through `@testable import`:

```sh
xcodebuild -project HOST/PRODUCT.xcodeproj -scheme PRODUCT-iOS \
  -configuration Release -destination id=DEVICE_UDID \
  -derivedDataPath DERIVED_DATA ENABLE_TESTABILITY=YES \
  -resultBundlePath RESULT.xcresult test
```

`InputDynamicTypeTests` checks normal, maximum, smaller, intermediate and restored
sizes for the same editor/plain/secure inputs, including a custom font, Bold Text,
retained focus/selection/marked text and secure-entry behavior. Its custom empty
keyboard prevents asynchronous system candidate updates from changing synthetic
marked text. Actual Pinyin candidate interaction remains separate app acceptance.
Keep failing results from before the fix and compare actual UIFont point sizes;
a green navigation test or a large title alone does not prove input typography.

`SceneActivationTests` uses the production UIKit window attachment and a private
NotificationCenter to check synchronous scene activation/deactivation and detached
observation without broadcasting synthetic events to UIKit itself. A real active
UIWindowScene supplies identity and initial state. The isolated notification
center is the only injected platform dependency; no OCaml session is started.
The physical Journal background/foreground regression separately exercises actual
system lifecycle notifications.
