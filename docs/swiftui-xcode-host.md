# SwiftUI Xcode application hosts

`tool/build_swiftui_example.py` now generates and builds actual Xcode application
projects. The previous direct `swiftc` application-bundle assembly is removed.
The OCaml reducer remains in the complete object, the renderer remains in the
local `BonsaiSwiftUI` Swift package, and each example owns its Swift App entrypoint.

## Generate and build

Run from this repository with its opam environment active:

```sh
python3 tool/build_swiftui_example.py mail
open examples/mail/apple/DerivedData/Build/Products/Debug/BonsaiMail.app
```

The helper compiles Mail's OCaml complete object with Dune, verifies its Apple
platform, architecture, deployment target and native ABI exports, stages it,
generates the Xcode project, builds the selected scheme and verifies the App's
signature. Network objects additionally embed static GMP before Xcode linking.
The generated Xcode build phase verifies the staged object again.

That phase also inspects the complete object's undefined symbols and writes a
target-local system-library response file before linking. Only an object that
references a `sqlite3_*` symbol adds `-lsqlite3`. App and runtime-test targets
each produce their own response file; the isolated test host and UI runner do
not link the OCaml runtime. Security and CoreFoundation remain explicit native
framework dependencies.

Actual Counter and SQLite Worker builds verify the resulting Mach-O library
dependencies on macOS Debug and physical-iOS Release. Counter must have no
SQLite dependency, while SQLite Worker must link `/usr/lib/libsqlite3.dylib`
without bundling a SQLite dylib. All four cases pass after reproducing Counter's
unwanted dependency on both destinations. These tests build unsigned Apps and
do not execute their physical UI.

To generate the project without compiling, staging or signing:

```sh
python3 tool/build_swiftui_example.py mail --generate-only
open examples/mail/apple/BonsaiMail.xcodeproj
```

`--host-directory` selects a different output location. Generation rewrites only
its managed project, scheme, plist and entitlement files. It retains unrelated
files. IDs and source references are stable across equivalent checkout layouts;
projects contain no absolute checkout paths. Application Swift sources, resource
directories and optional `apple-tests/*.swift` remain application-owned.

Native objects and Xcode DerivedData are ignored build outputs. Xcode builds use
the staged object; rerun the helper after changing OCaml sources. Integrated
OCaml rebuilding from the Xcode UI and the production OCaml CLI remain unfinished.

## Targets and configurations

The `BonsaiSwiftUI` package copies `Sources/PrivacyInfo.xcprivacy` into its
resource bundle. Xcode embeds `BonsaiSwiftUI_BonsaiSwiftUI.bundle` in the App;
applications retain ownership of any separate application privacy manifest.
The runtime resource preserves the previous File Timestamp (`C617.1`) and
System Boot Time (`35F9.1`) declarations, an empty collected-data list and
tracking set to false. This records runtime packaging, not an assessment of an
application's additional data practices.

Actual macOS resource builds and physical-iOS build-for-testing products verify
that exactly one runtime manifest is present and that its parsed declarations
match. The isolated iOS runtime XCTest host also builds successfully. These
three packaging tests passed in 97.851 seconds; they do not establish physical
UI test execution. `make xcode-test` runs the Xcode host suite and is included
in `make swift-test`.

Each project has separate `Bonsai<Name>-macOS` and `Bonsai<Name>-iOS` App targets
and shared schemes. The only architectures and deployment targets are:

| Target | SDK | Architecture | Minimum |
| --- | --- | --- | --- |
| macOS | macosx | arm64 | 26.0 |
| Physical iOS/iPadOS | iphoneos | arm64 | 26.0 |

Simulator, Intel Mac and Catalyst are unsupported. iOS supports iPhone and iPad,
uses SwiftUI scenes and a system launch screen, and disables multiple scenes.
macOS uses local ad-hoc signing. iOS uses automatic signing with an explicitly
selected development team. Entitlement files are explicit and initially empty;
no extra capability or private entitlement is injected.

