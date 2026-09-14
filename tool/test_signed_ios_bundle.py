"""Audit a real SwiftUI iOS executable signed with a profile-authorized identity.

Requires the native DataScript probe build and a development profile/private key.
No codesign, CMS, Mach-O, entitlement, or dSYM command is mocked. The expiry test
advances only the audit subprocess's clock; it does not change the system clock.
"""

import copy
import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
PRODUCTS = ROOT / "_build/ios/datascript-worker-device/host/DerivedData/Build/Products/Release-iphoneos"


class SignedIOSBundleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="swiftui-signing-audit-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        cls.source = Path(os.environ.get("SWIFTUI_SIGNED_AUDIT_APP", PRODUCTS / "DataScriptWorkerProbe.app"))
        cls.dsym = Path(os.environ.get("SWIFTUI_SIGNED_AUDIT_DSYM", PRODUCTS / "DataScriptWorkerProbe.app.dSYM"))
        cls.profile = Path(os.environ.get("SWIFTUI_SIGNED_AUDIT_PROFILE", ROOT /
            "examples/mail/apple/DerivedData/Build/Products/Release-iphoneos/BonsaiMail.app/embedded.mobileprovision"))
        for path in [cls.source, cls.dsym, cls.profile]:
            if not path.exists():
                raise RuntimeError(f"Required native signing fixture does not exist: {path}")
        decoded = subprocess.run(["security", "cms", "-D", "-i", str(cls.profile)],
                                 check=True, capture_output=True).stdout
        cls.profile_data = plistlib.loads(decoded)
        if cls.profile_data["Entitlements"]["get-task-allow"] is not True:
            raise RuntimeError("The signing audit requires a genuine development profile")
        identities = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning"], text=True)
        available = set(re.findall(r"\) ([0-9A-F]{40}) ", identities))
        allowed = {hashlib.sha1(cert).hexdigest().upper() for cert in cls.profile_data["DeveloperCertificates"]}
        matching = sorted(available & allowed)
        cls.identity = os.environ.get("SWIFTUI_SIGNED_AUDIT_IDENTITY")
        if cls.identity is None:
            if not matching:
                raise RuntimeError("No available signing identity is authorized by the development profile")
            cls.identity = matching[0]
        cls.team = cls.profile_data["TeamIdentifier"][0]
        cls.prefix = cls.profile_data["ApplicationIdentifierPrefix"][0]
        pattern = cls.profile_data["Entitlements"]["application-identifier"]
        if not pattern.startswith(cls.prefix + "."):
            raise RuntimeError("The profile App ID does not use its declared prefix")
        bundle = pattern[len(cls.prefix) + 1:]
        cls.bundle = bundle[:-1] + "org.bonsai-swiftui.signing-audit" if bundle.endswith("*") else bundle
        cls.entitlements = {
            "application-identifier": cls.prefix + "." + cls.bundle,
            "com.apple.developer.team-identifier": cls.team,
            "get-task-allow": True,
        }
        cls.app = cls.make_app("signed")

    @classmethod
    def make_app(cls, name, *, entitlements=None, identity=None, bundle=None, profile=True):
        app = cls.root / (name + ".app")
        shutil.copytree(cls.source, app)
        info_path = app / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleIdentifier"] = bundle or cls.bundle
        info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
        if profile:
            shutil.copyfile(cls.profile, app / "embedded.mobileprovision")
        path = cls.root / (name + "-entitlements.plist")
        path.write_bytes(plistlib.dumps(entitlements or cls.entitlements))
        result = subprocess.run([
            "codesign", "--force", "--sign", identity or cls.identity,
            "--entitlements", str(path), "--timestamp=none", str(app),
        ], capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise RuntimeError("Could not sign the native audit App: " + result.stderr)
        return app

    def verify(self, app=None, kind="development", *, dsym=False, sqlite=True, env=None):
        arguments = [str(ROOT / "tool/ci/verify_ios_bundle.sh"), str(app or self.app), kind]
        if dsym:
            arguments.append(str(self.dsym if dsym is True else dsym))
        if sqlite:
            arguments.append("require-sqlite")
        return subprocess.run(arguments, capture_output=True, text=True, env=env, timeout=30)

    def reject(self, result, reason):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(reason, result.stderr)

    def test_actual_signed_swiftui_app_and_matching_dsym(self):
        for dsym in [False, True]:
            with self.subTest(dsym=dsym):
                result = self.verify(dsym=dsym)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("signed iOS application bundle verification passed", result.stdout)

    def test_sqlite_and_dsym_requirements_reach_the_native_bundle_verifier(self):
        self.reject(self.verify(sqlite=False), "unexpectedly requires Apple system libsqlite3")
        self.reject(self.verify(dsym=self.app), "application dSYM does not exist")

    def test_adhoc_apps_are_not_development_signatures(self):
        app = self.make_app("adhoc", identity="-")
        self.reject(self.verify(app), "signing certificate")

    def test_missing_profile_is_rejected(self):
        app = self.make_app("without-profile", profile=False)
        self.reject(self.verify(app), "embedded provisioning profile is missing")

    def test_resource_tampering_invalidates_the_actual_signature(self):
        app = self.root / "tampered.app"
        shutil.copytree(self.app, app)
        info_path = app / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleDisplayName"] = "Tampered after signing"
        info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
        self.reject(self.verify(app), "application code signature is invalid")

    def test_profile_team_and_app_id_must_match_the_signed_entitlements(self):
        for key, value, reason in [
            ("com.apple.developer.team-identifier", "WRONGTEAM", "Team IDs differ"),
            ("application-identifier", "WRONGTEAM." + self.bundle, "App ID"),
        ]:
            with self.subTest(key=key):
                entitlements = copy.deepcopy(self.entitlements)
                entitlements[key] = value
                app = self.make_app("mismatch-" + key, entitlements=entitlements)
                self.reject(self.verify(app), reason)

    def test_bundle_identifier_must_match_the_signed_app_id(self):
        app = self.make_app("other-bundle", bundle="org.bonsai-swiftui.other-bundle")
        self.reject(self.verify(app), "bundle identifier")

    def test_debug_entitlements_are_typed_and_must_match_profile_and_signing_kind(self):
        self.reject(self.verify(kind="distribution"), "get-task-allow")
        for value in [False, "true"]:
            with self.subTest(value=value):
                entitlements = copy.deepcopy(self.entitlements)
                entitlements["get-task-allow"] = value
                app = self.make_app("debug-" + str(value), entitlements=entitlements)
                self.reject(self.verify(app), "get-task-allow")

    def test_expired_profile_is_rejected_without_changing_the_system_clock(self):
        directory = self.root / "clock"
        directory.mkdir()
        now = int(self.profile_data["ExpirationDate"].replace(tzinfo=datetime.UTC).timestamp()) + 1
        command = directory / "date"
        command.write_text("#!/usr/bin/env python3\nimport os,sys\n"
                           f"if sys.argv[1:] in [['+%s'], ['-u', '+%s']]: print({now})\n"
                           "else: os.execv('/bin/date', ['/bin/date', *sys.argv[1:]])\n")
        command.chmod(0o755)
        env = dict(os.environ, PATH=str(directory) + ":" + os.environ["PATH"])
        self.reject(self.verify(env=env), "profile has expired")


if __name__ == "__main__":
    unittest.main(verbosity=2)
