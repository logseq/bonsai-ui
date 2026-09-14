#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

# shellcheck source=tool/ios/toolchain.lock
. "$script_directory/toolchain.lock"

opam_root="$repository_root/_build/ios/opam-root"
switch_root="$repository_root/_build/ios/switches"
probe_source="$script_directory/probe/minimal.ml"
host_source="$script_directory/probe/probe_host.m"
info_plist_source="$script_directory/probe/Info.plist"

fail() {
  printf '%s\n' "iOS probe build failure: $1" >&2
  exit 1
}

test "$#" -eq 1 || fail "usage: build_probe.sh iphoneos"
test "$1" = iphoneos || fail "expected iphoneos"

logical_target=iphoneos
sdk=iphoneos
target_triple=$IPHONEOS_TARGET_TRIPLE
expected_platform=IOS

switch="$switch_root/$logical_target"
output_directory="$repository_root/_build/ios/probes/$logical_target"
probe_build_source="$output_directory/minimal.ml"
object="$output_directory/minimal.o"
app="$output_directory/BonsaiSwiftUIProbe.app"
executable="$app/BonsaiSwiftUIProbe"
sdk_version=$(xcrun --sdk "$sdk" --show-sdk-version)

OPAMROOT="$opam_root" opam var --switch="$switch" prefix >/dev/null 2>&1 ||
  fail "missing $logical_target switch; run tool/ios/setup_toolchain.sh $logical_target"

mkdir -p "$output_directory"
cp "$probe_source" "$probe_build_source"

VER="$IOS_DEPLOYMENT_TARGET" \
  SDK="$sdk_version" \
  OPAMROOT="$opam_root" \
  opam exec --switch="$switch" -- \
  ocamlfind -toolchain ios ocamlopt \
    -output-complete-obj \
    "$probe_build_source" \
    -o "$object"

"$script_directory/verify_macho.sh" \
  "$object" \
  "$expected_platform" \
  arm64 \
  "$IOS_DEPLOYMENT_TARGET"

mkdir -p "$app"
cp "$info_plist_source" "$app/Info.plist"

cross_prefix=$(OPAMROOT="$opam_root" opam var --switch="$switch" prefix)
ocaml_include="$cross_prefix/ios-sysroot/lib/ocaml"
sysroot=$(xcrun --sdk "$sdk" --show-sdk-path)
clang=$(xcrun --sdk "$sdk" --find clang)

"$clang" \
  -target "$target_triple" \
  -isysroot "$sysroot" \
  -miphoneos-version-min="$IOS_DEPLOYMENT_TARGET" \
  -fobjc-arc \
  -I"$ocaml_include" \
  "$host_source" \
  "$object" \
  -framework Foundation \
  -framework UIKit \
  -framework Security \
  -o "$executable"

"$script_directory/verify_macho.sh" \
  "$executable" \
  "$expected_platform" \
  arm64 \
  "$IOS_DEPLOYMENT_TARGET"

printf '%s\n' "iOS $logical_target probe build passed: $app"
