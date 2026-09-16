"""Build real Xcode hosts with the Swift package and OCaml Mail complete object."""

import importlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tool/build_swiftui_example.py"
NATIVE = ROOT / "_build/default/examples/mail/ocaml/native_embed.exe.o"


class HostConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="host configuration ")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / "swift").mkdir()
        (self.root / "swift/App.swift").write_text("import SwiftUI\n")
        (self.root / "apple-tests").mkdir()
        (self.root / "apple-tests/Test.swift").write_text("import XCTest\n")
        self.host = self.root / "apple"
        sys.path.insert(0, str(ROOT / "tool"))
        self.generator = importlib.import_module("swiftui_xcode_host")

    def generate(self, **options):
        return self.generator.generate_project(
            framework_root=ROOT, application_root=self.root, host_directory=self.host,
            product_name="Acceptance", bundle_identifiers={"macos": "org.example.desktop", "ios": "org.example.phone"},
            **options)

    def snapshot(self):
        return {str(p.relative_to(self.root)): (p.read_bytes(), p.stat().st_mtime_ns)
                if p.is_file() else (None, p.stat().st_mtime_ns)
                for p in self.root.rglob("*") if not p.is_symlink()}

    def test_package_products_and_independent_test_entitlements(self):
        package = {"id": "collections", "url": "https://github.com/apple/swift-collections.git",
                   "requirement": {"exact": "1.1.4"},
                   "products": [{"name": "OrderedCollections", "platforms": ["macos"]}]}
        source = self.root / "input.plist"
        source.write_bytes(plistlib.dumps({"keychain-access-groups": ["$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)"]}))
        inputs = {"macos": {p.lower(): "input.plist" for p in ("Debug", "Profile", "Release")}}
        project = self.generate(entitlements=inputs, swift_packages=[package])
        result = subprocess.run(["plutil", "-convert", "json", "-o", "-", project / "project.pbxproj"], capture_output=True, text=True, check=True)
        import json
        objects = json.loads(result.stdout)["objects"]
        remote = [v for v in objects.values() if v["isa"] == "XCRemoteSwiftPackageReference"]
        self.assertEqual(len(remote), 1)
        self.assertEqual(remote[0]["requirement"], {"kind": "exactVersion", "version": "1.1.4"})
        for target in [v for v in objects.values() if v["isa"] == "PBXNativeTarget"]:
            products = [objects[r]["productName"] for r in target["packageProductDependencies"]]
            self.assertEqual("OrderedCollections" in products, target["name"] == "Acceptance-macOS")
            for ref in objects[target["buildConfigurationList"]]["buildConfigurations"]:
                config = objects[ref]
                settings = config["buildSettings"]
                self.assertTrue(settings["PRODUCT_BUNDLE_IDENTIFIER"].startswith("org.example.desktop" if "macOS" in target["name"] else "org.example.phone"))
                path = settings.get("CODE_SIGN_ENTITLEMENTS")
                if path:
                    effective = plistlib.loads((self.host / path).read_bytes())
                    self.assertEqual(bool(effective), target["name"] == "Acceptance-macOS")
        before = self.snapshot()
        self.generate(entitlements=inputs, swift_packages=[package], check=True)
        self.generate(entitlements=inputs, swift_packages=[package])
        self.assertEqual(before, self.snapshot())

    def test_entitlement_symlink_escapes_and_typed_merge_conflicts(self):
        self.generate()
        source = self.root / "input.plist"
        inputs = {"macos": {p.lower(): "input.plist" for p in ("Debug", "Profile", "Release")}}
        for destination in (ROOT / "Package.swift", self.host / "Info-macOS.plist"):
            source.symlink_to(destination)
            before = self.snapshot()
            with self.assertRaisesRegex(ValueError, "outside|generated|ownership"):
                self.generate(entitlements=inputs)
            self.assertEqual(before, self.snapshot())
            source.unlink()
        # bool and int compare equal in Python; entitlement merging must preserve types.
        for value in (1, [True], {"nested": 1}):
            from unittest.mock import patch
            source.write_bytes(plistlib.dumps({"required": value}))
            required = {"required": True if value == 1 else [1] if isinstance(value, list) else {"nested": True}}
            with patch.object(self.generator, "FRAMEWORK_ENTITLEMENTS", {"macos": required, "ios": {}}):
                before = self.snapshot()
                with self.assertRaisesRegex(ValueError, "macos.*debug.*required"):
                    self.generate(entitlements=inputs)
                self.assertEqual(before, self.snapshot())

    def test_lock_projection_validation_and_obsolete_file_cleanup(self):
        import json
        package = {"id": "collections", "url": "https://github.com/apple/swift-collections.git",
                   "requirement": {"exact": "1.1.4"},
                   "products": [{"name": "OrderedCollections", "platforms": ["macos", "ios"]}]}
        self.generate(swift_packages=[package])
        lock = self.root / "swift-packages/Package.resolved"
        lock.parent.mkdir()
        pin = {"identity": "swift-collections", "kind": "remoteSourceControl", "location": package["url"],
               "state": {"version": "1.1.4", "revision": "a" * 40}}
        lock.write_text(json.dumps({"version": 3, "pins": [pin], "originHash": "fixture"}))
        self.generate(swift_packages=[package])
        projection = self.host / "Acceptance.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        self.assertEqual(lock.read_bytes(), projection.read_bytes())
        before = self.snapshot()
        self.generate(swift_packages=[package], check=True)
        self.assertEqual(before, self.snapshot())
        lock.write_text("not json")
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, "lock|Package.resolved"):
            self.generate(swift_packages=[package])
        self.assertEqual(before, self.snapshot())
        lock.unlink()
        self.generate(swift_packages=[package])
        self.assertFalse(projection.exists())
        (self.host / "macOS.entitlements").write_bytes(plistlib.dumps({}))
        (self.host / "keep.txt").write_text("user file")
        self.generate()
        self.assertFalse((self.host / "macOS.entitlements").exists())
        self.assertEqual((self.host / "keep.txt").read_text(), "user file")


