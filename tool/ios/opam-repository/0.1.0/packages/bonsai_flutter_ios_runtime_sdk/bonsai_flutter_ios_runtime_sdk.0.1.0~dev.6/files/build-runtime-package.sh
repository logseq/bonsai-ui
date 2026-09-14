#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SDK_ASSET_ROOT=${SDK_ASSET_ROOT:-$script_directory}

# shellcheck source=tool/ios/toolchain.lock
. "$SDK_ASSET_ROOT/toolchain.lock"

RUNTIME_CLOSURE_LOCK=${RUNTIME_CLOSURE_LOCK:-"$SDK_ASSET_ROOT/runtime-closure.lock"}
closure_lock=$RUNTIME_CLOSURE_LOCK
opam_root=${OPAMROOT:-$(opam var root)}
switch=${SDK_OPAM_SWITCH:?SDK_OPAM_SWITCH is required}
switch_prefix=${OPAM_SWITCH_PREFIX:?OPAM_SWITCH_PREFIX is required}
package_root=${SDK_PACKAGE_WORK_ROOT:?SDK_PACKAGE_WORK_ROOT is required}

fail() {
  printf '%s\n' "iOS runtime package build failure: $1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "required command is unavailable: $1"
}

test "$#" -eq 2 ||
  fail "usage: build_runtime_package.sh iphoneos <package>"

target=$1
requested_package=$2

test "$target" = iphoneos || fail "expected iphoneos"
expected_platform=IOS
expected_minimum=$IOS_DEPLOYMENT_TARGET

require_command awk
require_command cp
require_command dirname
require_command find
require_command grep
require_command ln
require_command mkdir
require_command mv
require_command opam
require_command make
require_command patch
require_command pkg-config
require_command rg
require_command sed
require_command shasum
require_command sort
require_command tar
require_command tr
require_command xcrun

test -x "$switch_prefix/bin/ocamlc" ||
  fail "selected opam switch is incomplete: $switch_prefix"

resolved_bonsai_version=$(
  OPAMROOT="$opam_root" \
    opam show --switch="$switch" --field=installed-version bonsai
)
test "$resolved_bonsai_version" = "$BONSAI_VERSION" ||
  fail "host dependencies are missing; run setup_host_dependencies.sh $target"

package_row=$(
  awk -F '|' -v package="$requested_package" '
    !/^#/ && $1 == package { print; found = 1 }
    END { if (!found) exit 1 }
  ' "$closure_lock"
) || fail "package is not present in the runtime closure: $requested_package"

old_ifs=$IFS
IFS='|'
set -- $package_row
IFS=$old_ifs

package_name=$1
package_version=$2
package_role=$3
package_capability=$4
package_build_mechanism=$5
source_url=$6
source_sha256=$7
package_components=$8
package_dependencies=$9

test "$package_name" = "$requested_package" ||
  fail "resolved the wrong package row"
case "$package_role" in
  target-package | target-build) ;;
  *) fail "invalid package role for $package_name: $package_role" ;;
esac

work_root="$package_root/$target/$package_name/$package_version/$source_sha256/recipe-$IOS_RUNTIME_RECIPE_REVISION"
source_archive="$work_root/source.archive"
source_archive_source="$SDK_ASSET_ROOT/runtime-$package_name-$source_sha256.archive"
source_directory="$work_root/source"
source_marker="$work_root/source.prepared"
build_directory="$work_root/build"
baseline_target_lib="$switch_prefix/ios-sysroot/lib"
standard_target_lib="$baseline_target_lib/ocaml"
target_lib=${TARGET_LIB:-$baseline_target_lib}
target_prefix=$(dirname -- "$target_lib")
findlib_conf="$work_root/findlib.conf"
mkdir -p "$work_root"
if test "$target_lib" != "$baseline_target_lib"; then
  seq_metadata="$baseline_target_lib/seq/META"
  if test ! -f "$seq_metadata"; then
    seq_metadata="$switch_prefix/lib/seq/META"
  fi
  test -f "$seq_metadata" ||
    fail "iPhoneOS seq compatibility metadata is missing"
  mkdir -p "$target_lib/seq"
  cp -f "$seq_metadata" "$target_lib/seq/META"
fi
{
  cat "$switch_prefix/lib/findlib.conf"
  awk \
    -v target_lib="$target_lib" \
    -v standard_target_lib="$standard_target_lib" '
      /^path\(ios\)/ {
        printf "path(ios) = \"%s:%s\"\n", target_lib, standard_target_lib
        next
      }
      /^destdir\(ios\)/ {
        printf "destdir(ios) = \"%s\"\n", target_lib
        next
      }
      { print }
    ' "$switch_prefix/lib/findlib.conf.d/ios.conf"
} >"$findlib_conf"
export OCAMLFIND_CONF="$findlib_conf"
unset OCAMLPATH

if test ! -f "$source_archive"; then
  test -f "$source_archive_source" ||
    fail "opam did not provide the source archive for $package_name"
  cp "$source_archive_source" "$source_archive"
