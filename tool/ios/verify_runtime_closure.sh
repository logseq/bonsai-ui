#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
. "$script_directory/toolchain.lock"
default_lock="$repository_root/vendor/opam-ios/runtime-closure.lock"
capability_lock="$script_directory/closure_capabilities.lock"

fail() {
  printf '%s\n' "iOS runtime closure verification failure: $1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "required command is unavailable: $1"
}

metadata() {
  key=$1
  sed -n "s/^# metadata\.$key=//p" "$closure_lock" | sed -n '1p'
}

canonical_features() {
  printf '%s' "$1" |
    tr ',' '\n' |
    sed '/^[[:space:]]*$/d; s/^[[:space:]]*//; s/[[:space:]]*$//' |
    sort -u |
    paste -sd, -
}

has_feature() {
  feature=$1
  case ",$selected_features," in
    *,$feature,*) return 0 ;;
    *) return 1 ;;
  esac
}

check_lock_only=false
closure_lock=$default_lock
selected_features=
target_lib=

while test "$#" -gt 0; do
  case "$1" in
    --check-lock-only)
      check_lock_only=true
      shift
      ;;
    --lock)
      test "$#" -ge 2 || fail "--lock requires a path"
      closure_lock=$2
      shift 2
      ;;
    --features)
      test "$#" -ge 2 || fail "--features requires a comma-separated value"
      selected_features=$2
      shift 2
      ;;
    --target-lib)
      test "$#" -ge 2 || fail "--target-lib requires a path"
      target_lib=$2
      shift 2
      ;;
    *) fail "unknown option: $1" ;;
  esac
done

require_command awk
require_command grep
require_command paste
require_command sed
require_command shasum
require_command sort
require_command tr
require_command wc

test -f "$closure_lock" || fail "missing closure lock: $closure_lock"
test -f "$capability_lock" || fail "missing capability lock: $capability_lock"
test "$(metadata format)" = bonsai-swiftui-ios-closure-v2 ||
  fail "unsupported or missing closure lock format"

if test -z "$selected_features"; then selected_features=$(metadata features); fi
selected_features=$(canonical_features "$selected_features")
has_feature core || selected_features=$(canonical_features "core,$selected_features")

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/bonsai-swiftui-ios-closure.XXXXXX")
body_file="$temporary_directory/body"
target_packages_file="$temporary_directory/target-packages"

cleanup() {
  rm -rf "$temporary_directory"
}

trap cleanup EXIT HUP INT TERM

awk -F '|' '
  /^#/ || NF == 0 { next }
  NF != 9 { exit 2 }
  $1 !~ /^[A-Za-z0-9_.+-]+$/ { exit 3 }
  $2 == "" { exit 4 }
  $3 != "target-package" && $3 != "host-package" && $3 != "target-build" { exit 5 }
  $4 !~ /^[A-Za-z0-9_.+-]+$/ { exit 6 }
  $5 !~ /^[A-Za-z0-9_.+-]+$/ { exit 7 }
  $6 !~ /^(https:\/\/|opam-metadata:\/\/)/ { exit 8 }
  $7 !~ /^[0-9a-f]{64}$/ { exit 9 }
  $3 == "target-package" && ($8 == "" || $8 == "-") { exit 10 }
  { print }
' "$closure_lock" >"$body_file" || fail "closure lock has an invalid row"

test -s "$body_file" || fail "closure lock has no package rows"
actual_package_count=$(wc -l <"$body_file" | tr -d ' ')
actual_target_package_count=$(awk -F '|' '$3 == "target-package" { count++ } END { print count + 0 }' "$body_file")
actual_host_package_count=$(awk -F '|' '$3 == "host-package" { count++ } END { print count + 0 }' "$body_file")
actual_target_build_count=$(awk -F '|' '$3 == "target-build" { count++ } END { print count + 0 }' "$body_file")
actual_component_count=$(
  awk -F '|' '$3 == "target-package" { count += split($8, components, ",") } END { print count + 0 }' "$body_file"
)

test "$(metadata package-count)" = "$actual_package_count" ||
  fail "metadata.package-count differs from package rows"
test "$(metadata target-package-count)" = "$actual_target_package_count" ||
  fail "metadata.target-package-count differs from package rows"
test "$(metadata host-package-count)" = "$actual_host_package_count" ||
  fail "metadata.host-package-count differs from package rows"
test "$(metadata target-build-count)" = "$actual_target_build_count" ||
  fail "metadata.target-build-count differs from package rows"
test "$(metadata component-count)" = "$actual_component_count" ||
  fail "metadata.component-count differs from target components"
test "$(sort -u "$body_file" | wc -l | tr -d ' ')" = "$actual_package_count" ||
  fail "closure lock contains a duplicate row"
