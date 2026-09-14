"""Validate the actual unsigned iOS probe bundle and damaged copies."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PRODUCTS = ROOT / "_build/ios/datascript-worker-device/host/DerivedData/Build/Products/Release-iphoneos"
APP = PRODUCTS / "DataScriptWorkerProbe.app"


class SwiftUIBundleTests(unittest.TestCase):
    def verify(self, app, *arguments):
        return subprocess.run([str(ROOT / "tool/ios/verify_app_bundle.sh"), str(app), *map(str, arguments)],
                              capture_output=True, text=True)

    def test_actual_swiftui_app_and_matching_dsym(self):
        result = self.verify(APP, PRODUCTS / "DataScriptWorkerProbe.app.dSYM", "require-sqlite")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_sqlite_must_be_explicitly_required(self):
        result = self.verify(APP)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpectedly requires Apple system libsqlite3", result.stderr)

    def test_missing_privacy_manifest_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / APP.name
            shutil.copytree(APP, app)
            (app / "BonsaiSwiftUI_BonsaiSwiftUI.bundle/PrivacyInfo.xcprivacy").unlink()
            result = self.verify(app, "require-sqlite")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("privacy manifest is missing", result.stderr)

    def test_mismatched_dsym_is_rejected(self):
        result = self.verify(APP, APP, "require-sqlite")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
