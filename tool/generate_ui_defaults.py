"""Evaluate the OCaml Theme defaults to generate the native baseline."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "ocaml/ui/theme.ml").read_text()
start = "(* BEGIN OCAML THEME DEFAULT VALUES *)"
end = "(* END OCAML THEME DEFAULT VALUES *)"
values = source.split(start, 1)[1].split(end, 1)[0]
printer = r'''
let () =
  print_endline "// Generated from ocaml/ui/theme.ml by tool/generate_ui_defaults.py. Do not edit.";
  print_endline "enum UIDefaultValues {";
  let floats name values =
    let values = Array.to_list values |> List.map (Printf.sprintf "%.17g") in
    Printf.printf "  static let %s: [Double] = [%s]\n" name (String.concat ", " values)
  in
  let ints name values =
    let values = Array.to_list values |> List.map string_of_int in
    Printf.printf "  static let %s: [Int] = [%s]\n" name (String.concat ", " values)
  in
  floats "metrics" Values.metrics;
  floats "extraMetrics" Values.extra_metrics;
  floats "textSizes" Values.text_sizes;
  ints "textWeights" Values.text_weights;
  ints "textForegrounds" Values.text_foregrounds;
  ints "textItalics" Values.text_italics;
  Printf.printf "  static let foreground = %d\n" Values.foreground;
  Printf.printf "  static let textRole = %d\n" Values.text_role;
  Printf.printf "  static let symbolRendering = %d\n" Values.symbol_rendering;
  ints "surfaceMaterials" Values.surface_materials;
  ints "surfaceShapes" Values.surface_shapes;
  ints "surfaceBackgrounds" Values.surface_backgrounds;
  floats "surfaceTintAlphas" Values.surface_tint_alphas;
  floats "surfaceOpacities" Values.surface_opacities;
  print_endline "}"
'''
with tempfile.TemporaryDirectory(prefix="bonsai-theme-defaults-") as directory:
    script = Path(directory) / "generate.ml"
    script.write_text(values + "\n" + printer)
    generated = subprocess.check_output(["ocaml", "-noinit", str(script)], text=True, cwd=ROOT)
path = ROOT / "swift/BonsaiSwiftUI/Sources/UIDefaultValues.swift"
if "--check" in sys.argv:
    if not path.exists() or path.read_text() != generated:
        sys.exit("Stale native Theme defaults; run make protocol-generate")
else:
    path.write_text(generated)