test "$(awk -F '|' '{ print $1 }' "$body_file" | sort -u | wc -l | tr -d ' ')" = "$actual_package_count" ||
  fail "closure lock contains a duplicate opam package"

actual_digest=$(shasum -a 256 "$body_file" | awk '{ print $1 }')
test "$(metadata digest)" = "$actual_digest" || fail "lock digest differs from package rows"

if grep -Ei '(refs/heads/main|#main([^0-9a-f]|$)|archive/main)' "$closure_lock" >/dev/null; then
  fail "closure lock contains a floating main source reference"
fi

awk -F '|' '$3 == "target-package" || $3 == "target-build" { print $1 }' \
  "$body_file" | sort -u >"$target_packages_file"
dependency_pairs_file="$temporary_directory/dependency-pairs"
awk -F '|' '
  ($3 == "target-package" || $3 == "target-build") && $9 != "-" {
    count = split($9, dependencies, ",")
    for (dependency_index = 1; dependency_index <= count; dependency_index++) {
      print $1 "|" dependencies[dependency_index]
    }
  }
' "$body_file" >"$dependency_pairs_file"
while IFS='|' read -r package dependency; do
  grep -Fx -- "$dependency" "$target_packages_file" >/dev/null ||
    fail "$package is missing target dependency $dependency"
done <"$dependency_pairs_file"

while IFS='|' read -r package _version role capability _build _source _sha components dependencies; do
  test "$role" = target-package || test "$role" = target-build || continue
  case "$capability" in
    Pure_ocaml | Foreign_stubs | Filesystem) ;;
    System_sqlite)
      has_feature sqlite || fail "$package requires the sqlite feature"
      ;;
    Network)
      has_feature network || fail "$package requires the network feature"
      ;;
    Entropy)
      has_feature network || fail "$package requires the network feature for its entropy recipe"
      ;;
    Unsupported)
      fail "$package uses unsupported capability; required cross-build recipe: add an explicit capability recipe"
      ;;
    *) fail "$package has unknown unsupported capability $capability; required cross-build recipe: register it explicitly" ;;
  esac
  if test "$role" = target-package; then
    test "$components" != - || fail "$package has no target components"
  fi
done <"$body_file"

if test "$check_lock_only" = true; then
  printf '%s\n' \
    "iOS closure lock verification passed: $actual_target_package_count target packages, $actual_host_package_count host-only packages, $actual_component_count components"
  exit 0
fi

if test -z "$target_lib"; then
  switch=${HOST_OCAML_SWITCH:-"$repository_root/_build/ios/switches/iphoneos"}
  target_lib="$switch/_opam/ios-sysroot/lib"
fi
test -d "$target_lib" || fail "target library directory does not exist: $target_lib"
require_command find
require_command ocamlobjinfo
iphoneos_switch=${IPHONEOS_SWITCH:-"$repository_root/_build/ios/switches/iphoneos"}
cross_ocamlfind="$iphoneos_switch/_opam/bin/ocamlfind"
test -x "$cross_ocamlfind" || fail "missing iPhoneOS findlib executable: $cross_ocamlfind"
artifact_list="$temporary_directory/artifacts"
: >"$artifact_list"

