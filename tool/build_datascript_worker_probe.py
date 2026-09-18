"""Build the physical-iOS SwiftUI runtime/persistence probe from a complete object."""

import argparse
from pathlib import Path
import shutil
import subprocess

from swiftui_xcode_host import generate_project


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-object", required=True, type=Path)
    parser.add_argument("--build-root", required=True, type=Path)
    parser.add_argument("--bundle-identifier", required=True)
    parser.add_argument("--development-team", default="")
    parser.add_argument("--signing-identity", default="Apple Development")
    args = parser.parse_args()
    subprocess.run([
        "sh", ROOT / "tool/ios/verify_complete_object.sh", args.native_object,
        "IOS", "26.0", "arm64",
    ], check=True)
    build = args.build_root.resolve()
    application = build / "application"
    sources = application / "swift"
    sources.mkdir(parents=True, exist_ok=True)
    for source in (ROOT / "tool/ios/fixtures/datascript-worker-host/swift").glob("*.swift"):
        shutil.copyfile(source, sources / source.name)
    shutil.copyfile(ROOT / "examples/sqlite_worker/swift/Startup.swift", sources / "Startup.swift")
    host = build / "host"
    project = generate_project(
        framework_root=ROOT, application_root=application, host_directory=host,
        product_name="DataScriptWorkerProbe", bundle_identifiers={"macos": args.bundle_identifier, "ios": args.bundle_identifier},
        development_team=args.development_team,
    )
    staged = host / "Native/iphoneos/Release/runtime.complete.o"
    staged.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(args.native_object, staged)
    signing = ([f"CODE_SIGN_IDENTITY={args.signing_identity}", "-allowProvisioningUpdates"]
               if args.development_team else ["CODE_SIGNING_ALLOWED=NO"])
    subprocess.run([
        "xcodebuild", "-project", project, "-scheme", "DataScriptWorkerProbe-iOS",
        "-configuration", "Release", "-destination", "generic/platform=iOS",
        "-derivedDataPath", host / "DerivedData", *signing, "build",
    ], check=True)
    app = host / "DerivedData/Build/Products/Release-iphoneos/DataScriptWorkerProbe.app"
    if args.development_team:
        subprocess.run(["codesign", "--verify", "--deep", "--strict", app], check=True)
    print(app)


if __name__ == "__main__":
    main()
