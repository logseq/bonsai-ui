"""Check process-API isolation in actual macOS/iOS native objects."""

import os
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = {"_fork", "_execv", "_execve", "_execvp", "_posix_spawn", "_posix_spawnp",
             "_popen", "_system"}
TARGET = "native/test/datascript_worker/datascript_worker_native_embed.exe.o"


class ProcessIsolationTests(unittest.TestCase):
    def test_physical_ios_complete_object_has_no_process_imports(self):
        env = dict(os.environ, OPAMROOT=str(ROOT / "_build/ios/opam-root"), VER="18.0",
                   SDK=subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], text=True).strip())
        env.pop("OCAMLPATH", None)
        subprocess.run([
            "opam", "exec", f"--switch={ROOT / '_build/ios/switches/iphoneos'}", "--",
            "dune", "build", f"--build-dir={ROOT / '_build/ios/swiftui-framework'}",
            "--profile=release", "-j4", "-xios", TARGET,
        ], env=env, cwd=ROOT, check=True)
        path = ROOT / "_build/ios/swiftui-framework/default.ios" / TARGET
        imports = set(subprocess.check_output(["nm", "-uj", path], text=True).split())
        self.assertEqual(imports & FORBIDDEN, set(), "iOS still imports process creation from libSystem")

    def test_macos_does_not_override_native_process_apis(self):
        subprocess.run(["dune", "build", TARGET], cwd=ROOT, check=True)
        path = ROOT / "_build/default" / TARGET
        defined = set(subprocess.check_output(["nm", "-gUj", path], text=True).split())
        self.assertEqual(defined & FORBIDDEN, set(), "iOS process overrides leaked into macOS")


if __name__ == "__main__":
    unittest.main(verbosity=2)