fi

printf '%s  %s\n' "$source_sha256" "$source_archive" |
  shasum -a 256 -c - >/dev/null ||
  fail "source digest does not match for $package_name"

tar -tf "$source_archive" |
  awk '
    /^\// { exit 1 }
    /(^|\/)\.\.(\/|$)/ { exit 1 }
  ' ||
  fail "source archive contains an unsafe path: $package_name"

if test ! -f "$source_marker"; then
  test ! -e "$source_directory" ||
    fail "source directory exists without a preparation marker: $source_directory"
  mkdir -p "$source_directory"
  tar -xf "$source_archive" -C "$source_directory" --strip-components=1
  if test "$package_name" = base; then
    patch \
      -d "$source_directory" \
      -p1 \
      <"$SDK_ASSET_ROOT/patches/base-host-generator.patch"
  fi
  if test "$package_name" = jst-config; then
    patch \
      -d "$source_directory" \
      -p1 \
      <"$SDK_ASSET_ROOT/patches/jst-config-host-discover.patch"
  fi
  if test "$package_name" = datascript-ocaml-native; then
    datascript_sqlite_dune="$source_directory/sqlite/dune"
    unpatched_sqlite_flags='(:standard -L%{env:DATASCRIPT_SQLITE_LIB_DIR=.} -lsqlite3)'
    patched_sqlite_flags='(:standard -lsqlite3)'
    if grep -F "$unpatched_sqlite_flags" "$datascript_sqlite_dune" >/dev/null; then
      patch \
        --batch \
        --forward \
        -d "$source_directory" \
        -p1 \
        <"$SDK_ASSET_ROOT/patches/datascript-system-sqlite.patch"
    elif ! grep -F "$patched_sqlite_flags" "$datascript_sqlite_dune" >/dev/null; then
      fail "DataScript SQLite source declaration changed upstream"
    fi
    grep -F 'DATASCRIPT_SQLITE_LIB_DIR' "$datascript_sqlite_dune" >/dev/null &&
      fail "DataScript SQLite still configures an explicit library path"
    grep -F "$patched_sqlite_flags" "$datascript_sqlite_dune" >/dev/null ||
      fail "DataScript SQLite does not link the system sqlite3 library"
  fi
  : >"$source_marker"
fi

detect_build_mechanism() {
  if test "$package_name" = zarith; then
    printf '%s\n' zarith
  elif test -f "$source_directory/dune-project"; then
    printf '%s\n' dune
  elif test -f "$source_directory/pkg/pkg.ml"; then
    printf '%s\n' topkg
  else
    printf '%s\n' unsupported
  fi
}

detected_build_mechanism=$(detect_build_mechanism)
if test "$package_name" != gmp-sys-ios && \
   test "$detected_build_mechanism" != "$package_build_mechanism"; then
  fail "$package_name uses unsupported capability build-system; required cross-build recipe: expected $package_build_mechanism, detected $detected_build_mechanism"
fi
if test "$package_capability" = Pure_ocaml; then
  rm -f "$work_root/foreign-stubs"
  printf '%s\n' "$package_components" | tr ',' '\n' |
    while IFS= read -r component; do
      archives=$(
        OPAMROOT="$opam_root" opam exec --switch="$switch" -- \
          ocamlfind query -predicates native -a-format "$component" 2>/dev/null || true
      )
      for archive in $archives; do
        test -f "$archive" || continue
        if OPAMROOT="$opam_root" opam exec --switch="$switch" -- \
          ocamlobjinfo "$archive" 2>/dev/null |
          grep -E '^Extra C object files:[[:space:]]+[^[:space:]]' >/dev/null; then
          printf '%s\n' foreign >"$work_root/foreign-stubs"
        fi
      done
    done
  printf '%s\n' "$package_components" | tr ',' '\n' |
    while IFS= read -r component; do
      rg --files-with-matches --fixed-strings "(public_name $component)" \
        "$source_directory" --glob dune |
        while IFS= read -r component_dune; do
          if rg '\(foreign_stubs|\(foreign_archives|\(c_library_flags|ctypes|cargo|rustc' \
            "$component_dune" >/dev/null; then
            printf '%s\n' foreign >"$work_root/foreign-stubs"
          fi
        done
    done
  test ! -f "$work_root/foreign-stubs" ||
    fail "$package_name uses unsupported capability foreign_stubs; required cross-build recipe: add an explicit capability recipe"
fi

if test "$package_name" = jst-config; then
  if ! grep -F '(run ../discover/discover.exe)' \
    "$source_directory/src/dune" >/dev/null; then
    patch \
      --batch \
      --forward \
      -d "$source_directory" \
      -p1 \
      <"$SDK_ASSET_ROOT/patches/jst-config-host-discover.patch"
  fi
  grep -F '(run %{first_dep})' "$source_directory/src/dune" >/dev/null &&
    fail "jst-config still aliases its host discovery executable"
