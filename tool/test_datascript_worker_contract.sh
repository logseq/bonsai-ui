#!/bin/sh

set -u

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

failures=0

fail() {
  printf '%s\n' "DataScript Worker contract failure: $1" >&2
  failures=$((failures + 1))
}

require_file() {
  test -f "$1" || fail "missing $1"
}

reject_file() {
  test ! -e "$1" || fail "obsolete path remains: $1"
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
    fail "$label unexpectedly contains: $needle"
  fi
}

require_before() {
  haystack=$1
  earlier=$2
  later=$3
  label=$4
  earlier_line=$(printf '%s\n' "$haystack" | grep -n -F -- "$earlier" | head -1 | cut -d: -f1)
  later_line=$(printf '%s\n' "$haystack" | grep -n -F -- "$later" | head -1 | cut -d: -f1)
  if test -z "$earlier_line" || test -z "$later_line" || \
    test "$earlier_line" -ge "$later_line"
  then
    fail "$label does not place $earlier before $later"
  fi
}

fixture=tool/ios/fixtures/application-closure
fixture_opam="$fixture/bonsai_swiftui_ios_closure_fixture.opam"
for path in \
  "$fixture/datascript_worker_probe.ml" \
  "$fixture/datascript_worker_native_embed.ml" \
  "$fixture_opam" \
  tool/ios/test_datascript_worker_device.sh
do
  require_file "$path"
done

fixture_packages=$(cat "$fixture_opam" 2>/dev/null)
for dependency in \
  '"ppx_deriving_yojson" {= "3.9.1"}' \
  '"melange-transit-core" {= "0.1.2"}' \
  '"melange-transit-native" {= "0.1.2"}' \
  '["datascript_ocaml.dev" "git+https://github.com/logseq/datascript-ocaml.git#main"]' \
  '["datascript-ocaml-native.dev" "git+https://github.com/logseq/datascript-ocaml.git#main"]' \
  '["melange-transit-core.0.1.2" "git+https://github.com/logseq/melange-transit.git#main"]' \
  '["melange-transit-native.0.1.2" "git+https://github.com/logseq/melange-transit.git#main"]'
do
  require_text "$fixture_packages" "$dependency" "DataScript Worker fixture package pins"
done
reject_text "$fixture_packages" 'melange-transit-core.0.1.1' \
  "DataScript Worker fixture package pins"
reject_text "$fixture_packages" 'melange-transit-native.0.1.1' \
  "DataScript Worker fixture package pins"

runtime_closure=$(cat vendor/opam-ios/runtime-closure.lock 2>/dev/null)
supported_closure=$(cat vendor/opam-ios/supported-closure.lock 2>/dev/null)
for closure in "$runtime_closure" "$supported_closure"; do
  require_text "$closure" \
    'ppx_deriving|6.0.3|target-package|Pure_ocaml|dune|https://github.com/ocaml-ppx/ppx_deriving/releases/download/v6.0.3/ppx_deriving-6.0.3.tbz|374aa97b32c5e01c09a97810a48bfa218c213b5b649e4452101455ac19c94a6d|ppx_deriving.runtime|-' \
    "ppx_deriving iOS runtime closure"
  require_text "$closure" \
    'ppx_deriving_yojson|3.9.1|target-package|Pure_ocaml|dune|https://github.com/ocaml-ppx/ppx_deriving_yojson/releases/download/v3.9.1/ppx_deriving_yojson-3.9.1.tbz|6a3ef7c7bb381f57448853f2a6d2287cf623628162a979587d1e8f7502114f4d|ppx_deriving_yojson.runtime|ppx_deriving' \
    "ppx_deriving_yojson iOS runtime closure"
  require_text "$closure" \
    'cppo|1.8.0|host-package|Host_only|' \
    "ppx_deriving native host closure"
  require_text "$closure" \
    'ppx_derivers|1.2.1|host-package|Host_only|' \
    "ppx_deriving native host closure"
  reject_text "$closure" \
    '|ppx_deriving,ppx_deriving.runtime|' \
    "ppx_deriving target components"
  reject_text "$closure" \
    '|ppx_deriving_yojson,ppx_deriving_yojson.runtime|' \
    "ppx_deriving_yojson target components"
  require_text "$closure" \
    'datascript-ocaml/archive/40345cc2f59214daa88b33b8aec711337d20afa7.tar.gz' \
    "DataScript iOS closure"
  require_text "$closure" 'melange-transit-core|0.1.2|target-package|' \
    "DataScript iOS closure"
  require_text "$closure" 'melange-transit-native|0.1.2|target-package|' \
    "DataScript iOS closure"
  require_text "$closure" \
    'melange-transit/archive/35f8afe7d6506863c7253e67a20befb3dde5c18f.tar.gz' \
    "DataScript iOS closure"
  reject_text "$closure" 'melange-transit-core|0.1.1|' \
    "DataScript iOS closure"
  reject_text "$closure" 'melange-transit-native|0.1.1|' \
    "DataScript iOS closure"
