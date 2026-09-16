"""Build an independent iOS App with installed opam libraries, CLI and SDK."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class InstalledIOSSDKTests(unittest.TestCase):
    def test_zarith_links_using_installed_archives(self):
        environment = {name: value for name, value in os.environ.items()
                       if name not in ("BONSAI_SWIFTUI_SOURCE_ROOT", "OCAMLPATH")}
        with tempfile.TemporaryDirectory(prefix="Bonsai installed arithmetic ") as directory:
            project = Path(directory)
            (project / "probe.ml").write_text(
                'let () = Callback.register "sdk_arithmetic" '
                '(fun () -> Z.to_string (Z.mul (Z.of_int 17) (Z.of_int 19)))\n')
            result = subprocess.run(
                ["opam", "exec", "--switch=bonsai-swiftui-ios", "--", "ocamlfind", "-toolchain", "ios",
                 "ocamlopt", "-package", "zarith", "-linkpkg", "-output-complete-obj",
                 "-o", "probe.o", "probe.ml"], cwd=project, env=environment,
                capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((project / "probe.o").is_file())

    def test_external_app_builds_without_source_or_prebuilt_object(self):
        environment = {name: value for name, value in os.environ.items()
                       if name not in ("BONSAI_SWIFTUI_SOURCE_ROOT", "OCAMLPATH")}
        with tempfile.TemporaryDirectory(prefix="Bonsai installed iOS ") as directory:
            project = Path(directory)

            def cli(*arguments):
                result = subprocess.run(["opam", "exec", "--", "bonsai-swiftui", *arguments],
                                        cwd=project, env=environment, capture_output=True,
                                        text=True, timeout=1800)
                self.assertEqual(result.returncode, 0, (result.stdout + result.stderr)[-20000:])
                return result

            cli("toolchain", "verify", "iphoneos")
            cli("init", "--name", "sdk_check", "--bundle-identifier", "org.example.sdkcheck")
            cli("build", "ios", "--profile", "release", "--no-codesign")
            bundles = list((project / "apple/DerivedData/Build/Products/Release-iphoneos").glob("*.app"))
            self.assertEqual(len(bundles), 1)
            info = subprocess.run(["plutil", "-extract", "DTPlatformName", "raw", "-o", "-",
                                   str(bundles[0] / "Info.plist")], capture_output=True, text=True)
            self.assertEqual(info.returncode, 0, info.stderr)
            self.assertEqual(info.stdout.strip(), "iphoneos")
            xcode = next(project.glob("apple/*.xcodeproj/project.pbxproj")).read_text()
            self.assertIn("share/bonsai_swiftui_tool/framework", xcode)
            self.assertNotIn(str(Path(__file__).resolve().parents[1]), xcode)


if __name__ == "__main__":
    unittest.main(verbosity=2)
