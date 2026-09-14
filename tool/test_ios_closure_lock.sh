#!/bin/sh

set -u

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repository_root=$(CDPATH= cd -- "$script_directory/.." && pwd)
verifier="$repository_root/tool/ios/verify_runtime_closure.sh"
resolver="$repository_root/tool/ios/resolve_application_closure.sh"
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/bonsai-swiftui-lock-test.XXXXXX")

cleanup() {
  rm -rf "$temporary_directory"
}

trap cleanup EXIT HUP INT TERM

failures=0

fail() {
  printf '%s\n' "iOS closure lock test failure: $1" >&2
  failures=$((failures + 1))
}

write_lock() {
  destination=$1
  features=$2
  body=$3
  package_count=$(printf '%s\n' "$body" | awk -F '|' 'NF { count++ } END { print count + 0 }')
  component_count=$(
    printf '%s\n' "$body" |
      awk -F '|' 'NF { count += split($8, components, ",") } END { print count + 0 }'
  )
  digest=$(printf '%s\n' "$body" | shasum -a 256 | awk '{ print $1 }')
  {
    printf '%s\n' '# metadata.format=bonsai-swiftui-ios-closure-v2'
    printf '%s\n' "# metadata.features=$features"
    printf '%s\n' '# metadata.roots=datascript-ocaml-native.sqlite,fixture-pure'
    printf '%s\n' "# metadata.package-count=$package_count"
    printf '%s\n' "# metadata.target-package-count=$package_count"
    printf '%s\n' '# metadata.host-package-count=0'
    printf '%s\n' '# metadata.target-build-count=0'
    printf '%s\n' "# metadata.component-count=$component_count"
    printf '%s\n' "# metadata.digest=$digest"
    printf '%s\n' '# package|version|role|capability|build-mechanism|source|sha256|findlib-components|target-dependencies'
    printf '%s\n' "$body"
  } >"$destination"
}

expect_success() {
  label=$1
  shift
  if ! output=$("$@" 2>&1); then
    printf '%s\n' "$output" >&2
    fail "$label unexpectedly failed"
  fi
}

expect_failure_contains() {
  label=$1
  expected=$2
  shift 2
  if output=$("$@" 2>&1); then
    fail "$label unexpectedly passed"
  elif ! printf '%s' "$output" | grep -F -- "$expected" >/dev/null; then
    printf '%s\n' "$output" >&2
    fail "$label did not report: $expected"
  fi
}

sha_a='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
sha_b='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
sha_c='cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
complete_body="fixture-pure|1.0.0|target-package|Pure_ocaml|dune|https://example.invalid/fixture-pure-1.0.0.tbz|$sha_a|fixture-pure|-
sqlite3|5.4.0|target-package|System_sqlite|dune|https://example.invalid/sqlite3-5.4.0.tbz|$sha_b|sqlite3|-
datascript-ocaml-native|dev|target-package|System_sqlite|dune|https://example.invalid/datascript-ocaml-native.tar.gz|$sha_c|datascript-ocaml-native.sqlite|sqlite3"

complete_lock="$temporary_directory/complete.lock"
write_lock "$complete_lock" core,sqlite "$complete_body"

expect_success \
  "complete sqlite closure acceptance" \
  "$verifier" \
  --check-lock-only \
  --lock "$complete_lock" \
  --features core,sqlite

expect_failure_contains \
  "sqlite closure rejection without feature" \
  "sqlite3 requires the sqlite feature" \
  "$verifier" \
  --check-lock-only \
  --lock "$complete_lock" \
  --features core

missing_dependency_body="fixture-pure|1.0.0|target-package|Pure_ocaml|dune|https://example.invalid/fixture-pure-1.0.0.tbz|$sha_a|fixture-pure|-
datascript-ocaml-native|dev|target-package|System_sqlite|dune|https://example.invalid/datascript-ocaml-native.tar.gz|$sha_c|datascript-ocaml-native.sqlite|sqlite3"
missing_dependency_lock="$temporary_directory/missing-dependency.lock"
write_lock "$missing_dependency_lock" core,sqlite "$missing_dependency_body"
expect_failure_contains \
  "missing target dependency" \
  "datascript-ocaml-native is missing target dependency sqlite3" \
  "$verifier" \
  --check-lock-only \
  --lock "$missing_dependency_lock" \
  --features core,sqlite

drifted_lock="$temporary_directory/drifted.lock"
cp "$complete_lock" "$drifted_lock"
sed -i.bak 's/fixture-pure|1.0.0/fixture-pure|1.0.1/' "$drifted_lock"
rm -f "$drifted_lock.bak"
expect_failure_contains \
  "closure lock drift" \
  "lock digest differs" \
  "$verifier" \
  --check-lock-only \
  --lock "$drifted_lock" \
  --features core,sqlite

core_identity=$(
  "$resolver" --identity --lock "$complete_lock" --features core 2>/dev/null
) || core_identity=
sqlite_identity=$(
  "$resolver" --identity --lock "$complete_lock" --features core,sqlite 2>/dev/null
) || sqlite_identity=
test -n "$core_identity" || fail "core SDK identity is missing"
test -n "$sqlite_identity" || fail "sqlite SDK identity is missing"
test "$core_identity" != "$sqlite_identity" ||
  fail "SDK identity does not separate selected features"

empty_target_lib="$temporary_directory/empty-target-lib"
mkdir -p "$empty_target_lib"
expect_failure_contains \
  "missing target artifacts" \
  "missing target artifact for fixture-pure" \
  "$verifier" \
  --lock "$complete_lock" \
  --features core,sqlite \
  --target-lib "$empty_target_lib"

if test "$failures" -ne 0; then
  printf '%s\n' "iOS closure lock tests failed with $failures violation(s)" >&2
  exit 1
fi

printf '%s\n' "iOS closure lock tests passed"