done

closure_capabilities=$(cat tool/ios/closure_capabilities.lock 2>/dev/null)
reject_text "$closure_capabilities" 'ppx_deriving|' \
  "generic ppx_deriving capability classification"
reject_text "$closure_capabilities" 'ppx_deriving_yojson|' \
  "generic ppx_deriving_yojson capability classification"

datascript_sqlite_patch=vendor/patches/ios/datascript-system-sqlite.patch
runtime_builder=$(cat tool/ios/build_runtime_package.sh 2>/dev/null)
toolchain_lock=$(cat tool/ios/toolchain.lock 2>/dev/null)
require_file "$datascript_sqlite_patch"
require_text \
  "$runtime_builder" \
  'if test "$package_name" = datascript-ocaml-native; then' \
  "DataScript SQLite runtime recipe"
require_text \
  "$runtime_builder" \
  'patches/datascript-system-sqlite.patch' \
  "DataScript SQLite runtime recipe"
require_text \
  "$runtime_builder" \
  'DataScript SQLite source declaration changed upstream' \
  "DataScript SQLite source-drift guard"
require_text \
  "$runtime_builder" \
  'DataScript SQLite still configures an explicit library path' \
  "DataScript SQLite patched-source guard"
require_text \
  "$runtime_builder" \
  'DataScript SQLite does not link the system sqlite3 library' \
  "DataScript SQLite system-library guard"
require_text \
  "$toolchain_lock" \
  "IOS_RUNTIME_RECIPE_REVISION='7'" \
  "DataScript SQLite runtime recipe revision"

if test -f "$datascript_sqlite_patch"; then
  patch_fixture=$(mktemp -d "${TMPDIR:-/tmp}/bonsai-datascript-patch.XXXXXX")
  mkdir -p "$patch_fixture/sqlite"
  trap 'rm -rf "$patch_fixture"' EXIT HUP INT TERM
  {
    printf '%s\n' \
      '(library' \
      ' (name datascript_sqlite)' \
      ' (public_name datascript-ocaml-native.sqlite)' \
      ' (foreign_stubs' \
      '  (language c)' \
      '  (names datascript_sqlite_stubs))' \
      ' (c_library_flags' \
      '  (:standard -L%{env:DATASCRIPT_SQLITE_LIB_DIR=.} -lsqlite3))' \
      ' (libraries datascript-ocaml-native persistent_sorted_set_ocaml melange-transit-native))'
  } >"$patch_fixture/sqlite/dune"
  if ! patch \
    --batch \
    --forward \
    -d "$patch_fixture" \
    -p1 \
    <"$datascript_sqlite_patch" >/dev/null; then
    fail "DataScript SQLite patch does not apply to the pinned upstream declaration"
  fi
  patched_sqlite_dune=$(cat "$patch_fixture/sqlite/dune")
  require_text \
    "$patched_sqlite_dune" \
    '(:standard -lsqlite3)' \
    "patched DataScript SQLite declaration"
  reject_text \
    "$patched_sqlite_dune" \
    'DATASCRIPT_SQLITE_LIB_DIR' \
    "patched DataScript SQLite declaration"
  reject_text \
    "$patched_sqlite_dune" \
    '-L.' \
    "patched DataScript SQLite declaration"
fi

transit_repository=tool/ios/opam-repository/0.1.0/packages
require_file \
  "$transit_repository/melange-transit-core/melange-transit-core.0.1.2/opam"
