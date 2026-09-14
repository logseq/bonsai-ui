"""Verify native search input and presentations through the real OCaml runtime."""
from pathlib import Path
import os
import plistlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]

class SearchWindowTests(unittest.TestCase):
    def test_search_window(self):
        bundle = ROOT / "_build/validation/SearchWindowAcceptance.app"
        executable = bundle / "Contents/MacOS/SearchWindowAcceptance"
        executable.parent.mkdir(parents=True, exist_ok=True)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.bonsai-swiftui.test.search",
            "CFBundleName": "SearchWindowAcceptance", "CFBundleExecutable": executable.name,
            "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "26.0", "LSUIElement": True,
        }))
        native = ROOT / "_build/default/native/test"
        sources = sorted((ROOT / "swift/BonsaiSwiftUI/Sources").glob("*.swift"))
        build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0",
            "-I", str(ROOT / "native/src"), "-L", str(native), "-lruntime_fixture",
            "-Xlinker", "-rpath", "-Xlinker", str(native), *map(str, sources),
            str(ROOT / "swift/BonsaiSwiftUI/Tests/AccessibilitySupport.swift"),
            str(ROOT / "native/test/search_window.swift"), "-o", str(executable)],
            cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
        for mode in range(3):
            with self.subTest(mode=mode):
                result = subprocess.run([str(executable), ["--inline", "--anchored", "--fullscreen"][mode]], cwd=ROOT, env=os.environ,
                                        capture_output=True, text=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(f"PASS: native search mode {mode}", result.stdout)
                print(result.stdout)

if __name__ == "__main__":
    unittest.main(verbosity=2)
