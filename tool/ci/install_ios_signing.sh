#!/bin/sh

set -eu

fail() {
  printf '%s\n' "iOS signing setup failure: $1" >&2
  exit 1
}

require_environment() {
  variable_name=$1
  eval "variable_value=\${$variable_name:-}"
  test -n "$variable_value" ||
    fail "required environment variable is unset: $variable_name"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "required command is unavailable: $1"
}

require_safe_runtime_directory() {
  case "$1" in
    /Users/* | /private/var/* | /var/*)
      ;;
    *)
      fail "RUNNER_TEMP must resolve to a private temporary directory"
      ;;
  esac
}

decode_base64() {
  encoded_value=$1
  destination=$2
  printf '%s' "$encoded_value" | base64 --decode >"$destination"
}

cleanup() {
  runtime_directory=${RUNNER_TEMP:-}
  test -n "$runtime_directory" || return 0
  require_safe_runtime_directory "$runtime_directory"

  manifest="$runtime_directory/bonsai-swiftui-ios-signing/profiles.manifest"
  if test -f "$manifest"; then
    while IFS= read -r installed_profile; do
      case "$installed_profile" in
        */Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision)
          rm -f -- "$installed_profile"
          ;;
        *)
          fail "refusing to remove an unexpected provisioning-profile path"
          ;;
      esac
    done <"$manifest"
  fi

  keychain_path="$runtime_directory/bonsai-swiftui-ios-signing.keychain-db"
  if test -f "$keychain_path"; then
    security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
  fi

  signing_directory="$runtime_directory/bonsai-swiftui-ios-signing"
  keychain_manifest="$signing_directory/keychains.manifest"
  if test -f "$keychain_manifest"; then
    set --
    while IFS= read -r original_keychain; do
      set -- "$@" "$original_keychain"
    done <"$keychain_manifest"
    if test "$#" -gt 0; then
      security list-keychains -d user -s "$@"
    fi
  fi
  if test -d "$signing_directory"; then
    find "$signing_directory" -type f -delete
    rmdir "$signing_directory" 2>/dev/null || true
  fi
}

install() {
  require_command base64
  require_command plutil
  require_command security

  require_environment RUNNER_TEMP
  require_environment IOS_KEYCHAIN_PASSWORD
  require_environment IOS_DEVELOPMENT_CERTIFICATE_P12_BASE64
  require_environment IOS_DEVELOPMENT_CERTIFICATE_PASSWORD
  require_environment IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64
  require_environment IOS_DISTRIBUTION_CERTIFICATE_PASSWORD
  require_environment IOS_DEVELOPMENT_PROFILE_BASE64
  require_environment IOS_DISTRIBUTION_PROFILE_BASE64
  require_environment IOS_EXPORT_OPTIONS_PLIST_BASE64

  require_safe_runtime_directory "$RUNNER_TEMP"
  signing_directory="$RUNNER_TEMP/bonsai-swiftui-ios-signing"
  keychain_path="$RUNNER_TEMP/bonsai-swiftui-ios-signing.keychain-db"
  profile_directory="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
  manifest="$signing_directory/profiles.manifest"
  keychain_manifest="$signing_directory/keychains.manifest"

  mkdir -p "$signing_directory" "$profile_directory"
  : >"$manifest"
  security list-keychains -d user |
    sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//' \
      >"$keychain_manifest"

  development_certificate="$signing_directory/development.p12"
  distribution_certificate="$signing_directory/distribution.p12"
  development_profile="$signing_directory/development.mobileprovision"
  distribution_profile="$signing_directory/distribution.mobileprovision"
  export_options="$signing_directory/ExportOptions.plist"

  decode_base64 \
    "$IOS_DEVELOPMENT_CERTIFICATE_P12_BASE64" \
    "$development_certificate"
  decode_base64 \
    "$IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64" \
    "$distribution_certificate"
  decode_base64 "$IOS_DEVELOPMENT_PROFILE_BASE64" "$development_profile"
  decode_base64 "$IOS_DISTRIBUTION_PROFILE_BASE64" "$distribution_profile"
  decode_base64 "$IOS_EXPORT_OPTIONS_PLIST_BASE64" "$export_options"

  security create-keychain \
    -p "$IOS_KEYCHAIN_PASSWORD" \
    "$keychain_path" >/dev/null
  security set-keychain-settings -lut 21600 "$keychain_path"
  security unlock-keychain \
    -p "$IOS_KEYCHAIN_PASSWORD" \
    "$keychain_path"
  security import "$development_certificate" \
    -k "$keychain_path" \
    -P "$IOS_DEVELOPMENT_CERTIFICATE_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null
  security import "$distribution_certificate" \
    -k "$keychain_path" \
    -P "$IOS_DISTRIBUTION_CERTIFICATE_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null
  security set-key-partition-list \
    -S apple-tool:,apple: \
    -s \
    -k "$IOS_KEYCHAIN_PASSWORD" \
    "$keychain_path" >/dev/null
  security list-keychains -d user -s "$keychain_path"

  development_profile_path=
  distribution_profile_path=
  for source_profile in "$development_profile" "$distribution_profile"; do
    decoded_profile="$source_profile.plist"
    security cms -D -i "$source_profile" >"$decoded_profile"
    profile_uuid=$(
      plutil -extract UUID raw -o - "$decoded_profile"
    )
    installed_profile="$profile_directory/$profile_uuid.mobileprovision"
    if test ! -e "$installed_profile"; then
      cp "$source_profile" "$installed_profile"
      printf '%s\n' "$installed_profile" >>"$manifest"
    fi
    if test "$source_profile" = "$development_profile"; then
      development_profile_path=$installed_profile
    else
      distribution_profile_path=$installed_profile
    fi
  done

  if test -n "${GITHUB_ENV:-}"; then
    printf '%s\n' \
      "IOS_EXPORT_OPTIONS_PLIST=$export_options" \
      "IOS_DEVELOPMENT_PROFILE_PATH=$development_profile_path" \
      "IOS_DISTRIBUTION_PROFILE_PATH=$distribution_profile_path" \
      >>"$GITHUB_ENV"
  fi

  printf '%s\n' "iOS signing material installed in an ephemeral keychain"
}

case "${1:-}" in
  install)
    install
    ;;
  cleanup)
    cleanup
    ;;
  *)
    fail "usage: tool/ci/install_ios_signing.sh <install|cleanup>"
    ;;
esac
