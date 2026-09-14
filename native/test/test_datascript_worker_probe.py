"""Exercise the real DataScript Worker probe across independent native processes."""

from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "_build/validation/datascript-worker-probe"
TARGET = "native/test/datascript_worker/datascript_worker_native_embed.exe.o"


class DataScriptWorkerProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        BUILD.mkdir(parents=True, exist_ok=True)
        subprocess.run(["dune", "build", TARGET], cwd=ROOT, check=True)
        subprocess.run([
            "python3", "tool/link_swiftui_runtime.py", ROOT / "_build/default" / TARGET,
            BUILD / "runtime.complete.o", "--dylib", BUILD / "libprobe.dylib",
        ], cwd=ROOT, check=True)
        runner = BUILD / "Runner.swift"
        runner.write_text(r'''import Foundation
@main enum Runner {
  static func main() async {
    do {
      _ = try await DataScriptWorkerProbe.run(
        directory: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true),
        timeout: .seconds(2))
    } catch {
      DataScriptWorkerProbe.marker("BONSAI_DATASCRIPT_PROBE_FAILED: \(error)")
      exit(1)
    }
  }
}
''')
        subprocess.run([
            "xcrun", "swiftc", "-emit-module", "-emit-library", "-parse-as-library",
            "-module-name", "BonsaiSwiftUI", "-emit-module-path", BUILD / "BonsaiSwiftUI.swiftmodule",
            "-target", "arm64-apple-macos26.0", "-I", ROOT / "native/src",
            "-L", BUILD, "-lprobe", "-Xlinker", "-rpath", "-Xlinker", BUILD,
            ROOT / "swift/BonsaiSwiftUI/Sources/GeneratedProtocol.swift",
            ROOT / "swift/BonsaiSwiftUI/Sources/NativeRuntime.swift",
            "-o", BUILD / "libBonsaiSwiftUI.dylib",
        ], check=True, cwd=ROOT)
        subprocess.run([
            "xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0",
            "-I", ROOT / "native/src", "-I", BUILD, "-L", BUILD, "-lBonsaiSwiftUI",
            "-Xlinker", "-rpath", "-Xlinker", BUILD,
            ROOT / "tool/ios/fixtures/datascript-worker-host/swift/Probe.swift",
            ROOT / "examples/sqlite_worker/swift/Startup.swift", runner,
            "-o", BUILD / "Runner",
        ], check=True, cwd=ROOT)

    def run_probe(self, directory):
        return subprocess.run([str(BUILD / "Runner"), str(directory)],
                              capture_output=True, text=True, timeout=15)

    def test_persists_restores_and_closes_across_processes(self):
        with tempfile.TemporaryDirectory(prefix="DataScript 本地-") as temporary:
            directory = Path(temporary)
            for phase in ["persisted", "restored"]:
                for name in ["probe-ready", "probe-closed"]:
                    (directory / name).write_text("stale result")
                result = self.run_probe(directory)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue((directory / "probe-ready").is_file(), result.stdout + result.stderr)
                self.assertEqual((directory / "probe-ready").read_text(), phase)
                self.assertEqual((directory / "probe-closed").read_text(), "closed")
                for marker in [f"BONSAI_DATASCRIPT_WORKER_{phase.upper()}",
                               "BONSAI_DERIVING_YOJSON_ROUND_TRIP", "BONSAI_RRBVEC_PROBE_PASSED",
                               "BONSAI_DATASCRIPT_WORKER_SHUTDOWN"]:
                    self.assertIn(marker, result.stdout + result.stderr)
                for marker in ["BONSAI_DATASCRIPT_HOST_RUNTIME_STARTED",
                               "BONSAI_DATASCRIPT_HOST_RUNTIME_DISPOSED",
                               "BONSAI_DATASCRIPT_PROBE_PASSED"]:
                    self.assertEqual((result.stdout + result.stderr).count(marker), 1)

    def test_corrupt_database_never_reports_readiness(self):
        with tempfile.TemporaryDirectory(prefix="DataScript corrupt-") as temporary:
            directory = Path(temporary)
            (directory / "datascript-worker-probe.sqlite3").write_bytes(b"invalid SQLite database" * 400)
            result = self.run_probe(directory)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertFalse((directory / "probe-ready").exists(), result.stdout + result.stderr)
            self.assertNotIn("BONSAI_DATASCRIPT_WORKER_PERSISTED", result.stdout + result.stderr)
            self.assertNotIn("BONSAI_DATASCRIPT_WORKER_RESTORED", result.stdout + result.stderr)
            self.assertNotIn("BONSAI_DATASCRIPT_PROBE_PASSED", result.stdout + result.stderr)
            self.assertEqual(
                (result.stdout + result.stderr).count("BONSAI_DATASCRIPT_HOST_RUNTIME_DISPOSED"),
                (result.stdout + result.stderr).count("BONSAI_DATASCRIPT_HOST_RUNTIME_STARTED"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
