import SwiftUI

@main struct DataScriptWorkerProbeApplication: App {
  @State private var status = "Running persistence probe"
  @State private var started = false

  var body: some Scene {
    WindowGroup {
      Text(status).padding().task {
        guard !started else { return }
        started = true
        do {
          let directory = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
          )
          .appendingPathComponent("DataScriptWorkerProbe", isDirectory: true)
          let phase = try await DataScriptWorkerProbe.run(directory: directory)
          status = "Passed: \(phase) and closed"
        } catch {
          DataScriptWorkerProbe.marker("BONSAI_DATASCRIPT_PROBE_FAILED: \(error)")
          status = "Failed: \(error)"
        }
      }
    }
  }
}
