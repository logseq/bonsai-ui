#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# Bootstrap with tool/ios/setup_toolchain.sh iphoneos before running this gate.
# The Python test inspects actual compiler, foreign-stub and runtime artifacts.
exec python3 "$repository_root/tool/test_ios_cross_compiler.py"
