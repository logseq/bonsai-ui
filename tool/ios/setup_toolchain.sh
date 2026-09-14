#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

# shellcheck source=tool/ios/toolchain.lock
. "$script_directory/toolchain.lock"

opam_root="$repository_root/_build/ios/opam-root"
switch_root="$repository_root/_build/ios/switches"
source_root="$repository_root/_build/ios/sources"
cross_repository="$source_root/opam-cross-ios"
overlay_repository="$source_root/opam-ios-overlay"

fail() {
  printf '%s\n' "iOS toolchain setup failure: $1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

opam_command() {
  OPAMROOT="$opam_root" opam "$@"
}

switch_path() {
  printf '%s/%s\n' "$switch_root" "$1"
}

switch_exists() {
  switch=$(switch_path "$1")
  opam_command switch list --short 2>/dev/null | grep -Fx -- "$switch" >/dev/null
}

ensure_cross_repository() {
  mkdir -p "$source_root"
  if test ! -d "$cross_repository/.git"; then
    git clone "$OPAM_CROSS_IOS_REPOSITORY" "$cross_repository"
  fi

  if test -n "$(git -C "$cross_repository" status --porcelain)"; then
    fail "managed opam-cross-ios checkout has local changes: $cross_repository"
  fi

  current_commit=$(git -C "$cross_repository" rev-parse HEAD)
  if test "$current_commit" != "$OPAM_CROSS_IOS_COMMIT"; then
    git -C "$cross_repository" fetch origin "$OPAM_CROSS_IOS_COMMIT"
    git -C "$cross_repository" checkout --detach "$OPAM_CROSS_IOS_COMMIT"
  fi

  resolved_commit=$(git -C "$cross_repository" rev-parse HEAD)
  test "$resolved_commit" = "$OPAM_CROSS_IOS_COMMIT" ||
    fail "opam-cross-ios checkout does not match the lock file"

  "$script_directory/prepare_cross_overlay.sh" \
    "$cross_repository" \
    "$overlay_repository"
}

ensure_opam_root() {
  if test ! -f "$opam_root/config"; then
    mkdir -p "$opam_root"
    opam_command init \
      --bare \
      --disable-sandboxing \
      --no-setup \
      --yes \
      default \
      "$OPAM_DEFAULT_REPOSITORY"
  fi
}

create_switch() {
  logical_name=$1
  switch=$(switch_path "$logical_name")

  if switch_exists "$logical_name"; then
    installed_version=$(opam_command exec --switch="$switch" -- ocamlc -version)
    if test "$installed_version" = "$OCAML_VERSION"; then
      return
    fi
    opam_command switch remove "$switch" --yes
  fi

  mkdir -p "$switch"
  opam_command switch create "$switch" \
    "ocaml-base-compiler.$OCAML_VERSION" \
    --no-install \
    --no-switch \
    --repositories="overlay=file://$overlay_repository,ios=file://$cross_repository,default=$OPAM_DEFAULT_REPOSITORY" \
    --yes
}

install_host() {
  create_switch host
}

install_iphoneos() {
  create_switch iphoneos
  switch=$(switch_path iphoneos)
  sdk_version=$(xcrun --sdk iphoneos --show-sdk-version)
  recipe_marker="$switch/_opam/.bonsai-swiftui-ios-recipe"
  recipe_identity="$OCAML_IOS_RECIPE_REVISION-$IOS_DEPLOYMENT_TARGET"

  opam_command update overlay

  if opam_command list \
    --switch="$switch" \
    --installed \
    --short \
    "$OCAML_IOS_PACKAGE" |
    grep -Fx ocaml-ios64 >/dev/null 2>&1; then
    installed_recipe_identity=$(cat "$recipe_marker" 2>/dev/null || true)
    if test "$installed_recipe_identity" != "$recipe_identity"; then
      ARCH="$IPHONEOS_ARCH" \
        SUBARCH="$IPHONEOS_SUBARCH" \
        PLATFORM="$IPHONEOS_PLATFORM" \
        SDK="$sdk_version" \
        VER="$IOS_DEPLOYMENT_TARGET" \
        opam_command reinstall \
          --switch="$switch" \
          conf-ios.4 \
          "$OCAML_IOS_PACKAGE" \
          --yes
    fi
  else
    ARCH="$IPHONEOS_ARCH" \
      SUBARCH="$IPHONEOS_SUBARCH" \
      PLATFORM="$IPHONEOS_PLATFORM" \
      SDK="$sdk_version" \
      VER="$IOS_DEPLOYMENT_TARGET" \
      opam_command install \
        --switch="$switch" \
        conf-ios.4 \
        "$OCAML_IOS_PACKAGE" \
        --yes
  fi

  printf '%s\n' "$recipe_identity" >"$recipe_marker"
}

verify_switch() {
  logical_name=$1
  switch=$(switch_path "$logical_name")
  installed_version=$(opam_command exec --switch="$switch" -- ocamlc -version)
  test "$installed_version" = "$OCAML_VERSION" ||
    fail "$logical_name switch does not use OCaml $OCAML_VERSION"

  if test "$logical_name" = iphoneos; then
    target_cflags=$(
      opam_command exec --switch="$switch" -- \
        ocamlfind -toolchain ios ocamlc -config |
        sed -n 's/^ocamlc_cflags: //p'
    )
    printf '%s\n' "$target_cflags" |
      grep -F -- "-miphoneos-version-min=$IOS_DEPLOYMENT_TARGET" >/dev/null ||
      fail "iphoneos compiler does not target iOS $IOS_DEPLOYMENT_TARGET"
    IOS_CROSS_TEST_OPAMROOT="$opam_root" \
      IOS_CROSS_TEST_SWITCH="$switch" \
      python3 "$repository_root/tool/test_ios_cross_compiler.py"
  fi
}

require_command git
require_command opam
require_command xcrun
require_command python3

requested_target=${1:-all}
case "$requested_target" in
  host)
    ensure_cross_repository
    ensure_opam_root
    install_host
    verify_switch host
    ;;
  iphoneos)
    ensure_cross_repository
    ensure_opam_root
    install_iphoneos
    verify_switch iphoneos
    ;;
  all)
    ensure_cross_repository
    ensure_opam_root
    install_host
    install_iphoneos
    verify_switch host
    verify_switch iphoneos
    ;;
  *)
    fail "expected host, iphoneos, or all"
    ;;
esac

printf '%s\n' "iOS $requested_target toolchain setup passed"
