import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func removal(
    token: Int64 = 1, state: UInt8 = 0, vertical: UInt8 = 0,
    collapseVertical: UInt8 = 1, title: String = "Delete", milliseconds: UInt32 = 180,
    update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(78))
      if update { $0.integer(UInt64(63)) }
      $0.integer(token)
      $0.integer(state)
      $0.integer(vertical)
      $0.integer(collapseVertical)
      try! $0.string(title)
      $0.integer(milliseconds)
      if !update {
        $0.integer(UInt16(2))
        $0.integer(UInt16(57))
        $0.integer(UInt64(100))
        $0.integer(UInt16(58))
        $0.integer(UInt64(101))
      }
    }
  }
}
struct RemovalNodeTests {
  @Test func removalValidatesBeforePublishing() throws {
    let store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.removal(), TreeFixture.text(2, "Item"), TreeFixture.children(1, [2]),
        TreeFixture.root(1),
      ])
    ).tree
    for bad in [
      TreeFixture.removal(state: 4, update: true),
      TreeFixture.removal(vertical: 2, update: true),
      TreeFixture.removal(collapseVertical: 2, update: true),
      TreeFixture.removal(title: "", update: true), TreeFixture.children(1, []),
    ] {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([bad], base: 1, revision: 2))
      }
    }
    let update = TreeFixture.removal(token: Int64.min, state: 3, update: true)
    for count in 0..<update.body.count {
      #expect(throws: (any Error).self) {
        try store.staging(
          TreeFixture.frame(
            [
              WireOperation(opcode: update.opcode, body: update.body.prefix(count))
            ], base: 1, revision: 2))
      }
    }
    _ = try store.staging(TreeFixture.frame([update], base: 1, revision: 2))
    #expect(store.revision == 1)
  }
}

