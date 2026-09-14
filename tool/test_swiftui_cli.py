"""Exercise native CLI ownership, real external builds, launch and child processes."""

from pathlib import Path
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "_build/default/bonsai_swiftui_tool/bin/main.exe"


class SwiftUICliTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="Bonsai SwiftUI CLI ")
        self.project = Path(self.directory.name)
        self.env = {**os.environ, "BONSAI_SWIFTUI_SOURCE_ROOT": str(ROOT)}
        self.env["OCAMLPATH"] = str(ROOT / "_build/install/default/lib") + os.pathsep + self.env.get("OCAMLPATH", "")

    def tearDown(self):
        self.directory.cleanup()

    def cli(self, *arguments, success=True, timeout=300):
        result = subprocess.run([str(CLI), *map(str, arguments)], cwd=self.project,
                                env=self.env, capture_output=True, text=True, timeout=timeout)
        if success:
            self.assertEqual(result.returncode, 0, (result.stdout + result.stderr)[-12000:])
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def initialize(self):
        self.cli("init", "--name", "journal", "--bundle-identifier", "org.example.journal")

    def test_framework_is_available_under_its_swiftui_package_names(self):
        for package in ("bonsai_swiftui", "bonsai_swiftui.ui", "bonsai_swiftui.driver",
                        "bonsai_swiftui.spec_impl", "bonsai_swiftui_test"):
            with self.subTest(package=package):
                result = subprocess.run(
                    ["ocamlfind", "query", package], cwd=self.project, env=self.env,
                    capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue(Path(result.stdout.strip()).is_dir())

    def test_native_initialization_and_generated_host_ownership(self):
        self.initialize()
        config = self.project / "bonsai-swiftui.sexp"
        self.assertTrue(config.is_file())
        self.assertIn("(minimum_version 18.0)", config.read_text())
        self.assertFalse((self.project / "bonsai-flutter.sexp").exists())
        self.assertFalse((self.project / "flutter").exists())
        self.assertFalse(list(self.project.rglob("*.dart")))
        self.assertFalse(list(self.project.rglob("pubspec*")))
        sources = [self.project / "swift/App.swift", self.project / "app/application.ml",
                   self.project / "app/dune"]
        for path in sources:
            self.assertTrue(path.is_file(), path)
        sources[0].write_text(sources[0].read_text() + "\n// Application-owned change.\n")
        sources[1].write_text(sources[1].read_text() + "\n(* Application-owned change. *)\n")
        sources[2].write_text(sources[2].read_text() + "\n; Application-owned change.\n")
        before = {p: p.read_bytes() for p in sources}
        self.cli("init", "--adopt")
        self.assertEqual(before, {p: p.read_bytes() for p in sources})
        self.cli("sync-host", "--check")
        project = self.project / "apple/BonsaiJournal.xcodeproj/project.pbxproj"
        expected = project.read_bytes()
        project.write_text("deliberate generated-project drift\n")
        self.cli("sync-host", "--check", success=False)
        self.assertEqual(project.read_text(), "deliberate generated-project drift\n")
        self.cli("sync-host")
        self.assertEqual(project.read_bytes(), expected)
        self.assertEqual(before, {p: p.read_bytes() for p in sources})

    def test_invalid_configuration_is_rejected_before_creation(self):
        for arguments in [
            ["--name", "../unsafe"],
            ["--name", "journal", "--ios-deployment-target", "15.0"],
            ["--name", "journal", "--macos-minimum-version", "15.0"],
            ["--name", "journal", "--bundle-identifier", "invalid identifier"],
        ]:
            with self.subTest(arguments=arguments):
                self.cli("init", *arguments, success=False)
                self.assertEqual(list(self.project.iterdir()), [])
        self.initialize()
        config = self.project / "bonsai-swiftui.sexp"
        original = config.read_text()
        config.write_text(original.replace("(lang 3)", "(lang 2)"))
        result = self.cli("build-native", "--target", "macos", success=False)
        self.assertIn("Unsupported schema version", result.stdout + result.stderr)
        config.write_text(original.replace("(apple_root apple)", "(flutter_root flutter)"))
        result = self.cli("sync-host", success=False)
        self.assertIn("Unknown app field", result.stdout + result.stderr)
        config.write_text(original)
        self.cli("build", "simulator", success=False)
        self.cli("run", "ios", success=False)
        self.assertFalse((self.project / "_build").exists())

    def test_external_application_builds_and_runs_real_ocaml(self):
        self.initialize()
        # Application-owned Swift sources can extend the generated host. The
        # native button must update the generated OCaml counter before exit.
        support = (ROOT / "swift/BonsaiSwiftUI/Tests/AccessibilitySupport.swift").read_text()
        (self.project / "swift/Acceptance.swift").write_text("#if os(macOS)\n" + support + "\n#endif\n")
        (self.project / "swift/App.swift").write_text('''import BonsaiSwiftUI
import SwiftUI
#if os(macOS)
import AppKit
#endif
@main struct JournalApplication: App {
  var body: some Scene {
    WindowGroup {
      BonsaiApplicationView(entrypoint: "journal")
        .frame(minWidth: 320, minHeight: 240)
        #if os(macOS)
        .task { await verifyCounter() }
        #endif
    }
  }
}
#if os(macOS)
@MainActor func verifyCounter() async {
  do {
    guard let window = NSApp.windows.first(where: { $0.contentView != nil }),
      let view = window.contentView else { throw CocoaError(.coderInvalidValue) }
    func waitFor(_ text: String) async throws {
      for _ in 0..<100 {
        try await settleAccessibility(view)
        if accessibilityElements(window).contains(where: { $0.value == text || $0.label == text }) { return }
      }
      throw CocoaError(.coderInvalidValue)
    }
    try await waitFor("Count: 0")
    guard let button = accessibilityElements(window).first(where: { $0.role == "AXButton" && $0.label == "Increment" }),
      button.press() else { throw CocoaError(.coderInvalidValue) }
    try await waitFor("Count: 1")
    print("PASS: external SwiftUI CLI application updates real OCaml state")
    fflush(stdout)
    exit(0)
  } catch {
    print("FAIL: external counter: \\(error)")
    fflush(stdout)
    exit(1)
  }
}
#endif
''')
        for profile, configuration in [("debug", "Debug"), ("profile", "Profile"), ("release", "Release")]:
            with self.subTest(profile=profile):
                self.cli("build", "macos", "--profile", profile)
                bundle = self.project / f"apple/DerivedData/Build/Products/{configuration}/BonsaiJournal.app"
                self.assertTrue(bundle.is_dir())
                subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
        result = self.cli("run", "macos", "--profile", "debug", timeout=120)
        self.assertIn("PASS: external SwiftUI CLI application updates real OCaml state", result.stdout)
        marker = self.project / "exec-result.txt"
        code = "import os,pathlib,sys; p=pathlib.Path(os.environ['BONSAI_SWIFTUI_NATIVE_OBJECT']); assert p.is_file(); pathlib.Path(sys.argv[1]).write_text(sys.argv[2]); sys.exit(17)"
        result = self.cli("exec", "--", sys.executable, "-c", code, marker, "literal $() `value` ; 😀", success=False)
        self.assertEqual(result.returncode, 17, result.stderr)
        self.assertEqual(marker.read_text(), "literal $() `value` ; 😀")

    def test_prebuilt_object_validation_and_read_only_sync_check(self):
        self.initialize()
        source = ROOT / "_build/default/examples/counter/ocaml/native_embed.exe.o"
        # A macOS object cannot enter an iPhoneOS build, even when unsigned.
        self.cli("build", "ios", "--no-codesign", "--native-object", source, success=False)
        self.assertFalse((self.project / "apple/Native/iphoneos").exists())
        before = {p.relative_to(self.project): (p.read_bytes(), p.stat().st_mtime_ns)
                  for p in self.project.rglob("*") if p.is_file()}
        self.cli("sync-host", "--check")
        after = {p.relative_to(self.project): (p.read_bytes(), p.stat().st_mtime_ns)
                 for p in self.project.rglob("*") if p.is_file()}
        self.assertEqual(before, after)

    def test_exec_failure_and_interrupt_keep_project_sources(self):
        self.initialize()
        marker = self.project / "child-ready.txt"
        invalid = self.project / "invalid.exe.o"
        invalid.write_text("not a native object")
        self.cli("exec", "--native-object", invalid, "--", sys.executable, "-c",
                 "from pathlib import Path; Path('child-ready.txt').write_text('unexpected')", success=False)
        self.assertFalse(marker.exists())
        source = ROOT / "_build/default/examples/counter/ocaml/native_embed.exe.o"
        owned = {p: p.read_bytes() for p in [self.project / "swift/App.swift", self.project / "app/dune"]}
        code = "import pathlib,signal,time; p=pathlib.Path('child-ready.txt'); signal.signal(signal.SIGINT,lambda *_: (p.write_text('interrupted'),exit(130))); p.write_text('ready'); time.sleep(60)"
        process = subprocess.Popen([str(CLI), "exec", "--native-object", str(source), "--", sys.executable, "-c", code],
                                   cwd=self.project, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            deadline = time.monotonic() + 30
            while not marker.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.1)
            self.assertTrue(marker.exists(), "exec child did not start")
            process.send_signal(signal.SIGINT)
            output, _ = process.communicate(timeout=15)
            self.assertEqual(process.returncode, 130, output)
            self.assertEqual(marker.read_text(), "interrupted")
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
        self.assertEqual(owned, {p: p.read_bytes() for p in owned})

    def test_clean_native_and_xcode_outputs_preserves_sources_and_other_platform(self):
        self.initialize()
        apple = self.project / "apple"
        for relative in ["Native/macosx/Debug/runtime.complete.o", "Native/iphoneos/Debug/runtime.complete.o",
                         "DerivedData/Build/Products/Debug/app-marker", "DerivedData/Build/Products/Release/app-marker",
                         "DerivedData/Build/Products/Debug-iphoneos/app-marker"]:
            path = apple / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("generated output")
        owned = {p: p.read_bytes() for p in [self.project / "swift/App.swift", self.project / "app/dune",
                                            apple / "BonsaiJournal.xcodeproj/project.pbxproj"]}
        self.cli("clean", "macos")
        self.assertFalse((apple / "Native/macosx").exists())
        self.assertFalse((apple / "DerivedData/Build/Products/Debug").exists())
        self.assertFalse((apple / "DerivedData/Build/Products/Release").exists())
        self.assertTrue((apple / "Native/iphoneos/Debug/runtime.complete.o").is_file())
        self.assertTrue((apple / "DerivedData/Build/Products/Debug-iphoneos/app-marker").is_file())
        self.cli("clean", "--all-project-builds")
        self.assertFalse((apple / "Native").exists())
        self.assertFalse((apple / "DerivedData").exists())
        self.assertEqual(owned, {p: p.read_bytes() for p in owned})

    def test_clean_does_not_follow_an_external_host_parent(self):
        self.initialize()
        with tempfile.TemporaryDirectory(prefix="unrelated CLI files ") as directory:
            outside = Path(directory)
            sentinel = outside / "Native/macosx/keep.txt"
            sentinel.parent.mkdir(parents=True)
            sentinel.write_text("unrelated")
            (self.project / "apple").rename(self.project / "saved-apple")
            (self.project / "apple").symlink_to(outside, target_is_directory=True)
            self.cli("clean", "--all-project-builds", success=False)
            self.assertEqual(sentinel.read_text(), "unrelated")
            self.assertTrue((self.project / "apple").is_symlink())


if __name__ == "__main__":
    unittest.main(verbosity=2)
