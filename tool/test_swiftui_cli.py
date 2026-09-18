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
        self.cli("init", "--name", "journal", "--macos-bundle-identifier", "org.example.journal", "--ios-bundle-identifier", "org.example.journal.ios")

    def snapshot(self, *, include_build=True):
        paths = []
        for directory, directories, files in os.walk(self.project):
            base = Path(directory)
            if not include_build:
                if base == self.project:
                    directories[:] = [d for d in directories if d != "_build"]
                if base == self.project / "apple":
                    directories[:] = [d for d in directories if d != "DerivedData"]
            paths.extend(base / name for name in directories + files)
        return {str(p.relative_to(self.project)): (p.read_bytes(), p.stat().st_mtime_ns)
                if p.is_file() else (None, p.stat().st_mtime_ns)
                for p in paths if not p.is_symlink()}

    def configured_entitlements(self):
        import plistlib
        self.initialize()
        path = self.project / "config/debug.entitlements"
        path.parent.mkdir()
        value = {"keychain-access-groups": ["$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)"],
                 "com.apple.security.cs.allow-jit": True, "nested": {"bool": False, "int": 1}}
        path.write_bytes(plistlib.dumps(value))
        release = path.with_name("release.entitlements")
        release.write_bytes(plistlib.dumps({"keychain-access-groups": value["keychain-access-groups"]}, fmt=plistlib.FMT_BINARY))
        config = self.project / "bonsai-swiftui.sexp"
        config.write_text(config.read_text().replace("(macos", """(macos
          (entitlements (debug config/debug.entitlements) (profile config/debug.entitlements)
                        (release config/release.entitlements))"""))
        return path, value

    def test_platform_entitlements_drift_and_adoption(self):
        import plistlib
        source, value = self.configured_entitlements()
        self.cli("sync-host")
        for profile in ("Debug", "Profile"):
            self.assertEqual(plistlib.loads((self.project / f"apple/Entitlements/macOS/{profile}.entitlements").read_bytes()), value)
        release = plistlib.loads((self.project / "apple/Entitlements/macOS/Release.entitlements").read_bytes())
        self.assertNotIn("com.apple.security.cs.allow-jit", release)
        before = self.snapshot()
        self.cli("init", "--adopt")
        self.cli("sync-host", "--check")
        self.cli("sync-host")
        self.assertEqual(before, self.snapshot())
        source.write_bytes(plistlib.dumps({**value, "new": True}))
        before = self.snapshot()
        self.cli("sync-host", "--check", success=False)
        self.assertEqual(before, self.snapshot())
        self.cli("sync-host")
        self.cli("sync-host", "--check")

    def test_invalid_file_inputs_preserve_existing_and_absent_hosts(self):
        import plistlib
        import shutil
        source, _ = self.configured_entitlements()
        config = self.project / "bonsai-swiftui.sexp"
        original = config.read_text()
        self.cli("sync-host")
        invalid = [b"broken plist", plistlib.dumps(["not a dictionary"]),
                   b'<plist><dict><key>a</key><true/><key>a</key><false/></dict></plist>',
                   b'<plist><dict><key>nested</key><dict><key>a</key><true/><key>a</key><false/></dict></dict></plist>']
        for absent in (False, True):
            if absent:
                shutil.rmtree(self.project / "apple")
            for content in invalid:
                source.write_bytes(content)
                for command in (("sync-host",), ("sync-host", "--check"), ("init", "--adopt"),
                                ("build", "macos"), ("build-native", "--target", "macos")):
                    with self.subTest(absent=absent, content=content, command=command):
                        before = self.snapshot()
                        self.cli(*command, success=False)
                        self.assertEqual(before, self.snapshot())
            source.unlink(missing_ok=True)
            for path in ("config/missing", "config", "../escape", "/tmp/escape", "apple/source.entitlements"):
                config.write_text(original.replace("config/debug.entitlements", path))
                before = self.snapshot()
                self.cli("init", "--adopt", success=False)
                self.assertEqual(before, self.snapshot())
            config.write_text(original)

    def test_schema_four_init_flags_and_derived_identifier_limits(self):
        for args in (("--bundle-identifier", "org.example.old"),
                     ("--ios-bundle-identifier", "org." + "a" * 245),
                     ("--macos-bundle-identifier", "invalid")):
            self.cli("init", "--name", "journal", *args, success=False)
            self.assertEqual(list(self.project.iterdir()), [])
        self.initialize()
        config = (self.project / "bonsai-swiftui.sexp").read_text()
        self.assertIn("(lang 4)", config)
        self.assertIn("org.example.journal.ios", config)
        project = (self.project / "apple/BonsaiJournal.xcodeproj/project.pbxproj").read_text()
        self.assertIn('"org.example.journal.ios"', project)
        self.assertIn('"org.example.journal"', project)
        for flag in ("--macos-bundle-identifier", "--ios-bundle-identifier"):
            before = self.snapshot()
            self.cli("init", "--adopt", flag, "org.example.other", success=False)
            self.assertEqual(before, self.snapshot())

    def test_remote_package_resolution_and_locked_builds(self):
        import json
        import plistlib
        self.initialize()
        config = self.project / "bonsai-swiftui.sexp"
        declaration = """(swift_packages
          (package (id collections) (url https://github.com/apple/swift-collections.git)
           (requirement (exact 1.1.4))
           (products (product (name OrderedCollections) (platforms macos ios))))
          (package (id algorithms) (url https://github.com/apple/swift-algorithms.git)
           (requirement (exact 1.2.0))
           (products (product (name Algorithms) (platforms macos)))))"""
        config.write_text(config.read_text().replace("(features)", "(features) " + declaration))
        (self.project / "swift/App.swift").write_text("""import BonsaiSwiftUI
import SwiftUI
import OrderedCollections
#if os(macOS)
import Algorithms
#endif
@main struct PackageAcceptance: App {
  init() {
    let values: OrderedSet<Int> = [3, 1, 3, 2]
    precondition(Array(values) == [3, 1, 2])
    #if os(macOS)
    precondition([1, 2, 3].chunks(ofCount: 2).map(Array.init) == [[1, 2], [3]])
    #endif
    if CommandLine.arguments.contains("--package-smoke") {
      print("PASS: OrderedCollections executed")
      exit(0)
    }
  }
  var body: some Scene { WindowGroup { BonsaiApplicationView(entrypoint: "journal") } }
}
""")
        self.cli("sync-host")
        before = self.snapshot(include_build=False)
        result = self.cli("build", "macos", success=False)
        self.assertIn("resolve-packages", result.stdout + result.stderr)
        self.assertEqual(before, self.snapshot(include_build=False))
        self.cli("resolve-packages", timeout=600)
        lock = self.project / "swift-packages/Package.resolved"
        resolved = lock.read_bytes()
        pins = json.loads(resolved)["pins"]
        pin = next(p for p in pins if p["identity"] == "swift-collections")
        self.assertEqual(pin["state"]["version"], "1.1.4")
        self.assertTrue(any(p["identity"] == "swift-numerics" for p in pins), "The lock must cover the transitive graph")
        self.cli("sync-host", "--check")
        print("Resolved remote pins: " + json.dumps(pins, sort_keys=True), flush=True)
        before = self.snapshot(include_build=False)
        self.cli("resolve-packages", timeout=600)
        self.assertEqual(before, self.snapshot(include_build=False), "Repeated resolution must preserve protected bytes and mtimes")
        for profile in ("debug", "profile", "release"):
            self.cli("build", "macos", "--profile", profile, timeout=600)
            bundle = self.project / f"apple/DerivedData/Build/Products/{profile.title()}/BonsaiJournal.app"
            metadata = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
            self.assertEqual(metadata["CFBundleIdentifier"], "org.example.journal")
            result = subprocess.run([bundle / "Contents/MacOS/BonsaiJournal", "--package-smoke"],
                                    capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS: OrderedCollections executed", result.stdout)
            self.assertEqual(lock.read_bytes(), resolved)
            print(f"PASS: locked {profile} build and package execution", flush=True)
        offline = subprocess.run(
            ["sandbox-exec", "-p", "(version 1)(allow default)(deny network-outbound)",
             str(CLI), "build", "macos", "--profile", "release", "--no-codesign"],
            cwd=self.project, env=self.env, capture_output=True, text=True, timeout=300,
        )
        self.assertEqual(offline.returncode, 0, (offline.stdout + offline.stderr)[-12000:])
        self.assertIn("dependency cache hit macos/release", offline.stderr)
        print("PASS: offline locked application build with cached packages", flush=True)
        if self.env.get("BONSAI_SWIFTUI_ACCEPT_IOS") == "1":
            self.cli("toolchain", "verify", "iphoneos")
            self.cli("build", "ios", "--profile", "release", "--no-codesign", timeout=900)
            metadata = plistlib.loads((self.project / "apple/DerivedData/Build/Products/Release-iphoneos/BonsaiJournal.app/Info.plist").read_bytes())
            self.assertEqual(metadata["CFBundleIdentifier"], "org.example.journal.ios")
            self.assertEqual(lock.read_bytes(), resolved)
            print("PASS: locked unsigned physical-iOS package build", flush=True)
        incomplete = json.loads(resolved)
        incomplete["pins"] = [p for p in pins if p["identity"] != "swift-numerics"]
        lock.write_text(json.dumps(incomplete))
        before = self.snapshot(include_build=False)
        result = self.cli("build", "macos", success=False, timeout=600)
        self.assertIn("resolve-packages", result.stdout + result.stderr)
        self.assertEqual(before, self.snapshot(include_build=False))
        lock.write_bytes(resolved)
        original = config.read_text()
        for bad in (original.replace("OrderedCollections", "MissingAcceptanceProduct"),
                    original.replace("(exact 1.1.4)", "(revision " + "0" * 40 + ")")):
            config.write_text(bad)
            # Offline generation accepts syntactically valid remote declarations.
            if "MissingAcceptanceProduct" in bad:
                self.cli("sync-host")
            if "MissingAcceptanceProduct" not in bad:
                import shutil
                shutil.rmtree(self.project / "apple")
            before = self.snapshot(include_build=False)
            self.cli("resolve-packages", success=False, timeout=600)
            self.assertEqual(before, self.snapshot(include_build=False))
            self.cli("build", "macos", success=False, timeout=600)
            self.assertEqual(before, self.snapshot(include_build=False))
        config.write_text(original.replace("(exact 1.1.4)", "(revision " + pin["state"]["revision"] + ")"))
        self.cli("resolve-packages", timeout=600)
        self.cli("build", "macos", timeout=600)
        self.assertEqual(next(p for p in json.loads(lock.read_bytes())["pins"] if p["identity"] == "swift-collections")["state"]["revision"], pin["state"]["revision"])

    def test_documented_journal_configuration_generates_without_signing(self):
        import plistlib
        self.initialize()
        documentation = (ROOT / "docs/swiftui-cli.md").read_text().split("## Application identities, entitlements and Swift packages", 1)[1]
        config = documentation.split("```lisp\n", 1)[1].split("```", 1)[0]
        (self.project / "bonsai-swiftui.sexp").write_text(config)
        xml = [section.split("```", 1)[0] for section in documentation.split("```xml\n")[1:]]
        directory = self.project / "config/entitlements"
        directory.mkdir(parents=True)
        (directory / "macos-debug-profile.entitlements").write_text(xml[0])
        (directory / "macos-release.entitlements").write_text(xml[1])
        self.cli("sync-host")
        self.cli("sync-host", "--check")
        project = (self.project / "apple/BonsaiJournal.xcodeproj/project.pbxproj").read_text()
        self.assertEqual(project.count('"PRODUCT_BUNDLE_IDENTIFIER" = "com.logseq.journal";'), 6)
        for profile, content in (("Debug", xml[0]), ("Profile", xml[0]), ("Release", xml[1])):
            effective = self.project / f"apple/Entitlements/macOS/{profile}.entitlements"
            self.assertEqual(plistlib.loads(effective.read_bytes()), plistlib.loads(content.encode()))

    def test_explicit_signing_identity_is_exposed(self):
        result = self.cli("build", "--help=plain")
        self.assertIn("--signing-identity", result.stdout)
        result = self.cli("run", "--help=plain")
        self.assertIn("--signing-identity", result.stdout)

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
        self.assertIn("(minimum_version 26.0)", config.read_text())
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
            ["--name", "journal", "--macos-bundle-identifier", "invalid identifier"],
        ]:
            with self.subTest(arguments=arguments):
                self.cli("init", *arguments, success=False)
                self.assertEqual(list(self.project.iterdir()), [])
        self.initialize()
        config = self.project / "bonsai-swiftui.sexp"
        original = config.read_text()
        config.write_text(original.replace("(lang 4)", "(lang 2)"))
        result = self.cli("build-native", "--target", "macos", success=False)
        self.assertIn("Unsupported schema version", result.stdout + result.stderr)
        config.write_text(original.replace("(apple_root apple)", "(unknown_root unknown)"))
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

    def test_local_only_native_failure_does_not_publish_an_absent_host(self):
        import shutil
        self.initialize()
        host = self.project / "apple"
        shutil.rmtree(host)
        self.cli("build", "macos", "--native-object", self.project / "missing.o", success=False)
        self.assertFalse(host.exists(), "Local-only preflight must remain read-only")
        self.assertFalse((self.project / "_build/bonsai-swiftui/dependencies").exists())

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
        dependencies = self.project / "_build/bonsai-swiftui/dependencies"
        for relative in ("packages/keep", "probes/macos/debug/object", "validation/macos/debug.json", "probes/ios/release/object", "validation/ios/release.json"):
            path = dependencies / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("cache")
        self.cli("clean", "macos")
        self.assertFalse((apple / "Native/macosx").exists())
        self.assertFalse((apple / "DerivedData/Build/Products/Debug").exists())
        self.assertFalse((apple / "DerivedData/Build/Products/Release").exists())
        self.assertTrue((apple / "Native/iphoneos/Debug/runtime.complete.o").is_file())
        self.assertTrue((apple / "DerivedData/Build/Products/Debug-iphoneos/app-marker").is_file())
        self.assertFalse((dependencies / "probes/macos").exists())
        self.assertFalse((dependencies / "validation/macos").exists())
        self.assertTrue((dependencies / "probes/ios/release/object").is_file())
        self.assertTrue((dependencies / "packages/keep").is_file())
        self.cli("clean", "--all-project-builds")
        self.assertFalse(dependencies.exists())
        self.assertTrue((self.project / "_build/.bonsai-swiftui-apple.lock").is_file())
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
