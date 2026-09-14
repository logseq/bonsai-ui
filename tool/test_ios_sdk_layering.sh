#!/bin/sh

set -u

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd)
sdk_lock="$repository_root/tool/ios/sdk_repository.lock"
sdk_repository="$repository_root/tool/ios/opam-repository/0.1.0"
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/bonsai-swiftui-sdk-layering.XXXXXX")

cleanup() {
  rm -rf "$temporary_directory"
}

trap cleanup EXIT HUP INT TERM

failures=0

fail() {
  printf '%s\n' "iOS SDK layering test failure: $1" >&2
  failures=$((failures + 1))
}

require_file() {
  test -f "$1" || fail "missing $1"
}

require_text() {
  haystack=$1
  needle=$2
  label=$3
  printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null ||
    fail "$label does not contain: $needle"
}

reject_text() {
  haystack=$1
  needle=$2
  label=$3
  if printf '%s' "$haystack" | grep -F -- "$needle" >/dev/null; then
    fail "$label contains forbidden text: $needle"
  fi
}

require_text "$(cat "$sdk_lock")" \
  "SDK_RUNTIME_PACKAGE_VERSION='" \
  "SDK repository lock"

# Load the package versions only after reporting a useful missing-feature failure.
SDK_RUNTIME_PACKAGE_VERSION=$(
  sed -n "s/^SDK_RUNTIME_PACKAGE_VERSION='\([^']*\)'$/\1/p" "$sdk_lock"
)
SDK_PACKAGE_VERSION=$(
  sed -n "s/^SDK_PACKAGE_VERSION='\([^']*\)'$/\1/p" "$sdk_lock"
)

if test -z "$SDK_RUNTIME_PACKAGE_VERSION" || test -z "$SDK_PACKAGE_VERSION"; then
  fail "SDK layer package versions are incomplete"
else
  runtime_package="$sdk_repository/packages/bonsai_swiftui_ios_runtime_sdk/bonsai_swiftui_ios_runtime_sdk.$SDK_RUNTIME_PACKAGE_VERSION"
  framework_package="$sdk_repository/packages/bonsai_swiftui_ios_sdk/bonsai_swiftui_ios_sdk.$SDK_PACKAGE_VERSION"
  runtime_opam="$runtime_package/opam"
  framework_opam="$framework_package/opam"

  require_file "$runtime_opam"
  require_file "$framework_opam"
  require_file "$runtime_package/files/build-runtime-sdk.sh"
  require_file "$runtime_package/files/build-runtime-closure.sh"
  require_file "$runtime_package/files/build-runtime-package.sh"
  require_file "$runtime_package/files/supported-closure.lock"
  require_file "$framework_package/files/build-installed-framework.sh"
  require_file "$framework_package/files/manifest.sexp"
  require_file "$framework_package/files/package-lock.sexp"

  if test -f "$runtime_opam"; then
    runtime_metadata=$(cat "$runtime_opam")
    require_text "$runtime_metadata" \
      '["sh" "./build-runtime-sdk.sh" "%{switch}%" "%{prefix}%"]' \
      "runtime SDK package"
    require_text "$runtime_metadata" \
      'runtime-bonsai-' \
      "runtime SDK source closure"
    reject_text "$runtime_metadata" \
      'bonsai_swiftui.tar.gz' \
      "runtime SDK package"
    reject_text "$runtime_metadata" \
      'build-installed-framework.sh' \
      "runtime SDK package"
  fi

  if test -f "$runtime_package/files/supported-closure.lock"; then
    reject_text \
      "$(cat "$runtime_package/files/supported-closure.lock")" \
      'bonsai_swiftui|' \
      "runtime SDK closure"
  fi

  if test -f "$framework_opam"; then
    framework_metadata=$(cat "$framework_opam")
    require_text "$framework_metadata" \
      'extra-source "bonsai_swiftui.tar.gz"' \
      "framework SDK package"
    require_text "$framework_metadata" \
      "\"bonsai_swiftui_ios_runtime_sdk\" {= \"$SDK_RUNTIME_PACKAGE_VERSION\"}" \
      "framework runtime dependency"
    require_text "$framework_metadata" \
      '["sh" "./build-installed-framework.sh" "%{switch}%" "%{prefix}%"]' \
      "framework SDK package"
    reject_text "$framework_metadata" \
      'runtime-bonsai-' \
      "framework SDK package"
    reject_text "$framework_metadata" \
      'build-runtime-closure.sh' \
      "framework SDK package"
  fi
fi

framework_builder="$repository_root/tool/ios/build_installed_framework.sh"
framework_updater="$repository_root/tool/ios/update_framework_sdk.sh"
require_file "$framework_builder"
require_file "$framework_updater"

if test -f "$framework_builder"; then
  framework_builder_text=$(cat "$framework_builder")
  require_text "$framework_builder_text" \
    '-p bonsai_swiftui' \
    "framework-only builder"
  reject_text "$framework_builder_text" \
    'build_runtime_closure' \
    "framework-only builder"
  reject_text "$framework_builder_text" \
    'build-runtime-closure' \
    "framework-only builder"
fi

if test -f "$framework_updater" && test -n "$SDK_RUNTIME_PACKAGE_VERSION"; then
  fake_bin="$temporary_directory/bin"
  opam_log="$temporary_directory/opam.log"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/opam" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$OPAM_LOG"
case "$*" in
  *"switch list --short"*) printf '%s\n' bonsai-swiftui-ios ;;
  *"list --switch=bonsai-swiftui-ios"*"bonsai_swiftui_ios_runtime_sdk"*)
    printf '%s\n' "$EXPECTED_RUNTIME_VERSION"
    ;;
esac
EOF
  chmod +x "$fake_bin/opam"

  if ! PATH="$fake_bin:$PATH" \
    OPAM_LOG="$opam_log" \
    EXPECTED_RUNTIME_VERSION="$SDK_RUNTIME_PACKAGE_VERSION" \
    "$framework_updater" >"$temporary_directory/update.out" 2>"$temporary_directory/update.err"
  then
    cat "$temporary_directory/update.err" >&2
    fail "framework-only updater failed"
  fi

  if test -f "$opam_log"; then
    update_actions=$(cat "$opam_log")
    require_text "$update_actions" \
      "install --switch=bonsai-swiftui-ios --yes bonsai_swiftui_ios_sdk.$SDK_PACKAGE_VERSION" \
      "framework-only update actions"
    reject_text "$update_actions" \
      'switch remove' \
      "framework-only update actions"
    reject_text "$update_actions" \
      "install --switch=bonsai-swiftui-ios --yes bonsai_swiftui_ios_runtime_sdk" \
      "framework-only update actions"
  fi

  mismatch_log="$temporary_directory/mismatch.log"
  if PATH="$fake_bin:$PATH" \
    OPAM_LOG="$mismatch_log" \
    EXPECTED_RUNTIME_VERSION=0.0.0-mismatch \
    "$framework_updater" >"$temporary_directory/mismatch.out" 2>"$temporary_directory/mismatch.err"
  then
    fail "framework updater accepted a mismatched runtime SDK"
  elif ! grep -F 'requires a full iPhoneOS toolchain replacement' \
    "$temporary_directory/mismatch.err" >/dev/null; then
    fail "runtime mismatch did not request a full toolchain replacement"
  fi
fi

if test "$failures" -ne 0; then
  printf '%s\n' "iOS SDK layering tests failed with $failures violation(s)" >&2
  exit 1
fi

printf '%s\n' "iOS SDK layering tests passed"
