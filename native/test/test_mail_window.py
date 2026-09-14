"""Render the actual Mail app and optionally export its native window content."""
from pathlib import Path
import os
import json
import plistlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]

class MailWindowTests(unittest.TestCase):
    def test_mail_window(self):
        bundle = ROOT / "_build/validation/MailWindowAcceptance.app"
        executable = bundle / "Contents/MacOS/MailWindowAcceptance"
        executable.parent.mkdir(parents=True, exist_ok=True)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.bonsai-swiftui.test.mail-window",
            "CFBundleName": "MailWindowAcceptance", "CFBundleExecutable": executable.name,
            "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "26.0", "LSUIElement": True,
        }))
        native = ROOT / "_build/default/native/test"
        module = subprocess.run(
            ["swift", "build", "--scratch-path", "_build/swift", "--target", "BonsaiSwiftUI"],
            cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(module.returncode, 0, module.stdout + module.stderr)
        module_root = Path(subprocess.check_output(
            ["swift", "build", "--scratch-path", "_build/swift", "--show-bin-path"],
            cwd=ROOT, text=True).strip())
        outputs = json.loads((module_root / "BonsaiSwiftUI.build/output-file-map.json").read_text())
        objects = sorted(value["object"] for value in outputs.values() if "object" in value)
        self.assertTrue(objects, "Missing current Swift library objects")
        build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0",
            "-I", str(ROOT / "native/src"), "-L", str(native), "-lruntime_fixture",
            "-Xlinker", "-rpath", "-Xlinker", str(native),
            "-I", str(module_root / "Modules"), *objects,
            str(ROOT / "swift/BonsaiSwiftUI/Tests/AccessibilitySupport.swift"),
            str(ROOT / "native/test/mail_window.swift"), "-o", str(executable)],
            cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
        for appearance in ("light", "dark"):
            with self.subTest(appearance=appearance):
                environment = dict(os.environ, BONSAI_MAIL_HOST_APPEARANCE=appearance)
                result = subprocess.run([str(executable)], cwd=ROOT, env=environment,
                                        capture_output=True, text=True, timeout=45)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("PASS: actual Mail native window", result.stdout)
                print(result.stdout)

if __name__ == "__main__":
    unittest.main(verbosity=2)
