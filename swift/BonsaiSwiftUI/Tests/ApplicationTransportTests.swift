import CryptoKit
import Foundation
import Testing

@testable import BonsaiSwiftUI

private func applicationEvent(_ payload: NativeEventPayload, sequence: UInt64 = 1) -> NativeEvent {
  NativeEvent(sequence: sequence, displayedRevision: 1, nodeID: 0, handlerID: 0, payload: payload)
}

private func applicationDigest(_ bytes: Data) -> String {
  "\(bytes.count):" + Insecure.MD5.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

struct ApplicationTransportTests {
  private func request(_ id: UInt64, _ bytes: Data) -> WireOperation {
    TreeFixture.operation(OperationId.applicationRequest) {
      $0.integer(id)
      $0.integer(UInt32(bytes.count))
      $0.bytes.append(bytes)
    }
  }

  @Test func applicationRequestsStageAtomicallyWithIndependentIDOwnership() throws {
    let initial = TreeFixture.initial.operations + [TreeFixture.environment()]
    let state = try FrameState().staging(TreeFixture.frame(initial))
    let opaque = Data([0, 255, 128, 0])
    let next = try state.staging(
      TreeFixture.frame(
        [
          request(2, opaque), TreeFixture.host(2, kind: 1), request(1, Data()),
        ], base: 1, revision: 2))
    #expect(next.applicationRequests.map(\.requestID) == [2, 1])
    #expect(next.applicationRequests.map(\.payload) == [opaque, Data()])
    for id: UInt64 in [1, 2] {
      #expect(throws: (any Error).self) {
        try next.staging(TreeFixture.frame([request(id, opaque)], base: 2, revision: 3))
      }
      #expect(throws: (any Error).self) {
        try next.staging(TreeFixture.frame(initial + [request(id, opaque)], revision: 3))
      }
    }
    let restarted = try next.staging(TreeFixture.frame(initial + [request(1, opaque)], epoch: 8))
    #expect(restarted.applicationRequests.count == 1)
    let maximum = Data(repeating: 255, count: ProtocolLimits.maxApplicationPayloadBytes)
    _ = try next.staging(TreeFixture.frame([request(3, maximum)], base: 2, revision: 3))
    let valid = request(3, opaque)
    var invalid = (0..<valid.body.count).map {
      WireOperation(opcode: valid.opcode, body: valid.body.prefix($0))
    }
    invalid += [
      request(0, opaque), request(UInt64.max, opaque),
      request(3, maximum + Data([0])),
      WireOperation(opcode: valid.opcode, body: valid.body + Data([0])),
    ]
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try next.staging(
          TreeFixture.frame(
            [
              TreeFixture.text(2, "Never committed", update: true), operation,
            ], base: 2, revision: 3))
      }
      #expect(next.tree.revision == 2)
    }
    #expect(throws: (any Error).self) {
      try next.staging(TreeFixture.frame([valid, valid], base: 2, revision: 3))
    }
  }

  @Test func boundedOpaqueEventsOwnTheirBytesAndDoNotCoalesce() throws {
    let count = 64
    let pointer = UnsafeMutableRawPointer.allocate(byteCount: count, alignment: 1)
    defer { pointer.deallocate() }
    pointer.initializeMemory(as: UInt8.self, repeating: 255, count: count)
    let borrowed = Data(bytesNoCopy: pointer, count: count, deallocator: .none)
    var queue = NativeEventQueue(maximumCount: 3)
    #expect({ queue.append(applicationEvent(.applicationResponse(1, borrowed))) }())
    #expect({ queue.append(applicationEvent(.applicationEvent(borrowed), sequence: 2)) }())
    pointer.initializeMemory(as: UInt8.self, repeating: 0, count: count)
    let expected = Data(repeating: 255, count: count)
    #expect(
      queue.events.map(\.payload) == [
        .applicationResponse(1, expected), .applicationEvent(expected),
      ])
    #expect({ queue.append(applicationEvent(.applicationEvent(expected), sequence: 3)) }())
    #expect({ !queue.append(applicationEvent(.applicationEvent(expected), sequence: 4)) }())
    #expect(queue.events.count == 3)
    let tooLarge = Data(repeating: 0, count: ProtocolLimits.maxApplicationPayloadBytes + 1)
    for payload in [
      NativeEventPayload.applicationResponse(1, tooLarge), .applicationEvent(tooLarge),
      .applicationResponse(0, Data()), .applicationRequestError(UInt64.max, .unavailable),
      .applicationRequestError(1, .handlerFailed(String(repeating: "😀", count: 1025))),
    ] {
      #expect(throws: (any Error).self) {
        try EventBatch.encode(epoch: 1, events: [applicationEvent(payload)])
      }
    }
    for payload in [
      NativeEventPayload.applicationEvent(Data()), .applicationResponse(1, Data()),
      .applicationRequestError(1, .unavailable),
    ] {
      #expect(throws: (any Error).self) {
        try EventBatch.encode(
          epoch: 1,
          events: [
            NativeEvent(
              sequence: 1, displayedRevision: 1, nodeID: 1, handlerID: 1, payload: payload)
          ])
      }
    }
  }

  @Test func repliesDrainIndividuallyWithoutLosingBudgetOrSurroundingInput() throws {
    let payloads: [NativeEventPayload] = [
      .applicationEvent(Data([0])), .applicationResponse(1, Data()),
      .applicationRequestError(2, .cancelled), .applicationEvent(Data([255])),
    ]
    let events = payloads.enumerated().map {
      applicationEvent($0.element, sequence: UInt64($0.offset + 1))
    }
    let size = try EventBatch.encode(epoch: 1, events: events).count
    var queue = NativeEventQueue(maximumCount: 4, maximumBytes: size)
    for event in events { #expect({ queue.append(event) }()) }
    #expect({ !queue.append(applicationEvent(.applicationEvent(Data()), sequence: 5)) }())
    for payload in payloads {
      #expect(queue.pumpEvents.map(\.payload) == [payload])
      queue.removePrefix(queue.pumpEvents.count)
    }
    #expect(queue.events.isEmpty)
    for event in events { #expect({ queue.append(event) }()) }
    queue.removeAll()
    for event in events { #expect({ queue.append(event) }()) }
  }
}

private struct ApplicationRuntimeHarness {
  let runtime: NativeRuntime
  var state = FrameState()
  var clock: Int64 = 0
  var sequence: UInt64 = 0

  mutating func pump(_ payloads: [NativeEventPayload] = [], button: String? = nil) async throws
    -> Int32
  {
    var events: [NativeEvent] = []
    if let button {
      let node = try #require(
        state.tree.nodes.values.first { node in
          node.bindings[EventTagId.press] != nil
            && node.children.contains { child in
              if case .text(let text) = state.tree.nodes[child]?.properties {
                return text.value == button
              }
              return false
            }
        })
      sequence += 1
      events.append(
        NativeEvent(
          sequence: sequence, displayedRevision: state.tree.revision,
          nodeID: node.id, handlerID: try #require(node.bindings[EventTagId.press])))
    }
    for payload in payloads {
      sequence += 1
      events.append(
        NativeEvent(
          sequence: sequence, displayedRevision: state.tree.revision,
          nodeID: 0, handlerID: 0, payload: payload))
    }
    clock += 1
    let output = try await runtime.pump(
      monotonicNanoseconds: clock,
      events: events.isEmpty ? Data() : EventBatch.encode(epoch: state.tree.epoch, events: events))
    if !output.bytes.isEmpty {
      state = try state.staging(WireFrame.decode(output.bytes))
    } else {
      state.applicationRequests = []
    }
    clock += 1
    try await runtime.acknowledge(output, monotonicNanoseconds: clock)
    return output.status
  }

  var history: String {
    state.tree.nodes.values.compactMap {
      if case .text(let text) = $0.properties, text.value.contains(";") { return text.value }
      return nil
    }.joined()
  }
}

extension NativeRuntimeTests {
  @Test func applicationOpaqueRepliesEventsAndEveryErrorReachActualOcaml() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "native-application-bridge")
    do {
      var app = ApplicationRuntimeHarness(runtime: runtime)
      _ = try await app.pump()
      _ = try await app.pump(button: "First")
      let first = try #require(app.state.applicationRequests.first)
      #expect(first.payload == Data([0, 111, 110, 101, 255]))
      _ = try await app.pump(button: "Second")
      let second = try #require(app.state.applicationRequests.first)
      #expect(second.payload == Data([128, 116, 119, 111, 0]))
      let opaque = Data([255, 0, 128])
      let status = try await app.pump([
        .applicationResponse(second.requestID, opaque),
        .applicationResponse(first.requestID, Data()), .applicationEvent(opaque),
        .applicationEvent(Data()),
      ])
      #expect(status == 0)
      #expect(
        app.history
          == "Second:ok:\(applicationDigest(opaque));First:ok:\(applicationDigest(Data()));event:\(applicationDigest(opaque));event:\(applicationDigest(Data()));"
      )
      let message = String(repeating: "😀", count: 1024)
      let failures: [(BonsaiApplicationError, String)] = [
        (.unavailable, "unavailable"), (.payloadTooLarge, "payload-too-large"),
        (.handlerFailed(message), "handler-failed:\(applicationDigest(Data(message.utf8)))"),
        (.cancelled, "cancelled"), (.shutdown, "shutdown"), (.runtimeReplaced, "runtime-replaced"),
        (.invalidResponse("本地\0"), "invalid-response:\(applicationDigest(Data("本地\0".utf8)))"),
      ]
      for (failure, expected) in failures {
        _ = try await app.pump(button: "Second")
        let request = try #require(app.state.applicationRequests.first)
        let outcome1 = try await app.pump([.applicationRequestError(request.requestID, failure)])
        #expect(outcome1 == 0)
        #expect(app.history.hasSuffix("Second:\(expected);"))
      }
      _ = try await app.pump(button: "Large")
      let large = try #require(app.state.applicationRequests.first)
      #expect(
        large.payload == Data(repeating: 255, count: ProtocolLimits.maxApplicationPayloadBytes))
      let outcome2 = try await app.pump([
        .applicationResponse(large.requestID, large.payload), .applicationEvent(large.payload),
      ])
      #expect(outcome2 == 0)
      #expect(
        app.history.hasSuffix(
          "Large:ok:\(applicationDigest(large.payload));event:\(applicationDigest(large.payload));")
      )
      _ = try await app.pump(button: "Overflow")
      #expect(app.state.applicationRequests.isEmpty)
      #expect(app.history.hasSuffix("Overflow:payload-too-large;"))
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }

  @Test func cancelledApplicationReplyCannotDiscardQueuedUiOrOtherReplies() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "native-application-bridge")
    do {
      var app = ApplicationRuntimeHarness(runtime: runtime)
      _ = try await app.pump()
      _ = try await app.pump(button: "First")
      let first = try #require(app.state.applicationRequests.first)
      _ = try await app.pump(button: "Second")
      let second = try #require(app.state.applicationRequests.first)
      _ = try await app.pump(button: "Cancel")
      #expect(app.history == "First:cancelled;")
      var queue = NativeEventQueue()
      let payloads: [NativeEventPayload] = [
        .applicationResponse(first.requestID, Data()), .press,
        .applicationEvent(Data([255])), .applicationResponse(second.requestID, Data()),
      ]
      let increment = try #require(
        app.state.tree.nodes.values.first { node in
          node.bindings[EventTagId.press] != nil
            && node.children.contains {
              if case .text(let text) = app.state.tree.nodes[$0]?.properties {
                return text.value == "Increment"
              }
              return false
            }
        })
      for (index, payload) in payloads.enumerated() {
        let event =
          payload == .press
          ? NativeEvent(
            sequence: UInt64(index + 1), displayedRevision: app.state.tree.revision,
            nodeID: increment.id, handlerID: try #require(increment.bindings[EventTagId.press]))
          : applicationEvent(payload, sequence: UInt64(index + 1))
        #expect({ queue.append(event) }())
      }
      var statuses: [Int32] = []
      while !queue.events.isEmpty {
        let batch = queue.pumpEvents
        let payloads = batch.map(\.payload)
        statuses.append(
          try await app.pump(
            payloads.filter { $0 != .press },
            button: payloads.contains(.press) ? "Increment" : nil))
        queue.removePrefix(batch.count)
      }
      #expect(statuses == [1, 0, 0])
      #expect(
        app.history
          == "First:cancelled;increment;event:\(applicationDigest(Data([255])));Second:ok:\(applicationDigest(Data()));"
      )
      let outcome3 = try await app.pump([.applicationResponse(second.requestID, Data())])
      #expect(outcome3 == 1)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func applicationWithoutProviderResolvesUnavailableAfterPresentation()
    async throws
  {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-application-bridge")
      _ = try await session.presented(#require(session.ticket))
      let button = try #require(
        session.tree.nodes.values.first { node in
          node.bindings[EventTagId.press] != nil
            && node.children.contains {
              if case .text(let text) = $0.properties { return text.value == "First" }
              return false
            }
        })
      #expect(session.activate(button))
      _ = try await session.refresh()
      let requestTicket = try #require(session.ticket)
      session.isActive = false
      #expect(try await session.presented(requestTicket) == false)
      session.isActive = true
      _ = try await session.presented(requestTicket)
      for _ in 0..<8 {
        _ = try await session.refresh()
        if let ticket = session.ticket { _ = try await session.presented(ticket) }
      }
      #expect(
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value == "First:unavailable;" }
          return false
        })
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
