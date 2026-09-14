"""Run the actual OCaml Navigation example inside a standalone SwiftUI scene."""
from pathlib import Path
import plistlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NavigationWindowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        bundle = ROOT / "_build/validation/NavigationWindowTest.app"
        executable = bundle / "Contents/MacOS/NavigationWindowTest"
        executable.parent.mkdir(parents=True, exist_ok=True)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.bonsai-swiftui.test.navigation-window",
            "CFBundleName": "NavigationWindowTest", "CFBundleExecutable": executable.name,
            "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "26.0",
            "LSUIElement": True,
        }))
        native = ROOT / "_build/default/native/test"
        sources = sorted((ROOT / "swift/BonsaiSwiftUI/Sources").glob("*.swift"))
        build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0",
                        "-I", str(ROOT / "native/src"), "-L", str(native), "-lruntime_fixture",
                        "-Xlinker", "-rpath", "-Xlinker", str(native),
                        *map(str, sources), str(ROOT / "swift/BonsaiSwiftUI/Tests/AccessibilitySupport.swift"),
                        str(ROOT / "native/test/navigation_window.swift"), "-o", str(executable)],
                       cwd=ROOT, capture_output=True, text=True)
        if build.returncode:
            raise AssertionError(build.stdout + build.stderr)
        cls.executable = executable

    def test_native_app_bars_reach_actual_gallery(self):
        result = subprocess.run([str(self.executable), "--app-bars"], cwd=ROOT,
                                capture_output=True, text=True, timeout=50)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS: actual Gallery app bars", result.stdout)

    def test_native_toolbar_reaches_actual_gallery(self):
        result = subprocess.run([str(self.executable), "--toolbar"], cwd=ROOT,
                                capture_output=True, text=True, timeout=40)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS: actual Gallery native toolbar", result.stdout)

    def test_native_system_back_reaches_ocaml(self):
        result = subprocess.run([str(self.executable)], cwd=ROOT, capture_output=True, text=True, timeout=40)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS: actual SwiftUI NavigationStack system Back", result.stdout)

    def test_native_system_sidebar_reaches_actual_gallery(self):
        result = subprocess.run([str(self.executable), "--split"], cwd=ROOT,
                                capture_output=True, text=True, timeout=40)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS: actual Gallery system sidebar", result.stdout)

    def test_native_system_sidebar_reaches_two_column_gallery(self):
        result = subprocess.run([str(self.executable), "--split-two-columns"], cwd=ROOT,
                                capture_output=True, text=True, timeout=40)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS: actual Gallery system sidebar", result.stdout)

    def test_native_system_tabs_reach_actual_gallery(self):
        result = subprocess.run([str(self.executable), "--tabs"], cwd=ROOT,
                                capture_output=True, text=True, timeout=40)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS: actual Gallery system tabs", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
