# Configurable iOS Deployment Target

## Problem

The Journal iPhone native UI decision requires an iOS 26 baseline for native
Liquid Glass controls. Config currently rejects every iOS minimum except 18.0,
and the Xcode generator hard-codes 18.0 even though native build planning and
SDK validation already consume the configured version. This prevents the
application from declaring its actual supported baseline.

## Proposal

Allow a numeric major.minor iOS deployment target at or above the framework's
18.0 API floor. Pass that target from Config through Host.sync into the generated
application, test hosts, tests, native artifact staging/verification, and package
validation staging. Preserve macOS's existing fixed baseline. Journal will use
26.0 without availability fallbacks or imitation materials.

This is dependency work for the user-authorized Journal native UI implementation,
recorded in its proposed 2026-09-16 native-swiftui-ui-standardization decision.
It does not change the framework's API floor or require rebuilding an SDK whose
manifest already permits a newer application minimum.

The installed OCaml SDK emits a complete object at its own 18.0 floor even
when the application build receives VER=26.0. Final iPhoneOS artifact staging
must perform a relocatable Clang link targeting the application's deployment
version, retaining the SDK floor as a library constraint rather than falsely
reporting the app object as 18.0. Verification stays strict.

The production owner of this artifact's Mach-O deployment metadata is
Artifact.prepare_source and the Apple linker. Plan.native_build is pure and
correctly emits VER=26.0, so its events/state cannot reproduce linker metadata.
The narrow regression compiles a real iOS 18 input object and calls public
Artifact.prepare_source for iOS 26, inspecting the actual staged Mach-O and
retained symbol. This is a valid SDK-floor input, not an injected incorrect
external result. No duplicate application or transport regression is added.

## Decision

Adopt application-configured iOS minimum deployment versions at or above the
framework's 18.0 floor. Host generation, package staging, native object staging
and validation consume that value. iPhoneOS final object staging uses the Apple
relocatable linker at the configured app target before strict verification.

## Alternatives considered

### Override the generated Xcode project manually

Regeneration would discard the minimum and make native verification disagree
with the application. The source configuration must own the supported baseline.

### Force all framework consumers to iOS 26

The library API floor and each application's minimum serve different purposes.
Allow applications to declare their requirements without changing unrelated apps.

## Acceptance criteria

- Config accepts 18.0, 26.0 and 26.1, preserving their exact major.minor values.
- Versions below 18.0 and malformed values are rejected.
- Generated iOS app and test targets use the configured deployment target in
  every build profile; native artifact verification uses that same target.
- A changed minimum is detected by read-only host checking and regeneration
  produces a host that subsequently passes checking.
- Existing configuration, host, native plan and SDK validation tests pass.
- Journal can regenerate and build an unsigned iOS 26 application.

## Consequences

Consumers can select the native API baseline their UI requires without changing
the framework library's floor. A configured target change invalidates host state
and native cache identity. Staging now requires the already-required Apple
Clang toolchain, while SDK-floor inputs remain immutable. The macOS baseline and
framework SDK manifest are unchanged. No compatibility path or validation bypass
is added. Journal's independent UI/device acceptance remains outstanding.

## Risks

- Host generation and package staging must receive the same deployment values.
- A higher app minimum does not make newer APIs available in the framework
  package itself; that package still declares its own API floor.

## Questions

No open questions. The user already selected current-system native UI without
compatibility paths; iOS 26 is required by the chosen Liquid Glass APIs.

## Implementation evidence

Implemented on 2026-09-17 in Config, Host, the Xcode generator and Artifact
staging. The installed local path-pinned CLI was reinstalled from this source.
The Journal config selects iOS 26.0 and `sync-host --check` passes.

The tool configuration/SDK suite passed 51 tests, Python HostConfigurationTests
passed 4 tests, and the native build suite passed 4 tests. The actual Mach-O
regression failed with minos 18.0 before the relocatable staging link and passed
with minos 26.0 afterward; its input remains unchanged and its symbol survives.

Journal's `bonsai-swiftui build-native --target iphoneos --profile release`
passed strict complete-object/ABI verification at IOS/arm64/minos 26.0. Its full
unsigned Release application then built successfully with Xcode, using the
verified object and locked, already resolved Swift dependencies. The app's
Info.plist and executable both declare 26.0. Detailed logs and hashes are in
Journal's `docs/test-reports/2026-09-16-native-swiftui-standardization/batch2-*`
evidence. This dependency outcome does not close Journal's device/UI acceptance.

No protected spec interfaces or Dune files were edited. The separate Journal UI
decision remains proposed. No changes have been committed or pushed.

