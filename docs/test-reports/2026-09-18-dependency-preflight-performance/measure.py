from pathlib import Path
import hashlib,json,os,re,subprocess,time
ROOT=Path('/Users/rcmerci/gh-repos/logseq_journal')
FRAMEWORK=Path('/Users/rcmerci/gh-repos/bonsai-ui')
OUT=Path('/tmp/bonsai-preflight-20260918')
def inputs():
    return {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [ROOT/'bonsai-swiftui.sexp',ROOT/'swift-packages/Package.resolved',*sorted((ROOT/'app').glob('*.ml')), *sorted((ROOT/'swift').glob('*.swift'))]}
def measure(label, *, installed=False, platform='ios', profile='release', offline=False):
    env=dict(os.environ)
    env.pop('BONSAI_SWIFTUI_SOURCE_ROOT',None)
    cli='bonsai-swiftui' if installed else str(FRAMEWORK/'_build/default/bonsai_swiftui_tool/bin/main.exe')
    if not installed: env['BONSAI_SWIFTUI_SOURCE_ROOT']=str(FRAMEWORK)
    command=[cli,'build',platform,'--profile',profile,'--no-codesign']
    if offline: command=['sandbox-exec','-p','(version 1)(allow default)(deny network-outbound)',*command]
    before=inputs(); started=time.monotonic()
    with (OUT/(label+'.log')).open('w') as log:
        result=subprocess.run(command,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
    seconds=time.monotonic()-started
    log=(OUT/(label+'.log')).read_text()
    generator=(Path('/Users/rcmerci/.opam/bonsai-ui/share/bonsai_swiftui_tool/framework') if installed else FRAMEWORK)/'tool/swiftui_xcode_host.py'
    record={'generator_sha256':hashlib.sha256(generator.read_bytes()).hexdigest(),'label':label,'command':command,'seconds':seconds,'exit':result.returncode,'phases':re.findall(r'bonsai-swiftui: ([^\n]+): ([0-9.]+)s',log),'inputs_unchanged':before==inputs(),'input_hashes':before,'cache':re.findall(r'bonsai-swiftui: dependency cache (?:hit|miss)[^\n]+',log),'disk':subprocess.run(['du','-sk',str(ROOT/'_build/bonsai-swiftui/dependencies'),str(ROOT/'apple/DerivedData')],capture_output=True,text=True).stdout}
    (OUT/(label+'.json')).write_text(json.dumps(record,indent=2))
    print(json.dumps({k:v for k,v in record.items() if k!='input_hashes'}),flush=True)
    if result.returncode: raise RuntimeError(label+' failed; see '+str(OUT/(label+'.log')))
    return record
if __name__=='__main__':
    measure('optimized-warm-6')
    subprocess.run(['python3',str(OUT/'baseline-preflight.py')],check=True)
