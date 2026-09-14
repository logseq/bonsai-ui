import Foundation
import Testing

@testable import BonsaiSwiftUI

struct FileCommandTests {
  private func pick(_ id: UInt64, multiple: UInt8 = 1) -> WireOperation {
    TreeFixture.operation(OperationId.hostRequest) {
      $0.integer(id)
      $0.integer(UInt16(HostRequestId.pickFiles))
      $0.integer(UInt16(2))
      try! $0.string("txt")
      try! $0.string("bin")
      $0.integer(multiple)
    }
  }
  private func save(_ id: UInt64, data: Data) -> WireOperation {
    TreeFixture.operation(OperationId.hostRequest) {
      $0.integer(id)
      $0.integer(UInt16(HostRequestId.saveFile))
      $0.integer(UInt8(1))
      try! $0.string("Bonsai.txt")
      $0.integer(UInt32(data.count))
      $0.bytes.append(data)
    }
  }
  @Test func fileCommandsPreserveOpaqueSaveBytesAndRejectPartialFrames() throws {
    let initial = TreeFixture.initial.operations + [TreeFixture.environment()]
    let state = try FrameState().staging(TreeFixture.frame(initial))
    let bytes = Data([0, 255, 128])
    let selection = pick(1)
    let export = save(2, data: bytes)
    let next = try state.staging(TreeFixture.frame([selection, export], base: 1, revision: 2))
    #expect(
      next.hostCommands == [
        .request(1, .pickFiles(allowedExtensions: ["txt", "bin"], allowMultiple: true)),
        .request(2, .saveFile(suggestedName: "Bonsai.txt", data: bytes)),
      ])
    _ = try state.staging(
      TreeFixture.frame(
        [save(1, data: Data(repeating: 255, count: 1_048_577))], base: 1, revision: 2))
    var malformed: [WireOperation] = [pick(1, multiple: 2), save(0, data: bytes)]
    for operation in [selection, export] {
      malformed += (0..<operation.body.count).map {
        WireOperation(opcode: operation.opcode, body: operation.body.prefix($0))
      }
      malformed.append(WireOperation(opcode: operation.opcode, body: operation.body + Data([0])))
    }
    for operation in malformed {
      #expect(throws: (any Error).self) {
        try state.staging(
          TreeFixture.frame(
            [TreeFixture.text(2, "Uncommitted", update: true), operation], base: 1, revision: 2))
      }
      #expect(state.tree.revision == 1)
    }
  }
}
