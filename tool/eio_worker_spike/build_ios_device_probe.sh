#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
target=iphoneos
APPLICATION_OPAM_FILE="$repository_root/tool/ios/fixtures/application-closure/bonsai_swiftui_ios_closure_fixture.opam"
RUNTIME_CLOSURE_LOCK="$repository_root/vendor/opam-ios/runtime-closure.lock"
BONSAI_SWIFTUI_FEATURES=core,network,sqlite
export APPLICATION_OPAM_FILE RUNTIME_CLOSURE_LOCK BONSAI_SWIFTUI_FEATURES

# shellcheck source=tool/ios/toolchain.lock
. "$repository_root/tool/ios/toolchain.lock"

opam_root="$repository_root/_build/ios/opam-root"
switch="$repository_root/_build/ios/switches/$target"
build_directory="$repository_root/_build/eio-worker-spike/ios-device/build"
output_directory="$repository_root/_build/eio-worker-spike/ios-device"
complete_object="$output_directory/eio_worker_device_probe.o"
app="$output_directory/BonsaiSwiftUIEioProbe.app"
executable="$app/BonsaiSwiftUIEioProbe"
sdk_version=$(xcrun --sdk "$target" --show-sdk-version)
sdk_root=$(xcrun --sdk "$target" --show-sdk-path)

mkdir -p "$build_directory" "$app"

"$repository_root/tool/ios/setup_toolchain.sh" "$target"
"$repository_root/tool/ios/setup_host_dependencies.sh" "$target"
"$repository_root/tool/ios/build_runtime_closure.sh" "$target"

compile() {
  OPAMROOT="$opam_root" \
    SDK="$sdk_version" \
    VER="$IOS_DEPLOYMENT_TARGET" \
    opam exec --switch="$switch" -- \
    ocamlfind -toolchain ios ocamlopt \
      -thread \
      -package cstruct,eio_posix \
      -I "$build_directory" \
      "$@"
}

compile -c -o "$build_directory/bounded_mailbox.cmi" \
  "$repository_root/ocaml/runtime/bounded_mailbox.mli"
compile -c -o "$build_directory/bounded_mailbox.cmx" \
  "$repository_root/ocaml/runtime/bounded_mailbox.ml"
compile -c -o "$build_directory/eio_worker_backend_spike.cmi" \
  "$script_directory/eio_worker_backend_spike.mli"
compile -c -o "$build_directory/eio_worker_backend_spike.cmx" \
  "$script_directory/eio_worker_backend_spike.ml"
compile -c -o "$build_directory/eio_worker_provider_spike.cmx" \
  "$script_directory/eio_worker_provider_spike.ml"
compile -c -o "$build_directory/eio_worker_device_probe.cmi" \
  "$script_directory/eio_worker_device_probe.mli"
compile -c -o "$build_directory/eio_worker_device_probe.cmx" \
  "$script_directory/eio_worker_device_probe.ml"
compile \
  -linkpkg \
  -output-complete-obj \
  -o "$complete_object" \
  "$build_directory/bounded_mailbox.cmx" \
  "$build_directory/eio_worker_backend_spike.cmx" \
  "$build_directory/eio_worker_provider_spike.cmx" \
  "$build_directory/eio_worker_device_probe.cmx"

"$repository_root/tool/ios/verify_macho.sh" \
  "$complete_object" \
  IOS \
  arm64 \
  "$IOS_DEPLOYMENT_TARGET"

cp "$repository_root/tool/ios/probe/Info.plist" "$app/Info.plist"
plutil -replace CFBundleExecutable -string BonsaiSwiftUIEioProbe "$app/Info.plist"
plutil -replace CFBundleIdentifier \
  -string org.bonsai-swiftui.eio-worker-probe \
  "$app/Info.plist"
plutil -replace CFBundleName -string BonsaiSwiftUIEioProbe "$app/Info.plist"
target_standard_library="$switch/_opam/ios-sysroot/lib/ocaml"
xcrun clang \
  -target "$IPHONEOS_TARGET_TRIPLE" \
  -isysroot "$sdk_root" \
  -miphoneos-version-min="$IOS_DEPLOYMENT_TARGET" \
  -fobjc-arc \
  -I "$target_standard_library" \
  "$script_directory/device_probe_host.m" \
  "$complete_object" \
  -framework Foundation \
  -framework Security \
  -framework UIKit \
  -lm \
  -lpthread \
  -o "$executable"

"$repository_root/tool/ios/verify_macho.sh" \
  "$executable" \
  IOS \
  arm64 \
  "$IOS_DEPLOYMENT_TARGET"

printf '%s\n' "Eio Worker iPhoneOS device probe build passed: $app"
