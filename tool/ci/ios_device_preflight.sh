#!/bin/sh

set -eu

fail() {
  printf '%s\n' "iOS device preflight failure: $1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "required command is unavailable: $1"
}

if test "$#" -lt 1 || test "$#" -gt 2 || test -z "$1"; then
  fail "usage: tool/ci/ios_device_preflight.sh <physical-device-id> [--require-signing]"
fi

device_id=$1
signing_required=false
if test "$#" -eq 2; then
  test "$2" = "--require-signing" ||
    fail "the only supported optional argument is --require-signing"
  signing_required=true
fi
script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
work_root="$repository_root/_build/ios/device-preflight"
mkdir -p "$work_root"
work_directory=$(mktemp -d "$work_root/run.XXXXXX")
device_details="$work_directory/device-details.json"
lock_state="$work_directory/lock-state.json"

require_command jq
require_command xcrun

xcrun devicectl device info details \
  --device "$device_id" \
  --quiet \
  --timeout 30 \
  --json-output "$device_details" >/dev/null ||
  fail "CoreDevice could not connect to the explicitly selected device"

jq -e '
  .info.outcome == "success"
  and .result.hardwareProperties.reality == "physical"
  and .result.hardwareProperties.platform == "iOS"
  and (.result.hardwareProperties.udid | type == "string" and length > 0)
  and (.result.hardwareProperties.supportedCPUTypes // [] | any(.name == "arm64"))
  and .result.connectionProperties.pairingState == "paired"
  and .result.deviceProperties.developerModeStatus == "enabled"
  and .result.deviceProperties.ddiServicesAvailable == true
  and (.result.deviceProperties.osVersionNumber // ""
       | select(type == "string")
       | select(test("^[0-9]+(\\.[0-9]+){0,2}$"))
       | split(".")[0] | tonumber >= 18)
' "$device_details" >/dev/null ||
  fail "the device must support physical iOS 18+ arm64, be paired and in Developer Mode, and have DDI services available"

# CoreDevice accepts names too; CI requires an exact UUID or hardware UDID.
jq -e --arg device_id "$device_id" '
  ($device_id | ascii_downcase) as $selected
  | (.result.identifier | ascii_downcase) == $selected
    or (.result.hardwareProperties.udid | ascii_downcase) == $selected
' "$device_details" >/dev/null ||
  fail "CoreDevice did not return the explicitly selected device UUID or UDID"
device_udid=$(jq -er '.result.hardwareProperties.udid' "$device_details")

xcrun devicectl device info lockState \
  --device "$device_id" \
  --quiet \
  --timeout 30 \
  --json-output "$lock_state" >/dev/null ||
  fail "CoreDevice could not read the selected device lock state"

jq -e '
  .info.outcome == "success"
  and .result.unlockedSinceBoot == true
  and .result.passcodeRequired == false
' "$lock_state" >/dev/null ||
  fail "the selected device must be currently unlocked"

require_environment() {
  variable_name=$1
  eval "variable_value=\${$variable_name:-}"
  test -n "$variable_value" ||
    fail "required signing environment variable is unset: $variable_name"
}

validate_profile() {
  profile_path=$1
  expected_debuggable=$2
  profile_label=$3
  decoded_profile="$work_directory/$profile_label.plist"

  test -f "$profile_path" ||
    fail "$profile_label provisioning profile is missing"
  security cms -D -i "$profile_path" >"$decoded_profile"

  profile_team=$(
    plutil -extract TeamIdentifier.0 raw -o - "$decoded_profile"
  )
  test "$profile_team" = "$IOS_DEVELOPMENT_TEAM" ||
    fail "$profile_label provisioning profile has the wrong Team ID"

  profile_app_id=$(
    plutil -extract Entitlements.application-identifier raw -o - \
      "$decoded_profile"
  )
  case "$profile_app_id" in
    *."$IOS_BUNDLE_IDENTIFIER" | *.\*)
      ;;
    *)
      fail "$profile_label provisioning profile does not cover the bundle identifier"
      ;;
  esac

  plutil -extract ProvisionedDevices json -o - "$decoded_profile" |
    jq -e --arg device_udid "$device_udid" '
      ($device_udid | ascii_downcase) as $selected
      | any(ascii_downcase == $selected)
    ' >/dev/null ||
    fail "$profile_label provisioning profile does not include the selected device"

  profile_debuggable=$(
    plutil -extract Entitlements.get-task-allow raw -o - "$decoded_profile"
  )
  test "$profile_debuggable" = "$expected_debuggable" ||
    fail "$profile_label provisioning profile has the wrong get-task-allow entitlement"

  expiration=$(
    plutil -extract ExpirationDate raw -o - "$decoded_profile"
  )
  expiration_epoch=$(
    date -j -f '%Y-%m-%dT%H:%M:%SZ' "$expiration" '+%s' 2>/dev/null ||
      date -j -f '%Y-%m-%d %H:%M:%S %z' "$expiration" '+%s' 2>/dev/null
  )
  minimum_expiration_epoch=$(( $(date '+%s') + 2592000 ))
  test "$expiration_epoch" -ge "$minimum_expiration_epoch" ||
    fail "$profile_label provisioning profile expires in less than 30 days"
}

if test "$signing_required" = true; then
  require_command openssl
  require_command plutil
  require_command security
  require_environment IOS_DEVELOPMENT_TEAM
  require_environment IOS_BUNDLE_IDENTIFIER
  require_environment IOS_DEVELOPMENT_PROFILE_PATH
  require_environment IOS_DISTRIBUTION_PROFILE_PATH

  development_identity=${IOS_DEVELOPMENT_SIGNING_IDENTITY:-Apple Development}
  distribution_identity=${IOS_DISTRIBUTION_SIGNING_IDENTITY:-Apple Distribution}

  security find-certificate -c "$development_identity" -p |
    openssl x509 -checkend 2592000 -noout >/dev/null 2>&1 ||
    fail "a valid development signing certificate with at least 30 days remaining is required"
  security find-certificate -c "$distribution_identity" -p |
    openssl x509 -checkend 2592000 -noout >/dev/null 2>&1 ||
    fail "a valid distribution signing certificate with at least 30 days remaining is required"

  validate_profile "$IOS_DEVELOPMENT_PROFILE_PATH" true development
  validate_profile "$IOS_DISTRIBUTION_PROFILE_PATH" false distribution
fi

printf '%s\n' "iOS physical-device preflight passed"
