"""Run the real Note complete object in a native macOS window."""
from pathlib import Path
import json
import os
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tool"))
from link_swiftui_runtime import stage_object, system_libraries


def main():
    bundle = ROOT / "_build/validation/NoteWindowAcceptance.app"
    executable = bundle / "Contents/MacOS/NoteWindowAcceptance"
    executable.parent.mkdir(parents=True, exist_ok=True)
    (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "org.bonsai-swiftui.test.note-window",
        "CFBundleName": executable.name, "CFBundleExecutable": executable.name,
        "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "26.0", "LSUIElement": True,
    }))
    shutil.copytree(ROOT / "examples/note/resources", bundle / "Contents/Resources", dirs_exist_ok=True)
    subprocess.run(["dune", "build", "examples/note/ocaml/native_embed.exe.o"], cwd=ROOT, check=True)
    complete = stage_object(ROOT / "_build/default/examples/note/ocaml/native_embed.exe.o",
                            bundle / "Contents/note.complete.o")
    subprocess.run(["swift", "build", "--scratch-path", "_build/swift", "--target", "BonsaiSwiftUI"], cwd=ROOT, check=True)
    module = Path(subprocess.check_output(["swift", "build", "--scratch-path", "_build/swift", "--show-bin-path"], cwd=ROOT, text=True).strip())
    outputs = json.loads((module / "BonsaiSwiftUI.build/output-file-map.json").read_text())
    objects = sorted(value["object"] for value in outputs.values() if "object" in value)
    subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0",
        "-I", str(ROOT / "native/src"), "-I", str(module / "Modules"), *objects, str(complete),
        "-framework", "CoreFoundation", "-framework", "Security", *system_libraries(complete),
        str(ROOT / "swift/BonsaiSwiftUI/Tests/AccessibilitySupport.swift"),
        str(ROOT / "native/test/note_window.swift"), "-o", str(executable)], cwd=ROOT, check=True)
    subprocess.run([str(executable)], cwd=ROOT, check=True, timeout=90)


if __name__ == "__main__":
    main()
