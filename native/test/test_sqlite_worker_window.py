"""Exercise SQLite and bounded file persistence across real SwiftUI app processes."""
from pathlib import Path
import os
import plistlib
import sqlite3
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SQLiteWorkerWindowTests(unittest.TestCase):
    def test_sqlite_worker_window(self):
        bundle = ROOT / "_build/validation/SQLiteWorkerWindowAcceptance.app"
        executable = bundle / "Contents/MacOS/SQLiteWorkerWindowAcceptance"
        executable.parent.mkdir(parents=True, exist_ok=True)
        (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.bonsai-swiftui.test.sqlite-worker-window",
            "CFBundleName": executable.name, "CFBundleExecutable": executable.name,
            "CFBundlePackageType": "APPL", "LSMinimumSystemVersion": "26.0", "LSUIElement": True,
        }))
        native = ROOT / "_build/default/native/test"
        sources = sorted((ROOT / "swift/BonsaiSwiftUI/Sources").glob("*.swift"))
        build = subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0",
            "-I", str(ROOT / "native/src"), "-L", str(native), "-lruntime_fixture",
            "-Xlinker", "-rpath", "-Xlinker", str(native), *map(str, sources),
            str(ROOT / "swift/BonsaiSwiftUI/Tests/AccessibilitySupport.swift"),
            str(ROOT / "examples/sqlite_worker/swift/Startup.swift"),
            str(ROOT / "native/test/sqlite_worker_window.swift"), "-o", str(executable)],
            cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
        with tempfile.TemporaryDirectory(prefix="SQLite 本地-") as temporary:
            directory = Path(temporary) / "Application Support" / "SQLite 本地"
            database = directory / "todos.sqlite3"
            for phase in ["write", "reopen"]:
                environment = dict(os.environ, BONSAI_SQLITE_DIRECTORY=str(directory), BONSAI_SQLITE_PHASE=phase)
                result = subprocess.run([str(executable)], cwd=ROOT, env=environment,
                                        capture_output=True, text=True, timeout=45)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("PASS: actual SQLite Worker window", result.stdout)
                print(result.stdout)
                with sqlite3.connect(database) as connection:
                    self.assertEqual(connection.execute("PRAGMA integrity_check").fetchone(), ("ok",))
                    self.assertEqual(connection.execute("SELECT title, completed FROM todos").fetchall(),
                                     [("Persisted 本地😀", int(phase == "write"))])
            content = (directory / "eio-worker-demo.bin").read_bytes()
            self.assertEqual(content, bytes(range(256)) * (4 * 1024 * 1024 // 256))
            self.assertEqual(list(directory.glob("eio-worker-demo.*.tmp")), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
