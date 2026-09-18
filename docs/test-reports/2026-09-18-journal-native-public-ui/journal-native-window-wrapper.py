import fcntl, subprocess, sys, runpy, time
from pathlib import Path
folder=Path('/Users/rcmerci/gh-repos/bonsai-ui/_build/validation/journal-final-ui')
folder.mkdir(parents=True,exist_ok=True)
original=subprocess.run
def run(command,*args,**kwargs):
    if '/Contents/MacOS/' not in str(command[0]):
        return original(command,*args,**kwargs)
    while not (folder/'allow-native-ui').exists(): time.sleep(0.25)
    with (folder/'exclusive.lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        return original(command,*args,**kwargs)
subprocess.run=run
script=sys.argv[1]
sys.argv=[script,*sys.argv[2:]]
runpy.run_path(script,run_name='__main__')
