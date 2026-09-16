# Testing the SwiftUI backend

The target matrix is physical iOS/iPadOS 18.0+ arm64 and macOS 26.0+ arm64.
iOS Simulator and Intel Mac are explicitly unsupported. The backend migration
is incomplete; commands below exercise the implemented boundaries. Their
success does not establish every widget, physical-device execution or screenshot
acceptance. See the [implementation ledger](swiftui-implementation.md) and the
[governing decision](agent-guide/proposed/architecture/2026-09-11-swiftui-only-apple-backend.md).

## Local commands

Use the project's OCaml switch and run commands from the worktree root. The
current development switch is `bonsai-ui` (OCaml 5.1.1). Refresh an already-open
shell after the switch rename so tools resolve from the current prefix:

```sh
eval "$(opam env --switch=bonsai-ui --set-switch)"
```

The separate `bonsai-swiftui-ios` switch contains the physical-iOS SDK; the CLI
selects it automatically for iOS builds.

```sh
opam exec --switch=bonsai-ui -- dune build @all @runtest @fmt
opam exec --switch=bonsai-ui -- dune exec protocol/generator/generate.exe -- --check
opam exec --switch=bonsai-ui -- dune exec protocol/generator/generate_fixtures.exe -- --check
opam exec --switch=bonsai-ui -- sh tool/check_viewport_types.sh
python3 tool/run_swift_tests.py
python3 tool/test_swift_platforms.py
opam exec --switch=bonsai-ui -- spec-dev-tool check --all
git diff --check
```

`python3 tool/run_swift_tests.py` requires a fresh, completed Swift Testing xUnit
report with executed cases and no failures. An XCTest message reporting zero
tests does not prove the Swift Testing run completed.

The September 14 full run at source `404ae17` passed 489 tests in 107 suites
in 486.197 seconds, including the final macOS Button/pan arbitration fix.
Source fingerprints and the log digest are recorded in
`_build/validation/swiftui-final-macos-404ae17.json`; this result does not include
physical-device or SDK-publication acceptance.

`make swift-test` additionally runs the C/OCaml native boundary, generator tests,
platform checks and standalone macOS window tests. Run it in the configured
OCaml environment. The `ci-*` packaging targets dispatch native builds for
the eleven examples. Their complete pipeline is not yet verified: the full
CI contract rejects the obsolete published SDK metadata before compiler and
Xcode checks. Build-matrix scheduling tests do not establish completed builds
of every configuration.

## OCaml and native runtime

Headless tests exercise actual Bonsai state, keyed reconciliation, revisioned
handlers, presentation acknowledgment, rejected-frame recovery, clocks, host
requests and lifecycle changes. They include randomized patches and large keyed
reorders. Text tests cover Unicode selection and marked-text revisions.

The runtime fixture embeds real OCaml consumers and Gallery components. It is
linked to the Swift tests through `native/test/libruntime_fixture.dylib` under
Dune's build directory. Swift actions must cross the production event bridge and
produce an OCaml-owned update; a Swift-only application reducer is not a valid
substitute.

Native tests cover C buffer ownership, ABI exports, startup validation, singleton
runtime ownership and shutdown. Worker tests use real domains, bounded channels,
cancellation and generation fences. Network and SQLite tests exercise their
actual service boundaries. Detailed checkpoint evidence and remaining physical
acceptance are recorded in the implementation ledger.

## Swift renderer and presentation

The Swift suite tests frame validation and atomic publication, identity,
displayed-event ownership, delayed/stale callbacks, resource disposal and
foreground/hidden-session behavior. Malformed frames must not partially change
the committed tree. The generated protocol is checked against the source schema;
old protocol versions and retired Page payloads are rejected.

Navigation uses OCaml-controlled `View.Navigation_stack` paths and
`View.Navigation_split`. Modal content uses `View.Sheet`; anchored content uses
`View.Popover`. The old Navigator/Page/Modal_* API and route-pop event are removed.
Relevant tests cover native Back actions, declined path changes, accepted/rejected
modal dismissal, disabled choices, repeated actions, inactive content and
same-window modal input fencing. Native sizing tests measure fitted/form/page
presentations subject to window and content constraints.

The Gallery page-layout test also verifies fixed header/footer controls around
a scrolling Body, independent actions, footer/window resizing and retained scroll
position. Scaffold slots are removed; these tests exercise ordinary composition.
See [page layouts](swiftui-page-layout.md).

Focused examples:

