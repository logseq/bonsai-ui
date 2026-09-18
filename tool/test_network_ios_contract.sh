#!/bin/sh

set -u

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd)
cd "$repository_root"

failures=0

fail() {
  printf '%s\n' "network iOS contract failure: $1" >&2
  failures=$((failures + 1))
}

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

reject_pattern() {
  haystack=$1
  pattern=$2
  label=$3
  if printf '%s' "$haystack" | grep -Ei -- "$pattern" >/dev/null; then
    fail "$label contains forbidden pattern: $pattern"
  fi
}

reject_text() {
  haystack=$1
  needle=$2
  label=$3
  if printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null; then
    fail "$label contains forbidden text: $needle"
  fi
}

for path in \
  examples/network/swift/App.swift \
  examples/network/apple/BonsaiNetwork.xcodeproj/project.pbxproj \
  examples/network/apple/BonsaiNetwork.xcodeproj/xcshareddata/xcschemes/BonsaiNetwork-iOS.xcscheme \
  examples/network/apple/BonsaiNetwork.xcodeproj/xcshareddata/xcschemes/BonsaiNetwork-macOS.xcscheme \
  examples/network/apple/Info-iOS.plist \
  examples/network/apple/Info-macOS.plist \
  examples/network/apple/iOS.entitlements \
  examples/network/apple/macOS.entitlements \
  swift/BonsaiSwiftUI/Sources/PrivacyInfo.xcprivacy
do
  require_file "$path"
done

network_config=$(cat examples/network/bonsai-swiftui.sexp 2>/dev/null || true)
require_text "$network_config" '(lang 3)' "network consumer config"
require_text "$network_config" '(features network)' "network consumer config"
require_text "$network_config" '(ios (minimum_version 26.0) (architectures arm64))' "physical iOS config"
require_text "$network_config" '(macos (minimum_version 26.0) (architectures arm64))' "macOS config"
require_file examples/network/bonsai_swiftui_network_example.opam.locked

if dune build bonsai_swiftui_tool/bin/main.exe; then
  (cd examples/network && BONSAI_SWIFTUI_SOURCE_ROOT="$repository_root" \
    "$repository_root/_build/default/bonsai_swiftui_tool/bin/main.exe" sync-host --check) ||
    fail "the Network Xcode host is stale or invalid"
else
  fail "the native CLI could not be built"
fi
python3 tool/test_swiftui_xcode_host.py XcodeHostTests.test_generation_and_apple_destination_settings ||
  fail "the generated Xcode destinations do not satisfy the Apple platform contract"

artifact_stager=$(cat bonsai_swiftui_tool/lib/artifact.ml)
require_text "$artifact_stager" '"pkg-config"' "macOS Network GMP discovery"
require_text "$artifact_stager" '"libgmp.a"' "macOS Network static GMP staging"
require_text "$artifact_stager" '"clang"' "macOS Network relocatable link"
require_text \
  "$artifact_stager" \
  'The network complete object still contains unresolved GMP symbols' \
  "macOS Network GMP verification"

ios_commands=$(make -n ci-ios)
require_text "$ios_commands" \
  'for consumer in clock counter gallery host_effects host_navigation mail navigation network note sqlite_worker text_input todo' \
  "ci-ios complete example matrix including Network"
require_text "$ios_commands" 'for profile in debug profile release' "ci-ios build profiles"
require_text "$ios_commands" 'build ios --profile "$profile" --no-codesign' "ci-ios native build"
reject_pattern "$ios_commands" '(^|[[:space:]])flutter/' "ci-ios obsolete backend paths"
closure_lock=$(cat vendor/opam-ios/runtime-closure.lock)
require_file vendor/opam-ios/supported-closure.lock
supported_closure_lock=$(cat vendor/opam-ios/supported-closure.lock)
require_text \
  "$supported_closure_lock" \
  'digestif,digestif.c' \
  "iOS Digestif default implementation components"
require_text \
  "$supported_closure_lock" \
  'mirage-ptime,mirage-ptime.unix' \
  "iOS Mirage ptime default implementation components"
require_text \
  "$supported_closure_lock" \
  '# metadata.features=core,network,sqlite' \
  "iOS supported closure lock"
for package in ca-certs-nss httpun-eio httpun-ws tls-eio x509 zarith; do
  require_text \
    "$supported_closure_lock" \
    "$package|" \
    "iOS supported Network closure"
