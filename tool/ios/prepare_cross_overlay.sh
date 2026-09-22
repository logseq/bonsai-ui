#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

# shellcheck source=tool/ios/toolchain.lock
. "$script_directory/toolchain.lock"

cross_repository=${1:-}
overlay_repository=${2:-}
template_package="$repository_root/vendor/opam-ios/$OCAML_IOS_PACKAGE"
base_package="$cross_repository/packages/ocaml-ios64.5.0.0"
target_package="$overlay_repository/packages/$OCAML_IOS_PACKAGE"

fail() {
  printf '%s\n' "iOS cross overlay preparation failure: $1" >&2
  exit 1
}

test -n "$cross_repository" ||
  fail "the opam-cross-ios checkout path is required"
test -n "$overlay_repository" ||
  fail "the overlay repository path is required"
test -d "$base_package" ||
  fail "the locked opam-cross-ios checkout lacks the OCaml 5.0 base recipe"
test -f "$template_package/opam" ||
  fail "the OCaml 5.1.1 overlay template is missing"

rm -rf "$overlay_repository"
mkdir -p "$overlay_repository/packages"
cp -R "$base_package" "$target_package"

cp "$template_package/opam" "$target_package/opam"
cp "$template_package/files/build.sh" "$target_package/files/build.sh"
cp "$template_package/files/install.sh" "$target_package/files/install.sh"
cp \
  "$template_package/files/ocamlmklib-failsafe.patch" \
  "$target_package/files/ocamlmklib-failsafe.patch"

perl -0pi -e '
  s/OCAML_DEVELOPMENT_VERSION=true/OCAML_DEVELOPMENT_VERSION=false/;
  s/OCAML_VERSION_MINOR=0/OCAML_VERSION_MINOR=1/;
  s/OCAML_VERSION_PATCHLEVEL=0/OCAML_VERSION_PATCHLEVEL=1/;
  s/OCAML_VERSION_EXTRA=beta1/OCAML_VERSION_EXTRA=/;
  s/BYTECCLIBS= -lm/BYTECCLIBS= -lm -framework Security -framework Foundation/;
  s/NATIVECCLIBS= -lm/NATIVECCLIBS= -lm -framework Security -framework Foundation/;
' "$target_package/files/Makefile.cross.in"

perl -0pi -e '
  s/HAS_ARCH_CODE32 is ignored on 32-bit machines\. \*\//HAS_ARCH_CODE32 is ignored on 32-bit machines. *\/\n\n#define TARGET_arm64 1\n#define SYS_macosx 1/;
  s/#define PROFINFO_WIDTH 0/#define HEADER_RESERVED_BITS 0\n\n#define PROFINFO_WIDTH 0/;
' "$target_package/files/m-ios.h"

perl -0pi -e '
  s/#define POSIX_SIGNALS 1/#define SYS_macosx 1\n\n#define POSIX_SIGNALS 1/;
' "$target_package/files/s-ios.h"

test "$(md5 -q "$target_package/files/Makefile.cross.in")" = \
  c338960cb9c22dff4b6e1b3ecbe2a15a ||
  fail "generated Makefile.cross.in does not match the tested recipe"
test "$(md5 -q "$target_package/files/m-ios.h")" = \
  66a125d352c8ee2271899eae808e5f86 ||
  fail "generated m-ios.h does not match the tested recipe"
test "$(md5 -q "$target_package/files/s-ios.h")" = \
  bcfd63d45db211005f64708ded08c746 ||
  fail "generated s-ios.h does not match the tested recipe"

# The simulator compiler reuses the entire recipe; only the conf package it
# reads differs. conf-ios-simulator supplies the iPhoneSimulator sysroot, the
# simulator -target triple, and the aarch64-apple-darwin.simulator marker.
simulator_package="$overlay_repository/packages/$OCAML_IOS_SIMULATOR_PACKAGE"
rm -rf "$simulator_package"
cp -R "$target_package" "$simulator_package"

sed -i.bak \
  -e 's/%{conf-ios:/%{conf-ios-simulator:/g' \
  -e 's/"conf-ios" {/"conf-ios-simulator" {/g' \
  -e 's/physical iOS arm64/iOS Simulator arm64/' \
  "$simulator_package/opam" \
  "$simulator_package/files/Makefile.cross.in"
rm -f \
  "$simulator_package/opam.bak" \
  "$simulator_package/files/Makefile.cross.in.bak"

simulator_makefile_md5=$(md5 -q "$simulator_package/files/Makefile.cross.in")
perl -0pi -e \
  "s/\[\"Makefile.cross.in\" \"md5=[0-9a-f]+\"\]/[\"Makefile.cross.in\" \"md5=$simulator_makefile_md5\"]/" \
  "$simulator_package/opam"

grep -F 'conf-ios:' "$simulator_package/opam" >/dev/null &&
  fail "generated simulator overlay still reads conf-ios"
grep -F 'conf-ios:' "$simulator_package/files/Makefile.cross.in" >/dev/null &&
  fail "generated simulator Makefile.cross still reads conf-ios"
grep -F 'conf-ios-simulator:' "$simulator_package/files/Makefile.cross.in" \
  >/dev/null ||
  fail "generated simulator Makefile.cross does not read conf-ios-simulator"

# The pinned conf-ios-simulator recipe lives in the vendor SDK packages;
# stage it into the overlay so dev switches resolve it like the SDK repo.
mkdir -p "$overlay_repository/packages/conf-ios-simulator.4"
cp "$repository_root/vendor/opam-ios/sdk-packages/conf-ios-simulator/conf-ios-simulator.4/opam" \
  "$overlay_repository/packages/conf-ios-simulator.4/opam"

printf '%s\n' 'opam-version: "2.0"' >"$overlay_repository/repo"
opam lint "$target_package/opam" >/dev/null ||
  fail "generated OCaml 5.1.1 overlay package is invalid"
opam lint "$simulator_package/opam" >/dev/null ||
  fail "generated iOS Simulator 5.1.1 overlay package is invalid"
