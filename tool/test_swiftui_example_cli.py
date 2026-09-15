"""Build standalone example copies through the public CLI and run packaged Mail."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "_build/default/bonsai_swiftui_tool/bin/main.exe"
EXAMPLES = (
    "clock", "counter", "gallery", "host_effects", "host_navigation", "mail",
    "navigation", "network", "note", "sqlite_worker", "text_input", "todo",
)


class ExampleCliTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="Bonsai standalone examples ")
        self.root = Path(self.directory.name)
        self.environment = {**os.environ, "BONSAI_SWIFTUI_SOURCE_ROOT": str(ROOT)}
        self.environment["OCAMLPATH"] = str(ROOT / "_build/install/default/lib") + os.pathsep + self.environment.get("OCAMLPATH", "")

    def tearDown(self):
        self.directory.cleanup()

    def copy_example(self, name):
        source = ROOT / "examples" / name
        target = self.root / name
        target.mkdir()
        for path in source.iterdir():
            if path.name in ("ocaml", "swift", "apple-tests", "resources", "test", "apple-ui-tests"):
                shutil.copytree(path, target / path.name)
            elif path.is_file() and (path.name in ("dune-project", "bonsai-swiftui.sexp") or ".opam" in path.name):
                shutil.copyfile(path, target / path.name)
        return target

    def cli(self, project, *arguments):
        result = subprocess.run(
            [str(CLI), *map(str, arguments)], cwd=project, env=self.environment,
            capture_output=True, text=True, timeout=300,
        )
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr)[-16000:])
        return result.stdout

    def test_standalone_examples_build_native_and_preserve_sources(self):
        for name in EXAMPLES:
            with self.subTest(example=name):
                project = self.copy_example(name)
                sources = {path: path.read_bytes() for path in project.rglob("*") if path.is_file()}
                self.cli(project, "sync-host")
                self.cli(project / "ocaml", "sync-host", "--check")
                output = self.cli(project, "build-native", "--target", "macos", "--profile", "debug")
                artifacts = [line.removeprefix("native artifact: ") for line in output.splitlines() if line.startswith("native artifact: ")]
                self.assertEqual(len(artifacts), 1, output)
                self.assertGreater(Path(artifacts[0]).stat().st_size, 0)
                self.assertEqual(sources, {path: path.read_bytes() for path in sources})
                self.assertFalse((project / "flutter").exists())

    def test_mail_builds_and_executes_packaged_ocaml_test(self):
        project = self.copy_example("mail")
        self.cli(project, "build", "macos", "--profile", "debug")
        bundle = project / "apple/DerivedData/Build/Products/Debug/BonsaiMail.app"
        self.assertTrue((bundle / "Contents/MacOS/BonsaiMail").is_file())
        output = self.cli(
            project / "ocaml", "exec", "--profile", "debug", "--",
            "xcodebuild", "-project", project / "apple/BonsaiMail.xcodeproj",
            "-scheme", "BonsaiMail-macOS", "-configuration", "Debug",
            "-destination", "platform=macOS,arch=arm64", "-derivedDataPath",
            project / "apple/DerivedData", "test",
        )
        self.assertRegex(output, r"testPackagedMailStartsPresentsAndRestarts.*passed")
        self.assertIn("** TEST SUCCEEDED **", output)

    def test_gallery_builds_as_a_standalone_native_host(self):
        project = self.copy_example("gallery")
        self.cli(project, "sync-host")
        self.cli(project / "ocaml", "sync-host", "--check")
        self.cli(project, "build", "macos", "--profile", "debug")
        bundle = project / "apple/DerivedData/Build/Products/Debug/BonsaiGallery.app"
        self.assertTrue((bundle / "Contents/MacOS/BonsaiGallery").is_file())
        for resource in ["gallery-demo.png", "gallery-animation.gif"]:
            self.assertEqual((bundle / "Contents/Resources" / resource).read_bytes(),
                             (project / "resources" / resource).read_bytes())
        self.assertFalse((project / "flutter").exists())
        self.cli(project, "sync-host", "--check")

    def test_note_packages_its_cover_and_runs_the_actual_ocaml_application(self):
        project = self.copy_example("note")
        self.cli(project, "build", "macos", "--profile", "debug")
        bundle = project / "apple/DerivedData/Build/Products/Debug/BonsaiNote.app"
        self.assertEqual((bundle / "Contents/Resources/typewriter.png").read_bytes(),
                         (project / "resources/typewriter.png").read_bytes())
        self.cli(project, "sync-host", "--check")
        output = self.cli(
            project, "exec", "--profile", "debug", "--",
            "xcodebuild", "-project", project / "apple/BonsaiNote.xcodeproj",
            "-scheme", "BonsaiNote-macOS", "-configuration", "Debug",
            "-destination", "platform=macOS,arch=arm64", "-derivedDataPath",
            project / "apple/DerivedData", "test",
        )
        self.assertRegex(output, r"testPackagedNoteStartsPresentsAndRestarts.*passed")
        self.assertIn("** TEST SUCCEEDED **", output)


if __name__ == "__main__":
    unittest.main(verbosity=2)