fi

if test "$package_name" = eio_posix; then
  if grep -F '| 6 -> Some (`Tcp' \
    "$source_directory/lib_eio_posix/net.ml" >/dev/null; then
    patch \
      --batch \
      --forward \
      -d "$source_directory" \
      -p1 \
      <"$SDK_ASSET_ROOT/patches/eio-posix-darwin-protocol-zero.patch"
  fi
  grep -F '| 6 -> Some (`Tcp' \
    "$source_directory/lib_eio_posix/net.ml" >/dev/null &&
    fail "eio_posix still drops Darwin address records with protocol zero"
  if grep -F 'Unix.getaddrinfo node service []' \
    "$source_directory/lib_eio_posix/net.ml" >/dev/null; then
    patch \
      --batch \
      --forward \
      -d "$source_directory" \
      -p1 \
      <"$SDK_ASSET_ROOT/patches/eio-posix-darwin-socktype-hints.patch"
  fi
  grep -F 'Unix.getaddrinfo node service []' \
    "$source_directory/lib_eio_posix/net.ml" >/dev/null &&
    fail "eio_posix still resolves Darwin addresses without socket type hints"
fi

if test "$package_name" = mirage-crypto-rng; then
  entropy_source="$source_directory/rng/unix/mc_getrandom_stubs.c"
  if grep -F '#include <sys/random.h>' "$entropy_source" >/dev/null; then
    patch \
      --batch \
      --forward \
      -d "$source_directory" \
      -p1 \
      <"$SDK_ASSET_ROOT/patches/mirage-crypto-rng-apple-entropy.patch"
  fi
  grep -F '#include <sys/random.h>' "$entropy_source" >/dev/null &&
    fail "mirage-crypto-rng still includes unavailable Apple sys/random.h"
  grep -F 'arc4random_buf(data, len);' "$entropy_source" >/dev/null ||
    fail "mirage-crypto-rng does not use the Apple system entropy source"
fi

sdk_version=$(xcrun --sdk "$target" --show-sdk-version)
sdk_root=$(xcrun --sdk "$target" --show-sdk-path)
target_archiver=$(xcrun --sdk "$target" --find ar)
target_pkg_config_path="$SDK_ASSET_ROOT/pkgconfig/$target"
test -f "$target_pkg_config_path/sqlite3.pc" ||
  fail "missing target SQLite pkg-config metadata"
export PKG_CONFIG_PATH="$target_pkg_config_path"
export PKG_CONFIG_SYSROOT_DIR="$sdk_root"
export SQLITE3_DISABLE_LOADABLE_EXTENSIONS=1

if test "$package_name" = gmp-sys-ios; then
  target_dependency_root="$SDK_PACKAGE_WORK_ROOT/dependencies/gmp"
  gmp_build_directory="$build_directory/gmp"
  target_cc="$switch_prefix/ios-sysroot/bin/ios-cc"
  target_cflags="-O2 -arch arm64 -isysroot $sdk_root -miphoneos-version-min=$IOS_DEPLOYMENT_TARGET"
  target_ldflags="-Wl,-syslibroot,$sdk_root -miphoneos-version-min=$IOS_DEPLOYMENT_TARGET"

  test -x "$target_cc" ||
    fail "missing iPhoneOS C compiler wrapper: $target_cc"
  mkdir -p "$gmp_build_directory" "$target_dependency_root"
  if test ! -f "$gmp_build_directory/Makefile"; then
    (
      cd "$gmp_build_directory"
      CC="$target_cc" \
        CFLAGS="$target_cflags" \
        CPPFLAGS="-arch arm64 -isysroot $sdk_root -miphoneos-version-min=$IOS_DEPLOYMENT_TARGET" \
        LDFLAGS="$target_ldflags" \
        "$source_directory/configure" \
          --host=aarch64-apple-darwin \
          --prefix="$target_dependency_root" \
          --disable-shared \
          --enable-static \
          --with-pic
    )
  fi
  make -C "$gmp_build_directory" -j "${JOBS:-4}"

  target_gmp_archive="$target_dependency_root/lib/libgmp.a"
  mkdir -p \
    "$target_dependency_root/include" \
    "$target_dependency_root/lib/pkgconfig"
  cp -f "$gmp_build_directory/.libs/libgmp.a" "$target_gmp_archive"
  cp -f "$gmp_build_directory/gmp.h" "$target_dependency_root/include/gmp.h"
  cp -f \
    "$gmp_build_directory/gmp.pc" \
    "$target_dependency_root/lib/pkgconfig/gmp.pc"
  test -f "$target_gmp_archive" || fail "target static GMP archive is missing"
  test "$(xcrun lipo -archs "$target_gmp_archive")" = arm64 ||
    fail "target static GMP archive is not arm64-only"
  if rg -a -l \
    '/opt/homebrew|/usr/local|MacOSX[0-9]|/private/tmp/bonsai-flutter-opam|-mpopcnt' \
    "$target_dependency_root/include" \
    "$target_dependency_root/lib/libgmp.a" \
    "$target_dependency_root/lib/pkgconfig/gmp.pc" >/dev/null; then
    fail "$package_name staged a prohibited host path or CPU flag"
  fi

  printf '%s\n' \
    "iOS $target runtime package build passed: $package_name $package_version"
  exit 0
