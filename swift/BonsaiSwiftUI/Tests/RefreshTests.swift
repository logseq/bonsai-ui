import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func refresh(
    token: Int64 = 1, state: UInt8 = 0, show: Int64? = nil,
    update: Bool = false, handler: UInt64 = 100
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(77))
      if update { $0.integer(UInt64(7)) }
      $0.integer(token)
      $0.integer(state)
      $0.integer(UInt8(show == nil ? 0 : 1))
      if let show { $0.integer(show) }
      if !update {
        $0.integer(UInt16(1))
        $0.integer(UInt16(56))
        $0.integer(handler)
      }
    }
  }
}

struct RefreshNodeTests {
  @Test func refreshOwnsOneVerticalViewportAndValidatesRequestsAtomically() throws {
    let store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.refresh(), TreeFixture.systemList(2), TreeFixture.children(1, [2]),
        TreeFixture.root(1),
      ])
    ).tree
    for bad in [
      TreeFixture.refresh(state: 3, update: true),
      TreeFixture.children(1, []), TreeFixture.children(1, [3]),
      TreeFixture.scroll(2, vertical: 0, update: true),
    ] {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([bad], base: 1, revision: 2))
      }
    }
    let update = TreeFixture.refresh(show: Int64.max, update: true)
    for count in 0..<update.body.count {
      #expect(throws: (any Error).self) {
        try store.staging(
          TreeFixture.frame(
            [
              WireOperation(opcode: update.opcode, body: update.body.prefix(count))
            ], base: 1, revision: 2))
      }
    }
    _ = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.refresh(token: Int64.min, state: 2, show: Int64.max, update: true)
        ], base: 1, revision: 2))
    #expect(store.revision == 1)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor
  func actualRefreshWaitsForOcamlAndPreservesItsViewport() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-refresh-0")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { _ = session.activate($0) }))
      host.sizingOptions = []
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 700, height: 650),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      func settle() async throws {
        for _ in 0..<3 {
          _ = try await session.refresh()
          if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
          try await settleAccessibility(host)
        }
      }
      func press(_ label: String) throws {
        let button = try #require(
          accessibilityElements(host).first {
            $0.role == "AXButton" && $0.label == label
          })
        _ = button.press()
      }
      func contains(_ text: String) -> Bool {
        session.tree.nodes.values.contains {
          if case .text(let value) = $0.properties { return value.value == text }
          return false
        }
      }
      func scroll() throws -> NSScrollView {
        var pending: [NSView] = [host]
        while let view = pending.popLast() {
          if let scroll = view as? NSScrollView { return scroll }
          pending += view.subviews
        }
        throw NSError(domain: "RefreshTests", code: 1)
      }
      try await settle()
      let native = try scroll()
      try press("Programmatic refresh")
      try press("Programmatic refresh")
      try await settle()
      #expect(contains("Requests: 1"))
      #expect(contains("State: pending"))
      try press("Programmatic refresh")
      try await settle()
      #expect(contains("Requests: 1"))

      try press("Complete request")
      try await settle()
      #expect(contains("State: completed"))
      try press("Programmatic refresh")
      try await settle()
      #expect(contains("Requests: 1"))
      try press("Next request")
      try press("Programmatic refresh")
      try await settle()
      #expect(contains("Requests: 2"))
      #expect(contains("State: pending"))
      try press("Programmatic refresh")
      try await settle()
      #expect(contains("Requests: 2"))
      try press("Next request")
      try await settle()
      try press("Programmatic refresh")
      try await settle()
      #expect(contains("Requests: 3"))
      #expect(try scroll() === native)
      session.isVisible = false
      try press("Programmatic refresh")
      try await settle()
      #expect(contains("Requests: 3"))
      session.isVisible = true
      try await settle()
      #expect(contains("Requests: 3"))
      try press("Complete request")
      try press("Next request")
      try await settle()
      try press("Programmatic refresh")
      try await settle()
      #expect(contains("Requests: 4"))
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

@MainActor struct RefreshLifecycleTests {
  @Test func requestsWaitAcrossAcknowledgmentAndReleaseOnCompletionCancellationAndRemoval()
    async throws
  {
    var store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.refresh(), TreeFixture.systemList(2), TreeFixture.children(1, [2]),
        TreeFixture.root(1),
      ])
    ).tree
    let tree = RenderTree()
    var events: [NativeEventPayload] = []
    tree.onInput = { _, event in
      events.append(event)
      return true
    }
    tree.commit(store)
    let controller = try #require(tree.root?.refreshController)
    controller.setPresentation(presented: true, active: true)
    let first = Task { await controller.perform() }
    let duplicate = Task { await controller.perform() }
    for _ in 0..<10 { await Task.yield() }
    #expect(events == [.refreshRequest(1)] && controller.busy)
    func update(token: Int64, state: UInt8) throws {
      store = try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.refresh(token: token, state: state, update: true)
          ], base: store.revision, revision: store.revision + 1)
      ).tree
      tree.commit(store)
      controller.setPresentation(presented: true, active: true)
    }
    try update(token: 1, state: 1)
    #expect(controller.pending == 1)
    try update(token: 1, state: 2)
    await first.value
    await duplicate.value
    #expect(!controller.busy)
    let oldGeneration = controller.generation
    try update(token: 2, state: 0)
    await controller.perform(generation: oldGeneration)
    #expect(events.count == 1)
    let canceled = Task { await controller.perform() }
    for _ in 0..<10 { await Task.yield() }
    canceled.cancel()
    await canceled.value
    for _ in 0..<10 { await Task.yield() }
    #expect(!controller.busy && events.count == 2)
    try update(token: 3, state: 0)
    let hidden = Task { await controller.perform() }
    for _ in 0..<10 { await Task.yield() }
    controller.setPresentation(presented: false, active: false)
    await hidden.value
    #expect(!controller.busy && !controller.canRequest)
    try update(token: 4, state: 0)
    let removed = Task { await controller.perform() }
    for _ in 0..<10 { await Task.yield() }
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame(
          [
            TreeFixture.text(1, "Replacement"), TreeFixture.root(1),
          ], epoch: 2)
      ).tree)
    await removed.value
    await controller.perform()
    #expect(
      events == [.refreshRequest(1), .refreshRequest(2), .refreshRequest(3), .refreshRequest(4)])
  }

}
