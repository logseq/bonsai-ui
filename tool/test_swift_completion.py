"""Reject successful process exits that did not complete Swift Testing."""

import contextlib
import io
import json
import sys
import unittest

from run_swift_tests import run_swift_tests


REPORT = '''<testsuites><testsuite name="TestResults" tests="1" errors="0"
failures="0" skipped="0"><testcase name="completed"/></testsuite></testsuites>'''

CHILD = '''
import json, pathlib, sys
payload, status, suffix = json.loads(sys.argv[1])
path = pathlib.Path(sys.argv[-1])
if payload is not None:
    path.with_name(path.stem + suffix + path.suffix).write_text(payload)
sys.exit(status)
'''


class SwiftCompletionTests(unittest.TestCase):
    def run_child(self, report, status=0, suffix="-swift-testing"):
        with contextlib.redirect_stderr(io.StringIO()):
            return run_swift_tests([
                sys.executable, "-c", CHILD, json.dumps([report, status, suffix])
            ])

    def test_complete_success(self):
        self.assertEqual(self.run_child(REPORT), 0)

    def test_nonzero_exit_with_complete_report(self):
        self.assertNotEqual(self.run_child(REPORT, status=7), 0)

    def test_zero_exit_without_report(self):
        self.assertNotEqual(self.run_child(None), 0)

    def test_unrelated_xctest_report_does_not_prove_swift_testing_completed(self):
        self.assertNotEqual(self.run_child(REPORT, suffix=""), 0)

    def test_report_from_prior_run_cannot_mask_missing_completion(self):
        self.assertEqual(self.run_child(REPORT), 0)
        self.assertNotEqual(self.run_child(None), 0)

    def test_truncated_and_malformed_reports(self):
        for report in ["", "<testsuites>", "<unrelated/>", "<testsuites/>"]:
            with self.subTest(report=report):
                self.assertNotEqual(self.run_child(report), 0)

    def test_declared_count_must_match_completed_cases(self):
        for count in ["0", "2", "-1", "unknown"]:
            with self.subTest(count=count):
                self.assertNotEqual(self.run_child(REPORT.replace('tests="1"', f'tests="{count}"')), 0)

    def test_failure_and_error_counters(self):
        for counter in ["failures", "errors"]:
            with self.subTest(counter=counter):
                self.assertNotEqual(self.run_child(REPORT.replace(f'{counter}="0"', f'{counter}="1"')), 0)

    def test_failed_case_cannot_hide_behind_successful_counters(self):
        for result in ["failure", "error"]:
            with self.subTest(result=result):
                report = REPORT.replace('<testcase name="completed"/>', f'<testcase name="completed"><{result}/></testcase>')
                self.assertNotEqual(self.run_child(report), 0)

    def test_all_skipped_is_not_an_executed_suite(self):
        report = REPORT.replace('skipped="0"', 'skipped="1"').replace(
            '<testcase name="completed"/>', '<testcase name="completed"><skipped/></testcase>')
        self.assertNotEqual(self.run_child(report), 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
