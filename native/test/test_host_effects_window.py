"""Exercise real host-effect dispatch using an isolated native macOS pasteboard."""
from pathlib import Path
import os
import plistlib
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class HostEffectsWindowTests(unittest.TestCase):
    def test_host_effects_window(self):
        bundle = ROOT / "_build/validation/HostEffectsWindowAcceptance.app"
        executable = bundle / "Contents/MacOS/HostEffectsWindowAcceptance"
        executable.parent.mkdir(parents=True, exist_ok=True)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.bonsai-swiftui.test.host-effects-window",
            "CFBundleName": executable.name, "CFBundleExecutable": executable.name,
            "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "26.0", "LSUIElement": True,
        }))
        native = ROOT / "_build/default/native/test"
        sources = sorted((ROOT / "swift/BonsaiSwiftUI/Sources").glob("*.swift"))
        build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-D", "BONSAI_STANDALONE_TEST", "-target", "arm64-apple-macos26.0",
            "-I", str(ROOT / "native/src"), "-L", str(native), "-lruntime_fixture",
            "-Xlinker", "-rpath", "-Xlinker", str(native), *map(str, sources),
            str(ROOT / "swift/BonsaiSwiftUI/Tests/AccessibilitySupport.swift"),
            str(ROOT / "swift/BonsaiSwiftUI/Tests/URLReceiverSupport.swift"),
            str(ROOT / "examples/host_effects/swift/ApplicationBridge.swift"),
            str(ROOT / "native/test/host_effects_window.swift"), "-o", str(executable)],
            cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
        result = subprocess.run([str(executable)], cwd=ROOT, env=os.environ,
                                capture_output=True, text=True, timeout=45)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS: actual Host Effects native window", result.stdout)
        print(result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
