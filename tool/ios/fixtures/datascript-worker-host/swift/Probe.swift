import BonsaiSwiftUI
import Foundation

enum DataScriptWorkerProbe {
  enum Failure: Error { case timeout, invalidReadiness, missingShutdown }

  static func marker(_ value: String) {
    FileHandle.standardError.write(Data((value + "\n").utf8))
  }

  // This is a runtime/persistence probe. Acknowledged frames are consumed by
  // the probe, not presented as application UI; it provides no rendering proof.
  static func run(directory: URL, timeout: Duration = .seconds(30)) async throws -> String {
    let payload = try SQLiteWorkerStartup.prepare(directory: directory)
    let ready = directory.appendingPathComponent("probe-ready")
    let closed = directory.appendingPathComponent("probe-closed")
    for url in [ready, closed] where FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    let runtime = try await NativeRuntime.open(entrypoint: "sqlite_worker", payload: payload)
    marker("BONSAI_DATASCRIPT_HOST_RUNTIME_STARTED")
    let phase: String
    do {
      let clock = ContinuousClock()
      let deadline = clock.now.advanced(by: timeout)
      while true {
        try Task.checkCancellation()
        let output = try await runtime.pump(
          monotonicNanoseconds: Int64(DispatchTime.now().uptimeNanoseconds))
        guard output.status != 2 else {
          throw NativeRuntimeError.nativeFailure(status: output.status, code: output.errorCode)
        }
        try await runtime.acknowledge(
          output, monotonicNanoseconds: Int64(DispatchTime.now().uptimeNanoseconds))
        if FileManager.default.fileExists(atPath: ready.path) {
          phase = try String(contentsOf: ready, encoding: .utf8)
          guard phase == "persisted" || phase == "restored" else { throw Failure.invalidReadiness }
          break
        }
        guard clock.now < deadline else { throw Failure.timeout }
        try await Task.sleep(for: .milliseconds(10))
      }
    } catch {
      await runtime.close()
      marker("BONSAI_DATASCRIPT_HOST_RUNTIME_DISPOSED")
      throw error
    }
    await runtime.close()
    marker("BONSAI_DATASCRIPT_HOST_RUNTIME_DISPOSED")
    guard try String(contentsOf: closed, encoding: .utf8) == "closed" else {
      throw Failure.missingShutdown
    }
    marker("BONSAI_DATASCRIPT_PROBE_PASSED")
    return phase
  }
}
