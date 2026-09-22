"""Typecheck supported hosts and verify explicit unsupported-target diagnostics."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "swift/BonsaiSwiftUI/Sources/PlatformSupport.swift"


class PlatformTests(unittest.TestCase):
    def typecheck(self, sdk, target):
        sdk_path = subprocess.check_output(
            ["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True
        ).strip()
        return subprocess.run(
            ["xcrun", "swiftc", "-typecheck", "-sdk", sdk_path, "-target", target, str(SOURCE)],
            capture_output=True,
            text=True,
        )

    def test_supported_platforms_typecheck(self):
        for sdk, target in [
            ("iphoneos", "arm64-apple-ios26.0"),
            ("iphonesimulator", "arm64-apple-ios26.0-simulator"),
            ("macosx", "arm64-apple-macos26.0"),
        ]:
            with self.subTest(target=target):
                result = self.typecheck(sdk, target)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_swift_module_typechecks_for_physical_ios(self):
        sdk_path = subprocess.check_output(
            ["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True
        ).strip()
        sources = sorted(SOURCE.parent.glob("*.swift"))
        with tempfile.TemporaryDirectory(prefix="bonsai-ios-swift-") as directory:
            module = Path(directory) / "BonsaiSwiftUI.swiftmodule"
            result = subprocess.run(
                ["xcrun", "swiftc", "-emit-module", "-parse-as-library",
                 "-module-name", "BonsaiSwiftUI", "-emit-module-path", str(module),
                 "-sdk", sdk_path, "-target", "arm64-apple-ios26.0",
                 "-I", str(ROOT / "native/src"), *map(str, sources)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            for application in sorted((ROOT / "examples").glob("*/swift/App.swift")):
                with self.subTest(example=application.parent.parent.name):
                    result = subprocess.run(
                        ["xcrun", "swiftc", "-typecheck", "-parse-as-library",
                         "-sdk", sdk_path, "-target", "arm64-apple-ios26.0",
                         "-I", directory, "-I", str(ROOT / "native/src"),
                         *map(str, sorted(application.parent.glob("*.swift")))],
                        capture_output=True, text=True,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_catalyst_and_intel_macos_are_explicitly_rejected(self):
        for sdk, target, diagnostic in [
            ("macosx", "arm64-apple-ios26.0-macabi", "Mac Catalyst is unsupported"),
            ("macosx", "x86_64-apple-macos26.0", "Only arm64 is supported"),
        ]:
            with self.subTest(target=target):
                result = self.typecheck(sdk, target)
                self.assertNotEqual(result.returncode, 0, "Unsupported target was accepted")
                self.assertIn(diagnostic, result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
