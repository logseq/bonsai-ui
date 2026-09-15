"""Normalize physical Note window captures beside the supplied reference panels."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
REFERENCE_CROPS = {
    "templates": (30, 125, 636, 1310),
    "cornell": (698, 125, 1306, 1310),
    "reading": (1365, 125, 1972, 1310),
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", required=True, type=Path)
    parser.add_argument("--captures", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--native-object", required=True, type=Path)
    args = parser.parse_args()
    result = json.loads((args.captures / "result.json").read_text())
    if result["status"] != "passed":
        raise SystemExit("Acceptance must finish before publishing comparison evidence")
    reference = Image.open(args.reference).convert("RGB")
    if reference.size != (2000, 1391):
        raise SystemExit("Reference crop coordinates require the original 2000x1391 image")
    args.output.mkdir(parents=True, exist_ok=True)
    capture_crop = (0, 141, 1170, 2460)
    for state, crop in REFERENCE_CROPS.items():
        capture = Image.open(args.captures / f"{state}.png").convert("RGB")
        if capture.size != (1170, 2532):
            raise SystemExit("Capture coordinates require the physical 390x844 point, 3x window")
        panels = []
        for source, rect in [(reference, crop), (capture, capture_crop)]:
            panel = source.crop(rect)
            panels.append(panel.resize((390, round(panel.height * 390 / panel.width)), Image.Resampling.LANCZOS))
        comparison = Image.new("RGB", (804, max(p.height for p in panels) + 40), "#fafafa")
        draw = ImageDraw.Draw(comparison)
        for i, (name, panel) in enumerate(zip(["Reference", "Physical iPhone / regular weight"], panels)):
            x = 8 + i * 398
            draw.text((x, 10), name, fill="#222222")
            comparison.paste(panel, (x, 32))
        comparison.save(args.output / f"{state}-comparison.png", optimize=True)
    for name in ["cornell-system", "templates-cool", "templates-focused", "templates-focused-cool", "templates-after-keyboard", "editing-keyboard", "reading-end", "narrow", "narrow-large-text"]:
        capture = Image.open(args.captures / f"{name}.png")
        capture.resize((390, 844), Image.Resampling.LANCZOS).save(args.output / f"{name}.png", optimize=True)
    sources = [
        "examples/note/ocaml/note.ml", "examples/note/ocaml/native_embed.ml",
        "examples/note/resources/typewriter.png", "examples/note/swift/App.swift",
        "ocaml/ui/native_widget.ml", "ocaml/ui/view.ml", "ocaml/runtime/driver.ml",
        "protocol/schema.sexp", "native/src/bonsai_swiftui_native.c",
        "swift/BonsaiSwiftUI/Sources/NativeSurface.swift",
        "swift/BonsaiSwiftUI/Sources/NativeSheet.swift",
        "swift/BonsaiSwiftUI/Sources/NativePresentation.swift",
        "swift/BonsaiSwiftUI/Sources/BonsaiSession.swift",
        "swift/BonsaiSwiftUI/Sources/NativeTextField.swift",
        "swift/BonsaiSwiftUI/Sources/NativeMenu.swift",
        "swift/BonsaiSwiftUI/Sources/BonsaiNativeViews.swift",
        "ocaml/protocol/binary_codec.ml", "examples/note/bonsai-swiftui.sexp",
        "native/test/note_device.swift",
    ]
    metadata = {
        "sourceRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "worktree": "Uncommitted implementation; exact source hashes below",
        "date": "2026-09-15", "device": "iPhone 13 (iPhone14,5)",
        "osBuild": "23G83", "xcode": "26.1.1 (17B100)",
        "nativeObjectSha256": sha(args.native_object),
        "sourceSha256": {name: sha(ROOT / name) for name in sources},
        "referenceSha256": sha(args.reference),
        "captureSha256": {f"{name}.png": sha(args.captures / f"{name}.png") for name in (
            "cornell-system", "cornell", "templates", "templates-cool", "templates-focused",
            "templates-focused-cool", "templates-after-keyboard", "search-empty", "reading",
            "reading-end", "editing-keyboard", "narrow", "narrow-large-text")},
        "referenceCrops": REFERENCE_CROPS, "windowCrop": capture_crop,
        "normalization": "390 pixels wide, preserved aspect ratio; crop and resize only",
        "fixtures": {"cornell": "Fresh warm Cornell; both disclosures collapsed",
                     "templates": "Empty query; top of catalog", "reading": "Fresh cool Reading; top of document"},
        "acceptance": result,
    }
    (args.output / "evidence.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(args.output)


if __name__ == "__main__":
    main()
