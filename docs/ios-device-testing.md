# Testing SwiftUI on a physical iOS device

The supported target is physical iOS/iPadOS 26.0+ arm64. Use Xcode and the
OCaml 5.1.1 toolchain pinned in `tool/ios/toolchain.lock`. There is no
Catalyst or Intel test lane. The iOS Simulator lane
(`build ios --simulator` / `run ios --simulator`) exists for development
iteration but is not a substitute for this device acceptance. The application
links its real OCaml complete
object into a native SwiftUI Xcode host.

## Device and development signing

The selected device must be connected, paired and trusted, have Developer Mode
and developer disk image services available, and be currently unlocked after
having been unlocked at least once since boot. Select its exact CoreDevice UUID
or hardware UDID. A device name is insufficient for the CI preflight.

Development execution needs an Apple development identity and provisioning
profile covering the application bundle identifier, Team ID and selected
device. Distribution identities are not prerequisites for an ordinary
local development run. Keep certificates, private keys, profile contents and
passwords out of the repository and shell history.

When device access is available, verify the selected hardware from the
repository root:

```sh
tool/ci/ios_device_preflight.sh "$IOS_DEVICE_ID"
```

This uses CoreDevice to validate physical iOS 26+ arm64, pairing, Developer
Mode, developer services and unlock state. It does not install or run an app.
Do not loop this command while the device is unavailable.

## Build, install and launch

With the consumer packages and published iOS toolchain installed:

```sh
make ci-ios-device EXAMPLE=mail \
  IOS_DEVICE_ID="$IOS_DEVICE_ID" \
  IOS_DEVELOPMENT_TEAM="$IOS_DEVELOPMENT_TEAM"
```

The Make target installs its consumer/toolchain prerequisites, runs hardware
preflight, builds the CLI and runs the selected example in Debug. The CLI
builds, signs, installs and launches the native app. This target does not run
XCTest, verify a restart, archive/export Release or establish distribution
signing. The current SDK snapshot still awaits regeneration from a published
SwiftUI source commit; see [packaging](packaging.md).

During source development, an already verified physical-iOS complete object
can be supplied directly. From `examples/mail`, with absolute paths in
`REPOSITORY_ROOT` and `MAIL_IOS_OBJECT`:

```sh
BONSAI_SWIFTUI_SOURCE_ROOT="$REPOSITORY_ROOT" \
  "$REPOSITORY_ROOT/_build/default/bonsai_swiftui_tool/bin/main.exe" \
  build ios --profile release --native-object "$MAIL_IOS_OBJECT" \
  --development-team "$IOS_DEVELOPMENT_TEAM"
```

This builds a signed generic iPhoneOS application without operating a device.
The object must already pass the iOS 26 arm64 and ABI checks. A macOS object
cannot be reused. The generated Mail project is
`examples/mail/apple/BonsaiMail.xcodeproj`; products are under that host's
`DerivedData` directory.

## Runtime and UI tests

Run the application-owned Mail UI suite from the repository root once the
current native object and signed app have been staged:

```sh
xcodebuild -project examples/mail/apple/BonsaiMail.xcodeproj \
  -scheme BonsaiMail-iOS -configuration Release \
  -destination "platform=iOS,id=$IOS_DEVICE_ID" \
  -derivedDataPath examples/mail/apple/DerivedData \
  -resultBundlePath "$MAIL_UI_RESULT_BUNDLE" \
  -only-testing:BonsaiMail-iOSUITests \
  DEVELOPMENT_TEAM="$IOS_DEVELOPMENT_TEAM" test
```

Choose a new, nonexistent result-bundle path for each run. The UI runner drives
the separate real Mail application; it does not link a second OCaml runtime.
It covers expansion/collapse, the attachment-bearing message, and swipe Archive.
The separate `BonsaiMail-iOSTests` bundle covers hosted runtime lifecycle and
Dynamic Type; select that bundle in `-only-testing` to run it independently.
The generated scheme includes both bundles, so selecting one keeps failures
and capture provenance attributable to the intended boundary.

If Xcode asks to unlock the device or enable UI Automation, complete that
system confirmation on the device. A runner timeout before any test starts
is not an application test failure or a passing run. Reuse `test-without-building`
only when the app and test products still match the intended source and
configuration and the only change is device readiness or system authorization.
After source changes, build the current products again. Preserve the original
result bundle and the test log; do not repeatedly rebuild while waiting for a
phone or authorization prompt.

Interrupted runs and incomplete `.xcresult` bundles are not passing evidence.
Require named test results and inspect their original screenshot attachments.
[Physical Mail captures](screenshots/swiftui-mail/physical-interaction/README.md)
record the existing expansion/attachment pass and the interrupted swipe retest.
The UIKit text-input contract and its physical hosted tests are described in
[text input](swiftui-text-input.md). No new physical acceptance is implied by
this guide.

## Signature and distribution checks

`tool/ci/verify_ios_bundle.sh <App.app> development` checks the actual signature,
profile, bundle identifier, Team ID, expiry, authorized signing certificate,
typed entitlements and native target metadata. See [testing](testing.md) for
its optional dSYM/SQLite checks and the signed-bundle regression fixtures.

The optional `ios_device_preflight.sh ... --require-signing` path additionally
requires both development and distribution profiles and certificates, with at
least 30 days remaining. `tool/ci/install_ios_signing.sh` prepares temporary
keychain/profile material for a configured signing lane and supplies cleanup.
Those stricter inputs do not make the ordinary `ci-ios-device` target an
archive/export lane. A successful development run does not establish App Store,
TestFlight, distribution export or every widget's physical-device acceptance.