fi

host_lib=$(
  OPAMROOT="$opam_root" \
    opam var --switch="$switch" lib
)
host_package_root="$host_lib/$package_name"
test -f "$host_package_root/META" ||
  fail "host package metadata is missing for $package_name"

target_package_root="$target_lib/$package_name"
mkdir -p "$target_package_root"
for metadata_name in META dune-package opam; do
  if test -f "$host_package_root/$metadata_name"; then
    cp -f "$host_package_root/$metadata_name" "$target_package_root/"
  fi
done

if test "$package_name" = zarith; then
  gmp_root="$SDK_PACKAGE_WORK_ROOT/dependencies/gmp"
  zarith_tool_directory="$build_directory/toolchain"
  test -f "$gmp_root/include/gmp.h" ||
    fail "target GMP headers are missing; build gmp-sys-ios first"
  test -f "$gmp_root/lib/libgmp.a" ||
    fail "target static GMP archive is missing; build gmp-sys-ios first"
  mkdir -p "$zarith_tool_directory"
  ln -sf "$switch_prefix/bin/ocaml" "$zarith_tool_directory/ocaml"
  ln -sf "$switch_prefix/bin/ocamlfind" "$zarith_tool_directory/ocamlfind"
  for target_tool in ocamlc ocamldep ocamlmklib ocamlopt; do
    ln -sf \
      "$switch_prefix/ios-sysroot/bin/$target_tool" \
      "$zarith_tool_directory/$target_tool"
  done

  (
    cd "$source_directory"
    OPAMROOT="$opam_root" \
      SDK="$sdk_version" \
      VER="$IOS_DEPLOYMENT_TARGET" \
      OCAMLFIND_TOOLCHAIN=ios \
      opam exec --switch="$switch" -- \
      env \
        "PATH=$zarith_tool_directory:$switch_prefix/bin:$PATH" \
        "PKG_CONFIG_PATH=$gmp_root/lib/pkgconfig" \
        PKG_CONFIG_SYSROOT_DIR= \
        CFLAGS=-O2 \
        "CPPFLAGS=-I$gmp_root/include" \
        "LDFLAGS=-L$gmp_root/lib" \
        ./configure \
          -installdir "$target_package_root" \
          -gmp
    OPAMROOT="$opam_root" \
      SDK="$sdk_version" \
      VER="$IOS_DEPLOYMENT_TARGET" \
      OCAMLFIND_TOOLCHAIN=ios \
      opam exec --switch="$switch" -- \
      env \
        "PATH=$zarith_tool_directory:$switch_prefix/bin:$PATH" \
        make -j "${JOBS:-4}" \
          zarith_version.cmx \
          z.cmx \
          q.cmx \
          big_int_Z.cmx \
          libzarith.a

    "$zarith_tool_directory/ocamlopt" \
      -a \
      -o zarith.cmxa \
      zarith_version.cmx \
      z.cmx \
      q.cmx \
      big_int_Z.cmx \
      -cclib -lzarith \
      -cclib "-L$gmp_root/lib" \
      -cclib -lgmp
  )

  find "$source_directory" \
    -maxdepth 1 \
    -type f \
    \( \
      -name '*.a' -o \
      -name '*.cmi' -o \
      -name '*.cmx' -o \
      -name '*.cmxa' -o \
      -name '*.h' -o \
      -name '*.mli' \
    \) \
    -exec cp -f {} "$target_package_root/" \;

  OPAMROOT="$opam_root" \
    opam exec --switch="$switch" -- \
    ocamlfind -toolchain ios query -predicates=native zarith >/dev/null ||
    fail "staged component is not visible to findlib: zarith"
  sh "$script_directory/verify_macho.sh" \
    "$source_directory/z.o" \
    "$expected_platform" \
    arm64 \
    "$expected_minimum"
  sh "$script_directory/verify_macho.sh" \
    "$source_directory/caml_z.o" \
    "$expected_platform" \
    arm64 \
    "$expected_minimum"

  if rg -a -l \
    '/opt/homebrew|/usr/local|MacOSX[0-9]|/private/tmp/bonsai-flutter-opam|-mpopcnt' \
    "$target_package_root" >/dev/null; then
    fail "$package_name staged a prohibited host path or CPU flag"
  fi

  printf '%s\n' \
    "iOS $target runtime package build passed: $package_name $package_version"
  exit 0
fi