Debug, Profile and Release configurations exist for each target. Debug uses the
Dune `dev` profile and unoptimized Swift compilation. Profile and Release use the
Dune `release` profile and optimized Swift compilation with debug symbols; the
Profile scheme retains its profiling action. Native staging paths include both
SDK and configuration: `Native/<sdk>/<configuration>/runtime.complete.o`.
Mail now passes macOS native builds and packaged runtime tests in Debug, Profile
and Release. Instruments profiling, distribution archives and optimized builds of
the other examples remain unverified.

Schemes explicitly match the run destination's architecture for the entire
dependency graph, including Swift packages. App target settings alone did not
prevent Xcode from attempting Intel package compilation in Release. The supported
macOS destination is `platform=macOS,arch=arm64`. Apple describes the scheme-wide
architecture override in the [Xcode 15.3 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-15_3-release-notes).

A device build currently requires an already cross-compiled iOS 26 arm64 complete
object via `--native-object` and a `--development-team`. The helper rejects a
macOS object before invoking the device build. It does not silently substitute a
host object, install an old iOS SDK, create a Simulator toolchain, or select a
signing identity.

The new iOS 18 cross-toolchain and complete dependency closure have been built
and audited. The actual Mail complete object links successfully into the SwiftUI
iOS Release App. A separate build using the original Mail project's saved
Development Team succeeds with automatic signing and an embedded provisioning
profile; `codesign --verify --deep --strict` passes. Its executable is physical
IOS/arm64/minimum 18.0. The signed bundle is
`examples/mail/apple/DerivedData/Build/Products/Release-iphoneos/BonsaiMail.app`.
Installation and runtime acceptance remain outstanding because the paired iPhone
13 is currently unavailable. This build does not establish actual device runtime
behavior or screenshot acceptance. See [iOS toolchain](swiftui-ios-toolchain.md).

All ten available standalone Swift App examples now have verified signed iOS
Release bundles. Their actual OCaml complete objects, final executable metadata,
plists and signatures pass checks. See [example build evidence](swiftui-example-builds.md)
for the per-example matrix, manifest and remaining configurations. Gallery is
still unfinished.

Resources use Xcode's resource build phase; folder references retain nested paths
and same-named files in separate directories. All targets consume the repository's
local framework Swift package. Applications can also select pinned remote packages.

## Tests

Mail owns `examples/mail/apple-tests/MailRuntimeTests.swift`. The generator adds
native XCTest targets when an example has `apple-tests` sources. Mail's test links
the same Swift package and complete object as the App. It opens the real Mail
entrypoint, finds its known message in the initial frame, acknowledges presentation,
pumps again, closes and repeats startup. macOS runs this as a tool-hosted test.
iOS requires an application host on physical devices: the generator creates a
minimal `BonsaiMailTestHost.app` only when application-owned test sources exist.
This host contains no BonsaiSwiftUI package or OCaml complete object. The test
bundle owns the single runtime, so it cannot race the Mail UI's session. The
generated test target depends on the host and sets `TEST_HOST` and `BUNDLE_LOADER`.
The real build regression checks Xcode's app-hosted run manifest, the host's
architecture/deployment metadata and absence of native runtime exports.

The earlier iOS `build-for-testing` success used a tool-hosted test and did not
prove that the tests could execute on a device. The first device test attempt
exposed this limitation; the application-hosted replacement now builds and passes the real Mail
startup/presentation/restart test on iPhone 13, iOS 26.6.1 (23G83).

After building Mail with the helper:

```sh
xcodebuild -project examples/mail/apple/BonsaiMail.xcodeproj \
  -scheme BonsaiMail-macOS -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath examples/mail/apple/DerivedData test
```

The physical-iOS test-build checkpoint uses an explicit development team:

```sh
xcodebuild -project examples/mail/apple/BonsaiMail.xcodeproj \
  -scheme BonsaiMail-iOS -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath examples/mail/apple/DerivedData \
  DEVELOPMENT_TEAM="$APPLE_DEVELOPMENT_TEAM" build-for-testing
```

The earlier build log is `/tmp/swiftui-ios18-mail-build-for-testing.log`. Xcode writes
the `.xctestrun` manifest under the host's `DerivedData/Build/Products` and the
test bundle in `Release-iphoneos`. Test compilation and signing do not establish
device installation, test execution or runtime acceptance.

