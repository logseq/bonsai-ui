import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor private func swipeCommand(_ title: String, in host: NSView, owner: String? = nil) throws
{
  let elements = accessibilityElements(host).filter { element in
    owner.map { name in element.actions.contains { $0.name == name } } ?? true
  }
  let action = try #require(elements.flatMap(\.actions).first { $0.name == title })
  #expect(action.handler?() == true)
}

@MainActor struct SwipeActionsTests {
  @Test func malformedActionGraphsAndUpdatesCannotPublish() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.swipeTree())).tree
    for update in [
      TreeFixture.swipe(enabled: 2, update: true),
      TreeFixture.swipe(group: "", update: true),
      TreeFixture.swipeAction(title: "", update: true),
      TreeFixture.swipeAction(side: 2, update: true),
      TreeFixture.swipeAction(extent: 0, update: true),
      TreeFixture.swipeAction(extent: .nan, update: true),
      TreeFixture.swipeAction(extent: .infinity, update: true),
      TreeFixture.children(1, [3, 2, 5]), TreeFixture.children(3, []),
      TreeFixture.root(3),
    ] {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([update], base: 1, revision: 2))
      }
    }
    let update = TreeFixture.swipeAction(title: "Updated", update: true)
    for length in 0..<update.body.count {
      #expect(throws: (any Error).self) {
        try store.staging(
          TreeFixture.frame(
            [
              WireOperation(opcode: update.opcode, body: update.body.prefix(length))
            ], base: 1, revision: 2))
      }
    }
    #expect(store.revision == 1)
    #expect(store.accessibilityHiddenNodes.isSuperset(of: [4, 6]))
    #expect(throws: (any Error).self) {
      try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.swipeAction(5, title: "Conflicting", full: 1, update: true)
          ], base: 1, revision: 2))
    }
  }

  @Test(arguments: [true, false]) func nativeActionsRetainContentAndRespectAdmission(admit: Bool)
    async throws
  {
    initializeAccessibilityApplication()
    var store = try NodeStore().staging(TreeFixture.frame(TreeFixture.swipeTree())).tree
    let tree = RenderTree()
    tree.commit(store)
    let original = tree.nodes
    var events: [UInt64] = []
    tree.onInput = { node, payload in
      #expect(payload == .press)
      events.append(node.id.node)
      return admit
    }
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }).environment(
        \.scenePhase, .active))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    #expect(
      !accessibilityElements(host).contains { $0.role == "AXButton" && $0.label == "Archive" })
    try swipeCommand("Show leading actions", in: host)
    try await settleAccessibility(host)
    let button = try #require(
      accessibilityElements(host).first { $0.role == "AXButton" && $0.label == "Archive" })
    #expect(button.enabled)
    #expect(button.press())
    try await settleAccessibility(host)
    #expect(events == [3])
    #expect(
      accessibilityElements(host).contains { $0.role == "AXButton" && $0.label == "Archive" }
        == !admit)
    store = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.text(2, "Updated preview", update: true)
        ], base: 1, revision: 2)
    ).tree
    tree.commit(store)
    try await settleAccessibility(host)
    #expect(original.allSatisfy { tree.nodes[$0.key] === $0.value })
  }

  @Test func openingAnotherGroupedRowClosesTheFirstAndDisablingCancelsInput() async throws {
    initializeAccessibilityApplication()
    let operations =
      Array(TreeFixture.swipeTree().dropLast()) + [
        TreeFixture.swipe(10), TreeFixture.text(11, "Second preview"),
        TreeFixture.swipeAction(12, title: "Second archive"), TreeFixture.text(13, "Second label"),
        TreeFixture.children(12, [13]), TreeFixture.children(10, [11, 12]),
        TreeFixture.create(20, kind: NodeKindId.column), TreeFixture.children(20, [1, 10]),
        TreeFixture.root(20),
      ]
    var store = try NodeStore().staging(TreeFixture.frame(operations)).tree
    let tree = RenderTree()
    tree.commit(store)
    var events = 0
    tree.onInput = { _, _ in
      events += 1
      return true
    }
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }).environment(
        \.scenePhase, .active))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    try swipeCommand("Show leading actions", in: host, owner: "Archive")
    try await settleAccessibility(host)
    let oldButton = try #require(
      accessibilityElements(host).first { $0.role == "AXButton" && $0.label == "Archive" })
    try swipeCommand("Show leading actions", in: host, owner: "Second archive")
    try await settleAccessibility(host)
    #expect(
      !accessibilityElements(host).contains { $0.role == "AXButton" && $0.label == "Archive" })
    #expect(
      accessibilityElements(host).contains { $0.role == "AXButton" && $0.label == "Second archive" }
    )
    _ = oldButton.press()
    #expect(events == 0)
    store = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.swipe(10, enabled: 0, update: true)
        ], base: 1, revision: 2)
    ).tree
    tree.commit(store)
    try await settleAccessibility(host)
    #expect(
      !accessibilityElements(host).contains {
        $0.role == "AXButton" && $0.label == "Second archive"
      })
    #expect(events == 0)
  }

}

