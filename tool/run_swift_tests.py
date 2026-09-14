"""Run the Swift Testing suite and require its completed xUnit report."""

from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


def completed_cases(report):
    root = ET.parse(report).getroot()
    suites = root.findall("testsuite")
    if root.tag != "testsuites" or not suites:
        raise ValueError("Missing Swift Testing suites")
    executed = 0
    for suite in suites:
        cases = suite.findall("testcase")
        skipped = sum(case.find("skipped") is not None for case in cases)
        if (
            int(suite.attrib["tests"]) != len(cases)
            or int(suite.attrib["failures"]) != 0
            or int(suite.attrib["errors"]) != 0
            or int(suite.attrib["skipped"]) != skipped
            or suite.findall(".//failure")
            or suite.findall(".//error")
        ):
            raise ValueError("Failed or inconsistent Swift Testing report")
        executed += len(cases) - skipped
    if executed == 0:
        raise ValueError("No Swift tests completed")
    return executed


def run_swift_tests(command):
    with tempfile.TemporaryDirectory(prefix="bonsai-swift-tests-") as directory:
        report = Path(directory) / "results.xml"
        status = subprocess.run([*command, "--xunit-output", str(report)]).returncode
        if status != 0:
            return status
        # SwiftPM writes Swift Testing separately from its XCTest report.
        # A fresh directory prevents a previous successful run masking early exit.
        swift_report = report.with_name("results-swift-testing.xml")
        try:
            completed_cases(swift_report)
        except (OSError, ET.ParseError, ValueError, KeyError) as error:
            print(f"Swift Testing did not complete successfully: {error}", file=sys.stderr)
            return 1
        return 0


if __name__ == "__main__":
    # Native UI tests share one AppKit application and must not compete for its run loop.
    sys.exit(run_swift_tests(["swift", "test", "--scratch-path", "_build/swift", "--no-parallel"]))
