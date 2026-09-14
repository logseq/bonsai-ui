import SwiftUI
import UniformTypeIdentifiers

struct NativeExportDocument: FileDocument {
  static let readableContentTypes: [UTType] = [.data]
  private let data: Data
  init(data: Data) throws {
    guard data.count <= ProtocolLimits.maxFrameBytes else { throw WireError.limitExceeded }
    self.data = data.withUnsafeBytes { Data($0) }
  }
  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw HostServiceError.failed("Only regular files can be exported")
    }
    try self.init(data: data)
  }
  func makeFileWrapper() -> FileWrapper { FileWrapper(regularFileWithContents: data) }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { makeFileWrapper() }
}
