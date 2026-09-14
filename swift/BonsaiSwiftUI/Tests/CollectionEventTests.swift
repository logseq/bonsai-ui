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

// Mail's remaining widgets cannot yet stage as a complete native tree. Inspect
// its collection using the production catalog/window decoders, without a second
// implementation of either property format.
private struct CollectionWireState {
  var id: UInt64 = 0
  var handler: UInt64 = 0
  var windowID: UInt64 = 0
  var window: RenderCollectionWindow?
  var catalog: RenderCollectionCatalog?
  var children: [UInt64] = []
  var firstIndex: Int { window?.firstIndex ?? 0 }
  var geometry: CollectionGeometry? { catalog?.geometry }
  mutating func apply(_ output: NativeOutput) throws {
    guard !output.bytes.isEmpty else { return }
    for operation in try WireFrame.decode(output.bytes).operations {
      var reader = WireReader(operation.body)
      switch operation.opcode {
      case OperationId.createNode, OperationId.updateProps:
        let node = try reader.integer(UInt64.self)
        let kind = Int(try reader.integer(UInt16.self))
        guard kind == NodeKindId.collectionCatalog || kind == NodeKindId.collectionWindow else {
          continue
        }
        if operation.opcode == OperationId.updateProps { _ = try reader.integer(UInt64.self) }
        if kind == NodeKindId.collectionCatalog {
          id = node
          catalog = try RenderCollectionCatalog.decode(&reader)
        } else {
          windowID = node
          window = try RenderCollectionWindow.decode(&reader)
        }
        if operation.opcode == OperationId.createNode {
          let bindings = try reader.bindings()
          if kind == NodeKindId.collectionCatalog {
            handler = try #require(bindings[EventTagId.visibleRangeChanged])
          } else {
            #expect(bindings.isEmpty)
          }
        }
        #expect(reader.remaining == 0)
      case OperationId.setChildren:
        guard try reader.integer(UInt64.self) == windowID else { continue }
        let count = Int(try reader.integer(UInt32.self))
        children = try (0..<count).map { _ in try reader.integer(UInt64.self) }
      case OperationId.updateEventBindings:
        guard try reader.integer(UInt64.self) == id else { continue }
        handler = try #require(reader.bindings()[EventTagId.visibleRangeChanged])
      default: break
      }
    }
    let catalog = try #require(catalog)
    let window = try #require(window)
    try #require(
      window.firstIndex <= catalog.keys.count
        && window.keys.count <= catalog.keys.count - window.firstIndex)
    #expect(
      Array(catalog.keys[window.firstIndex..<(window.firstIndex + window.keys.count)])
        == window.keys)
    #expect(children.count == window.keys.count)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeRangesBoundActualMailMaterializationAndPreserveDelayedPaging()
    async throws
  {
    let runtime = try await NativeRuntime.open(entrypoint: "mail-collection")
    do {
      var snapshot = CollectionWireState()
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      try snapshot.apply(initial)
      let epoch = try WireFrame.decode(initial.bytes).epoch
      #expect(snapshot.geometry?.count == 20 && snapshot.children.count == 20)
      #expect(
        snapshot.catalog?.timing
          == CollectionTiming(expandMilliseconds: 240, collapseMilliseconds: 190))
      let viewport = try CollectionViewport(geometry: #require(snapshot.geometry))
      viewport.observe(CGRect(x: 0, y: 0, width: 420, height: 616))
      #expect(viewport.visibleRange == 0..<7)
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      let first = NativeEvent(
        sequence: 1, displayedRevision: initial.revision, nodeID: snapshot.id,
        handlerID: snapshot.handler, payload: .visibleRange(viewport.visibleRange))
      let narrowed = try await runtime.pump(
        monotonicNanoseconds: 3, events: EventBatch.encode(epoch: epoch, events: [first]))
      try snapshot.apply(narrowed)
      for operation in try WireFrame.decode(narrowed.bytes).operations
      where operation.opcode == OperationId.createNode
        || operation.opcode == OperationId.updateProps
      {
        var reader = WireReader(operation.body)
        _ = try reader.integer(UInt64.self)
        #expect(try reader.integer(UInt16.self) != NodeKindId.collectionCatalog)
      }
      #expect(
        snapshot.firstIndex == 0 && snapshot.children.count == 11 && snapshot.geometry?.count == 20)
      try await runtime.acknowledge(narrowed, monotonicNanoseconds: 4)
      var queue = NativeEventQueue()
      for (sequence, offset) in [(UInt64(2), 352.0), (UInt64(3), 1144.0)] {
        viewport.observe(CGRect(x: 0, y: offset, width: 420, height: 616))
        let accepted = queue.append(
          NativeEvent(
            sequence: sequence, displayedRevision: narrowed.revision,
            nodeID: snapshot.id, handlerID: snapshot.handler,
            payload: .visibleRange(viewport.visibleRange)))
        #expect(accepted)
      }
      #expect(queue.events.count == 1 && viewport.visibleRange == 13..<20)
      let loading = try await runtime.pump(
        monotonicNanoseconds: 5, events: EventBatch.encode(epoch: epoch, events: queue.events))
      try snapshot.apply(loading)
      #expect(
        snapshot.geometry?.count == 21 && snapshot.firstIndex == 9 && snapshot.children.count == 12)
      try await runtime.acknowledge(loading, monotonicNanoseconds: 6)
      let beforeDelay = try await runtime.pump(monotonicNanoseconds: 700_000_005)
      try snapshot.apply(beforeDelay)
      #expect(snapshot.geometry?.count == 21)
      try await runtime.acknowledge(beforeDelay, monotonicNanoseconds: 700_000_006)
      let loaded = try await runtime.pump(monotonicNanoseconds: 800_000_005)
      try snapshot.apply(loaded)
      #expect(
        snapshot.geometry?.count == 40 && snapshot.firstIndex == 9 && snapshot.children.count == 15)
      try await runtime.acknowledge(loaded, monotonicNanoseconds: 800_000_006)
      let idle = try await runtime.pump(monotonicNanoseconds: 1_600_000_005)
      try snapshot.apply(idle)
      #expect(snapshot.geometry?.count == 40)
      try await runtime.acknowledge(idle, monotonicNanoseconds: 1_600_000_006)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
