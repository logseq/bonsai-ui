# SwiftUI Counter iOS Simulator capture

[Counter on iPhone 17 simulator](counter-iossimulator.png) is an original
1206×2622 PNG captured with `xcrun simctl io booted screenshot` on an
iPhone 17 iOS Simulator (runtime 27.0), after
`bonsai-swiftui run ios --simulator --profile debug` booted the device,
installed the ad-hoc-signed application and launched it. The adjacent
`capture-manifest.json` records the source commit, running executable hash,
complete-object verification (platform IOSSIMULATOR, minos 26.0, sdk 26.5)
and capture method. No image pixels or system settings were changed.

This is a **simulator capture**, not a physical-device capture. Simulator
lanes verify build, launch and OCaml state changes but do not replace the
physical-iPhoneOS gates, which remain the authoritative acceptance target.

## State-change evidence

The hosted XCTest suite `BonsaiCounter-iOSUITests` executed inside the same
simulator: it found the Increment button by accessibility label, tapped it
twice, and observed the OCaml-rendered state advance `Count: 0` →
`Count: 1` → `Count: 2` before terminating the application.
