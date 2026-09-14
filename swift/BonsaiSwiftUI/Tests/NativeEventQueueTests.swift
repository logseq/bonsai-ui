import Foundation
import Testing

@testable import BonsaiSwiftUI

struct NativeEventQueueTests {
  private func edit(
    _ sequence: UInt64, text: String = "Draft", session: UInt64 = 1,
    node: UInt64 = 1, handler: UInt64 = 1, displayed: UInt64 = 1
  ) throws -> NativeEvent {
    NativeEvent(
      sequence: sequence, displayedRevision: displayed, nodeID: node, handlerID: handler,
      payload: .textEdit(
        TextEdit(
          sessionID: session, localRevision: sequence,
          baseDocumentRevision: 1, value: try textValue(text))))
  }

  @Test func consecutiveFullEditsCoalesceWithoutCrossingBarriersOrOwners() throws {
    var queue = NativeEventQueue()
    #expect(true == (queue.append(try edit(1))))
    #expect(true == (queue.append(try edit(2, text: "中文😀"))))
    #expect(queue.events.count == 1 && queue.events.last?.sequence == 2)
    #expect(
      true
        == (queue.append(
          NativeEvent(
            sequence: 3, displayedRevision: 1, nodeID: 1,
            handlerID: 2, payload: .textSubmit("中文😀")))))
    for event in [
      try edit(4), try edit(5, session: 2), try edit(6, node: 2),
      try edit(7, handler: 2), try edit(8, displayed: 2),
    ] {
      #expect(true == (queue.append(event)))
    }
    #expect(queue.events.map(\.sequence) == [2, 3, 4, 5, 6, 7, 8])
    #expect(throws: Never.self) { _ = try EventBatch.encode(epoch: 1, events: queue.events) }
  }

  @Test func capacityRejectionPreservesTheLastAcceptedValueAndDrainResetsBudgets() throws {
    let first = try edit(1)
    let bytes = try EventBatch.encode(epoch: 1, events: [first]).count
    var queue = NativeEventQueue(maximumCount: 1, maximumBytes: bytes)
    #expect(true == (queue.append(first)))
    #expect(false == (queue.append(try edit(2, text: "This replacement exceeds the byte budget"))))
    #expect(queue.events.count == 1 && queue.events.first?.sequence == 1)
    #expect(true == (queue.append(try edit(2, text: "A"))))
    #expect(
      false
        == (queue.append(NativeEvent(sequence: 3, displayedRevision: 1, nodeID: 1, handlerID: 2))))
    #expect(false == (queue.append(try edit(2))))
    #expect(
      false
        == (queue.append(
          try edit(3, text: String(repeating: "x", count: ProtocolLimits.maxStringBytes + 1)))))
    #expect(queue.events.count == 1 && queue.events.first?.sequence == 2)
    queue.removeAll()
    #expect(true == (queue.append(first) && queue.events.count == 1))
  }
}