The corrected physical execution uses the `BonsaiMail-iOS` scheme, Release,
the hardware device destination and an explicit development team. The command
`xcodebuild ... -destination 'platform=iOS,id=<hardware-UDID>'
DEVELOPMENT_TEAM=<team> -allowProvisioningUpdates test` signs the dedicated host
and executes the test bundle. The actual run passed one test with zero failures
and zero skips; the test case took 0.109 seconds.
`/tmp/swiftui-mail-physical-runtime-hosted-20260913.xcresult` and its adjacent
log record this result. `_build/validation/swiftui-mail-physical-runtime.json`
records verified host/test signatures, metadata and hashes. This establishes
the runtime lifecycle on that device, not visual acceptance or iOS 18 coverage.

The host generator integration suite is:

```sh
python3 tool/test_swiftui_xcode_host.py
```

It builds actual Xcode applications, verifies ad-hoc signing and arm64 metadata,
runs Mail's XCTest in all three configurations, checks both platforms in all three configurations, rejects a
macOS object used for iOS, builds nested resource directories containing duplicate
filenames, and checks regeneration and checkout portability. It does not replace
Mail window/interaction tests or the required full macOS and physical-iOS screenshots.

The test-host change passes all seven host integration tests in 349.698 seconds
(`/tmp/swiftui-ios-test-host-regression.log`), including macOS runtime execution
in Debug, Profile and Release and actual iOS app-hosted test-product inspection.

## Platform UI test bundles

Applications can supply `apple-ui-tests/ios/*.swift` and
`apple-ui-tests/macos/*.swift`. The generator adds the corresponding platform
UI-testing target to the existing scheme only when that directory has sources.
The UI test target depends on and names the real App through `TEST_TARGET_NAME`.
It does not link the Swift renderer or native complete object. Runtime tests
remain in a separate XCTest target, with their isolated iOS host.

Mail's iOS sources drive the actual application through XCUITest, using
accessibility labels and physical gestures. They retain screenshots with
`XCTAttachment(screenshot:)` and `.keepAlways`, including a failure screenshot
and accessibility tree. The real-build regression verifies Xcode's generated
UI-testing run manifest, the target App's actual bundle identifier and the
runner's arm64 architecture and absence of OCaml runtime symbols. Its passing
log is `/tmp/swiftui-mail-ui-host-green-verified.log` (39.497 seconds).

Run the generated iOS scheme against a hardware device as above; use
`-only-testing:BonsaiMail-iOSUITests` to select only UI scenarios. Export original
attachments after the test finishes with:

```sh
xcrun xcresulttool export attachments --path /path/to/Mail.xcresult \
  --output-path /path/to/mail-captures
```

Inspect the exported PNGs and attachment manifest before counting a scenario
as screenshot evidence. Compilation and a generated UI runner do not establish
physical interaction or visual acceptance.

A physical phone may request its passcode specifically for XCTest's Enable UI
Automation even when ordinary App launch and runtime XCTest already work.
The first Mail UI run encountered that prompt and timed out before executing
UI cases. Complete the device's own prompt, then rerun the same signed tests;
do not interpret an automation-initialization failure as an application
assertion failure or use Simulator output as replacement evidence.

The full generator regression after adding platform UI tests passes all eight
tests in 389.647 seconds (`/tmp/swiftui-mail-ui-host-regression.log`). The actual
UI runner and UI bundle contain no OCaml runtime symbols; the targeted App
does. Runtime XCTest on iPhone 13 passes again, while UI case execution awaits
the device's observed XCTest passcode prompt.

## Application host configuration

The CLI passes validated schema-4 platform identities, per-profile entitlement
paths and explicit remote package products to the shared generator. See the
[complete application configuration](swiftui-cli.md#application-identities-entitlements-and-swift-packages)
for input files, ownership, package resolution and signing limits.

Generated test identities use each platform's application identifier followed by
`.test-host`, `.tests` or `.ui-tests`. Application-only entitlements and remote
products do not propagate into test targets. Generated profile entitlement files
replace the previous single file per platform; synchronization removes only
those obsolete generated filenames and leaves unrelated host files intact.
