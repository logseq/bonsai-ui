#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root="$script_directory/opam-repository/0.1.0"
switch=bonsai-swiftui-ios

# shellcheck source=tool/ios/sdk_repository.lock
. "$script_directory/sdk_repository.lock"

fail() {
  printf '%s\n' "iPhoneOS framework SDK update failure: $1" >&2
  exit 1
}

test "$#" -eq 0 || fail "usage: update-framework-sdk.sh"
test -f "$repository_root/repository.sexp" ||
  fail "missing generated SDK repository: $repository_root"

opam switch list --short | grep -Fx "$switch" >/dev/null ||
  fail "the global iPhoneOS switch is missing; run toolchain install iphoneos"

installed_runtime_version=$(
  opam list \
    --switch="$switch" \
    --installed \
    --short \
    --columns=version \
    bonsai_swiftui_ios_runtime_sdk 2>/dev/null
) || installed_runtime_version=
test "$installed_runtime_version" = "$SDK_RUNTIME_PACKAGE_VERSION" ||
  fail "runtime SDK version $installed_runtime_version does not match $SDK_RUNTIME_PACKAGE_VERSION; this update requires a full iPhoneOS toolchain replacement"

snapshot_sha256=$(
  awk '$1 == "(repository_snapshot_sha256" { value=$2; sub(/\)$/, "", value); print value }' \
    "$repository_root/repository.sexp"
)
test -n "$snapshot_sha256" || fail "repository snapshot digest is missing"
repository_name="bonsai-swiftui-ios-framework-$(printf '%s' "$snapshot_sha256" | cut -c1-12)"

if opam repository list --all --short | grep -Fx "$repository_name" >/dev/null; then
  opam repository add \
    --switch="$switch" \
    --rank=1 \
    "$repository_name"
else
  opam repository add \
    --switch="$switch" \
    --rank=1 \
    --yes \
    "$repository_name" \
    "file://$repository_root"
fi
opam update --switch="$switch" "$repository_name"
opam install \
  --switch="$switch" \
  --yes \
  "bonsai_swiftui_ios_sdk.$SDK_PACKAGE_VERSION" \
  --assume-depexts

printf '%s\n' "iPhoneOS framework SDK updated: $SDK_PACKAGE_VERSION"
