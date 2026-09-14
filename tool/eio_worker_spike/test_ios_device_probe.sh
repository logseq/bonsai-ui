#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
build_script="$script_directory/build_ios_device_probe.sh"
app="$repository_root/_build/eio-worker-spike/ios-device/BonsaiSwiftUIEioProbe.app"
executable="$app/BonsaiSwiftUIEioProbe"
complete_object="$repository_root/_build/eio-worker-spike/ios-device/eio_worker_device_probe.o"

# shellcheck source=tool/ios/toolchain.lock
. "$repository_root/tool/ios/toolchain.lock"

fail() {
  printf '%s\n' "Eio Worker iOS device probe test failure: $1" >&2
  exit 1
}

require_environment() {
  variable_name=$1
  eval "variable_value=\${$variable_name:-}"
  test -n "$variable_value" || fail "required environment variable is unset: $variable_name"
}

require_environment IOS_DEVICE_ID
require_environment IOS_SIGNING_IDENTITY
require_environment IOS_PROVISIONING_PROFILE
require_environment IOS_BUNDLE_IDENTIFIER

test -x "$build_script" || fail "device probe is not implemented"
test -f "$script_directory/eio_worker_device_probe.mli" ||
  fail "device probe interface is not implemented"
test -f "$script_directory/eio_worker_device_probe.ml" ||
  fail "device probe implementation is not implemented"
test -f "$script_directory/device_probe_host.m" ||
  fail "device probe host is not implemented"

"$build_script"

test -f "$complete_object" || fail "complete object was not produced"
test -x "$executable" || fail "device probe executable was not produced"

"$repository_root/tool/ios/verify_macho.sh" \
  "$complete_object" \
  IOS \
  arm64 \
  "$IOS_DEPLOYMENT_TARGET"
"$repository_root/tool/ios/verify_macho.sh" \
  "$executable" \
  IOS \
  arm64 \
  "$IOS_DEPLOYMENT_TARGET"

defined_symbols=$(nm -g "$complete_object" | awk '$2 ~ /^[TDSB]$/ { print $3 }')
for symbol in \
  _camlEio_worker_backend_spike.entry \
  _camlEio_worker_provider_spike.entry \
  _camlEio_worker_device_probe.entry \
  _caml_startup_exn
do
  printf '%s\n' "$defined_symbols" | grep -Fx "$symbol" >/dev/null ||
    fail "complete object does not define $symbol"
done

expected_markers='BONSAI_SWIFTUI_EIO_DEVICE_PROBE_OK'
launch_timeout=30
lifecycle=0
if test "${IOS_REQUIRE_LIFECYCLE:-0}" = 1; then
  expected_markers="${expected_markers}
BONSAI_SWIFTUI_EIO_DEVICE_PROBE_BACKGROUND
BONSAI_SWIFTUI_EIO_DEVICE_PROBE_RESUME_OK"
  launch_timeout=60
  lifecycle=1
fi

IOS_PROBE_APP="$app" \
IOS_PROBE_EXPECTED_MARKERS="$expected_markers" \
IOS_PROBE_LAUNCH_TIMEOUT="$launch_timeout" \
IOS_PROBE_RUN_LIFECYCLE="$lifecycle" \
  "$repository_root/tool/ios/run_probe_on_device.sh"

printf '%s\n' "Eio Worker physical iPhone probe tests passed"
