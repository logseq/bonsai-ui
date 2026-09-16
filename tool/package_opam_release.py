"""Package this worktree for opam consumers, without requiring a Git checkout.

The output contains one reproducible source archive and a repository for the
three public packages. By default the repository downloads the local archive;
--archive-url supplies the immutable download URL for a published release.
"""

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = ("bonsai_swiftui", "bonsai_swiftui_test", "bonsai_swiftui_tool")
SOURCE_DIRECTORIES = {"ocaml", "bonsai_swiftui_tool", "native", "swift", "protocol", "tool", "vendor", "examples"}
SOURCE_FILES = {"dune-project", "Package.swift", "LICENSE", ".ocamlformat", *(p + ".opam" for p in PACKAGES)}


def create_release(output, archive_url):
    manifests = {name: (ROOT / (name + ".opam")).read_text() for name in PACKAGES}
    versions = {re.search(r'^version: "([^"]+)"$', text, re.MULTILINE).group(1)
                for text in manifests.values()}
    if len(versions) != 1:
        raise ValueError("All public packages must have the same release version")
    version = versions.pop()
    if not re.fullmatch(r"[A-Za-z0-9.+~_-]+", version):
        raise ValueError("Invalid release version")
    files = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=ROOT,
    ).decode().split("\0")
    sources = sorted({name for name in files if name
                      and (name in SOURCE_FILES or Path(name).parts[0] in SOURCE_DIRECTORIES)
                      and (ROOT / name).is_file()})
    output.mkdir(parents=True, exist_ok=False)
    archive = output / f"bonsai-swiftui-{version}.tar.gz"
    with archive.open("wb") as file:
        with gzip.GzipFile(filename="", mode="wb", fileobj=file, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w") as tar:
                for name in sources:
                    path = ROOT / name
                    if path.is_symlink():
                        raise ValueError(f"Release sources must not be symlinks: {name}")
                    info = tar.gettarinfo(str(path), arcname=f"bonsai-swiftui-{version}/{name}")
                    info.uid = info.gid = info.mtime = 0
                    info.uname = info.gname = ""
                    info.mode = 0o755 if info.mode & 0o111 else 0o644
                    with path.open("rb") as source:
                        tar.addfile(info, source)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    url = archive_url or archive.as_uri()
    repository = output / "repository"
    repository.mkdir()
    (repository / "repo").write_text('opam-version: "2.0"\n')
    for name, manifest in manifests.items():
        package = repository / "packages" / name / f"{name}.{version}"
        package.mkdir(parents=True)
        (package / "opam").write_text(
            manifest.rstrip() + '\nurl {\n  src: ' + json.dumps(url)
            + '\n  checksum: "sha256=' + digest + '"\n}\n'
        )
    print(f"Archive: {archive}\nSHA256: {digest}\nOpam repository: {repository}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="New output directory")
    parser.add_argument("--archive-url", help="Published source archive URL")
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        parser.error(f"Output already exists: {output}")
    try:
        create_release(output, args.archive_url)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
