#!/bin/sh
set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
framework_root=$(CDPATH= cd -- "$script_directory/../.." && pwd)

# shellcheck source=tool/ios/sdk_repository.lock
. "$script_directory/sdk_repository.lock"
. "$script_directory/toolchain.lock"
BONSAI_SWIFTUI_SOURCE_REVISION=${SDK_SOURCE_REVISION:-$BONSAI_SWIFTUI_SOURCE_REVISION}
BONSAI_SWIFTUI_SOURCE_SHA256=${SDK_SOURCE_SHA256:-$BONSAI_SWIFTUI_SOURCE_SHA256}
expected_framework_source_url=${SDK_SOURCE_URL:-https://github.com/logseq/bonsai-ui/archive/$BONSAI_SWIFTUI_SOURCE_REVISION.tar.gz}

if [ "$#" -ne 6 ]; then
  echo "usage: $0 SOLUTION_JSON OPAM_REPO_CACHE OUTPUT_REPOSITORY FRAMEWORK_OPAM RUNTIME_OPAM SUPPORTED_CLOSURE_LOCK" >&2
  exit 64
fi

solution_json=$1
repo_cache=$2
output_repository=$3
framework_opam=$4
runtime_opam=$5
supported_closure_lock=$6
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

runtime_closure_body="$temporary_directory/runtime-closure.body"
runtime_closure_lock="$temporary_directory/runtime-closure.lock"
awk -F '|' '$1 !~ /^#/ && NF && $1 != "bonsai_swiftui" { print }' \
  "$supported_closure_lock" > "$runtime_closure_body"
runtime_features=$(sed -n 's/^# metadata.features=//p' "$supported_closure_lock")
runtime_roots=$(sed -n 's/^# metadata.roots=//p' "$supported_closure_lock")
runtime_package_count=$(wc -l < "$runtime_closure_body" | tr -d ' ')
runtime_target_package_count=$(grep -c '|target-package|' "$runtime_closure_body" || true)
runtime_host_package_count=$(grep -c '|host-package|' "$runtime_closure_body" || true)
runtime_target_build_count=$(grep -c '|target-build|' "$runtime_closure_body" || true)
runtime_component_count=$(
  awk -F '|' '$3 == "target-package" { count += split($8, components, ",") } END { print count + 0 }' \
    "$runtime_closure_body"
)
runtime_body_digest=$(shasum -a 256 "$runtime_closure_body" | cut -d ' ' -f 1)
{
  printf '%s\n' '# metadata.format=bonsai-swiftui-ios-closure-v2'
  printf '%s\n' "# metadata.features=$runtime_features"
  printf '%s\n' "# metadata.roots=$runtime_roots"
  printf '%s\n' "# metadata.package-count=$runtime_package_count"
  printf '%s\n' "# metadata.target-package-count=$runtime_target_package_count"
  printf '%s\n' "# metadata.host-package-count=$runtime_host_package_count"
  printf '%s\n' "# metadata.target-build-count=$runtime_target_build_count"
  printf '%s\n' "# metadata.component-count=$runtime_component_count"
  printf '%s\n' "# metadata.digest=$runtime_body_digest"
  printf '%s\n' '# package|version|role|capability|build-mechanism|source|sha256|findlib-components|target-dependencies'
  cat "$runtime_closure_body"
} > "$runtime_closure_lock"

packages_tsv="$temporary_directory/packages.tsv"
jq -r '.solution[] | .install? | select(.) | [.name, .version] | @tsv' \
  "$solution_json" | LC_ALL=C sort -u > "$packages_tsv"

package_lock="$temporary_directory/package-universe.lock"
source_lock="$temporary_directory/source-archives.lock"
framework_meta_file="$temporary_directory/framework.opam"
runtime_meta_file="$temporary_directory/runtime.opam"
framework_files="$temporary_directory/framework-files"
runtime_files="$temporary_directory/runtime-files"
mkdir -p "$framework_files" "$runtime_files"
mkdir -p "$runtime_files/patches" "$runtime_files/pkgconfig/iphoneos"
sed \
  -e "s/^framework_source_sha256=.*/framework_source_sha256='$BONSAI_SWIFTUI_SOURCE_SHA256'/" \
  -e "s/^framework_deployment_target=.*/framework_deployment_target='$IOS_DEPLOYMENT_TARGET'/" \
  "$script_directory/build_installed_framework.sh" \
  > "$framework_files/build-installed-framework.sh"
cp "$script_directory/build_runtime_sdk.sh" "$runtime_files/build-runtime-sdk.sh"
cp "$script_directory/build_runtime_closure.sh" "$runtime_files/build-runtime-closure.sh"
cp "$script_directory/build_runtime_package.sh" "$runtime_files/build-runtime-package.sh"
cp "$script_directory/verify_macho.sh" "$runtime_files/verify_macho.sh"
cp "$script_directory/toolchain.lock" "$runtime_files/toolchain.lock"
cp "$runtime_closure_lock" "$runtime_files/supported-closure.lock"
cp "$framework_root/vendor/patches/ios/"*.patch "$runtime_files/patches/"
for patch_file in "$runtime_files/patches/"*.patch; do
  sed 's/^ $//' "$patch_file" >"$patch_file.normalized"
  mv "$patch_file.normalized" "$patch_file"
done
cp "$framework_root/vendor/pkgconfig/iphoneos/sqlite3.pc" "$runtime_files/pkgconfig/iphoneos/"
chmod +x "$framework_files/"*.sh "$runtime_files/"*.sh

printf '%s\n' '# package|version|repository|metadata-sha256' > "$package_lock"
printf '%s\n' '# package|version|source|algorithm|checksum' > "$source_lock"

while IFS="$(printf '\t')" read -r package version; do
  case "$package" in
    bonsai_swiftui_ios_sdk | bonsai_swiftui_ios_runtime_sdk) continue ;;
  esac
  package_directory=
  repository_name=
  for repository in bonsai-swiftui-ios ios-cross default; do
    candidate="$repo_cache/$repository/packages/$package/$package.$version"
    if [ -d "$candidate" ]; then
      package_directory=$candidate
      case "$repository" in
        bonsai-swiftui-ios) repository_name=local ;;
        ios-cross) repository_name=ios-cross ;;
        default) repository_name=default ;;
      esac
      break
    fi
  done
  if [ -z "$package_directory" ]; then
    echo "missing solved package metadata: $package.$version" >&2
    exit 1
  fi
  if find "$package_directory" -type l | grep -q .; then
    echo "package metadata contains a symlink: $package.$version" >&2
    exit 1
  fi

  metadata_input="$temporary_directory/metadata-input"
  : > "$metadata_input"
  find "$package_directory" -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    relative=${file#"$package_directory"/}
    printf '%s\0%s\0' "$relative" "$(shasum -a 256 "$file" | cut -d ' ' -f 1)"
  done > "$metadata_input"
  metadata_sha=$(shasum -a 256 "$metadata_input" | cut -d ' ' -f 1)
  printf '%s|%s|%s|%s\n' \
    "$package" "$version" "$repository_name" "$metadata_sha" >> "$package_lock"

  perl -0777 -e '
    use strict;
    use warnings;
    my ($package, $version, @files) = @ARGV;
    for my $file (@files) {
      open my $handle, "<", $file or die "cannot read $file: $!\n";
      local $/;
      my $contents = <$handle>;
      close $handle;
      my @blocks = $file =~ m{/url$}
        ? ($contents)
        : ($contents =~ /(?:^|\n)\s*(?:url|extra-source\s+"[^"]+")\s*\{(.*?)^\s*\}/msg);
      for my $block (@blocks) {
        next unless $block =~ /"([^"]+:\/\/[^\"]+)"/s;
        my $source = $1;
        my ($algorithm, $checksum);
        if ($block =~ /"sha256=([0-9a-fA-F]{64})"/s) {
          ($algorithm, $checksum) = ("sha256", $1);
        } elsif ($block =~ /"sha512=([0-9a-fA-F]{128})"/s) {
          ($algorithm, $checksum) = ("sha512", $1);
        } else {
          die "$package.$version source lacks SHA-256 or SHA-512: $source\n";
        }
        print "$package|$version|$source|$algorithm|$checksum\n";
      }
    }
  ' "$package" "$version" "$package_directory/opam" \
    $(find "$package_directory" -maxdepth 1 -type f -name url -print) >> "$source_lock"
done < "$packages_tsv"

{
  printf '%s\n' '(package_lock' ' (format_version 1)' ' (packages'
  while IFS='|' read -r package version repository metadata_sha; do
    case "$package" in
      ''|'# package') continue ;;
    esac
    printf '  (%s %s %s %s)\n' "$package" "$version" "$repository" "$metadata_sha"
  done < "$package_lock"
  printf '%s\n' ' ))'
} > "$framework_files/package-lock.sexp"

package_lock_digest=$(shasum -a 256 "$framework_files/package-lock.sexp" | cut -d ' ' -f 1)
target_components_digest=$(shasum -a 256 "$runtime_closure_lock" | cut -d ' ' -f 1)
target_packages="$temporary_directory/target-packages.tsv"
awk -F '|' '
  $1 !~ /^#/ && ($3 == "target-build" || $3 == "target-package") {
    print $1 "\t" $2
  }
