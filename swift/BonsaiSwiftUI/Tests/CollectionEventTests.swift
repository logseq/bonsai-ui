import Foundation
import Testing

@testable import BonsaiSwiftUI

struct CollectionEventTests {
  @Test func visibleRangesCoalesceWithinTheirOwnerAndPreserveActionBarriers() throws {
    var queue = NativeEventQueue()
    for sequence: UInt64 in 1...2 {
      let accepted = queue.append(
        NativeEvent(
          sequence: sequence, displayedRevision: 1, nodeID: 1,
          handlerID: 2, payload: .visibleRange(Int(sequence)..<Int(sequence + 10))))
      #expect(accepted)
    }
    #expect(queue.events.count == 1 && queue.events.first?.payload == .visibleRange(2..<12))
    let pressed = queue.append(
      NativeEvent(sequence: 3, displayedRevision: 1, nodeID: 2, handlerID: 3))
    let ranged = queue.append(
      NativeEvent(
        sequence: 4, displayedRevision: 1, nodeID: 1, handlerID: 2, payload: .visibleRange(3..<13)))
    let other = queue.append(
      NativeEvent(
        sequence: 5, displayedRevision: 1, nodeID: 2, handlerID: 2, payload: .visibleRange(5..<15)))
    #expect(pressed && ranged && other && queue.events.map(\.sequence) == [2, 3, 4, 5])
    let bytes = try EventBatch.encode(epoch: 1, events: queue.events)
    var reader = WireReader(bytes)
    _ = try reader.data(ProtocolLimits.headerBytes)
    #expect(try reader.integer(UInt32.self) == 4)
    #expect(try reader.integer(UInt32.self) == 50)
    _ = try reader.data(32)
    #expect(try reader.integer(UInt16.self) == EventTagId.visibleRangeChanged)
    #expect(try reader.integer(UInt64.self) == 2 && reader.integer(UInt64.self) == 12)
    let invalid = NativeEvent(
      sequence: 1, displayedRevision: 1, nodeID: 1, handlerID: 1, payload: .visibleRange(-1..<2))
    #expect(throws: WireError.invalidHeader) { try EventBatch.encode(epoch: 1, events: [invalid]) }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeListRangesPreserveActualMailDelayedPaging() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "mail-collection")
    do {
      var store = NodeStore()
      func apply(_ output: NativeOutput) throws {
        if !output.bytes.isEmpty { store = try store.staging(WireFrame.decode(output.bytes)).tree }
      }
      func rows() throws -> [UInt64] {
        let list = try #require(store.nodes.values.first { $0.kind == NodeKindId.nativeList })
        return list.children.flatMap { Array(store.nodes[$0]!.children.dropFirst(2)) }
      }
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      try apply(initial)
      let retained = try rows()
      #expect(retained.count == 20)
      let list = try #require(store.nodes.values.first { $0.kind == NodeKindId.nativeList })
      let handler = try #require(list.bindings[EventTagId.visibleRangeChanged])
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      let nearEnd = NativeEvent(
        sequence: 1, displayedRevision: initial.revision,
        nodeID: list.id, handlerID: handler, payload: .visibleRange(13..<20))
      let loading = try await runtime.pump(
        monotonicNanoseconds: 3,
        events: EventBatch.encode(epoch: store.epoch, events: [nearEnd]))
      try apply(loading)
      #expect(try rows().count == 21)
      #expect(try Array(rows().prefix(20)) == retained)
      try await runtime.acknowledge(loading, monotonicNanoseconds: 4)
      let beforeDelay = try await runtime.pump(monotonicNanoseconds: 700_000_003)
      try apply(beforeDelay)
      #expect(try rows().count == 21)
      try await runtime.acknowledge(beforeDelay, monotonicNanoseconds: 700_000_004)
      let loaded = try await runtime.pump(monotonicNanoseconds: 800_000_003)
      try apply(loaded)
      #expect(try rows().count == 40)
      #expect(try Array(rows().prefix(20)) == retained)
      try await runtime.acknowledge(loaded, monotonicNanoseconds: 800_000_004)
      let idle = try await runtime.pump(monotonicNanoseconds: 1_600_000_003)
      try apply(idle)
      #expect(try rows().count == 40)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