extension NativeRuntimeTests {
  @Test @MainActor func actualMailCanStageItsCompleteTree() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "mail-collection")
      #expect(try await session.presented(#require(session.ticket)))
      #expect(session.tree.nodes.values.contains { $0.kind == 42 })
      #expect(!session.tree.nodes.values.contains { $0.kind == NodeKindId.nativeWidget })
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGallerySwipeActionsResolveUnchangedResponsesAndKeepContentIdentity()
    async throws
  {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-swipe")
      #expect(try await session.presented(#require(session.ticket)))
      let root = try #require(session.tree.root)
      let host = NSHostingView(
        rootView: NativeNodeView(node: root, activate: { session.activate($0) }).environment(
          \.scenePhase, .active))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      let owners = session.tree.nodes.values.compactMap(\.swipeController)
      #expect(owners.count == 2)
      let original = session.tree.nodes
      func text(_ value: String) -> Bool {
        session.tree.nodes.values.contains {
          if case .text(let p) = $0.properties { return p.value == value }
          return false
        }
      }
      func press(_ label: String) throws {
        let button = try #require(
          accessibilityElements(host).first { $0.role == "AXButton" && $0.label == label })
        #expect(button.press())
      }
      func refresh() async throws {
        if try await session.refresh() {
          #expect(try await session.presented(#require(session.ticket)))
        }
        try await settleAccessibility(host)
      }
      try swipeCommand("Archive horizontal", in: host)
      #expect(owners.filter { $0.pending != nil }.count == 1)
      try swipeCommand("Archive horizontal", in: host)
      await Task.yield()
      try await refresh()
      #expect(text("Archived: 1"))
      #expect(owners.allSatisfy { $0.pending == nil })
      try press("Ignore actions")
      try await refresh()
      for _ in 0..<2 {
        try swipeCommand("Archive vertical", in: host)
        #expect(owners.filter { $0.pending != nil }.count == 1)
        #expect(!(try await session.refresh()))
        #expect(owners.allSatisfy { $0.pending == nil })
        #expect(text("Archived: 1"))
      }
      try press("Accept actions")
      try await refresh()
      try swipeCommand("Archive vertical", in: host)
      try await refresh()
      #expect(text("Archived: 2"))
      #expect(original.allSatisfy { session.tree.nodes[$0.key] === $0.value })
      try press("Disable actions")
      try await refresh()
      #expect(
        !accessibilityElements(host).flatMap(\.actions).contains { $0.name == "Archive horizontal" }
      )
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

@MainActor extension SwipeActionsTests {
  @Test(arguments: [false, true], [200.0, 400.0])
  func nativeActionWidthsRespectConfiguredExtents(vertical: Bool, length: Double) async throws {
    initializeAccessibilityApplication()
    let operations =
      Array(TreeFixture.swipeTree(vertical: vertical ? 1 : 0).dropLast()) + [
        TreeFixture.swipeAction(7, title: "Trash", extent: 160, full: 0),
        TreeFixture.text(8, "Trash"), TreeFixture.children(7, [8]),
        TreeFixture.layoutFrame(9, width: vertical ? 100 : length, height: vertical ? length : 100),
        TreeFixture.children(9, [2]), TreeFixture.children(1, [9, 3, 7, 5]), TreeFixture.root(1),
      ]
    let tree = RenderTree()
    tree.commit(try NodeStore().staging(TreeFixture.frame(operations)).tree)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }).environment(
        \.scenePhase, .active))
    let window = NSWindow(
      contentRect: NSRect(
        x: 0, y: 0, width: vertical ? 100 : length, height: vertical ? length : 100),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    try swipeCommand(vertical ? "Show top actions" : "Show leading actions", in: host)
    try await settleAccessibility(host)
    func width(_ title: String) throws -> CGFloat {
      let element = try #require(
        accessibilityElements(host).first { $0.role == "AXButton" && $0.label == title })
      let selector = NSSelectorFromString("accessibilityFrame")
      #expect(element.object.responds(to: selector))
      typealias Frame = @convention(c) (AnyObject, Selector) -> CGRect
      let get = unsafeBitCast(element.object.method(for: selector), to: Frame.self)
      let frame = get(element.object, selector)
      return vertical ? frame.height : frame.width
    }
    let paneExtent = min(length * 0.8, 240)
    #expect(abs(try width("Archive") - paneExtent / 3) < 1)
    #expect(abs(try width("Trash") - paneExtent * 2 / 3) < 1)
  }
}

@MainActor extension SwipeActionsTests {
  @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
  func nativeLeadingPaneStaysInsideItsRow(direction: LayoutDirection) async throws {
    initializeAccessibilityApplication()
    let operations =
      Array(TreeFixture.swipeTree().dropLast()) + [
        TreeFixture.layoutFrame(7, width: 400, height: 100), TreeFixture.children(7, [2]),
        TreeFixture.children(1, [7, 3, 5]), TreeFixture.root(1),
      ]
    let tree = RenderTree()
    tree.commit(try NodeStore().staging(TreeFixture.frame(operations)).tree)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in })
        .environment(\.scenePhase, .active).environment(\.layoutDirection, direction))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    try swipeCommand("Show leading actions", in: host)
    try await settleAccessibility(host)
    let element = try #require(
      accessibilityElements(host).first { $0.role == "AXButton" && $0.label == "Archive" })
    let selector = NSSelectorFromString("accessibilityFrame")
    typealias Frame = @convention(c) (AnyObject, Selector) -> CGRect
    let get = unsafeBitCast(element.object.method(for: selector), to: Frame.self)
    let actual = get(element.object, selector)
    let bounds = window.convertToScreen(host.convert(host.bounds, to: nil))
    let expected = direction == .leftToRight ? bounds.minX : bounds.maxX - 80
    #expect(abs(actual.minX - expected) < 1)
    #expect(abs(actual.width - 80) < 1)
  }
}