' "$runtime_closure_lock" | LC_ALL=C sort -u > "$target_packages"
printf '%s\t%s\n' bonsai_swiftui "$BONSAI_SWIFTUI_VERSION" >> "$target_packages"
printf '%s\t%s\n' ocaml-ios64 5.1.1 >> "$target_packages"
LC_ALL=C sort -u "$target_packages" -o "$target_packages"

{
  printf '%s\n' \
    '(sdk' \
    ' (format_version 1)' \
    " (bonsai_swiftui_version $BONSAI_SWIFTUI_VERSION)" \
    ' (bonsai_swiftui_source' \
    "  $BONSAI_SWIFTUI_SOURCE_REVISION" \
    '  sha256' \
    "  $BONSAI_SWIFTUI_SOURCE_SHA256)" \
    " (abi_version $SDK_ABI_VERSION)" \
    ' (ocaml_version 5.1.1)' \
    ' (dune_version_range 3.17 4.0)' \
    ' (cross_compiler ocaml-ios64 5.1.1)' \
    ' (findlib_toolchain ios)' \
    ' (architecture arm64)' \
    ' (platform iphoneos)' \
    " (minimum_deployment_target $IOS_DEPLOYMENT_TARGET)" \
    " (package_universe_digest $package_lock_digest)" \
    " (target_components_digest $target_components_digest)" \
    ' (required_frameworks Foundation Security)' \
    ' (required_system_libraries sqlite3)' \
    " (build_recipe_revision $SDK_BUILD_RECIPE_REVISION)" \
    ' (packages'
  while IFS="$(printf '\t')" read -r package version; do
    printf '  (%s %s)\n' "$package" "$version"
  done < "$target_packages"
  printf '%s\n' ' )' ' (libraries'
  awk -F '|' '
    $1 !~ /^#/ && ($3 == "target-build" || $3 == "target-package") && $8 != "-" {
      count = split($8, components, ",")
      component_list = ""
      for (component_index = 1; component_index <= count; component_index++) {
        component_list = component_list " " components[component_index]
      }
      for (component_index = 1; component_index <= count; component_index++) {
        printf "  (%s %s %s (%s))\n", components[component_index], $1, $2, substr(component_list, 2)
      }
    }
  ' "$runtime_closure_lock"
  standard_library_components='threads unix str dynlink'
  for library in $standard_library_components; do
    printf '  (%s ocaml-ios64 5.1.1 (%s))\n' "$library" "$standard_library_components"
  done
  framework_components='bonsai_swiftui bonsai_swiftui.driver bonsai_swiftui.native_backend bonsai_swiftui.protocol bonsai_swiftui.runtime bonsai_swiftui.runtime_adapter bonsai_swiftui.spec bonsai_swiftui.spec_impl bonsai_swiftui.ui'
  for library in $framework_components; do
    printf '  (%s bonsai_swiftui %s (%s))\n' \
      "$library" "$BONSAI_SWIFTUI_VERSION" "$framework_components"
  done
  printf '%s\n' ' ))'
} > "$framework_files/manifest.sexp"

