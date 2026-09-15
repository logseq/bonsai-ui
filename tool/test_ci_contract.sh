#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

fail() {
  printf '%s\n' "ci contract failure: $1" >&2
  exit 1
}

test ! -e "$repository_root/flutter" || fail "obsolete Flutter backend exists at repository root"

# Reject an incomplete published SDK before running compiler and Xcode checks.
"$repository_root/tool/test_ios_sdk_layering.sh"
"$repository_root/tool/test_ios_deployment_target_contract.sh"
"$repository_root/tool/test_network_ios_contract.sh"

require_file() {
  test -f "$1" || fail "missing $1"
}

require_text() {
  haystack=$1
  needle=$2
  label=$3
  printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null ||
    fail "$label does not contain: $needle"
}

reject_text() {
  haystack=$1
  needle=$2
  label=$3
  if printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null; then
    fail "$label contains forbidden text: $needle"
  fi
}

reject_pattern() {
  haystack=$1
  pattern=$2
  label=$3
  if printf '%s' "$haystack" | grep -Ei -- "$pattern" >/dev/null; then
    fail "$label contains forbidden pattern: $pattern"
  fi
}

require_exact_installed_version() {
  package=$1
  expected=$2
  actual=$(opam list --installed --short --columns=version "$package" 2>/dev/null) ||
    fail "$package is not installed"
  test "$actual" = "$expected" ||
    fail "$package version is $actual, expected $expected"
}

require_opam_release_source() {
  package=$1
  version=$2
  metadata=$(opam show --raw "$package.$version" 2>/dev/null) ||
    fail "unable to read opam metadata for $package.$version"
  require_text \
    "$metadata" \
    "https://github.com/janestreet/$package/archive/refs/tags/$version.tar.gz" \
    "$package source metadata"
}

require_sha256() {
  path=$1
  expected=$2
  actual=$(shasum -a 256 "$path" | awk '{ print $1 }')
  test "$actual" = "$expected" ||
    fail "$path SHA-256 is $actual, expected $expected"
}

assert_consumer_root() {
  root=examples/$1
  package=$2
  feature=${3:-}
  for path in "$root/dune-project" "$root/.ocamlformat" \
    "$root/bonsai-swiftui.sexp" "$root/$package.opam" \
    "$root/$package.opam.locked" "$root/swift/App.swift" \
    "$root/ocaml/native_embed.ml"; do
    require_file "$path"
  done
  config=$(cat "$root/bonsai-swiftui.sexp")
  require_text "$config" '(lang 3)' "$root config"
  require_text "$config" "(name $1)" "$root application identity"
  require_text "$config" '(native_target ocaml/native_embed.exe.o)' "$root config"
  require_text "$config" '(ios (minimum_version 18.0) (architectures arm64))' "$root physical iOS target"
  require_text "$config" '(macos (minimum_version 26.0) (architectures arm64))' "$root macOS target"
  require_text "$config" "(features$feature)" "$root capabilities"
  test ! -e "$root/bonsai-flutter.sexp" || fail "$root contains an obsolete configuration"
  test ! -e "$root/flutter" || fail "$root contains an obsolete host"
  (cd "$root" && BONSAI_SWIFTUI_SOURCE_ROOT="$repository_root" \
    "$repository_root/_build/default/bonsai_swiftui_tool/bin/main.exe" sync-host --check) || \
    fail "$root generated SwiftUI host is stale or invalid"
}
test "$(ocamlc -version)" = "5.1.1" ||
  fail "OCaml version is $(ocamlc -version), expected 5.1.1"

require_exact_installed_version base v0.17.3
require_exact_installed_version bonsai v0.17.0
require_exact_installed_version core v0.17.2
require_exact_installed_version incr_dom v0.17.0
require_exact_installed_version incremental v0.17.0
require_exact_installed_version sqlite3 5.4.0
require_exact_installed_version tls 2.1.2
require_exact_installed_version tls-eio 2.1.2
require_exact_installed_version ca-certs-nss 3.126
require_exact_installed_version httpun 0.2.0
require_exact_installed_version httpun-eio 0.2.0
require_exact_installed_version httpun-ws 0.2.0
require_exact_installed_version gluten-eio 0.5.2
require_exact_installed_version virtual_dom v0.17.0
for package in bonsai incr_dom incremental virtual_dom; do
  require_opam_release_source "$package" v0.17.0
