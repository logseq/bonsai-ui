#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

fail() {
  printf '%s\n' "Apple complete-object verification failure: $1" >&2
  exit 1
}

test "$#" -eq 4 ||
  fail "usage: verify_complete_object.sh <object> <platform> <minimum> <architecture>"

object_path=$1
expected_platform=$2
expected_minimum=$3
expected_architecture=$4

"$script_directory/verify_macho.sh" \
  "$object_path" \
  "$expected_platform" \
  "$expected_architecture" \
  "$expected_minimum"

defined_symbols=$(nm -g "$object_path" | awk '$2 ~ /^[TDSB]$/ { print $3 }')
for symbol in \
  _bs_abi_version_major \
  _bs_abi_version_minor \
  _bs_protocol_version_major \
  _bs_protocol_version_minor \
  _bs_runtime_create \
  _bs_runtime_pump \
  _bs_runtime_presentation_succeeded \
  _bs_runtime_presentation_rejected \
  _bs_runtime_get_last_error \
  _bs_buffer_free \
  _bs_runtime_outstanding_buffers \
  _bs_runtime_destroy \
  _caml_startup_exn
do
  printf '%s\n' "$defined_symbols" | grep -Fx "$symbol" >/dev/null ||
    fail "$object_path does not define $symbol"
done

if printf '%s\n' "$defined_symbols" | grep -E '^_bf_' >/dev/null; then
  fail "$object_path still defines an obsolete Flutter ABI symbol"
fi

if LC_ALL=C strings -a -n 8 "$object_path" |
  grep -E \
    '/opt/homebrew|/usr/local|MacOSX[0-9]|/private/tmp/bonsai-swiftui-opam' \
    >/dev/null; then
  fail "$object_path embeds a prohibited host path"
fi

printf '%s\n' "Apple complete-object verification passed: $object_path"
