"""Exercise SDK generation across real Git metadata and filesystem boundaries."""

import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT)


class SdkRepositoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="swiftui-sdk-repository-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.ios = self.root / "tool/ios"
        shutil.copytree(ROOT / "tool/ios", self.ios,
                        ignore=shutil.ignore_patterns("opam-repository", "fixtures"))
        shutil.copytree(ROOT / "vendor", self.root / "vendor")
        self.output = self.ios / "opam-repository/0.1.0"
        for args in [("init", "-q"), ("config", "user.email", "sdk@example.test"),
                     ("config", "user.name", "SDK fixture")]:
            self.assertEqual(run("git", *args, cwd=self.root).returncode, 0)
        self.package = self.root / "bonsai_swiftui.opam"
        self.locked_opam = (ROOT / "bonsai_swiftui.opam").read_text()
        self.package.write_text(self.locked_opam)
        run("git", "add", "bonsai_swiftui.opam", cwd=self.root)
        self.assertEqual(run("git", "commit", "-qm", "Locked source", cwd=self.root).returncode, 0)
        self.revision = run("git", "rev-parse", "HEAD", cwd=self.root).stdout.strip()
        self.package.write_text(self.locked_opam.replace("native SwiftUI backend", "later HEAD"))
        run("git", "commit", "-qam", "Later source", cwd=self.root)
        self.package.write_text("uncommitted package metadata must not be published\n")

        default = self.root / "default-input"
        default.mkdir()
        versions = {"base-bigarray": "base", "base-bytes": "base", "base-domains": "base",
                    "base-nnp": "base", "base-threads": "base", "base-unix": "base",
                    "conf-sqlite3": "1", "dune": "3.23.1", "dune-build-info": "3.23.1",
                    "melange": "5.1.0-51", "ocaml": "5.1.1", "ocaml-base-compiler": "5.1.1",
                    "ocaml-config": "3", "ocaml-options-vanilla": "1", "ocamlfind": "1.9.8",
                    "seq": "base", "fixture-dependency": "1"}
        for name, version in versions.items():
            directory = default / "packages" / name / f"{name}.{version}"
            directory.mkdir(parents=True)
            (directory / "opam").write_text('opam-version: "2.0"\n')
        for args in [("init", "-q"), ("config", "user.email", "sdk@example.test"),
                     ("config", "user.name", "SDK fixture"), ("add", "."),
                     ("commit", "-qm", "Pinned dependency fixture")]:
            self.assertEqual(run("git", *args, cwd=default).returncode, 0)
        default_revision = run("git", "rev-parse", "HEAD", cwd=default).stdout.strip()
        cross = ROOT / "_build/ios/sources/opam-cross-ios"
        self.assertTrue((cross / ".git").is_dir(), "Prepare the locked iOS toolchain first")
        lock = self.ios / "sdk_repository.lock"
        text = lock.read_text()
        for name, value in {"BONSAI_SWIFTUI_SOURCE_REVISION": self.revision,
                            "DEFAULT_REPOSITORY_URL": str(default),
                            "DEFAULT_REPOSITORY_COMMIT": default_revision}.items():
            text = re.sub(rf"^{name}=.*$", f"{name}='{value}'", text, flags=re.M)
        lock.write_text(text)
        toolchain = self.ios / "toolchain.lock"
        toolchain.write_text(re.sub(r"^OPAM_CROSS_IOS_REPOSITORY=.*$",
                                   f"OPAM_CROSS_IOS_REPOSITORY='{cross}'",
                                   toolchain.read_text(), flags=re.M))
        closure = self.root / "vendor/opam-ios/supported-closure.lock"
        closure.write_text("# metadata.features=core\n# metadata.roots=fixture-dependency\n"
                           "fixture-dependency|1|host-package|Host_only|opam|https://example.test/dep.tar.gz|"
                           + "a" * 64 + "|-|-\n")

    def generate(self, mode="--write"):
        return run("sh", str(self.ios / "regenerate_sdk_repository.sh"), mode, cwd=self.root)

    def tree(self):
        return {str(p.relative_to(self.output)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in self.output.rglob("*") if p.is_file()}

    def test_bootstrap_uses_locked_metadata_and_replaces_obsolete_output(self):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stdout)
        framework = self.output / "packages/bonsai_swiftui/bonsai_swiftui.0.1.0~dev"
        self.assertEqual((framework / "opam").read_text(), self.locked_opam)
        self.assertIn(self.revision, (framework / "url").read_text())
        sdk = next((self.output / "packages/bonsai_swiftui_ios_sdk").glob("*/files"))
        self.assertIn("(minimum_deployment_target 18.0)", (sdk / "manifest.sexp").read_text())
        self.assertIn("18.0", (sdk / "build-installed-framework.sh").read_text())
        compiler = self.output / "packages/ocaml-ios64/ocaml-ios64.5.1.1"
        self.assertIn("physical iOS arm64", (compiler / "opam").read_text())
        conf = self.output / "packages/conf-ios/conf-ios.4/opam"
        self.assertIn("-miphoneos-version-min=18.0", conf.read_text())
        universe = (self.output / "package-universe.lock").read_text()
        self.assertIn("bonsai_swiftui|0.1.0~dev|local|", universe)
        self.assertIn("conf-ios|4|local|", universe)
        self.assertIn("conf-pkg-config|5|local|", universe)
        baseline = self.tree()
        self.assertEqual(self.generate("--check").returncode, 0)
        self.assertEqual(self.tree(), baseline)
        obsolete = self.output / "packages/obsolete-package/obsolete-package.1/opam"
        obsolete.parent.mkdir(parents=True)
        obsolete.write_text('opam-version: "2.0"\n')
        self.assertNotEqual(self.generate("--check").returncode, 0)
        self.assertTrue(obsolete.exists(), "--check must not mutate output")
        self.assertEqual(self.generate().returncode, 0)
        self.assertEqual(self.tree(), baseline)

    def test_missing_locked_swiftui_metadata_preserves_existing_output(self):
        self.output.mkdir(parents=True)
        (self.output / "sentinel").write_text("preserve until generation succeeds")
        run("git", "rm", "-f", "bonsai_swiftui.opam", cwd=self.root)
        run("git", "commit", "-qm", "Missing framework package", cwd=self.root)
        missing = run("git", "rev-parse", "HEAD", cwd=self.root).stdout.strip()
        lock = self.ios / "sdk_repository.lock"
        lock.write_text(lock.read_text().replace(self.revision, missing))
        before = self.tree()
        result = self.generate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("locked source lacks bonsai_swiftui.opam", result.stdout)
        self.assertEqual(self.tree(), before)


if __name__ == "__main__":
    unittest.main()