require_file \
  "$transit_repository/melange-transit-native/melange-transit-native.0.1.2/opam"
reject_file \
  "$transit_repository/melange-transit-core/melange-transit-core.0.1.1"
reject_file \
  "$transit_repository/melange-transit-native/melange-transit-native.0.1.1"

sdk_repository_lock=$(cat tool/ios/sdk_repository.lock 2>/dev/null)
require_text "$sdk_repository_lock" "SDK_ABI_VERSION='4'" \
  "ppx_deriving_yojson SDK ABI version"
require_text "$sdk_repository_lock" "SDK_BUILD_RECIPE_REVISION='5'" \
  "ppx_deriving_yojson SDK build recipe revision"
require_text "$sdk_repository_lock" "SDK_RUNTIME_PACKAGE_VERSION='0.1.0~dev.7'" \
  "DataScript runtime SDK version"
require_text "$sdk_repository_lock" "SDK_PACKAGE_VERSION='0.1.0~dev.42'" \
  "DataScript framework SDK version"

sdk_packages=tool/ios/opam-repository/0.1.0/packages
runtime_sdk="$sdk_packages/bonsai_swiftui_ios_runtime_sdk/bonsai_swiftui_ios_runtime_sdk.0.1.0~dev.7"
framework_sdk="$sdk_packages/bonsai_swiftui_ios_sdk/bonsai_swiftui_ios_sdk.0.1.0~dev.42"
require_file "$runtime_sdk/opam"
require_file "$runtime_sdk/files/supported-closure.lock"
require_file "$framework_sdk/opam"
require_file "$framework_sdk/files/manifest.sexp"
reject_file \
  "$sdk_packages/bonsai_swiftui_ios_runtime_sdk/bonsai_swiftui_ios_runtime_sdk.0.1.0~dev.6"
reject_file \
  "$sdk_packages/bonsai_swiftui_ios_sdk/bonsai_swiftui_ios_sdk.0.1.0~dev.38"
package_universe=$(cat tool/ios/opam-repository/0.1.0/package-universe.lock 2>/dev/null)
require_text "$package_universe" 'ppx_deriving|6.0.3|default|' \
  "ppx_deriving immutable package metadata"
require_text "$package_universe" 'ppx_deriving_yojson|3.9.1|default|' \
  "ppx_deriving_yojson immutable package metadata"
source_archives=$(cat tool/ios/opam-repository/0.1.0/source-archives.lock 2>/dev/null)
require_text "$source_archives" \
  'ppx_deriving|6.0.3|https://github.com/ocaml-ppx/ppx_deriving/releases/download/v6.0.3/ppx_deriving-6.0.3.tbz|sha256|374aa97b32c5e01c09a97810a48bfa218c213b5b649e4452101455ac19c94a6d' \
  "ppx_deriving immutable repository source"
require_text "$source_archives" \
  'ppx_deriving_yojson|3.9.1|https://github.com/ocaml-ppx/ppx_deriving_yojson/releases/download/v3.9.1/ppx_deriving_yojson-3.9.1.tbz|sha256|6a3ef7c7bb381f57448853f2a6d2287cf623628162a979587d1e8f7502114f4d' \
  "ppx_deriving_yojson immutable repository source"

fixture_dune=$(cat "$fixture/app.dune")
for library in \
  bonsai_swiftui_sqlite_worker_example \
  datascript-ocaml-native \
  datascript-ocaml-native.sqlite \
  uutf \
  uunf \
  uucp
do
  require_text "$fixture_dune" "$library" "DataScript Worker fixture libraries"
done
require_text "$fixture_dune" 'datascript_worker_native_embed' "DataScript Worker fixture executable"
require_text "$fixture_dune" '(pps ppx_deriving_yojson)' \
  "DataScript Worker real PPX preprocessing"

probe=$(cat "$fixture/datascript_worker_probe.ml" 2>/dev/null)
require_text "$probe" '[@@deriving yojson]' "derived JSON codec declaration"
require_text "$probe" 'json_probe_to_yojson' "generated JSON encoder execution"
require_text "$probe" 'json_probe_of_yojson' "generated JSON decoder execution"
require_text "$probe" 'BONSAI_DERIVING_YOJSON_ROUND_TRIP' \
  "generated JSON codec round-trip marker"
