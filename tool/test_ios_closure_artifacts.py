"""Audit real iPhoneOS libraries, including foreign objects inside archives."""

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_ios_cross_compiler import OPAM_ROOT, ROOT, SWITCH


class ClosureArtifactTests(unittest.TestCase):
    def command(self, arguments, cwd):
        result = subprocess.run(list(map(str, arguments)), cwd=cwd, text=True,
                                capture_output=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def fixture(self, root):
        source = root / "source"
        source.mkdir()
        (source / "probe.ml").write_text("let value = 18\n")
        self.command(["opam", "exec", f"--root={OPAM_ROOT}", f"--switch={SWITCH}", "--",
                      "ocamlfind", "-toolchain", "ios", "ocamlopt", "-a", "-o", "probe.cmxa", "probe.ml"], source)
        library = root / "lib/runtime_probe"
        library.mkdir(parents=True)
        for name in ("probe.cmxa", "probe.a", "probe.cmi"):
            shutil.copyfile(source / name, library / name)
        (library / "META").write_text('version = "1.0"\narchive(native) = "probe.cmxa"\n')
        return source, library, self.write_lock(root, "runtime_probe")

    def write_lock(self, root, component):
        row = f"{component}|1.0|target-package|Pure_ocaml|dune|https://example.invalid/probe.tar.gz|" + "0" * 64 + f"|{component}|-\n"
        lock = root / "closure.lock"
        lock.write_text(
            "# metadata.format=bonsai-swiftui-ios-closure-v2\n# metadata.features=core\n"
            "# metadata.roots=runtime_probe\n# metadata.package-count=1\n"
            "# metadata.target-package-count=1\n# metadata.host-package-count=0\n"
            "# metadata.target-build-count=0\n# metadata.component-count=1\n"
            f"# metadata.digest={hashlib.sha256(row.encode()).hexdigest()}\n" + row
        )
        return lock

    def verify(self, root, lock):
        prefix = Path(self.command(["opam", "var", f"--root={OPAM_ROOT}", f"--switch={SWITCH}", "prefix"], root).strip())
        env = dict(os.environ, IPHONEOS_SWITCH=SWITCH, PATH=f"{prefix / 'bin'}:{os.environ['PATH']}")
        return subprocess.run(["sh", str(ROOT / "tool/ios/verify_runtime_closure.sh"),
                               "--lock", str(lock), "--target-lib", str(root / "lib")],
                              cwd=root, env=env, text=True, capture_output=True, timeout=120)

    def test_ios18_loose_objects_and_archives_are_accepted(self):
        with tempfile.TemporaryDirectory(prefix="bonsai closure accepted ") as directory:
            root = Path(directory)
            source, library, lock = self.fixture(root)
            shutil.copyfile(source / "probe.o", library / "probe.o")
            result = self.verify(root, lock)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_wrong_platform_or_minimum_inside_archive_is_rejected(self):
        for target, diagnostic in [("arm64-apple-ios15.0", "expected minimum version 18.0"),
                                   ("arm64-apple-macos26.0", "expected platform IOS")]:
            with self.subTest(target=target), tempfile.TemporaryDirectory(prefix="bonsai closure rejected ") as directory:
                root = Path(directory)
                source, library, lock = self.fixture(root)
                (source / "foreign.c").write_text("int foreign_value(void) { return 1; }\n")
                self.command(["xcrun", "clang", "-target", target, "-c", "foreign.c", "-o", "foreign.o"], source)
                self.command(["xcrun", "ar", "-rcs", library / "libforeign.a", "foreign.o"], source)
                result = self.verify(root, lock)
                self.assertNotEqual(result.returncode, 0, "Invalid archive was accepted")
                self.assertIn(diagnostic, result.stdout + result.stderr)

    def test_missing_declared_native_artifact_is_rejected(self):
        for name in ("probe.cmxa", "probe.a"):
            with self.subTest(name=name), tempfile.TemporaryDirectory(prefix="bonsai closure missing ") as directory:
                root = Path(directory)
                source, library, lock = self.fixture(root)
                (library / name).unlink()
                result = self.verify(root, lock)
                self.assertNotEqual(result.returncode, 0, f"Missing {name} was accepted")
                self.assertIn("missing target native", result.stdout + result.stderr)

    def test_interface_only_virtual_library_is_accepted(self):
        with tempfile.TemporaryDirectory(prefix="bonsai virtual interface ") as directory:
            root = Path(directory)
            shutil.copytree(Path(SWITCH) / "_opam/ios-sysroot/lib/digestif", root / "lib/digestif")
            result = self.verify(root, self.write_lock(root, "digestif"))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_one_concrete_virtual_module_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="bonsai virtual module ") as directory:
            root = Path(directory)
            library = root / "lib/datascript_ocaml"
            shutil.copytree(Path(SWITCH) / "_opam/ios-sysroot/lib/datascript_ocaml", library)
            (library / "datascript__Query.cmx").unlink()
            result = self.verify(root, self.write_lock(root, "datascript_ocaml"))
            self.assertNotEqual(result.returncode, 0, "A missing concrete virtual module was accepted")
            self.assertIn("datascript__Query.cmx", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
