#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)
output_repository="$script_directory/opam-repository/0.1.0"

# shellcheck source=tool/ios/sdk_repository.lock
. "$script_directory/sdk_repository.lock"
# shellcheck source=tool/ios/toolchain.lock
. "$script_directory/toolchain.lock"

fail() {
  printf '%s\n' "iPhoneOS SDK repository generation failure: $1" >&2
  exit 1
}

mode=--write
source_archive=
while test "$#" -gt 0; do
  case "$1" in
    --check | --write) mode=$1; shift ;;
    --source-archive)
      test "$#" -ge 2 || fail "--source-archive requires a path"
      source_archive=$2; shift 2 ;;
    --output)
      test "$#" -ge 2 || fail "--output requires a path"
      output_repository=$2; shift 2 ;;
    *) fail "usage: $0 [--check|--write] [--source-archive PATH] [--output PATH]" ;;
  esac
done

for command in awk cp diff find git jq mkdir mktemp opam python3 sed shasum sort; do
  command -v "$command" >/dev/null 2>&1 || fail "required command is unavailable: $command"
done

cache_root="$repository_root/_build/ios/sdk-repository-sources"
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM
staged_repository="$temporary_directory/repository"
repository_cache="$temporary_directory/repository-cache"
solution_json="$temporary_directory/solution.json"

ensure_checkout() {
  url=$1
  commit=$2
  checkout=$3
  reference=${4:-}

  if test ! -d "$checkout/.git"; then
    mkdir -p "$(dirname -- "$checkout")"
    if test -n "$reference" && test -d "$reference/.git"; then
      git clone --reference-if-able "$reference" "$url" "$checkout"
    else
      git clone "$url" "$checkout"
    fi
  fi
  test -z "$(git -C "$checkout" status --porcelain)" ||
    fail "managed repository checkout has local changes: $checkout"
  if ! git -C "$checkout" cat-file -e "$commit^{commit}" 2>/dev/null; then
    git -C "$checkout" fetch origin "$commit"
  fi
  git -C "$checkout" checkout --detach "$commit"
  test "$(git -C "$checkout" rev-parse HEAD)" = "$commit" ||
    fail "repository checkout did not resolve locked commit: $checkout"
}

# Package metadata and identity must describe the selected immutable input.
if test -n "$source_archive"; then
  python3 - "$source_archive" "$temporary_directory/framework.opam" <<'PY_SOURCE'
from pathlib import Path, PurePosixPath
import sys
import tarfile
try:
    with tarfile.open(sys.argv[1]) as archive:
        members = archive.getmembers()
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or not (member.isfile() or member.isdir()):
                raise ValueError("unsafe archive member: " + member.name)
        candidates = [m for m in members if m.isfile()
                      and len(PurePosixPath(m.name).parts) == 2
                      and PurePosixPath(m.name).name == "bonsai_swiftui.opam"]
        if len(candidates) != 1:
            raise ValueError("expected one top-level bonsai_swiftui.opam")
        Path(sys.argv[2]).write_bytes(archive.extractfile(candidates[0]).read())
except (OSError, ValueError, tarfile.TarError) as error:
    raise SystemExit("Invalid framework source archive: " + str(error))
PY_SOURCE
  archive_version=$(opam show --just-file "$temporary_directory/framework.opam" --field=version)
  test "$archive_version" = "$BONSAI_SWIFTUI_VERSION" || fail "source archive package version differs from SDK version"
  BONSAI_SWIFTUI_SOURCE_SHA256=$(shasum -a 256 "$source_archive" | awk '{print $1}')
  BONSAI_SWIFTUI_SOURCE_REVISION="archive-sha256-$BONSAI_SWIFTUI_SOURCE_SHA256"
  framework_source_url=$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve().as_uri())' "$source_archive")
