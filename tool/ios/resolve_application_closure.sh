#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
capability_lock="$script_directory/closure_capabilities.lock"

# shellcheck source=tool/ios/toolchain.lock
. "$script_directory/toolchain.lock"

fail() {
  printf '%s\n' "iOS application closure resolution failure: $1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 ||
    fail "required command is unavailable: $1"
}

canonical_features() {
  printf '%s' "$1" |
    tr ',' '\n' |
    sed '/^[[:space:]]*$/d; s/^[[:space:]]*//; s/[[:space:]]*$//' |
    sort -u |
    paste -sd, -
}

lock_digest() {
  lock=$1
  awk '!/^# metadata.digest=/' "$lock" | shasum -a 256 | awk '{ print $1 }'
}

sdk_identity() {
  lock=$1
  features=$(canonical_features "$2")
  test -f "$lock" || fail "missing closure lock: $lock"
  closure_digest=$(lock_digest "$lock")
  features_digest=$(printf '%s' "$features" | shasum -a 256 | awk '{ print $1 }')
  toolchain_digest=$(shasum -a 256 "$script_directory/toolchain.lock" | awk '{ print $1 }')
  printf '%s\000%s\000%s\000%s' \
    bonsai-swiftui-iphoneos-sdk-v2 \
    "$features_digest" \
    "$closure_digest" \
    "$toolchain_digest" |
    shasum -a 256 |
    awk '{ print $1 }'
}

application_opam_roots() {
  opam_file=$1
  awk '
    /^depends:[[:space:]]*\[/ { in_depends = 1; next }
    in_depends && /^[[:space:]]*\]/ { exit }
    in_depends && match($0, /"[A-Za-z0-9_.+-]+"/) {
      package = substr($0, RSTART + 1, RLENGTH - 2)
      constraint = $0
      sub(/^[^{]*\{/, "", constraint)
      sub(/\}[^}]*$/, "", constraint)
      if (constraint !~ /(^|[[:space:]&(])=[[:space:]]*"/) {
        printf "application opam root %s must use an exact version constraint\n", package > "/dev/stderr"
        invalid = 1
        exit
      }
      if (package != "ocaml" && package != "dune") print package
    }
    END { if (invalid) exit 1 }
  ' "$opam_file"
}

is_builtin_library() {
  case "$1" in
    str | unix | threads | dynlink | bigarray) return 0 ;;
    *) return 1 ;;
  esac
}

is_framework_library() {
  case "$1" in
    bonsai_swiftui | bonsai_swiftui.* | bonsai_swiftui_*) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_findlib_closure() {
  external_libraries=$1
  components=$2
  closure_roots=$3
  : >"$components"
  : >"$closure_roots"

  while IFS= read -r library; do
    test -n "$library" || continue
    is_builtin_library "$library" && continue
    if ! is_framework_library "$library"; then
      printf '%s\n' "$library" >>"$closure_roots"
    fi
    if OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
      ocamlfind query "$library" >/dev/null 2>&1; then
      OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
        ocamlfind query -recursive -p-format "$library" >>"$components"
    else
      fail "External Dune library $library does not resolve in the pinned host switch"
    fi
  done <"$external_libraries"

  grep -Ev \
    '^(bonsai_swiftui($|[._].*)|runtime_events|seq|str|threads(\.posix)?|unix|dynlink|bigarray)$' \
    "$components" | sort -u >"$components.sorted"
  mv "$components.sorted" "$components"
  sort -u "$closure_roots" >"$closure_roots.sorted"
  mv "$closure_roots.sorted" "$closure_roots"
}