done
closure_rows=$(printf '%s\n' "$closure_lock" | awk -F '|' '!/^#/ && NF { count++ } END { print count + 0 }')
target_rows=$(printf '%s\n' "$closure_lock" | awk -F '|' '$3 == "target-package" { count++ } END { print count + 0 }')
host_rows=$(printf '%s\n' "$closure_lock" | awk -F '|' '$3 == "host-package" { count++ } END { print count + 0 }')
target_build_rows=$(printf '%s\n' "$closure_lock" | awk -F '|' '!/^#/ && NF && $3 == "target-build" { count++ } END { print count + 0 }')
component_count=$(printf '%s\n' "$closure_lock" | awk -F '|' '$3 == "target-package" { count += split($8, components, ",") } END { print count + 0 }')

metadata_value() {
  printf '%s\n' "$closure_lock" |
    sed -n "s/^# metadata\.$1=//p" |
    sed -n '1p'
}

test "$(metadata_value package-count)" = "$closure_rows" ||
  fail "iOS closure package count is not derived from lock rows"
test "$(metadata_value target-package-count)" = "$target_rows" ||
  fail "iOS closure target-package count is not derived from lock rows"
test "$(metadata_value host-package-count)" = "$host_rows" ||
  fail "iOS closure host-package count is not derived from lock rows"
test "$(metadata_value target-build-count)" = "$target_build_rows" ||
  fail "iOS closure target-build count is not derived from lock rows"
test "$(metadata_value component-count)" = "$component_count" ||
  fail "iOS closure component count is not derived from lock rows"

require_text "$closure_lock" '# metadata.format=bonsai-swiftui-ios-closure-v2' "iOS runtime closure lock"
require_text "$closure_lock" '# metadata.features=core,sqlite' "fixture closure features"
reject_pattern \
  "$closure_lock" \
  '(^|[|])(openssl|ssl|eio-ssl|piaf|cohttp-eio)([|.-]|$)' \
  "iOS runtime closure lock"

closure_verifier=$(cat tool/ios/verify_runtime_closure.sh)
for metadata_key in \
  package-count \
  target-package-count \
  host-package-count \
  target-build-count \
  component-count
do
  require_text "$closure_verifier" "metadata $metadata_key" "lock-derived iOS closure metadata"
done
reject_pattern "$closure_verifier" '= (88|90|128)([^0-9]|$)' "iOS closure verifier"

capability_lock=$(cat tool/ios/closure_capabilities.lock)
for recipe in \
  'ca-certs-nss|Network|network|dune-ios-network' \
  'httpun-eio|Network|network|dune-ios-network' \
  'httpun-ws|Network|network|dune-ios-network' \
  'mirage-crypto-rng.unix|Entropy|network|dune-ios-apple-entropy' \
  'tls-eio|Network|network|dune-ios-network' \
  'x509|Network|network|dune-ios-network'
do
  require_text "$capability_lock" "$recipe" "network cross-build capability lock"
done

resolver=$(cat tool/ios/resolve_application_closure.sh)
require_text \
  "$resolver" \
  'BONSAI_SWIFTUI_DUNE_CLOSURE_HELPER' \
  "application semantic closure roots"
require_text \
  "$resolver" \
  'application opam metadata has no dependency roots' \
  "application package metadata"
reject_pattern "$resolver" 'network_root|network roots' "application closure resolver"
require_text \
  "$resolver" \
  'build_mechanism=zarith' \
  "Zarith application closure build mechanism"
require_text \
  "$resolver" \
  'ocaml-ios64' \
  "application closure compiler-package exclusion"

network_dune=$(cat examples/network/ocaml/dune)
network_opam=$(cat examples/network/bonsai_swiftui_network_example.opam 2>/dev/null || true)
for library in ca-certs-nss httpun-eio httpun-ws mirage-crypto-rng.unix tls-eio x509; do
  require_text "$network_dune" "$library" "network application Dune roots"
done
for package in ca-certs-nss httpun-eio httpun-ws mirage-crypto-rng tls-eio x509; do
  require_text "$network_opam" "\"$package\" {=" "network application pinned opam roots"
done

