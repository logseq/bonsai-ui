#!/bin/sh

set -eu

script_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$script_directory/ios/toolchain.lock"
host_switch=${HOST_SWITCH:-$(opam switch show)}
ios_switch=${IOS_SWITCH:-bonsai-swiftui-ios}
temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/bonsai-swiftui-rrbvec.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

mkdir -p "$temporary_directory/host" "$temporary_directory/ios"
for target in host ios; do
  for source in rrbvec_probe.ml rrbvec_native_embed.ml; do
    cp "$script_directory/ios/fixtures/application-closure/$source" \
      "$temporary_directory/$target/$source"
  done
done

(
  cd "$temporary_directory/host"
  opam exec --switch="$host_switch" -- \
    env -u OCAMLFIND_CONF -u OCAMLFIND_TOOLCHAIN \
    ocamlfind ocamlopt -package rrbvec -linkpkg -o probe.exe \
    rrbvec_probe.ml rrbvec_native_embed.ml
  ./probe.exe
)

ios_findlib_conf=${IOS_OCAMLFIND_CONF:-$(opam var --switch="$ios_switch" lib)/findlib.conf}
(
  cd "$temporary_directory/ios"
  opam exec --switch="$ios_switch" -- \
    env OCAMLFIND_CONF="$ios_findlib_conf" \
    ocamlfind -toolchain ios ocamlopt -package rrbvec -linkpkg \
    -output-complete-obj -o probe.o rrbvec_probe.ml rrbvec_native_embed.ml
)
"$script_directory/ios/verify_macho.sh" \
  "$temporary_directory/ios/probe.o" IOS arm64 "$IOS_DEPLOYMENT_TARGET"
nm "$temporary_directory/ios/probe.o" | grep -E ' [Tt] _camlRrbvec\.' >/dev/null
printf '%s\n' "rrbvec macOS execution and iPhoneOS complete-object checks passed"