```sh
swift test --scratch-path _build/swift --filter NavigationStackTests
swift test --scratch-path _build/swift --filter SheetTests
swift test --scratch-path _build/swift --filter PopoverTests
python3 native/test/test_navigation_window.py
python3 native/test/test_mail_window.py
```

Native window tests use their own SwiftUI/AppKit windows. Accessibility actions
and native callback tests verify specific interaction paths. They do not prove
physical pointer/keyboard dispatch, VoiceOver, iOS gesture cancellation, device
IME or performance. In particular, Sheet's actual Gallery test covers a nested
popover; it does not establish concurrent or nested sheet arbitration.

The former Flutter route harness also covered custom transition geometry,
receding backgrounds, Material barrier appearance and restoration IDs. These
framework-specific controls are removed in favor of system navigation and
presentation. Their deletion does not waive keyboard avoidance, focus ownership,
scroll/detent arbitration, dismissal correctness or accessibility acceptance for
the new native implementation.

The [macOS host environment tests](swiftui-host-environment.md) mount the actual
application boundary in native windows and verify OCaml environment updates,
hide/resume, resizing and runtime restart. Their read-only accessibility checks
compare current system values; they do not toggle system preferences. Automatic
iOS environment observation is implemented; its physical-device behavior
remains an acceptance item.

## Mail and physical-device acceptance

### Signed native bundle audit

`tool/ci/verify_ios_bundle.sh <SwiftUI.app> <development|distribution>
[app.dSYM] [require-sqlite]` verifies the native executable and resources, then
checks the actual code signature, embedded profile, authorized signing
certificate, Team ID, exact or wildcard App ID, bundle identifier, UTC expiry
and typed `get-task-allow` entitlements. It no longer expects a Flutter framework.
The optional dSYM and explicit SQLite requirement can be used together.

Run `python3 tool/test_signed_ios_bundle.py` on a signing-enabled Mac. This
separate test requires the built native DataScript probe App/dSYM, a genuine
development profile and its installed private key. Defaults use the DataScript
probe products and Mail's embedded profile. Override them with
`SWIFTUI_SIGNED_AUDIT_APP`, `SWIFTUI_SIGNED_AUDIT_DSYM`,
`SWIFTUI_SIGNED_AUDIT_PROFILE` and optionally `SWIFTUI_SIGNED_AUDIT_IDENTITY`.
Missing prerequisites fail setup; this credential-dependent test is not part
of the credential-free `ci-contract` lane.

The test signs temporary App copies and exercises genuine signature failure,
ad-hoc signing, missing profiles, mismatched entitlements and bundle IDs,
expiry, dSYM and SQLite requirements. Only the expiry audit subprocess sees
a future clock. It does not install an App, export private keys or change the
system clock. The checkpoint passes nine signing tests and four native bundle
regressions. A positive distribution-signing run and physical installation
remain required; this metadata audit does not replace device provisioning
validation. Apple's [TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
describes these profile fields and their diagnostic limitations.

### Mail execution

Build the current macOS Mail application against its OCaml complete object:

```sh
opam exec --switch=bonsai-ui -- python3 tool/build_swiftui_example.py mail
codesign --verify --deep --strict examples/mail/apple/DerivedData/Build/Products/Debug/BonsaiMail.app
```

The native Mail window regression checks inbox rendering, inline expansion and
archive actions through OCaml. It also posts native mouse events to distinguish
row dragging from ordinary clicking. The full application behavior suite covers
mailboxes, read/star state, detail, attachment/reply notices and paging. These
checks do not replace actual reviewed application screenshots.

`tool/test_swift_platforms.py` compiles the full Swift module and available
example entrypoints for physical iOS 18 arm64, and checks explicit rejection of
unsupported targets. It does not cross-link OCaml, provision/sign an application,
install on a device or execute iOS UI tests.

Physical iOS acceptance requires an available iOS 18+ device and development
signing. It must include the runtime, input/IME, navigation, scrolling, native
presentation, accessibility and screenshot gates in the governing decision.
Do not add a Simulator lane to replace those requirements.

Mail screenshots must come from the running SwiftUI app linked to real OCaml and be
saved with the required reproducibility manifest under
`docs/screenshots/swiftui-mail/`. Diagnostic view rasters, previews and mockups
do not satisfy that deliverable. A locked desktop does not establish a usable
macOS application-window capture.

The [device guide](ios-device-testing.md) gives the current native launch and
application-owned XCTest commands, including recovery from unlock/automation
prompts without rebuilding unchanged products. The
[committed-source macOS captures](screenshots/swiftui-mail/committed-source/README.md)
include the corrected mouse-drag behavior and exact binary/image provenance.
