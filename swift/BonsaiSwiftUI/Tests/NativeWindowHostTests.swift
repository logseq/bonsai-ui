import AppKit
import Testing

@testable import BonsaiSwiftUI

@MainActor private func hostTestWindow(_ title: String) -> NSWindow {
  initializeAccessibilityApplication()
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
    styleMask: [.titled, .resizable], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.title = title
  return window
}

@MainActor struct NativeWindowHostTests {
  @Test func requestsUseTheOwnedWindowAndRespectDeclarativeTitleChanges() async throws {
    let first = hostTestWindow("First original")
    let second = hostTestWindow("Second original")
    defer {
      first.close()
      second.close()
    }
    let host = NativeWindowHost()
    let owner = NSView()
    let replacement = NSView()
    let service = NativeHostService(windowHost: host)
    await #expect(throws: (any Error).self) {
      try await service.execute(.setWindowTitle("Unbound"))
    }
    await #expect(throws: (any Error).self) {
      try await service.execute(.setWindowSize(width: 760, height: 560))
    }
    host.attach(window: first, title: "Application", owner: owner)
    #expect(first.title == "Application")
    #expect(try await service.execute(.setWindowTitle("Window 本地😀")) == Data())
    #expect(first.title == "Window 本地😀")
    #expect(second.title == "Second original")
    host.attach(window: first, title: "Application", owner: owner)
    #expect(first.title == "Window 本地😀")
    host.attach(window: first, title: "New application title", owner: owner)
    #expect(first.title == "New application title")
    host.attach(window: first, title: nil, owner: owner)
    #expect(first.title == "First original")
    #expect(try await service.execute(.setWindowSize(width: 760, height: 560)) == Data())
    #expect(first.contentRect(forFrameRect: first.frame).size == CGSize(width: 760, height: 560))
    #expect(second.contentRect(forFrameRect: second.frame).size == CGSize(width: 480, height: 360))
    host.attach(window: second, title: "Moved", owner: replacement)
    #expect(first.title == "First original")
    host.detach(owner: owner)
    #expect(try await service.execute(.setWindowTitle("")) == Data())
    #expect(second.title == "")
    host.reset()
    #expect(second.title == "Second original")
    await #expect(throws: (any Error).self) { try await service.execute(.setWindowTitle("Closed")) }
    host.attach(window: second, title: "Application", owner: replacement)
    second.title = "Changed by another owner"
    host.reset()
    #expect(second.title == "Changed by another owner")
  }

  @Test func windowClosureAndOwnerReplacementEndPendingLayoutRequests() async throws {
    for closeWindow in [true, false] {
      let window = hostTestWindow("Layout lifetime")
      defer { window.close() }
      let host = NativeWindowHost()
      let owner = NSView()
      let replacement = NSView()
      host.attach(window: window, title: nil, owner: owner)
      let target = NodeLayoutTarget(identity: RenderIdentity(epoch: 1, node: 2))
      target.attach(UUID(), registry: host.layoutRequests)
      let task = Task { try await host.layoutRequests.measure(target, valid: { true }) }
      for _ in 0..<100 {
        if host.layoutRequests.subscriptionCount == 1 { break }
        await Task.yield()
      }
      try #require(host.layoutRequests.subscriptionCount == 1)
      if closeWindow {
        window.close()
      } else {
        host.attach(window: window, title: nil, owner: replacement)
      }
      #expect(host.layoutRequests.subscriptionCount == 0)
      host.reset()
      await #expect(throws: HostServiceError.self) { try await task.value }
    }
  }

  @Test func malformedRequestsAndCancelledOperationsCannotMutateTheWindow() async throws {
    let window = hostTestWindow("Original")
    defer { window.close() }
    let host = NativeWindowHost()
    let owner = NSView()
    host.attach(window: window, title: "Application", owner: owner)
    let service = NativeHostService(windowHost: host)
    for invalid in [0.0, -1.0, Double.nan, Double.infinity, -Double.infinity] {
      await #expect(throws: (any Error).self) {
        try await service.execute(.setWindowSize(width: invalid, height: 560))
      }
      await #expect(throws: (any Error).self) {
        try await service.execute(.setWindowSize(width: 760, height: invalid))
      }
    }
    await #expect(throws: (any Error).self) {
      try await service.execute(
        .setWindowTitle(String(repeating: "x", count: ProtocolLimits.maxStringBytes + 1)))
    }
    let dispatcher = HostEffectDispatcher(service: service)
    var replies: [HostResponse] = []
    dispatcher.dispatch([
      .request(1, .setWindowTitle("Cancelled")), .cancel(1),
      .request(2, .setWindowSize(width: 760, height: 560)), .cancel(2),
    ]) { replies.append($0) }
    for _ in 0..<20 { await Task.yield() }
    #expect(replies.map(\.status) == [.cancelled, .cancelled])
    #expect(window.title == "Application")
    #expect(window.contentRect(forFrameRect: window.frame).size == CGSize(width: 480, height: 360))
    host.detach(owner: owner)
    #expect(window.title == "Original")
    await #expect(throws: (any Error).self) {
      try await service.execute(.setWindowSize(width: 760, height: 560))
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualWindowRequestsWaitForPresentationAndResume() async throws {
    let window = hostTestWindow("Original")
    defer { window.close() }
    let host = NativeWindowHost()
    let owner = NSView()
    host.attach(window: window, title: "Host Effects", owner: owner)
    let session = BonsaiSession(windowHost: host)
    session.isVisible = true
    func button(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first { node in
          node.kind == NodeKindId.button
            && node.children.contains {
              if case .text(let text) = $0.properties { return text.value == title }
              return false
            }
        })
    }
    func status(_ text: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let value) = $0.properties { return value.value == text }
        return false
      }
    }
    do {
      try await session.start(entrypoint: "host_effects")
      #expect(try await session.presented(#require(session.ticket)))
      #expect(session.activate(try button("Rename window")))
      #expect(try await session.refresh())
      #expect(window.title == "Host Effects")
      session.isActive = false
      #expect(!(try await session.presented(#require(session.ticket))))
      for _ in 0..<20 { await Task.yield() }
      #expect(window.title == "Host Effects")
      session.isActive = true
      for _ in 0..<100 {
        if let ticket = session.ticket { _ = try await session.presented(ticket) }
        _ = try await session.refresh()
        if status("Window title updated") { break }
        try await Task.sleep(for: .milliseconds(5))
      }
      #expect(status("Window title updated"))
      #expect(window.title == "Bonsai SwiftUI 本地😀")
      if let ticket = session.ticket { _ = try await session.presented(ticket) }
      #expect(session.activate(try button("Resize window")))
      #expect(try await session.refresh())
      await session.close()
      for _ in 0..<20 { await Task.yield() }
      #expect(window.title == "Original")
      #expect(
        window.contentRect(forFrameRect: window.frame).size == CGSize(width: 480, height: 360))
    } catch {
      await session.close()
      throw error
    }
  }
}
