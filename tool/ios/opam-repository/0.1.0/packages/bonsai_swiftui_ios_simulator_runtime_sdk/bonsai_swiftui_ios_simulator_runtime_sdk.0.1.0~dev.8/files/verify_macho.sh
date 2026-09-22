#!/bin/sh

set -eu

fail() {
  printf '%s\n' "Mach-O verification failure: $1" >&2
  exit 1
}

test "$#" -eq 4 ||
  fail "usage: verify_macho.sh <artifact> <platform> <architecture> <minimum-version>"

artifact=$1
expected_platform=$2
expected_architecture=$3
expected_minimum=$4

test -f "$artifact" || fail "artifact does not exist: $artifact"

file_output=$(file "$artifact")
printf '%s\n' "$file_output"
printf '%s\n' "$file_output" | grep -F -- "$expected_architecture" >/dev/null ||
  fail "expected architecture $expected_architecture"

architectures=$(xcrun lipo -archs "$artifact")
printf '%s\n' "architectures $architectures"
test "$architectures" = "$expected_architecture" ||
  fail "expected only $expected_architecture, found $architectures"

build_output=$(xcrun vtool -show-build "$artifact")
printf '%s\n' "$build_output"
printf '%s\n' "$build_output" |
  grep -E "platform[[:space:]]+$expected_platform([[:space:]]|$)" >/dev/null ||
  fail "expected platform $expected_platform"
printf '%s\n' "$build_output" |
  grep -E "minos[[:space:]]+$expected_minimum([[:space:]]|$)" >/dev/null ||
  fail "expected minimum version $expected_minimum"

if xcrun otool -l "$artifact" |
  grep -A2 'LC_SEGMENT_64' |
  grep -F '__LLVM' >/dev/null; then
  fail "Bitcode segment __LLVM is prohibited"
fi

printf '%s\n' "Mach-O verification passed: $artifact"
