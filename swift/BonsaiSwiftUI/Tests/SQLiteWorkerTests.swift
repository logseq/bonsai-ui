import Foundation
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test @MainActor func actualSQLiteWorkerStartsAndReopensItsDatabase() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SQLite 本地-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = directory.appendingPathComponent("todos.sqlite3")
    let pathBytes = Data(database.path.utf8)
    let directoryBytes = Data(directory.path.utf8)
    var payload = Data("SWC1".utf8)
    for count in [pathBytes.count, directoryBytes.count] {
      var size = UInt32(count).littleEndian
      withUnsafeBytes(of: &size) { payload.append(contentsOf: $0) }
    }
    payload.append(pathBytes)
    payload.append(directoryBytes)
    for _ in 0..<2 {
      let session = BonsaiSession()
      session.isVisible = true
      do {
        try await session.start(entrypoint: "sqlite_worker", payload: payload)
        var ready = false
        for _ in 0..<100 {
          if let ticket = session.ticket { _ = try await session.presented(ticket) }
          try await session.refresh()
          ready = session.tree.nodes.values.contains { node in
            if case .text(let text) = node.properties { return text.value == "Ready" }
            return false
          }
          if ready { break }
          try await Task.sleep(for: .milliseconds(10))
        }
        #expect(ready)
        #expect(FileManager.default.fileExists(atPath: database.path))
        await session.close()
      } catch {
        await session.close()
        throw error
      }
    }
  }
}
