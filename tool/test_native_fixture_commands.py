"""Verify the public Make fixture commands select the native generators."""

from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


class NativeFixtureCommandTests(unittest.TestCase):
    def test_make_uses_swift_for_generation_and_verification(self):
        for target, check in [("protocol-fixtures-generate", False),
                              ("protocol-fixtures-check", True)]:
            with self.subTest(target=target):
                result = subprocess.run(["make", "-n", target], cwd=ROOT,
                                        capture_output=True, text=True, check=True)
                self.assertNotIn("dart run", result.stdout)
                self.assertNotIn("flutter/", result.stdout)
                command = "python3 tool/generate_input_fixtures.py"
                if check:
                    command += " --check"
                self.assertIn(command, result.stdout.splitlines())
                self.assertIn("generate_fixtures.exe", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
