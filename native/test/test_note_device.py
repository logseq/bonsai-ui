"""Build and launch physical-device acceptance against the real Note object.

The app records onscreen captures and result.json in Documents/note-acceptance.
No XCTest manager, simulator, synthetic application model, or offscreen host is used.
"""
from pathlib import Path
import argparse
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tool"))
from swiftui_xcode_host import generate_project


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-object", required=True, type=Path)
    parser.add_argument("--device", required=True)
    parser.add_argument("--development-team", required=True)
    args = parser.parse_args()
    app = ROOT / "_build/validation/note-device-host"
    (app / "swift").mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "native/test/note_device.swift", app / "swift/App.swift")
    shutil.copytree(ROOT / "examples/note/resources", app / "resources", dirs_exist_ok=True)
    host = app / "apple"
    native = host / "Native/iphoneos/Debug/runtime.complete.o"
    native.parent.mkdir(parents=True, exist_ok=True)
    native.unlink(missing_ok=True)
    shutil.copy2(args.native_object, native)
    generate_project(framework_root=ROOT, application_root=app, host_directory=host,
                     product_name="NoteDeviceAcceptance",
                     bundle_identifier="org.bonsai-swiftui.test.note-device",
                     development_team=args.development_team)
    subprocess.run(["xcodebuild", "-project", str(host / "NoteDeviceAcceptance.xcodeproj"),
                    "-scheme", "NoteDeviceAcceptance-iOS", "-configuration", "Debug",
                    "-destination", f"id={args.device}", "-derivedDataPath", str(host / "DerivedData"),
                    "-allowProvisioningUpdates", "build"], check=True, cwd=ROOT)
    bundle = host / "DerivedData/Build/Products/Debug-iphoneos/NoteDeviceAcceptance.app"
    subprocess.run(["xcrun", "devicectl", "device", "install", "app", "--device", args.device,
                    str(bundle)], check=True)
    subprocess.run(["xcrun", "devicectl", "device", "process", "launch", "--terminate-existing",
                    "--device", args.device, "org.bonsai-swiftui.test.note-device"], check=True)


if __name__ == "__main__":
    main()
