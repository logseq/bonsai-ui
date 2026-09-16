"""Install release archives with opam, then exercise an independent native App.

On macOS, clone the active dependency switch with APFS copy-on-write. The original
switch is never modified. This tests real package installation, not provisioning
all third-party dependencies on a clean machine.
"""

import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import test_swiftui_cli as consumer


@unittest.skipUnless(sys.platform == "darwin", "Native SwiftUI requires macOS")
class OpamConsumerTests(unittest.TestCase):
    def test_opam_install_builds_and_runs_external_application(self):
        def run(arguments, **kwargs):
            result = subprocess.run(arguments, capture_output=True, text=True, **kwargs)
            if result.returncode:
                print((result.stdout + result.stderr)[-16000:], flush=True)
            self.assertEqual(result.returncode, 0, (result.stdout + result.stderr)[-16000:])
            return result.stdout.strip()

        root = Path(run(["opam", "var", "root"]))
        prefix = Path(run(["opam", "var", "prefix"]))
        with tempfile.TemporaryDirectory(prefix="bonsai-opam-") as directory:
            workspace = Path(directory).resolve()
            release = workspace / "release"
            run([sys.executable, str(consumer.ROOT / "tool/package_opam_release.py"), str(release)])
            isolated = workspace / "opam"
            isolated.mkdir()
            # Clone only the active switch and repository metadata, not other switches.
            for name in ("config", "repo", "opam-init"):
                run(["cp", "-cR", str(root / name), str(isolated / name)])
            switch = "consumer"
            root_config = isolated / "config"
            text = re.sub(r"installed-switches: \[.*?\]", 'installed-switches: ["consumer"]',
                          root_config.read_text(), flags=re.DOTALL)
            text = re.sub(r'^switch: ".*"$', 'switch: "consumer"', text, flags=re.MULTILINE)
            root_config.write_text(text)
            installed = isolated / switch
            print("Cloning the dependency switch", flush=True)
            run(["cp", "-cR", str(prefix), str(installed)])
            # Compiler/findlib executables embed their original installation paths.
            # Relocate those paths in this copied fixture; real opam switches are
            # compiled for their own prefix and do not need these test overrides.
            findlib = installed / "lib/findlib.conf"
            findlib.write_text(findlib.read_text().replace(str(prefix), str(installed)))
            config = installed / ".opam-switch/switch-config"
            config.write_text(config.read_text().replace(str(root), str(isolated)))
            env = {key: value for key, value in os.environ.items()
                   if not key.startswith("BONSAI_SWIFTUI_")
                   and key not in ("OCAMLPATH", "CAML_LD_LIBRARY_PATH", "OCAMLLIB", "OPAM_SWITCH_PREFIX")}
            env.update(OPAMROOT=str(isolated), OPAMSWITCH=switch,
                       OCAMLFIND_CONF=str(findlib), OCAMLLIB=str(installed / "lib/ocaml"))
            run(["opam", "repository", "add", "bonsai-consumer", str(release / "repository"),
                 "--this-switch", "--yes"], env=env)
            packages = ["bonsai_swiftui", "bonsai_swiftui_test", "bonsai_swiftui_tool"]
            # A repeated acceptance run must still build the new source archive.
            run(["opam", "remove", "--yes", *packages], env=env)
            print("Installing release packages with opam", flush=True)
            run(["opam", "install", "--yes", *packages], env=env)
            print("Building and running the independent App", flush=True)
            actual_env = json.loads(run(["opam", "exec", "--", sys.executable, "-c",
                                        "import json,os; print(json.dumps(dict(os.environ)))"], env=env))
            self.assertNotIn("BONSAI_SWIFTUI_SOURCE_ROOT", actual_env)
            self.assertFalse(actual_env.get("OCAMLPATH"))
            query = run(["ocamlfind", "query", "bonsai_swiftui.ui"], env=actual_env)
            self.assertTrue(Path(query).is_relative_to(installed), query)
            for package in packages:
                build = installed / ".opam-switch/build" / (package + ".0.1.0~dev")
                if build.exists():
                    shutil.rmtree(build)
            shutil.rmtree(release)
            scenario = consumer.SwiftUICliTests("test_external_application_builds_and_runs_real_ocaml")
            scenario.setUp()
            self.addCleanup(scenario.tearDown)
            original_cli = consumer.CLI
            self.addCleanup(setattr, consumer, "CLI", original_cli)
            consumer.CLI = installed / "bin/bonsai-swiftui"
            scenario.env = actual_env
            scenario.test_external_application_builds_and_runs_real_ocaml()
            project = scenario.project / "apple/BonsaiJournal.xcodeproj/project.pbxproj"
            self.assertNotIn(str(consumer.ROOT), project.read_text())
            self.assertIn("share/bonsai_swiftui_tool/framework", project.read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
