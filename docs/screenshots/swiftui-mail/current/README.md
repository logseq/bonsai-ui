# Current Mail runtime captures

These September 14, 2026 captures use the verified SwiftUI package-namespace
build and the explicit light application theme. They supersede the earlier
appearance evidence in the parent directory. Source remains uncommitted.

## macOS

- [Inbox](mail-macos-inbox.jpg)
- [Expanded preview](mail-macos-expanded.jpg)
- [Message detail](mail-macos-detail.jpg)
- [Archived](mail-macos-archived.jpg)

All four images are original CUA application-window JPEG bytes at 1200×760.
The application was restarted from the audited Debug bundle. Native controls
expanded Mara Vale, opened the message, archived it and selected Archived.
The accessibility state confirmed the message became read and moved to that
mailbox. The screenshots show complete sidebar/detail backgrounds and readable
preview and detail body text. Subsequent captures show an inactive window and
the capture provider's pointer highlight; these pixels were retained.

## Physical iOS

[Inbox](mail-ios-inbox.png) is the original 1170×2532 Xcode Devices screenshot
from iPhone 13 running iOS 26.6.1 (23G83). The verified signed Release App was
installed, then launched with `--terminate-existing`. The native navigation bar
and tab bar now agree with the application's light surfaces. The device's
AssistiveTouch overlay is visible and was retained. Expanded, attachment and
swipe-action acceptance requires the separate physical UI scenarios.

## Provenance

[The manifest](capture-manifest.json) records image hashes, source-file hashes,
the build checkpoint, verified binary hashes, installation location and device
launch result. Binary hashes were checked before launch. No cropping, resizing,
retouching, re-encoding or generated image content was used. System appearance
and accessibility settings were not changed. These are development captures;
they do not establish publication or completion of every widget's acceptance.
