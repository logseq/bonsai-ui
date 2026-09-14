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

minimum_version=$IOS_DEPLOYMENT_TARGET
opam_root="$repository_root/_build/ios/opam-root"
switch="$repository_root/_build/ios/switches/$target"
build_directory="$repository_root/_build/eio-worker-spike/ios-build"
output_directory="$repository_root/_build/eio-worker-spike/ios/$target/arm64"
complete_object="$output_directory/eio_worker_backend_spike.o"
probe_executable="$output_directory/eio_worker_backend_spike_probe"
sdk_version=$(xcrun --sdk "$target" --show-sdk-version)
sdk_root=$(xcrun --sdk "$target" --show-sdk-path)

mkdir -p "$build_directory" "$output_directory"

"$repository_root/tool/ios/setup_toolchain.sh" "$target"
"$repository_root/tool/ios/setup_host_dependencies.sh" "$target"
"$repository_root/tool/ios/build_runtime_closure.sh" "$target"

compile() {
  OPAMROOT="$opam_root" \
    SDK="$sdk_version" \
    VER="$minimum_version" \
    opam exec --switch="$switch" -- \
    ocamlfind -toolchain ios ocamlopt \
      -thread \
      -package eio_posix \
      -I "$build_directory" \
      "$@"
}

compile \
  -c \
  -o "$build_directory/bounded_mailbox.cmi" \
  "$repository_root/ocaml/runtime/bounded_mailbox.mli"
compile \
  -c \
  -o "$build_directory/bounded_mailbox.cmx" \
  "$repository_root/ocaml/runtime/bounded_mailbox.ml"
compile \
  -c \
  -o "$build_directory/eio_worker_backend_spike.cmi" \
  "$script_directory/eio_worker_backend_spike.mli"
compile \
  -c \
  -o "$build_directory/eio_worker_backend_spike.cmx" \
  "$script_directory/eio_worker_backend_spike.ml"
compile \
  -linkpkg \
  -output-complete-obj \
  -o "$complete_object" \
  "$build_directory/bounded_mailbox.cmx" \
  "$build_directory/eio_worker_backend_spike.cmx"

"$repository_root/tool/ios/verify_macho.sh" \
  "$complete_object" \
  IOS \
  arm64 \
  "$minimum_version"

target_standard_library="$switch/_opam/ios-sysroot/lib/ocaml"
xcrun clang \
  -target "arm64-apple-ios$minimum_version" \
  -isysroot "$sdk_root" \
  -miphoneos-version-min="$minimum_version" \
  -I "$target_standard_library" \
  "$script_directory/probe_host.c" \
  "$complete_object" \
  -framework Foundation \
  -framework Security \
  -lm \
  -lpthread \
  -o "$probe_executable"

"$repository_root/tool/ios/verify_macho.sh" \
  "$probe_executable" \
  IOS \
  arm64 \
  "$minimum_version"

object_size=$(stat -f '%z' "$complete_object")
printf '%s\n' "Eio Worker iPhoneOS complete-object spike passed"
printf '%s\n' "complete object: $complete_object"
printf '%s\n' "complete object bytes: $object_size"
