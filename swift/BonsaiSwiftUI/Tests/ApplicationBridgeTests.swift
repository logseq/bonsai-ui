import Foundation
import Testing

@testable import BonsaiSwiftUI

@MainActor private func bridgeButton(_ session: BonsaiSession, _ label: String) throws
  -> RenderNodeState
{
  try #require(
    session.tree.nodes.values.first { node in
      node.bindings[EventTagId.press] != nil
        && node.children.contains {
          if case .text(let text) = $0.properties { return text.value == label }
          return false
        }
    })
}

@MainActor private func bridgeHistory(_ session: BonsaiSession) -> String {
  session.tree.nodes.values.compactMap {
    if case .text(let text) = $0.properties, text.value.contains(";") { return text.value }
    return nil
  }.joined()
}

@MainActor private func bridgeSettle(_ session: BonsaiSession, until condition: () -> Bool)
  async throws
{
  let deadline = ContinuousClock.now + .seconds(3)
  while !condition(), ContinuousClock.now < deadline {
    _ = try await session.refresh()
    if let ticket = session.ticket { _ = try await session.presented(ticket) }
    try await Task.sleep(for: .milliseconds(2))
  }
  try #require(condition())
}

@MainActor private func bridgePress(_ session: BonsaiSession, _ label: String) async throws {
  #expect(session.activate(try bridgeButton(session, label)))
  _ = try await session.refresh()
  if let ticket = session.ticket { _ = try await session.presented(ticket) }
}

extension NativeRuntimeTests {
  @Test @MainActor func applicationProviderWaitsForPresentationAndEchoesOpaqueBytes() async throws {
    var calls: [Data] = []
    var connected = 0
    var disconnected = 0
    var sink: BonsaiApplicationEvents?
    let bridge = BonsaiApplicationBridge(
      request: { bytes in
        calls.append(bytes)
        return bytes
      },
      connected: {
        sink = $0
        connected += 1
      }, disconnected: { disconnected += 1 })
    let session = BonsaiSession(applicationBridge: bridge)
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-application-bridge")
      #expect(connected == 0)
      _ = try await session.presented(#require(session.ticket))
      #expect(connected == 1)
      #expect(session.activate(try bridgeButton(session, "First")))
      _ = try await session.refresh()
      let requestTicket = try #require(session.ticket)
      #expect(calls.isEmpty)
      session.isActive = false
      #expect(try await session.presented(requestTicket) == false)
      #expect(calls.isEmpty)
      session.isActive = true
      _ = try await session.presented(requestTicket)
      try await bridgeSettle(session) { bridgeHistory(session).contains("First:ok:5:") }
      #expect(calls == [Data([0, 111, 110, 101, 255])])
      #expect(connected == 1)
      let sender = try #require(sink)
      try sender.send(Data([128, 0, 255]))
      try await bridgeSettle(session) { bridgeHistory(session).contains("event:3:") }
      await session.close()
      await session.close()
      #expect(disconnected == 1)
      #expect(throws: BonsaiApplicationEvents.SendError.closed) { try sender.send(Data()) }
    } catch {
      await session.close()
      throw error
    }
  }

