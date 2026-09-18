# SwiftUI example build evidence

## Haptic feedback checkpoint

All eleven current OCaml complete objects cross-build for physical iOS 18 arm64
and pass target/ABI checks with no prohibited process imports. Object hashes are
in `_build/validation/swiftui-haptics-ios-objects.json`. Host Effects and Mail
relink through the public CLI as macOS Debug and signed iOS Release Apps, using
these exact iOS objects. The signed iOS Apps pass the native App/privacy and
provisioning/certificate authorization audit. Other example Apps retain their
earlier link provenance even though their native objects have been refreshed.

The standalone Host Effects App passes native menu selection, four haptic
requests and its existing services in 42.030 seconds. The iOS 18 Swift module
and all eleven example entrypoints compile; the three platform checks pass in
22.550 seconds. macOS CLI source builds require this worktree's installed
libraries first in OCAMLPATH while the replacement packages are unpublished.
No physical-device run, new Mail capture or source/SDK publication occurred.

## Action-menu checkpoint

Host Effects and Mail rebuild as macOS Debug Apps with the current SwiftUI
renderer and OCaml objects. Deep/strict signatures and arm64/macOS 26 complete
objects verify; both generated projects pass `sync-host --check`. Host Effects'
standalone native window test passes actual menu selection and the existing
services in 40.996 seconds. The full Swift regression passes 462 tests in 101
suites in 469.588 seconds.

The current Swift module emits for physical iOS 18 arm64, and all eleven example
Swift entrypoints typecheck against it. The three platform checks pass in
22.264 seconds, including explicit Simulator/Intel rejection. This checkpoint
does not rebuild cross-compiled iOS objects or relink signed iOS Apps; those
records below retain their earlier source provenance. Opening the rebuilt Mail
for a fresh capture still reports the Mac locked. No new screenshot or physical
execution is claimed. See `_build/validation/swiftui-host-menus.json`.

## Notification and source-removal checkpoint

All eleven current OCaml example programs cross-build for physical iOS 18
arm64. Their complete objects pass platform/minimum-version/ABI-export checks
and contain no prohibited process-start imports. The updated Host Effects
example builds as macOS Debug and development-signed iOS Release. Both bundle
signatures verify; the iOS App additionally passes the native App/privacy and
provisioning authorization audit. This is build evidence, not physical execution.

The root Flutter source tree is removed, and the native CI contract passes.
Earlier per-example App records below still describe their recorded builds;
only Host Effects was relinked at this checkpoint. Current object hashes are in
`_build/validation/swiftui-notices-ios-objects.json`. No source/SDK publication or
new screenshot is claimed.

## Native file-service checkpoint

After file import/export integration, Host Effects and Mail were rebuilt through
the native CLI as macOS Debug and signed physical-iOS Release Apps. The changed
OCaml programs cross-build with the isolated iOS 18 compiler. All four Apps pass
deep/strict signatures, exact arm64/deployment-target checks and complete-object
ABI verification; staged and Xcode-consumed object hashes agree. The iOS Apps
also match the cross-built objects, retain iPhone/iPad device families and
contain provisioning profiles. Logs are `/tmp/swiftui-files-ios-objects.log`,
`/tmp/swiftui-files-{host_effects,mail}-{macos,ios}.log` and
`/tmp/swiftui-files-app-audit.log`.

`_build/validation/swiftui-file-services-bundles.json` records the four artifacts.
The main iOS example manifest refreshes these two records to
`native-file-services`; the other eight records describe earlier checkpoints.
This does not establish actual chooser selection, physical-iOS execution or
complete Mail screenshots. No source or SDK commit/push has occurred.

## Standalone example coverage

All eleven examples now have native App build evidence. Ten retain signed
physical-iOS checkpoints. Gallery additionally builds macOS Debug in a temporary
standalone copy and an unsigned physical-iOS Release App; its complete renderer
test remains failing at KeyboardListener. Compilation does not establish a
runnable Gallery, physical interaction or screenshot acceptance.

| Example | macOS Debug | iPhoneOS Release |
| --- | --- | --- |
| Clock | Verified | Verified |
| Counter | Verified | Verified |
| Host Effects | Verified | Verified |
| Host Navigation | Verified | Verified |
| Mail | Verified | Verified |
| Navigation | Verified | Verified |
| Network | Verified | Verified |
| SQLite Worker | Verified | Verified |
| Text Input | Verified | Verified |
| Todo | Verified | Verified |
| Gallery | Built; complete page blocked | Built unsigned; complete page blocked |

