from pathlib import Path
import hashlib, importlib.util, json, subprocess, time
out=Path('/tmp/bonsai-preflight-20260918')
root=Path('/Users/rcmerci/gh-repos/logseq_journal')
framework=Path('/Users/rcmerci/gh-repos/bonsai-ui')
spec=importlib.util.spec_from_file_location('baseline_host',out/'baseline_host.py')
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
original_run=subprocess.run
samples=[]
active=[]
index=0
def traced(command,**kwargs):
    started=time.monotonic()
    result=original_run(command,**kwargs)
    seconds=time.monotonic()-started
    record={'command':command,'seconds':seconds,'exit':result.returncode}
    active.append(record)
    (out/f'baseline-preflight-{index}-{len(active)}.log').write_text((result.stdout or '')+(result.stderr or ''))
    (out/f'baseline-preflight-{index}-progress.json').write_text(json.dumps(active,indent=2))
    print(json.dumps(record),flush=True)
    return result
module.subprocess.run=traced
options=dict(framework_root=framework,application_root=root,host_directory=out/'baseline-published-host',product_name='BonsaiLogseqJournal',bundle_identifiers={'macos':'com.logseq.journal','ios':'com.example.bonsaiFlutterLogseqJournalHost'},ios_minimum_version='26.0',entitlements={'macos':{'debug':'config/entitlements/macos-debug-profile.entitlements','profile':'config/entitlements/macos-debug-profile.entitlements','release':'config/entitlements/macos-release.entitlements'}},swift_packages=[{'id':'amplify-swift','url':'https://github.com/aws-amplify/amplify-swift.git','requirement':{'exact':'2.61.0'},'products':[{'name':'AWSCognitoAuthPlugin','platforms':['ios','macos']},{'name':'Amplify','platforms':['ios','macos']}]}])
for index in range(1,2):
    active=[]
    started=time.monotonic()
    before=(root/'swift-packages/Package.resolved').read_bytes()
    try:
        module.resolve_packages(locked=True,**options)
        status='passed'
    except Exception as error:
        status=str(error)
    sample={'sample':index,'seconds':time.monotonic()-started,'status':status,'commands':active,'lock_unchanged':before==(root/'swift-packages/Package.resolved').read_bytes(),'lock_sha256':hashlib.sha256(before).hexdigest()}
    samples.append(sample)
    (out/'baseline-preflight.json').write_text(json.dumps(samples,indent=2))
    print(json.dumps(sample),flush=True)
    if status!='passed': break
