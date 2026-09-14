"""Verify the cross-built virtual library consumed by native Datascript."""

from pathlib import Path
import subprocess
import unittest

from test_ios_cross_compiler import ROOT, SWITCH


class VirtualLibraryTests(unittest.TestCase):
    def test_all_concrete_virtual_modules_have_ios18_native_artifacts(self):
        prefix = Path(SWITCH) / "_opam"
        host = prefix / "lib/datascript_ocaml"
        target = prefix / "ios-sysroot/lib/datascript_ocaml"
        expected = sorted(path.name for path in host.iterdir() if path.suffix in (".cmx", ".o"))
        self.assertTrue(expected, "The installed virtual library has no native module inventory")
        missing = [name for name in expected if not (target / name).is_file()]
        self.assertEqual(missing, [], "The target virtual library is missing concrete native modules")
        for name in expected:
            if name.endswith(".o"):
                result = subprocess.run(
                    ["sh", str(ROOT / "tool/ios/verify_macho.sh"), str(target / name), "IOS", "arm64", "18.0"],
                    text=True, capture_output=True, timeout=30,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
