"""Run a disposable public-API consumer using the installed CLI/framework only."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
host = Path(tempfile.mkdtemp(prefix="bonsai-installed-shutdown-"))
env = {key: value for key, value in os.environ.items()
       if key not in ("BONSAI_SWIFTUI_SOURCE_ROOT", "OCAMLPATH")}

def cli(*args, timeout=300):
    result = subprocess.run(["opam", "exec", "--switch=bonsai-ui", "--", "bonsai-swiftui", *args],
                            cwd=host, env=env, capture_output=True, text=True, timeout=timeout)
    with (REPORT / "installed-probe-build.log").open("a") as log:
        log.write(f"COMMAND: {args}\n{result.stdout}\n{result.stderr}\n")
    if result.returncode:
        raise RuntimeError((result.stdout + result.stderr)[-8000:])
    return result

cli("init", "--name", "shutdown_probe", "--macos-bundle-identifier", "org.example.bonsai.shutdownprobe",
    "--ios-bundle-identifier", "org.example.bonsai.shutdownprobe.ios")
fixture = (ROOT / "native/test/runtime_fixture.ml").read_text()
fixture = "module Ui = Bonsai_swiftui_ui\n" + fixture[fixture.index("let shutdown_audit"):]
fixture = fixture.replace("~handle:(fun context path bytes ->\n      Eio.Time.Mono.sleep (Worker.Request_context.clock context) 0.02;", "~handle:(fun _ path bytes ->")
fixture = fixture[:fixture.index("let () =\n  Native_backend.embed")]
fixture += '''let app = App.create_with_worker ~name:"Installed shutdown probe"
  ~decode_config:(fun bytes -> let path = Bytes.to_string bytes in shutdown_fixture_path := path; Ok path)
  ~service:shutdown_service shutdown_component
'''
(host / "app/application.ml").write_text(fixture)
swift = r'''
import BonsaiSwiftUI
import SwiftUI
#if os(macOS)
import AppKit
@main struct Probe: App {
  @NSApplicationDelegateAdaptor(Delegate.self) var delegate
  var body: some Scene {
    WindowGroup {
      BonsaiApplicationView(entrypoint: "shutdown_probe",
        payload: Data("AUDIT_PATH".utf8), applicationBridge: delegate.bridge)
        .frame(minWidth: 400, minHeight: 240)
    }
  }
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
  var events: BonsaiApplicationEvents?
  var started = false
  var disconnected = 0
  var ordinary = 0
  var operation: BonsaiApplicationShutdown?
  let mode = (try? String(contentsOfFile: "MODE_PATH", encoding: .utf8)) ?? "visible"
  var bridge: BonsaiApplicationBridge {
    BonsaiApplicationBridge(request: { [self] bytes in ordinary += 1; return bytes },
      connected: { [self] events in
        self.events = events
        guard !started else { return }
        started = true
        Task {
          try? await Task.sleep(for: .milliseconds(200))
          switch mode {
          case "hidden": NSApp.hide(nil)
          case "inactive": NSApp.deactivate()
          case "minimized": NSApp.windows.first?.miniaturize(nil)
          default: break
          }
          try? await Task.sleep(for: .milliseconds(100))
          try! Data("ready".utf8).write(to: URL(fileURLWithPath: "READY_PATH"))
        }
      }, disconnected: { [self] in disconnected += 1 })
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if operation != nil { return .terminateLater }
    guard let events else { return .terminateCancel }
    do {
      let hidden = NSApp.isHidden
      let active = NSApp.isActive
      let minimized = NSApp.windows.contains { $0.isMiniaturized }
      let start = ProcessInfo.processInfo.systemUptime
      let op = try events.beginShutdown(event: Data([12]), timeout: .seconds(2),
        accepting: { $0.first == 13 }, request: { _ in .finish(Data([99])) })
      operation = op
      let duplicate = try events.beginShutdown(event: Data([14]), timeout: .seconds(9),
        accepting: { _ in false }, request: { _ in .reply(Data()) })
      Task {
        let outcome = await op.result
        let record: [String: Any] = ["mode": mode, "outcome": String(describing: outcome),
          "hidden": hidden, "active": active, "minimized": minimized,
          "seconds": ProcessInfo.processInfo.systemUptime - start,
          "ordinary": ordinary, "disconnected": disconnected, "sameOperation": op === duplicate]
        let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        try! data.write(to: URL(fileURLWithPath: "RESULT_PATH"))
        sender.reply(toApplicationShouldTerminate: true)
      }
      return .terminateLater
    } catch { return .terminateCancel }
  }
}
#else
@main struct Probe: App {
  var body: some Scene { WindowGroup { BonsaiApplicationView(entrypoint: "shutdown_probe") } }
}
#endif
'''
for key, name in [("AUDIT_PATH", "audit.log"), ("MODE_PATH", "mode.txt"), ("RESULT_PATH", "result.json"), ("READY_PATH", "ready.txt")]:
    swift = swift.replace(key, str(host / name))
(host / "swift/App.swift").write_text(swift)
cli("build", "macos", "--profile", "debug", timeout=900)
results = []
for mode in ["visible", "hidden", "inactive", "minimized"]:
    (host / "mode.txt").write_text(mode)
    for name in ["audit.log", "result.json", "ready.txt"]:
        (host / name).unlink(missing_ok=True)
    launch_log = (REPORT / f"installed-{mode}-launch.log").open("w")
    process = subprocess.Popen(["opam", "exec", "--switch=bonsai-ui", "--", "bonsai-swiftui",
                                "run", "macos", "--profile", "debug"], cwd=host, env=env,
                               stdout=launch_log, stderr=subprocess.STDOUT)
    ready_deadline = time.monotonic() + 30
    while not (host / "ready.txt").exists() and time.monotonic() < ready_deadline:
        time.sleep(0.05)
    assert (host / "ready.txt").exists(), "consumer did not become ready"
    bundle = next((host / "apple/DerivedData/Build/Products/Debug").glob("*.app"))
    # Send a genuine native Quit event. Calling NSApp.terminate synchronously
    # inside a Swift concurrency job can hold its executor during AppKit's
    # termination modal loop and is not equivalent to a user Quit event.
    quit_result = subprocess.run(["osascript", "-e", f'tell application "{bundle}" to quit'],
                                 capture_output=True, text=True, timeout=15)
    assert quit_result.returncode == 0, quit_result.stderr
    process.wait(timeout=15)
    launch_log.close()
    deadline = time.monotonic() + 15
    while not (host / "result.json").exists() and time.monotonic() < deadline:
        time.sleep(0.05)
    record = json.loads((host / "result.json").read_text())
    record["audit"] = (host / "audit.log").read_text().splitlines()
    assert record["outcome"] == "completed" and record["sameOperation"], record
    assert record["ordinary"] == 0 and record["disconnected"] == 1, record
    assert record["audit"].count("final-reply-accepted") == 1, record
    assert record["audit"].count("worker-closed") == 1, record
    if mode == "hidden": assert record["hidden"], record
    if mode == "inactive": assert not record["active"], record
    if mode == "minimized": assert record["minimized"], record
    results.append(record)
    time.sleep(0.3)
(REPORT / "installed-probe-results.json").write_text(json.dumps({"host": str(host), "results": results}, indent=2) + "\n")
print(json.dumps(results, indent=2))
print("Disposable consumer:", host)
