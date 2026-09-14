import Foundation
import Testing

@testable import BonsaiSwiftUI

private func keyboardEvent(_ key: NativeKey, sequence: UInt64 = 1) -> NativeEvent {
  NativeEvent(sequence: sequence, displayedRevision: 1, nodeID: 1, handlerID: 1, payload: .key(key))
}

struct KeyboardEventTests {
  @Test func invalidKeyIdentifiersCannotReplaceOrDiscardAdmittedEvents() throws {
    let valid = NativeKey(logical: 97, physical: 0, action: .down, modifiers: 0)
    var queue = NativeEventQueue()
    let admitted = queue.append(keyboardEvent(valid))
    #expect(admitted)
    for bad in [UInt64(Int64.max) + 1, UInt64.max] {
      for field in [\NativeKey.logical, \.physical] {
        var key = valid
        key[keyPath: field] = bad
        #expect(throws: WireError.invalidHeader) {
          try EventBatch.encode(epoch: 1, events: [keyboardEvent(key, sequence: 2)])
        }
        let invalid = queue.append(keyboardEvent(key, sequence: 2))
        #expect(!invalid)
        #expect(queue.events.map(\.payload) == [.key(valid)])
      }
    }
  }

  @Test func repeatedKeysKeepEveryActionAndHonorExactEventAndByteBudgets() throws {
    let actions: [NativeKey.Action] = [.down, .repeat, .repeat, .up, .down, .up]
    let events = actions.enumerated().map { index, action in
      keyboardEvent(
        NativeKey(
          logical: 0, physical: UInt64(Int64.max), action: action,
          modifiers: UInt32.max), sequence: UInt64(index + 1))
    }
    let bytes = try EventBatch.encode(epoch: 1, events: events)
    var queue = NativeEventQueue(maximumCount: events.count, maximumBytes: bytes.count)
    for event in events {
      let admitted = queue.append(event)
      #expect(admitted)
    }
    #expect(queue.events.map(\.payload) == events.map(\.payload))
    let overflow = queue.append(
      keyboardEvent(
        NativeKey(logical: 0, physical: 0, action: .up, modifiers: 0), sequence: 7))
    #expect(!overflow)
    var short = NativeEventQueue(maximumBytes: bytes.count - 1)
    for event in events.dropLast() {
      let admitted = short.append(event)
      #expect(admitted)
    }
    let excess = short.append(try #require(events.last))
    #expect(!excess)
    #expect(short.events.map(\.payload) == events.dropLast().map(\.payload))
  }
}

extension NativeRuntimeTests {
  @Test func keyboardEventsReachActualOcamlWithEveryFieldAndPreserveRepeatsAndReplayFence()
    async throws
  {
    let runtime = try await NativeRuntime.open(entrypoint: "native-keyboard-events")
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let frame = try WireFrame.decode(initial.bytes)
      var binding: (node: UInt64, handler: UInt64)?
      for operation in frame.operations where operation.opcode == OperationId.createNode {
        var reader = WireReader(operation.body)
        let node = try reader.integer(UInt64.self)
        guard try reader.integer(UInt16.self) == NodeKindId.keyboardListener else { continue }
        _ = try reader.integer(UInt8.self)
        _ = try reader.integer(UInt8.self)
        let count = try reader.integer(UInt16.self)
        #expect(count == 1)
        let tag = try reader.integer(UInt16.self)
        #expect(tag == EventTagId.key)
        binding = (node, try reader.integer(UInt64.self))
      }
      let owner = try #require(binding)
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      var events: [NativeEvent] = []
      var expected = ""
      for (logical, physical, modifiers) in [
        (UInt64(0), UInt64(Int64.max), UInt32.max),
        (UInt64(Int64.max), UInt64(0), UInt32(0)),
        (UInt64(97), UInt64(4), UInt32(0x120000)),
      ] {
        for (action, name) in [
          (NativeKey.Action.down, "down"), (.repeat, "repeat"), (.repeat, "repeat"), (.up, "up"),
        ] {
          events.append(
            NativeEvent(
              sequence: UInt64(events.count + 1),
              displayedRevision: frame.revision, nodeID: owner.node, handlerID: owner.handler,
              payload: .key(
                NativeKey(
                  logical: logical, physical: physical, action: action,
                  modifiers: modifiers))))
          expected += "\(logical):\(physical):\(name):\(modifiers);"
        }
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
