#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$repository_root"

dune build ocaml/ui/bonsai_swiftui_ui.cma

temporary_directory=$(mktemp -d "${TMPDIR:-/tmp}/bonsai-swiftui-viewport-types.XXXXXX")
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

ui_cmi="$repository_root/_build/default/ocaml/ui/.bonsai_swiftui_ui.objs/byte"
spec_cmi="$repository_root/_build/default/ocaml/spec_impl/.bonsai_swiftui_spec_impl.objs/byte"
fixtures="$repository_root/ocaml/test/viewport_compile"

compile() {
  source_file=$1
  output_name=$(basename "$source_file" .ml)
  ocamlc -c -I "$spec_cmi" -I "$ui_cmi" -o "$temporary_directory/$output_name.cmo" "$source_file"
}

compile "$fixtures/valid.ml"

for source_file in \
  "$fixtures/vertical_in_column.ml" \
  "$fixtures/horizontal_in_row.ml" \
  "$fixtures/viewport_in_weighted_fixed.ml" \
  "$fixtures/body_axis_mismatch.ml"
do
  diagnostic="$temporary_directory/$(basename "$source_file").stderr"
  if compile "$source_file" 2>"$diagnostic"; then
    echo "Expected OCaml type checking to reject $source_file" >&2
    exit 1
  fi
  if grep -q "Unbound" "$diagnostic"; then
    echo "Compile-fail fixture used a missing API instead of proving a type mismatch: $source_file" >&2
    cat "$diagnostic" >&2
    exit 1
  fi
  if ! grep -q "Viewport" "$diagnostic"; then
    echo "Compile-fail fixture did not fail with a viewport type mismatch: $source_file" >&2
    cat "$diagnostic" >&2
    exit 1
  fi
done

for source_file in \
  "$fixtures/collection_unkeyed_items.ml" \
  "$fixtures/collection_direct_key_items.ml"
do
  diagnostic="$temporary_directory/$(basename "$source_file").stderr"
  if compile "$source_file" 2>"$diagnostic"; then
    echo "Expected OCaml type checking to reject $source_file" >&2
    exit 1
  fi
  if grep -q "Unbound" "$diagnostic"; then
    echo "Compile-fail fixture used a missing API instead of proving a type mismatch: $source_file" >&2
    cat "$diagnostic" >&2
    exit 1
  fi
  if ! grep -q "Keyed.t" "$diagnostic"; then
    echo "Compile-fail fixture did not fail with a keyed-item type mismatch: $source_file" >&2
    cat "$diagnostic" >&2
    exit 1
  fi
done
