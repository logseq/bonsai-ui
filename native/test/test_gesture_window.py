"""Exercise native recognizers in a real OCaml-backed SwiftUI window."""
from pathlib import Path
import plistlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class GestureWindowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        bundle = ROOT / "_build/validation/GestureWindowAcceptance.app"
        cls.executable = bundle / "Contents/MacOS/GestureWindowAcceptance"
        cls.executable.parent.mkdir(parents=True, exist_ok=True)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.bonsai-swiftui.test.gesture-window",
            "CFBundleName": cls.executable.name, "CFBundleExecutable": cls.executable.name,
            "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "26.0", "LSUIElement": True,
        }))
        native = ROOT / "_build/default/native/test"
        sources = sorted((ROOT / "swift/BonsaiSwiftUI/Sources").glob("*.swift"))
        build = subprocess.run([
            "xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0",
            "-I", str(ROOT / "native/src"), "-L", str(native), "-lruntime_fixture",
            "-Xlinker", "-rpath", "-Xlinker", str(native), *map(str, sources),
            str(ROOT / "swift/BonsaiSwiftUI/Tests/AccessibilitySupport.swift"),
            str(ROOT / "native/test/gesture_window.swift"), "-o", str(cls.executable),
        ], cwd=ROOT, capture_output=True, text=True)
        if build.returncode:
            raise RuntimeError(build.stdout + build.stderr)

    def test_native_gestures(self):
        for scenario in ("recognition", "single", "drag", "rebind", "inactive", "pointer"):
            with self.subTest(scenario=scenario):
                result = subprocess.run([str(self.executable), "--" + scenario], cwd=ROOT,
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("PASS: actual OCaml Gesture window", result.stdout)
                print(result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
