import Foundation
import Testing

@testable import BonsaiSwiftUI

private struct FileImportFixture {
  let root: URL
  let destination: URL
  let first: URL
  let second: URL
  let opaque = Data([0, 255, 128, 0])

  init() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "BonsaiFileImportTest-\(UUID().uuidString)", isDirectory: true)
    destination = root.appendingPathComponent("imports", isDirectory: true)
    first = root.appendingPathComponent("first/同名.bin")
    second = root.appendingPathComponent("second/同名.bin")
    for directory in [
      destination, first.deletingLastPathComponent(), second.deletingLastPathComponent(),
    ] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try opaque.write(to: first)
    try Data().write(to: second)
  }
  func remove() { try? FileManager.default.removeItem(at: root) }
  var importedDirectories: [URL] {
    (try? FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil))
      ?? []
  }
}

@MainActor struct FileImportTests {
  @Test func importsKeepEveryFileAndDuplicateBasenameWithoutChangingSources() async throws {
    let fixture = try FileImportFixture()
    defer { fixture.remove() }
    let imports = NativeFileImports(parent: fixture.destination)
    let urls = try await imports.copy([fixture.first, fixture.second])
    try #require(urls.count == 2)
    #expect(urls[0] != urls[1])
    #expect(urls.map(\.lastPathComponent) == ["同名.bin", "同名.bin"])
    #expect(try Data(contentsOf: urls[0]) == fixture.opaque)
    #expect(try Data(contentsOf: urls[1]) == Data())
    try Data([1, 2]).write(to: urls[0])
    #expect(try Data(contentsOf: fixture.first) == fixture.opaque)
    #expect(fixture.importedDirectories.count == 1)
    imports.reset()
    #expect(fixture.importedDirectories.isEmpty)
    #expect(FileManager.default.fileExists(atPath: fixture.first.path))
  }

  @Test func fileContentsAreNotLimitedByTheHostResponseByteBudget() async throws {
    let fixture = try FileImportFixture()
    defer { fixture.remove() }
    let bytes = Data(repeating: 255, count: ProtocolLimits.maxStringBytes + 1)
    try bytes.write(to: fixture.first)
    let imports = NativeFileImports(parent: fixture.destination)
    defer { imports.reset() }
    let urls = try await imports.copy([fixture.first])
    let url = try #require(urls.first)
    #expect(try Data(contentsOf: url) == bytes)
    #expect(url.path.utf8.count < ProtocolLimits.maxStringBytes)
  }

  @Test func invalidSelectionsRollBackAllCopiesAndLeaveOriginalsUntouched() async throws {
    let fixture = try FileImportFixture()
    defer { fixture.remove() }
    let imports = NativeFileImports(parent: fixture.destination)
    for invalid in [
      fixture.root.appendingPathComponent("missing"), fixture.root,
      try #require(URL(string: "https://example.com/file")),
    ] {
      await #expect(throws: (any Error).self) { try await imports.copy([fixture.first, invalid]) }
      #expect(fixture.importedDirectories.isEmpty)
      #expect(try Data(contentsOf: fixture.first) == fixture.opaque)
    }
    let empty = try await imports.copy([])
    #expect(empty.isEmpty && fixture.importedDirectories.isEmpty)
    imports.reset()
  }

  @Test func cancellationBeforeImportDoesNotCopyAndResetAllowsNewImports() async throws {
    let fixture = try FileImportFixture()
    defer { fixture.remove() }
    let imports = NativeFileImports(parent: fixture.destination)
    let cancelled = Task { try await imports.copy([fixture.first]) }
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(fixture.importedDirectories.isEmpty)
    let first = try await imports.copy([fixture.first])
    imports.reset()
    #expect(first.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    let second = try await imports.copy([fixture.second])
    #expect(first != second)
    #expect(try Data(contentsOf: #require(second.first)) == Data())
    imports.reset()
    #expect(fixture.importedDirectories.isEmpty)
  }
}

extension FileImportTests {
  @Test func discardingOneCompletedImportDoesNotDeleteOtherImports() async throws {
    let fixture = try FileImportFixture()
    defer { fixture.remove() }
    let imports = NativeFileImports(parent: fixture.destination)
    defer { imports.reset() }
    let first = try await imports.copy([fixture.first])
    let second = try await imports.copy([fixture.second])
    imports.discard(first)
    #expect(first.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    #expect(try Data(contentsOf: #require(second.first)) == Data())
    #expect(fixture.importedDirectories.count == 1)
  }

  @Test func oversizedFileListIsRejectedBeforeCopyingAnything() async throws {
    let fixture = try FileImportFixture()
    defer { fixture.remove() }
    let imports = NativeFileImports(parent: fixture.destination)
    defer { imports.reset() }
    await #expect(throws: (any Error).self) {
      try await imports.copy(Array(repeating: fixture.first, count: 10000))
    }
    #expect(fixture.importedDirectories.isEmpty)
  }
}