framework_source_record=$(awk -F '|' '
  $1 == package && $2 == version { print; exit }
' package="bonsai_swiftui" version="$BONSAI_SWIFTUI_VERSION" "$source_lock")
test -n "$framework_source_record" || {
  echo "missing Bonsai SwiftUI source archive lock" >&2
  exit 1
}
old_ifs=$IFS
IFS='|'
set -- $framework_source_record
IFS=$old_ifs
framework_source_url=$3
framework_source_checksum_algorithm=$4
framework_source_checksum=$5
test "$framework_source_checksum_algorithm" = sha256 || {
  echo "Bonsai SwiftUI source must use SHA-256" >&2
  exit 1
}
test "$framework_source_url" = \
  "$expected_framework_source_url" || {
  echo "Bonsai SwiftUI source revision differs from sdk_repository.lock" >&2
  exit 1
}
test "$framework_source_checksum" = "$BONSAI_SWIFTUI_SOURCE_SHA256" || {
  echo "Bonsai SwiftUI source checksum differs from sdk_repository.lock" >&2
  exit 1
}

{
  printf '%s\n' \
    'opam-version: "2.0"' \
    'synopsis: "Bonsai SwiftUI iPhoneOS framework SDK"' \
    'description: """' \
    'Builds and installs the Bonsai SwiftUI framework for iPhoneOS arm64 on top' \
    'of the exact immutable runtime SDK package.' \
    '"""' \
    'maintainer: "bonsai_swiftui contributors"' \
    'authors: ["bonsai_swiftui contributors"]' \
    'license: "MIT"' \
    'homepage: "https://github.com/logseq/bonsai-ui"' \
    'bug-reports: "https://github.com/logseq/bonsai-ui/issues"' \
    'dev-repo: "git+https://github.com/logseq/bonsai-ui.git"' \
    'extra-source "bonsai_swiftui.tar.gz" {' \
    "  src: \"$framework_source_url\"" \
    "  checksum: [\"sha256=$framework_source_checksum\"]" \
    '}' \
    'extra-files: ['
  find "$framework_files" -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    relative=${file#"$framework_files"/}
    printf '  ["%s" "sha256=%s"]\n' \
      "$relative" \
      "$(shasum -a 256 "$file" | cut -d ' ' -f 1)"
  done
  printf '%s\n' \
    ']' \
    'depends: [' \
    "  \"bonsai_swiftui\" {= \"$BONSAI_SWIFTUI_VERSION\"}" \
    "  \"bonsai_swiftui_ios_runtime_sdk\" {= \"$SDK_RUNTIME_PACKAGE_VERSION\"}" \
    ']' \
    'build: [' \
    '  ["sh" "./build-installed-framework.sh" "%{switch}%" "%{prefix}%"]' \
    ']' \
    'install: [' \
    '  ["cp" "-R" ".bonsai_swiftui_ios_framework_sdk/stage/ios-sysroot/." "%{prefix}%/ios-sysroot/"]' \
    '  ["mkdir" "-p" "%{share}%/bonsai_swiftui_ios_sdk"]' \
    '  ["cp" "manifest.sexp" "%{share}%/bonsai_swiftui_ios_sdk/manifest.sexp"]' \
    '  ["cp" "package-lock.sexp" "%{share}%/bonsai_swiftui_ios_sdk/package-lock.sexp"]' \
    ']' \
    'available: os = "macos" & arch = "arm64"'
} > "$framework_meta_file"

{
  printf '%s\n' \
    'opam-version: "2.0"' \
    'synopsis: "Immutable Bonsai SwiftUI iPhoneOS runtime SDK"' \
    'description: """' \
    'Builds and installs the locked iPhoneOS arm64 cross-compiler runtime and' \
    'target dependency closure independently from the Bonsai SwiftUI framework.' \
    '"""' \
    'maintainer: "bonsai_swiftui contributors"' \
    'authors: ["bonsai_swiftui contributors"]' \
    'license: "MIT"' \
    'homepage: "https://github.com/logseq/bonsai-ui"' \
    'bug-reports: "https://github.com/logseq/bonsai-ui/issues"' \
    'dev-repo: "git+https://github.com/logseq/bonsai-ui.git"'
  awk -F '|' '
    $1 !~ /^#/ && ($3 == "target-build" || $3 == "target-package") {
      printf "extra-source \"runtime-%s-%s.archive\" {\n", $1, $7
      printf "  src: \"%s\"\n", $6
      printf "  checksum: [\"sha256=%s\"]\n", $7
      print "}"
    }
  ' "$runtime_closure_lock"
  printf '%s\n' 'extra-files: ['
  find "$runtime_files" -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    relative=${file#"$runtime_files"/}
    printf '  ["%s" "sha256=%s"]\n' \
      "$relative" \
      "$(shasum -a 256 "$file" | cut -d ' ' -f 1)"
  done
  printf '%s\n' ']' 'depends: ['
  while IFS="$(printf '\t')" read -r package version; do
    case "$package" in
      bonsai_swiftui | bonsai_swiftui_ios_sdk | bonsai_swiftui_ios_runtime_sdk) continue ;;
    esac
    printf '  "%s" {= "%s"}\n' "$package" "$version"
  done < "$packages_tsv"
  printf '%s\n' \
    ']' \
    'build: [' \
    '  ["sh" "./build-runtime-sdk.sh" "%{switch}%" "%{prefix}%"]' \
    ']' \
    'install: [' \
    '  ["cp" "-R" ".bonsai_swiftui_ios_runtime_sdk/stage/ios-sysroot/." "%{prefix}%/ios-sysroot/"]' \
    ']' \
    'available: os = "macos" & arch = "arm64"'
} > "$runtime_meta_file"

mkdir -p \
  "$output_repository" \
  "$(dirname "$framework_opam")" \
  "$(dirname "$runtime_opam")"
actual_framework_files="$(dirname "$framework_opam")/files"
actual_runtime_files="$(dirname "$runtime_opam")/files"
mkdir -p "$actual_framework_files" "$actual_runtime_files"
mv "$package_lock" "$output_repository/package-universe.lock"
mv "$source_lock" "$output_repository/source-archives.lock"
cp -R "$framework_files/." "$actual_framework_files/"
cp -R "$runtime_files/." "$actual_runtime_files/"
mv "$framework_meta_file" "$framework_opam"
mv "$runtime_meta_file" "$runtime_opam"