## Gallery host checkpoint

The standalone macOS CLI/resource test passes in 31.091 seconds. The common
complete-object/source-preservation test now covers all eleven standalone
copies and passes in 19.700 seconds. Gallery's physical-iOS object passes
IOS/arm64/minimum 18.0 and native ABI verification; its unsigned Release App
build succeeds. Logs are `/tmp/swiftui-gallery-host-green.log`,
`/tmp/swiftui-eleven-native-examples.log`, `/tmp/swiftui-gallery-ios-object.log`
and `/tmp/swiftui-gallery-ios-build.log`.

This checkpoint does not update historical signed-bundle manifests or claim
that the complete Gallery page renders. Its required complete-page test still
fails at node 53. See [Gallery acceptance](swiftui-gallery.md).

## Scope of the ten signed checkpoints

All ten actual OCaml programs cross-build with the isolated iOS 18 compiler and
audited dependency closure. Each complete object passes IOS/arm64/minimum 18.0,
SwiftUI ABI and OCaml startup symbol checks, and obsolete Flutter ABI/host-path
rejection. Xcode links the objects with the actual SwiftUI package and each
application's Swift entrypoint. Every iOS Release App passes deep/strict
signature verification and includes a provisioning profile. Every executable
is IOS/arm64/minimum 18.0; every plist declares iPhoneOS only, minimum 18.0 and
iPhone/iPad device families. Existing macOS Debug bundles were independently
rechecked for deep/strict signing, MACOS/arm64/minimum 26.0.

Network's final executable has no unresolved GMP symbols. SQLite Worker links
the iOS system `/usr/lib/libsqlite3.dylib`. Neither check establishes successful
network or filesystem operations on a device.

The iOS builds use the original Mail project's saved development team through
an Xcode command-line override. Generated projects retain portable settings.
No Simulator, Intel or Catalyst destination was added.

## Artifacts and reproduction

Bundles use each generated host's standard output directory:

- macOS: `examples/<example>/apple/DerivedData/Build/Products/Debug/Bonsai<Name>.app`.
- iOS: `examples/<example>/apple/DerivedData/Build/Products/Release-iphoneos/Bonsai<Name>.app`.

`_build/validation/ios-examples/manifest.json` records all ten bundle paths,
bundle IDs, native-object and executable SHA-256 values, platform/configuration,
signature checks and per-example build logs. The manifest explicitly records
that device execution is unverified. Its source identity is base commit
`39c486233d0a1a614c6cb1267a80fa19d6076fcc` plus the uncommitted migration worktree;
this is not a published source or SDK release.

Cross-build all available Swift App examples from the repository root:

```sh
OPAMROOT="$PWD/_build/ios/opam-root" \
  SDK="$(xcrun --sdk iphoneos --show-sdk-version)" VER=26.0 \
  opam exec --switch="$PWD/_build/ios/switches/iphoneos" -- \
  dune build --build-dir="$PWD/_build/ios/swiftui-framework" \
    --profile=release -j 4 -x ios \
    examples/{clock,counter,gallery,host_effects,host_navigation,mail,navigation,network,sqlite_worker,text_input,todo}/ocaml/native_embed.exe.o
```

Then build a selected example with an explicitly selected development team:

```sh
python3 tool/build_swiftui_example.py network \
  --target iphoneos --configuration Release \
  --native-object _build/ios/swiftui-framework/default.ios/examples/network/ocaml/native_embed.exe.o \
  --development-team "$APPLE_DEVELOPMENT_TEAM"
```

The cross-build log is `/tmp/swiftui-ios18-all-examples-cross-build.log`; complete
object checks are in `/tmp/swiftui-ios18-all-examples-objects.log`. See
[toolchain setup and audit](swiftui-ios-toolchain.md) and
[Xcode host details](swiftui-xcode-host.md).

## Remaining acceptance

All physical-iOS execution, interaction, accessibility and screenshots remain
unverified while the paired device is unavailable. iOS Debug/Profile builds,
macOS optimized builds outside Mail, distribution archives and the production
CLI/SDK workflow remain separate work. Gallery still requires its remaining
widget families and application extension before it can run as a complete
standalone SwiftUI App. Full Mail screenshots remain outstanding.

Mail's iOS Release XCTest bundle additionally passes `build-for-testing`,
IOS/arm64/minimum 18.0 validation and deep/strict signature verification.
The test has not run on a device. See [Xcode test commands](swiftui-xcode-host.md).

