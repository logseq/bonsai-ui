# Application-owned SwiftUI host configuration acceptance

Date: 2026-09-16. Implementation HEAD: `09bd1571f7f1e76327b9402274d31119b7df7ecc`
plus the audited dirty worktree. No framework source commit or push was made.
Journal's repository was not modified. Signing and device gates below remain
blocked on caller-supplied selections; unsigned builds are not signing evidence.

## Release provenance

All three host packages (`bonsai_swiftui`, `bonsai_swiftui_tool`,
`bonsai_swiftui_test`, version `0.1.0~dev`) were explicitly reinstalled in the
`bonsai-ui` opam switch from the final immutable local release repository.
Their installed opam records all contain the final archive checksum.

| Artifact | SHA-256 |
| --- | --- |
| SDK framework source archive | `2eaa76457fa3638e68b772c26411052416e8d4871e45ae6c83ea3db7864aad88` |
| Final host/CLI/test release archive | `dbce93fc108e052328dc0b94576930a3c1caceb1d60b84b05e19382f9f1161fc` |

The immutable directories are under
`~/.local/share/bonsai-swiftui/releases/`:

- `2026-09-16-host-configuration-source-01`
- `2026-09-16-host-configuration-source-repro-01` (identical source archive hash)
- `2026-09-16-host-configuration-final-01`

The final archive was packaged after regenerating SDK metadata from the source
archive. These hashes intentionally identify separate artifacts. No archive was
replaced. The framework SDK was upgraded through the generated opam repository
to `0.1.0~dev.42`; the runtime SDK remains `0.1.0~dev.7`. Installed toolchain
verification reports
`f29473c53f30c1c1c76e0eb330a57616ba4d5b6440294c6e1ad97266f5b27918`.

[release.json](release.json) records paths, installed package checksum records,
and compiler/tool versions. [source-inputs.json](source-inputs.json) and
[final-inputs.json](final-inputs.json) record archive member hashes. Every final
archive member was compared with the worktree. Pre-existing changes are preserved
and recorded separately in [baseline.patch](baseline.patch) and
[baseline-untracked.txt](baseline-untracked.txt). The preceding `.41` generated
SDK snapshot was also retained outside the worktree before regeneration.

Environment: OCaml 5.1.1, Xcode 26.1.1 (17B100), Swift 6.2.1, Python 3.13.3,
opam 2.3.0, Dune 3.23.1. Installed `doctor` and `toolchain verify iphoneos` pass.
The installed SDK source identity is recorded in
[installed-sdk-manifest.sexp](installed-sdk-manifest.sexp).

## Behavior and regression evidence

Focused tests first failed for unsupported schema 4, the removed initialization
flag, and the missing resolver command. The first real package acceptance also
exposed that Xcode's resolver and `-showBuildSettings` do not reject a missing
product. `-dry-run` is advertised but unsupported by Xcode's modern build system.
The implementation therefore builds an isolated SwiftUI validation application
with the selected products for both platforms in disposable staging. Valid
products compile; missing products fail before publishing the lock or host.

| Check | Result |
| --- | --- |
| `dune build @all @install` | Passed |
| `dune runtest` | Passed |
| OCaml CLI/library and native plan suites | 50 CLI/library tests and 3 native plan tests passed (11.639 and 3.450 seconds) |
| Python CLI ownership/build suite excluding remote graph matrix | 12 passed, 194.176 seconds |
| Documented Journal configuration generation | Passed; both IDs `com.logseq.journal`, all full entitlement dictionaries preserved |
| Python Xcode host suite | 12 passed, 729.420 seconds |
| Standalone repository configurations | All 12 examples synchronized, checked and built native objects without changing inputs (27.085 seconds) |
| Python release packager suite | 3 passed, 1.676 seconds |
| Installed prefix layout smoke | 1 passed, 94.222 seconds |
| Installed iOS SDK suite | 2 passed, 38.157 seconds |
| Source archive reproducibility | Two fresh output directories produced identical hashes |
| SDK repository reproducibility | `regenerate_sdk_repository.sh --check --source-archive ...` passed |
| Installed host configuration/remote graph matrix | 5 passed, 353.163 seconds; all profile/platform, transitive-lock and remote failure checks passed |

