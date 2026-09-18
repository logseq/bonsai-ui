from pathlib import Path
import subprocess, sys, json, re, time, fcntl
root=Path('/Users/rcmerci/gh-repos/bonsai-ui')
output=root/'_build/validation/journal-isolated-swift'
output.mkdir(parents=True,exist_ok=True)
listing=subprocess.run(['swift','test','list','--scratch-path','_build/swift'],cwd=root,text=True,capture_output=True,check=True)
(output/'test-list.txt').write_text(listing.stdout)
ids=[line.strip() for line in listing.stdout.splitlines() if line.startswith('BonsaiSwiftUITests.')]
suites=sorted({line.split('.',1)[1].split('/')[0] for line in ids} - {'NativeRuntimeTests'})
plans=[(suite, ['--filter',suite,'--skip','NativeRuntimeTests']) for suite in suites]
plans += [('runtime-'+line.split('/',1)[1].split('(')[0],['--filter',line.split('/',1)[1].split('(')[0]]) for line in ids if '.NativeRuntimeTests/' in line]
# Preserve one invocation per test declaration, including its parameterized cases.
plans=list({name:(name,args) for name,args in plans}.values())
results=[]
command='from tool.run_swift_tests import run_swift_tests; import sys; sys.exit(run_swift_tests(["swift","test","--scratch-path","_build/swift","--skip-build","--no-parallel",*sys.argv[1:]]))'
while not (root/"_build/validation/journal-final-ui/allow-native-ui").exists(): time.sleep(0.25)
for index,(name,args) in enumerate(plans):
    log=output/(name+'.log')
    start=time.monotonic()
    with log.open('w') as stream, (root/'_build/validation/journal-final-ui/exclusive.lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        try:
            code=subprocess.run([sys.executable,'-c',command,*args],cwd=root,stdout=stream,stderr=subprocess.STDOUT,timeout=600).returncode
        except subprocess.TimeoutExpired:
            code=124
    text=log.read_text()
    counts=re.findall(r'Test run with (\d+) tests? (?:in (\d+) suites? )?passed',text)
    results.append(dict(name=name,status=code,seconds=round(time.monotonic()-start,2),completed_count=int(counts[-1][0]) if counts else None,log=str(log)))
    (output/'results.json').write_text(json.dumps(results,indent=2))
    print(f'{index+1}/{len(plans)} {name}: '+('PASS' if code==0 else f'FAIL {code}'),flush=True)
print(json.dumps({'invocations':len(results),'passed':sum(r['status']==0 for r in results),'failed':[r['name'] for r in results if r['status']!=0]},indent=2),flush=True)
sys.exit(any(r['status']!=0 for r in results))
