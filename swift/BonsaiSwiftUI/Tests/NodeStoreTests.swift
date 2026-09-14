import Foundation
import Testing

@testable import BonsaiSwiftUI

struct NodeStoreTests {
  @Test func stagesTypedTreeAndRetainsAncillaryOperations() throws {
    let metadata = WireOperation(opcode: OperationId.setApplicationTheme, body: Data([1, 2]))
    let frame = TreeFixture.frame(TreeFixture.initial.operations + [metadata])
    let initial = NodeStore()
    let transaction = try initial.staging(frame)
    #expect(initial.nodes.isEmpty)
    #expect(transaction.tree.nodes.count == 4)
    #expect(transaction.tree.root == 1)
    #expect(
      transaction.tree.nodes[3]?.properties
        == .button(enabled: true, role: 2, style: 3, autofocus: false))
    #expect(transaction.tree.nodes[3]?.bindings == [EventTagId.press: 9])
    #expect(transaction.ancillaryOperations == [metadata])
  }

  @Test func textUpdatesAndKeyedReordersPreserveIdentity() throws {
    let before = try NodeStore().staging(TreeFixture.initial).tree
    let after = try before.staging(
      TreeFixture.frame(
        [
          TreeFixture.text(2, "Count: 1", update: true), TreeFixture.children(1, [3, 2]),
        ], base: 1, revision: 2)
    ).tree
    #expect(before.nodes[2]?.properties == .text("Count: 0"))
    #expect(after.nodes[2]?.properties == .text("Count: 1"))
    #expect(after.nodes[1]?.children == [3, 2])
    #expect(after.nodes[3] == before.nodes[3])
  }

  @Test func failedTransactionsDoNotChangeOriginalTree() throws {
    let before = try NodeStore().staging(TreeFixture.initial).tree
    let snapshot = before
    let corruptions: [[WireOperation]] = [
      [TreeFixture.children(1, [2, 99])],
      [TreeFixture.children(1, [2, 2, 3])],
      [TreeFixture.children(3, [1])],
      [TreeFixture.children(1, [3])],
      [TreeFixture.children(2, [4])],
      [TreeFixture.create(1)],
      [TreeFixture.create(8)],
      [TreeFixture.root(0)],
      [TreeFixture.text(99, "Missing", update: true)],
      [TreeFixture.operation(OperationId.dropNode) { $0.integer(UInt64(4)) }],
    ]
    for operations in corruptions {
      #expect(throws: (any Error).self) {
        try before.staging(
          TreeFixture.frame(
            [TreeFixture.text(2, "Must not leak", update: true)] + operations,
            base: 1, revision: 2))
      }
      #expect(before == snapshot)
    }
  }

  @Test func rejectsStaleEpochRevisionAndMalformedProperties() throws {
    let store = try NodeStore().staging(TreeFixture.initial).tree
    for frame in [
      TreeFixture.frame([], base: 1, revision: 2, epoch: 8),
      TreeFixture.frame([], base: 2, revision: 3),
      TreeFixture.frame([], base: 1, revision: 1),
    ] {
      #expect(throws: TreeError.revisionMismatch) { try store.staging(frame) }
    }
    for button in [
      TreeFixture.button(1, enabled: false),
      TreeFixture.button(1, role: 3),
      TreeFixture.button(1, style: 4),
      TreeFixture.button(1, handler: 0),
    ] {
      #expect(throws: (any Error).self) {
        try NodeStore().staging(
          TreeFixture.frame([
            button, TreeFixture.text(2, "Button"), TreeFixture.children(1, [2]),
            TreeFixture.root(1),
          ]))
      }
    }
    for operation in TreeFixture.initial.operations {
      for count in 0..<operation.body.count {
        let truncated = WireOperation(opcode: operation.opcode, body: operation.body.prefix(count))
        #expect(throws: (any Error).self) {
          try NodeStore().staging(TreeFixture.frame([truncated]))
        }
      }
    }
  }
}

extension NativeRuntimeTests {
  @Test func realCounterStagesAndUpdatesThroughSwiftButton() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "counter")
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let transaction = try NodeStore().staging(WireFrame.decode(initial.bytes))
      let store = transaction.tree
      let button = try #require(store.nodes.values.first { $0.kind == NodeKindId.button })
      #expect(button.properties == .button(enabled: true, role: 0, style: 3, autofocus: false))
      let handler = try #require(button.bindings[EventTagId.press])
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      let event = NativeEvent(
        sequence: 1, displayedRevision: store.revision,
        nodeID: button.id, handlerID: handler)
      let updated = try await runtime.pump(
        monotonicNanoseconds: 3,
        events: EventBatch.encode(epoch: store.epoch, events: [event]))
      let next = try store.staging(WireFrame.decode(updated.bytes)).tree
      #expect(next.nodes.values.contains { $0.properties == .text("Count: 1") })
      #expect(next.nodes[button.id] == button)
      try await runtime.acknowledge(updated, monotonicNanoseconds: 4)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
