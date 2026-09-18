"""Exercise dependency preflight with a real local Git package and real Xcode."""
from pathlib import Path
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / 'tool/swiftui_xcode_host.py'
CLI = ROOT / '_build/default/bonsai_swiftui_tool/bin/main.exe'


class DependencyCacheTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = tempfile.TemporaryDirectory(prefix='bonsai dependency fixture ')
        cls.repo = Path(cls.fixture.name) / 'cache-fixture'
        cls.repo.mkdir()
        (cls.repo / 'Sources/CacheFixture').mkdir(parents=True)
        (cls.repo / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CacheFixture", products: [.library(name: "CacheFixture", targets: ["CacheFixture"])], targets: [.target(name: "CacheFixture")])
''')
        (cls.repo / 'Sources/CacheFixture/Value.swift').write_text('public let fixtureValue = 42\n')
        for args in [('init',), ('add', '.'), ('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'fixture'), ('tag', '1.0.0')]:
            subprocess.run(['git', '-C', str(cls.repo), *args], check=True, capture_output=True)
        cls.revision = subprocess.check_output(['git', '-C', str(cls.repo), 'rev-parse', 'HEAD'], text=True).strip()

    @classmethod
    def tearDownClass(cls):
        cls.fixture.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='bonsai dependency consumer ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'swift').mkdir()
        (self.root / 'swift/App.swift').write_text('import SwiftUI\n')
        self.lock = self.root / 'swift-packages/Package.resolved'
        self.lock.parent.mkdir()
        self.lock.write_text(json.dumps({'version': 2, 'pins': [{'identity': 'cache-fixture', 'kind': 'remoteSourceControl', 'location': self.repo.as_uri(), 'state': {'revision': self.revision, 'version': '1.0.0'}}]}))
        self.trace = self.root / 'trace.jsonl'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        # Trace actual tool execution; no resolver/build results are mocked.
        xcode = shutil.which('xcodebuild')
        wrapper = self.bin / 'xcodebuild'
        wrapper.write_text(f'''#!{sys.executable}
import json, os, pathlib, subprocess, sys, time
args=sys.argv[1:]
trace=pathlib.Path(os.environ['TRACE'])
with trace.open('a') as f: f.write(json.dumps({{'event':'start','pid':os.getpid(),'args':args,'time':time.monotonic()}})+'\\n')
gate=os.environ.get('PROBE_GATE')
if gate and 'build' in args:
    pathlib.Path(gate+'.waiting').touch()
    while not pathlib.Path(gate).exists(): time.sleep(0.05)
cache=os.environ.get('ISOLATED_PACKAGE_CACHE')
if cache and '-project' in args: args += ['-packageCachePath', cache]
r=subprocess.run([{xcode!r},*args])
if '-version' in args: print(os.environ.get('TOOLCHAIN_STAMP',''))
with trace.open('a') as f: f.write(json.dumps({{'event':'end','pid':os.getpid(),'args':args,'time':time.monotonic()}})+'\\n')
sys.exit(r.returncode)
''')
        wrapper.chmod(0o755)
        self.env = {**os.environ, 'PATH': str(self.bin)+os.pathsep+os.environ['PATH'], 'TRACE': str(self.trace), 'BONSAI_SWIFTUI_SOURCE_ROOT': str(ROOT)}
        self.cache = self.root / '_build/bonsai-swiftui/dependencies'

    def command(self, platform='ios', profile='release', resolve=False, product='CacheFixture', framework=ROOT, minimum='18.0', version='1.0.0'):
        return [sys.executable, str(GENERATOR), '--framework-root', str(framework), '--application-root', str(self.root), '--host-directory', str(self.root/'apple'), '--product-name', 'CacheApp', '--macos-bundle-identifier', 'org.example.cache', '--ios-bundle-identifier', 'org.example.cache.ios', '--ios-minimum-version', minimum, '--swift-package', 'fixture', self.repo.as_uri(), 'exact', version, '--swift-product', 'fixture', product, 'macos,ios', *(['--resolve-packages'] if resolve else ['--locked-preflight', '--platform', platform, '--profile', profile])]

    def run_probe(self, success=True, env=None, **kwargs):
        result = subprocess.run(self.command(**kwargs), env=env or self.env, capture_output=True, text=True, timeout=180)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout+result.stderr)
        return result

    def operations(self):
        if not self.trace.exists(): return []
        return [e for e in map(json.loads, self.trace.read_text().splitlines()) if e['event']=='start' and ('build' in e['args'] or '-resolvePackageDependencies' in e['args'])]

    def protected_snapshot(self):
        return {str(p.relative_to(self.root)): (p.read_bytes(), p.stat().st_mtime_ns) for base in ('apple', 'swift-packages') for p in (self.root/base).rglob('*') if p.is_file()}

    def test_selected_configuration_and_warm_hit_survive_source_edits(self):
        self.run_probe()
        ops = self.operations()
        self.assertEqual(len(ops), 2)
        for e in ops:
            self.assertEqual(e['args'][e['args'].index('-scheme')+1], 'CacheApp-iOS')
            self.assertEqual(e['args'][e['args'].index('-configuration')+1], 'Release')
            self.assertNotIn('-disablePackageRepositoryCache', e['args'])
        before = self.protected_snapshot()
        (self.root/'swift/App.swift').write_text('import SwiftUI\n// application edit\n')
        (self.root/'app').mkdir()
        (self.root/'app/main.ml').write_text('let value = 42\n')
        result = self.run_probe()
        self.assertIn('cache hit', result.stderr)
        self.assertEqual(len(self.operations()), 2)
        self.assertEqual(before.keys(), self.protected_snapshot().keys())
        self.assertEqual(self.lock.read_bytes(), before['swift-packages/Package.resolved'][0])

    def test_configuration_platform_toolchain_and_deployment_invalidate(self):
        self.run_probe()
        for kwargs, env in [({'profile':'debug'}, self.env), ({'platform':'macos'}, self.env), ({'minimum':'26.0'}, self.env), ({'minimum':'26.0'}, {**self.env,'TOOLCHAIN_STAMP':'changed'})]:
            count = len(self.operations())
            self.run_probe(env=env, **kwargs)
            self.assertEqual(len(self.operations()), count+2)

    def test_missing_or_corrupt_records_and_outputs_revalidate(self):
        self.run_probe()
        records = list((self.cache/'validation').rglob('*.json'))
        self.assertEqual(len(records), 1)
        for action in ('corrupt', 'delete', 'outputs'):
            count = len(self.operations())
            if action == 'corrupt': records[0].write_text('{')
            elif action == 'delete': records[0].unlink()
            else: shutil.rmtree(self.cache/'probes/ios/release/DerivedData')
            self.run_probe()
            self.assertEqual(len(self.operations()), count+2)

    def test_invalid_local_lock_does_not_create_cache(self):
        self.lock.write_text('{')
        before = self.protected_snapshot()
        self.run_probe(success=False)
        self.assertFalse(self.cache.exists())
        self.assertEqual(self.operations(), [])
        self.assertEqual(before, self.protected_snapshot())

    def test_remote_failure_preserves_host_and_lock_and_cannot_poison_hit(self):
        self.run_probe()
        before = self.protected_snapshot()
        self.run_probe(product='MissingProduct', success=False)
        self.assertEqual(before, self.protected_snapshot())
        self.assertIn('cache hit', self.run_probe().stderr)
        data = json.loads(self.lock.read_text())
        data['pins'][0]['state']['revision'] = '0'*40
        self.lock.write_text(json.dumps(data))
        before = self.protected_snapshot()
        self.run_probe(success=False)
        self.assertEqual(before, self.protected_snapshot())

    def test_explicit_resolution_checks_both_platforms_and_seeds_debug(self):
        self.run_probe(resolve=True)
        self.assertEqual(len(self.operations()), 4)
        self.run_probe(platform='ios', profile='debug')
        self.run_probe(platform='macos', profile='debug')
        self.assertEqual(len(self.operations()), 4)
        self.run_probe(resolve=True)
        self.assertEqual(len(self.operations()), 8)

    def test_concurrent_probes_share_one_validation(self):
        command = self.command()
        with subprocess.Popen(command, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as a, subprocess.Popen(command, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as b:
            for process in (a,b):
                out, err = process.communicate(timeout=180)
                self.assertEqual(process.returncode,0,out+err)
        self.assertEqual(len(self.operations()),2)

    def test_interrupted_validation_does_not_publish_success(self):
        gate = self.root/'gate'
        process = subprocess.Popen(self.command(), env={**self.env,'PROBE_GATE':str(gate)}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        try:
            deadline=time.monotonic()+60
            while not gate.with_suffix('.waiting').exists() and process.poll() is None and time.monotonic()<deadline: time.sleep(.1)
            self.assertTrue(gate.with_suffix('.waiting').exists())
        finally:
            if process.poll() is None: os.killpg(process.pid,signal.SIGKILL)
            process.communicate(timeout=10)
        self.assertEqual(list((self.cache/'validation').rglob('*.json')),[])
        self.run_probe()
        self.assertIn('cache hit',self.run_probe().stderr)

    def test_framework_manifest_generator_and_relocation_invalidate(self):
        framework=self.root/'framework'
        framework.mkdir()
        # The isolated probe does not link the framework, but Xcode reads its manifest.
        shutil.copy(ROOT/'Package.swift', framework/'Package.swift')
        for name in ('swift','native','tool'):
            (framework/name).symlink_to(ROOT/name, target_is_directory=True)
        self.run_probe(framework=framework)
        with (framework/'Package.swift').open('a') as f: f.write('\n// changed local manifest\n')
        self.run_probe(framework=framework)
        self.assertEqual(len(self.operations()),4)
        relocated=self.root/'relocated-framework'
        framework.rename(relocated)
        self.run_probe(framework=relocated)
        self.assertEqual(len(self.operations()),6)

    def wait_for_gate(self, process, gate):
        deadline = time.monotonic() + 90
        while not gate.with_suffix('.waiting').exists() and process.poll() is None and time.monotonic() < deadline:
            time.sleep(.1)
        self.assertTrue(gate.with_suffix('.waiting').exists())

    def test_clean_waits_for_preflight_and_keeps_guard_inode(self):
        subprocess.run([str(CLI), 'init', '--name', 'cache_app'], cwd=self.root, env=self.env, check=True, capture_output=True)
        gate = self.root / 'gate'
        with subprocess.Popen(self.command(), env={**self.env, 'PROBE_GATE': str(gate)}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as build:
            try:
                self.wait_for_gate(build, gate)
                guard = self.root / '_build/.bonsai-swiftui-apple.lock'
                inode = guard.stat().st_ino
                with subprocess.Popen([str(CLI), 'clean', 'iphoneos'], cwd=self.root, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as clean:
                    time.sleep(.3)
                    status = clean.poll()
                    gate.touch()
                    self.assertIsNone(status, 'clean must wait for the active preflight')
                    for process in (build, clean):
                        out, err = process.communicate(timeout=180)
                        self.assertEqual(process.returncode, 0, out + err)
                self.assertFalse((self.cache / 'validation/ios').exists())
                self.assertFalse((self.cache / 'probes/ios').exists())
                self.assertTrue((self.cache / 'packages').exists())
                self.assertEqual(guard.stat().st_ino, inode)
            finally:
                gate.touch()

    def test_resolution_waits_for_preflight(self):
        gate = self.root / 'gate'
        with subprocess.Popen(self.command(), env={**self.env, 'PROBE_GATE': str(gate)}, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as build:
            try:
                self.wait_for_gate(build, gate)
                with subprocess.Popen(self.command(resolve=True), env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as resolve:
                    time.sleep(.3)
                    status = resolve.poll()
                    count = len(self.operations())
                    gate.touch()
                    self.assertIsNone(status)
                    self.assertEqual(count, 2)
                    for process in (build, resolve):
                        out, err = process.communicate(timeout=180)
                        self.assertEqual(process.returncode, 0, out + err)
                self.assertEqual(len(self.operations()), 6)
            finally:
                gate.touch()

    def test_generator_and_application_relocation_invalidate(self):
        self.run_probe()
        generator = self.root / 'generator.py'
        generator.write_bytes(GENERATOR.read_bytes() + b'\n# changed generator\n')
        command = self.command()
        command[1] = str(generator)
        result = subprocess.run(command, env=self.env, capture_output=True, text=True, timeout=180)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(self.operations()), 4)
        relocated = self.root.with_name(self.root.name + '-relocated')
        self.root.rename(relocated)
        self.addCleanup(shutil.rmtree, relocated, True)
        self.root = relocated
        self.env.update(PATH=str(relocated/'bin')+os.pathsep+os.environ['PATH'], TRACE=str(relocated/'trace.jsonl'))
        self.trace = relocated / 'trace.jsonl'
        self.run_probe()
        self.assertEqual(len(self.operations()), 6)

    def test_cache_symlink_is_rejected_without_writing_external_files(self):
        outside = self.root / 'outside'
        outside.mkdir()
        self.cache.parent.mkdir(parents=True)
        self.cache.symlink_to(outside, target_is_directory=True)
        self.run_probe(success=False)
        self.assertEqual(list(outside.iterdir()), [])
        self.assertEqual(self.operations(), [])

    def test_offline_warm_preflight_and_read_only_host_check(self):
        self.run_probe()
        before = {str(p): (p.read_bytes(),p.stat().st_mtime_ns) for p in self.cache.rglob('*') if p.is_file() and 'DerivedData' not in p.parts and 'packages' not in p.parts}
        command = self.command()
        command = command[:command.index('--locked-preflight')] + ['--check']
        result = subprocess.run(command, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        after = {str(p): (p.read_bytes(),p.stat().st_mtime_ns) for p in self.cache.rglob('*') if p.is_file() and 'DerivedData' not in p.parts and 'packages' not in p.parts}
        self.assertEqual(before, after)
        result = subprocess.run(['sandbox-exec', '-p', '(version 1)(allow default)(deny network-outbound)', *self.command()], env=self.env, capture_output=True, text=True, timeout=180)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn('cache hit', result.stderr)
        self.assertEqual(len(self.operations()), 2)

    def isolated_repository(self):
        original = self.repo
        self.repo = self.root / 'dependency/cache-fixture'
        shutil.copytree(original, self.repo)
        data = json.loads(self.lock.read_text())
        data['pins'][0]['location'] = self.repo.as_uri()
        self.lock.write_text(json.dumps(data))

    def commit_dependency(self, tag):
        for args in [('add', '.'), ('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'dependency update'), ('tag', '-f', tag)]:
            subprocess.run(['git', '-C', str(self.repo), *args], check=True, capture_output=True)
        return subprocess.check_output(['git', '-C', str(self.repo), 'rev-parse', 'HEAD'], text=True).strip()

    def test_unsupported_selected_platform_preserves_outputs(self):
        self.isolated_repository()
        source = self.repo / 'Sources/CacheFixture/Value.swift'
        source.write_text('#if os(iOS)\n#error("CacheFixture does not support iOS")\n#endif\npublic let fixtureValue = 42\n')
        revision = self.commit_dependency('1.0.0')
        data = json.loads(self.lock.read_text())
        data['pins'][0]['state']['revision'] = revision
        self.lock.write_text(json.dumps(data))
        before = self.protected_snapshot()
        result = self.run_probe(success=False)
        self.assertIn('CacheFixture does not support iOS', result.stderr)
        self.assertEqual(before, self.protected_snapshot())
        self.assertEqual(list((self.cache/'validation').rglob('*.json')), [])

    def test_changed_valid_pin_revalidates_release(self):
        self.isolated_repository()
        self.run_probe()
        source = self.repo / 'Sources/CacheFixture/Value.swift'
        source.write_text('public let fixtureValue = 43\n')
        revision = self.commit_dependency('1.0.1')
        self.run_probe(resolve=True, version='1.0.1')
        self.assertEqual(json.loads(self.lock.read_text())['pins'][0]['state']['revision'], revision)
        count = len(self.operations())
        self.assertIn('cache miss', self.run_probe(version='1.0.1').stderr)
        self.assertEqual(len(self.operations()), count+2)
        self.assertIn('cache hit', self.run_probe(version='1.0.1').stderr)

    def test_empty_cache_offline_reports_missing_sources(self):
        data = {'version': 2, 'pins': [{'identity': 'swift-collections', 'kind': 'remoteSourceControl', 'location': 'https://github.com/apple/swift-collections.git', 'state': {'revision': '671108c96644956dddcd89dd59c203dcdb36cec7', 'version': '1.1.4'}}]}
        self.lock.write_text(json.dumps(data))
        command = self.command(product='OrderedCollections', version='1.1.4')
        command[command.index('--swift-package')+2] = data['pins'][0]['location']
        env = {**self.env, 'ISOLATED_PACKAGE_CACHE': str(self.root/'empty-repository-cache')}
        before = self.protected_snapshot()
        result = subprocess.run(['sandbox-exec','-p','(version 1)(allow default)(deny network-outbound)',*command], env=env, capture_output=True, text=True, timeout=180)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Swift package validation failed',result.stderr)
        self.assertEqual(before,self.protected_snapshot())
        self.assertEqual(list((self.cache/'validation').rglob('*.json')),[])

    def test_incomplete_transitive_lock_is_rejected_with_existing_checkout_state(self):
        self.isolated_repository()
        transitive_root = tempfile.TemporaryDirectory(prefix='bonsai-transitive-')
        self.addCleanup(transitive_root.cleanup)
        transitive = Path(transitive_root.name) / 'transitive-fixture'
        (transitive/'Sources/TransitiveFixture').mkdir(parents=True)
        (transitive/'Package.swift').write_text('// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: "TransitiveFixture", products: [.library(name: "TransitiveFixture", targets: ["TransitiveFixture"])], targets: [.target(name: "TransitiveFixture")])\n')
        (transitive/'Sources/TransitiveFixture/Value.swift').write_text('public let transitiveValue = 42\n')
        for args in [('init',), ('add', '.'), ('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'transitive'), ('tag', '1.0.0')]:
            subprocess.run(['git','-C',str(transitive),*args],check=True,capture_output=True)
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            port = listener.getsockname()[1]
        daemon = subprocess.Popen(['git', 'daemon', '--reuseaddr', '--export-all', '--listen=127.0.0.1', f'--port={port}', '--base-path='+transitive_root.name, transitive_root.name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        def stop_daemon():
            daemon.terminate()
            daemon.wait(timeout=10)
        self.addCleanup(stop_daemon)
        deadline = time.monotonic()+5
        while True:
            try:
                with socket.create_connection(('127.0.0.1',port),timeout=.2): break
            except OSError:
                if daemon.poll() is not None or time.monotonic() > deadline: self.fail('Git fixture daemon did not start')
                time.sleep(.05)
        transitive_url = f'git://127.0.0.1:{port}/transitive-fixture'
        manifest = self.repo/'Package.swift'
        manifest.write_text('// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: "CacheFixture", products: [.library(name: "CacheFixture", targets: ["CacheFixture"])], dependencies: [.package(url: "'+transitive_url+'", exact: "1.0.0")], targets: [.target(name: "CacheFixture", dependencies: [.product(name: "TransitiveFixture", package: "transitive-fixture")])])\n')
        (self.repo/'Sources/CacheFixture/Value.swift').write_text('import TransitiveFixture\npublic let fixtureValue = transitiveValue\n')
        self.commit_dependency('1.0.0')
        self.run_probe(resolve=True)
        self.run_probe()
        complete = self.lock.read_bytes()
        data = json.loads(complete)
        self.assertEqual(len(data['pins']),2)
        data['pins'] = [p for p in data['pins'] if p['identity'] != 'transitive-fixture']
        self.lock.write_text(json.dumps(data))
        before = self.protected_snapshot()
        result = self.run_probe(success=False)
        self.assertIn('resolve-packages', result.stderr)
        self.assertEqual(before, self.protected_snapshot())
        self.lock.write_bytes(complete)
        self.run_probe()


if __name__ == '__main__':
    unittest.main(verbosity=2)
