"""Exercise native swipe recognition inside a standalone SwiftUI App."""
from pathlib import Path
import os
import plistlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]

class SwipeWindowTests(unittest.TestCase):
    def test_swipe_window(self):
        bundle = ROOT / "_build/validation/SwipeWindowAcceptance.app"
        executable = bundle / "Contents/MacOS/SwipeWindowAcceptance"
        executable.parent.mkdir(parents=True, exist_ok=True)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.bonsai-swiftui.test.swipe-window",
            "CFBundleName": "SwipeWindowAcceptance", "CFBundleExecutable": executable.name,
            "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "26.0", "LSUIElement": True,
        }))
        native = ROOT / "_build/default/native/test"
        sources = sorted((ROOT / "swift/BonsaiSwiftUI/Sources").glob("*.swift"))
        build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0",
            "-D", "BONSAI_STANDALONE_TEST", "-I", str(ROOT / "native/src"), "-L", str(native), "-lruntime_fixture",
            "-Xlinker", "-rpath", "-Xlinker", str(native), *map(str, sources),
            str(ROOT / "swift/BonsaiSwiftUI/Tests/AccessibilitySupport.swift"),
            str(ROOT / "swift/BonsaiSwiftUI/Tests/TreeFixture.swift"),
            str(ROOT / "swift/BonsaiSwiftUI/Tests/SwipeActionsFixture.swift"),
            str(ROOT / "native/test/swipe_window.swift"), "-o", str(executable)],
            cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
        for args in [[], ["--rtl"], ["--vertical"]]:
            with self.subTest(arguments=args):
                result = subprocess.run([str(executable), *args], cwd=ROOT, env=os.environ,
                                        capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("PASS: native swipe axis arbitration", result.stdout)
                print(result.stdout)

if __name__ == "__main__":
    unittest.main(verbosity=2)
