# Direct native builds for the SwiftUI CLI

The native builder now asks Dune for the configured complete-object target
directly. It no longer requires, generates, validates or repairs platform
aliases. The obsolete `sync-project` command and managed alias blocks are
removed from the tool and repository consumers. Existing application Dune
files remain application-owned, including during repeated initialization and
adoption. New complete-object stanzas have no Flutter embedding environment
gate.

The later [native CLI checkpoint](swiftui-cli.md) replaces the configuration,
generated application/host sources and `build`/`run`/`exec` orchestration with
SwiftUI/Xcode equivalents. Package names and installed SDK publication remain
unfinished. This earlier native-builder checkpoint alone does not establish
physical-iOS execution.

## Target and profile handling

The builder accepts a project-relative `.exe.o` path. It rejects absolute paths,
parent traversal, alias names and option-like targets before invoking Dune.
Dune parses target arguments as S-expressions, so each target is encoded as an
S-expression atom and passed as one process argument. This preserves filenames
containing spaces without shell interpolation.

Debug builds use Dune's `dev` profile. Profile and Release both use Dune's
`release` profile, while retaining separate build, staging and manifest paths.
The existing platform-specific contexts and deployment settings remain explicit.
Removing an alias does not remove complete-object verification: staging still
checks native ABI symbols, Mach-O architecture/platform/minimum and prohibited
host references before replacing the previous artifact.

## Verification

`bonsai_swiftui_tool/test/native_plan_tests.ml` executes real Dune commands in
temporary project paths containing spaces. An ordinary OCaml executable with
`(modes (native object))` proves direct construction in all three profiles,
observes the actual Dune profile, preserves the object on unchanged rebuilds,
and changes the object after an OCaml source edit. No managed aliases or
embedding flag are supplied.

A second fixture builds and stages the actual SwiftUI Counter complete object
through `Build_system.build_native`, using an object filename containing spaces.
It uses the real opam, Dune and native-object verifier, compares the verified
artifact with the actual Counter object, and checks that a repeated build
preserves both the staged file and application Dune source. Target validation
and scaffold ownership are also covered.

Initial tests reproduced the missing alias/preflight failures and obsolete
alias injection (`/tmp/swiftui-cli-native-direct-red-final.log` and
`/tmp/swiftui-cli-native-scaffold-red.log`). Removing the alias path exposed
Dune's unencoded space-containing target failure
(`/tmp/swiftui-cli-native-direct-green.log`); S-expression encoding fixes it.
A subsequent `dune exec` invocation omitted declared test dependencies, which
was corrected by running the Dune test alias. That harness setup error is not
reported as a production failure. The complete tool test alias passes all
three native integration tests and 86 existing CLI/library tests
(`/tmp/swiftui-cli-native-suite.log`).

The old alias-generation, alias-repair and alias-only validation tests are
replaced by actual direct builds and unchanged-source checks. Existing SDK,
dependency-closure, artifact, locking, process-status and signal tests remain.
The broader Flutter-era shell CI contract still requires its full migration;
its obsolete alias assertions have been removed, without claiming that the
remaining CI contract passes.

The final repository `@all @runtest @fmt` gate passes
(`/tmp/swiftui-cli-native-all.log`). Counter also builds directly in the
isolated physical-iOS Dune workspace after the alias removal
(`/tmp/swiftui-cli-native-ios-direct.log`); its complete object passes actual
IOS/arm64/minimum 18.0 and SwiftUI ABI verification
(`/tmp/swiftui-cli-native-ios-audit.log`). This uses the rebuilt isolated
cross-toolchain, not the CLI's still-unmigrated installed-SDK discovery path.
