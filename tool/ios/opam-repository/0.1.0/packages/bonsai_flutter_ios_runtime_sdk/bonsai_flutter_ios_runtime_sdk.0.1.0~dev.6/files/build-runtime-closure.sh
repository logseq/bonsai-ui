#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SDK_ASSET_ROOT=${SDK_ASSET_ROOT:-$script_directory}
RUNTIME_CLOSURE_LOCK=${RUNTIME_CLOSURE_LOCK:-"$SDK_ASSET_ROOT/runtime-closure.lock"}
closure_lock=$RUNTIME_CLOSURE_LOCK
opam_root=${OPAMROOT:-$(opam var root)}
switch=${SDK_OPAM_SWITCH:?SDK_OPAM_SWITCH is required}
switch_prefix=${OPAM_SWITCH_PREFIX:?OPAM_SWITCH_PREFIX is required}
target_lib=${TARGET_LIB:?TARGET_LIB is required}

fail() {
  printf '%s\n' "iOS runtime closure build failure: $1" >&2
  exit 1
}

test "$#" -eq 1 || fail "usage: build_runtime_closure.sh iphoneos"
target=$1
test "$target" = iphoneos || fail "expected iphoneos"
test -f "$closure_lock" || fail "missing runtime closure lock: $closure_lock"

stage_host_ppx_metadata() {
  host_lib=$(
    OPAMROOT="$opam_root" opam var --switch="$switch" lib
  )
  awk -F '|' '!/^#/ && NF { print $1 }' "$closure_lock" |
    while IFS= read -r package; do
      OPAMROOT="$opam_root" \
        opam show --switch="$switch" --list-files "$package" 2>/dev/null |
        while IFS= read -r installed_file; do
          test "${installed_file##*/}" = META || continue
          test -f "$installed_file" || continue
          case "$installed_file" in "$host_lib"/*) ;; *) continue ;; esac
          metadata_directory=$(dirname -- "$installed_file")
          relative_directory=${metadata_directory#"$host_lib"/}
          target_directory="$target_lib/$relative_directory"
          mkdir -p "$target_directory"
          for metadata_name in META dune-package opam; do
            test -f "$metadata_directory/$metadata_name" || continue
            cp -f "$metadata_directory/$metadata_name" "$target_directory/"
          done
        done
    done
}

# Dune resolves PPX drivers in the native host context, but its cross context
# still needs metadata for the drivers and their locked dependencies. Project
# only metadata selected by the lock; host archives and executables never enter
# the iPhoneOS target library.
stage_host_ppx_metadata

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/bonsai-flutter-build-closure.XXXXXX")
pending="$temporary_directory/pending"
next_pending="$temporary_directory/next-pending"
built="$temporary_directory/built"

cleanup() {
  rm -rf "$temporary_directory"
}

trap cleanup EXIT HUP INT TERM

# Pure_ocaml packages use the generic Dune or Topkg target path. Platform
# capabilities remain explicit in closure_capabilities.lock.
awk -F '|' '
  !/^#/ && NF && ($3 == "target-package" || $3 == "target-build") { print }
' "$closure_lock" >"$pending"
: >"$built"

while test -s "$pending"; do
  : >"$next_pending"
  progress=0
  while IFS='|' read -r package_name _version _role _capability _mechanism _source _sha _components dependencies; do
    ready=true
    if test "$dependencies" != -; then
      dependency_file="$temporary_directory/dependencies"
      printf '%s\n' "$dependencies" | tr ',' '\n' >"$dependency_file"
      while IFS= read -r dependency; do
        if ! grep -Fx -- "$dependency" "$built" >/dev/null; then ready=false; fi
      done <"$dependency_file"
    fi
    if test "$ready" = false; then
      printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
        "$package_name" \
        "$_version" \
        "$_role" \
        "$_capability" \
        "$_mechanism" \
        "$_source" \
        "$_sha" \
        "$_components" \
        "$dependencies" \
        >>"$next_pending"
      continue
    fi
    RUNTIME_CLOSURE_LOCK="$closure_lock" \
      TARGET_LIB="$target_lib" \
      sh "$script_directory/build-runtime-package.sh" "$target" "$package_name"
    printf '%s\n' "$package_name" >>"$built"
    progress=$((progress + 1))
  done <"$pending"
  test "$progress" -gt 0 ||
    fail "target-package dependency graph is cyclic or names a missing package"
  mv "$next_pending" "$pending"
done

printf '%s\n' "iOS $target runtime closure build passed"