done
require_opam_release_source core v0.17.2
require_opam_release_source base v0.17.3

unexpected_release_train_versions=$(
  opam list --installed --short --columns=name,version |
    awk \
      '$2 ~ /^v0[.]/ &&
       $1 != "ocaml-compiler-libs" &&
       $2 !~ /^v0[.]17([.-]|$)/ { print }'
)
test -z "$unexpected_release_train_versions" ||
  fail "installed Jane Street release-train packages are not v0.17.x:
$unexpected_release_train_versions"

upstream_baseline=$(cat docs/upstream-baseline.md)
for version in 'OCaml | 5.1.1' 'Bonsai | v0.17.0' 'Core | v0.17.2' 'Base | v0.17.3'; do
  require_text "$upstream_baseline" "$version" "upstream baseline"
done

patch_files=$(
  find . \
    -path './.git' -prune -o \
    -path './_build' -prune -o \
    -path './_build-v017' -prune -o \
    -type f \( -name '*.patch' -o -name '*.diff' \) -print |
    LC_ALL=C sort
)
. "$repository_root/tool/ios/sdk_repository.lock"
runtime_patch_root="./tool/ios/opam-repository/0.1.0/packages/bonsai_swiftui_ios_runtime_sdk/bonsai_swiftui_ios_runtime_sdk.$SDK_RUNTIME_PACKAGE_VERSION/files/patches"
expected_patch_files="$runtime_patch_root/base-host-generator.patch
$runtime_patch_root/datascript-system-sqlite.patch
$runtime_patch_root/eio-posix-darwin-protocol-zero.patch
$runtime_patch_root/eio-posix-darwin-socktype-hints.patch
$runtime_patch_root/jst-config-host-discover.patch
$runtime_patch_root/mirage-crypto-rng-apple-entropy.patch
./tool/ios/opam-repository/0.1.0/packages/ocaml-ios64/ocaml-ios64.5.1.1/files/ocamlmklib-failsafe.patch
./tool/ios/opam-repository/0.1.0/packages/ocaml-ios64/ocaml-ios64.5.1.1/files/sys.patch
./vendor/opam-ios/ocaml-ios64.5.1.1/files/ocamlmklib-failsafe.patch
./vendor/patches/basement-macos.patch
./vendor/patches/ios/base-host-generator.patch
./vendor/patches/ios/datascript-system-sqlite.patch
./vendor/patches/ios/eio-posix-darwin-protocol-zero.patch
./vendor/patches/ios/eio-posix-darwin-socktype-hints.patch
./vendor/patches/ios/jst-config-host-discover.patch
./vendor/patches/ios/mirage-crypto-rng-apple-entropy.patch"
test "$patch_files" = "$expected_patch_files" ||
  fail "upstream patch allowlist changed:
$patch_files"
require_sha256 \
  vendor/opam-ios/ocaml-ios64.5.1.1/files/ocamlmklib-failsafe.patch \
  2e087a1cccc6514af07559a688ffc17c651a2bb5b2a67d115cc28051f2e89767
require_sha256 \
  vendor/patches/basement-macos.patch \
  1c97bd1e3ad6eeefe30fce6a81a06ed4685fdef95efb53e67cd9389b6201327b
require_sha256 \
  vendor/patches/ios/base-host-generator.patch \
  e919f3c5ec1e6a546a6e499ed262d309055fd0c856d7c216d3609b7d64ca47b5
require_sha256 \
  vendor/patches/ios/datascript-system-sqlite.patch \
  25671b3a84772c8a6b6c9fae3c8c2e0efa1b7d88c9ca2edb274b2ce40de481a4
require_sha256 \
  vendor/patches/ios/eio-posix-darwin-protocol-zero.patch \
  b6a158f56db6bc1c1e19ad2412625f2d7941a5004274e3a45fe58f6c89e5b963
require_sha256 \
  vendor/patches/ios/eio-posix-darwin-socktype-hints.patch \
  8b5eb1ecc716afeac54f6ebc0792f14df5107dbdac5ebb81da3ea0a31e187e17
