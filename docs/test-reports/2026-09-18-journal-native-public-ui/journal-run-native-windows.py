from pathlib import Path
import subprocess,sys,json,time
from concurrent.futures import ThreadPoolExecutor,as_completed
root=Path('/Users/rcmerci/gh-repos/bonsai-ui')
output=root/'_build/validation/journal-native-windows'
output.mkdir(parents=True,exist_ok=True)
make=(root/'Makefile').read_text().split('swift-test: native-test protocol-check xcode-test\n',1)[1].split('\nnative-object:',1)[0]
scripts=[line.strip().split()[1] for line in make.splitlines() if line.strip().startswith('python3 native/test/test_')]
results=[]
def verify(script):
    log=output/(Path(script).stem+'.log')
    start=time.monotonic()
    with log.open('w') as stream:
        try: code=subprocess.run([sys.executable,'/tmp/journal-native-window-wrapper.py',script],cwd=root,stdout=stream,stderr=subprocess.STDOUT,timeout=1200).returncode
        except subprocess.TimeoutExpired: code=124
    return dict(script=script,status=code,seconds=round(time.monotonic()-start,2),log=str(log))
with ThreadPoolExecutor(max_workers=3) as pool:
    futures=[pool.submit(verify,script) for script in scripts]
    for future in as_completed(futures):
        result=future.result()
        results.append(result)
        (output/'results.json').write_text(json.dumps(results,indent=2))
        print(f'{len(results)}/{len(scripts)} {result["script"]}: '+('PASS' if result['status']==0 else f'FAIL {result["status"]}'),flush=True)
sys.exit(any(r['status']!=0 for r in results))
