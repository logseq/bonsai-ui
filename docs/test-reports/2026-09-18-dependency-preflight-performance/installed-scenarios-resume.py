from pathlib import Path
import json, os
from measure import ROOT, OUT, measure, inputs
before=inputs()
for label, relative, addition in [
    ('ocaml-edit','app/journal_symbols.ml', b'\n(* Dependency cache acceptance: application-only edit. *)\n'),
    ('swift-edit','swift/App.swift', b'\n// Dependency cache acceptance: application-only edit.\n'),
    ('lock-edit','swift-packages/Package.resolved', b'\n\n')]:
    path=ROOT/relative
    original=path.read_bytes(); stat=path.stat()
    changed=original+addition
    path.write_bytes(changed)
    try:
        measure('installed-'+label, installed=True)
    finally:
        if path.read_bytes()!=changed:
            raise RuntimeError('Concurrent source edit detected; refusing to overwrite '+str(path))
        path.write_bytes(original)
        os.utime(path,ns=(stat.st_atime_ns,stat.st_mtime_ns))
measure('installed-lock-restored', installed=True)
measure('installed-platform-profile-switch', installed=True, platform='macos', profile='debug')
for index in range(1,6): measure(f'installed-final-warm-{index}', installed=True)
(OUT/'scenario-restoration.json').write_text(json.dumps({'all_input_hashes_restored':before==inputs()},indent=2))
assert before==inputs()