case "$package_build_mechanism" in
  topkg)
    require_command opam-installer
    topkg_build_directory="$source_directory/_build-ios"
    topkg_driver="$source_directory/pkg/pkg-ios.ml"
    grep -E '^#use "topfind";*$' "$source_directory/pkg/pkg.ml" >/dev/null ||
      fail "$package_name has an unsupported Topkg driver; required cross-build recipe: load host Topkg explicitly"
    grep -E '^#require "topkg";*$' "$source_directory/pkg/pkg.ml" >/dev/null ||
      fail "$package_name has an unsupported Topkg driver; required cross-build recipe: load host Topkg explicitly"
    sed '/^#use "topfind";*$/d; /^#require "topkg";*$/d' \
      "$source_directory/pkg/pkg.ml" >"$topkg_driver"
    topkg_arguments=
    if test "$package_name" = fmt; then
      topkg_arguments="--with-base-unix false --with-cmdliner false"
    fi
    if test "$package_name" = logs; then
      topkg_arguments="--with-base-threads false --with-cmdliner false --with-fmt false --with-js_of_ocaml-compiler false --with-lwt false"
    fi
    if test "$package_name" = uucp; then
      topkg_arguments="--with-uunf false --with-cmdliner false"
    fi
    if test "$package_name" = uunf; then
      topkg_arguments="--with-uutf false --with-cmdliner false"
    fi
    if test "$package_name" = uutf; then
      topkg_arguments="--with-cmdliner false"
    fi
    (
      cd "$source_directory"
      OPAMROOT="$opam_root" \
        SDK="$sdk_version" \
        VER="$IOS_DEPLOYMENT_TARGET" \
        opam exec --switch="$switch" -- \
        ocaml \
          -I "$host_lib/topkg" \
          "$host_lib/topkg/topkg.cma" \
          pkg/pkg-ios.ml \
          build \
          --build-dir _build-ios \
          --debug false \
          --tests false \
          --toolchain ios \
          $topkg_arguments

      install_manifest="$package_name.install"
      case "$package_name" in
        fmt | mtime)
          install_manifest="$package_name.runtime.install"
          awk '
            /_build-ios\/src\/top\// ||
            /_build-ios\/src\/mtime_top_init\.ml/ {
              if ($0 ~ /\][[:space:]]*$/) print "]"
              next
            }
            { print }
          ' "$package_name.install" >"$install_manifest"
          ;;
      esac
      opam-installer \
        --name "$package_name" \
        --prefix "$target_prefix" \
        --libdir "$target_lib" \
        "$install_manifest"
    )

    case "$package_name" in
      fmt | mtime)
        test ! -e "$target_package_root/top" ||
          fail "$package_name staged an unrelated toplevel library"
        ;;
    esac
    if test "$package_name" = mtime; then
      test ! -e "$target_package_root/mtime_top_init.ml" ||
        fail "mtime staged an unrelated toplevel initializer"
    fi

    printf '%s\n' "$package_components" |
      tr ',' '\n' |
      while IFS= read -r component; do
        OPAMROOT="$opam_root" \
          opam exec --switch="$switch" -- \
          ocamlfind -toolchain ios query -predicates=native "$component" \
          >/dev/null ||
          fail "staged component is not visible to findlib: $component"
      done

    primary_topkg_object="$topkg_build_directory/src/$package_name.o"
    if test -f "$primary_topkg_object"; then
      representative_object=$primary_topkg_object
    else
      representative_object=$(
        find "$topkg_build_directory" \
          -type f \
          -name '*.o' \
          ! -name 'myocamlbuild.o' |
          sort |
          sed -n '1p'
      )
    fi
    test -n "$representative_object" ||
      fail "no representative target object was produced for $package_name"
    sh "$script_directory/verify_macho.sh" \
      "$representative_object" \
      "$expected_platform" \
      arm64 \
      "$expected_minimum"

    if rg -a -l \
      '/opt/homebrew|/usr/local|MacOSX[0-9]|/private/tmp/bonsai-flutter-opam|-mpopcnt' \
      "$target_package_root" >/dev/null; then
      fail "$package_name staged a prohibited host path or CPU flag"
    fi

    printf '%s\n' \
      "iOS $target runtime package build passed: $package_name $package_version"
    exit 0
    ;;
esac

