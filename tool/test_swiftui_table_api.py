"""Reproduce the independent SwiftUI Table API investigation, without Bonsai."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tool/probe_swiftui_table.swift"


class TableAPIInvestigation(unittest.TestCase):
    def test_physical_ios_api(self):
        sdk = subprocess.check_output(
            ["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True
        ).strip()
        result = subprocess.run(
            ["xcrun", "swiftc", "-typecheck", "-parse-as-library", "-sdk", sdk,
             "-target", "arm64-apple-ios18.0", str(SOURCE)],
            cwd=ROOT, capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_native_macos_api(self):
        with tempfile.TemporaryDirectory(prefix="bonsai-table-api-") as directory:
            executable = Path(directory) / "TableAPIProbe"
            result = subprocess.run(
                ["xcrun", "swiftc", "-parse-as-library", "-target",
                 "arm64-apple-macos26.0", str(SOURCE),
                 str(ROOT / "swift/BonsaiSwiftUI/Tests/AccessibilitySupport.swift"),
                 "-o", str(executable)],
                cwd=ROOT, capture_output=True, text=True, timeout=60,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run(
                [str(executable)], cwd=ROOT, capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS: dynamic mixed columns", result.stdout)
            print(result.stdout.strip())


if __name__ == "__main__":
    unittest.main(verbosity=2)