else
  test "$(printf '%s' "$BONSAI_SWIFTUI_SOURCE_REVISION" | tr -d '0-9a-f' | wc -c | tr -d ' ')" = 0 &&
    test "${#BONSAI_SWIFTUI_SOURCE_REVISION}" -eq 40 ||
    fail "framework source revision must be a full commit ID"
  git -C "$repository_root" show "$BONSAI_SWIFTUI_SOURCE_REVISION:bonsai_swiftui.opam" \
    > "$temporary_directory/framework.opam" 2>/dev/null ||
    fail "locked source lacks bonsai_swiftui.opam: $BONSAI_SWIFTUI_SOURCE_REVISION"
  framework_source_url="https://github.com/RCmerci/bonsai_flutter/archive/$BONSAI_SWIFTUI_SOURCE_REVISION.tar.gz"
fi

default_checkout="$cache_root/opam-repository"
cross_checkout="$cache_root/opam-cross-ios"
ensure_checkout \
  "$DEFAULT_REPOSITORY_URL" \
  "$DEFAULT_REPOSITORY_COMMIT" \
  "$default_checkout" \
  "$repository_root/_build/opam-repository-9fdd0666"
ensure_checkout \
  "$OPAM_CROSS_IOS_REPOSITORY" \
  "$OPAM_CROSS_IOS_COMMIT" \
  "$cross_checkout" \
  "$repository_root/_build/ios/sources/opam-cross-ios"

mkdir -p "$staged_repository/packages"
printf '%s\n' 'opam-version: "2.0"' > "$staged_repository/repo"
cp -R "$repository_root/vendor/opam-ios/sdk-packages/." "$staged_repository/packages/"
"$script_directory/prepare_cross_overlay.sh" "$cross_checkout" "$temporary_directory/cross-overlay"
mkdir -p "$staged_repository/packages/ocaml-ios64"
cp -R "$temporary_directory/cross-overlay/packages/$OCAML_IOS_PACKAGE" \
  "$staged_repository/packages/ocaml-ios64/"

framework_packages="$staged_repository/packages/bonsai_swiftui_ios_sdk"
runtime_packages="$staged_repository/packages/bonsai_swiftui_ios_runtime_sdk"
framework_source_package="$staged_repository/packages/bonsai_swiftui/bonsai_swiftui.$BONSAI_SWIFTUI_VERSION"
mkdir -p "$framework_packages" "$runtime_packages" "$framework_source_package"
cp "$temporary_directory/framework.opam" "$framework_source_package/opam"
framework_url="$framework_source_package/url"
{
  printf '%s\n' \
    'src:' \
    "  \"$framework_source_url\"" \
    'checksum:' \
    "  \"sha256=$BONSAI_SWIFTUI_SOURCE_SHA256\""
} > "$framework_url"

mkdir -p "$repository_cache"
ln -s "$staged_repository" "$repository_cache/bonsai-swiftui-ios"
ln -s "$default_checkout" "$repository_cache/default"
ln -s "$cross_checkout" "$repository_cache/ios-cross"

packages_tsv="$temporary_directory/packages.tsv"
awk -F '|' '!/^#/ && NF && $1 != "gmp-sys-ios" { print $1 "\t" $2 }' \
  "$repository_root/vendor/opam-ios/supported-closure.lock" > "$packages_tsv"
printf '%b\n' \
  'base-bigarray	base' \
  'base-bytes	base' \
  'base-domains	base' \
  'base-nnp	base' \
  'base-threads	base' \
  'base-unix	base' \
  'conf-ios	4' \
  'conf-pkg-config	5' \
  'conf-sqlite3	1' \
  "dune	$DUNE_VERSION" \
  "dune-build-info	$DUNE_VERSION" \
  'melange	5.1.0-51' \
  "ocaml	$OCAML_VERSION" \
  "ocaml-base-compiler	$OCAML_VERSION" \
  'ocaml-config	3' \
  "ocaml-ios64	$OCAML_VERSION" \
  'ocaml-options-vanilla	1' \
  "ocamlfind	$OCAMLFIND_VERSION" \
  'seq	base' >> "$packages_tsv"
printf '%s\t%s\n' bonsai_swiftui "$BONSAI_SWIFTUI_VERSION" >> "$packages_tsv"
printf '%s\t%s\n' bonsai_swiftui_ios_sdk "$SDK_PACKAGE_VERSION" >> "$packages_tsv"
printf '%s\t%s\n' \
  bonsai_swiftui_ios_runtime_sdk \
  "$SDK_RUNTIME_PACKAGE_VERSION" >> "$packages_tsv"