if test "$package_name" = domain-local-await; then
  manual_build_directory="$build_directory/manual"
  mkdir -p "$manual_build_directory"

  compile_manual() {
    OPAMROOT="$opam_root" \
      SDK="$sdk_version" \
      VER="$IOS_DEPLOYMENT_TARGET" \
      opam exec --switch="$switch" -- \
      ocamlfind -toolchain ios ocamlopt \
        -package thread-table \
        -I "$manual_build_directory" \
        "$@"
  }

  compile_manual \
    -c \
    -o "$manual_build_directory/Thread_intf.cmx" \
    "$source_directory/src/Thread_intf.ml"
  compile_manual \
    -c \
    -o "$manual_build_directory/Domain_local_await.cmi" \
    "$source_directory/src/Domain_local_await.mli"
  compile_manual \
    -c \
    -o "$manual_build_directory/Domain_local_await.cmx" \
    "$source_directory/src/Domain_local_await.ml"
  compile_manual \
    -a \
    -o "$manual_build_directory/Domain_local_await.cmxa" \
    "$manual_build_directory/Thread_intf.cmx" \
    "$manual_build_directory/Domain_local_await.cmx"

  find "$manual_build_directory" \
    -maxdepth 1 \
    -type f \
    \( -name '*.a' -o -name '*.cmi' -o -name '*.cmx' -o -name '*.cmxa' \) \
    -exec cp -f {} "$target_package_root/" \;

  OPAMROOT="$opam_root" \
    opam exec --switch="$switch" -- \
    ocamlfind -toolchain ios query -predicates=native domain-local-await \
    >/dev/null ||
    fail "staged component is not visible to findlib: domain-local-await"

  sh "$script_directory/verify_macho.sh" \
    "$manual_build_directory/Domain_local_await.o" \
    "$expected_platform" \
    arm64 \
    "$expected_minimum"

  if rg -a -l \
    '/opt/homebrew|/usr/local|MacOSX[0-9]|/private/tmp/bonsai-flutter-opam|-mpopcnt' \
    "$target_package_root" >/dev/null; then
    fail "$package_name staged a prohibited host path or CPU flag"
  fi

  printf '%s\n' \
    "iOS $target runtime package build passed: $package_name $package_version"
  exit 0
fi

component_order_file="$work_root/components.ordered"
virtual_interface_marker="$work_root/virtual-interface-only"
rm -f "$virtual_interface_marker"
: >"$component_order_file.unsorted"
printf '%s\n' "$package_components" | tr ',' '\n' |
  while IFS= read -r component; do
    component_archives=$(
      OPAMROOT="$opam_root" \
        opam exec --switch="$switch" -- \
        ocamlfind query -predicates=native -format '%a' "$component"
    )
    if test -n "$component_archives"; then priority=0; else priority=1; fi
    printf '%s|%s\n' "$priority" "$component"
  done >"$component_order_file.unsorted"
sort -t '|' -k1,1 -k2,2 "$component_order_file.unsorted" |
  sed 's/^[^|]*|//' >"$component_order_file"

