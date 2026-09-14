#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

fail() {
  printf '%s\n' "iPhoneOS runtime SDK build failure: $1" >&2
  exit 1
}

test "$#" -eq 2 || fail "usage: build-runtime-sdk.sh OPAM_SWITCH OPAM_SWITCH_PREFIX"
SDK_OPAM_SWITCH=$1
selected_prefix=$2
test -n "${OPAM_SWITCH_PREFIX:-}" || fail "OPAM_SWITCH_PREFIX is missing"
test "$selected_prefix" = "$OPAM_SWITCH_PREFIX" ||
  fail "selected opam prefix differs from OPAM_SWITCH_PREFIX"

for command in awk cp find grep mkdir opam patch rg sed shasum sort tar xcrun; do
  command -v "$command" >/dev/null 2>&1 || fail "required command is unavailable: $command"
done

work_root="$PWD/.bonsai_flutter_ios_runtime_sdk"
stage_root="$work_root/stage"
target_lib="$stage_root/ios-sysroot/lib"
package_work_root="$work_root/packages"
mkdir -p "$target_lib" "$package_work_root"

export SDK_ASSET_ROOT=$script_directory
export SDK_OPAM_SWITCH
export SDK_PACKAGE_WORK_ROOT=$package_work_root
export RUNTIME_CLOSURE_LOCK="$script_directory/supported-closure.lock"
export TARGET_LIB=$target_lib

sh "$script_directory/build-runtime-closure.sh" iphoneos

printf '%s\n' "iPhoneOS runtime SDK build passed"
