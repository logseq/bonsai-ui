"""Build an external App using the installed package layout and opam asset recipe.

This checks Dune installation and the declared opam install commands in an
isolated prefix. It does not change an opam switch or test dependency solving.
"""

import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest

import test_swiftui_cli as consumer


class InstalledSwiftUICliTests(unittest.TestCase):
    def test_installed_application_builds_and_runs_real_ocaml(self):
        scenario = consumer.SwiftUICliTests("test_external_application_builds_and_runs_real_ocaml")
        scenario.setUp()
        self.addCleanup(scenario.tearDown)
        original_cli = consumer.CLI
        self.addCleanup(setattr, consumer, "CLI", original_cli)
        with tempfile.TemporaryDirectory(prefix="Bonsai SwiftUI installed ") as directory:
            prefix = Path(directory)
            install = subprocess.run(
                ["dune", "install", "--prefix", str(prefix), "bonsai_swiftui",
                 "bonsai_swiftui_test", "bonsai_swiftui_tool"],
                cwd=consumer.ROOT, capture_output=True, text=True,
            )
            self.assertEqual(install.returncode, 0, install.stdout + install.stderr)
            self.assertTrue((prefix / "lib/bonsai_swiftui/spec/bonsai_swiftui_spec.cmi").is_file())
            recipe = subprocess.run(
                ["opam", "show", "--just-file", "./bonsai_swiftui_tool.opam",
                 "--field=install", "--normalise"],
                cwd=consumer.ROOT, capture_output=True, text=True,
            )
            self.assertEqual(recipe.returncode, 0, recipe.stdout + recipe.stderr)
            commands = re.findall(r"\[([^\[\]]+)\]", recipe.stdout)
            self.assertTrue(commands, "The tool package has no asset installation recipe")
            for command in commands:
                arguments = [a.replace("%{share}%", str(prefix / "share"))
                             for a in shlex.split(command)]
                self.assertFalse(any("%{" in a for a in arguments), arguments)
                subprocess.run(arguments, cwd=consumer.ROOT, check=True, capture_output=True)
            consumer.CLI = prefix / "bin/bonsai-swiftui"
            self.assertTrue(consumer.CLI.is_file())
            self.assertFalse(consumer.CLI.is_symlink())
            scenario.env.pop("BONSAI_SWIFTUI_SOURCE_ROOT", None)
            scenario.env["OCAMLPATH"] = str(prefix / "lib")
            scenario.test_external_application_builds_and_runs_real_ocaml()
            project = scenario.project / "apple/BonsaiJournal.xcodeproj/project.pbxproj"
            framework = prefix / "share/bonsai_swiftui_tool/framework"
            self.assertIn(os.path.relpath(framework, scenario.project / "apple"), project.read_text())
            self.assertNotIn(str(consumer.ROOT), project.read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
