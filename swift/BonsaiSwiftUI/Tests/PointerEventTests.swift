import Foundation
import Testing

@testable import BonsaiSwiftUI

private func pointerEvent(_ payload: NativeEventPayload, sequence: UInt64 = 1) -> NativeEvent {
  NativeEvent(sequence: sequence, displayedRevision: 1, nodeID: 1, handlerID: 1, payload: payload)
}

struct PointerEventTests {
  @Test func invalidCoordinatesAndIdentifiersNeverEnterTheQueue() throws {
    let valid = NativePointer(
      id: 0, localX: -1.25, localY: 2.5, globalX: -100.75, globalY: 200.125,
      kind: .mouse, buttons: UInt32.max)
    var invalid: [NativePointer] = []
    for bad in [Double.nan, Double.infinity, -Double.infinity] {
      for coordinate in [\NativePointer.localX, \.localY, \.globalX, \.globalY] {
        var value = valid
        value[keyPath: coordinate] = bad
        invalid.append(value)
      }
    }
    var badID = valid
    badID.id = UInt64(Int64.max) + 1
    invalid.append(badID)
    badID.id = UInt64.max
    invalid.append(badID)
    for value in invalid {
      for payload in [
        NativeEventPayload.pointerEnter(value), .pointerLeave(value),
        .pointerDown(value), .pointerUp(value),
      ] {
        #expect(throws: WireError.invalidHeader) {
          try EventBatch.encode(epoch: 1, events: [pointerEvent(payload)])
        }
        var queue = NativeEventQueue()
        let accepted = queue.append(pointerEvent(payload))
        #expect(!accepted)
        #expect(queue.events.isEmpty)
      }
    }
  }

  @Test func transitionsPreserveOrderAndRespectExactQueueBounds() throws {
    let value = NativePointer(
      id: UInt64(Int64.max), localX: 0, localY: 0, globalX: 0, globalY: 0,
      kind: .unknown, buttons: 0)
    let payloads: [NativeEventPayload] = [
      .pointerEnter(value), .pointerEnter(value), .pointerDown(value), .pointerUp(value),
      .pointerLeave(value), .pointerLeave(value),
    ]
    let events = payloads.enumerated().map {
      pointerEvent($0.element, sequence: UInt64($0.offset + 1))
    }
    let bytes = try EventBatch.encode(epoch: 1, events: events)
    var exact = NativeEventQueue(maximumCount: events.count, maximumBytes: bytes.count)
    for event in events {
      let accepted = exact.append(event)
      #expect(accepted)
    }
    #expect(exact.events.map(\.payload) == payloads)
    let excessAccepted = exact.append(pointerEvent(.pointerUp(value), sequence: 7))
    #expect(!excessAccepted)
    var short = NativeEventQueue(maximumBytes: bytes.count - 1)
    for event in events.dropLast() {
      let accepted = short.append(event)
      #expect(accepted)
    }
    let overflowAccepted = short.append(try #require(events.last))
    #expect(!overflowAccepted)
    #expect(short.events.count == events.count - 1)
  }
}

extension NativeRuntimeTests {
  @Test func pointerEventsReachActualOcamlHandlersWithEveryFieldAndKind() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "native-pointer-events")
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let frame = try WireFrame.decode(initial.bytes)
      var bindings: [Int: (UInt64, UInt64)] = [:]
      for operation in frame.operations where operation.opcode == OperationId.createNode {
        var reader = WireReader(operation.body)
        let id = try reader.integer(UInt64.self)
        let kind = Int(try reader.integer(UInt16.self))
        guard kind == NodeKindId.hoverRegion || kind == NodeKindId.gesture else { continue }
        if kind == NodeKindId.hoverRegion { _ = try reader.integer(UInt8.self) }
        let count = try reader.integer(UInt16.self)
        for _ in 0..<count {
          let tag = Int(try reader.integer(UInt16.self))
          bindings[tag] = (id, try reader.integer(UInt64.self))
        }
      }
      #expect(bindings.count == 4)
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      var sequence: UInt64 = 0
      var expected: [String] = []
      var events: [NativeEvent] = []
      let kinds: [(NativePointer.Kind, String)] = [
        (.mouse, "mouse"), (.touch, "touch"), (.stylus, "stylus"),
        (.invertedStylus, "inverted-stylus"), (.trackpad, "trackpad"), (.unknown, "unknown"),
      ]
      for (kind, name) in kinds {
        let value = NativePointer(
          id: kind == .mouse ? 0 : UInt64(Int64.max),
          localX: -1.25, localY: 2.5, globalX: -100.75, globalY: 200.125,
          kind: kind, buttons: kind == .mouse ? 0 : UInt32.max)
        for (payload, action) in [
          (NativeEventPayload.pointerEnter(value), "enter"), (.pointerDown(value), "down"),
          (.pointerUp(value), "up"), (.pointerLeave(value), "leave"),
        ] {
          sequence += 1
          let (node, handler) = try #require(bindings[payload.tag])
          events.append(
            NativeEvent(
              sequence: sequence, displayedRevision: frame.revision, nodeID: node,
              handlerID: handler, payload: payload))
          expected.append(
            "\(action):\(value.id):-1.250:2.500:-100.750:200.125:\(name):\(value.buttons);")
        }
      }
      let batch = try EventBatch.encode(epoch: frame.epoch, events: events)
      let updated = try await runtime.pump(monotonicNanoseconds: 3, events: batch)
      #expect(updated.status == 0)
      #expect(updated.bytes.range(of: Data(expected.joined().utf8)) != nil)
      try await runtime.acknowledge(updated, monotonicNanoseconds: 4)
      let replay = try await runtime.pump(monotonicNanoseconds: 5, events: batch)
      #expect(replay.bytes.isEmpty)
      try await runtime.acknowledge(replay, monotonicNanoseconds: 6)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
