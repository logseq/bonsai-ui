# Native SwiftUI CLI

The executable is `bonsai-swiftui`. It initializes application-owned OCaml and
Swift sources, generates a native Xcode host, builds complete objects and Apps,
and launches macOS or physical-iOS Apps. The old executable name, Dart adapter,
Flutter create/pub-get flow, Native Assets profile injection and Flutter
argument forwarding are removed. Source packages and modules now use
`bonsai_swiftui`, `bonsai_swiftui_test` and `bonsai_swiftui_tool`. The virtual
spec module is `Bonsai_swiftui_spec`, with public package `bonsai_swiftui.spec`.
SDK regeneration/publication is still required.

## Configuration and ownership

The only project configuration is `bonsai-swiftui.sexp`, using schema 3:

```lisp
(lang 3)
(app
 (name journal)
 (apple_root apple)
 (bundle_identifier org.example.journal)
 (native_target app/native_embed.exe.o)
 (features)
 (macos (minimum_version 26.0) (architectures arm64))
 (ios (minimum_version 18.0) (architectures arm64)))
```

Core is implicit; `network` and `sqlite` are explicit features. Old schemas and
host fields are rejected. Minimum versions and architectures match the selected
backend contract; Simulator, Intel and Catalyst are unsupported. Initialization
validates the complete configuration and framework availability before writing
files, so an invalid name, bundle ID or deployment target creates no project.

`swift/*.swift`, `resources/`, `apple-tests/*.swift`, and the OCaml sources belong
to the application. The starter has a real OCaml counter using native View/Button
and App.View contracts, and a Swift App calling `BonsaiApplicationView` with the
registered entrypoint. No application reducer is generated in Swift.

`init --adopt` uses the existing configuration and sources. It does not replace
Swift or OCaml code or append Dune aliases. The Xcode project, schemes, plists
and entitlements under `apple_root` are tool-generated. `sync-host --check`
computes all expected output before comparing files, without writing or
creating directories. `sync-host` repairs generated output while leaving
application sources and unrelated files alone.

## Build and execution

```sh
bonsai-swiftui init --name journal --bundle-identifier org.example.journal
bonsai-swiftui build macos --profile debug
bonsai-swiftui run macos --profile debug
bonsai-swiftui sync-host --check
```

The native build pipeline is Dune complete object, ABI/platform verification,
staging, Xcode build, App metadata/platform checks, and signing verification.
Object verification rejects wrong-platform input before it reaches the host.
The App check does not require all native ABI exports in its main executable:
Xcode Debug can place implementation code in a debug dynamic library. ABI
validation occurs on the complete object before linking.

| Profile | Dune profile | Xcode configuration |
| --- | --- | --- |
| debug | dev | Debug |
| profile | release | Profile |
| release | release | Release |

Profiles retain separate native build/staging paths. Xcode products are under
`apple/DerivedData/Build/Products/<configuration>/BonsaiJournal.app`; iOS adds
`-iphoneos` to the configuration directory. SDK paths are carried in a private
`BONSAI_SWIFTUI_APPLE_SDK_ROOT` variable rather than changing the compiler's
ambient `SDKROOT`, which can also affect host tools during cross compilation.

An explicitly selected complete object can enter the same verified pipeline:

```sh
bonsai-swiftui build ios --profile release \
  --native-object /path/to/ios18/native_embed.exe.o \
  --development-team "$APPLE_DEVELOPMENT_TEAM"
bonsai-swiftui run ios --profile release \
  --native-object /path/to/ios18/native_embed.exe.o \
  --development-team "$APPLE_DEVELOPMENT_TEAM" --device "$DEVICE_ID"
```

The object must register the entrypoint used by the application's Swift source.
Relative object paths are interpreted from the invocation directory. The
physical device ID is mandatory before an iOS run can start building. Builds
may use `--no-codesign`; runs always require signing. No Simulator fallback or
Flutter command is used. Automatic installed-SDK discovery now requires the
iOS 18 floor, but publication/install validation of the replacement SDK remains
unfinished; the verified iOS CLI route uses an explicit iOS 18 object.

`exec -- COMMAND ARGUMENT...` prepares verified macOS native artifacts, stages
the host object and preserves the command's arguments, working directory,
failure status and interrupts. It provides `BONSAI_SWIFTUI_NATIVE_OBJECT` and
`BONSAI_SWIFTUI_CONFIGURATION` without rewriting a project configuration or
pubspec. `--native-object` can also select its input explicitly.

## Cleanup and prerequisites

`clean macos` and `clean iphoneos` remove the selected native build state,
staged host objects and Xcode product directories. They retain the other
platform's output and shared Xcode intermediates. `clean --all-project-builds`
also removes the entire generated Native and DerivedData directories. Neither
mode removes application sources or the generated Xcode project. All output
parents are checked before deletion; cleanup refuses to traverse a symlink
parent outside the project, and removing an output symlink never deletes its
referent.

`doctor` checks Python 3.9 or newer, opam, Dune, Xcode and the selected Apple SDK/Swift
compiler. Python supplies the shared deterministic Xcode generator. Development
from this checkout additionally needs its OCaml packages available to external
Dune projects, for example through the `_build/install/default/lib` directory
after `dune build @install`.

## Behavioral evidence

`tool/test_swiftui_cli.py` exercises actual CLI initialization/adoption,
read-only checking/repair, invalid configuration rejection before writes,
wrong-platform object rejection, cleanup boundaries, argument fidelity,
failure status and interrupt forwarding. Its independent application builds
from the generated OCaml program in Debug/Profile/Release. A native SwiftUI
window then presses Increment and verifies `Count: 0` becomes `Count: 1`
through the real OCaml runtime. No Flutter process or Swift-only model is used.

