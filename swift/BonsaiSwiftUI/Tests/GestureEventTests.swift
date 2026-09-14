import Foundation
import Testing

@testable import BonsaiSwiftUI

private func gestureEvent(_ payload: NativeEventPayload, sequence: UInt64 = 1) -> NativeEvent {
  NativeEvent(sequence: sequence, displayedRevision: 1, nodeID: 1, handlerID: 1, payload: payload)
}

struct GestureEventTests {
  @Test func tapsRejectNonfiniteCoordinatesWithoutChangingAdmittedEvents() throws {
    let valid = NativeTap(
      localX: -1.25, localY: 2.5, globalX: -100.75, globalY: 200.125, kind: .mouse)
    var queue = NativeEventQueue()
    let admitted = queue.append(gestureEvent(.tap(valid)))
    #expect(admitted)
    for bad in [Double.nan, Double.infinity, -Double.infinity] {
      for coordinate in [\NativeTap.localX, \.localY, \.globalX, \.globalY] {
        var value = valid
        value[keyPath: coordinate] = bad
        for payload in [NativeEventPayload.tap(value), .doubleTap(value)] {
          #expect(throws: WireError.invalidHeader) {
            try EventBatch.encode(epoch: 1, events: [gestureEvent(payload, sequence: 2)])
          }
          let admitted = queue.append(gestureEvent(payload, sequence: 2))
          #expect(!admitted)
          #expect(queue.events.map(\.payload) == [.tap(valid)])
        }
      }
    }
  }

  @Test func gesturesKeepRepeatedActionsAndHonorExactQueueBudgets() throws {
    let tap = NativeTap(
      localX: -1.25, localY: 2.5, globalX: -100.75, globalY: 200.125, kind: .stylus)
    let payloads: [NativeEventPayload] = [
      .tap(tap), .tap(tap), .doubleTap(tap), .doubleTap(tap), .longPress, .longPress,
    ]
    let events = payloads.enumerated().map {
      gestureEvent($0.element, sequence: UInt64($0.offset + 1))
    }
    let encoded = try EventBatch.encode(epoch: 1, events: events)
    var queue = NativeEventQueue(maximumCount: events.count, maximumBytes: encoded.count)
    for event in events {
      let admitted = queue.append(event)
      #expect(admitted)
    }
    #expect(queue.events.map(\.payload) == payloads)
    let overflow = queue.append(gestureEvent(.longPress, sequence: 7))
    #expect(!overflow)
    var short = NativeEventQueue(maximumBytes: encoded.count - 1)
    for event in events.dropLast() {
      let admitted = short.append(event)
      #expect(admitted)
    }
    let excess = short.append(try #require(events.last))
    #expect(!excess)
    #expect(short.events.count == events.count - 1)
  }
}

extension NativeRuntimeTests {
  @Test func actualGestureTreeStagesAndRejectsMalformedUpdatesAtomically() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "native-gesture-window")
    do {
      let output = try await runtime.pump(monotonicNanoseconds: 1)
      let frame = try WireFrame.decode(output.bytes)
      let initial = try NodeStore().staging(frame).tree
      let gesture = try #require(initial.nodes.values.first { $0.kind == NodeKindId.gesture })
      #expect(gesture.bindings.count == 5)
      #expect(gesture.children.count == 1)
      let child = try #require(gesture.children.first)
      let invalidBindings = TreeFixture.operation(OperationId.updateEventBindings) {
        $0.integer(gesture.id)
        $0.integer(UInt16(1))
        $0.integer(UInt16(EventTagId.press))
        $0.integer(UInt64(999))
      }
      for operation in [
        TreeFixture.children(gesture.id, []),
        TreeFixture.children(gesture.id, [child, child]), invalidBindings,
      ] {
        #expect(throws: (any Error).self) {
          try initial.staging(
            TreeFixture.frame(
              [operation], base: frame.revision, revision: frame.revision + 1, epoch: frame.epoch))
        }
        #expect(initial.nodes[gesture.id] == gesture)
      }
      try await runtime.acknowledge(output, monotonicNanoseconds: 2)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }

  @Test func gesturesReachActualOcamlWithAllCoordinatesKindsAndReplayFencing() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "native-gesture-events")
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let frame = try WireFrame.decode(initial.bytes)
      var bindings: [Int: (UInt64, UInt64)] = [:]
      for operation in frame.operations where operation.opcode == OperationId.createNode {
        var reader = WireReader(operation.body)
        let id = try reader.integer(UInt64.self)
        guard try reader.integer(UInt16.self) == NodeKindId.gesture else { continue }
        let count = try reader.integer(UInt16.self)
        for _ in 0..<count {
          let tag = Int(try reader.integer(UInt16.self))
          bindings[tag] = (id, try reader.integer(UInt64.self))
        }
      }
      #expect(bindings.count == 3)
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      var expected = ""
      var events: [NativeEvent] = []
      let kinds: [(NativePointer.Kind, String)] = [
        (.mouse, "mouse"), (.touch, "touch"), (.stylus, "stylus"),
        (.invertedStylus, "inverted-stylus"), (.trackpad, "trackpad"), (.unknown, "unknown"),
      ]
      for (kind, name) in kinds {
        let value = NativeTap(
          localX: -1.25, localY: 2.5, globalX: -100.75, globalY: 200.125, kind: kind)
        for (payload, action) in [
          (NativeEventPayload.tap(value), "tap"), (.doubleTap(value), "double"),
        ] {
          let (node, handler) = try #require(bindings[payload.tag])
          events.append(
            NativeEvent(
              sequence: UInt64(events.count + 1), displayedRevision: frame.revision,
              nodeID: node, handlerID: handler, payload: payload))
          expected += "\(action):-1.250:2.500:-100.750:200.125:\(name);"
        }
      }
      let (node, handler) = try #require(bindings[EventTagId.longPress])
      for _ in 0..<2 {
        events.append(
          NativeEvent(
            sequence: UInt64(events.count + 1), displayedRevision: frame.revision,
            nodeID: node, handlerID: handler, payload: .longPress))
        expected += "long;"
      }
      let bytes = try EventBatch.encode(epoch: frame.epoch, events: events)
      let updated = try await runtime.pump(monotonicNanoseconds: 3, events: bytes)
      #expect(updated.status == 0)
      #expect(updated.bytes.range(of: Data(expected.utf8)) != nil)
      try await runtime.acknowledge(updated, monotonicNanoseconds: 4)
      let replay = try await runtime.pump(monotonicNanoseconds: 5, events: bytes)
      #expect(replay.bytes.isEmpty)
      try await runtime.acknowledge(replay, monotonicNanoseconds: 6)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}
