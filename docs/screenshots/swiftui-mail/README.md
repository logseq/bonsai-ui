# SwiftUI Mail capture evidence

The [September 14 current captures](current/README.md) supersede the older
appearance evidence below: four macOS states and a fresh physical-iOS Inbox
now use the verified package-namespace build with Mail's explicit light theme.
The sections below retain their original checkpoint provenance.

Four complete macOS application-window captures are now available from the
running SwiftUI Mail App linked to the real OCaml program:

- [Inbox](mail-macos-inbox.png): sidebar, inbox and detail placeholder.
- [Expanded preview](mail-macos-expanded.png): Mara Vale's complete field notes.
- [Message detail](mail-macos-detail.png): the same message opened in the third column.
- [Archived](mail-macos-archived.png): Mara Vale after the native Archive action.

These captures show the sidebar, native backgrounds, icons and full expanded
text that were missing from the earlier cache exports. They were reviewed for
missing layers, clipping, overlapping controls and incorrect state. Physical-iOS
expanded-preview, swipe-action and detail captures, appearance fixes and final release provenance remain unfinished.

## Appearance fix after these captures

Mail now explicitly requests `Theme.Light` to match its fixed light palette.
The actual macOS window test first reproduced the inherited-dark mismatch,
then passed from both light and dark AppKit environments after the change,
including expansion, Archive and mailbox navigation (34.928 seconds).
No system appearance was changed. The existing images below predate this fix;
physical iOS appearance and fresh full-window captures remain unverified.

## Physical-iOS Inbox capture

[Inbox on iPhone 13](mail-ios-inbox.png) is an original 1170×2532 PNG from Xcode
Devices, captured after reinstalling the verified Release App and launching
with `--terminate-existing`. The adjacent JSON records source hashes, the exact
installed executable/native-object hashes, signing verification and install/
launch evidence. This fresh launch displays Inbox correctly. The device runs
iOS 26.6.1 (23G83). Dark native navigation chrome surrounds Mail's explicitly
light content surfaces; appearance consistency still requires visual work.
No image pixels or system settings were changed.

## First physical-iOS diagnostic

[Initial Mailboxes in Dark appearance](diagnostics/mail-ios-mailboxes-dark.png)
is an earlier original 1170×2532 PNG captured by Xcode Devices on an iPhone 13 running
iOS 26.6.1 (23G83), after successful App installation and launch. The adjacent
JSON records original/output hashes, binary hashes, environment and capture
method. Its installed executable identity is unverified because Xcode rebuilt
the local App between installations; the reinstalled Inbox capture above has
the exact build provenance. No pixels or system settings were changed.

This image exposes inadequate contrast between hard-coded Mail foreground
colors and the black system background. It shows Mailboxes, but its navigation history is unverified. A subsequent
reinstall/fresh launch displays Inbox correctly, so this image does not prove
an initial compact-column defect. It is diagnostic evidence, not a passing
visual-acceptance capture. Expanded preview, swipe actions and
detail-with-attachment remain outstanding. The separate
physical runtime XCTest passes startup, presentation and restart; that test
does not cover these visible defects.

## Current capture provenance

- Source: base commit `39c486233d0a1a614c6cb1267a80fa19d6076fcc` plus the current
  uncommitted migration. `capture-manifest.json` records 290 source-file hashes,
  the running executable path and the audited executable/native-object hashes.
- App: `examples/mail/apple/DerivedData/Build/Products/Debug/BonsaiMail.app`,
  rebuilt at the `native-node-services` checkpoint. The running process path was
  checked against this bundle.
- Xcode: 26.1.1 (17B100). Runtime: macOS 26.6.2 (25G83).
- Hardware: Mac Studio, Mac16,9, Apple M4 Max. The connected AG493UG7R4 display
  reports 6400×1800 physical pixels and 3200×900 logical points, a 2× display
  scale. The App requests a 1200×760-point default window; the capture provider
  returns 1200×760 pixels. No interactive resize was performed during capture.
- Appearance: Light, observed in the captured App. System appearance settings
  were not changed.
