# Physical iOS 18 OCaml toolchain

The SwiftUI target is physical iOS/iPadOS 18.0 arm64. Simulator, Catalyst and
Intel targets are unsupported. This document separates compiler verification
from dependency-closure, application linking and physical-device acceptance.

## Isolated compiler bootstrap

Run from the repository root:

```sh
sh tool/ios/setup_toolchain.sh iphoneos
```

The setup uses the locked opam-cross-ios source revision and the repository's
OCaml 5.1.1 overlay. It creates an opam root and local switch under `_build/ios/`:

- Root: `_build/ios/opam-root`.
- Switch: `_build/ios/switches/iphoneos`.
- Installed compiler/runtime: the switch's `_opam/ios-sysroot`.

It does not modify the user's existing global switches. The selected Xcode
installation supplies the physical-device SDK; the source lock supplies arm64,
iPhoneOS and minimum iOS 18.0. The local recipe identity includes the compiler
recipe revision and minimum deployment target. Flutter and Dart version locks
are removed from `tool/ios/toolchain.lock`.

The compiler's C command and OCaml C flags embed their deployment target during
installation. Setting `VER=18.0` when invoking an already installed iOS 15 compiler
does not rebuild those commands or its native runtime. The new target therefore
requires an actual compiler/runtime rebuild.

## Verification

Setup runs the real cross-compiler tests before reporting success. They can also
be rerun directly:

```sh
python3 tool/test_ios_cross_compiler.py
```

The tests check the installed OCaml configuration, compile a C foreign stub and
an OCaml callback into an Apple complete object, and inspect a native allocation
object extracted from the installed `libasmrun.a`. Mach-O validation checks
physical IOS platform, arm64 and minimum 18.0. The complete object must contain
the runtime startup symbol and the actual foreign-stub symbol. A separate check
rejects Simulator input before setup begins.

`IOS_CROSS_TEST_OPAMROOT` and `IOS_CROSS_TEST_SWITCH` select an explicitly supplied
installation for auditing. They do not alter its compiler or manufacture a
passing target. The prior global iOS 15 installation fails three tests: its
compiler flags, newly compiled C object and installed native-runtime object all
retain 15.0 (`/tmp/swiftui-ios18-compiler-red.log`).

The fresh worktree-local compiler setup passed all four tests. The deployment
version gate is now `sh tool/test_ios_deployment_target_contract.sh`; it runs the
same actual artifact checks after bootstrap, replacing Flutter project/pubspec
text scans. The broader old CI and published SDK contract scripts remain to be
migrated.

## Dependency artifact audit

The supported runtime lock contains 103 target packages, 128 host packages,
two target build dependencies and 146 findlib components. The obsolete framework
host row is removed: the framework must be built from the selected source tree,
not installed from an earlier Flutter release. Host dependencies are installed
in the isolated switch, and all 105 target source archives are staged with their
locked SHA-256 checksums verified.

Run the artifact regression checks after compiler bootstrap:

```sh
python3 tool/test_ios_closure_artifacts.py
```

These tests compile real OCaml libraries and C foreign objects. They check valid
iOS 18 libraries, reject iOS 15 and macOS objects hidden inside static archives,
and reject missing declared `.cmxa` metadata or companion `.a` archives. The
verifier uses the deployment target from `toolchain.lock` and audits every
archive member as well as loose objects, deduplicating overlapping component
directories. Findlib archive paths are read individually to preserve spaces.
The initial three tests pass after reproducing five failures in the previous
verifier. Two additional tests use installed Digestif and Datascript libraries
to distinguish interface-only virtual libraries from those with concrete
modules, and to reject even one missing concrete module. All five tests pass.
The virtual-library checks need the installed dependency closure in addition
to compiler bootstrap.

The complete 105-item target build finished. Its first installation audit found
54 missing native module files in Datascript's virtual library. The generic
recipe now builds all concrete native modules before staging them. A dedicated
check verifies the expected `.cmx`/`.o` inventory and every object's target:

```sh
python3 tool/test_ios_virtual_library.py
```

The verifier uses the locked host installation only for expected virtual-module
filenames. Target bytes always come from the cross-build; interface-only
libraries such as Digestif are not required to manufacture native objects.

## Remaining application pipeline

Compiler verification does not establish an audited dependency closure. Bonsai,
Core, networking, SQLite and other locked native dependencies have completed
their iOS 18 build. The full installation audit passes for 103 target packages
and 146 components, covering 166 static archives and 1,129 Mach-O objects
(`/tmp/swiftui-ios18-target-audit-complete.log`).
The separate target-build GMP static archive also passes a full member audit:
525 objects, all IOS/arm64/minimum 18.0 (`/tmp/swiftui-ios18-gmp-audit.log`).

