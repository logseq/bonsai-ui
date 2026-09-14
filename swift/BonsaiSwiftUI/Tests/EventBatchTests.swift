import Foundation
import Testing

@testable import BonsaiSwiftUI

extension NativeRuntimeTests {
  @Test func swiftPressRunsActualOcamlCounterHandler() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "counter")
    let initial = try await runtime.pump(monotonicNanoseconds: 1)
    let frame = try WireFrame.decode(initial.bytes)
    var press: NativeEvent?
    for operation in frame.operations where operation.opcode == OperationId.createNode {
      var body = WireReader(operation.body)
      let nodeID = try body.integer(UInt64.self)
      let kind = try body.integer(UInt16.self)
      if kind == NodeKindId.button {
        _ = try body.data(4)  // Enabled, role, style, and autofocus properties.
        #expect(try body.integer(UInt16.self) == 1)
        #expect(try body.integer(UInt16.self) == EventTagId.press)
        let handlerID = try body.integer(UInt64.self)
        press = NativeEvent(
          sequence: 1, displayedRevision: frame.revision,
          nodeID: nodeID, handlerID: handlerID)
      }
    }
    let event = try #require(press)
    try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
    let batch = try EventBatch.encode(epoch: frame.epoch, events: [event])
    let updated = try await runtime.pump(monotonicNanoseconds: 3, events: batch)
    #expect(updated.status == 0)
    #expect(updated.bytes.range(of: Data("Count: 1".utf8)) != nil)
    #expect(try WireFrame.decode(updated.bytes).kind == FrameKindId.incrementalFrame)
    try await runtime.acknowledge(updated, monotonicNanoseconds: 4)
    // Replaying the same sequence must not execute the handler a second time.
    let replay = try await runtime.pump(monotonicNanoseconds: 5, events: batch)
    #expect(replay.status == 1)
    #expect(replay.bytes.range(of: Data("Count: 2".utf8)) == nil)
    await runtime.close()
  }
}

struct EventEncodingTests {
  @Test func canonicalFixtureMatchesByteForByte() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let fixture = try String(
      contentsOf: root.appendingPathComponent(
        "protocol/generated/fixtures/swift_counter_press.hex"), encoding: .utf8)
    let expected = Data(
      try fixture.split(whereSeparator: \.isWhitespace).map {
        try #require(UInt8($0, radix: 16))
      })
    let press = NativeEvent(sequence: 1, displayedRevision: 1, nodeID: 3, handlerID: 9001)
    #expect(try EventBatch.encode(epoch: 21, events: [press]) == expected)
  }

  @Test func invalidIDsAndUnorderedEventsAreRejected() throws {
    let valid = NativeEvent(sequence: 1, displayedRevision: 1, nodeID: 3, handlerID: 1)
    for epoch: UInt64 in [0, UInt64.max] {
      #expect(throws: WireError.invalidHeader) {
        try EventBatch.encode(epoch: epoch, events: [valid])
      }
    }
    #expect(throws: WireError.invalidOrder) {
      try EventBatch.encode(epoch: 7, events: [valid, valid])
    }
    for event in [
      NativeEvent(sequence: 0, displayedRevision: 1, nodeID: 3, handlerID: 1),
      NativeEvent(sequence: 1, displayedRevision: 0, nodeID: 3, handlerID: 1),
      NativeEvent(sequence: 1, displayedRevision: 1, nodeID: 0, handlerID: 1),
      NativeEvent(sequence: 1, displayedRevision: 1, nodeID: 3, handlerID: UInt64.max),
    ] {
      #expect(throws: WireError.invalidHeader) { try EventBatch.encode(epoch: 7, events: [event]) }
    }
    #expect(throws: WireError.limitExceeded) {
      try EventBatch.encode(
        epoch: 7, events: Array(repeating: valid, count: ProtocolLimits.maxOperations + 1))
    }
  }
}
