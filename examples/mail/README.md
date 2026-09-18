# Bonsai Mail

Bonsai Mail is a fictional, local-only mail reader. OCaml/Bonsai owns its data,
paging, mailbox selection, inline previews, detail selection and application
tabs. SwiftUI is the only target, on physical iOS 26+ arm64 and macOS 26+ arm64.
Simulator is unsupported.

Mail uses a fixed light palette and explicitly requests `Theme.Light` at the
application root. Native navigation, tabs and content therefore share the same
appearance even when the device uses Dark mode. This preference only affects
Mail; it does not change the system setting. An adaptive dark Mail palette is
not currently provided.

## Navigation

The application uses native `View.Tabs` for Mail, Chat, Spaces and Meet. Mail
contains a three-column `View.Navigation_split`: mailbox sidebar, message list
and message detail. Other tabs display explicit local scope notices. Switching
tabs retains Mail's loaded messages, expanded card and selected detail.

The split requests all columns on wide layouts and the message list as its
initial compact column. Menu requests the sidebar. Selecting a mailbox shows
its list and clears any previous detail. Opening a preview selects the detail
column and marks the message read. A native return to the list clears detail
only if its observed message key still matches. Visibility-only changes retain
detail selection; stale column events cannot resurrect an old message.

SwiftUI owns system tab controls, split adaptation and safe areas. The old
combined NavigationShell, custom bottom bar, Scaffold and route-page wrappers
have been removed. The root fills the available window instead of imposing a
720-point phone layout.

## Mail behavior

- Twenty initial deterministic messages and unlimited local append pages of
  twenty messages after a 750 ms delay.
- A bounded collection window, sparse expanded-row extents and loading footer.
- Read, unread, starred, archived and trashed state; Inbox, Starred, Archived,
  Trash and Settings destinations.
- A single expanded inline preview with a two-level outline and independent
  Reply, Open, star and collapse actions.
- Message details, optional attachment tiles and explicit reply-scope notices.
- Native swipe-action containers and retained row/card morphing surfaces.

Search, composition, network accounts and persistence are outside this example's
scope. Chat, Spaces, Meet and Settings intentionally provide local placeholders.

## Current validation and runtime status

Run the actual OCaml application behavior tests from the repository root:

```sh
dune exec examples/mail/test/mail_example_tests.exe
```

The tests exercise paging, row identity, expansion, message actions, all four
tabs, native split events, stale-selection filtering and mailbox transitions.
Native Gallery applications separately exercise the SwiftUI TabView and split
controls through the production OCaml bridge.

Build the native development bundle from the repository root with the project
opam environment active:

```sh
python3 tool/build_swiftui_example.py mail
```

This generates `examples/mail/apple/BonsaiMail.xcodeproj`, then builds and
ad-hoc signs `examples/mail/apple/DerivedData/Build/Products/Debug/BonsaiMail.app` against Mail's
real OCaml complete object. Its SwiftUI entrypoint uses a 1200×760 macOS window
and an iOS WindowGroup. The previous Flutter host and configuration are removed.

The complete Mail tree now stages through SwiftUI, including native morphing
surfaces and swipe-action containers. `python3 native/test/test_mail_window.py`
checks inbox rendering, a usable list column width, expansion and Archive action
dispatch through the real OCaml model in a standalone App window. It starts
separate processes with light and dark inherited AppKit appearances and checks
that Mail's native content remains light before and after mailbox navigation.

Native mouse swipe acceptance now passes for the tested axis and layout-direction
cases. Four reviewed macOS window captures and an iPhone Inbox capture exist
at an earlier source checkpoint; see the [capture evidence](../../docs/screenshots/swiftui-mail/README.md).
The appearance fix passes the macOS native window scenario in both inherited
appearances (34.928 seconds). Its physical iOS appearance, remaining interactions
and fresh screenshots are still unverified. Optional offscreen NSView bitmap
exports omit native compositor content and are diagnostic only. See
[swipe actions](../../docs/swiftui-swipe-actions.md) and
[Mail navigation](../../docs/swiftui-mail-navigation.md) for current evidence.


## Xcode host and packaged runtime test

The generated project has separate macOS and physical-iOS targets with
Debug/Profile/Release configurations. Application Swift sources remain in
`swift/`; the project links the local Swift package and a verified complete
object staged by the helper. Regenerate without building with
`python3 tool/build_swiftui_example.py mail --generate-only`.

After the normal macOS build, run the packaged runtime test:

```sh
xcodebuild -project examples/mail/apple/BonsaiMail.xcodeproj \
  -scheme BonsaiMail-macOS -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath examples/mail/apple/DerivedData test
```

`apple-tests/MailRuntimeTests.swift` opens the actual Mail entrypoint, observes
the first message frame, acknowledges presentation, pumps and repeats startup
in a separate XCTest process. The iOS Release test target now builds and signs
successfully for physical iOS 26 arm64. An earlier source checkpoint passed
startup/presentation/restart on iPhone 13. The current Release App has since
been installed and launched there, and a fresh Inbox capture confirms the light
appearance. Expanded/detail/swipe UI scenarios still require XCTest passcode
authorization on the device. See
[Xcode host details](../../docs/swiftui-xcode-host.md).

The physical iOS 26 Release App now cross-compiles, links with the real OCaml
Mail complete object, and builds with development signing. Its bundle passes
deep/strict signature verification and contains a provisioning profile:
`apple/DerivedData/Build/Products/Release-iphoneos/BonsaiMail.app`.
The final executable is iPhoneOS arm64 with minimum 26.0. Current-device installation and Inbox appearance are now recorded in the
[September 14 captures](../../docs/screenshots/swiftui-mail/current/README.md).
Remaining physical interaction screenshots and final release provenance stay open.
See [toolchain and cross-build instructions](../../docs/swiftui-ios-toolchain.md).


## Native CLI consumer

This example owns `bonsai-swiftui.sexp`, its OCaml sources and `swift/`.
Prepare the source-checkout environment described in the [root README](../../README.md),
then run from this example directory:

```sh
"$BONSAI_SWIFTUI_CLI" build macos --profile debug
"$BONSAI_SWIFTUI_CLI" run macos --profile debug
"$BONSAI_SWIFTUI_CLI" sync-host --check
```

The CLI builds this example's `ocaml/native_embed.exe.o` as an independent Dune
project and generates the `apple/` Xcode host. Swift and OCaml sources remain
application-owned. See the [CLI guide](../../docs/swiftui-cli.md) for optimized
configurations, signing and physical-iOS builds with an explicit iOS 26 object.
The old OCaml package identifiers and installed SDK publication remain part of
the unfinished repository migration.