extract_pps_libraries() {
  awk '
    {
      line = $0
      sub(/;.*/, "", line)
      if (!in_pps) {
        if (!match(line, /\(pps([[:space:]]|\))/)) next
        line = substr(line, RSTART)
        in_pps = 1
        depth = 0
        accept = 1
      }
      open_count = gsub(/\(/, "(", line)
      close_count = gsub(/\)/, ")", line)
      depth += open_count - close_count
      gsub(/[()]/, " ", line)
      count = split(line, words, /[[:space:]]+/)
      for (word_index = 1; word_index <= count; word_index++) {
        word = words[word_index]
        if (word == "--") accept = 0
        if (accept && word != "" && word != "pps" &&
            word ~ /^[A-Za-z0-9][A-Za-z0-9_.+-]*$/) print word
      }
      if (depth <= 0) {
        in_pps = 0
        depth = 0
        accept = 0
      }
    }
  ' "$1"
}

if test "${1:-}" = --identity; then
  shift
  lock=
  features=
  while test "$#" -gt 0; do
    case "$1" in
      --lock)
        test "$#" -ge 2 || fail "--lock requires a path"
        lock=$2
        shift 2
        ;;
      --features)
        test "$#" -ge 2 || fail "--features requires a comma-separated value"
        features=$2
        shift 2
        ;;
      *) fail "unknown identity option: $1" ;;
    esac
  done
  test -n "$lock" || fail "--lock is required"
  test -n "$features" || fail "--features is required"
  sdk_identity "$lock" "$features"
  exit 0
fi

if test "${1:-}" = --application-opam-roots; then
  test "$#" -eq 2 || fail "--application-opam-roots requires one opam file"
  test -f "$2" || fail "application opam file does not exist: $2"
  roots=$(application_opam_roots "$2") || exit 1
  printf '%s\n' "$roots" | sort -u
  exit 0
fi

if test "${1:-}" = --findlib-closure; then
  test "$#" -eq 4 ||
    fail "--findlib-closure requires external-library, component, and root paths"
  test -f "$2" || fail "external library file does not exist: $2"
  opam_root=${OPAMROOT:-"$repository_root/_build/ios/opam-root"}
  host_switch=${HOST_OCAML_SWITCH:-}
  test -n "$host_switch" || fail "HOST_OCAML_SWITCH is required"
  resolve_findlib_closure "$2" "$3" "$4"
  exit 0
fi

test "$#" -eq 3 ||
  fail "usage: resolve_application_closure.sh iphoneos <project-root> <output-lock>"
target=$1
project_root=$2
output_lock=$3
test "$target" = iphoneos || fail "expected iphoneos"
test -d "$project_root" || fail "application root does not exist: $project_root"
test -f "$capability_lock" || fail "missing capability lock: $capability_lock"

require_command awk
require_command curl
require_command find
require_command mktemp
require_command ocamlfind
require_command opam
require_command paste
require_command rg
require_command sed
require_command shasum
require_command sort
require_command tar
require_command tr

opam_root=${OPAMROOT:-"$repository_root/_build/ios/opam-root"}
host_switch=${HOST_OCAML_SWITCH:-}
test -n "$host_switch" ||
  fail "HOST_OCAML_SWITCH must name the pinned native build-dependency switch"
test -x "$host_switch/_opam/bin/ocamlc" || fail "host switch is unavailable: $host_switch"

features=$(canonical_features "${BONSAI_SWIFTUI_FEATURES:-core}")
case ",$features," in
  *,core,*) ;;
  *) features=$(canonical_features "core,$features") ;;
esac

application_opam_file=${APPLICATION_OPAM_FILE:-}
if test -z "$application_opam_file"; then
  application_opam_file=$(
    find "$project_root" -maxdepth 1 -type f -name '*.opam' | sort | sed -n '1p'
  )
fi
test -n "$application_opam_file" ||
  fail "application must provide pinned opam package metadata"
