#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
build_script="$script_directory/build_ios_complete_object.sh"
artifact_directory="$repository_root/_build/eio-worker-spike/ios/iphoneos/arm64"
complete_object="$artifact_directory/eio_worker_backend_spike.o"
probe_executable="$artifact_directory/eio_worker_backend_spike_probe"

# shellcheck source=tool/ios/toolchain.lock
. "$repository_root/tool/ios/toolchain.lock"

fail() {
  printf '%s\n' "Eio Worker iPhoneOS spike test failure: $1" >&2
  exit 1
}

test -x "$build_script" || fail "iPhoneOS Eio closure is not implemented"

"$build_script"

"$repository_root/tool/ios/verify_macho.sh" \
  "$complete_object" \
  IOS \
  arm64 \
  "$IOS_DEPLOYMENT_TARGET"
"$repository_root/tool/ios/verify_macho.sh" \
  "$probe_executable" \
  IOS \
  arm64 \
  "$IOS_DEPLOYMENT_TARGET"

defined_symbols=$(nm -g "$complete_object" | awk '$2 ~ /^[TDSB]$/ { print $3 }')
for symbol in \
  _camlEio_posix.entry \
  _camlEio_worker_backend_spike.entry \
  _caml_startup_exn
do
  printf '%s\n' "$defined_symbols" | grep -Fx "$symbol" >/dev/null ||
    fail "complete object does not define $symbol"
done

if LC_ALL=C strings -a -n 8 "$complete_object" |
  grep -E \
    '/opt/homebrew|/usr/local|MacOSX[0-9]|/private/tmp/bonsai-swiftui-opam|-mpopcnt' \
    >/dev/null; then
  fail "complete object embeds a prohibited host path or CPU flag"
fi

printf '%s\n' "Eio Worker iPhoneOS complete-object spike tests passed"
