"""Emit native library search flags for the supported Apple target context."""
import json
import subprocess
import sys

sdk = {"default": "macosx", "default.ios": "iphoneos"}[sys.argv[1]]
root = subprocess.check_output(["xcrun", "--sdk", sdk, "--show-sdk-path"], text=True).strip()
print("(" + json.dumps("-L" + root + "/usr/lib", ensure_ascii=False) + ")")
