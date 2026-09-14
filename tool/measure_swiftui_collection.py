"""Build and measure the real mixed-collection fixture in six fresh processes."""

from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "_build/validation/collection-performance"


def run(command, **kwargs):
    return subprocess.run(command, cwd=ROOT, check=True, **kwargs)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "summary.json").unlink(missing_ok=True)
    fixture = ROOT / "_build/default/native/test/libruntime_fixture.dylib"
    if not fixture.is_file():
        raise SystemExit("Build native/test/libruntime_fixture.dylib with Dune first")
    with (OUTPUT / "build.log").open("w") as log:
        run(["swift", "build", "--scratch-path", "_build/swift", "--target", "BonsaiSwiftUI"],
            stdout=log, stderr=subprocess.STDOUT)
        build = Path(run(["swift", "build", "--scratch-path", "_build/swift", "--show-bin-path"],
                         capture_output=True, text=True).stdout.strip())
        # SwiftPM can retain obsolete objects after a source file is removed.
        # Link only outputs belonging to the current compilation graph.
        outputs = json.loads((build / "BonsaiSwiftUI.build/output-file-map.json").read_text())
        objects = sorted(Path(value["object"]) for value in outputs.values() if "object" in value)
        if not objects:
            raise RuntimeError("Missing Swift library objects")
        binary = OUTPUT / "measure-collection"
        command = ["xcrun", "swiftc", "-parse-as-library", "-target", "arm64-apple-macos26.0",
                   "-I", str(build / "Modules"), "-I", str(ROOT / "native/src"),
                   str(ROOT / "tool/measure_swiftui_collection.swift"),
                   *map(str, objects), "-L", str(fixture.parent), "-lruntime_fixture",
                   "-Xlinker", "-rpath", "-Xlinker", str(fixture.parent), "-o", str(binary)]
        run(command, stdout=log, stderr=subprocess.STDOUT)
    reports = []
    for axis in ["vertical", "horizontal"]:
        for repetition in range(1, 4):
            name = f"{axis}-{repetition}"
            with (OUTPUT / f"{name}.json").open("w") as out, (OUTPUT / f"{name}.log").open("w") as log:
                run([str(binary), axis], stdout=out, stderr=log)
            report = json.loads((OUTPUT / f"{name}.json").read_text())
            reports.append(report)
            print(f"Completed {name}: {len(report['samples'])} verified updates", flush=True)
    summary = {}
    for axis in ["vertical", "horizontal"]:
        axis_reports = [report for report in reports if report["axis"] == axis]
        phases = {}
        for phase in ["initial", "adjacent", "distant"]:
            samples = [sample for report in axis_reports for sample in report["samples"]
                       if sample["phase"] == phase]
            metrics = {}
            for key in ["pump_ms", "decode_apply_ms", "synchronous_layout_display_ms", "ack_ms", "total_ms"]:
                values = sorted(sample[key] for sample in samples)
                metrics[key] = {"median": statistics.median(values),
                                "p95": values[math.ceil(len(values) * .95) - 1], "max": max(values)}
            phases[phase] = {"count": len(samples), "timings": metrics,
                             "max_frame_bytes": max(sample["frame_bytes"] for sample in samples),
                             "max_render_nodes": max(sample["render_nodes"] for sample in samples),
                             "max_materialized_rows": max(sample["materialized_rows"] for sample in samples)}
        summary[axis] = {"phases": phases, "memory_runs": [
            {"before_open_bytes": report["resident_before_open_bytes"],
             "after_initial_bytes": report["samples"][0]["resident_bytes"],
             "peak_sampled_bytes": max(sample["resident_bytes"] for sample in report["samples"]),
             "after_runtime_close_bytes": report["resident_after_runtime_close_bytes"]}
            for report in axis_reports]}
    metadata = {
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "source_revision": run(["git", "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip(),
        "dirty_worktree": bool(run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout),
        "host": run(["sw_vers"], capture_output=True, text=True).stdout,
        "compiler": run(["xcrun", "swiftc", "--version"], capture_output=True, text=True).stdout,
        "compile_command": command,
        "sha256": {str(path.relative_to(ROOT)): digest(path) for path in [
            fixture, binary, ROOT / "tool/measure_swiftui_collection.swift",
            ROOT / "tool/measure_swiftui_collection.py", ROOT / "examples/gallery/ocaml/mixed_collection_catalog.ml"]},
        "scope": reports[0]["scope"], "summary": summary,
        "raw_reports_sha256": {path.name: digest(path) for path in sorted(OUTPUT.glob("*-?.json"))},
    }
    (OUTPUT / "summary.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Report: {OUTPUT / 'summary.json'}")


if __name__ == "__main__":
    main()
