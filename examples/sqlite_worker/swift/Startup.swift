import Foundation

enum SQLiteWorkerStartup {
  static func prepare(directory explicitDirectory: URL? = nil) throws -> Data {
    let files = FileManager.default
    let directory: URL
    if let explicitDirectory {
      guard explicitDirectory.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
      directory = explicitDirectory.standardizedFileURL
    } else {
      guard let identifier = Bundle.main.bundleIdentifier else { throw CocoaError(.fileNoSuchFile) }
      directory = try files.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      ).appendingPathComponent(identifier, isDirectory: true)
    }
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
    let database = Data(directory.appendingPathComponent("todos.sqlite3").path.utf8)
    let support = Data(directory.path.utf8)
    guard database.count + support.count + 12 <= 1024 * 1024 else {
      throw CocoaError(.fileWriteInvalidFileName)
    }
    var payload = Data("SWC1".utf8)
    for length in [database.count, support.count] {
      var value = UInt32(length).littleEndian
      withUnsafeBytes(of: &value) { payload.append(contentsOf: $0) }
    }
    payload.append(database)
    payload.append(support)
    return payload
  }
}