The worktree framework and actual Mail application also cross-build successfully.
The resulting object at
`_build/ios/swiftui-framework/default.ios/examples/mail/ocaml/native_embed.exe.o`
passes physical IOS/arm64/18.0 validation, required SwiftUI ABI and OCaml runtime
symbol checks, and rejection of obsolete Flutter ABI exports and prohibited host
paths (`/tmp/swiftui-ios18-mail-object.log`). Build it from this checkout with:

```sh
OPAMROOT="$PWD/_build/ios/opam-root" \
  SDK="$(xcrun --sdk iphoneos --show-sdk-version)" VER=18.0 \
  opam exec --switch="$PWD/_build/ios/switches/iphoneos" -- \
  dune build --build-dir="$PWD/_build/ios/swiftui-framework" \
    --profile=release -x ios examples/mail/ocaml/native_embed.exe.o
```

Xcode links this object with the Swift package into the actual Mail Release App
(`/tmp/swiftui-ios18-mail-xcode-build.log`). A subsequent build uses the original
Mail project's saved Development Team and succeeds with automatic signing
(`/tmp/swiftui-ios18-mail-sign-build.log`). The bundle at
`examples/mail/apple/DerivedData/Build/Products/Release-iphoneos/BonsaiMail.app`
passes `codesign --verify --deep --strict` and contains a valid provisioning
profile. Its executable remains IOS/arm64/minimum 18.0; Info.plist declares only
iPhoneOS and minimum 18.0.

Installation and actual device interaction remain unverified. The paired iPhone
13 is currently unavailable, and the Mac desktop remains locked for complete
window captures. No Simulator substitute is accepted.

The published SDK recipe and source identities are a separate deliverable. They
must be generated from the exact pushed framework commit and published separately
after that source push. Existing generated SDK metadata is not rewritten to
claim that an uncommitted worktree is a published SwiftUI SDK.

## Installed local SDK acceptance

On 2026-09-16, the replacement SDK was installed in the global
`bonsai-swiftui-ios` opam switch. The framework package is `0.1.0~dev.40`,
the runtime package is `0.1.0~dev.7`, and the SDK build recipe is 5.
The SDK declares the matching host UI library needed by Dune's host context;
the target Zarith package includes GMP without transient build-directory paths.

All four compiler/runtime artifact tests pass with
`IOS_CROSS_TEST_OPAMROOT="$HOME/.opam"` and
`IOS_CROSS_TEST_SWITCH=bonsai-swiftui-ios`. The installed CLI's
`toolchain verify iphoneos` also passes. Both tests in
`tool/test_swiftui_ios_installed.py` pass: independent unsigned Release App
building with no source override or prebuilt object, and installed Zarith linking.

This installation uses an explicitly checksum-identified local source archive;
it does not identify an uncommitted worktree as a published commit. Public release
publication and device execution remain separate. See the
[installation evidence](opam-installation.md#installed-ios-sdk-acceptance).

The broader `tool/test_datascript_worker_contract.sh` also passes with the global
SDK selected through those environment variables. It verifies worker behavior,
process isolation, physical-iOS object metadata and an unsigned Worker App build.

## Native physical-device preflight

`tool/ci/ios_device_preflight.sh <UUID-or-UDID> [--require-signing]`
uses Xcode CoreDevice JSON directly. It requires a physical iOS 18+ device
with arm64 support, pairing, Developer Mode, available DDI services, and a
successful current lock-state response. It accepts an exact CoreDevice UUID
or hardware UDID, including case-insensitive hexadecimal spelling. It does
not resolve display names through Flutter or require the absent CoreDevice
`bootState` field. A successful details query alone is insufficient: CoreDevice
can return cached information while DDI services are unavailable.

Signing preflight retains certificate validity, Team ID, bundle identifier,
debug entitlement, and profile expiration checks. Device membership is an
exact match in `ProvisionedDevices` against the resolved hardware UDID;
a UUID, a substring, or a match elsewhere in the profile is insufficient.
Only the device array is converted to JSON because a provisioning profile's
date fields cannot be converted by `plutil` to JSON.

`python3 tool/test_ios_device_preflight.py` runs eight regression tests through
the actual shell script and installed JSON, plist, date, and certificate tools.
The hardware and keychain boundaries replay responses, so these tests establish
preflight behavior, not device connectivity or CMS trust. `make ci-contract`
includes this gate. The 2026-09-14 live iPhone check returned iOS 26.6.1,
paired, Developer Mode enabled, but `ddiServicesAvailable=false`; preflight
correctly failed before the lock query, signing, or application launch.
