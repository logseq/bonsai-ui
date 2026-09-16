"""Check the consumable opam repository and source archive as release artifacts."""

import hashlib
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PACKAGER = ROOT / "tool/package_opam_release.py"
PACKAGES = ("bonsai_swiftui", "bonsai_swiftui_test", "bonsai_swiftui_tool")


class OpamReleaseTests(unittest.TestCase):
    def package(self, output, *args):
        result = subprocess.run([sys.executable, str(PACKAGER), str(output), *args],
                                cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return next(output.glob("*.tar.gz"))

    def test_local_repository_has_verifiable_complete_sources(self):
        with tempfile.TemporaryDirectory(prefix="opam release ") as directory:
            output = Path(directory) / "release"
            archive = self.package(output)
            digest = hashlib.sha256(archive.read_bytes()).hexdigest()
            for name in PACKAGES:
                manifest = next((output / "repository/packages" / name).glob("*/opam"))
                self.assertIn(archive.resolve().as_uri(), manifest.read_text())
                self.assertIn("sha256=" + digest, manifest.read_text())
                result = subprocess.run(["opam", "lint", str(manifest)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            with tarfile.open(archive) as source:
                paths = {"/".join(p.split("/")[1:]) for p in source.getnames()}
                for path in ("ocaml/ui/theme.ml", "bonsai_swiftui.opam",
                             "bonsai_swiftui_tool.opam", "native/src/bonsai_swiftui_native.c",
                             "swift/BonsaiSwiftUI/Sources/UIDefaultValues.swift",
                             "tool/swiftui_xcode_host.py", "dune-project", "Package.swift"):
                    self.assertIn(path, paths)
                self.assertFalse(any(p.startswith(("_build/", ".git/", ".build/")) for p in paths))
            # Identical sources must produce identical archives, even at another location.
            other = self.package(Path(directory) / "other")
            self.assertEqual(archive.read_bytes(), other.read_bytes())

    def test_publisher_can_supply_the_download_url(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "release"
            url = "https://example.org/releases/framework.tar.gz"
            self.package(output, "--archive-url", url)
            for manifest in (output / "repository/packages").glob("*/*/opam"):
                self.assertIn(url, manifest.read_text())
                self.assertNotIn(output.as_uri(), manifest.read_text())

    def test_existing_output_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            marker = output / "keep.txt"
            marker.write_text("keep")
            result = subprocess.run([sys.executable, str(PACKAGER), str(output)],
                                    capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("already exists", result.stderr)
            self.assertEqual(marker.read_text(), "keep")
            self.assertEqual(list(output.iterdir()), [marker])


if __name__ == "__main__":
    unittest.main(verbosity=2)
