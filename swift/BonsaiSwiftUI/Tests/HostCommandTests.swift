import Foundation
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func host(_ id: UInt64, kind: UInt16, text: String? = nil) -> WireOperation {
    operation(OperationId.hostRequest) {
      $0.integer(id)
      $0.integer(kind)
      if let text {
        $0.integer(UInt32(text.utf8.count))
        $0.bytes.append(contentsOf: text.utf8)
      }
    }
  }
}

struct HostCommandTests {
  private var initial: WireFrame {
    TreeFixture.frame(TreeFixture.initial.operations + [TreeFixture.environment()])
  }

  @Test func windowRequestsStageAtomicallyAndRejectInvalidGeometry() throws {
    func size(_ width: Double, _ height: Double) -> WireOperation {
      TreeFixture.operation(OperationId.hostRequest) {
        $0.integer(UInt64(2))
        $0.integer(UInt16(10))
        $0.integer(width.bitPattern)
        $0.integer(height.bitPattern)
      }
    }
    let state = try FrameState().staging(initial)
    let title = TreeFixture.host(1, kind: 9, text: "Window 本地😀")
    let geometry = size(760, 560)
    let next = try state.staging(TreeFixture.frame([title, geometry], base: 1, revision: 2))
    #expect(next.tree.revision == 2)
    var malformed = [TreeFixture.host(1, kind: 9, text: nil)]
    for operation in [title, geometry] {
      malformed += (0..<operation.body.count).map {
        WireOperation(opcode: operation.opcode, body: operation.body.prefix($0))
      }
      malformed.append(WireOperation(opcode: operation.opcode, body: operation.body + Data([0])))
    }
    for dimension in [0.0, -1.0, Double.nan, Double.infinity, -Double.infinity] {
      malformed += [size(dimension, 560), size(760, dimension)]
    }
    for operation in malformed {
      #expect(throws: (any Error).self) {
        try state.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
      #expect(state.tree.revision == 1)
    }
  }

  @Test func clipboardCommandsAndCancellationStageWithTheirView() throws {
    let state = try FrameState().staging(initial)
    let result = try state.staging(
      TreeFixture.frame(
        [
          TreeFixture.host(2, kind: 2, text: "Unicode 本地😀"),
          TreeFixture.host(1, kind: 1), TreeFixture.host(2, kind: 0),
          TreeFixture.host(3, kind: 13),
        ], base: 1, revision: 2))
    #expect(result.tree.revision == 2)
    #expect(result.application == state.application)
    #expect(state.tree.revision == 1)
  }

  @Test func malformedHostCommandsRejectTheWholeTransaction() throws {
    let state = try FrameState().staging(initial)
    let valid = TreeFixture.host(1, kind: 2, text: "Unicode 本地😀").body
    var invalid = (0..<valid.count).map {
      WireOperation(opcode: OperationId.hostRequest, body: valid.prefix($0))
    }
    invalid += [
      TreeFixture.host(0, kind: 1), TreeFixture.host(UInt64.max, kind: 1),
      TreeFixture.host(1, kind: UInt16.max), TreeFixture.host(1, kind: 0, text: "extra"),
      TreeFixture.host(1, kind: 1, text: "extra"),
      TreeFixture.host(1, kind: 13, text: "extra"),
      TreeFixture.host(
        1, kind: 2, text: String(repeating: "x", count: ProtocolLimits.maxStringBytes + 1)),
    ]
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try state.staging(
          TreeFixture.frame(
            [
              TreeFixture.text(2, "Partial update", update: true),
              TreeFixture.host(2, kind: 2, text: "Never execute a partial transaction"), operation,
            ], base: 1, revision: 2))
      }
      #expect(state.tree.revision == 1)
    }
  }

  @Test func requestIDsCannotRepeatWithinOrAfterAnAcceptedFrame() throws {
    let state = try FrameState().staging(initial)
    #expect(throws: (any Error).self) {
      try state.staging(
        TreeFixture.frame(
          [
            TreeFixture.host(1, kind: 1), TreeFixture.host(1, kind: 2, text: "duplicate"),
          ], base: 1, revision: 2))
    }
    let committed = try state.staging(
      TreeFixture.frame([TreeFixture.host(2, kind: 1)], base: 1, revision: 2))
    for id: UInt64 in [1, 2] {
      #expect(throws: (any Error).self) {
        try committed.staging(
          TreeFixture.frame([TreeFixture.host(id, kind: 1)], base: 2, revision: 3))
      }
      #expect(throws: (any Error).self) {
        try committed.staging(
          TreeFixture.frame(initial.operations + [TreeFixture.host(id, kind: 1)], revision: 3))
      }
    }
    _ = try committed.staging(
      TreeFixture.frame([TreeFixture.host(3, kind: 1)], base: 2, revision: 3))
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualHostEffectsExampleStages() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "host_effects")
      #expect(try await session.presented(#require(session.ticket)))
      #expect(
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value == "No host request has run" }
          return false
        })
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
