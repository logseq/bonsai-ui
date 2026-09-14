import AppKit
import Foundation
import Testing

@testable import BonsaiSwiftUI

@MainActor final class DelayedClipboardService: HostService {
  let clipboard: NativeHostService
  var holdReads = false
  var holdWrites = false
  private(set) var started: [HostRequest] = []
  private var waits: [CheckedContinuation<Void, Never>] = []
  init(_ pasteboard: NSPasteboard) { clipboard = NativeHostService(pasteboard: pasteboard) }
  func execute(_ request: HostRequest) async throws -> Data {
    started.append(request)
    let hold: Bool
    switch request {
    case .platformInformation, .setWindowTitle, .setWindowSize, .openURL, .pickFiles, .saveFile,
      .requestFocus, .clearFocus, .measureLayout, .scrollTo, .showNotice, .showNativeMenu,
      .hapticFeedback, .pickCivil:
      hold = false
    case .clipboardRead: hold = holdReads
    case .clipboardWrite: hold = holdWrites
    }
    if hold { await withCheckedContinuation { waits.append($0) } }
    try Task.checkCancellation()
    return try await clipboard.execute(request)
  }
  func release() {
    let pending = waits
    waits = []
    for continuation in pending { continuation.resume() }
  }
}

@MainActor struct HostServicesTests {
  @Test func nativeClipboardUsesUTF8AndReportsOversizedResults() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let service = NativeHostService(pasteboard: pasteboard)
    #expect(try await service.execute(.clipboardRead) == Data())
    #expect(try await service.execute(.clipboardWrite("本地😀")) == Data())
    #expect(pasteboard.string(forType: .string) == "本地😀")
    #expect(try await service.execute(.clipboardRead) == Data("本地😀".utf8))
    pasteboard.clearContents()
    pasteboard.setString(
      String(repeating: "x", count: ProtocolLimits.maxStringBytes + 1), forType: .string)
    await #expect(throws: (any Error).self) { try await service.execute(.clipboardRead) }
  }

  @Test func cancellationAndCloseFenceDelayedNativeWritesAndBoundPendingRequests() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("Keep", forType: .string)
    let service = DelayedClipboardService(pasteboard)
    service.holdWrites = true
    let dispatcher = HostEffectDispatcher(service: service, maximumPending: 2)
    var responses: [HostResponse] = []
    dispatcher.dispatch([
      .request(1, .clipboardWrite("Cancelled")), .request(2, .clipboardWrite("Closed")),
      .request(3, .clipboardWrite("Overflow")),
    ]) { responses.append($0) }
    for _ in 0..<20 { await Task.yield() }
    #expect(service.started.count == 2)
    #expect(responses.map(\.requestID) == [3])
    #expect(responses.first?.status == .error)
    dispatcher.dispatch([.cancel(1), .cancel(1), .cancel(99)]) { responses.append($0) }
    #expect(responses.filter { $0.requestID == 1 }.map(\.status) == [.cancelled])
    dispatcher.reset()
    service.release()
    for _ in 0..<20 { await Task.yield() }
    #expect(pasteboard.string(forType: .string) == "Keep")
    #expect(!responses.contains { $0.requestID == 2 })
    service.holdWrites = false
    dispatcher.dispatch([.request(1, .clipboardWrite("New lifetime"))]) { responses.append($0) }
    for _ in 0..<20 { await Task.yield() }
    #expect(pasteboard.string(forType: .string) == "New lifetime")
    #expect(responses.filter { $0.requestID == 1 }.map(\.status) == [.cancelled, .ok])
  }

  @Test func sameFrameCancellationPreventsClipboardMutation() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("Keep", forType: .string)
    let dispatcher = HostEffectDispatcher(service: NativeHostService(pasteboard: pasteboard))
    var responses: [HostResponse] = []
    dispatcher.dispatch([.request(1, .clipboardWrite("Cancelled")), .cancel(1)]) {
      responses.append($0)
    }
    for _ in 0..<20 { await Task.yield() }
    #expect(pasteboard.string(forType: .string) == "Keep")
    #expect(responses.map(\.status) == [.cancelled])
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualHostEffectsRoundTripOnlyAfterPresentationAndResume() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let service = DelayedClipboardService(pasteboard)
    let session = BonsaiSession(hostService: service)
    session.isVisible = true
    func contains(_ value: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let text) = $0.properties { return text.value == value }
        return false
      }
    }
    func button(_ title: String) throws -> RenderNodeState {
      let label = try #require(
        session.tree.nodes.values.first {
          if case .text(let text) = $0.properties { return text.value == title }
          return false
        })
      return try #require(session.tree.nodes.values.first { $0.children.contains { $0 === label } })
    }
    func settle(_ expected: String) async throws {
      for _ in 0..<100 {
        if let ticket = session.ticket { _ = try await session.presented(ticket) }
        _ = try await session.refresh()
        if contains(expected) { return }
        try await Task.sleep(for: .milliseconds(5))
      }
      Issue.record("Missing host effect result: \(expected)")
    }
    do {
      try await session.start(entrypoint: "host_effects")
      #expect(try await session.presented(#require(session.ticket)))
      #expect(session.activate(try button("Write clipboard")))
      #expect(try await session.refresh())
      #expect(pasteboard.string(forType: .string) == nil)
      session.isActive = false
      #expect(!(try await session.presented(#require(session.ticket))))
      #expect(service.started.isEmpty)
      session.isActive = true
      try await settle("Clipboard write completed")
      #expect(pasteboard.string(forType: .string) == "Written by Bonsai SwiftUI")
      if let ticket = session.ticket { _ = try await session.presented(ticket) }
      pasteboard.clearContents()
      pasteboard.setString("Read 本地😀", forType: .string)
      #expect(session.activate(try button("Read clipboard")))
      try await settle("Clipboard: Read 本地😀")
      if let ticket = session.ticket { _ = try await session.presented(ticket) }
      pasteboard.clearContents()
      pasteboard.setString(
        String(repeating: "界", count: ProtocolLimits.maxStringBytes / 3) + "x", forType: .string)
      #expect(session.activate(try button("Read clipboard")))
      try await settle("Clipboard: " + String(repeating: "界", count: 1365) + "…")
      if let ticket = session.ticket { _ = try await session.presented(ticket) }
      pasteboard.clearContents()
      pasteboard.setString(
        String(repeating: "x", count: ProtocolLimits.maxStringBytes + 1), forType: .string)
      #expect(session.activate(try button("Read clipboard")))
      try await settle("Clipboard read failed")
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func delayedHostRepliesRebaseAcrossPresentationAndCannotCrossRestart()
    async throws
  {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("Original", forType: .string)
    let service = DelayedClipboardService(pasteboard)
    service.holdReads = true
    let session = BonsaiSession(hostService: service)
    session.isVisible = true
    func button(_ title: String) throws -> RenderNodeState {
      let label = try #require(
        session.tree.nodes.values.first {
          if case .text(let value) = $0.properties { return value.value == title }
          return false
        })
      return try #require(session.tree.nodes.values.first { $0.children.contains { $0 === label } })
    }
    func hasText(_ text: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let value) = $0.properties { return value.value == text }
        return false
      }
    }
    func settle(_ text: String) async throws {
      for _ in 0..<100 {
        if let ticket = session.ticket { _ = try await session.presented(ticket) }
        _ = try await session.refresh()
        if hasText(text) { return }
        try await Task.sleep(for: .milliseconds(5))
      }
      Issue.record("Missing delayed host response: \(text)")
    }
    do {
      try await session.start(entrypoint: "host_effects")
      #expect(try await session.presented(#require(session.ticket)))
      #expect(session.activate(try button("Read clipboard")))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      for _ in 0..<20 { await Task.yield() }
      #expect(service.started.count == 1)
      #expect(session.activate(try button("Write clipboard")))
      #expect(try await session.refresh())
      let pending = try #require(session.ticket)
      service.holdReads = false
      service.release()
      for _ in 0..<20 { await Task.yield() }
      #expect(session.ticket == pending)
      #expect(try await session.presented(pending))
      try await settle("Clipboard write completed")
      if let ticket = session.ticket { _ = try await session.presented(ticket) }
      service.holdReads = true
      #expect(session.activate(try button("Read clipboard")))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      for _ in 0..<20 { await Task.yield() }
      await session.close()
      try await session.start(entrypoint: "host_effects")
      #expect(try await session.presented(#require(session.ticket)))
      service.release()
      for _ in 0..<20 { await Task.yield() }
      _ = try await session.refresh()
      #expect(hasText("No host request has run"))
      pasteboard.clearContents()
      pasteboard.setString("New lifetime", forType: .string)
      service.holdReads = false
      #expect(session.activate(try button("Read clipboard")))
      try await settle("Clipboard: New lifetime")
      await session.close()
    } catch {
      service.release()
      await session.close()
      throw error
    }
  }
}