class XcodeHostTests(unittest.TestCase):
    def assert_runtime_privacy_manifest(self, bundle):
        manifests = [path for path in bundle.rglob("PrivacyInfo.xcprivacy")
                     if any(parent.name == "BonsaiSwiftUI_BonsaiSwiftUI.bundle"
                            for parent in path.parents)]
        self.assertEqual(len(manifests), 1,
                         "The built App must contain the runtime's Swift package privacy manifest")
        manifest = plistlib.loads(manifests[0].read_bytes())
        categories = {entry["NSPrivacyAccessedAPIType"]: entry["NSPrivacyAccessedAPITypeReasons"]
                      for entry in manifest["NSPrivacyAccessedAPITypes"]}
        self.assertEqual(categories, {
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
            "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
        })
        self.assertEqual(manifest["NSPrivacyCollectedDataTypes"], [])
        self.assertFalse(manifest["NSPrivacyTracking"])

    def command(self, *arguments, success=True):
        result = subprocess.run(
            list(map(str, arguments)), cwd=ROOT, text=True,
            capture_output=True, timeout=300,
        )
        if success:
            self.assertEqual(result.returncode, 0, (result.stdout + result.stderr)[-12000:])
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def generate(self, host):
        self.command(sys.executable, BUILDER, "mail", "--generate-only", "--host-directory", host)
        project = host / "BonsaiMail.xcodeproj"
        self.assertTrue(project.is_dir(), "No Xcode application project was generated")
        return project

    def test_generation_and_apple_destination_settings(self):
        with tempfile.TemporaryDirectory(prefix="bonsai Xcode host ") as directory:
            host = Path(directory)
            project = self.generate(host)
            files = {p.relative_to(host): p.read_bytes() for p in host.rglob("*") if p.is_file()}
            (host / "user-notes.txt").write_text("Keep application-owned files.\n")
            self.generate(host)
            self.assertEqual(files, {p: (host / p).read_bytes() for p in files})
            self.assertTrue((host / "user-notes.txt").is_file())
            for target, sdk, minimum_key, minimum in [
                ("BonsaiMail-macOS", "macosx", "MACOSX_DEPLOYMENT_TARGET", "26.0"),
                ("BonsaiMail-iOS", "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET", "18.0"),
            ]:
                for configuration in ("Debug", "Profile", "Release"):
                    with self.subTest(target=target, configuration=configuration):
                        settings = self.command(
                            "xcodebuild", "-project", project, "-target", target,
                            "-configuration", configuration, "-showBuildSettings",
                        ).stdout
                        self.assertIn(f"{minimum_key} = {minimum}", settings)
                        self.assertIn(f"SUPPORTED_PLATFORMS = {sdk}", settings)
                        self.assertIn("ARCHS = arm64", settings)
                        self.assertIn(f"Native/{sdk}/{configuration}/runtime.complete.o", settings)
                        self.assertIn("SUPPORTS_MACCATALYST = NO", settings)

    def test_mail_build_and_xcode_runtime_test(self):
        with tempfile.TemporaryDirectory(prefix="bonsai Mail build ") as directory:
            host = Path(directory)
            self.command(sys.executable, BUILDER, "mail", "--host-directory", host)
            bundle = host / "DerivedData/Build/Products/Debug/BonsaiMail.app"
            metadata = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
            self.assertEqual(metadata["LSMinimumSystemVersion"], "26.0")
            self.assertEqual(metadata["CFBundleIdentifier"], "org.bonsai-swiftui.example.mail")
            self.command("codesign", "--verify", "--deep", "--strict", bundle)
            executable = bundle / "Contents/MacOS/BonsaiMail"
            self.assertEqual(self.command("xcrun", "lipo", "-archs", executable).stdout.strip(), "arm64")
            result = self.command(
                "xcodebuild", "-project", host / "BonsaiMail.xcodeproj",
                "-scheme", "BonsaiMail-macOS", "-configuration", "Debug",
                "-destination", "platform=macOS,arch=arm64", "-derivedDataPath", host / "DerivedData",
                "test",
            )
            self.assertRegex(result.stdout, r"testPackagedMailStartsPresentsAndRestarts.*passed")
            self.assertIn("** TEST SUCCEEDED **", result.stdout)

    def test_system_sqlite_linkage_follows_the_native_object(self):
        for example, product, needs_sqlite in [
            ("counter", "BonsaiCounter", False),
            ("sqlite_worker", "BonsaiSqliteWorker", True),
        ]:
            for sdk, platform, configuration, build_root in [
                ("macosx", "macOS", "Debug", "_build/default"),
                ("iphoneos", "iOS", "Release", "_build/ios/swiftui-framework/default.ios"),
            ]:
                with self.subTest(example=example, platform=platform), tempfile.TemporaryDirectory(
                    prefix="Bonsai native link requirements "
                ) as directory:
                    host = Path(directory)
                    native = ROOT / build_root / "examples" / example / "ocaml/native_embed.exe.o"
                    self.assertTrue(native.is_file(), f"Build the {platform} {example} complete object first")
                    self.command(sys.executable, BUILDER, example, "--generate-only", "--host-directory", host)
                    staged = host / "Native" / sdk / configuration / "runtime.complete.o"
                    staged.parent.mkdir(parents=True)
                    shutil.copyfile(native, staged)
                    self.command(
                        "xcodebuild", "-project", host / f"{product}.xcodeproj",
                        "-scheme", f"{product}-{platform}", "-configuration", configuration,
                        "-destination", "platform=macOS,arch=arm64" if platform == "macOS" else "generic/platform=iOS",
                        "-derivedDataPath", host / "DerivedData", "CODE_SIGNING_ALLOWED=NO", "build",
                    )
                    products = host / "DerivedData/Build/Products"
                    bundle = products / (configuration if platform == "macOS" else configuration + "-iphoneos") / f"{product}.app"
                    binary_root = bundle / "Contents/MacOS" if platform == "macOS" else bundle
                    binaries = [binary_root / product, *binary_root.glob("*.debug.dylib")]
                    dependencies = "\n".join(self.command("otool", "-L", binary).stdout for binary in binaries)
                    self.assertEqual("/usr/lib/libsqlite3.dylib" in dependencies, needs_sqlite, dependencies)
                    self.assertIn("Security.framework/", dependencies)
                    self.assertEqual(list(bundle.rglob("*sqlite*.dylib")), [], "SQLite must come from the OS")

    def test_ios_ui_tests_build_separate_from_the_application_runtime(self):
        native = ROOT / "_build/ios/swiftui-framework/default.ios/examples/mail/ocaml/native_embed.exe.o"
        self.assertTrue(native.is_file(), "Build Mail's physical-iOS complete object first")
        with tempfile.TemporaryDirectory(prefix="bonsai device UI tests ") as directory:
            host = Path(directory)
            project = self.generate(host)
            staged = host / "Native/iphoneos/Release/runtime.complete.o"
            staged.parent.mkdir(parents=True)
            shutil.copyfile(native, staged)
            self.command(
                "xcodebuild", "-project", project, "-scheme", "BonsaiMail-iOS",
                "-configuration", "Release", "-destination", "generic/platform=iOS",
                "-derivedDataPath", host / "DerivedData", "CODE_SIGNING_ALLOWED=NO",
                "build-for-testing",
            )
            products = host / "DerivedData/Build/Products"
            self.assert_runtime_privacy_manifest(products / "Release-iphoneos/BonsaiMail.app")
            manifests = list(products.glob("*.xctestrun"))
            self.assertEqual(len(manifests), 1)
            tests = plistlib.loads(manifests[0].read_bytes())
            self.assertIn("BonsaiMail-iOSUITests", tests,
                          "Application-owned iOS UI tests must be included in the device test run")
            test = tests["BonsaiMail-iOSUITests"]
            self.assertTrue(test["IsUITestBundle"])
            application = Path(test["UITargetAppPath"].replace("__TESTROOT__", str(products)))
            app_metadata = plistlib.loads((application / "Info.plist").read_bytes())
            self.assertEqual(app_metadata["CFBundleIdentifier"], "org.bonsai-swiftui.example.mail")
            app_symbols = self.command("xcrun", "nm", "-g", application / app_metadata["CFBundleExecutable"]).stdout
            self.assertIn("_bs_runtime_create", app_symbols)
            bundle = Path(test["TestHostPath"].replace("__TESTROOT__", str(products)))
            metadata = plistlib.loads((bundle / "Info.plist").read_bytes())
            executable = bundle / metadata["CFBundleExecutable"]
            symbols = self.command("xcrun", "nm", "-g", executable).stdout
            self.assertNotIn("_bs_runtime_create", symbols)
            self.assertNotIn("_caml_startup", symbols)
            self.assertEqual(self.command("xcrun", "lipo", "-archs", executable).stdout.strip(), "arm64")
            test_bundles = list(bundle.glob("PlugIns/*.xctest"))
            self.assertEqual(len(test_bundles), 1)
            test_metadata = plistlib.loads((test_bundles[0] / "Info.plist").read_bytes())
            test_symbols = self.command("xcrun", "nm", "-g", test_bundles[0] / test_metadata["CFBundleExecutable"]).stdout
            self.assertNotIn("_bs_runtime_create", test_symbols)
            self.assertNotIn("_caml_startup", test_symbols)

    def test_ios_runtime_tests_build_with_an_isolated_application_host(self):
        native = ROOT / "_build/ios/swiftui-framework/default.ios/examples/mail/ocaml/native_embed.exe.o"
        self.assertTrue(native.is_file(), "Build Mail's physical-iOS complete object first")
        with tempfile.TemporaryDirectory(prefix="bonsai device test host ") as directory:
            host = Path(directory)
            project = self.generate(host)
            staged = host / "Native/iphoneos/Release/runtime.complete.o"
            staged.parent.mkdir(parents=True)
            shutil.copyfile(native, staged)
            self.command(
                "xcodebuild", "-project", project, "-scheme", "BonsaiMail-iOS",
                "-configuration", "Release", "-destination", "generic/platform=iOS",
                "-derivedDataPath", host / "DerivedData", "CODE_SIGNING_ALLOWED=NO",
                "build-for-testing",
            )
            products = host / "DerivedData/Build/Products"
            manifests = list(products.glob("*.xctestrun"))
            self.assertEqual(len(manifests), 1)
            test = plistlib.loads(manifests[0].read_bytes())["BonsaiMail-iOSTests"]
            self.assertTrue(test.get("IsAppHostedTestBundle"),
                            "Physical devices require application-hosted XCTest bundles")
            bundle = Path(test["TestHostPath"].replace("__TESTROOT__", str(products)))
            metadata = plistlib.loads((bundle / "Info.plist").read_bytes())
            executable = bundle / metadata["CFBundleExecutable"]
            self.assertTrue(executable.is_file(), test["TestHostPath"])
            self.assertNotEqual(bundle.name, "BonsaiMail.app",
                                "The runtime test must not compete with the Mail UI session")
            symbols = self.command("xcrun", "nm", "-g", executable).stdout
            self.assertNotIn("_bs_runtime_create", symbols,
                             "The empty host must not link a second OCaml runtime")
            self.assertNotIn("_caml_startup", symbols)
            self.assertEqual(metadata["MinimumOSVersion"], "18.0")
            self.assertEqual(metadata["UIDeviceFamily"], [1, 2])
            self.assertEqual(self.command("xcrun", "lipo", "-archs", executable).stdout.strip(), "arm64")

    def test_macos_object_cannot_be_used_for_device_ios(self):
        with tempfile.TemporaryDirectory(prefix="bonsai wrong platform ") as directory:
            result = self.command(
                sys.executable, BUILDER, "mail", "--host-directory", directory,
                "--target", "iphoneos", "--native-object", NATIVE,
                success=False,
            )
            self.assertIn("expected platform IOS", result.stdout + result.stderr)

    def test_optimized_mail_builds_and_runs_without_intel_artifacts(self):
        with tempfile.TemporaryDirectory(prefix="bonsai optimized Mail ") as directory:
            host = Path(directory)
            for configuration in ("Release", "Profile"):
                with self.subTest(configuration=configuration):
                    self.command(sys.executable, BUILDER, "mail", "--host-directory", host,
                                 "--configuration", configuration)
                    executable = host / "DerivedData/Build/Products" / configuration / "BonsaiMail.app/Contents/MacOS/BonsaiMail"
                    self.assertEqual(self.command("xcrun", "lipo", "-archs", executable).stdout.strip(), "arm64")
                    result = self.command(
                        "xcodebuild", "-project", host / "BonsaiMail.xcodeproj",
                        "-scheme", "BonsaiMail-macOS", "-configuration", configuration,
                        "-destination", "platform=macOS,arch=arm64",
                        "-derivedDataPath", host / "DerivedData", "test",
                    )
                    self.assertRegex(result.stdout, r"testPackagedMailStartsPresentsAndRestarts.*passed")
                    self.assertIn("** TEST SUCCEEDED **", result.stdout)

    def test_resources_preserve_nested_paths_in_built_bundle(self):
        with tempfile.TemporaryDirectory(prefix="bonsai resource host ") as directory:
            root = Path(directory)
            self.generate(root / "preflight")
            generator = importlib.import_module("swiftui_xcode_host")
            example = root / "resource example"
            shutil.copytree(ROOT / "examples/mail/swift", example / "swift")
            for path, value in [("one/item.dat", b"first"), ("two/item.dat", b"second")]:
                resource = example / "resources" / path
                resource.parent.mkdir(parents=True, exist_ok=True)
                resource.write_bytes(value)
            host = root / "apple"
            project = generator.generate_project(
                framework_root=ROOT, application_root=example, host_directory=host,
                product_name="BonsaiResources", bundle_identifiers={"macos": "org.bonsai-swiftui.test.resources", "ios": "org.bonsai-swiftui.test.resources"},
            )
            self.assertNotIn("TestHost", (project / "project.pbxproj").read_text(),
                             "Applications without tests must not acquire a test host")
            self.assertNotIn("UITests", (project / "project.pbxproj").read_text())
            native = host / "Native/macosx/Debug/runtime.complete.o"
            native.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(NATIVE, native)
            self.command(
                "xcodebuild", "-project", project, "-scheme", "BonsaiResources-macOS",
                "-configuration", "Debug", "-destination", "platform=macOS,arch=arm64",
                "-derivedDataPath", host / "DerivedData", "build",
            )
            resources = host / "DerivedData/Build/Products/Debug/BonsaiResources.app/Contents/Resources"
            self.assertEqual((resources / "one/item.dat").read_bytes(), b"first")
            self.assertEqual((resources / "two/item.dat").read_bytes(), b"second")
            self.assert_runtime_privacy_manifest(resources.parent.parent)

    def test_generated_project_is_portable_between_checkouts(self):
        with tempfile.TemporaryDirectory(prefix="bonsai relocated checkout ") as directory:
            generator = importlib.import_module("swiftui_xcode_host")
            projects = []
            for checkout in ("first", "second"):
                framework = Path(directory) / checkout
                example = framework / "examples/mail"
                shutil.copytree(ROOT / "examples/mail/swift", example / "swift")
                project = generator.generate_project(
                    framework_root=framework, application_root=example,
                    host_directory=example / "apple", product_name="BonsaiMail",
                    bundle_identifiers={"macos": "org.bonsai-swiftui.example.mail", "ios": "org.bonsai-swiftui.example.mail"},
                )
                projects.append((project / "project.pbxproj").read_text())
            self.assertEqual(projects[0], projects[1])
            self.assertNotIn(directory, projects[0])


if __name__ == "__main__":
    unittest.main(verbosity=2)
