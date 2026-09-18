#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
fixture_root="$script_directory/fixtures/application-closure"
build_root="$repository_root/_build/ios/datascript-worker-device"
application_opam="$fixture_root/bonsai_swiftui_ios_closure_fixture.opam"
closure_lock="$build_root/runtime-closure.lock"
opam_root="$repository_root/_build/ios/opam-root"
switch="$repository_root/_build/ios/switches/iphoneos"
native_target=native/test/datascript_worker/datascript_worker_native_embed.exe.o

fail() {
  printf '%s\n' "DataScript Worker physical-device failure: $1" >&2
  exit 1
}

require_environment() {
  variable_name=$1
  eval "variable_value=\${$variable_name:-}"
  test -n "$variable_value" || fail "required environment variable is unset: $variable_name"
}

require_environment IOS_DEVICE_ID
require_environment IOS_DEVELOPMENT_TEAM
require_environment IOS_BUNDLE_IDENTIFIER
IOS_SIGNING_IDENTITY=${IOS_SIGNING_IDENTITY:-${IOS_DEVELOPMENT_SIGNING_IDENTITY:-Apple Development}}

"$repository_root/tool/ci/ios_device_preflight.sh" "$IOS_DEVICE_ID"
mkdir -p "$build_root"
dune_closure_helper="$repository_root/_build/default/bonsai_swiftui_tool/bin/main.exe"
(cd "$repository_root" && dune build bonsai_swiftui_tool/bin/main.exe)

APPLICATION_OPAM_FILE="$application_opam" \
BONSAI_SWIFTUI_FEATURES=core,sqlite \
SKIP_CLOSURE_VERIFY=true \
  "$script_directory/setup_toolchain.sh" iphoneos
APPLICATION_OPAM_FILE="$application_opam" \
BONSAI_SWIFTUI_FEATURES=core,sqlite \
SKIP_CLOSURE_VERIFY=true \
  "$script_directory/setup_host_dependencies.sh" iphoneos

OPAMROOT="$opam_root" \
HOST_OCAML_SWITCH="$switch" \
APPLICATION_OPAM_FILE="$application_opam" \
BONSAI_SWIFTUI_FEATURES=core,sqlite \
BONSAI_SWIFTUI_DUNE_CLOSURE_HELPER="$dune_closure_helper" \
BONSAI_SWIFTUI_NATIVE_TARGET="$native_target" \
  "$script_directory/resolve_application_closure.sh" \
    iphoneos \
    "$repository_root" \
    "$closure_lock"

sdk_identity=$(
  "$script_directory/resolve_application_closure.sh" \
    --identity \
    --lock "$closure_lock" \
    --features core,sqlite
)
target_lib="$repository_root/_build/ios/sdk-cache/$sdk_identity/lib"
findlib_conf="$repository_root/_build/ios/sdk-cache/$sdk_identity/findlib.conf"
mkdir -p "$target_lib"
RUNTIME_CLOSURE_LOCK="$closure_lock" \
TARGET_LIB="$target_lib" \
BONSAI_SWIFTUI_FEATURES=core,sqlite \
BONSAI_SWIFTUI_CLOSURE_DIGEST="$sdk_identity" \
  "$script_directory/build_runtime_closure.sh" iphoneos
"$script_directory/write_findlib_conf.sh" "$target_lib" "$findlib_conf"


# Host OCAMLPATH must not select macOS archives during cross-compilation.
sdk_version=$(xcrun --sdk iphoneos --show-sdk-version)
dune_build="$build_root/dune"
env -u OCAMLPATH \
  OPAMROOT="$opam_root" OCAMLFIND_CONF="$findlib_conf" \
  SDK="$sdk_version" VER=26.0 \
  opam exec --switch="$switch" -- \
    dune build --root="$repository_root" --build-dir="$dune_build" \
      --profile=release -j4 -xios "$native_target"
complete_object="$dune_build/default.ios/$native_target"
"$script_directory/verify_complete_object.sh" "$complete_object" IOS 26.0 arm64

python3 "$repository_root/tool/build_datascript_worker_probe.py" \
  --native-object "$complete_object" --build-root "$build_root" \
  --bundle-identifier "$IOS_BUNDLE_IDENTIFIER" \
  --development-team "$IOS_DEVELOPMENT_TEAM" \
  --signing-identity "$IOS_SIGNING_IDENTITY"
app="$build_root/host/DerivedData/Build/Products/Release-iphoneos/DataScriptWorkerProbe.app"
"$script_directory/verify_app_bundle.sh" "$app" "$app.dSYM" require-sqlite
codesign --verify --deep --strict "$app"

"$repository_root/tool/ci/ios_device_preflight.sh" "$IOS_DEVICE_ID"
xcrun devicectl device uninstall app \
  --device "$IOS_DEVICE_ID" "$IOS_BUNDLE_IDENTIFIER" >/dev/null 2>&1 || true
xcrun devicectl device install app \
  --device "$IOS_DEVICE_ID" "$app" >/dev/null

launcher_pid=
cleanup() {
  if test -n "$launcher_pid"; then
    kill "$launcher_pid" 2>/dev/null || true
    wait "$launcher_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT HUP INT TERM

wait_for_marker() {
  log=$1
  marker=$2
  deadline=$(( $(date +%s) + 45 ))
  while ! grep -F -- "$marker" "$log" >/dev/null 2>&1; do
    if grep -F 'BONSAI_DATASCRIPT_PROBE_FAILED' "$log" >/dev/null 2>&1 ||
       ! kill -0 "$launcher_pid" 2>/dev/null || test "$(date +%s)" -ge "$deadline"; then
      sed -n '1,260p' "$log" >&2
      fail "physical-device probe did not produce marker: $marker"
    fi
    sleep 1
  done
}

launch_and_wait() {
  log=$1
  expected=$2
  xcrun devicectl device process launch \
    --device "$IOS_DEVICE_ID" --terminate-existing --console --timeout 60 \
    "$IOS_BUNDLE_IDENTIFIER" >"$log" 2>&1 &
  launcher_pid=$!
  wait_for_marker "$log" 'BONSAI_DATASCRIPT_HOST_RUNTIME_STARTED'
  wait_for_marker "$log" "$expected"
  wait_for_marker "$log" 'BONSAI_DERIVING_YOJSON_ROUND_TRIP'
  wait_for_marker "$log" 'BONSAI_RRBVEC_PROBE_PASSED'
  wait_for_marker "$log" 'BONSAI_DATASCRIPT_WORKER_SHUTDOWN'
  wait_for_marker "$log" 'BONSAI_DATASCRIPT_HOST_RUNTIME_DISPOSED'
  wait_for_marker "$log" 'BONSAI_DATASCRIPT_PROBE_PASSED'
  kill "$launcher_pid" 2>/dev/null || true
  wait "$launcher_pid" 2>/dev/null || true
  launcher_pid=
}

launch_and_wait "$build_root/first-launch.log" 'BONSAI_DATASCRIPT_WORKER_PERSISTED'
launch_and_wait "$build_root/second-launch.log" 'BONSAI_DATASCRIPT_WORKER_RESTORED'
printf '%s\n' "DataScript Worker signed physical-iPhone persistence slice passed: $IOS_DEVICE_ID"
