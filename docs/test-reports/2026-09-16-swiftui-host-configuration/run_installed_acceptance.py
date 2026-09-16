"""Rerun the installed host matrix using the CLI selected by PATH and its opam environment."""
import os
from pathlib import Path
import sys
import unittest
import shutil
import subprocess
ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tool'))
import test_swiftui_cli as consumer
consumer.CLI = Path(shutil.which('bonsai-swiftui')).resolve()
class InstalledHostAcceptance(consumer.SwiftUICliTests):
    def setUp(self):
        super().setUp()
        self.env = {k:v for k,v in os.environ.items()
                    if k not in ('BONSAI_SWIFTUI_SOURCE_ROOT','OCAMLPATH')}
        self.env['BONSAI_SWIFTUI_ACCEPT_IOS']='1'
        self.assertNotIn('OCAMLPATH', self.env)
        self.assertNotIn('BONSAI_SWIFTUI_SOURCE_ROOT', self.env)
        self.lock_committed = False
        print('Installed consumer: '+str(self.project), flush=True)
    def cli(self, *arguments, **options):
        result = super().cli(*arguments, **options)
        if arguments == ('resolve-packages',) and result.returncode == 0 and not self.lock_committed:
            def git(*args):
                return subprocess.check_output(['git', '-C', str(self.project), *args], text=True)
            git('init')
            git('add', 'bonsai-swiftui.sexp', 'swift-packages/Package.resolved', 'swift/App.swift')
            git('-c', 'user.name=Bonsai Acceptance', '-c', 'user.email=acceptance@example.invalid',
                'commit', '-m', 'feat(acceptance): lock remote Swift package graph')
            (REPORT / 'consumer-lock-commit.txt').write_text(git('show', '--stat', '--format=fuller', 'HEAD'))
            (REPORT / 'committed-Package.resolved').write_text(git('show', 'HEAD:swift-packages/Package.resolved'))
            self.lock_committed = True
        return result
    def tearDown(self):
        if (self.project/'swift-packages/Package.resolved').is_file():
            report=REPORT
            (report/'consumer-Package.resolved').write_bytes((self.project/'swift-packages/Package.resolved').read_bytes())
            (report/'consumer.sexp').write_bytes((self.project/'bonsai-swiftui.sexp').read_bytes())
            (report/'consumer-App.swift').write_bytes((self.project/'swift/App.swift').read_bytes())
        project=self.project/'apple/BonsaiJournal.xcodeproj/project.pbxproj'
        if project.exists():
            self.assertIn('share/bonsai_swiftui_tool/framework', project.read_text())
            self.assertNotIn(str(consumer.ROOT), project.read_text())
        super().tearDown()
names=['test_remote_package_resolution_and_locked_builds',
       'test_platform_entitlements_drift_and_adoption',
       'test_invalid_file_inputs_preserve_existing_and_absent_hosts',
       'test_schema_four_init_flags_and_derived_identifier_limits',
       'test_documented_journal_configuration_generates_without_signing']
result=unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(InstalledHostAcceptance(name) for name in names))
raise SystemExit(not result.wasSuccessful())
