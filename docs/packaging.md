# Native Apple packaging

Applications link their OCaml complete object into a SwiftUI Xcode App target.
The local `BonsaiSwiftUI` Swift package owns the renderer, native adapters and
runtime privacy resource. The C bridge is exposed through `CBonsaiSwiftUI`;
no Dart FFI or Flutter engine participates in native application builds.

## Application ownership

Each application owns `bonsai-swiftui.sexp`, its OCaml component and native
entrypoint, `swift/App.swift`, resources and optional `apple-tests/*.swift`.
Schema 3 selects the application identity, native-object target, explicit
capabilities and Apple destinations. `bonsai-swiftui sync-host` generates the
Xcode project, shared schemes, plists and entitlement files. `sync-host --check`
rejects stale generated output. Application sources remain application-owned.

The only supported destinations are macOS 26.0+ arm64, physical iOS/iPadOS
26.0+ arm64 and the iOS 26.0+ arm64 Simulator (`--simulator` on the `ios`
target). Debug, Profile and Release have separate build and staging paths.
Profile and Release use the optimized OCaml release profile; Xcode retains
separate configurations and profiling actions. Intel and Catalyst
are unsupported.

## Native objects and dependencies

Every application produces a complete object containing its OCaml component,
entrypoint, runtime and the shared `bs_*` C ABI. The CLI asks Dune for that
configured target, validates its platform, architecture, minimum deployment
version and ABI exports, then stages it under the generated host:

```text
Native/<sdk>/<configuration>/runtime.complete.o
```

The SDK is `macosx` or `iphoneos`. Objects cannot be reused across destinations.
Changing environment variables around an older installed cross-compiler does
not rebuild its runtime or change the deployment target of existing objects.
Use the actual [iOS 26 compiler and closure](swiftui-ios-toolchain.md).

Network complete objects embed static GMP before Xcode links the App. Native
linking uses Apple's Security and CoreFoundation frameworks. System SQLite is
selected from the complete object's undefined `sqlite3_*` symbols; the Xcode
verification phase writes a fresh response file before linking each App or
runtime-test target. SQLite comes from the OS rather than an application-owned
copy. Explicit capability validation remains part of the CLI's native closure
checks; system-library selection does not bypass it.

The Swift package copies `PrivacyInfo.xcprivacy` into
`BonsaiSwiftUI_BonsaiSwiftUI.bundle`. It records runtime declarations; an
application retains ownership of its own additional privacy declarations.
See [Xcode hosts](swiftui-xcode-host.md) for resource and isolated test-host
packaging details.

## Build and device execution

Run the public CLI from the application root:

```sh
bonsai-swiftui build macos --profile debug
bonsai-swiftui build ios --profile release --no-codesign
bonsai-swiftui run ios --profile debug --device "$IOS_DEVICE_ID" \
  --development-team "$IOS_DEVELOPMENT_TEAM"
```

The worktree executable and source-library environment are documented in the
[README](../README.md). The [native build guide](swiftui-cli-native-build.md)
explains Dune target validation and profile handling. The
[example helper](swiftui-xcode-host.md) can also package an explicitly supplied
physical-iOS complete object.

Unsigned builds establish compilation and linking only. Device installation,
runtime XCTest execution and UI acceptance are distinct gates. Runtime XCTest
uses a separate iOS application host so the test process does not initialize a
second application runtime; UI tests run separately against the actual App.

## Current completion boundary

The September 14 macOS regression passed all 489 tests in 107 suites in
486.197 seconds using `python3 tool/run_swift_tests.py`, including its fresh
xUnit completion check. This run includes the spec-module rename, scoped
theme and Dropdown changes, measured Mail rows, conditional swipe panes and
the final macOS Button/pan arbitration fix.
The local evidence and input hashes are recorded in
`_build/validation/swiftui-final-macos-404ae17.json`.

The installed CLI layout now has an actual external-application gate:
`make installed-cli-test` installs the three Dune packages into a temporary
prefix, executes the tool's declared opam asset-install commands there, and
unsets `BONSAI_SWIFTUI_SOURCE_ROOT`. The copied CLI discovers its own installed
Swift package and scripts. An external OCaml application builds in Debug,
Profile and Release, passes signature checks, and updates its counter through
the native button. The generated Xcode project points at the installed assets.
This gate does not register packages in an opam switch, solve dependencies or
establish a published iOS SDK.

All eleven standalone examples pass the native build and source-preservation
gate. Their renamed iOS complete objects also pass platform and ABI checks;
these build checks do not establish physical UI acceptance for every example.
Mail has actual macOS captures and passing physical tests for Dynamic Type,
runtime teardown, inbox expansion/collapse and opening a message with an
attachment. See the [physical interaction captures](screenshots/swiftui-mail/physical-interaction/README.md).
The conditional swipe-pane fix still needs a physical Archive retest after
the interrupted device run. Broader widget/service acceptance, full CI cleanup,
distribution signing and release export remain unfinished. See the
[implementation ledger](swiftui-implementation.md) for exact evidence.

[The committed-source macOS captures](screenshots/swiftui-mail/committed-source/README.md)
include a successful real mouse swipe and Archive activation after the macOS
Button/pan arbitration fix. Their manifest identifies source `11d75d4` and the
rebuilt Debug binaries; the full 489-test run above includes this last fix.

Public OCaml packages now use `bonsai_swiftui`, including the
`Bonsai_swiftui_spec` module. Installed SDK publication remains unfinished.
After a source commit is pushed,
the generated iOS SDK must be updated
from that exact pushed revision and committed and pushed separately. This
uncommitted migration does not claim a published native SDK.

## SDK repository generation

The generator builds a fresh repository from explicit local dependency inputs
in `vendor/opam-ios/sdk-packages`, the current cross-compiler template and the
pinned upstream repositories. The framework opam file comes from the Git
revision in `tool/ios/sdk_repository.lock`. It never comes from an earlier
generated snapshot, a later HEAD or uncommitted package metadata. The framework
builder and manifest both receive the iOS 26 minimum from `toolchain.lock`.

After the locked cross-repository checkout is available, run
`make ios-sdk-repository-test` to verify empty-output generation, locked-source
selection, reproducibility, removal of obsolete output and preservation of
existing output when source metadata is missing. The tests use temporary Git
repositories and do not publish or build an SDK.

The full dependency metadata also generates and passes `opam lint` in an
isolated local-source fixture. This verifies repository assembly, not download
or compilation of a released framework archive. The checked-in published
snapshot still refers to the previous source revision; generation deliberately
rejects that lock because it has no `bonsai_swiftui.opam`. Publication requires
updating the source commit and archive checksum after pushing the migration.
The two isolated SDK-generation tests passed again on September 14 in 9.464
seconds. The CI patch allowlist reads the runtime version from the same lock;
its approved patch names and checksum checks remain unchanged.