require_sha256 \
  vendor/patches/ios/jst-config-host-discover.patch \
  d1d9fbbf8df8f8e315fad1a834352a5a80e948e62012a104d5362461f195df78
require_sha256 \
  vendor/patches/ios/mirage-crypto-rng-apple-entropy.patch \
  898002b98bddd3a6f212441a7bba32a45ad26f0cb40ab175b2fe0f762e4adea2

if find vendor \
  -type d \
  \( \
    -name bonsai -o \
    -name incremental -o \
    -name incr_dom -o \
    -name flutter \
  \) |
  grep . >/dev/null; then
  fail "vendor contains a forbidden upstream source overlay"
fi

dependency_control_text=$(cat \
  bonsai_swiftui.opam \
  bonsai_swiftui_test.opam \
  dune-project \
  tool/ci/*.sh \
  tool/ios/*.sh)
require_text \
  "$dependency_control_text" \
  'sqlite3' \
  "dependency controls"
require_text \
  "$dependency_control_text" \
  'eio_posix' \
  "dependency controls"
for dependency in httpun-eio tls-eio ca-certs-nss; do
  reject_text \
    "$(cat bonsai_swiftui.opam)" \
    "$dependency" \
    "core package dependency controls"
done
for dependency in piaf eio-ssl cohttp-eio openssl-sys-ios; do
  reject_text \
    "$(cat bonsai_swiftui.opam examples/network/bonsai_swiftui_network_example.opam dune-project)" \
    "$dependency" \
    "network dependency controls"
done
if find ocaml -type f -print | grep -F '/worker_http/' >/dev/null; then
  fail "framework still contains the legacy worker_http library"
fi

dune_package_metadata() {
  awk -v RS='' -v package_name="$1" \
    'index($0, "(name " package_name ")") { print; exit }' \
    dune-project
}

bonsai_swiftui_dune_package=$(dune_package_metadata bonsai_swiftui)
bonsai_swiftui_test_dune_package=$(dune_package_metadata bonsai_swiftui_test)
reject_text \
  "$bonsai_swiftui_dune_package" \
  '(sqlite3 ' \
  "bonsai_swiftui dune package dependencies"
require_text \
  "$bonsai_swiftui_test_dune_package" \
  '(sqlite3 (= 5.4.0))' \
  "bonsai_swiftui_test dune package dependencies"
reject_text \
  "$(cat bonsai_swiftui.opam)" \
  '"sqlite3"' \
  "bonsai_swiftui opam dependencies"
require_text \
  "$(cat bonsai_swiftui_test.opam)" \
  '"sqlite3" {= "5.4.0"}' \
  "bonsai_swiftui_test opam dependencies"
require_text \
  "$(cat vendor/opam-ios/runtime-closure.lock)" \
  'sqlite3|5.4.0|host-package|Host_only|opam|https://github.com/mmottl/sqlite3-ocaml/releases/download/5.4.0/sqlite3-5.4.0.tbz|f0069532f78ac24f16d79262af01434952d0481f8bf80ae541dff4a56cc4e9ff|-|-' \
  "iOS runtime closure lock"
require_text \
  "$(cat tool/ios/toolchain.lock)" \
  "SQLITE3_VERSION='5.4.0'" \
  "iOS toolchain lock"
require_text \
  "$(cat tool/ios/toolchain.lock)" \
  "EIO_VERSION='1.2'" \
  "iOS Eio toolchain lock"
require_text \
  "$(cat vendor/opam-ios/runtime-closure.lock)" \
  'eio_posix|1.2|target-package|Filesystem|dune|https://github.com/ocaml-multicore/eio/releases/download/v1.2/eio-1.2.tbz|3792e912bd8d494bb2e38f73081825e4d212b1970cf2c1f1b2966caa9fd6bc40|eio_posix|' \
  "iOS Eio runtime closure lock"
ios_closure_verifier=$(cat tool/ios/verify_runtime_closure.sh)
require_text \
  "$ios_closure_verifier" \
  'metadata package-count' \
  "lock-derived iOS closure package count"
require_text \
  "$ios_closure_verifier" \
  'metadata component-count' \
  "lock-derived iOS closure component count"
require_text "$ios_closure_verifier" 'System_sqlite)' "iOS SQLite capability gate"
require_text "$ios_closure_verifier" 'Filesystem)' "iOS filesystem capability gate"
reject_text \
  "$(cat tool/ios/setup_host_dependencies.sh)" \
  'sqlite3.$SQLITE3_VERSION' \
  "application-owned iOS host SQLite dependency setup"
require_text \
  "$(cat tool/ios/setup_host_dependencies.sh)" \
  'eio_posix.$EIO_VERSION' \
  "iOS host Eio dependency setup"
runtime_events_installer=$(cat \
  vendor/opam-ios/ocaml-ios64.5.1.1/files/install.sh)
require_text \
  "$runtime_events_installer" \
  'runtime_events' \
  "iOS OCaml 5 runtime-events metadata staging"
require_text \
  "$runtime_events_installer" \
  'ios-sysroot/lib/ocaml/runtime_events/' \
  "iOS OCaml 5 runtime-events target archive staging"
ios_toolchain_setup=$(cat tool/ios/setup_toolchain.sh)
require_text \
  "$ios_toolchain_setup" \
  'recipe_identity="$OCAML_IOS_RECIPE_REVISION-$IOS_DEPLOYMENT_TARGET"' \
  "iOS toolchain recipe identity"
require_text \
  "$ios_toolchain_setup" \
  'conf-ios.4' \
  "iOS deployment-target toolchain reinstall"
require_text \
  "$ios_toolchain_setup" \
  'miphoneos-version-min=$IOS_DEPLOYMENT_TARGET' \
  "iOS cross-compiler deployment-target verification"
ios_metadata_stager=$(cat tool/ios/stage_host_metadata.sh)
require_text \
  "$ios_metadata_stager" \
  'target_standard_library="$target_lib/ocaml"' \
  "iOS target standard-library staging"
require_text \
  "$ios_metadata_stager" \
  "-name '*.cmxa'" \
  "iOS target standard-library native archives"
ios_runtime_package_builder=$(cat tool/ios/build_runtime_package.sh)
require_text \
  "$ios_runtime_package_builder" \
  'libsqlite3_stubs.a' \
  "iOS target SQLite stubs"
require_text \
  "$ios_runtime_package_builder" \
  '-lsqlite3' \
  "iOS target system SQLite dependency"
require_text \
  "$ios_runtime_package_builder" \
  'test ! -f "$target_package_root/libsqlite3.a"' \
  "iOS bundled SQLite rejection"
reject_pattern \
  "$dependency_control_text" \
  'opam[[:space:]]+pin[[:space:]]+add[[:space:]]+(bonsai|incremental|incr_dom)' \
  "dependency controls"
reject_pattern \
  "$dependency_control_text" \
  'file://[^[:space:]]*(bonsai|incremental|incr_dom)' \
  "dependency controls"

runtime_source=$(cat ocaml/runtime/*.ml ocaml/runtime/*.mli ocaml/ffi/*.ml ocaml/ffi/*.mli \
  native/src/*.c swift/BonsaiSwiftUI/Sources/*.swift)
reject_pattern "$runtime_source" 'Time_source[.]Private|Obj[.]magic' "runtime source"

dry_run_target() {
  target=$1
  if ! output=$(make -n "$target" 2>&1); then
    printf '%s\n' "$output" >&2
    fail "make target $target is unavailable"
  fi
  printf '%s' "$output"
}

makefile=$(cat Makefile)
require_text "$makefile" 'BONSAI_SWIFTUI :=' "Makefile local CLI"
require_text "$makefile" 'export BONSAI_SWIFTUI_SOURCE_ROOT :=' "Makefile source assets"
require_text "$makefile" 'ci-install-consumers: ci-install-framework' "consumer installation"
require_text "$makefile" 'ci-swift: ci-install-consumers swift-test protocol-fixtures-check' "Swift CI"
require_text "$makefile" 'ci-macos: ci-ocaml ci-swift' "macOS CI"
require_text "$makefile" 'ci-ios: ci-install-ios-toolchain' "physical iOS CI"
reject_pattern "$makefile" 'flutter/|dart (run|test|analyze)|flutter (test|analyze|build)' "Makefile obsolete backend commands"
for obsolete in dart-test flutter-test dart-analyze native-analyze ci-flutter; do
  if make -n "$obsolete" >/dev/null 2>&1; then
    fail "obsolete Make target is still available: $obsolete"
  fi
done

toolchain_commands=$(dry_run_target ci-install-ios-toolchain)
require_text "$toolchain_commands" 'toolchain install iphoneos' "iPhoneOS compiler installation"
require_text "$toolchain_commands" 'toolchain verify iphoneos' "iPhoneOS compiler verification"
require_text "$(dry_run_target ios-sdk-repository)" 'tool/ios/regenerate_sdk_repository.sh --write' "SDK generation"

ocaml_commands=$(dry_run_target ci-ocaml)
for command in 'opam install . --deps-only --with-test' 'dune build @all' 'dune runtest' \
  'dune build @fmt' 'generate.exe -- --check' 'generate_fixtures.exe -- --check' \
  'dune build --profile release ocaml/bench/runtime_bench.exe'; do
  require_text "$ocaml_commands" "$command" "ci-ocaml"
done

swift_commands=$(dry_run_target ci-swift)
for command in 'sh tool/test_native_runtime.sh' 'python3 tool/run_swift_tests.py' \
  'python3 tool/test_swiftui_xcode_host.py' 'python3 tool/test_swift_platforms.py' \
  'python3 tool/generate_input_fixtures.py --check' 'python3 native/test/test_mail_window.py' \
  'sync-host --check'; do
  require_text "$swift_commands" "$command" "ci-swift"
done
fixture_commands=$(dry_run_target protocol-fixtures-check)
require_text "$fixture_commands" 'generate_fixtures.exe -- --check' "OCaml fixtures"
require_text "$fixture_commands" 'python3 tool/generate_input_fixtures.py --check' "Swift fixtures"
integration_commands=$(dry_run_target integration-test)
for command in test_swiftui_cli.py test_swiftui_doctor.py test_swiftui_example_cli.py; do
  require_text "$integration_commands" "$command" "native CLI integration"
done

for platform in macos ios; do
  commands=$(dry_run_target "ci-$platform")
  require_text "$commands" 'for consumer in clock counter gallery host_effects host_navigation mail navigation network note sqlite_worker text_input todo' "ci-$platform complete example matrix"
  require_text "$commands" 'for profile in debug profile release' "ci-$platform profile matrix"
  require_text "$commands" "build $platform --profile" "ci-$platform native build"
  reject_pattern "$commands" '(^|[[:space:]])flutter/' "ci-$platform obsolete host"
  reject_text "$commands" 'simulator' "ci-$platform destination"
  if test "$platform" = ios; then
    require_text "$commands" '--no-codesign' "ci-ios unsigned builds"
  fi
done

native_commands=$(make -n native-object EXAMPLE=mail)
require_text "$native_commands" 'cd examples/mail && ' "native example selection"
require_text "$native_commands" 'build macos --profile debug' "native example build"
device_commands=$(dry_run_target ci-ios-device)
require_text "$device_commands" 'IOS_DEVICE_ID is required' "explicit physical-device selection"
require_text "$device_commands" 'IOS_DEVELOPMENT_TEAM is required' "explicit signing team"
require_text "$makefile" 'ios_device_preflight.sh "$(IOS_DEVICE_ID)"' "selected-device preflight"
require_text "$device_commands" 'run ios --profile debug --device' "physical-device launch"
reject_pattern "$device_commands" '(^|[[:space:]])flutter/' "physical-device native host"

xcode_generator=$(cat tool/swiftui_xcode_host.py)
require_text "$xcode_generator" 'Security' "Apple native security linkage"
require_text "$xcode_generator" '^_sqlite3_[A-Za-z0-9_]+$' "native-object SQLite linkage selection"
require_text "$xcode_generator" 'runtime-system-libraries.rsp' "per-target native system-library response"
require_text "$(cat Package.swift)" '.copy("PrivacyInfo.xcprivacy")' "runtime privacy resource"
require_file swift/BonsaiSwiftUI/Sources/PrivacyInfo.xcprivacy

network_manifest=$(cat examples/network/bonsai_swiftui_network_example.opam)
for dependency in '"tls" {= "2.1.2"}' '"tls-eio" {= "2.1.2"}' \
  '"ca-certs-nss" {= "3.126"}' '"httpun-eio" {= "0.2.0"}' '"httpun-ws" {= "0.2.0"}'; do
  require_text "$network_manifest" "$dependency" "network dependencies"
done
network_source=$(cat examples/network/ocaml/*.ml examples/network/swift/*.swift)
reject_pattern "$network_source" 'allow_insecure|certificate[^[:space:]]*bypass|badCertificateCallback' "network source"
reject_pattern "$(cat examples/network/swift/*.swift)" 'URLSession|NWConnection|WebSocket' "OCaml-owned networking"
reject_text "$(cat examples/mail/ocaml/dune)" 'bonsai_swiftui_trace_' "Mail closure"
reject_text "$(cat examples/mail/ocaml/dune)" 'native_embed_debug' "Mail target"
reject_text "$(cat examples/mail/ocaml/dune)" 'native_embed_release' "Mail target"

readme=$(cat README.md)
require_text "$readme" 'bonsai-swiftui' "native CLI documentation"
require_text "$readme" 'make ci-swift' "native CI documentation"
require_text "$(cat docs/packaging.md)" 'CBonsaiSwiftUI' "native packaging documentation"

ffi_dune=$(cat ocaml/ffi/dune)
for example_library in \
  bonsai_swiftui_clock_example \
  bonsai_swiftui_counter_example \
  bonsai_swiftui_gallery \
  bonsai_swiftui_host_effects_example \
  bonsai_swiftui_host_navigation_example \
  bonsai_swiftui_mail_example \
  bonsai_swiftui_navigation_example \
  bonsai_swiftui_sqlite_worker_example \
  bonsai_swiftui_text_input_example \
  bonsai_swiftui_todo_example
do
  reject_text "$ffi_dune" "$example_library" "generic FFI library"
done

sanitizer_commands=$(dry_run_target ci-sanitizers)
require_text "$sanitizer_commands" 'native/src/bonsai_swiftui_native.c' "native bridge sanitizer"
require_text "$sanitizer_commands" 'native/test/native_bridge_test.c' "native ownership sanitizer coverage"
require_text "$sanitizer_commands" '_build/ci/native_bridge_sanitized' "sanitized test execution"
sanitizer_override=$(make -n ci-sanitizers SANITIZERS=address,undefined)
require_text "$sanitizer_override" '-fsanitize=address,undefined' "explicit sanitizer selection"

require_file tool/ci/install_ios_signing.sh
require_file tool/ci/ios_device_preflight.sh
require_file tool/ios/sdk_repository.lock
require_file tool/ios/regenerate_sdk_repository.sh
require_text "$(cat tool/ci/ios_device_preflight.sh)" '.result.passcodeRequired == false' "currently unlocked physical device"
require_text "$(cat tool/ci/install_ios_signing.sh)" 'Library/Developer/Xcode/UserData/Provisioning Profiles' "signing profile installation"


dune build bonsai_swiftui_tool/bin/main.exe
assert_consumer_root clock bonsai_swiftui_clock_example
assert_consumer_root counter bonsai_swiftui_counter_example
assert_consumer_root gallery bonsai_swiftui_gallery
assert_consumer_root host_effects bonsai_swiftui_host_effects_example
assert_consumer_root host_navigation bonsai_swiftui_host_navigation_example
assert_consumer_root mail bonsai_swiftui_mail_example
assert_consumer_root navigation bonsai_swiftui_navigation_example
assert_consumer_root note bonsai_swiftui_note_example
assert_consumer_root network bonsai_swiftui_network_example ' network'
assert_consumer_root sqlite_worker bonsai_swiftui_sqlite_worker_example ' sqlite'
assert_consumer_root text_input bonsai_swiftui_text_input_example
assert_consumer_root todo bonsai_swiftui_todo_example

printf '%s\n' "CI contract tests passed"
