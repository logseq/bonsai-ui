import Foundation

private struct ImportedFileBatch: Sendable {
  let directory: URL
  let files: [URL]

  func discard() { try? FileManager.default.removeItem(at: directory) }

  static func copy(_ sources: [URL], parent: URL) throws -> ImportedFileBatch {
    try Task.checkCancellation()
    let manager = FileManager.default
    let directory = parent.appendingPathComponent(
      "BonsaiImport-\(UUID().uuidString)", isDirectory: true)
    var replyBytes = 4
    for (index, source) in sources.enumerated() {
      let destination = directory.appendingPathComponent(String(index), isDirectory: true)
        .appendingPathComponent(source.lastPathComponent)
      let recordBytes = 6 + destination.path.utf8.count
      guard recordBytes <= ProtocolLimits.maxStringBytes - replyBytes else {
        throw HostServiceError.failed("The selected file list exceeds the transfer limit")
      }
      replyBytes += recordBytes
    }
    try manager.createDirectory(
      at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    do {
      var files: [URL] = []
      for (index, source) in sources.enumerated() {
        try Task.checkCancellation()
        guard source.isFileURL else {
          throw HostServiceError.failed("A local file URL is required")
        }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let folder = directory.appendingPathComponent(String(index), isDirectory: true)
        try manager.createDirectory(
          at: folder, withIntermediateDirectories: false,
          attributes: [.posixPermissions: 0o700])
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Void, any Error>?
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) {
          url in
          result = Result {
            try Task.checkCancellation()
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
              throw HostServiceError.failed("Only regular files can be imported")
            }
            try manager.copyItem(at: url, to: destination)
            try Task.checkCancellation()
          }
        }
        if let coordinationError { throw coordinationError }
        guard let result else {
          throw HostServiceError.failed("File coordination did not complete")
        }
        try result.get()
        files.append(destination)
      }
      try Task.checkCancellation()
      return ImportedFileBatch(directory: directory, files: files)
    } catch {
      try? manager.removeItem(at: directory)
      throw error
    }
  }
}

/// Owns imported copies until the runtime closes. Never deletes source files.
@MainActor final class NativeFileImports {
  private let parent: URL
  private var generation = UUID()
  private var jobs: [UUID: Task<ImportedFileBatch, any Error>] = [:]
  private var committed: [ImportedFileBatch] = []

  init(parent: URL = FileManager.default.temporaryDirectory) { self.parent = parent }

  func copy(_ urls: [URL]) async throws -> [URL] {
    try Task.checkCancellation()
    guard !urls.isEmpty else { return [] }
    let identity = generation
    let id = UUID()
    let parent = parent
    let job = Task.detached(priority: .userInitiated) {
      try ImportedFileBatch.copy(urls, parent: parent)
    }
    jobs[id] = job
    defer { jobs.removeValue(forKey: id) }
    let batch = try await withTaskCancellationHandler {
      try await job.value
    } onCancel: {
      job.cancel()
    }
    guard identity == generation, !Task.isCancelled else {
      batch.discard()
      throw CancellationError()
    }
    committed.append(batch)
    return batch.files
  }

  func discard(_ files: [URL]) {
    guard let index = committed.firstIndex(where: { $0.files == files }) else { return }
    committed.remove(at: index).discard()
  }

  func reset() {
    generation = UUID()
    for job in jobs.values { job.cancel() }
    jobs.removeAll()
    for batch in committed { batch.discard() }
    committed.removeAll()
  }
}
