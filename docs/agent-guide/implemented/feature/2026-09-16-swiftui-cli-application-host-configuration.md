# Application-owned SwiftUI host configuration

## Problem

Logseq Journal cannot replace its previous host with a CLI-owned SwiftUI host
while expressing its platform identities and authentication storage requirements.
The installed CLI cannot express separate platform bundle IDs,
application entitlements, or application Swift package products. Editing a
generated Xcode project or maintaining a second native build pipeline would
break the consumer ownership contract.

This proposal records the agreed scope for those three CLI capabilities and their
release acceptance. Implementation and installed unsigned acceptance are complete.
It does not modify Journal,
select an authentication provider, or resolve Journal's migration as a whole.

### Evidence rechecked on 2026-09-16

Framework HEAD: `09bd1571f7f1e76327b9402274d31119b7df7ecc`. The worktree already
contains package, documentation, and iOS SDK changes. They must be preserved and
must not be mistaken for changes made while preparing this proposal.

The authoritative consumer report is
[`logseq_journal` preflight](../../../../../logseq_journal/docs/test-reports/2026-09-16-bonsai-swiftui-preflight/README.md).
Its disposable reproduction was rerun without editing Journal:

```sh
python3 /Users/rcmerci/gh-repos/logseq_journal/docs/test-reports/2026-09-16-bonsai-swiftui-preflight/reproduce_host.py
```

| Check | Observed result |
| --- | --- |
| Unmodified generated host | `sync-host --check` exits 0 |
| Candidate `ios.bundle_identifier` | Exit 123: `Unknown ios field: bundle_identifier` |
| Candidate `app.entitlements` | Exit 123: `Unknown app field: entitlements` |
| Candidate `app.swift_packages` | Exit 123: `Unknown app field: swift_packages` |
| Generated platform entitlement files | Both are empty dictionaries |

Installed executable: `/Users/rcmerci/.opam/bonsai-ui/bin/bonsai-swiftui`.
Installed host packages `bonsai_swiftui`, `bonsai_swiftui_tool`, and
`bonsai_swiftui_test` are all `0.1.0~dev`. The release archive at
`~/.local/share/bonsai-swiftui/releases/2026-09-16-logseq-installed/bonsai-swiftui-0.1.0~dev.tar.gz`
was rehashed as
`1e4be4d52491d889ff2f848dca358eddfb6687e4ea36f5cbccd929fe0a389f5a`.
The `bonsai-swiftui-ios` switch has framework SDK `0.1.0~dev.41` and runtime SDK
`0.1.0~dev.7`. Installed `toolchain verify iphoneos` passes with fingerprint
`ef332900b0a90214cbee00cbc0e74f7de90f14af828bb885f4b57b53d3c68149`.
These identify the pre-implementation baseline, not the future release.

Current source agrees with the installed behavior:

- `bonsai_swiftui_tool/lib/config.ml` accepts schema 3, one application bundle
  identifier, and only minimum version/architectures in each platform record.
- `lib/host.ml` passes that one identifier to `tool/swiftui_xcode_host.py`.
  The generator emits empty entitlements and links only local `BonsaiSwiftUI`.
- `lib/build_system.ml` also uses the shared identifier for built-app metadata
  verification and physical-iOS launch. `lib/cache.ml` includes it in cache keys.
- The generator renders expected output in memory before writing, which is a
  useful foundation for validation and read-only drift checks.
- `bin/main.ml` currently initializes/adopts workspace metadata before host
  generation. New file-dependent validation must move ahead of these writes.
- `tool/build_swiftui_example.py` and host tests call the generator directly;
  changing only the installed CLI call site would leave inconsistent behavior.

Journal sources were read directly. macOS uses `com.logseq.journal`; iOS uses
one legacy backend-named identifier in Debug, Profile, and Release. The exact
historical value remains available in the linked preflight report. It is not
retained as a target identity or copied into the proposed configuration.
Both macOS entitlement files contain the Keychain access group
`$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)`. Debug/Profile additionally
contains `com.apple.security.cs.allow-jit = true` and
`com.apple.security.network.server = true`; Release does not. Whole-file
preservation matters, not merely extracting one Keychain key. The existing
[Keychain decision](../../../../../logseq_journal/docs/agent-guide/implemented/bugfix/2026-08-22-macos-amplify-keychain-sharing.md)
requires Data Protection Keychain and the signed application access group.