while IFS= read -r component; do
    component_query=$(
      OPAMROOT="$opam_root" \
        opam exec --switch="$switch" -- \
        ocamlfind query \
          -predicates=native \
          -format '%d|%a' \
        "$component"
    )
    if test -z "$component_query"; then
      component_host_directory=$(
        OPAMROOT="$opam_root" \
          opam exec --switch="$switch" -- \
          ocamlfind query "$component"
      )
      component_query="$component_host_directory|"
    fi
    component_host_directory=${component_query%%|*}
    component_archives=${component_query#*|}
    component_relative_path=${component_host_directory#"$host_lib/"}
    target_component_directory="$target_lib/$component_relative_path"
    mkdir -p "$target_component_directory"

    # Package headers are architecture-independent inputs for downstream C
    # stubs. Copy installed headers first so target-generated headers, such as
    # jst-config's config.h, replace any host-generated version below.
    find "$component_host_directory" \
      \( -type f -o -type l \) \
      -name '*.h' |
      while IFS= read -r header; do
        header_relative=${header#"$component_host_directory/"}
        header_destination="$target_component_directory/$header_relative"
        mkdir -p "$(dirname "$header_destination")"
        cp -f "$header" "$header_destination"
      done

    if test -z "$component_archives"; then
      dune_file=$(
        rg \
          --files-with-matches \
          --fixed-strings \
          "(public_name $component)" \
          "$source_directory" \
          --glob dune |
          sed -n '1p'
      )
      test -n "$dune_file" ||
        fail "could not locate the virtual Dune library for $component"
      source_component_directory=$(dirname -- "$dune_file")
      source_component_relative=${source_component_directory#"$source_directory/"}
      if test "$source_component_relative" = "$source_component_directory"; then
        source_component_relative=.
      fi
      dune_name=$(sed -n 's/^[[:space:]]*(name[[:space:]]\([^ )]*\)).*/\1/p' "$dune_file" | sed -n '1p')
      test -n "$dune_name" ||
        fail "could not resolve the Dune name for virtual component $component"
      build_component_directory="$build_directory/default.ios/$source_component_relative"
      object_directory="$build_component_directory/.$dune_name.objs"
      if test "$source_component_relative" = .; then
        virtual_target_prefix=".$dune_name.objs"
      else
        virtual_target_prefix="$source_component_relative/.$dune_name.objs"
      fi
      OPAMROOT="$opam_root" \
        SDK="$sdk_version" \
        VER="$IOS_DEPLOYMENT_TARGET" \
        opam exec --switch="$switch" -- \
        dune build \
          --root="$source_directory" \
          --build-dir="$build_directory" \
          --profile=release \
          -j "${JOBS:-4}" \
          -x ios \
          "$virtual_target_prefix/byte/$dune_name.cmi"
      find "$component_host_directory" \
        -maxdepth 1 \
        \( -type f -o -type l \) \
        \( -name '*.ml' -o -name '*.mli' \) \
        -exec cp -f {} "$target_component_directory/" \;
      for object_mode in byte native; do
        test -d "$object_directory/$object_mode" || continue
        find "$object_directory/$object_mode" \
          -maxdepth 1 \
          -type f \
          \( \
            -name '*.cmi' -o \
            -name '*.cmt' -o \
            -name '*.cmti' -o \
            -name '*.cmx' -o \
            -name '*.o' \
          \) \
          -exec cp -f {} "$target_component_directory/" \;
      done
      find "$build_component_directory" \
        -maxdepth 1 \
        -type f \
        \( -name '*.ml' -o -name '*.mli' -o -name '*.ml-gen' \) \
        -exec cp -f {} "$target_component_directory/" \;
      find "$target_component_directory" -maxdepth 1 -type f -name '*.cmi' |
        grep . >/dev/null ||
        fail "virtual component $component has no target interface artifacts"
      : >"$virtual_interface_marker"
      continue
    fi

    printf '%s\n' "$component_archives" |
      tr ' ' '\n' |
      while IFS= read -r archive_name; do
        test -n "$archive_name" || continue
        dune_file=$(
          rg \
            --files-with-matches \
            --fixed-strings \
            "(public_name $component)" \
            "$source_directory" \
            --glob dune |
            sed -n '1p'
        )
        test -n "$dune_file" ||
          fail "could not locate the Dune library for $component"
        duplicate_dune_file=$(
          rg \
            --files-with-matches \
            --fixed-strings \
            "(public_name $component)" \
            "$source_directory" \
            --glob dune |
            sed -n '2p'
        )
        test -z "$duplicate_dune_file" ||
          fail "multiple Dune libraries declare $component"

        source_component_directory=$(dirname -- "$dune_file")
        source_component_relative=${source_component_directory#"$source_directory/"}
        if test "$source_component_relative" = "$source_component_directory"; then
          source_component_relative=.
        fi
        if test "$source_component_relative" = .; then
          dune_target=$archive_name
        else
          dune_target="$source_component_relative/$archive_name"
        fi
        OPAMROOT="$opam_root" \
          SDK="$sdk_version" \
          VER="$IOS_DEPLOYMENT_TARGET" \
          opam exec --switch="$switch" -- \
          dune build \
            --root="$source_directory" \
            --build-dir="$build_directory" \
            --profile=release \
            -j "${JOBS:-4}" \
            -x ios \
            "$dune_target"

        if test "$package_name" = jst-config; then
          OPAMROOT="$opam_root" \
            SDK="$sdk_version" \
            VER="$IOS_DEPLOYMENT_TARGET" \
            opam exec --switch="$switch" -- \
            dune build \
              --root="$source_directory" \
              --build-dir="$build_directory" \
              --profile=release \
              -j "${JOBS:-4}" \
              -x ios \
              src/config.h \
              src/thread_id.h
        fi

        build_component_directory="$build_directory/default.ios/$source_component_relative"
        archive_stem=${archive_name%.cmxa}
        object_directory="$build_component_directory/.$archive_stem.objs"

        test -f "$build_component_directory/$archive_name" ||
          fail "Dune did not produce $component archive $archive_name"

        extra_c_objects=$(
          OPAMROOT="$opam_root" \
            opam exec --switch="$switch" -- \
            ocamlobjinfo "$build_component_directory/$archive_name" |
            sed -n 's/^Extra C object files:[[:space:]]*//p'
        )
        for extra_c_object in $extra_c_objects; do
          case "$extra_c_object" in
            -lsqlite3)
              test "$package_capability" = System_sqlite ||
                fail "$component unexpectedly depends on system SQLite"
              ;;
            -L*)
              fail "$component uses unsupported library path $extra_c_object"
              ;;
            -l*)
              static_archive="lib${extra_c_object#-l}.a"
              if test "$source_component_relative" = .; then
                static_archive_target=$static_archive
              else
                static_archive_target="$source_component_relative/$static_archive"
              fi
              if test ! -f \
                "$build_directory/default.ios/$static_archive_target"; then
                stub_objects=$(
                  find "$build_component_directory" \
                    -maxdepth 1 \
                    -type f \
                    -name '*.o' \
                    -print
                )
                if test -n "$stub_objects"; then
                  "$target_archiver" \
                    rcs \
                    "$build_directory/default.ios/$static_archive_target" \
                    $stub_objects
                else
                  OPAMROOT="$opam_root" \
                    SDK="$sdk_version" \
                    VER="$IOS_DEPLOYMENT_TARGET" \
                    opam exec --switch="$switch" -- \
                    dune build \
                      --root="$source_directory" \
                      --build-dir="$build_directory" \
                      --profile=release \
                      -j "${JOBS:-4}" \
                      -x ios \
                      "$static_archive_target"
                fi
                test -f \
                  "$build_directory/default.ios/$static_archive_target" ||
                  fail "$component did not produce target C stubs $static_archive"
              fi
              ;;
            *)
              fail "$component uses unsupported extra C object $extra_c_object"
              ;;
          esac
        done

        find "$build_component_directory" \
          -maxdepth 1 \
          \( -type f -o -type l \) \
          \( \
            -name "$archive_stem.a" -o \
            -name "$archive_name" -o \
            -name 'lib*_stubs.a' -o \
            -name '*.h' -o \
            -name '*.js' -o \
            -name '*.ml' -o \
            -name '*.mli' \
          \) \
          -exec cp -f {} "$target_component_directory/" \;

        if test -d "$object_directory/byte"; then
          find "$object_directory/byte" \
            -maxdepth 1 \
            -type f \
            \( -name '*.cmi' -o -name '*.cmt' -o -name '*.cmti' \) \
            -exec cp -f {} "$target_component_directory/" \;
        fi
        if test -d "$object_directory/native"; then
          find "$object_directory/native" \
            -maxdepth 1 \
            -type f \
            -name '*.cmx' \
            -exec cp -f {} "$target_component_directory/" \;
        fi
      done

    OPAMROOT="$opam_root" \
      opam exec --switch="$switch" -- \
      ocamlfind -toolchain ios query -predicates=native "$component" \
      >/dev/null ||
      fail "staged component is not visible to findlib: $component"
done <"$component_order_file"

# Dune implementation packages install the public interfaces and native
# metadata of their virtual library beside the implementation archive. Use
# the host installation only as the expected filename inventory; every copied
# artifact must come from this package's iPhoneOS build directory.
if find "$target_package_root" -maxdepth 1 -type f -name '*.cmxa' | grep . >/dev/null; then
  find "$host_package_root" \
    -maxdepth 1 \
    -type f \
    \( -name '*.cmi' -o -name '*.cmt' -o -name '*.cmti' -o -name '*.cmx' \) |
    while IFS= read -r host_metadata_artifact; do
      artifact_name=${host_metadata_artifact##*/}
      test ! -f "$target_package_root/$artifact_name" || continue
      target_candidates="$work_root/$artifact_name.target-candidates"
      find "$build_directory/default.ios" -type f -name "$artifact_name" \
        >"$target_candidates"
      candidate_count=$(wc -l <"$target_candidates" | tr -d ' ')
      if test "$candidate_count" -eq 0; then
        case "$artifact_name" in
          *.cmt | *.cmti) continue ;;
          *) fail "$package_name cannot resolve a target build artifact for $artifact_name" ;;
        esac
      fi
      candidate_digest_count=$(
        while IFS= read -r target_candidate; do
          shasum -a 256 "$target_candidate" | awk '{ print $1 }'
        done <"$target_candidates" | sort -u | wc -l | tr -d ' '
      )
      test "$candidate_digest_count" -eq 1 ||
        fail "$package_name has conflicting target build artifacts for $artifact_name"
      target_candidate=$(sed -n '1p' "$target_candidates")
      cp -f "$target_candidate" "$target_package_root/$artifact_name"
    done
