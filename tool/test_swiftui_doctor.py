"""Exercise CLI diagnostics against installed Apple tools without a Flutter host."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "_build/default/bonsai_swiftui_tool/bin/main.exe"


class NativeDoctorTests(unittest.TestCase):
    def run_doctor(self, *arguments, environment=None):
        with tempfile.TemporaryDirectory(prefix="bonsai-swiftui-doctor-") as directory:
            root = Path(directory)
            trap = root / "flutter"
            trap.write_text("#!/bin/sh\nprintf invoked > flutter-invoked\nexit 97\n")
            trap.chmod(0o755)
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}")
            env.update(environment or {})
            result = subprocess.run(
                [str(CLI), "doctor", *arguments], cwd=root, env=env,
                text=True, capture_output=True, timeout=60,
            )
            self.assertFalse((root / "flutter-invoked").exists(), "doctor invoked Flutter")
            self.assertEqual(sorted(path.name for path in root.iterdir()), ["flutter"])
            return result

    def test_native_toolchain_without_project_or_flutter(self):
        for arguments, sdk in [
            ([], "MacOSX"),
            (["--target", "macos"], "MacOSX"),
            (["--target", "iphoneos"], "iPhoneOS"),
        ]:
            with self.subTest(arguments=arguments):
                result = self.run_doctor(*arguments)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("ok opam", result.stdout)
                self.assertIn("ok dune", result.stdout)
                self.assertIn("Xcode", result.stdout)
                self.assertIn("Apple Swift version", result.stdout)
                self.assertIn(sdk, result.stdout)

    def test_invalid_xcode_selection_fails(self):
        result = self.run_doctor(environment={"DEVELOPER_DIR": "/nonexistent/bonsai-xcode"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("xcodebuild is unavailable", result.stderr)

    def test_simulator_is_not_a_target(self):
        result = self.run_doctor("--target", "iphonesimulator")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid value", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