test -f "$application_opam_file" ||
  fail "application opam file does not exist: $application_opam_file"

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/bonsai-swiftui-resolver.XXXXXX")
external_libraries_file="$temporary_directory/external-libraries"
components_file="$temporary_directory/components"
closure_roots_file="$temporary_directory/closure-roots"
target_packages_file="$temporary_directory/target-packages"
component_owners_file="$temporary_directory/component-owners"
host_packages_file="$temporary_directory/host-packages"
ppx_libraries_file="$temporary_directory/ppx-libraries"
application_ppx_libraries_file="$temporary_directory/application-ppx-libraries"
ppx_packages_file="$temporary_directory/ppx-packages"
target_build_libraries_file="$temporary_directory/target-build-libraries"
target_build_packages_file="$temporary_directory/target-build-packages"
all_target_packages_file="$temporary_directory/all-target-packages"
rows_file="$temporary_directory/rows"
body_file="$temporary_directory/body"
source_cache="$repository_root/_build/ios/resolver-sources"

cleanup() {
  rm -rf "$temporary_directory"
}

trap cleanup EXIT HUP INT TERM
mkdir -p "$source_cache" "$(dirname -- "$output_lock")"

dune_closure_helper=${BONSAI_SWIFTUI_DUNE_CLOSURE_HELPER:-}
native_target=${BONSAI_SWIFTUI_NATIVE_TARGET:-}
test -n "$dune_closure_helper" ||
  fail "BONSAI_SWIFTUI_DUNE_CLOSURE_HELPER must name the OCaml semantic closure helper"
test -x "$dune_closure_helper" ||
  fail "Dune semantic closure helper is unavailable: $dune_closure_helper"
test -n "$native_target" ||
  fail "BONSAI_SWIFTUI_NATIVE_TARGET must name the application native embed target"

if ! OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
  "$dune_closure_helper" \
    internal-resolve-dune-closure \
    --project-root "$project_root" \
    --target "$native_target" \
    >"$external_libraries_file"
then
  fail "Dune workspace/configuration error while resolving $native_target"
fi
test -s "$external_libraries_file" ||
  fail "application native embed target has no external Dune dependencies"

: >"$application_ppx_libraries_file.unsorted"
find "$project_root" \
  \( -type d \( -name .git -o -name _build \) -prune \) -o \
  -type f -name dune -print |
  LC_ALL=C sort |
  while IFS= read -r dune_file; do
    extract_pps_libraries "$dune_file"
  done >"$application_ppx_libraries_file.unsorted"
sort -u \
  "$application_ppx_libraries_file.unsorted" \
  >"$application_ppx_libraries_file.all"
grep -Fxf \
  "$external_libraries_file" \
  "$application_ppx_libraries_file.all" \
  >"$application_ppx_libraries_file" || true

if test -s "$application_ppx_libraries_file"; then
  grep -Fvx -f "$application_ppx_libraries_file" "$external_libraries_file" \
    >"$external_libraries_file.target" || true
  while IFS= read -r ppx_library; do
    OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
      ocamlfind query "$ppx_library" >/dev/null 2>&1 ||
      fail "Application PPX library $ppx_library does not resolve in the pinned host switch"
    runtime_dependencies=$(
      OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
        ocamlfind query -format '%(ppx_runtime_deps)' "$ppx_library"
    )
    for runtime_dependency in $runtime_dependencies; do
      printf '%s\n' "$runtime_dependency" >>"$external_libraries_file.target"
    done
  done <"$application_ppx_libraries_file"
  sort -u "$external_libraries_file.target" >"$external_libraries_file"
fi

if ! application_packages=$(application_opam_roots "$application_opam_file"); then
  fail "application opam metadata has invalid dependency constraints"
fi
application_packages=$(printf '%s\n' "$application_packages" | sort -u | paste -sd, -)
test -n "$application_packages" || fail "application opam metadata has no dependency roots"

resolve_findlib_closure \
  "$external_libraries_file" \
  "$components_file" \
  "$closure_roots_file"

test -s "$components_file" || fail "application has no target findlib components"

owner_of_component() {
  component=$1
  meta=$(
    OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
      ocamlfind query -format '%m' "$component"
  )
  owner=$(
    OPAMROOT="$opam_root" opam list \
      --switch="$host_switch" \
      --installed \
      --owns-file="$meta" \
      --short \
      --columns=name |
      sed -n '1p'
  )
  test -n "$owner" || fail "Dune library $component is not owned by an installed opam package"
  printf '%s\n' "$owner"
}

