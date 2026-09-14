"""Stage an OCaml complete object and link its macOS runtime dependencies statically."""
import argparse
from pathlib import Path
import shutil
import subprocess


def undefined_symbols(path):
    return subprocess.check_output(["xcrun", "nm", "-u", str(path)], text=True)


def system_libraries(path):
    return ["-lsqlite3"] if "_sqlite3_" in undefined_symbols(path) else []


def stage_object(source, destination):
    source = Path(source)
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if "___gmp" in undefined_symbols(source):
        directory = subprocess.check_output(["pkg-config", "--variable=libdir", "gmp"], text=True).strip()
        archive = Path(directory) / "libgmp.a"
        if not archive.is_file():
            raise RuntimeError(f"Missing static GMP archive: {archive}")
        subprocess.run(["xcrun", "clang", "-target", "arm64-apple-macos26.0", "-r",
                        "-Wl,-no_compact_unwind", str(source), str(archive), "-o", str(destination)], check=True)
    else:
        shutil.copyfile(source, destination)
    if "___gmp" in undefined_symbols(destination):
        raise RuntimeError("The staged native object still has unresolved GMP symbols")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("complete", type=Path)
    parser.add_argument("--dylib", type=Path, required=True)
    args = parser.parse_args()
    complete = stage_object(args.source, args.complete)
    subprocess.run(["xcrun", "clang", "-target", "arm64-apple-macos26.0", "-dynamiclib",
                    "-install_name", "@rpath/" + args.dylib.name, "-Wl,-no_compact_unwind", str(complete),
                    "-framework", "CoreFoundation", "-framework", "Security", "-lpthread",
                    *system_libraries(complete),
                    "-o", str(args.dylib)], check=True)


if __name__ == "__main__":
    main()