## Proposal

### Confirmed design choices

On 2026-09-16, the user accepted the remaining recommendations:

- Adopt schema 4 with required platform-local bundle identifiers and replacement
  platform-specific init flags. Update repository-owned consumers directly;
  reject schema 3 and remove the old flag without compatibility paths.
- Use complete per-profile entitlement files, reject conflicting framework values,
  and apply application entitlement inputs and package products only to application
  targets. Test targets do not inherit them implicitly.
- Include `resolve-packages`, an application-owned transitive dependency lock,
  and builds that enforce the lock. Direct dependency pinning alone is insufficient
  for this delivery.
- Use `com.logseq.journal` for Journal on both macOS and iOS. The user approved
  this replacement iOS identity; platform configuration remains independent, and
  acceptance fixtures must also exercise distinct platform identities.

The naming cleanup requirement below is also confirmed. All design questions
have been answered. These confirmations settled the planned scope. The implementation outcome and
acceptance evidence are recorded in the Decision and Validation sections below.

### Scope and ownership

Introduce one coherent configuration model for platform identities, complete
entitlement inputs, and pinned remote Swift packages with explicit products.
Keep OCaml/Swift sources, entitlement inputs, and dependency declarations
application-owned outside `apple_root`. Keep generated projects, plists,
schemes, and effective entitlement files CLI-owned inside `apple_root`.

Use the existing CLI build, sign, and run pipeline. Do not hardcode Journal
values into framework defaults.

### Confirmed naming cleanup requirement

The user's subsequent instruction supersedes the original prompt's requirement
to preserve the backend-named iOS identifier: remove all retired-backend keywords,
including those embedded in application identities. Preserve the macOS identity
`com.logseq.journal` and use the user-approved `com.logseq.journal` as the new iOS
identity in every profile. This choice does not supply a signing team, certificate,
provisioning profile, or device; those inputs remain caller-supplied.

Inventory and remove retired-backend naming from in-scope source and file paths,
module/package references, CLI options, configuration, target/product names,
bundle IDs, entitlement references, scripts, fixtures, comments, and repository
documentation. Regenerate CLI-owned output rather than hand-editing it. Do not
retain old spellings as aliases, fallbacks, or compatibility paths. Verify both
file contents and path names case-insensitively, including compound names and
mixed-case identifiers. A renamed string alone is not sufficient if the obsolete
dependency or implementation remains.

The framework implementation covers framework-owned deliverables. Journal's
source cleanup and deployment identity changes belong to its subsequent migration
task; this proposal does not include editing that consumer repository.
Historical consumer reports are linked as evidence, not copied into new examples
or rewritten to suggest that the baseline used the replacement identity.

Changing the iOS bundle ID is now intentional. Validate its signing/provisioning,
installation and upgrade behavior, and effective Keychain access independently.
Do not claim that preserving the entitlement expression preserves its expanded
access-group value after an identity change. The macOS Keychain contract remains
unchanged. Session continuity remains a separate acceptance gate, and forced
reauthentication is not silently substituted for it.

Excluded: authentication/session conversion, Amplify selection, Journal source
changes, Collection catalog scalability, Simulator/Catalyst support, arbitrary
Xcode build-setting injection, local package overrides, and branch/range package
requirements. No compatibility facade, decoder fallback, old CLI alias, or
automated configuration migration is proposed.

### Selected public model: schema 4

Move the required bundle identifier into each platform block. Require both
platform identities even when equal; remove the app-level field. Accept only
`(lang 4)`. Update repository-owned configurations/examples and tests directly;
reject schema 3 with an actionable error before writes. Document the new syntax
without shipping an old-schema decoder or migration command.

