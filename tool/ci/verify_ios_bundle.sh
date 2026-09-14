#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

fail() {
  printf '%s\n' "signed iOS bundle verification failure: $1" >&2
  exit 1
}

if test "$#" -lt 2 || test "$#" -gt 4; then
  fail "usage: tool/ci/verify_ios_bundle.sh <SwiftUI.app> <development|distribution> [app.dSYM] [require-sqlite]"
fi

app_bundle=$1
signing_kind=$2
dsym=${3:-}
sqlite_mode=${4:-}
if test "$dsym" = require-sqlite; then
  test -z "$sqlite_mode" || fail "require-sqlite must be the last argument"
  dsym=
  sqlite_mode=require-sqlite
fi
test -z "$sqlite_mode" || test "$sqlite_mode" = require-sqlite ||
  fail "expected optional mode require-sqlite"

case "$signing_kind" in
  development | distribution)
    ;;
  *)
    fail "signing kind must be development or distribution"
    ;;
esac

"$repository_root/tool/ios/verify_app_bundle.sh" "$app_bundle" "$dsym" "$sqlite_mode"

profile="$app_bundle/embedded.mobileprovision"
test -f "$profile" || fail "embedded provisioning profile is missing"

codesign --verify --deep --strict "$app_bundle" >/dev/null 2>&1 ||
  fail "application code signature is invalid"

work_root="$repository_root/_build/ios/signed-bundle-audit"
mkdir -p "$work_root"
work_directory=$(mktemp -d "$work_root/run.XXXXXX")
decoded_profile="$work_directory/profile.plist"
app_entitlements="$work_directory/app-entitlements.plist"

security cms -D -i "$profile" >"$decoded_profile" 2>/dev/null ||
  fail "embedded provisioning profile cannot be decoded"
codesign -d --entitlements - --xml "$app_bundle" >"$app_entitlements" 2>/dev/null ||
  fail "application entitlements cannot be extracted"

plist_value() {
  plist_path=$1
  plist_key=$2
  plist_type=$3
  plist_label=$4
  plutil -extract "$plist_key" raw -expect "$plist_type" -o - "$plist_path" 2>/dev/null ||
    fail "missing or invalid $plist_label"
}

certificate_prefix="$work_directory/signing-certificate"
codesign -d --extract-certificates="$certificate_prefix" "$app_bundle" >/dev/null 2>&1 ||
  fail "application signing certificate cannot be extracted"
test -s "${certificate_prefix}0" || fail "application has no signing certificate"
certificate_count=$(plist_value "$decoded_profile" DeveloperCertificates array "profile signing certificates")
certificate_index=0
certificate_authorized=false
while test "$certificate_index" -lt "$certificate_count"; do
  certificate=$(plist_value "$decoded_profile" "DeveloperCertificates.$certificate_index" data "profile signing certificate")
  printf '%s' "$certificate" | base64 -D >"$work_directory/profile-certificate" ||
    fail "invalid profile signing certificate"
  if cmp -s "${certificate_prefix}0" "$work_directory/profile-certificate"; then
    certificate_authorized=true
    break
  fi
  certificate_index=$((certificate_index + 1))
done
test "$certificate_authorized" = true ||
  fail "application signing certificate is not authorized by the profile"

profile_team=$(
  plist_value "$decoded_profile" TeamIdentifier.0 string "profile Team ID"
)
profile_app_id=$(
  plist_value "$decoded_profile" Entitlements.application-identifier string "profile App ID"
)
app_team=$(
  plist_value "$app_entitlements" 'com\.apple\.developer\.team-identifier' string "application Team ID"
)
app_id=$(
  plist_value "$app_entitlements" application-identifier string "application App ID"
)

test "$profile_team" = "$app_team" ||
  fail "application and provisioning-profile Team IDs differ"
case "$profile_app_id" in
  *.\*)
    allowed_prefix=${profile_app_id%\*}
    case "$app_id" in
      "$allowed_prefix"*) ;;
      *) fail "application App ID is not covered by the provisioning profile" ;;
    esac
    ;;
  *) test "$app_id" = "$profile_app_id" ||
       fail "application and provisioning-profile App IDs differ" ;;
esac

app_prefix=$(plist_value "$decoded_profile" ApplicationIdentifierPrefix.0 string "profile App ID prefix")
bundle_identifier=$(plist_value "$app_bundle/Info.plist" CFBundleIdentifier string "bundle identifier")
case "$bundle_identifier" in
  '' | *[!A-Za-z0-9.-]* | .* | *. | *..*) fail "invalid application bundle identifier" ;;
esac
test "$app_id" = "$app_prefix.$bundle_identifier" ||
  fail "signed App ID does not match the application bundle identifier"

expiration=$(plist_value "$decoded_profile" ExpirationDate date "profile expiration date")
expiration_epoch=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$expiration" '+%s' 2>/dev/null) ||
  fail "invalid profile expiration date"
test "$expiration_epoch" -gt "$(date -u '+%s')" || fail "provisioning profile has expired"

profile_debuggable=$(
  plist_value "$decoded_profile" Entitlements.get-task-allow bool "profile get-task-allow entitlement"
)
app_debuggable=$(
  plist_value "$app_entitlements" get-task-allow bool "application get-task-allow entitlement"
)
test "$profile_debuggable" = "$app_debuggable" ||
  fail "application and provisioning-profile get-task-allow entitlements differ"

case "$signing_kind:$app_debuggable" in
  development:true | distribution:false)
    ;;
  *)
    fail "get-task-allow does not match the required signing kind"
    ;;
esac

printf '%s\n' "signed iOS application bundle verification passed"