Local tests cover platform IDs and derived IDs in all profiles, profile-specific
XML/binary entitlements, nested values and literal substitutions, typed merge
conflicts, malformed/duplicate XML keys, unsafe and symlinked inputs, application
versus test-target ownership, invalid declarations, absent/existing host failure
snapshots, repeated synchronization, adoption, and read-only drift checks.
Snapshots compare file bytes and file/directory mtimes. Unrelated generated-root
files survive removal of the obsolete per-platform entitlement filenames.

The installed matrix invokes `/Users/rcmerci/.opam/bonsai-ui/bin/bonsai-swiftui`
in independent temporary consumers without `BONSAI_SWIFTUI_SOURCE_ROOT` or
`OCAMLPATH`. Generated projects reference installed framework assets and are
checked for absence of the framework worktree path. It exercises:

- `swift-collections` 1.1.4 / `OrderedCollections` on both platforms;
- `swift-algorithms` 1.2.0 / `Algorithms` on macOS only;
- the resolved transitive `swift-numerics` 1.1.1 pin;
- fresh-cache repeated resolution, locked profile/platform builds, real executed
  `OrderedSet` and `chunks` computations, and exact-to-full-revision replacement;
- missing transitive pins, nonexistent products and revisions, with complete
  before/after consumer snapshots and no partial publication.

The consumer lock was committed in a disposable Git repository as
`c4c312e`; [consumer-lock-commit.txt](consumer-lock-commit.txt) and
[committed-Package.resolved](committed-Package.resolved) retain the evidence.
Subsequent build preflights recreate both platform hosts in fresh staging
locations, disable repository caching and automatic package updates, and compare
all resolved pins against this application-owned lock before publishing output.

## Caller-dependent gates

The following are **blocked**, not passed:

- Production macOS signature entitlements and expanded Keychain groups for each
  profile: no caller-selected signing identity and team were provided.
- iOS provisioning, signed installation, device launch and upgrade behavior:
  no caller-selected provisioning/team/device inputs were provided.
- Effective Keychain access and historical session continuity after the iOS
  identity change: require the separately migrated consumer and its selected
  authentication provider; no provider/version/products were selected here.

Available machine certificates were not treated as the caller's selections.
`--signing-identity` now allows an explicit certificate through the existing CLI
build/run pipeline. Test hosts/runners remain separate and do not inherit
application Keychain groups or remote products. No forced reauthentication,
team-prefix substitution, consumer-source edits or signing identity invention
was used as an acceptance workaround.

The [public configuration example](../../swiftui-cli.md#application-identities-entitlements-and-swift-packages)
contains both finalized Journal identities, complete Debug/Profile and Release
entitlement inputs, package products/platforms, ownership, lock policy and signing
commands. This verifies CLI integration, not Journal's native dependency closure
or its authentication migration.

## Reproduction and audit

Run the installed matrix in the selected host opam environment:

```sh
opam exec --switch=bonsai-ui -- python3 docs/test-reports/2026-09-16-swiftui-host-configuration/run_installed_acceptance.py
```

[installed-host-tests.log](installed-host-tests.log) contains the resolved pins,
profile executions, unsigned iOS build and final result. Other logs in this
directory retain the commands' test summaries and release installation output.
The runner uses the repository's reusable test scenarios as test code; generated
consumers and runtime framework discovery use the installed packages exclusively.

[naming-audit.txt](naming-audit.txt) records the exact case-insensitive path and
content audit scope. It found no retired-backend names in the host configuration
deliverables. No obsolete backend dependency, config decoder, option alias or
compatibility implementation was retained.

No protected OCaml spec file or Dune file was changed by this implementation.
The pre-existing `dune-project` repository metadata edit is preserved in the
baseline record. The later source-commit/push rule remains applicable if these
changes are committed and pushed: regenerate the SDK from that pushed commit
and commit/push the generated SDK update separately. These local archive-based
installations do not replace that obligation.
