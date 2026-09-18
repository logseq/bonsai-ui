"""Replay CoreDevice responses through the real preflight and signing checks.

Only the external device/keychain boundaries are replayed. JSON parsing,
profile membership, entitlement checks and certificate expiry use real tools.
These tests do not establish physical-device readiness or CMS trust.
"""

import copy
import datetime
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
DEVICE = "11111111-2222-3333-4444-555555555555"
UDID = "00008110-000A71C414BB801E"
DETAILS = {
    "info": {"outcome": "success"},
    "result": {
        "identifier": DEVICE,
        "hardwareProperties": {
            "platform": "iOS", "reality": "physical", "udid": UDID,
            "supportedCPUTypes": [{"name": "arm64e"}, {"name": "arm64"}],
        },
        "connectionProperties": {"pairingState": "paired"},
        "deviceProperties": {
            "osVersionNumber": "26.0", "developerModeStatus": "enabled",
            "ddiServicesAvailable": True,
        },
    },
}
LOCK = {"info": {"outcome": "success"},
        "result": {"unlockedSinceBoot": True, "passcodeRequired": False}}


class DevicePreflightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="swiftui-preflight-")
        cls.root = Path(cls.directory.name)
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", str(cls.root / "key.pem"), "-out", str(cls.root / "cert.pem"),
            "-days", "60", "-subj", "/CN=Preflight Test",
        ], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def run_preflight(self, details=None, lock=None, device=DEVICE,
                      signing=False, profile_change=None, command_failure=None):
        with tempfile.TemporaryDirectory(dir=self.root) as directory:
            root = Path(directory)
            (root / "details.json").write_text(json.dumps(details or DETAILS))
            (root / "lockState.json").write_text(json.dumps(lock or LOCK))
            replay = root / "xcrun"
            replay.write_text("""#!/usr/bin/env python3
import os, pathlib, shutil, sys
root = pathlib.Path(os.environ['PREFLIGHT_REPLAY'])
args = sys.argv[1:]
with (root / 'commands.jsonl').open('a') as f:
    import json
    f.write(json.dumps(args) + '\\n')
assert args[:3] == ['devicectl', 'device', 'info'], args
kind = args[3]
if kind == os.environ.get('PREFLIGHT_COMMAND_FAILURE'):
    sys.exit(9)
shutil.copyfile(root / (kind + '.json'), args[args.index('--json-output') + 1])
""")
            replay.chmod(0o755)
            flutter = root / "flutter"
            flutter.write_text("#!/bin/sh\nexit 97\n")
            flutter.chmod(0o755)
            security = root / "security"
            security.write_text("""#!/usr/bin/env python3
import os, pathlib, sys
args = sys.argv[1:]
if args[0] == 'find-certificate':
    sys.stdout.buffer.write(pathlib.Path(os.environ['PREFLIGHT_CERT']).read_bytes())
elif args[:2] == ['cms', '-D']:
    sys.stdout.buffer.write(pathlib.Path(args[args.index('-i') + 1]).read_bytes())
else:
    sys.exit(98)
""")
            security.chmod(0o755)
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                       PREFLIGHT_REPLAY=str(root),
                       PREFLIGHT_CERT=str(self.root / "cert.pem"),
                       PREFLIGHT_COMMAND_FAILURE=command_failure or "")
            if signing:
                env.update(IOS_DEVELOPMENT_TEAM="TESTTEAM", IOS_BUNDLE_IDENTIFIER="org.test.mail")
                for label, debug in [("development", True), ("distribution", False)]:
                    profile = {
                        "TeamIdentifier": ["TESTTEAM"], "ProvisionedDevices": [UDID],
                        "ExpirationDate": datetime.datetime.now(datetime.UTC).replace(tzinfo=None)
                        + datetime.timedelta(days=60),
                        "Entitlements": {"application-identifier": "TESTTEAM.org.test.mail",
                                         "get-task-allow": debug},
                    }
                    if profile_change:
                        profile_change(profile)
                    path = root / f"{label}.plist"
                    path.write_bytes(plistlib.dumps(profile))
                    env[f"IOS_{label.upper()}_PROFILE_PATH"] = str(path)
            result = subprocess.run(
                [str(ROOT / "tool/ci/ios_device_preflight.sh"), device]
                + (["--require-signing"] if signing else []),
                env=env, capture_output=True, text=True, timeout=20,
            )
            commands = root / "commands.jsonl"
            calls = [json.loads(line) for line in commands.read_text().splitlines()] if commands.exists() else []
            return result, calls

    def test_physical_ios_without_flutter_or_boot_state(self):
        for device in [DEVICE, UDID, UDID.lower()]:
            with self.subTest(device=device):
                result, calls = self.run_preflight(device=device)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual([call[3] for call in calls], ["details", "lockState"])
                self.assertIn("preflight passed", result.stdout)

    def test_rejects_unsupported_or_unavailable_device_before_lock_query(self):
        changes = [
            ("hardwareProperties", "platform", "macOS"),
            ("hardwareProperties", "reality", "simulated"),
            ("hardwareProperties", "supportedCPUTypes", [{"name": "x86_64"}]),
            ("hardwareProperties", "udid", ""),
            ("connectionProperties", "pairingState", "unpaired"),
            ("deviceProperties", "developerModeStatus", "disabled"),
            ("deviceProperties", "ddiServicesAvailable", False),
            ("deviceProperties", "osVersionNumber", "17.9"),
            ("deviceProperties", "osVersionNumber", "invalid"),
            ("deviceProperties", "osVersionNumber", None),
        ]
        for section, key, value in changes:
            with self.subTest(key=key, value=value):
                details = copy.deepcopy(DETAILS)
                details["result"][section][key] = value
                result, calls = self.run_preflight(details=details)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual([call[3] for call in calls], ["details"])

    def test_requires_exact_selected_identifier(self):
        result, calls = self.run_preflight(device="another-device")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("selected device", result.stderr)
        self.assertEqual(len(calls), 1)

    def test_rejects_locked_or_incomplete_lock_response(self):
        for state in [{}, {"unlockedSinceBoot": False, "passcodeRequired": False},
                      {"unlockedSinceBoot": True, "passcodeRequired": True}]:
            result, calls = self.run_preflight(lock={"info": {"outcome": "success"}, "result": state})
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("currently unlocked", result.stderr)
            self.assertEqual(len(calls), 2)

    def test_coredevice_failure_stops_preflight(self):
        for command, count in [("details", 1), ("lockState", 2)]:
            result, calls = self.run_preflight(command_failure=command)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("CoreDevice", result.stderr)
            self.assertEqual(len(calls), count)

    def test_signing_resolves_coredevice_uuid_to_profile_udid(self):
        result, _ = self.run_preflight(signing=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_signing_membership_is_exact_and_only_uses_provisioned_devices(self):
        for devices in [[], [UDID + "0"], [DEVICE]]:
            def change(profile):
                profile["ProvisionedDevices"] = devices
                profile["Name"] = UDID
            result, _ = self.run_preflight(signing=True, profile_change=change)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("does not include the selected device", result.stderr)

    def test_signing_still_checks_team_bundle_entitlements_and_expiry(self):
        changes = [
            lambda p: p.update(TeamIdentifier=["WRONG"]),
            lambda p: p["Entitlements"].update({"application-identifier": "TESTTEAM.org.other"}),
            lambda p: p["Entitlements"].update({"get-task-allow": False}),
            lambda p: p.update(ExpirationDate=datetime.datetime(2000, 1, 1)),
        ]
        for change in changes:
            result, _ = self.run_preflight(signing=True, profile_change=change)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("provisioning profile", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