host_setup=$(cat tool/ios/setup_host_dependencies.sh)
for dependency in \
  'ca-certs-nss.$CA_CERTS_NSS_VERSION' \
  'gluten-eio.$GLUTEN_EIO_VERSION' \
  'httpun-eio.$HTTPUN_EIO_VERSION' \
  'httpun-ws.$HTTPUN_WS_VERSION' \
  'mirage-crypto-rng.$MIRAGE_CRYPTO_VERSION' \
  'tls-eio.$TLS_VERSION' \
  'x509.$X509_VERSION'
do
  require_text "$host_setup" "$dependency" "iOS host network dependency setup"
done
reject_pattern \
  "$host_setup" \
  '(openssl|ssl|eio-ssl|piaf|cohttp-eio)' \
  "iOS host dependency setup"

toolchain_lock=$(cat tool/ios/toolchain.lock)
for pin in \
  "CA_CERTS_NSS_VERSION='3.126'" \
  "GLUTEN_EIO_VERSION='0.5.2'" \
  "HTTPUN_EIO_VERSION='0.2.0'" \
  "HTTPUN_WS_VERSION='0.2.0'" \
  "MIRAGE_CRYPTO_VERSION='2.2.0'" \
  "TLS_VERSION='2.1.2'" \
  "X509_VERSION='1.1.1'"
do
  require_text "$toolchain_lock" "$pin" "iOS network toolchain lock"
done

cross_compiler_opam=$(cat tool/ios/opam-repository/0.1.0/packages/ocaml-ios64/ocaml-ios64.5.1.1/opam)
require_text \
  "$cross_compiler_opam" \
  '"ocamlmklib-failsafe.patch" "sha256=b51bd717117618cca4b47960769d336a2bb0922176e627c24e453b507b75823e"' \
  "iOS cross-compiler patch checksum"
sdk_repository_lock=$(cat tool/ios/opam-repository/0.1.0/repository.sexp)
require_text \
  "$sdk_repository_lock" \
  'https://github.com/ocaml/opam-repository.git' \
  "iOS default opam repository"
require_text \
  "$sdk_repository_lock" \
  '9fdd0666a192f1896963cf446f37f0c691bbd3db' \
  "iOS default opam repository commit"

runtime_builder=$(cat tool/ios/build_runtime_package.sh)
require_text "$runtime_builder" 'gmp-sys-ios' "iOS static GMP target recipe"
require_text \
  "$runtime_builder" \
  'SDK_PACKAGE_WORK_ROOT/dependencies/gmp' \
  "iOS writable static GMP staging"
reject_pattern \
  "$runtime_builder" \
  '\$switch_prefix/ios-deps' \
  "iOS immutable switch prefix"
require_text "$runtime_builder" 'zarith' "iOS Zarith target recipe"
require_text \
  "$runtime_builder" \
  'printf '\''%s\n'\'' zarith' \
  "iOS Zarith build-mechanism detection"
python3 tool/test_ios_virtual_library.py ||
  fail "the installed virtual library is missing concrete physical-iOS modules"
python3 tool/test_ios_closure_artifacts.py ||
  fail "the closure verifier accepted invalid or missing native artifacts"
require_text \
  "$runtime_builder" \
  'virtual-interface-only' \
  "iOS virtual-library interface verification"
require_file vendor/patches/ios/mirage-crypto-rng-apple-entropy.patch
require_text \
  "$runtime_builder" \
  'mirage-crypto-rng-apple-entropy.patch' \
  "iOS mirage-crypto-rng Apple entropy recipe"
reject_pattern \
  "$runtime_builder" \
  '(openssl|libssl|libcrypto|securetransport)' \
  "iOS runtime package builder"

installed_sdk_builder=$(cat tool/ios/build_runtime_sdk.sh)
require_text \
  "$installed_sdk_builder" \
  'build-runtime-closure.sh' \
  "iOS runtime SDK closure build"
package_universe_generator=$(cat tool/ios/generate_package_universe.sh)
require_text \
  "$package_universe_generator" \
  'supported-closure.lock' \
  "iOS package-universe supported closure"

device_probe=$(cat tool/network_spike/test_ios_device_probe.sh)
require_text \
  "$device_probe" \
  'IOS_DEVELOPMENT_PROFILE_PATH' \
  "network device probe signing contract"
require_text \
  "$device_probe" \
  'IOS_DEVELOPMENT_SIGNING_IDENTITY' \
  "network device probe signing contract"

if test "$failures" -ne 0; then
  printf '%s\n' "network iOS contract failed with $failures violation(s)" >&2
  exit 1
fi

printf '%s\n' "Network iOS contract tests passed"