## Window-service checkpoint

After the shared window-service and presentation-owner changes, Host Effects'
changed OCaml program was cross-built again. Host Effects and Mail were then
rebuilt as macOS Debug and signed physical-iOS Release Apps. All four bundles
pass deep/strict signatures and executable architecture/deployment checks
(`/tmp/swiftui-window-host-bundle-audit.log`). Their iOS Apps also retain the
required iPhone/iPad families, iPhoneOS platform and embedded profiles.
The manifest updates these two records with current object/executable hashes
and a `native-window-host-services` checkpoint. The other eight records and
the Mail build-for-testing bundle describe the earlier build checkpoint; they
have not been rebuilt after the latest shared-source changes. Physical-device
execution remains unverified.


## Standalone CLI checkpoint

The ten examples with Swift entrypoints now also own native CLI configurations.
Independent copies of all ten pass actual macOS native builds and source
preservation; the separate Mail copy builds its App and executes the packaged
OCaml XCTest through the CLI. Network and SQLite Worker additionally pass fresh
iOS 18 cross-build/object verification after Apple system-library search flags
moved into the native backend library's installed archive metadata. These new
object checks do not replace the older iOS App-bundle manifest records.

The worktree's Mail Debug App has also been rebuilt by `bonsai-swiftui build
macos --profile debug` from its own directory, with its own configuration and
OCaml sources. The bundle at the usual `apple/DerivedData` path passes macOS 26
arm64 metadata and deep/strict signature checks. Its current identity is recorded
in `_build/validation/swiftui-mail-cli-macos.json`; the build log is
`/tmp/swiftui-mail-example-cli-macos.log`. Complete window screenshots remain
unverified. See [native CLI evidence](swiftui-cli.md).


## URL-service checkpoint

After native URL dispatch and the Host Effects URL editor were added, Host
Effects and Mail rebuilt through the native CLI as macOS Debug and signed iOS
Release Apps. The changed Host Effects program also cross-built for iOS 18.
All four bundles pass strict signatures, architecture and minimum-version
checks; the iOS Apps preserve their device families and provisioning profiles.
`_build/validation/swiftui-url-host-bundles.json` records this checkpoint, and
`/tmp/swiftui-url-host-bundle-audit-final.log` records the final verification.
The main iOS manifest updates Host Effects/Mail to `native-url-host-service`;
the other eight Apps and Mail's iOS XCTest bundle still represent earlier
checkpoints. Physical-device execution and complete screenshots remain open.


## Application-bridge checkpoint

Host Effects now supplies an application-owned Swift bridge and receives bundle
information and time-zone notifications through its actual OCaml component.
Host Effects and Mail rebuilt through the CLI as macOS Debug and signed iOS 18
Release Apps. Their complete objects, final executables, metadata and signatures
pass verification, and each staged object matches the object consumed by Xcode.
The iOS Apps preserve their provisioning profiles and iPhone/iPad families.
`_build/validation/swiftui-application-bridge-bundles.json` and
`/tmp/swiftui-application-bundle-audit.log` record this checkpoint. The main iOS
manifest updates these two Apps to `application-swift-bridge`; the remaining
Apps and Mail's iOS XCTest bundle retain their earlier checkpoints. The actual
Host Effects macOS window passes application request/event integration together
with its existing services. Physical iOS execution and complete Mail screenshots
remain outstanding.


## Native focus, layout and complete macOS captures

Host Effects and Mail rebuilt through the CLI for macOS Debug and signed iOS
Release after the native focus/layout changes. All four App bundles pass
deep/strict signing, architecture/minimum-version and complete-object ABI
checks; staged and consumed object hashes match, and iOS artifacts match the
cross-build outputs. The audit is `/tmp/swiftui-node-services-app-audit.log`,
with hashes in `_build/validation/swiftui-node-services-bundles.json`.

The rebuilt macOS Mail App now has four reviewed complete window captures:
inbox, expanded preview, message detail and Archived. Their original capture
bytes, lossless PNG re-encodings and source/binary provenance are recorded in
[the capture evidence](screenshots/swiftui-mail/README.md). These are an
uncommitted-source checkpoint; final publication and physical-iOS captures
remain required.

Physical-device installation of the signed Mail App succeeded on iPhone 13,
iOS 26.6.1 (23G83). Launch was denied because the phone was locked. The first
physical XCTest attempt also exposed an independent generator defect: the
test target was tool-hosted, which Xcode refuses on device destinations.
Earlier successful `build-for-testing` results do not establish device test
runnability. An isolated application host is being added and verified.

The corrected host now passes physical execution: Mail's Release runtime
XCTest completes startup/presentation/restart on iPhone 13, iOS 26.6.1 (23G83),
with one passing test, zero failures and zero skips. Both the dedicated host
and nested test bundle pass strict signing and IOS/arm64/minimum-18 checks.
The actual Mail App also launches after unlocking. See
`_build/validation/swiftui-mail-physical-runtime.json` and
`/tmp/swiftui-mail-physical-runtime-hosted-20260913.xcresult`.
The first original iOS screenshot exposes Dark-appearance contrast and initial
compact-column issues, so physical visual acceptance is still incomplete.

The current signed Mail App was re-audited, reinstalled and freshly launched
after Xcode rebuilt its executable. Its new Inbox PNG and exact source/binary
provenance are recorded in [the capture evidence](screenshots/swiftui-mail/README.md).
This launch displays Inbox correctly, so the earlier Mailboxes observation
does not establish an initial compact-navigation defect. The Mail iOS bundle
record advances to `physical-ios-runtime-test-host`; appearance and remaining
interaction screenshots still require work. All seven Xcode-host regression
tests pass in 349.698 seconds.

## Civil host picker build checkpoint


All eleven iOS 18 complete objects were rebuilt after the host picker change and
passed architecture, deployment, ABI and prohibited-process-import checks.
The public CLI rebuilt Host Effects and Mail as macOS Debug and signed iOS
Release Apps. Both iOS bundles passed provisioning/privacy validation, and
their staged objects exactly match the current cross-build hashes. Both generated
hosts pass `sync-host --check`. Other example App bundles retain earlier linking
provenance; the eleven current complete objects are independently recorded.
No new physical run or screenshot is claimed. The source remains uncommitted.

`_build/validation/swiftui-host-pickers.json` records the four complete App file
hash sets, current source/test hashes and verification logs. The separate
`swiftui-pickers-ios-objects.json` records all eleven cross-built objects.

## UIKit environment build checkpoint

All eleven iOS complete objects are current after the Host Effects reactive
environment display. Host Effects and Mail macOS Debug/iOS Release Apps include
the UIKit observer and pass native/signing audits. A separate unsigned iOS 18
arm64 UI-testing bundle builds in `HostEffectsUIKitTesting` DerivedData. It is
compile-only evidence and has not executed on a device. Artifact hashes and
verification results are recorded in `swiftui-uikit-environment.json` under
`_build/validation/`. The other nine App bundles retain earlier linking provenance.

Mail was subsequently rebuilt for macOS Debug and signed iOS Release after
requesting Light at its application root to match the fixed palette. The real
macOS window scenario passes under both light and dark inherited appearances
(34.928 seconds), alongside the OCaml Mail behavior tests. Both App signatures,
iOS provisioning and the staged iOS complete-object hash pass validation.
`_build/validation/swiftui-mail-appearance.json` records the new artifact hashes
and logs. Physical-iOS appearance and fresh screenshots remain unverified;
the earlier capture files have not been replaced.

## UIKit KeyboardListener build checkpoint

Gallery now builds as a development-signed physical-iOS 18 Release App with
UIKit KeyboardListener support. Node 53 no longer fails the iOS decoder. The
Release optimizer initially crashed on a dictionary captured by nested delivery
closures; binding the delivery closure before routing avoids that compiler
failure without changing optimization settings. The shared/macOS keyboard and
complete Gallery staging/dispatch regression passes 28 tests in eight suites.
Physical keyboard/IME propagation and native Gallery page acceptance remain
unverified. Other App binaries retain their previous checkpoint provenance.

## Source package rename checkpoint

All eleven examples now use `bonsai_swiftui` package/module names. Independent
copies build their native objects against the renamed installed libraries
(20.656 seconds); all eleven physical-iOS complete objects were rebuilt and
pass ABI, architecture, minimum-version and process-import checks. Mail's macOS
Debug and development-signed iOS Release Apps were rebuilt and verified. Its
actual macOS window test passes with light and dark inherited appearances,
including expansion, Archive and mailbox navigation (40.109 seconds).
`_build/validation/swiftui-package-rename.json` records the artifact hashes and
verification logs. Other App binaries retain earlier linking provenance. No
new device execution, screenshot, source push or SDK publication is claimed.