Replace the initialization identity option with
`--macos-bundle-identifier` and `--ios-bundle-identifier`; remove
`--bundle-identifier` rather than retain an alias. When omitted, fresh init may
use the same existing name-derived default for each platform. `init --adopt`
continues to consume the existing configuration and rejects initialization
identity options. Journal supplies `com.logseq.journal` explicitly for both
platforms; the CLI does not derive one platform's identity from the other.

The following schema-4 syntax is supported by the installed CLI. Both Journal
bundle identifiers are finalized:

```lisp
(lang 4)
(app
 (name journal)
 (apple_root apple)
 (native_target app/native_embed.exe.o)
 (features)
 (macos
  (bundle_identifier com.logseq.journal)
  (minimum_version 26.0)
  (architectures arm64)
  (entitlements
   (debug config/entitlements/macos-debug-profile.entitlements)
   (profile config/entitlements/macos-debug-profile.entitlements)
   (release config/entitlements/macos-release.entitlements)))
 (ios
  (bundle_identifier com.logseq.journal)
  (minimum_version 18.0)
  (architectures arm64))
 (swift_packages
  (package
   (id swift-collections)
   (url https://github.com/apple/swift-collections.git)
   (requirement (exact 1.1.4))
   (products
    (product
     (name OrderedCollections)
     (platforms macos ios))))))
```

