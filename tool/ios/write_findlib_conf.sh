#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
switch="$repository_root/_build/ios/switches/iphoneos"

fail() {
  printf '%s\n' "iOS findlib configuration failure: $1" >&2
  exit 1
}

test "$#" -eq 2 || fail "usage: write_findlib_conf.sh <target-lib> <output>"
target_lib=$1
output=$2
baseline_target_lib="$switch/_opam/ios-sysroot/lib"
standard_target_lib="$baseline_target_lib/ocaml"
host_conf="$switch/_opam/lib/findlib.conf"
ios_conf="$switch/_opam/lib/findlib.conf.d/ios.conf"

test -d "$target_lib" || fail "target library directory does not exist: $target_lib"
test -f "$host_conf" || fail "host findlib configuration is missing"
test -f "$ios_conf" || fail "iOS findlib toolchain configuration is missing"
mkdir -p "$(dirname -- "$output")"

{
  sed '/^[[:space:]]*$/d' "$host_conf"
  awk \
    -v target_lib="$target_lib" \
    -v standard_target_lib="$standard_target_lib" '
      /^path\(ios\)/ {
        printf "path(ios) = \"%s:%s\"\n", target_lib, standard_target_lib
        next
      }
      /^destdir\(ios\)/ {
        printf "destdir(ios) = \"%s\"\n", target_lib
        next
      }
      { print }
    ' "$ios_conf"
} >"$output.partial"
mv "$output.partial" "$output"

grep -F "ocamlopt(ios)" "$output" >/dev/null ||
  fail "generated configuration does not select the iOS compiler"
grep -F "path(ios) = \"$target_lib:$standard_target_lib\"" "$output" >/dev/null ||
  fail "generated configuration does not select the application target closure"

printf '%s\n' "Generated iOS application findlib configuration: $output"
