"""Exercise mixed collection reset in an actual SwiftUI application window."""
from pathlib import Path
import plistlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MixedCollectionWindowTests(unittest.TestCase):
    def test_mixed_collection_window(self):
        bundle = ROOT / "_build/validation/MixedCollectionWindowAcceptance.app"
        executable = bundle / "Contents/MacOS/MixedCollectionWindowAcceptance"
        executable.parent.mkdir(parents=True, exist_ok=True)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.bonsai-swiftui.test.mixed-collection-window",
            "CFBundleName": executable.name, "CFBundleExecutable": executable.name,
            "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "26.0", "LSUIElement": True,
        }))
        native = ROOT / "_build/default/native/test"
        sources = sorted((ROOT / "swift/BonsaiSwiftUI/Sources").glob("*.swift"))
        build = subprocess.run([
            "xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0",
            "-I", str(ROOT / "native/src"), "-L", str(native), "-lruntime_fixture",
            "-Xlinker", "-rpath", "-Xlinker", str(native), *map(str, sources),
            str(ROOT / "swift/BonsaiSwiftUI/Tests/AccessibilitySupport.swift"),
            str(ROOT / "native/test/mixed_collection_window.swift"), "-o", str(executable),
        ], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
        for flags in ([], ["--rtl"], ["--horizontal"], ["--horizontal", "--rtl"]):
            with self.subTest(flags=flags):
                result = subprocess.run([str(executable), *flags], cwd=ROOT,
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("PASS: actual mixed collection window", result.stdout)
                print(result.stdout, flush=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
