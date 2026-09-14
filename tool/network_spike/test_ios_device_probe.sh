#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
build_script="$script_directory/build_ios_device_probe.sh"
app="$repository_root/_build/network-spike/ios-device/BonsaiSwiftUINetworkProbe.app"
complete_object="$repository_root/_build/network-spike/ios-device/network_spike_device_probe.o"

fail() {
  printf '%s\n' "Network spike iOS device probe failure: $1" >&2
  exit 1
}

require_environment() {
  variable_name=$1
  eval "variable_value=\${$variable_name:-}"
  test -n "$variable_value" || fail "required environment variable is unset: $variable_name"
}

test -x "$build_script" || fail "device probe build script is not implemented"
test -f "$script_directory/network_spike_device_probe.ml" ||
  fail "device probe OCaml implementation is not implemented"
test -f "$script_directory/device_probe_host.m" ||
  fail "device probe host is not implemented"

"$build_script"

test -f "$complete_object" || fail "complete object was not produced"
test -d "$app" || fail "application bundle was not produced"

IOS_SIGNING_IDENTITY=${IOS_SIGNING_IDENTITY:-${IOS_DEVELOPMENT_SIGNING_IDENTITY:-Apple Development}}
IOS_PROVISIONING_PROFILE=${IOS_PROVISIONING_PROFILE:-${IOS_DEVELOPMENT_PROFILE_PATH:-}}
export IOS_SIGNING_IDENTITY IOS_PROVISIONING_PROFILE

require_environment IOS_DEVICE_ID
require_environment IOS_SIGNING_IDENTITY
require_environment IOS_PROVISIONING_PROFILE
require_environment IOS_BUNDLE_IDENTIFIER

IOS_PROBE_APP="$app" \
IOS_PROBE_EXPECTED_MARKERS="BONSAI_SWIFTUI_NETWORK_DEVICE_PROBE_OK" \
IOS_PROBE_LAUNCH_TIMEOUT=45 \
  "$repository_root/tool/ios/run_probe_on_device.sh"

printf '%s\n' "Network spike physical iPhone probe passed"
