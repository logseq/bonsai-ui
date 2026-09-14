import Foundation
import Testing

@testable import BonsaiSwiftUI

struct FileExportTests {
  @Test func exportWritesOpaqueEmptyAndLargeFilesWithoutBorrowingInputMemory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "BonsaiFileExportTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    for (index, bytes) in [Data(), Data([0, 255, 128]), Data(repeating: 255, count: 1_048_577)]
      .enumerated()
    {
      let document = try NativeExportDocument(data: bytes)
      let file = root.appendingPathComponent("\(index).bin")
      try document.makeFileWrapper().write(to: file, options: .atomic, originalContentsURL: nil)
      #expect(try Data(contentsOf: file) == bytes)
    }
    let memory = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 1)
    defer { memory.deallocate() }
    memory.initializeMemory(as: UInt8.self, repeating: 255, count: 64)
    let borrowed = Data(bytesNoCopy: memory, count: 64, deallocator: .none)
    let document = try NativeExportDocument(data: borrowed)
    memory.initializeMemory(as: UInt8.self, repeating: 0, count: 64)
    #expect(document.makeFileWrapper().regularFileContents == Data(repeating: 255, count: 64))
    #expect(throws: (any Error).self) {
      try NativeExportDocument(data: Data(repeating: 0, count: ProtocolLimits.maxFrameBytes + 1))
    }
  }
}
