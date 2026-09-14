#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

dune build native/test/libruntime_fixture.dylib
output_directory="$repository_root/_build/default/native/test"
BONSAI_NATIVE_TEST_LIBRARY="$output_directory/libruntime_fixture.dylib" \
  python3 native/test/test_runtime.py