- Capture: CUA `App.getScreenshot` / `App.getAXStateAndScreenshot`. The original
  JPEG bytes are retained in `capture-originals/`. PNGs are lossless re-encodings
  of those JPEG pixels; dimensions and every decoded RGB pixel were verified
  equal. No cropping, resizing, compositing, retouching or generated imagery was
  applied. Adjacent JSON files record original/output hashes and write times.
- Fixture state: fresh Mail inbox → expand Mara Vale → Open message (marks read)
  → Archive → select Archived. Each operation used the actual native control and
  updated the OCaml model. No external mail service or real mailbox is involved.

To reproduce, build Mail with the native CLI as documented in
[the CLI guide](../../swiftui-cli.md), launch the generated macOS App from a fresh
process, and follow the fixture sequence above. Capture the complete App window
and retain the original bytes and source/binary provenance. A committed final
source/SDK release is still required for release-level reproduction.

## Earlier diagnostic captures

The files in `diagnostics/` are unedited
NSView.cacheDisplay exports from a running standalone SwiftUI App linked to the
real OCaml Mail application. They are useful for inspecting the current message
list and expanded card, but are not complete application-window screenshots.

## Captured diagnostic states

- [Inbox](diagnostics/mail-macos-inbox.png), presented revision 2.
- [Expanded Mara Vale preview](diagnostics/mail-macos-expanded.png), presented
  revision 5. The native button dispatched the expansion through OCaml.
- [Archived mailbox](diagnostics/mail-macos-archived.png), presented revision 9.
  The native Archive action removed Mara Vale from Inbox; the sidebar's Archived
  button then selected the mailbox containing that message.

Visual inspection found missing sidebar content and incomplete background/native
layer capture. The detail area appears black/transparent, and some expanded text
is truncated. These images cannot establish correct sidebar/detail layout,
background composition, complete controls or visual acceptance. The desktop was
locked when checked; a complete window capture is still required to distinguish
export limitations from application layout defects. No pixels were filled,
composited, redrawn or generated to conceal missing output.

The extended native window test finds all five mailbox buttons and the detail
placeholder, and successfully selects Archived and returns to Inbox. This
establishes mounted controls and working OCaml state transitions despite the
missing exported sidebar pixels. It does not establish visible rendering or
rule out layout defects; the complete window capture is still required.

## Reproduction and provenance

- Source: base commit `39c486233d0a1a614c6cb1267a80fa19d6076fcc` plus the uncommitted
  SwiftUI migration worktree at capture time, September 13, 2026. This is not a
  reproducible committed release snapshot.
- Toolchain: Xcode 26.1.1, build 17B100; Swift 6.2.1.
- Runtime: macOS 26.6.2, build 25G83, Apple Silicon model identifier Mac16,9.
- Native content size: 1200 by 760 points; exported size: 2400 by 1520 pixels
  (2x). The capture excludes desktop composition and window chrome.
- Appearance: the application requests System mode; the content view reports
  `NSAppearanceNameAqua` at capture time. The adjacent JSON files record this
  native value, the 2x backing scale and the 1200 by 760 point content bounds.
- Fixture: `native/test/runtime_fixture.ml` registers the actual `Mail.app` as
  `mail-collection`; `native/test/mail_window.swift` starts
  `BonsaiApplicationView`, waits for presented inbox content, exports the content,
  presses Mara Vale, exports the expanded preview, verifies Archive removes the
  item through OCaml, selects Archived and exports that mailbox, then returns to
  Inbox and verifies the item remains absent. No Swift-only mail model is used.
- Adjacent JSON files record the state, presented revision, dimensions, runtime
  version, capture method and UTC timestamp.

Run from this worktree:

```sh
opam exec --switch=bonsai-ui -- dune build @all
BONSAI_MAIL_CAPTURE_DIRECTORY=/tmp/mail-content-export \
  python3 native/test/test_mail_window.py
```

The September 13 diagnostic run passed the extended native window scenario in
24.776 seconds (`/tmp/swiftui-mail-sidebar-final.log`). Passing that interaction
gate does not qualify the exported images as complete screenshots.

## Still required

Repeat the reviewed macOS captures against the final published source snapshot.
Physical iOS inline preview, swipe actions and detail-with-attachment captures
remain outstanding. Repeat Inbox after appearance fixes. Simulator is unsupported.
