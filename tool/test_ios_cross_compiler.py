"""Verify the real OCaml cross-compiler and C runtime for iOS arm64 targets."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
OPAM_ROOT = os.environ.get("IOS_CROSS_TEST_OPAMROOT", str(ROOT / "_build/ios/opam-root"))
SWITCH = os.environ.get("IOS_CROSS_TEST_SWITCH", str(ROOT / "_build/ios/switches/iphoneos"))
PLATFORM = os.environ.get("IOS_CROSS_TEST_PLATFORM", "IOS")
CFLAGS_EXPECT = os.environ.get("IOS_CROSS_TEST_CFLAGS_EXPECT",
                               "-miphoneos-version-min=26.0")


class CrossCompilerTests(unittest.TestCase):
    def command(self, *arguments, cwd=ROOT):
        result = subprocess.run(list(map(str, arguments)), cwd=cwd, text=True,
                                capture_output=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def cross(self, *arguments, cwd=ROOT):
        return self.command("opam", "exec", f"--root={OPAM_ROOT}", f"--switch={SWITCH}",
                            "--", "ocamlfind", "-toolchain", "ios", *arguments, cwd=cwd)

    def verify(self, artifact):
        self.command("sh", ROOT / "tool/ios/verify_macho.sh", artifact,
                     PLATFORM, "arm64", "26.0")

    def test_actual_compiler_configuration(self):
        configuration = self.cross("ocamlopt", "-config")
        self.assertIn("version: 5.1.1", configuration)
        self.assertIn("architecture: arm64", configuration)
        for key in ("ocamlc_cflags", "ocamlopt_cflags"):
            line = next(line for line in configuration.splitlines() if line.startswith(key + ":"))
            self.assertIn(CFLAGS_EXPECT, line)
            self.assertNotIn("MacOSX", line)

    def test_foreign_stub_and_complete_object(self):
        with tempfile.TemporaryDirectory(prefix="bonsai ios26 compiler ") as directory:
            work = Path(directory)
            (work / "probe.ml").write_text(
                'external native_value : unit -> int = "bonsai_ios26_probe"\n'
                'let () = Callback.register "bonsai_swiftui_compiler_probe" native_value\n'
            )
            (work / "probe_stubs.c").write_text(
                '#include <caml/mlvalues.h>\n'
                'CAMLprim value bonsai_ios26_probe(value unit) { (void)unit; return Val_int(18); }\n'
            )
            self.cross("ocamlopt", "-c", "probe_stubs.c", cwd=work)
            self.verify(work / "probe_stubs.o")
            self.cross("ocamlopt", "-output-complete-obj", "-o", "probe.o",
                       "probe_stubs.o", "probe.ml", cwd=work)
            self.verify(work / "probe.o")
            symbols = self.command("xcrun", "nm", "-g", work / "probe.o")
            self.assertIn("_caml_startup_exn", symbols)
            self.assertIn("_bonsai_ios26_probe", symbols)

    def test_installed_native_runtime_object(self):
        prefix = Path(self.command("opam", "var", f"--root={OPAM_ROOT}",
                                   f"--switch={SWITCH}", "prefix").strip())
        archive = prefix / "ios-sysroot/lib/ocaml/libasmrun.a"
        with tempfile.TemporaryDirectory(prefix="bonsai ios26 runtime ") as directory:
            work = Path(directory)
            self.command("xcrun", "ar", "-x", archive, "alloc.n.o", cwd=work)
            self.verify(work / "alloc.n.o")

    def test_unsupported_target_rejected_before_setup(self):
        result = subprocess.run(["sh", str(ROOT / "tool/ios/setup_toolchain.sh"), "iphonesimulator"],
                                cwd=ROOT, text=True, capture_output=True, timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected host, iphoneos, iossimulator, or all", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