require_text "$probe" 'Datascript_sqlite.open_session' "DataScript SQLite open"
require_text "$probe" 'Datascript.store' "typed fact persistence"
require_text "$probe" 'Datascript.restore' "typed fact restoration"
require_text "$probe" 'BONSAI_DATASCRIPT_WORKER_PERSISTED' "first-launch marker"
require_text "$probe" 'BONSAI_DATASCRIPT_WORKER_RESTORED' "relaunch marker"
require_text "$probe" 'BONSAI_DATASCRIPT_WORKER_SHUTDOWN' "Worker shutdown marker"

service=$(cat examples/sqlite_worker/ocaml/sqlite_worker_service.ml)
service_interface=$(cat examples/sqlite_worker/ocaml/sqlite_worker_service.mli)
require_text "$service" 'create_with_persistence_probe' "injectable Worker persistence probe"
require_text "$service_interface" 'create_with_persistence_probe' "Worker persistence probe interface"

device_test=$(cat tool/ios/test_datascript_worker_device.sh 2>/dev/null)
device_entry=$(cat tool/ios/fixtures/datascript-worker-host/swift/Probe.swift)
require_text \
  "$device_entry" \
  'marker("BONSAI_DATASCRIPT_HOST_RUNTIME_STARTED")' \
  "physical-device host runtime start evidence"
require_text \
  "$device_entry" \
  'marker("BONSAI_DATASCRIPT_HOST_RUNTIME_DISPOSED")' \
  "physical-device host runtime disposal evidence"
require_text "$device_test" 'IOS_DEVICE_ID' "physical iPhone selection"
require_text "$device_test" 'IOS_SIGNING_IDENTITY' "physical iPhone signing"
require_text "$device_test" '--signing-identity "$IOS_SIGNING_IDENTITY"' \
  "selected Development signing identity"
reject_text "$device_test" '--require-signing' \
  "Development-only DataScript physical slice"
require_before \
  "$device_test" \
  'ios_device_preflight.sh' \
  'setup_toolchain.sh' \
  "physical-device fail-fast preflight"
require_text "$device_test" 'build_datascript_worker_probe.py' "native SwiftUI probe build"
require_text "$device_test" 'Release-iphoneos/DataScriptWorkerProbe.app' "standalone physical-device Release App"
reject_text "$device_test" 'flutter build' "native probe build"
reject_text "$device_test" 'flutter pub' "native probe dependencies"
require_text "$device_entry" 'NativeRuntime.open' "actual native runtime startup"
require_text "$device_entry" 'await runtime.close()' "awaited native runtime disposal"
require_text "$device_test" 'BONSAI_DATASCRIPT_PROBE_PASSED' "complete native probe evidence"
require_text "$device_test" 'BONSAI_DATASCRIPT_WORKER_PERSISTED' "first launch evidence"
require_text "$device_test" 'BONSAI_DATASCRIPT_WORKER_SHUTDOWN' "runtime shutdown evidence"
require_text "$device_test" 'BONSAI_DATASCRIPT_WORKER_RESTORED' "relaunch evidence"
require_text "$device_test" 'BONSAI_DERIVING_YOJSON_ROUND_TRIP' \
  "physical-device generated JSON codec evidence"
require_text "$device_test" '--terminate-existing' "runtime relaunch"

require_text "$(cat Makefile)" 'tool/test_datascript_worker_contract.sh' "CI contract target"

if test "$failures" -ne 0; then
  printf '%s\n' "DataScript Worker contract failed with $failures violation(s)" >&2
  exit 1
fi

# Behavioral checks use the real OCaml program, Swift runtime and Apple linker.
python3 native/test/test_datascript_worker_probe.py || exit 1
python3 tool/test_ios_process_isolation.py || exit 1
python3 tool/build_datascript_worker_probe.py \
  --native-object _build/ios/swiftui-framework/default.ios/native/test/datascript_worker/datascript_worker_native_embed.exe.o \
  --build-root _build/ios/datascript-worker-device \
  --bundle-identifier org.bonsai-swiftui.probe.datascript-worker || exit 1
python3 tool/test_swiftui_ios_bundle.py || exit 1

printf '%s\n' "DataScript Worker contract tests passed"
