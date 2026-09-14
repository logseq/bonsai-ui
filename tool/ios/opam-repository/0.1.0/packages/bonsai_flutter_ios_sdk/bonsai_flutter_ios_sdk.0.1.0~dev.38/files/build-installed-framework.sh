#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

fail() {
  printf '%s\n' "iPhoneOS framework SDK build failure: $1" >&2
  exit 1
}

test "$#" -eq 2 || fail "usage: build-installed-framework.sh OPAM_SWITCH OPAM_SWITCH_PREFIX"
SDK_OPAM_SWITCH=$1
selected_prefix=$2
test -n "${OPAM_SWITCH_PREFIX:-}" || fail "OPAM_SWITCH_PREFIX is missing"
test "$selected_prefix" = "$OPAM_SWITCH_PREFIX" ||
  fail "selected opam prefix differs from OPAM_SWITCH_PREFIX"

for command in awk cp dune find mkdir opam shasum tar xcrun; do
  command -v "$command" >/dev/null 2>&1 || fail "required command is unavailable: $command"
done

work_root="$PWD/.bonsai_flutter_ios_framework_sdk"
stage_root="$work_root/stage"
target_lib="$stage_root/ios-sysroot/lib"
mkdir -p "$target_lib"

framework_source_sha256='b57cf03feb661e66e20e7e561c6830f12372b58edd2386fcb33c7adbe40bf106'
framework_archive_source="$script_directory/bonsai_flutter.tar.gz"
framework_archive="$work_root/bonsai_flutter.tar.gz"
framework_source="$work_root/framework-source"
framework_build="$work_root/framework-build"

if test ! -f "$framework_archive"; then
  test -f "$framework_archive_source" ||
    fail "opam did not provide the Bonsai Flutter source archive"
  actual_sha256=$(shasum -a 256 "$framework_archive_source" | cut -d ' ' -f 1)
  test "$actual_sha256" = "$framework_source_sha256" ||
    fail "Bonsai Flutter source checksum mismatch"
  cp "$framework_archive_source" "$framework_archive"
fi

if test ! -d "$framework_source"; then
  mkdir -p "$framework_source"
  tar -xzf "$framework_archive" --strip-components=1 -C "$framework_source"
fi

findlib_conf="$work_root/findlib.conf"
runtime_target_lib="$OPAM_SWITCH_PREFIX/ios-sysroot/lib"
standard_target_lib="$runtime_target_lib/ocaml"
test -d "$standard_target_lib" ||
  fail "the installed iPhoneOS runtime SDK is missing its target standard library"
{
  cat "$OPAM_SWITCH_PREFIX/lib/findlib.conf"
  awk \
    -v runtime_target_lib="$runtime_target_lib" \
    -v standard_target_lib="$standard_target_lib" \
    -v framework_target_lib="$target_lib" '
      /^path\(ios\)/ {
        printf "path(ios) = \"%s:%s:%s\"\n", framework_target_lib, runtime_target_lib, standard_target_lib
        next
      }
      /^destdir\(ios\)/ {
        printf "destdir(ios) = \"%s\"\n", framework_target_lib
        next
      }
      { print }
    ' "$OPAM_SWITCH_PREFIX/lib/findlib.conf.d/ios.conf"
} > "$findlib_conf"

sdk_version=$(xcrun --sdk iphoneos --show-sdk-version)
sdk_root=$(xcrun --sdk iphoneos --show-sdk-path)
(
  cd "$framework_source"
  OPAMROOT=${OPAMROOT:-$(opam var root)} \
    OCAMLFIND_CONF="$findlib_conf" \
    BONSAI_FLUTTER_EMBED_OCAML=enabled \
    BONSAI_FLUTTER_APPLE_SDK_ROOT="$sdk_root" \
    SDK="$sdk_version" \
    VER=15.0 \
    opam exec --switch="$SDK_OPAM_SWITCH" -- \
    dune build \
      --build-dir="$framework_build" \
      --profile=release \
      -x ios \
      -p bonsai_flutter
)

framework_install_root="$framework_build/install/default.ios"
test -d "$framework_install_root/lib/bonsai_flutter" ||
  fail "Dune did not produce the iPhoneOS framework install tree"
cp -RL "$framework_install_root/." "$stage_root/ios-sysroot/"

printf '%s\n' "iPhoneOS framework SDK build passed"
