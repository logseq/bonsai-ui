#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

# shellcheck source=tool/ios/toolchain.lock
. "$script_directory/toolchain.lock"

fail() {
  printf '%s\n' "iOS app-bundle verification failure: $1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "required command is unavailable: $1"
}

test "$#" -ge 1 && test "$#" -le 3 ||
  fail "usage: verify_app_bundle.sh <SwiftUI.app> [app.dSYM] [require-sqlite]"

app_path=$1
dsym_path=
sqlite_mode=
if test "${2:-}" = require-sqlite; then
  sqlite_mode=require-sqlite
else
  dsym_path=${2:-}
  sqlite_mode=${3:-}
fi
test -z "$sqlite_mode" || test "$sqlite_mode" = require-sqlite ||
  fail "expected optional mode require-sqlite"
test -d "$app_path" || fail "application bundle does not exist: $app_path"
executable=$(plutil -extract CFBundleExecutable raw -o - "$app_path/Info.plist")
case "$executable" in
  '' | */*) fail "invalid application executable name" ;;
esac
binary_path="$app_path/$executable"
privacy_manifest="$app_path/BonsaiSwiftUI_BonsaiSwiftUI.bundle/PrivacyInfo.xcprivacy"

for command_name in file jq nm plutil sed sort xcrun; do
  require_command "$command_name"
done

test -d "$app_path" || fail "application bundle does not exist: $app_path"
test -f "$binary_path" || fail "application executable does not exist: $binary_path"
test -f "$privacy_manifest" || fail "application privacy manifest is missing"

"$script_directory/verify_macho.sh" \
  "$binary_path" \
  IOS \
  arm64 \
  "$IOS_DEPLOYMENT_TARGET"

file "$binary_path" | grep -F 'Mach-O 64-bit executable arm64' >/dev/null ||
  fail "expected a native arm64 application executable"

xcrun otool -L "$binary_path" |
  sed -n '2,$p' |
  sed 's/^[[:space:]]*//' |
  while IFS= read -r dependency; do
    case "$dependency" in
      @* | /usr/lib/* | /System/Library/*) ;;
      '') ;;
      *) fail "prohibited application dependency: $dependency" ;;
    esac
  done

if test "$sqlite_mode" = require-sqlite; then
  xcrun otool -L "$binary_path" |
    grep -F '/usr/lib/libsqlite3.dylib' >/dev/null ||
    fail "application does not require Apple system libsqlite3"
  nm -u "$binary_path" |
    awk '{ print $1 }' |
    grep -E '^_sqlite3_' >/dev/null ||
    fail "application does not reference sqlite3 symbols"
else
  if xcrun otool -L "$binary_path" |
    grep -F '/usr/lib/libsqlite3.dylib' >/dev/null; then
    fail "application unexpectedly requires Apple system libsqlite3"
  fi
fi

# A static SwiftUI App exports its own entrypoints as well. Check the live
# runtime boundary here; verify_complete_object.sh checks the complete ABI
# before the linker removes unused functions from the application.
defined_symbols=$(nm -gU "$binary_path" | awk '{ print $3 }')
for symbol in _bs_runtime_create _bs_runtime_pump _bs_runtime_destroy; do
  printf '%s\n' "$defined_symbols" | grep -Fx "$symbol" >/dev/null ||
    fail "application does not define $symbol"
done
if printf '%s\n' "$defined_symbols" | grep -E '^_bf_' >/dev/null; then
  fail "application still defines an obsolete Flutter ABI symbol"
fi

prohibited_process_symbols=$(
  nm -u "$binary_path" |
    awk '{ print $1 }' |
    grep -E \
      '^_(fork|execv|execve|execvp|posix_spawn|posix_spawnp|popen|system)$' ||
    true
)
test -z "$prohibited_process_symbols" ||
  fail "application references prohibited process APIs: $prohibited_process_symbols"

undefined_symbols=$(
  nm -u "$binary_path" |
    awk '{ print $1 }'
)
printf '%s\n' "$undefined_symbols" |
  grep -E '^_(fstat|lstat|stat)$' >/dev/null ||
  fail "file-timestamp reason is declared without a matching linked API"
printf '%s\n' "$undefined_symbols" |
  grep -E '^_(clock_gettime_nsec_np|mach_absolute_time)$' >/dev/null ||
  fail "system-boot-time reason is declared without a matching linked API"

plutil -lint "$privacy_manifest" >/dev/null ||
  fail "application privacy manifest is invalid"
privacy_json=$(
  plutil -convert json -o - "$privacy_manifest"
)
printf '%s\n' "$privacy_json" |
  jq -e '
    .NSPrivacyTracking == false
    and .NSPrivacyCollectedDataTypes == []
    and (
      .NSPrivacyAccessedAPITypes
      | length == 2
    )
    and any(
      .NSPrivacyAccessedAPITypes[];
      .NSPrivacyAccessedAPIType
        == "NSPrivacyAccessedAPICategoryFileTimestamp"
      and .NSPrivacyAccessedAPITypeReasons == ["C617.1"]
    )
    and any(
      .NSPrivacyAccessedAPITypes[];
      .NSPrivacyAccessedAPIType
        == "NSPrivacyAccessedAPICategorySystemBootTime"
      and .NSPrivacyAccessedAPITypeReasons == ["35F9.1"]
    )
  ' >/dev/null ||
  fail "application privacy manifest does not match linked required-reason APIs"

if test -n "$dsym_path"; then
  test -f "$dsym_path/Contents/Resources/DWARF/$executable" ||
    fail "application dSYM does not exist: $dsym_path"
  binary_uuid=$(xcrun dwarfdump --uuid "$binary_path" | awk '{ print $2 }')
  dsym_uuid=$(xcrun dwarfdump --uuid "$dsym_path" | awk '{ print $2 }')
  test "$binary_uuid" = "$dsym_uuid" ||
    fail "application and dSYM UUIDs do not match"
fi

printf '%s\n' "iOS app-bundle verification passed: $app_path"
