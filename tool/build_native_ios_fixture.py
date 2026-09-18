"""Cross-compile the existing native test scenarios for a physical iOS host."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--findlib-config", type=Path, required=True)
    parser.add_argument("--framework-library", type=Path, required=True,
                        help="Current worktree's cross-built install/default.ios/lib")
    parser.add_argument("--ocamlfind", type=Path, required=True)
    parser.add_argument("--build-directory", type=Path, required=True)
    args = parser.parse_args()
    build = args.build_directory.resolve()
    build.mkdir(parents=True, exist_ok=True)
    library = args.framework_library.absolute()
    env = dict(os.environ, OCAMLFIND_CONF=str(args.findlib_config.resolve()),
               OCAMLPATH=str(library))
    findlib = [str(args.ocamlfind.resolve()), "-toolchain", "ios"]

    def run(arguments, **kwargs):
        return subprocess.run(arguments, cwd=build, env=env, check=True, **kwargs)

    selected = run([*findlib, "query", "bonsai_swiftui.protocol"],
                   capture_output=True, text=True).stdout.strip()
    if not Path(selected).is_relative_to(library):
        parser.error("findlib did not select the supplied current framework library")
    configuration = run([*findlib, "ocamlopt", "-config"],
                        capture_output=True, text=True).stdout
    if "-miphoneos-version-min=26.0" not in configuration:
        parser.error("the selected cross-compiler must target physical iOS 26.0")

    # Reuse the existing target's source inventory without changing Dune targets.
    # Dune stages its copy_files inputs; every module is then compiled for iOS.
    subprocess.run(["dune", "build", "native/test/runtime_fixture.exe.o"],
                   cwd=ROOT, check=True)
    target = (ROOT / "native/test/dune").read_text().split("(executable", 1)[1]
    modules = re.search(r"\(modules\s+([^)]*)\)", target).group(1).split()
    packages = re.search(r"\(libraries\s+([^)]*)\)", target).group(1).split()
    # Findlib requires explicit implementations of Dune's virtual libraries.
    packages = ["digestif.c", "mirage-ptime.unix", *packages]
    sources = []
    for module in modules:
        for suffix in (".mli", ".ml"):
            source = ROOT / "_build/default/native/test" / f"{module}{suffix}"
            if source.is_file():
                shutil.copyfile(source, build / source.name)
                sources.append(source.name)
    ordered = run([*findlib, "ocamldep", "-sort", *sources],
                  capture_output=True, text=True).stdout.split()
    compiler = [*findlib, "ocamlopt", "-thread", "-package", ",".join(packages)]
    for source in ordered:
        print(f"Compiling iOS fixture: {source}", flush=True)
        run([*compiler, "-c", source])
    objects = [str(Path(source).with_suffix(".cmx"))
               for source in ordered if source.endswith(".ml")]
    output = build / "runtime_fixture.o"
    run([*compiler, "-linkpkg", "-linkall", "-output-complete-obj",
         "-o", str(output), *objects])
    run([str(ROOT / "tool/ios/verify_complete_object.sh"),
         str(output), "IOS", "26.0", "arm64"])
    print(output)


if __name__ == "__main__":
    main()