The package is a small CLI acceptance example, not Journal's authentication
provider. Its published [1.1.4 manifest](https://raw.githubusercontent.com/apple/swift-collections/1.1.4/Package.swift)
exports `OrderedCollections`. The disposable consumer should import that module
and use `OrderedSet` in executed Swift code. Passing this example establishes
package integration only. Journal's final features, native target, and provider
products must come from its separately validated migration requirements; the
example's `(features)` does not assert Journal's native dependency closure.

### Platform identity behavior

Select the platform identity consistently in all three Xcode configurations,
application build settings, generated plist substitutions, built-app validation,
and iOS launch commands. Keep `CFBundleIdentifier` expressed through
`$(PRODUCT_BUNDLE_IDENTIFIER)` and verify the resolved app plist after building.

Derive generated runtime test-host, runtime-test, and UI-test bundle IDs from
that platform's application ID with the existing `.test-host`, `.tests`, and
`.ui-tests` suffixes. Validate derived identifiers too, including length limits.
This does not preserve the previous host's test-target bundle names.
Test process identities are separate from production application identities.

### Entitlement inputs and effective files

An omitted `entitlements` block means no application additions. When present,
require exactly `debug`, `profile`, and `release`, each naming one complete
plist dictionary. Reusing a file across profiles is explicit. No implicit
Debug-to-Release inheritance, shallow overlay, or key allowlist is introduced.
An intentionally empty profile uses an empty dictionary file.

Resolve inputs relative to the application root. Require readable regular files
within that root and outside `apple_root`; reject absolute paths, parent
traversal, directories, and symlink escapes, including paths that resolve back
into generated output. Place Journal inputs under `config/entitlements/`, not
`resources/`, because the current generator bundles the latter as app resources.

Parse XML or binary plist dictionaries without discarding keys or changing
value types. Reject malformed/non-dictionary inputs and duplicate XML dictionary
keys rather than allowing a parser to silently overwrite them. Preserve nested
values, booleans, arrays, and build-setting substitution strings verbatim.
Serialize deterministically to profile-specific generated files such as
`Entitlements/macOS/Debug.entitlements`. Set each application configuration's
`CODE_SIGN_ENTITLEMENTS` to its corresponding file.

Define framework-required entitlements as a separate, explicit dictionary; it
is currently empty. Merge disjoint keys and identical values. Fail on a shared
key with unequal typed values, naming the platform, profile, and key. Do not
silently override values or union access-group arrays. Application inputs are
never rewritten. Xcode/provisioning-added signature entitlements are separate
from this source merge and are inspected after signing when credentials exist.

Application entitlements apply to application targets only. Generated test
hosts/runners do not automatically inherit production Keychain access groups
or app capabilities; their required entitlements remain independently generated.
Test-specific entitlement configuration is outside this first scope. Report
that limit if a subsequent authentication test requires it.

For Journal, preserve the full Debug/Profile source dictionary including both
additional booleans, and the complete Release dictionary. Never substitute a
team prefix during generation, disable Data Protection Keychain, change access
groups, or use forced reauthentication as an acceptance workaround.

### Swift packages and product selection

`swift_packages` is optional. Each package has a unique stable `id`, a remote
HTTPS Git URL, exactly one requirement, and one or more named products. Initially
support `(exact X.Y.Z)` and `(revision FULL_COMMIT_HASH)`; reject mutable branches,
version ranges, abbreviated revisions, duplicate package identities/URLs,
conflicting pins, empty products, and unknown fields. Validate supported version
and full-revision syntax explicitly rather than forwarding arbitrary text.

Each product requires a nonempty, duplicate-free platform list of `macos` and/or
`ios`. Link it only to selected application targets in every profile. Reject
ambiguous product-name collisions on the same target and attempts to replace
the reserved framework package/product. Reuse a single remote package reference
per identity and create deterministic product/build-file references per target.
The installed local `BonsaiSwiftUI` reference remains framework-owned.

Application runtime-test and UI-test targets do not receive all application
packages implicitly. Additional test-target linkage can be a later explicit
capability; this change guarantees application Swift imports. Platform-only
imports in shared `swift/*.swift` sources require application-owned Swift
conditional compilation.

Validate declaration structure offline before any host mutation. Remote URL
availability, tag/revision existence, exported product names, platform support,
and transitive solver compatibility require package resolution. Resolve and
validate them in disposable staging before publishing host output on a build or
explicit dependency-resolution operation; retain the previous host on failure.
`sync-host` and `sync-host --check` stay offline and must not claim remote
semantic validation. A syntactically valid but nonexistent remote product is a
resolution failure, distinct from an invalid configuration structure.

### Dependency reproducibility decision

An exact direct version or revision alone does not freeze transitive dependencies.
Selected scope: add one explicit `bonsai-swiftui resolve-packages` operation
that uses Xcode's resolver in staging and writes an application-owned
`swift-packages/Package.resolved` outside `apple_root` after successful validation.
Commit that lock with application configuration; do not edit generated projects.

For remote-package builds, require a matching lock and enforce its resolved
versions/revisions. Missing or stale locks should give the resolution command
as the next step, not silently update dependencies. `sync-host` copies the lock
into the generated Xcode workspace's expected location when available;
`sync-host --check` compares that projection without resolving or writing.
Allow offline host generation before the first lock exists, with deterministic
absence of the generated lock. Builds and release acceptance require resolution.

Before declaring implementation complete, prove on the supported Xcode version that one
shared lock covers the two platform product selections, that automatic package
updates can be disabled, and that a relocated generated host honors the lock.
Treat this as an implementation gate, not a capability already demonstrated.
Do not implement a custom Swift dependency solver or silently reduce this scope
to direct dependency pinning if the Xcode integration needs further work.

### Generation, validation, and adoption boundary

1. Parse and validate the entire typed configuration, including all platforms,
   profiles, identifiers, and package declarations.
2. Read and validate every entitlement input and any lock input; validate source
   ownership and required adopt inputs before writing workspace metadata.
3. Render the full expected host in memory. Use stable object identities and
   canonical ordering; do not include temporary paths or resolver timestamps.
4. In check mode, compare only. Do not create directories, locks, temp files in
   the consumer, downloads, or resolver state. Snapshot paths, bytes, and mtimes
   in tests to demonstrate the read-only property even on failure.
5. In write mode, update only validated CLI-owned output. Invalid input must leave
   either an absent host absent or the prior host unchanged. Plan cleanup of
   obsolete CLI-owned output names when moving to per-profile entitlements,
   without recursively deleting unrelated files or application inputs.
6. Build/run must perform the same preflight before native staging or workspace
   mutations. Resolve remote semantics in staging before publishing a new host.
   I/O failure recovery is separate from the no-partial-output input guarantee.

Preserve `init --adopt` source bytes and mtimes for existing OCaml, Swift, Dune,
opam, configuration, entitlements, and package lock files. It must not resolve
packages, rewrite existing metadata, append aliases, or synthesize app code.
There is no old configuration conversion hidden inside adopt.

### Implementation work packages

These are the ordered implementation scopes of the agreed proposal.
Write focused failing tests before the implementation of each behavior.

| Step | Files / area | Work and completion evidence |
| --- | --- | --- |
| 1. Configuration and initialization | `bonsai_swiftui_tool/lib/config.ml`, `lib/scaffold.ml`, `bin/main.ml`, `test/tool_tests.ml`, `test/native_plan_tests.ml` | Typed platform identities, profile input paths, package/product declarations; schema 4 and new init options; failures precede writes; remove old shape |
| 2. Host rendering and preflight | `lib/host.ml`, `tool/swiftui_xcode_host.py`, `tool/build_swiftui_example.py`, `tool/test_swiftui_xcode_host.py` | Validated data passed without a second public config decoder; profile-specific settings and plist merge; deterministic remote references/product linkage; all direct callers updated |
| 3. Build/run integration | `lib/build_system.ml`, `lib/plan.ml`, `lib/cache.ml`, existing OCaml plan tests | Platform-correct verification/launch; inspect cache inputs and prevent stale host reuse when entitlement contents or pins change; avoid unnecessary native recompilation where inputs are host-only |
| 4. Resolver/lock | `bin/main.ml`, `lib/host.ml`, `lib/plan.ml`, `lib/build_system.ml`, existing Python host helper/tests | Staged resolution, product validation, app-owned lock, locked build flags, offline sync; prove behavior with the actual Xcode toolchain |
| 5. Consumer and ownership acceptance | `tool/test_swiftui_cli.py`, `tool/test_swiftui_installed_cli.py`, `tool/test_swiftui_ios_installed.py`, `tool/test_swiftui_opam_install.py` | Reusable independent consumer covers profile/platform matrix, real package import/use, adoption, read-only drift detection, regeneration, and failures |
| 6. Public configuration and release | `docs/swiftui-cli.md`, `docs/swiftui-xcode-host.md`, `docs/opam-installation.md`, relevant `README.md` sections, `examples/*/bonsai-swiftui.sexp`, affected fixtures | Complete syntax/ownership/signing examples; update existing consumers directly; package/install matching release; rerun installed acceptance and record evidence |

Paths abbreviated as `lib/`, `bin/`, or `test/` in this table are under
`bonsai_swiftui_tool/`. Inventory all schema-3 literals and direct generator
callers before editing; the table is not permission to ignore other consumers.

Reuse the existing OCaml test stanzas and Python unittest entrypoints. Current
CLI dependencies are `digestif`, `sexplib`, and `unix`; carry typed host inputs
through explicit helper arguments or another dependency-free encoding, rather
than adding an OCaml JSON dependency that requires a protected Dune edit.

No protected interface or Dune-file change is currently required. The active
spec interfaces are under `ocaml/spec/`; no spec change is proposed there or
under any `spec/` subtree. Do not edit `dune`, `dune-project`, or protected OCaml
interfaces as part of this scope without explicit authorization. If new test
stanzas, dependencies, release-version edits in `dune-project`, or an interface
change become necessary, report the exact file and stanza/signature first.
Stop immediately if an unclear or unreasonable protected `.mli` blocks progress.

### Release and installed-consumer acceptance

Use the existing release workflow, not a hand-built prefix as the final proof:

1. Record implementation HEAD and the exact dirty source inputs included in the
   release. The packager includes non-ignored untracked source files, so audit
   its input set and preserve the pre-existing worktree changes.
2. Run `python3 tool/package_opam_release.py <new-immutable-source-release-dir>`.
   Repeat into a separate new directory to check identical archive SHA-256 for
   identical inputs. Never replace an already delivered archive.
3. For an unpublished local source release, use
   `sh tool/ios/regenerate_sdk_repository.sh --source-archive <source-archive>`,
   followed by its `--check` form. Record the source archive hash separately
   from the final host/CLI release hash; avoid a self-referential archive identity.
4. Repackage after SDK metadata generation. Install all three host packages from
   that final release repository, even if version strings are unchanged; verify
   opam's recorded source checksums rather than trusting versions alone. Use
   explicit reinstall when the selected installed version already exists.
5. Install/update the matching iOS SDK through the supported toolchain workflow.
   Run installed `doctor` and `toolchain verify iphoneos`; record host switch,
   compiler/Xcode versions, package versions/checksums, runtime/framework SDK
   versions, SDK source identity, and verification fingerprint.
6. Run the independent consumer through the installed executable with no
   framework `_build` references, source-root override, or framework `OCAMLPATH`.
   Framework-local development tests and the prefix-layout smoke test are not
   substitutes for real opam installation and installed-CLI acceptance.
7. Deliver the exact schema-4 Journal host example using `com.logseq.journal` for
   both platforms, entitlement source contents,
   verified generic package example, commands/results, and blocked signing/device
   checks. Keep the Amplify provider/version/products explicitly unresolved until
   its separate compatibility work selects them.

If implementation code is later committed and pushed, the repository rule also
requires regenerating the iOS SDK repository from that pushed commit and committing
and pushing the generated SDK update separately. An archive-based local release
does not replace that post-push obligation. Proposal preparation performed no commit, push or installation. The implementation
subsequently generated immutable local releases and installed their packages;
no framework source commit or push has been made.

## Decision

Implemented schema 4 with required platform-local identities and replacement
initialization options, complete profile entitlement inputs, typed remote package
declarations, staged resolution and an application-owned transitive lock. The
CLI validates file inputs before initialization, adoption, native preparation or
Apple build writes. Native cache keys exclude host-only identities and paths.
Application products and entitlements remain isolated from test targets.

Xcode 26.1.1 resolves nonexistent product names without rejecting them, and its
modern build system rejects `-dry-run`. Resolution therefore compiles disposable
SwiftUI validation applications with each platform's selected products before
publishing output. Locked builds disable automatic resolution/updates and
compare the complete resolved pin graph. There is one supported implementation,
with no old schema decoder, old initialization alias or custom dependency solver.
The existing signing pipeline also accepts a caller-selected `--signing-identity`.

## Alternatives considered

### Keep an app-level bundle ID with optional platform overrides

This reduces configuration edits but retains two competing identity locations
and implicit inheritance. Prefer required platform identities in schema 4 and
direct updates to repository-owned consumers. The user accepted this breaking
surface; the optional-override alternative is not selected.

### Inline entitlement dictionaries or per-key/profile overlays

Both introduce another plist representation and potentially lossy merge rules.
Complete application-owned plist files preserve existing value types and profile
differences. Require explicit profile mappings and fail on framework conflicts.

### Hand-edit generated Xcode projects or add a native build wrapper

Rejected: generated artifacts must remain CLI-owned and installed consumers must
use the supported build/sign/run pipeline. Neither is an acceptance workaround.

### Implement Amplify integration as the package acceptance fixture

Rejected for this scope: it entangles CLI correctness with unverified session
storage compatibility and authentication configuration. A small pinned remote
package establishes linkage/import behavior without implying session continuity.

### Pin direct dependencies without an application-owned lock

Smaller than the selected resolver/lock scope and sufficient to express exact
versions/revisions. However, transitive dependencies may vary across resolutions;
it cannot establish a reproducible full dependency graph. Not selected: the user
accepted transitive locking and locked builds as part of this delivery.

## Acceptance criteria

The criteria below were the agreed implementation gates. Automated behavior,
real package resolution/builds, installed consumers and release provenance now
pass as recorded in the linked acceptance report. Caller-dependent production
signing, device, Keychain and session-continuity checks remain explicitly blocked.

- Complete the behavior, ownership, installed-consumer, and release gates below;
  report signing/device prerequisites separately when they prevent verification.

| Gate | Required observable result |
| --- | --- |
| Failing tests first | Focused parser/generator/CLI tests fail for the intended missing behavior before the implementation; no source override in final consumer acceptance |
| Platform identity | Both identities are correct across Debug/Profile/Release settings, generated plist references, derived test identities, app metadata verification, and iOS launch plan |
| Entitlements | All source keys/types survive; Debug/Profile differ correctly from Release; substitutions remain literal before signing; source files are unchanged |
| Conflict/error cases | Invalid/overlong IDs, duplicate/unknown fields, invalid profile maps, missing/malformed/non-dictionary/duplicate-key plists, unsafe paths, merge conflicts, duplicate packages/products, bad pins, and unsupported platforms produce clear diagnostics without partial host generation |
| Package import | A pinned remote package resolves; selected targets link its product; Swift imports and executes a value from the package; unselected targets have no product linkage |
| Remote failures | Missing revision/product or incompatible package fails staged resolution without changing the previous host; sync remains offline and distinguishes these from syntactic invalidity |
| Reproducibility | Repeated sync produces identical bytes and preserves unchanged mtimes; exact and revision declarations are tested; repeat fresh-cache resolution/build from the committed lock and verify no dependency drift |
| Adoption | `init --adopt` preserves all existing application inputs and succeeds with configured IDs/entitlements/packages |
| Drift checks | Check passes after generation; deliberate generated-file or source-entitlement changes are detected with no writes; supported regeneration repairs output and check passes again |
| Failure ownership | Snapshot existing and absent hosts before invalid init/adopt/sync/build attempts; compare paths, contents, and mtimes afterward |
| macOS builds | Installed CLI builds independent consumer in Debug, Profile, and Release; inspect effective settings and built plists; run package-use smoke behavior |
| iOS build | Generate both platform hosts; verify installed SDK; build an unsigned physical-iOS app where supported and inspect its identifier/product linkage |
| Signed entitlements | With caller-provided signing/team credentials, inspect actual signed macOS app entitlements for each profile, including expanded Keychain access group; verify iOS signing/device launch only when the corresponding inputs exist |
| Release identity | Matching host library/CLI/test packages installed from recorded final archive; corresponding iOS SDK metadata verified; exact source/final archive hashes and package/SDK identities recorded |
| Public documentation | Full example uses `com.logseq.journal` for both platforms and includes complete app-owned macOS entitlement inputs, explicit package products/platforms, schema policy, ownership, lock policy, and signing limits |
| Naming cleanup | Case-insensitive content and path audits find no retired-backend keywords in in-scope deliverables, including compound bundle IDs; obsolete dependencies and paths are removed rather than aliased; generated output is regenerated |
| iOS identity change | Replacement identity is explicit; signing/provisioning, installation/upgrade behavior, and effective Keychain access are verified or recorded as blocked; historical session continuity is not inferred |

Use existing entrypoints as applicable:

```sh
dune exec bonsai_swiftui_tool/test/tool_tests.exe
dune exec bonsai_swiftui_tool/test/native_plan_tests.exe
python3 tool/test_swiftui_xcode_host.py
python3 tool/test_swiftui_cli.py
python3 tool/test_swiftui_installed_cli.py
python3 tool/test_package_opam_release.py
python3 tool/test_swiftui_opam_install.py
python3 tool/test_swiftui_ios_installed.py
```

The independent consumer must include a genuine remote fetch and build, not only
PBX text assertions or a local package mock. Use synthetic acceptance identities
for executable/signing tests unless the caller explicitly supplies authorized
identities; assert `com.logseq.journal` for both Journal platforms in
generation-only fixtures. Also use distinct synthetic IDs to test independent
platform selection; Journal's equal IDs do not exercise that distinction.

No signing identity, team, provisioning profile, or device ID is invented.
Unsigned/ad-hoc builds do not establish production Keychain access. Record
unavailable signing/device gates as blocked, with the missing prerequisite;
do not mark them passed. Do not infer Amplify session continuity, Journal's
complete native dependency closure, or physical-device acceptance from CLI tests.

## Consequences

Repository-owned consumers now require schema 4. Remote package applications
commit `swift-packages/Package.resolved`; offline sync projects this lock without
fetching or writing source inputs. Explicit resolution and build preflight need
Xcode and validate both Apple platform graphs in staging. Application OCaml
objects are not required to resolve Swift packages.

Three host packages were reinstalled from the same immutable final archive.
Framework SDK snapshot `.42` identifies the separate immutable source archive;
runtime SDK `.7` is unchanged. Existing dirty source/SDK work was preserved and
audited. No protected spec interface or Dune file was changed by this work.
No Journal source change, authentication-provider selection, production signing
claim or device/session-continuity claim is included.

## Risks

- Schema 4 and replacement init flags deliberately break existing callers. Update
  repository-owned examples and fixtures together; external applications must
  adopt the documented shape explicitly, without a compatibility implementation.
- Generated test identities remain derived; automatic production entitlement or
  package inheritance could expose capabilities to unintended test processes.
- macOS's current default ad-hoc signing cannot prove Journal's Keychain contract.
  If the current CLI cannot express caller-supplied signing needs, identify and
  minimally extend that existing pipeline rather than edit generated projects.
- Xcode package resolution, lock placement, and platform-product behavior require
  real-toolchain validation. Remote outages must be distinguished from local CLI
  regressions. Resolver/lock integration is required scope, not an optional extension.
- Full plist preservation is intentional, but it does not certify that every
  entitlement is valid for a supplied Apple provisioning profile.
- Source and final CLI release archives can have different hashes because the CLI
  bundles SDK metadata. Confusing those hashes can create a falsely matched SDK.
- The dirty baseline includes release metadata and generated SDK work. Preserve
  its ownership; do not silently include unrelated work in an implementation commit.
- Removing the backend-named iOS identity can change installation/upgrade and
  Keychain behavior. The naming cleanup and replacement `com.logseq.journal`
  identity are decided, but continuity results remain unverified. Do not
  reintroduce the retired name to bypass those outstanding checks.

## Questions

- None. The user confirmed all design choices, including `com.logseq.journal`
  for iOS, on 2026-09-16. Xcode locking is verified; production signing, Keychain
  and device checks require caller-supplied inputs and the separate consumer
  migration. Revisions and lifecycle transitions follow `spec-dev-tool`.

## Validation

The [acceptance report](../../../test-reports/2026-09-16-swiftui-host-configuration/README.md)
records source/final archive hashes, the exact dirty input inventories, installed
opam checksum records, compiler versions, SDK source identity and fingerprint,
commands, test logs, remote lock pins and blocked caller-dependent gates.

- `dune build @all @install`, `dune runtest`, 50 focused OCaml CLI/library tests,
  three native plan tests, formatting checks and `git diff --check` pass.
- Twelve CLI ownership/build tests, twelve Xcode host tests and three release
  packager tests pass. All twelve standalone example configurations synchronize
  and build their native objects while preserving application inputs.
- Five installed-host scenarios pass in 353.163 seconds with no source override
  or framework `OCAMLPATH`: Debug/Profile/Release macOS package imports execute,
  unsigned physical-iOS package linkage builds, full-revision pins work, repeated
  fresh-cache resolution preserves output, and transitive/missing-product/revision
  failures preserve existing or absent hosts. The graph includes the genuine
  remote `swift-algorithms` to `swift-numerics` transitive dependency.
- Installed iOS SDK tests pass (38.157 seconds), and installation-layout smoke
  passes (94.222 seconds). Both source-package reproduction and regenerated SDK
  repository checks pass; installed `doctor` and `toolchain verify iphoneos` pass.
- The documented Journal fixture generates both `com.logseq.journal` platform
  identities and its complete profile entitlement dictionaries without signing.
- Production signatures/expanded access groups, provisioning/device launch,
  installation/upgrade behavior and historical session continuity are blocked
  on caller-selected credentials/device inputs and the separate consumer migration.