LC_ALL=C sort -u "$packages_tsv" -o "$packages_tsv"
jq -Rn \
  '[inputs | split("\t") | {install: {name: .[0], version: .[1]}}] | {solution: .}' \
  < "$packages_tsv" > "$solution_json"

framework_package_directory="$framework_packages/bonsai_swiftui_ios_sdk.$SDK_PACKAGE_VERSION"
runtime_package_directory="$runtime_packages/bonsai_swiftui_ios_runtime_sdk.$SDK_RUNTIME_PACKAGE_VERSION"
SDK_SOURCE_REVISION="$BONSAI_SWIFTUI_SOURCE_REVISION" \
SDK_SOURCE_SHA256="$BONSAI_SWIFTUI_SOURCE_SHA256" \
SDK_SOURCE_URL="$framework_source_url" \
"$script_directory/generate_package_universe.sh" \
  "$solution_json" \
  "$repository_cache" \
  "$staged_repository" \
  "$framework_package_directory/opam" \
  "$runtime_package_directory/opam" \
  "$repository_root/vendor/opam-ios/supported-closure.lock"

repository_digest() {
  root=$1
  find "$root" -type f ! -name repository.sexp -print |
    LC_ALL=C sort |
    {
      first=true
      while IFS= read -r file; do
        relative=${file#"$root"/}
        checksum=$(shasum -a 256 "$file" | awk '{ print $1 }')
        if test "$first" = false; then printf '\0'; fi
        printf '%s\0%s' "$relative" "$checksum"
        first=false
      done
    } |
    shasum -a 256 |
    awk '{ print $1 }'
}

snapshot_sha256=$(repository_digest "$staged_repository")
source_lock_sha256=$(shasum -a 256 "$repository_root/vendor/opam-ios/runtime-closure.lock" | awk '{ print $1 }')
package_universe_sha256=$(shasum -a 256 "$staged_repository/package-universe.lock" | awk '{ print $1 }')
source_archives_sha256=$(shasum -a 256 "$staged_repository/source-archives.lock" | awk '{ print $1 }')

{
  printf '%s\n' \
    '(repository' \
    ' (format_version 1)' \
    ' (repository_version 0.1.0)' \
    " (repository_snapshot_sha256 $snapshot_sha256)" \
    ' (source_lock' \
    '  vendor/opam-ios/runtime-closure.lock' \
    "  $source_lock_sha256)" \
    ' (package_universe' \
    '  package-universe.lock' \
    "  $package_universe_sha256)" \
    ' (source_archives' \
    '  source-archives.lock' \
    "  $source_archives_sha256)" \
    ' (default_repository' \
    "  $DEFAULT_REPOSITORY_URL" \
    "  $DEFAULT_REPOSITORY_COMMIT)" \
    ' (cross_repository' \
    "  $OPAM_CROSS_IOS_REPOSITORY" \
    "  $OPAM_CROSS_IOS_COMMIT)" \
    " (compiler ocaml-base-compiler $OCAML_VERSION)" \
    " (sdk_package bonsai_swiftui_ios_sdk $SDK_PACKAGE_VERSION))"
} > "$staged_repository/repository.sexp"

if test "$mode" = --check; then
  diff -ru "$output_repository" "$staged_repository" >/dev/null ||
    fail "committed iPhoneOS SDK repository is stale; run: make ios-sdk-repository"
  printf '%s\n' "iPhoneOS SDK repository is reproducible"
  exit 0
fi

# Stage the complete replacement alongside the destination before changing it.
mkdir -p "$(dirname "$output_repository")"
replacement="$output_repository.generated.$$"
previous="$output_repository.previous.$$"
cp -R "$staged_repository" "$replacement"
if test -e "$output_repository"; then mv "$output_repository" "$previous"; fi
if ! mv "$replacement" "$output_repository"; then
  if test -e "$previous"; then mv "$previous" "$output_repository"; fi
  rm -rf "$replacement"
  fail "could not replace the SDK repository"
fi
rm -rf "$previous"

printf '%s\n' "iPhoneOS SDK repository regenerated: $SDK_PACKAGE_VERSION"