# verify_macho.sh checks arm64 and LC_BUILD_VERSION platform IOS before any
# target package is accepted as an iPhoneOS artifact.
while IFS='|' read -r package _version role capability _build _source _sha components _dependencies; do
  test "$role" = target-package || test "$role" = target-build || continue
  test "$components" != - || continue
  package_artifact_count=0
  sqlite_link_found=false
  component_file="$temporary_directory/components"
  printf '%s\n' "$components" | tr ',' '\n' >"$component_file"
  while IFS= read -r component; do
    component_directory=$(
      OCAMLPATH="$target_lib${OCAMLPATH:+:$OCAMLPATH}" \
        "$cross_ocamlfind" -toolchain ios query "$component" 2>/dev/null
    ) || fail "missing target artifact for $package component $component"
    case "$component_directory" in
      "$target_lib" | "$target_lib"/*) ;;
      *) fail "$package component $component resolved outside the selected target closure: $component_directory" ;;
    esac
    component_archives="$temporary_directory/component-archives"
    (
      OCAMLPATH="$target_lib${OCAMLPATH:+:$OCAMLPATH}" \
        "$cross_ocamlfind" -toolchain ios query \
          -predicates=native \
          -format '%+a' \
          "$component" 2>/dev/null |
        sed -n '/\.cmxa$/p'
    ) >"$component_archives"
    if test -s "$component_archives"; then
      while IFS= read -r component_artifact; do
        case "$component_artifact" in
          "$target_lib"/*) ;;
          *) fail "native archive resolved outside the selected target closure: $component_artifact" ;;
        esac
        test -f "$component_artifact" || fail "missing target native metadata: $component_artifact"
        native_archive="${component_artifact%.cmxa}.a"
        test -f "$native_archive" || fail "missing target native archive: $native_archive"
        printf '%s\n' "$native_archive" >>"$artifact_list"
        if test "$capability" = System_sqlite &&
          ocamlobjinfo "$component_artifact" | grep -F -- '-lsqlite3' >/dev/null; then
          sqlite_link_found=true
        fi
      done <"$component_archives"
    else
      component_exports=$(
        OCAMLPATH="$target_lib${OCAMLPATH:+:$OCAMLPATH}" \
          "$cross_ocamlfind" -toolchain ios query \
            -format '%(exports)' \
            "$component" 2>/dev/null
      )
      if test -n "$component_exports"; then
        alias_requires=$(
          OCAMLPATH="$target_lib${OCAMLPATH:+:$OCAMLPATH}" \
            "$cross_ocamlfind" -toolchain ios query \
              -format '%(requires)' \
              "$component" 2>/dev/null
        )
        test -n "$alias_requires" ||
          fail "component alias $component has no target dependency"
        for alias_dependency in $alias_requires; do
          OCAMLPATH="$target_lib${OCAMLPATH:+:$OCAMLPATH}" \
            "$cross_ocamlfind" -toolchain ios query "$alias_dependency" >/dev/null ||
            fail "component alias $component has missing target dependency $alias_dependency"
        done
      elif find "$component_directory" -maxdepth 1 -type f -name '*.cmi' |
        grep . >/dev/null; then
        # Interface-only virtual libraries have no native objects. Libraries
        # with concrete modules must retain every module, not merely one .cmx.
        # As in the builder, the host supplies filenames, never target bytes.
        host_component_directory=$(
          OCAMLPATH= "$cross_ocamlfind" query "$component" 2>/dev/null
        ) || fail "missing virtual component inventory: $component"
        case "$host_component_directory" in
          "$iphoneos_switch/_opam/lib"/*) ;;
          *) fail "virtual component inventory is outside the selected switch: $component" ;;
        esac
        for host_artifact in "$host_component_directory"/*.cmi "$host_component_directory"/*.cmx "$host_component_directory"/*.o; do
          test -f "$host_artifact" || continue
          artifact_name=${host_artifact##*/}
          test -f "$component_directory/$artifact_name" ||
            fail "missing target virtual module artifact: $component/$artifact_name"
        done
      else
        fail "missing target interface artifact for virtual component $component"
      fi
    fi
    package_artifact_count=$((package_artifact_count + 1))
    find "$component_directory" -type f \( -name '*.o' -o -name '*.a' \) -print >>"$artifact_list"
  done <"$component_file"
  test "$package_artifact_count" -gt 0 || fail "missing target artifact for $package"
  if test "$capability" = System_sqlite; then
    test "$sqlite_link_found" = true ||
      fail "$package target archive does not link the system -lsqlite3 library"
  fi
done <"$body_file"

# Component directories overlap; audit each installed artifact only once.
sort -u "$artifact_list" >"$temporary_directory/unique-artifacts"
while IFS= read -r artifact; do
  case "$artifact" in
    *.o)
      "$script_directory/verify_macho.sh" "$artifact" IOS "$IPHONEOS_ARCH" "$IOS_DEPLOYMENT_TARGET"
      ;;
    *.a)
      printf '%s\n' "Auditing static archive: $artifact"
      members="$temporary_directory/members"
      xcrun ar -t "$artifact" >"$members" || fail "cannot list archive: $artifact"
      # Extraction must not escape its directory or overwrite duplicate members.
      while IFS= read -r member; do
        case "$member" in
          '' | . | .. | */*) fail "invalid archive member in $artifact: $member" ;;
        esac
      done <"$members"
      test "$(sort -u "$members" | wc -l)" = "$(wc -l <"$members")" ||
        fail "duplicate archive members in $artifact"
      extraction_directory=$(mktemp -d "$temporary_directory/archive.XXXXXX")
      (cd "$extraction_directory" && xcrun ar -x "$artifact") || fail "cannot extract archive: $artifact"
      while IFS= read -r member; do
        case "$member" in __.SYMDEF | '__.SYMDEF SORTED' | __.SYMDEF_64 | '__.SYMDEF_64 SORTED') continue ;; esac
        "$script_directory/verify_macho.sh" "$extraction_directory/$member" IOS "$IPHONEOS_ARCH" "$IOS_DEPLOYMENT_TARGET"
      done <"$members"
      rm -rf "$extraction_directory"
      ;;
  esac
done <"$temporary_directory/unique-artifacts"

printf '%s\n' \
  "iOS runtime closure verification passed: $actual_target_package_count target packages, $actual_host_package_count host-only packages, $actual_component_count components"
