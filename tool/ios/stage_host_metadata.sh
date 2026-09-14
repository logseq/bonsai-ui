#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
opam_root="$repository_root/_build/ios/opam-root"
switch_root="$repository_root/_build/ios/switches"

fail() {
  printf '%s\n' "iOS host metadata staging failure: $1" >&2
  exit 1
}

test "$#" -eq 1 ||
  fail "usage: stage_host_metadata.sh iphoneos"

target=$1
test "$target" = iphoneos || fail "expected iphoneos"

switch="$switch_root/$target"
test -x "$switch/_opam/bin/ocamlc" ||
  fail "missing target switch: $switch"

host_lib=$(
  OPAMROOT="$opam_root" \
    opam var --switch="$switch" lib
)
target_lib="$switch/_opam/ios-sysroot/lib"
target_standard_library="$target_lib/ocaml"
mkdir -p "$target_lib"

find "$host_lib" -mindepth 1 -maxdepth 1 -type d |
  while IFS= read -r host_package_directory; do
    if test ! -f "$host_package_directory/META" &&
      test ! -f "$host_package_directory/dune-package"; then
      continue
    fi
    package_name=${host_package_directory##*/}
    target_package_directory="$target_lib/$package_name"
    mkdir -p "$target_package_directory"

    for metadata_name in META dune-package opam; do
      if test -f "$host_package_directory/$metadata_name"; then
        cp -f \
          "$host_package_directory/$metadata_name" \
          "$target_package_directory/"
      fi
    done
  done

find "$target_standard_library" -mindepth 1 -maxdepth 1 -type d |
  while IFS= read -r target_standard_package; do
    test -f "$target_standard_package/META" || continue
    package_name=${target_standard_package##*/}
    target_package_directory="$target_lib/$package_name"
    mkdir -p "$target_package_directory"

    find "$target_standard_package" \
      -maxdepth 1 \
      -type f \
      \( \
        -name META -o \
        -name '*.a' -o \
        -name '*.cma' -o \
        -name '*.cmi' -o \
        -name '*.cmti' -o \
        -name '*.cmx' -o \
        -name '*.cmxa' -o \
        -name '*.mli' \
      \) \
      -exec cp -f {} "$target_package_directory/" \;
  done

printf '%s\n' \
  "iOS $target host metadata and target standard-library staging passed"