extension NativeRuntimeTests {
  @Test(arguments: [false, true], [false, true]) @MainActor
  func actualRemovalPreservesRejectedItemsAndRemovesOnlyAfterAcceptance(vertical: Bool, rtl: Bool)
    async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: vertical ? "native-removal-v" : "native-removal-h")
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { _ = session.activate($0) }
        )
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight))
      host.sizingOptions = []
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 700, height: 600),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      func settle() async throws {
        for _ in 0..<4 {
          _ = try await session.refresh()
          if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
          try await settleAccessibility(host)
        }
      }
      func press(_ label: String) throws {
        let control = try #require(
          accessibilityElements(host).first { $0.role == "AXButton" && $0.label == label })
        #expect(control.press())
      }
      func remove(_ name: String) throws {
        let action = try #require(
          accessibilityElements(host).flatMap(\.actions).first { $0.name == name })
        #expect(action.handler?() == true)
      }
      func contains(_ text: String) -> Bool {
        session.tree.nodes.values.contains {
          if case .text(let value) = $0.properties { return value.value == text }
          return false
        }
      }
      try await settle()
      let original = try #require(
        session.tree.nodes.values.first {
          if case .text(let value) = $0.properties { return value.value == "Item 1" }
          return false
        })
      try remove("Delete 1")
      try await settle()
      #expect(contains("Requests: 1"))
      #expect(contains("Pending: 1"))
      #expect(contains("Item 1"))
      #expect(!accessibilityElements(host).flatMap(\.actions).contains { $0.name == "Delete 1" })
      try press("Reject request")
      try await settle()
      #expect(session.tree.nodes[original.id.node] === original)
      try press("Next request")
      try await settle()
      try remove("Delete 1")
      try await settle()
      #expect(contains("Requests: 2"))
      try press("Replace pending request")
      try await settle()
      #expect(contains("Item 1"))
      #expect(contains("Removed: 0"))
      try remove("Delete 2")
      try await settle()
      #expect(contains("Requests: 3"))
      #expect(contains("Pending: 2"))
      try press("Accept request")
      try await settle()
      #expect(!contains("Item 2"))
      #expect(contains("Item 1"))
      #expect(contains("Removed: 1"))
      session.isVisible = false
      session.isVisible = true
      try await settle()
      #expect(contains("Removed: 1"))
      try remove("Delete 1")
      try await settle()
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension RemovalNodeTests {
  @Test(arguments: [false, true]) @MainActor
  func nativeCollapseCancellationAndReducedMotionRetainTheChild(collapseVertical: Bool) async throws
  {
    initializeAccessibilityApplication()
    var store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.removal(collapseVertical: collapseVertical ? 1 : 0, milliseconds: 800),
        TreeFixture.layoutFrame(2, width: 180, height: 90), TreeFixture.text(3, "Retained item"),
        TreeFixture.children(2, [3]), TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    let tree = RenderTree()
    var events: [NativeEventPayload] = []
    tree.onInput = { _, event in
      events.append(event)
      return true
    }
    tree.commit(store)
    let controller = try #require(tree.root?.removalController)
    let retained = try #require(tree.nodes[3])
    var measured = CGSize.zero
    func content() -> some View {
      NativeNodeView(node: tree.root!, activate: { _ in }).fixedSize()
        .onGeometryChange(for: CGSize.self) {
          $0.size
        } action: {
          measured = $0
        }
    }
    let host = NSHostingView(rootView: content())
    host.sizingOptions = []
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      controller.dispose()
      window.orderOut(nil)
      window.contentView = nil
    }
    controller.setPresentation(presented: true, active: true)
    try await settleAccessibility(host)
    #expect(abs(measured.width - 180) < 1 && abs(measured.height - 90) < 1)
    func update(token: Int64, state: UInt8) throws {
      store = try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.removal(
              token: token, state: state, collapseVertical: collapseVertical ? 1 : 0,
              milliseconds: 800, update: true)
          ], base: store.revision, revision: store.revision + 1)
      ).tree
      tree.commit(store)
      controller.setPresentation(presented: true, active: true)
    }
    try update(token: 1, state: 2)
    try await settleAccessibility(host)
    let extent = collapseVertical ? measured.height : measured.width
    #expect(extent > 0 && extent < (collapseVertical ? 90 : 180))
    #expect(events.isEmpty)
    try update(token: 2, state: 0)
    try await settleAccessibility(host)
    #expect(abs(measured.width - 180) < 1 && abs(measured.height - 90) < 1)
    #expect(events.isEmpty && tree.nodes[3] === retained)
    controller.configure(size: CGSize(width: 180, height: 90), rtl: false, reducedMotion: true)
    try await settleAccessibility(host)
    try update(token: 2, state: 2)
    try await settleAccessibility(host)
    #expect((collapseVertical ? measured.height : measured.width) < 1)
    #expect(events == [.removalCompleted(2)])
    controller.setPresentation(presented: true, active: true)
    #expect(events.count == 1)
    controller.configure(size: CGSize(width: 180, height: 90), rtl: false, reducedMotion: false)
    try update(token: 3, state: 0)
    try await settleAccessibility(host)
    try update(token: 3, state: 2)
    controller.setPresentation(presented: false, active: false)
    try await settleAccessibility(host)
    #expect(events == [.removalCompleted(2)])
    controller.setPresentation(presented: true, active: true)
    try await settleAccessibility(host)
    #expect(events == [.removalCompleted(2), .removalCompleted(3)])
    try update(token: 4, state: 0)
    try await settleAccessibility(host)
    try update(token: 4, state: 2)
    tree.commit(
      try NodeStore().staging(
        TreeFixture.frame(
          [
            TreeFixture.text(1, "Replacement"), TreeFixture.root(1),
          ], epoch: 2)
      ).tree)
    try await settleAccessibility(host)
    #expect(events == [.removalCompleted(2), .removalCompleted(3)])
    #expect(!controller.canRequest)
  }
}
