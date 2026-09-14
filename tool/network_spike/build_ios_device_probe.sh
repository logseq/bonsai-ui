#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
target=iphoneos

# shellcheck source=tool/ios/toolchain.lock
. "$repository_root/tool/ios/toolchain.lock"

opam_root="$repository_root/_build/ios/opam-root"
switch="$repository_root/_build/ios/switches/$target"
build_directory="$repository_root/_build/network-spike/ios-device/build"
output_directory="$repository_root/_build/network-spike/ios-device"
complete_object="$output_directory/network_spike_device_probe.o"
app="$output_directory/BonsaiSwiftUINetworkProbe.app"
executable="$app/BonsaiSwiftUINetworkProbe"
sdk_version=$(xcrun --sdk "$target" --show-sdk-version)
sdk_root=$(xcrun --sdk "$target" --show-sdk-path)

compile_packages="bigstringaf,ca-certs-nss,cstruct,digestif,domain-name,eio,eio.core,eio.unix,eio_posix,gluten,gluten-eio,httpun,httpun-eio,httpun-ws,mirage-crypto-rng,mirage-crypto-rng.unix,ptime,tls,tls-eio,unix,x509"
link_packages="digestif.c,mirage-ptime.unix,bigstringaf,ca-certs-nss,cstruct,domain-name,eio,eio.core,eio.unix,eio_posix,gluten,gluten-eio,httpun,httpun-eio,httpun-ws,mirage-crypto-rng.unix,ptime,tls,tls-eio,unix,x509"

mkdir -p "$build_directory" "$app"

compile() {
  OPAMROOT="$opam_root" \
    SDK="$sdk_version" \
    VER="$IOS_DEPLOYMENT_TARGET" \
    opam exec --switch="$switch" -- \
    ocamlfind -toolchain ios ocamlopt \
      -thread \
      -package "$compile_packages" \
      -I "$build_directory" \
      "$@"
}

compile -c -o "$build_directory/network_spike.cmi" \
  "$script_directory/network_spike.mli"
compile -c -o "$build_directory/network_spike.cmx" \
  "$script_directory/network_spike.ml"
compile -c -o "$build_directory/network_spike_device_probe.cmx" \
  "$script_directory/network_spike_device_probe.ml"

OPAMROOT="$opam_root" \
  SDK="$sdk_version" \
  VER="$IOS_DEPLOYMENT_TARGET" \
  opam exec --switch="$switch" -- \
  ocamlfind -toolchain ios ocamlopt \
    -thread \
    -linkpkg \
    -output-complete-obj \
    -package "$link_packages" \
    -I "$build_directory" \
    -o "$complete_object" \
    "$build_directory/network_spike.cmx" \
    "$build_directory/network_spike_device_probe.cmx"

"$repository_root/tool/ios/verify_macho.sh" \
  "$complete_object" \
  IOS \
  arm64 \
  "$IOS_DEPLOYMENT_TARGET"

if nm -u "$complete_object" | rg -i 'ssl|libcrypto|openssl|securetransport'; then
  printf '%s\n' "Network spike introduced a prohibited TLS backend" >&2
  exit 1
fi

cp "$repository_root/tool/ios/probe/Info.plist" "$app/Info.plist"
cp "$script_directory/localhost-cert.pem" "$app/localhost-cert.pem"
cp "$script_directory/localhost-key.pem" "$app/localhost-key.pem"
plutil -replace CFBundleExecutable -string BonsaiSwiftUINetworkProbe "$app/Info.plist"
plutil -replace CFBundleIdentifier \
  -string org.bonsai-swiftui.network-probe \
  "$app/Info.plist"
plutil -replace CFBundleName -string BonsaiSwiftUINetworkProbe "$app/Info.plist"

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

printf '%s\n' "Network spike iPhoneOS device probe build passed: $app"
