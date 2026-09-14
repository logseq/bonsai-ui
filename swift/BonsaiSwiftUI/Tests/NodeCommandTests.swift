import Foundation
import Testing

@testable import BonsaiSwiftUI

struct NodeCommandTests {
  @Test func nodeCommandsValidateIdentitiesAndCompleteBodiesBeforePublication() throws {
    let state = try FrameState().staging(
      TreeFixture.frame(TreeFixture.initial.operations + [TreeFixture.environment()]))
    for (kind, expected) in [
      (6, HostRequest.requestFocus(42)), (7, .clearFocus), (14, .measureLayout(42)),
    ] {
      let command = TreeFixture.operation(OperationId.hostRequest) {
        $0.integer(UInt64(1))
        $0.integer(UInt16(kind))
        if kind != 7 { $0.integer(UInt64(42)) }
      }
      let next = try state.staging(TreeFixture.frame([command], base: 1, revision: 2))
      #expect(next.hostCommands == [.request(1, expected)])
      var invalid = (0..<command.body.count).map {
        WireOperation(opcode: command.opcode, body: command.body.prefix($0))
      }
      invalid.append(WireOperation(opcode: command.opcode, body: command.body + Data([0])))
      if kind != 7 {
        for target in [UInt64(0), UInt64.max] {
          invalid.append(
            TreeFixture.operation(OperationId.hostRequest) {
              $0.integer(UInt64(1))
              $0.integer(UInt16(kind))
              $0.integer(target)
            })
        }
      }
      for candidate in invalid {
        #expect(throws: (any Error).self) {
          try state.staging(TreeFixture.frame([candidate], base: 1, revision: 2))
        }
        #expect(state.tree.revision == 1)
      }
    }
  }
}