  @Test @MainActor func applicationDelayedCancellationKeepsUiAndOtherRepliesAlive() async throws {
    var entered = 0
    let bridge = BonsaiApplicationBridge(request: { bytes in
      entered += 1
      try await Task.sleep(for: .milliseconds(bytes.first == 0 ? 80 : 10))
      return bytes
    })
    let session = BonsaiSession(applicationBridge: bridge)
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-application-bridge")
      _ = try await session.presented(#require(session.ticket))
      try await bridgePress(session, "First")
      try await bridgePress(session, "Second")
      try await bridgePress(session, "Cancel")
      try await bridgePress(session, "Increment")
      try await bridgeSettle(session) { bridgeHistory(session).contains("Second:ok:5:") }
      try await Task.sleep(for: .milliseconds(100))
      for _ in 0..<4 {
        _ = try await session.refresh()
        if let ticket = session.ticket { _ = try await session.presented(ticket) }
      }
      let history = bridgeHistory(session)
      #expect(entered == 2)
      #expect(history.contains("First:cancelled;"))
      #expect(history.contains("increment;"))
      #expect(!history.contains("First:ok:"))
      try await bridgePress(session, "Increment")
      #expect(bridgeHistory(session).hasSuffix("increment;"))
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }

  @Test @MainActor func applicationErrorsAreBoundedAndOversizedResponsesResolve() async throws {
    let message = String(repeating: "😀", count: 2000)
    let bridge = BonsaiApplicationBridge(request: { bytes in
      if bytes.first == 0 { throw BonsaiApplicationError.handlerFailed(message) }
      return Data(repeating: 255, count: 1_048_577)
    })
    let session = BonsaiSession(applicationBridge: bridge)
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-application-bridge")
      _ = try await session.presented(#require(session.ticket))
      try await bridgePress(session, "First")
      try await bridgeSettle(session) {
        bridgeHistory(session).contains("First:handler-failed:4096:")
      }
      try await bridgePress(session, "Second")
      try await bridgeSettle(session) {
        bridgeHistory(session).contains("Second:payload-too-large;")
      }
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }

  @Test @MainActor func applicationEventBackpressurePreservesQueuedInputAndPendingReply()
    async throws
  {
    var sink: BonsaiApplicationEvents?
    var started = false
    var release: CheckedContinuation<Data, Never>?
    let bridge = BonsaiApplicationBridge(
      request: { _ in
        started = true
        return await withCheckedContinuation { release = $0 }
      }, connected: { sink = $0 })
    let session = BonsaiSession(applicationBridge: bridge)
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-application-bridge")
      _ = try await session.presented(#require(session.ticket))
      try await bridgePress(session, "Second")
      try await bridgeSettle(session) { started }
      let sender = try #require(sink)
      session.isActive = false
      let oversized = Data(repeating: 0, count: 1_048_577)
      #expect(throws: BonsaiApplicationEvents.SendError.payloadTooLarge) {
        try sender.send(oversized)
      }
      for _ in 0..<1024 { try sender.send(Data([255])) }
      #expect(throws: BonsaiApplicationEvents.SendError.backpressure) { try sender.send(Data()) }
      release?.resume(returning: Data([0, 128]))
      release = nil
      try await Task.sleep(for: .milliseconds(5))
      session.isActive = true
      try await bridgeSettle(session) { bridgeHistory(session).contains("Second:ok:2:") }
      #expect(bridgeHistory(session).components(separatedBy: "event:1:").count - 1 == 1024)
      try sender.send(Data())
      try await bridgeSettle(session) { bridgeHistory(session).contains("event:0:") }
      await session.close()
    } catch {
      release?.resume(returning: Data())
      await session.close()
      throw error
    }
  }

  @Test @MainActor func applicationCloseCancelsTasksAndFencesOldSendersAcrossRestart() async throws
  {
    var sinks: [BonsaiApplicationEvents] = []
    var started = false
    var wasCancelled = false
    var finish: CheckedContinuation<Data, Never>?
    let bridge = BonsaiApplicationBridge(
      request: { _ in
        started = true
        let result = await withCheckedContinuation { finish = $0 }
        wasCancelled = Task.isCancelled
        return result
      }, connected: { sinks.append($0) })
    let session = BonsaiSession(applicationBridge: bridge)
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-application-bridge")
      _ = try await session.presented(#require(session.ticket))
      try await bridgePress(session, "Second")
      try await bridgeSettle(session) { started }
      await session.close()
      try await session.start(entrypoint: "native-application-bridge")
      _ = try await session.presented(#require(session.ticket))
      try #require(sinks.count == 2)
      #expect(throws: BonsaiApplicationEvents.SendError.closed) { try sinks[0].send(Data([0])) }
      finish?.resume(returning: Data([255]))
      finish = nil
      try await bridgeSettle(session) { wasCancelled }
      try sinks[1].send(Data([128]))
      try await bridgeSettle(session) { bridgeHistory(session).contains("event:1:") }
      #expect(!bridgeHistory(session).contains("Second:"))
      await session.close()
    } catch {
      finish?.resume(returning: Data())
      await session.close()
      throw error
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func applicationOwnsNotificationSubscriptionAndStopsItOnClose() async throws {
    let name = Notification.Name("BonsaiApplicationBridgeTest-\(UUID().uuidString)")
    var observer: NSObjectProtocol?
    var observed = 0
    let bridge = BonsaiApplicationBridge(
      request: { $0 },
      connected: { events in
        observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main)
        { notification in
          guard let payload = notification.userInfo?["bytes"] as? Data else { return }
          MainActor.assumeIsolated {
            observed += 1
            try? events.send(payload)
          }
        }
      },
      disconnected: {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
      })
    let session = BonsaiSession(applicationBridge: bridge)
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-application-bridge")
      _ = try await session.presented(#require(session.ticket))
      NotificationCenter.default.post(name: name, object: nil, userInfo: ["bytes": Data([255])])
      NotificationCenter.default.post(name: name, object: nil, userInfo: ["bytes": Data([128, 0])])
      try await bridgeSettle(session) { bridgeHistory(session).contains("event:2:") }
      #expect(bridgeHistory(session).hasPrefix("event:1:"))
      #expect(observed == 2)
      await session.close()
      NotificationCenter.default.post(name: name, object: nil, userInfo: ["bytes": Data()])
      #expect(observed == 2)
      #expect(observer == nil)
    } catch {
      await session.close()
      if let observer { NotificationCenter.default.removeObserver(observer) }
      throw error
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func applicationRequestConcurrencyIsBoundedAndExcessRequestsResolve()
    async throws
  {
    var waiting: [CheckedContinuation<Data, Never>] = []
    let bridge = BonsaiApplicationBridge(request: { _ in
      await withCheckedContinuation { waiting.append($0) }
    })
    let session = BonsaiSession(applicationBridge: bridge)
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-application-bridge")
      _ = try await session.presented(#require(session.ticket))
      let button = try bridgeButton(session, "Second")
      for _ in 0..<300 { #expect(session.activate(button)) }
      _ = try await session.refresh()
      _ = try await session.presented(#require(session.ticket))
      try await bridgeSettle(session) { waiting.count == 256 }
      for continuation in waiting { continuation.resume(returning: Data()) }
      waiting.removeAll()
      try await bridgeSettle(session) {
        bridgeHistory(session).components(separatedBy: "Second:").count - 1 == 300
      }
      let history = bridgeHistory(session)
      #expect(history.components(separatedBy: "Second:unavailable;").count - 1 == 44)
      #expect(history.components(separatedBy: "Second:ok:0:").count - 1 == 256)
      await session.close()
    } catch {
      for continuation in waiting { continuation.resume(returning: Data()) }
      await session.close()
      throw error
    }
  }
}
