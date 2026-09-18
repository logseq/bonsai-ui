"""Generate or check input fixtures using the production Swift event encoder."""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from run_swift_tests import run_swift_tests


ROOT = Path(__file__).resolve().parents[1]
NAMES = {f"swift_{name}.hex" for name in (
    "confirmation_action", "confirmation_dismissed",
    "counter_press", "host_response", "text_edit_unicode", "text_limit_reached",
    "environment_changed", "application_response", "application_event",
)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    os.chdir(ROOT)
    subprocess.run(["dune", "build", "native/test/libruntime_fixture.dylib"], check=True)
    with tempfile.TemporaryDirectory(prefix="bonsai-swift-input-fixtures-") as directory:
        os.environ["BONSAI_SWIFTUI_INPUT_FIXTURE_OUTPUT"] = directory
        status = run_swift_tests([
            "swift", "test", "--scratch-path", "_build/swift", "--no-parallel",
            "--filter", "SwiftInputFixtureTests",
        ])
        if status:
            return status
        outputs = {path.name: path.read_bytes() for path in Path(directory).glob("*.hex")}
        if set(outputs) != NAMES:
            print("Swift did not produce the complete input fixture set", file=sys.stderr)
            return 1
        destination = ROOT / "protocol/generated/fixtures"
        stale = []
        for name, data in sorted(outputs.items()):
            path = destination / name
            if args.check:
                if not path.is_file() or path.read_bytes() != data:
                    stale.append(path)
            else:
                path.write_bytes(data)
        for path in stale:
            print(f"Generated fixture is stale: {path}", file=sys.stderr)
        return int(bool(stale))


if __name__ == "__main__":
    sys.exit(main())