struct HostResponseQueueTests {
  @Test func responsesUseControlIdentityAndNeverCoalesce() throws {
    func event(_ request: UInt64, node: UInt64 = 0, handler: UInt64 = 0) -> NativeEvent {
      NativeEvent(
        sequence: request, displayedRevision: 2, nodeID: node, handlerID: handler,
        payload: .hostResponse(
          HostResponse(requestID: request, status: .ok, value: Data("Value".utf8))))
    }
    var queue = NativeEventQueue(maximumCount: 2)
    let first = queue.append(event(1))
    let second = queue.append(event(2))
    let overflow = queue.append(event(3))
    #expect(first && second && !overflow)
    #expect(queue.events.count == 2)
    _ = try EventBatch.encode(epoch: 1, events: queue.events)
    for invalid in [event(1, node: 1), event(1, handler: 1)] {
      #expect(throws: (any Error).self) { try EventBatch.encode(epoch: 1, events: [invalid]) }
    }
    for response in [
      HostResponse(requestID: 0, status: .ok, value: Data()),
      HostResponse(requestID: UInt64.max, status: .ok, value: Data()),
      HostResponse(requestID: 1, status: .cancelled, value: Data([0])),
      HostResponse(
        requestID: 1, status: .ok,
        value: Data(repeating: 0, count: ProtocolLimits.maxStringBytes + 1)),
    ] {
      let invalid = NativeEvent(
        sequence: 1, displayedRevision: 2, nodeID: 0, handlerID: 0, payload: .hostResponse(response)
      )
      #expect(throws: (any Error).self) { try EventBatch.encode(epoch: 1, events: [invalid]) }
    }
  }
}