The first run reproduced the absent native initialization and invalid-config
write ordering (`/tmp/swiftui-cli-apple-red-final.log`). Ownership/process tests
pass (`/tmp/swiftui-cli-apple-ownership.log`). The external application exposed
the misplaced Debug ABI check, then passed all three builds, native execution
and command status checks in 120.841 seconds
(`/tmp/swiftui-cli-apple-external-second.log`). Cleanup tests reproduced retained
Xcode output and missing parent validation, then both passed
(`/tmp/swiftui-cli-apple-clean-red.log`,
`/tmp/swiftui-cli-apple-clean-green.log`).

The old pubspec/adapter/profile-injection tests are replaced by these real
native workflows. Fifty existing non-Flutter CLI/library tests retain the SDK,
closure, configuration, artifact, locking and source-ownership contracts, plus
three direct-native-build integration tests. Full widget coverage, Gallery,
complete screenshots, package renaming and SDK publication are still open.

The final seven-test CLI suite passes in 126.764 seconds
(`/tmp/swiftui-cli-apple-integration-final.log`). The repository
`@all @runtest @fmt @install` gate also passes
(`/tmp/swiftui-cli-apple-repository-continuation.log`).

The actual Mail Swift App and iOS 18 OCaml complete object also build through
`bonsai-swiftui build ios --profile release --native-object ...` with development
signing. The resulting App passes deep/strict signature, IOS/arm64/minimum 18.0,
iPhone/iPad family and provisioning-profile checks
(`/tmp/swiftui-cli-mail-ios-build.log`). The persistent project and evidence are
under `_build/validation/swiftui-cli-mail-ios-h4jc0d0s/`; `validation.json`
records the object, executable and Swift source hashes and explicitly leaves
device execution unverified. This is an uncommitted source checkpoint, not a
published SDK or a physical-iOS runtime result.


The shared Xcode generator also passes all six existing integration tests in
272.299 seconds (`/tmp/swiftui-cli-apple-xcode-regression.log`). They build Mail
and execute its actual packaged OCaml startup/presentation/restart XCTest in
Debug, Profile and Release, verify platform settings and wrong-object rejection,
and exercise relative project paths and nested resource packaging. These are
macOS executions, not iOS device or complete screenshot acceptance.


## Standalone repository examples

The ten examples with Swift App entrypoints now own schema-3 configurations:
Clock, Counter, Host Effects, Host Navigation, Mail, Navigation, Network,
SQLite Worker, Text Input and Todo. Their native target is
`ocaml/native_embed.exe.o`. Network explicitly enables the network feature,
and SQLite Worker enables SQLite. Gallery remains unfinished.

With the configured development environment and CLI available, run `build macos`
or `run macos` from an example directory. Project discovery also works from its
`ocaml/` subdirectory. The application retains its Swift sources, resources,
XCTest sources and OCaml program during synchronization and compilation.

Apple SDK library search flags now belong to the native backend library's
`c_library_flags` and propagate through its installed OCaml archive metadata.
Examples and the native runtime fixture no longer include a source-tree-relative
flags file or use an example-specific SDK environment variable. The framework's
Dune rule selects the actual macOS or physical-iOS SDK for the target context.
The private CLI SDK variable remains relevant to artifact preparation.

`tool/test_swiftui_example_cli.py` copies the actual example sources into
independent space-containing directories, generates/checks each host, builds
all ten complete objects and verifies source preservation. Its separate Mail
scenario builds the actual App and runs its packaged OCaml XCTest through
`exec` from a nested directory. No example model is replaced by a test counter.


The final independent-example suite passes both tests in 66.893 seconds
(`/tmp/swiftui-example-cli-library-flags-final.log`), including all ten native
builds and actual Mail App/XCTest execution. The repository build also passes
with the library-owned flags (`/tmp/swiftui-example-cli-repository-final.log`).

Network and SQLite Worker also cross-build and pass complete-object validation
for physical iOS 18 after the library flag change
(`/tmp/swiftui-example-cli-ios-cross.log` and the two corresponding
`/tmp/swiftui-example-cli-ios-*-audit.log` files). Host and target `.cmxa`
metadata contain their respective Apple SDK library paths. These checks do not
establish an installed SDK release or device execution.

## Source package rename

The development executable is now `_build/default/bonsai_swiftui_tool/bin/main.exe`.
There is no old command wrapper or old public-package alias. The OCaml build,
test, format and install targets pass. Eight CLI integration tests pass in
152.948 seconds, including discovery of the new package names and an external
application that builds in all three profiles and changes actual OCaml state.
All eleven standalone examples also build their native objects against the new
packages (20.656 seconds). Installed/published iOS SDK snapshots remain separate
from these source-checkout results.

## Installed CLI acceptance

`make installed-cli-test` exercises the installed layout using an isolated
prefix. Dune installs `bonsai_swiftui`, `bonsai_swiftui_test` and
`bonsai_swiftui_tool`; the test executes the asset-copy commands from the tool's
opam install field. It then invokes the copied executable outside the source
tree, with only the new prefix in `OCAMLPATH` and no
`BONSAI_SWIFTUI_SOURCE_ROOT` override. Ordinary host dependencies still come
from the configured OCaml toolchain.

The external application builds in Debug, Profile and Release, passes native
signature checks, launches and updates real OCaml state from Count: 0 to
Count: 1. Child-command argument and exit-status handling also pass. The Xcode
project selects the installed Swift package. This checkpoint passed in 85.552
seconds; no production code or asset recipe needed changing. It verifies the
installation boundary, not opam dependency resolution or iOS SDK publication.
