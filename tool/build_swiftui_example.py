"""Generate and build a SwiftUI example using Xcode and its OCaml complete object."""

import argparse
from pathlib import Path
import shutil
import subprocess

from link_swiftui_runtime import stage_object
from swiftui_xcode_host import CONFIGURATIONS, generate_project


ROOT = Path(__file__).resolve().parents[1]


def run(*arguments):
    subprocess.run(list(map(str, arguments)), cwd=ROOT, check=True)


def main():
    available = sorted(path.parent.parent.name for path in (ROOT / "examples").glob("*/swift/App.swift"))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("example", choices=available)
    parser.add_argument("--host-directory", type=Path)
    parser.add_argument("--generate-only", action="store_true")
    parser.add_argument("--target", choices=("macos", "iphoneos"), default="macos")
    parser.add_argument("--configuration", choices=CONFIGURATIONS, default="Debug")
    parser.add_argument("--native-object", type=Path, help="Use an already-built complete object for the selected target and configuration")
    parser.add_argument("--development-team", default="", help="Apple development team for physical-device signing")
    args = parser.parse_args()
    example = args.example
    name = f"Bonsai{example.title().replace('_', '')}"
    host = (args.host_directory or ROOT / "examples" / example / "apple").resolve()
    if args.target == "iphoneos" and not args.generate_only and args.native_object is None:
        parser.error("iPhoneOS builds require --native-object from the iOS 26 arm64 cross-toolchain")
    project = generate_project(
        framework_root=ROOT, application_root=ROOT / "examples" / example,
        host_directory=host, product_name=name,
        bundle_identifiers={platform: f"org.bonsai-swiftui.example.{example.replace('_', '-')}"
                            for platform in ("macos", "ios")},
        development_team=args.development_team,
    )
    if args.generate_only:
        print(project)
        return
    sdk, platform, minimum, scheme = (
        ("macosx", "MACOS", "26.0", f"{name}-macOS") if args.target == "macos"
        else ("iphoneos", "IOS", "26.0", f"{name}-iOS")
    )
    source = args.native_object
    if source is None:
        target = f"examples/{example}/ocaml/native_embed.exe.o"
        profile = "dev" if args.configuration == "Debug" else "release"
        run("dune", "build", f"--profile={profile}", target)
        source = ROOT / "_build/default" / target
    run("sh", ROOT / "tool/ios/verify_complete_object.sh", source, platform, minimum, "arm64")
    complete = host / "Native" / sdk / args.configuration / "runtime.complete.o"
    if args.target == "macos":
        stage_object(source, complete)
    else:
        complete.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, complete)
    destination = "platform=macOS,arch=arm64" if args.target == "macos" else "generic/platform=iOS"
    run("xcodebuild", "-project", project, "-scheme", scheme, "-configuration", args.configuration,
        "-destination", destination, "-derivedDataPath", host / "DerivedData", "build")
    configuration = args.configuration + ("-iphoneos" if args.target == "iphoneos" else "")
    bundle = host / "DerivedData/Build/Products" / configuration / f"{name}.app"
    run("codesign", "--verify", "--deep", "--strict", bundle)
    print(bundle)


if __name__ == "__main__":
    main()
