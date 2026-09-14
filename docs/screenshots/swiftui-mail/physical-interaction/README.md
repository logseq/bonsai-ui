# Physical Mail interaction captures

Captured on September 14, 2026 by the application's XCUITest runner on a
physical iPhone 13, iOS 26.6.1, with Xcode 26.1.1. These are complete system
screenshots at 1170 × 2532 pixels (390 × 844 points, 3× scale), using Mail's
application-owned light appearance and deterministic fictional messages.

The source is the uncommitted SwiftUI migration based on
`39c486233d0a1a614c6cb1267a80fa19d6076fcc`, after the internal spec-module rename
and before the conditional swipe-pane fix. No source or SDK was published.

| File | State reached through native UI input |
| --- | --- |
| `ios-inbox.png` | Fresh launch with twenty initial messages. |
| `ios-expanded.png` | Tap Mara Vale to expand its inline preview. |
| `ios-detail-attachment.png` | Collapse Mara, expand Juniper Works and tap Open; the detail contains `Miniature-landscape-guide.pdf`. |

The `MailUITests.testInboxExpansionAndAttachmentDetail` scenario passed in
16.595 seconds. Original attachments are preserved in
`/tmp/swiftui-mail-authorized-ui-confirmed.xcresult` and exported under
`_build/validation/swiftui-mail-authorized-ui`. The separate swipe scenario in
that run failed because hidden Archive buttons also appeared as hittable
accessibility elements. It does not establish successful physical Archive.

The conditional-pane fix passes focused macOS and native mouse-input tests and
a generic iPhoneOS Release build. Its device retest was interrupted when the
user temporarily removed the iPhone. Re-run the application-owned iOS UI tests
after device access is restored; do not count that interrupted run as passing.

Reproduction after staging the current verified iOS complete object and building
the signed Mail app:

```sh
xcodebuild -project examples/mail/apple/BonsaiMail.xcodeproj \
  -scheme BonsaiMail-iOS -configuration Release \
  -destination 'platform=iOS,id=DEVICE_UDID' \
  -derivedDataPath examples/mail/apple/DerivedData \
  -only-testing:BonsaiMail-iOSUITests DEVELOPMENT_TEAM=YOUR_TEAM test
```

Use a new result-bundle path with `-resultBundlePath` to preserve each run.
System UI Automation confirmation must be completed on the device.