fi

if test "$package_capability" = System_sqlite; then
  sqlite_link_found=false
  find "$target_package_root" -type f -name '*.cmxa' -print |
    while IFS= read -r sqlite_archive; do
      if OPAMROOT="$opam_root" opam exec --switch="$switch" -- \
        ocamlobjinfo "$sqlite_archive" | grep -F -- '-lsqlite3' >/dev/null; then
        printf '%s\n' "$sqlite_archive" >"$work_root/system-sqlite-link"
      fi
    done
  test -f "$work_root/system-sqlite-link" ||
    fail "$package_name target archive lost its external system -lsqlite3 requirement"
  if test "$package_name" = sqlite3; then
    test -f "$target_package_root/libsqlite3_stubs.a" ||
      fail "sqlite3 target stubs archive is missing"
    test ! -f "$target_package_root/libsqlite3.a" ||
      fail "a bundled SQLite implementation was staged"
  fi
fi

representative_object=$(
  find "$build_directory/default.ios" -type f -name '*.o' |
    sort |
    sed -n '1p'
)
if test -n "$representative_object"; then
  sh "$script_directory/verify_macho.sh" \
    "$representative_object" \
    "$expected_platform" \
    arm64 \
    "$expected_minimum"
else
  test "$package_name" = stdlib-shims || test -f "$virtual_interface_marker" ||
    fail "no representative target object was produced for $package_name"
  printf '%s\n' \
    "No Mach-O object is expected for interface-only package $package_name"
fi

if rg -a -l \
  '/opt/homebrew|/usr/local|MacOSX[0-9]|/private/tmp/bonsai-flutter-opam|-mpopcnt' \
  "$target_package_root" >/dev/null; then
  fail "$package_name staged a prohibited host path or CPU flag"
fi

printf '%s\n' \
  "iOS $target runtime package build passed: $package_name $package_version"