while IFS= read -r component; do
  owner=$(owner_of_component "$component")
  printf '%s|%s\n' "$component" "$owner"
done <"$components_file" >"$component_owners_file"
awk -F '|' '{ print $2 }' "$component_owners_file" | sort -u >"$target_packages_file"

component_list_for_package() {
  package=$1
  awk -F '|' -v package="$package" '$2 == package { print $1 }' \
    "$component_owners_file" |
    paste -sd, -
}

target_dependencies_for_package() {
  package=$1
  components=$(component_list_for_package "$package")
  test -n "$components" || {
    printf '%s\n' -
    return
  }
  printf '%s\n' "$components" |
    tr ',' '\n' |
    while IFS= read -r component; do
      OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
        ocamlfind query -recursive -p-format "$component"
    done |
    grep -Ev '^(runtime_events|seq|str|threads(\.posix)?|unix|dynlink|bigarray)$' |
    sort -u |
    while IFS= read -r dependency_component; do
      awk -F '|' -v component="$dependency_component" \
        '$1 == component { print $2; exit }' "$component_owners_file"
    done |
    sort -u |
    grep -Fvx -- "$package" |
    paste -sd, - |
    awk 'NF { print; found = 1 } END { if (!found) print "-" }'
}

source_url_for_package() {
  package=$1
  pin=$(
    OPAMROOT="$opam_root" opam list \
      --switch="$host_switch" \
      --installed \
      --short \
      --columns=pin \
      "$package" |
      sed -n '1p'
  )
  if test -n "$pin"; then
    case "$pin" in
      git+https://github.com/*.git\#[0-9a-f][0-9a-f]*)
        repository=${pin#git+https://github.com/}
        commit=${repository#*#}
        repository=${repository%%#*}
        repository=${repository%.git}
        printf '%s' "$commit" | grep -E '^[0-9a-f]{40}$' >/dev/null ||
          fail "$package pin does not name an exact 40-character commit: $pin"
        printf '%s\n' "https://github.com/$repository/archive/$commit.tar.gz"
        return
        ;;
      *) fail "$package has a floating or unsupported pin: $pin" ;;
    esac
  fi
  source_url=$(
    OPAMROOT="$opam_root" opam show --switch="$host_switch" --raw "$package" |
    sed -n '/^url[[:space:]]*{/,/^}/p' |
    sed -n 's/.*"\(http[s]*:[^"]*\)".*/\1/p' |
    sed -n '1p'
  )
  case "$source_url" in
    http://erratique.ch/*) source_url="https://${source_url#http://}" ;;
  esac
  printf '%s\n' "$source_url"
}

prepare_source() {
  package=$1
  source_url=$2
  url_digest=$(printf '%s' "$source_url" | shasum -a 256 | awk '{ print $1 }')
  archive="$source_cache/$url_digest.archive"
  source_directory="$source_cache/$url_digest.source"
  if test ! -f "$archive"; then
    rm -f "$archive.partial"
    if ! curl \
      --fail \
      --location \
      --retry 5 \
      --retry-all-errors \
      --silent \
      --show-error \
      --output "$archive.partial" \
      "$source_url"; then
      rm -f "$archive.partial"
      fail "$package source is unavailable: $source_url"
    fi
    mv "$archive.partial" "$archive"
  fi
  if test ! -d "$source_directory"; then
    mkdir "$source_directory.partial"
    tar -xf "$archive" -C "$source_directory.partial" --strip-components=1
    mv "$source_directory.partial" "$source_directory"
  fi
  printf '%s|%s\n' "$archive" "$source_directory"
}

resolve_host_build_packages() {
  cp "$application_ppx_libraries_file" "$ppx_libraries_file.unsorted"
  : >"$target_build_libraries_file.unsorted"
  while IFS= read -r package; do
    source_url=$(source_url_for_package "$package")
    test -n "$source_url" || continue
    prepared=$(prepare_source "$package" "$source_url")
    source_directory=${prepared#*|}
    components=$(component_list_for_package "$package")
    printf '%s\n' "$components" | tr ',' '\n' |
      while IFS= read -r component; do
        rg --files-with-matches --fixed-strings "(public_name $component)" \
          "$source_directory" --glob dune |
          while IFS= read -r component_dune; do
            extract_pps_libraries "$component_dune" >>"$ppx_libraries_file.unsorted"
            rg -o '%\{lib:[A-Za-z0-9_.+-]+:' "$component_dune" |
              sed 's/^%{lib://; s/:$//' \
                >>"$target_build_libraries_file.unsorted" || true
          done
      done
  done <"$target_packages_file"
  sort -u "$ppx_libraries_file.unsorted" >"$ppx_libraries_file"
  sort -u "$target_build_libraries_file.unsorted" >"$target_build_libraries_file"

  : >"$ppx_packages_file.unsorted"
  while IFS= read -r ppx_library; do
    test -n "$ppx_library" || continue
    if ! OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
      ocamlfind query "$ppx_library" >/dev/null 2>&1; then
      # Private PPX libraries are built from the same source tree by Dune and
      # deliberately have no installed findlib owner.
      continue
    fi
    owner=$(owner_of_component "$ppx_library")
    printf '%s\n' "$owner" >>"$ppx_packages_file.unsorted"
  done <"$ppx_libraries_file"
  sort -u "$ppx_packages_file.unsorted" >"$ppx_packages_file"

  : >"$target_build_packages_file"
  while IFS= read -r target_build_library; do
    test -n "$target_build_library" || continue
    OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
      ocamlfind query "$target_build_library" >/dev/null 2>&1 ||
      fail "target build library $target_build_library does not resolve in the pinned host switch"
    owner=$(owner_of_component "$target_build_library")
    if grep -Fx "$owner" "$target_packages_file" >/dev/null; then continue; fi
    printf '%s|%s\n' "$target_build_library" "$owner" >>"$component_owners_file"
    printf '%s\n' "$owner" >>"$target_build_packages_file"
  done <"$target_build_libraries_file"
  sort -u "$component_owners_file" -o "$component_owners_file"
  sort -u "$target_build_packages_file" -o "$target_build_packages_file"
  cat "$target_packages_file" "$target_build_packages_file" |
    sort -u >"$all_target_packages_file"

  host_roots=$(
    {
      printf '%s\n' "$application_packages" | tr ',' '\n'
      cat "$ppx_packages_file"
    } | sed '/^$/d' | sort -u | paste -sd, -
  )
  OPAMROOT="$opam_root" opam list \
    --switch="$host_switch" \
    --installed \
    --required-by="$host_roots" \
    --recursive \
    --sort \
    --short \
    --columns=name |
    sort -u |
    comm -23 - "$all_target_packages_file" |
    grep -Ev '^(base-(bigarray|bytes|domains|nnp|threads|unix)|conf-|dune|ocaml|ocaml-base-compiler|ocaml-config|ocaml-ios64|ocaml-options-vanilla|ocamlfind|seq)$' \
      >"$host_packages_file" || true
}

capability_for_package() {
  package=$1
  components=$2
  source_directory=$3
  capability_row=$(
    awk -F '|' -v package="$package" '
      !/^#/ && $1 == package { print; exit }
    ' "$capability_lock"
  )
  if test -z "$capability_row"; then
    capability_row=$(
      printf '%s\n' "$components" |
        tr ',' '\n' |
        while IFS= read -r component; do
          awk -F '|' -v component="$component" '
            !/^#/ && $1 == component { print; exit }
          ' "$capability_lock"
        done |
        sed -n '1p'
    )
  fi
  if test -n "$capability_row"; then
    printf '%s\n' "$capability_row"
    return
  fi
  # A system SQLite linker dependency is a capability of the selected
  # artifacts, not an identity assigned to a particular package name.
  for component in $(printf '%s\n' "$components" | tr ',' ' '); do
    archives=$(
      OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
        ocamlfind query -predicates native -a-format "$component" 2>/dev/null || true
    )
    for archive in $archives; do
      test -f "$archive" || continue
      if OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
        ocamlobjinfo "$archive" 2>/dev/null |
        sed -n 's/^Extra C object files:[[:space:]]*//p' |
        tr ' ' '\n' |
        grep -Fx -- '-lsqlite3' >/dev/null
      then
        printf '%s|System_sqlite|sqlite|dune-ios-system-sqlite\n' "$package"
        return
      fi
    done
  done
  printf '%s\n' "$components" | tr ',' '\n' |
    while IFS= read -r component; do
      OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
        ocamlfind query -recursive -p-format "$component"
    done |
    grep -Fx unix >"$temporary_directory/unix-capability" || true
  if test -s "$temporary_directory/unix-capability"; then
    rm -f "$temporary_directory/unix-capability"
    fail "$package uses unsupported capability Unix platform APIs; required cross-build recipe: add an explicit filesystem, networking, entropy, or process capability entry to closure_capabilities.lock"
  fi
  printf '%s\n' "$components" | tr ',' '\n' |
    while IFS= read -r component; do
      archives=$(
        OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
          ocamlfind query -predicates native -a-format "$component" 2>/dev/null || true
      )
      for archive in $archives; do
        test -f "$archive" || continue
        if OPAMROOT="$opam_root" opam exec --switch="$host_switch" -- \
          ocamlobjinfo "$archive" 2>/dev/null |
          grep -E '^Extra C object files:[[:space:]]+[^[:space:]]' >/dev/null; then
          printf '%s\n' foreign >"$temporary_directory/foreign-stubs"
        fi
      done
    done
  printf '%s\n' "$components" | tr ',' '\n' |
    while IFS= read -r component; do
      rg --files-with-matches --fixed-strings "(public_name $component)" \
        "$source_directory" --glob dune |
        while IFS= read -r component_dune; do
          if rg '\(foreign_stubs|\(foreign_archives|\(c_library_flags|ctypes|cargo|rustc' \
            "$component_dune" >/dev/null; then
            printf '%s\n' foreign >"$temporary_directory/foreign-stubs"
          fi
        done
    done
  if test -f "$temporary_directory/foreign-stubs"; then
    rm -f "$temporary_directory/foreign-stubs"
    fail "$package uses unsupported capability foreign stubs; required cross-build recipe: add an explicit entry to closure_capabilities.lock"
  fi
  printf '%s|Pure_ocaml|core|generic-pure-ocaml\n' "$package"
}

validate_required_feature() {
  package=$1
  capability=$2
  required_feature=$3
  recipe=$4
  if test "$capability" = Unsupported; then
    fail "$package uses unsupported capability; required cross-build recipe: $recipe"
  fi
  if test "$required_feature" != -; then
    case ",$features," in
      *,$required_feature,*) ;;
      *) fail "$package requires the $required_feature feature for cross-build recipe $recipe" ;;
    esac
  fi
}

row_for_package() {
  package=$1
  role=$2
  version=$(
    OPAMROOT="$opam_root" opam show \
      --switch="$host_switch" \
      --field=installed-version \
      "$package"
  )
  source_url=$(source_url_for_package "$package")
  components=-
  dependencies=-
  capability=Host_only
  build_mechanism=opam
  if test -n "$source_url"; then
    prepared=$(prepare_source "$package" "$source_url")
    archive=${prepared%%|*}
    source_directory=${prepared#*|}
    source_sha256=$(shasum -a 256 "$archive" | awk '{ print $1 }')
  elif test "$role" = host-package; then
    source_url="opam-metadata://$package.$version"
    source_sha256=$(
      OPAMROOT="$opam_root" opam show --switch="$host_switch" --raw "$package" |
        shasum -a 256 |
        awk '{ print $1 }'
    )
  else
    fail "$package has no immutable source URL"
  fi
  if test "$role" = target-package || test "$role" = target-build; then
    components=$(component_list_for_package "$package")
    test -n "$components" || fail "$package owns no selected target component"
    dependencies=$(target_dependencies_for_package "$package")
    if test "$package" = zarith; then
      if test "$dependencies" = -; then
        dependencies=gmp-sys-ios
      else
        dependencies="$dependencies,gmp-sys-ios"
      fi
    fi
    if test "$package" = zarith; then
      build_mechanism=zarith
    elif test -f "$source_directory/dune-project"; then
      build_mechanism=dune
    elif test -f "$source_directory/pkg/pkg.ml"; then
      build_mechanism=topkg
    else
      fail "$package uses unsupported capability build system; required cross-build recipe: teach detect_build_mechanism about its build mechanism"
    fi
    capability_row=$(capability_for_package "$package" "$components" "$source_directory")
    old_ifs=$IFS
    IFS='|'
    set -- $capability_row
    IFS=$old_ifs
    capability=$2
    required_feature=$3
    recipe=$4
    validate_required_feature "$package" "$capability" "$required_feature" "$recipe"
  fi
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
    "$package" \
    "$version" \
    "$role" \
    "$capability" \
    "$build_mechanism" \
    "$source_url" \
    "$source_sha256" \
    "$components" \
    "$dependencies"
}

while IFS= read -r package; do
  row_for_package "$package" target-package
done <"$target_packages_file" >"$rows_file"
resolve_host_build_packages
while IFS= read -r package; do
  test -n "$package" || continue
  row_for_package "$package" target-build
done <"$target_build_packages_file" >>"$rows_file"
if grep -Fx zarith "$target_packages_file" >/dev/null; then
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
    gmp-sys-ios \
    "$GMP_VERSION" \
    target-build \
    Foreign_stubs \
    autoconf \
    "$GMP_SOURCE" \
    "$GMP_SHA256" \
    - \
    - \
    >>"$rows_file"
fi
while IFS= read -r package; do
  test -n "$package" || continue
  row_for_package "$package" host-package
done <"$host_packages_file" >>"$rows_file"

sort -t '|' -k3,3 -k1,1 "$rows_file" >"$body_file"
package_count=$(wc -l <"$body_file" | tr -d ' ')
target_package_count=$(grep -c '|target-package|' "$body_file" || true)
host_package_count=$(grep -c '|host-package|' "$body_file" || true)
target_build_count=$(grep -c '|target-build|' "$body_file" || true)
component_count=$(
  awk -F '|' '$3 == "target-package" { count += split($8, components, ",") } END { print count + 0 }' \
    "$body_file"
)
roots=$(sort -u "$closure_roots_file" | paste -sd, -)
body_digest=$(shasum -a 256 "$body_file" | awk '{ print $1 }')

{
  printf '%s\n' '# metadata.format=bonsai-swiftui-ios-closure-v2'
  printf '%s\n' "# metadata.features=$features"
  printf '%s\n' "# metadata.roots=$roots"
  printf '%s\n' "# metadata.package-count=$package_count"
  printf '%s\n' "# metadata.target-package-count=$target_package_count"
  printf '%s\n' "# metadata.host-package-count=$host_package_count"
  printf '%s\n' "# metadata.target-build-count=$target_build_count"
  printf '%s\n' "# metadata.component-count=$component_count"
  printf '%s\n' "# metadata.digest=$body_digest"
  printf '%s\n' '# package|version|role|capability|build-mechanism|source|sha256|findlib-components|target-dependencies'
  cat "$body_file"
} >"$output_lock.partial"
mv "$output_lock.partial" "$output_lock"

printf '%s\n' \
  "Resolved iPhoneOS application closure: $target_package_count target packages, $host_package_count host-only packages, $component_count components"
