import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func tabs(_ selection: String = "mail", update: Bool = false) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(31))
      if update { $0.integer(UInt64(1)) }
      try! $0.string(selection)
      if !update {
        $0.integer(UInt16(1))
        $0.integer(UInt16(52))
        $0.integer(UInt64(92))
      }
    }
  }
  static func tab(
    _ id: UInt64, key: String, title: String, badge: String? = nil,
    accessibilityLabel: String? = nil, update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(40))
      if update { $0.integer(UInt64(31)) }
      try! $0.string(key)
      try! $0.string(title)
      try! $0.string("tray")
      for value in [badge, accessibilityLabel] {
        $0.integer(UInt8(value == nil ? 0 : 1))
        if let value { try! $0.string(value) }
      }
      if !update { $0.integer(UInt16(0)) }
    }
  }
  static func tabsTree(selection: String = "mail", second: String = "chat") -> [WireOperation] {
    [
      tabs(selection), tab(2, key: "mail", title: "Mail"), tab(3, key: second, title: "Chat"),
      text(4, "Inbox content"), text(5, "Chat content"), children(2, [4]), children(3, [5]),
      children(1, [2, 3]), root(1),
    ]
  }
}

@MainActor struct TabsTests {
  @Test(arguments: [true, false]) func tabSelectionRetainsTheOtherPage(admitted: Bool) async throws
  {
    initializeAccessibilityApplication()
    var store = try NodeStore().staging(TreeFixture.frame(TreeFixture.tabsTree())).tree
    let tree = RenderTree()
    tree.commit(store)
    let original = tree.nodes
    var events = [NativeEventPayload]()
    tree.onInput = { _, payload in
      events.append(payload)
      return admitted
    }
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    host.sizingOptions = []
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    #expect(accessibilityElements(host).contains { $0.value == "Inbox content" })
    let root = try #require(tree.root)
    let controller = try #require(root.tabsController)
    #expect(controller.request(RenderTabKey("chat"), emit: root.emit) == admitted)
    try await settleAccessibility(host)
    #expect(events.count == 1 && events.first?.tag == 52)
    #expect(
      accessibilityElements(host).contains {
        $0.value == (admitted ? "Chat content" : "Inbox content")
      })
    // Reordering keeps the selected semantic key and the mounted page objects.
    store = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.tabs("chat", update: true), TreeFixture.children(1, [3, 2]),
        ], base: 1, revision: 2)
    ).tree
    tree.commit(store)
    try await settleAccessibility(host)
    #expect(original.allSatisfy { tree.nodes[$0.key] === $0.value })
    #expect(accessibilityElements(host).contains { $0.value == "Chat content" })
    #expect(events.count == 1)
  }

  @Test func invalidTabGraphsCannotReplaceTheDisplayedTree() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.tabsTree())).tree
    for operation in [
      TreeFixture.tabs("missing", update: true), TreeFixture.tabs("", update: true),
      TreeFixture.children(1, []), TreeFixture.children(1, [4]), TreeFixture.children(2, []),
      TreeFixture.root(2),
    ] {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
    }
    #expect(throws: (any Error).self) {
      try NodeStore().staging(TreeFixture.frame(TreeFixture.tabsTree(second: "mail")))
    }
    let update = TreeFixture.tabs("chat", update: true)
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
  }

  @Test func semanticTabKeysUseExactUTF8Identity() throws {
    let operations: [WireOperation] = [
      TreeFixture.tabs("é"), TreeFixture.tab(2, key: "é", title: "First"),
      TreeFixture.tab(3, key: "e\u{301}", title: "Second"),
      TreeFixture.text(4, "First content"), TreeFixture.text(5, "Second content"),
      TreeFixture.children(2, [4]),
      TreeFixture.children(3, [5]), TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
    ]
    let store = try NodeStore().staging(TreeFixture.frame(operations)).tree
    #expect(store.nodes.count == 5)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryTabsKeepStateAndRejectHiddenOrUnpresentedInput() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-tabs")
      let root = try #require(session.tree.root)
      let controller = try #require(root.tabsController)
      #expect(!controller.request(RenderTabKey("chat"), emit: root.emit))
      #expect(try await session.presented(#require(session.ticket)))
      func button(_ label: String) throws -> RenderNodeState {
        let matches = session.tree.nodes.values.filter { node in
          guard case .button = node.properties, let child = node.children.first,
            case .text(let text) = child.properties
          else { return false }
          return text.value == label
        }
        if matches.count == 1 { return matches[0] }
        var pending = root.children.filter {
          if case .tab(let tab) = $0.properties { return tab.key == controller.selection }
          return false
        }
        while let node = pending.popLast() {
          if matches.contains(where: { $0 === node }) { return node }
          pending.append(contentsOf: node.children)
        }
        throw NSError(domain: "TabsTests", code: 1)
      }
      func press(_ label: String) async throws {
        #expect(session.activate(try button(label)))
        #expect(try await session.refresh())
        #expect(try await session.presented(#require(session.ticket)))
      }
      let mailButton = try button("Increment mail")
      let chatButton = try button("Increment chat")
      #expect(!session.activate(chatButton))
      try await press("Increment mail")
      #expect(controller.request(RenderTabKey("chat"), emit: root.emit))
      #expect(!session.activate(mailButton))
      #expect(!session.activate(chatButton))
      #expect(try await session.refresh())
      #expect(!session.activate(chatButton))
      #expect(try await session.presented(#require(session.ticket)))
      try await press("Increment chat")
      try await press("Lock tabs")
      #expect(controller.request(RenderTabKey("mail"), emit: root.emit))
      #expect(!(try await session.refresh()))
      #expect(controller.selection == RenderTabKey("chat"))
      try await press("Unlock tabs")
      #expect(controller.request(RenderTabKey("mail"), emit: root.emit))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      let original = session.tree.nodes
      let oldOrder = root.children.map(\.id)
      try await press("Reorder tabs")
      #expect(root.children.map(\.id) == oldOrder.reversed())
      #expect(original.allSatisfy { session.tree.nodes[$0.key] === $0.value })
      #expect(controller.selection == RenderTabKey("mail"))
      #expect(
        session.tree.nodes.values.contains { node in
          if case .text(let text) = node.properties { return text.value == "Mail count: 1" }
          return false
        })
      #expect(
        session.tree.nodes.values.contains { node in
          if case .text(let text) = node.properties { return text.value == "Chat count: 1" }
          return false
        })
      #expect(!controller.request(RenderTabKey("unknown"), emit: root.emit))
      await session.close()
      #expect(!controller.request(RenderTabKey("chat"), emit: root.emit))
    } catch {
      await session.close()
      throw error
    }
  }
}

@MainActor struct TabsRequestTests {
  @Test func anOlderResponseCannotClearANewerSelectionOfTheSamePage() throws {
    let tree = RenderTree()
    tree.commit(try NodeStore().staging(TreeFixture.frame(TreeFixture.tabsTree())).tree)
    let root = try #require(tree.root)
    let controller = try #require(root.tabsController)
    var queue = NativeEventQueue()
    var sequence: UInt64 = 0
    tree.onInput = { _, payload in
      sequence += 1
      return queue.append(
        NativeEvent(
          sequence: sequence, displayedRevision: 1,
          nodeID: root.id.node, handlerID: 92, payload: payload))
    }
    #expect(controller.request(RenderTabKey("chat"), emit: root.emit))
    let old = try #require(controller.pending)
    #expect(controller.request(RenderTabKey("mail"), emit: root.emit))
    #expect(controller.request(RenderTabKey("chat"), emit: root.emit))
    let latest = try #require(controller.pending)
    #expect(queue.events.count == 1)
    #expect(queue.events.first?.payload == .tabSelection(RenderTabKey("chat")))
    controller.resolve(old)
    #expect(controller.pending == latest && controller.selection == RenderTabKey("chat"))
    controller.resolve(latest)
    #expect(controller.selection == RenderTabKey("mail"))
  }

  @Test func aRemovedPageInvalidatesPendingSelectionAndCapturedBindings() throws {
    let tree = RenderTree()
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.tabsTree())).tree
    tree.commit(store)
    let root = try #require(tree.root)
    let controller = try #require(root.tabsController)
    var events = [NativeEventPayload]()
    tree.onInput = { _, payload in
      events.append(payload)
      return true
    }
    let binding = controller.binding(emit: root.emit)
    #expect(binding.wrappedValue == RenderTabKey("mail"))
    binding.wrappedValue = RenderTabKey("chat")
    let next = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.children(1, [2]),
          TreeFixture.operation(OperationId.dropNode) { $0.integer(UInt64(3)) },
          TreeFixture.operation(OperationId.dropNode) { $0.integer(UInt64(5)) },
        ], base: 1, revision: 2)
    ).tree
    tree.commit(next)
    #expect(controller.pending == nil && controller.selection == RenderTabKey("mail"))
    binding.wrappedValue = RenderTabKey("chat")
    #expect(events.count == 1)
    #expect(binding.wrappedValue == RenderTabKey("mail"))
    binding.wrappedValue = RenderTabKey("chat")
    #expect(events.count == 1)
    tree.commit(NodeStore())
    #expect(!controller.request(RenderTabKey("chat"), emit: root.emit))
  }
}

extension TabsRequestTests {
  @Test func acceptingATabEchoDoesNotInvalidateTheRetainedSystemBinding() throws {
    let tree = RenderTree()
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.tabsTree())).tree
    tree.commit(store)
    let root = try #require(tree.root)
    let controller = try #require(root.tabsController)
    var events = [NativeEventPayload]()
    tree.onInput = { _, payload in
      events.append(payload)
      return true
    }
    let binding = controller.binding(emit: root.emit)
    _ = binding.wrappedValue
    binding.wrappedValue = RenderTabKey("chat")
    _ = binding.wrappedValue
    let request = try #require(controller.pending)
    let accepted = try store.staging(
      TreeFixture.frame(
        [TreeFixture.tabs("chat", update: true)], base: 1, revision: 2)
    ).tree
    tree.commit(accepted)
    controller.resolve(request)
    binding.wrappedValue = RenderTabKey("mail")
    #expect(events.count == 2)
    #expect(controller.selection == RenderTabKey("mail"))
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func tabEchoAwaitingPresentationRetainsTheFinalIntentAndFencesPageInput()
    async throws
  {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-tabs")
      let root = try #require(session.tree.root)
      let controller = try #require(root.tabsController)
      let buttons = session.tree.nodes.values.filter {
        if case .button = $0.properties { return true }
        return false
      }
      #expect(try await session.presented(#require(session.ticket)))
      #expect(controller.request(RenderTabKey("chat"), emit: root.emit))
      #expect(try await session.refresh())
      let chatTicket = try #require(session.ticket)
      #expect(controller.request(RenderTabKey("mail"), emit: root.emit))
      #expect(buttons.allSatisfy { !session.activate($0) })
      #expect(try await session.presented(chatTicket))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(controller.selection == RenderTabKey("mail"))
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension TabsTests {
  @Test func badgeAndAccessibilityUpdatesRetainTheTabPages() throws {
    let original = try NodeStore().staging(TreeFixture.frame(TreeFixture.tabsTree())).tree
    let tree = RenderTree()
    tree.commit(original)
    let retained = tree.nodes
    var store = original
    for (index, badge) in ["0", "4611686018427387903", "•", nil].enumerated() {
      store = try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.tab(
              2, key: "mail", title: "Mail", badge: badge,
              accessibilityLabel: badge == nil ? nil : "Inbox messages", update: true)
          ], base: UInt64(index + 1), revision: UInt64(index + 2))
      ).tree
      tree.commit(store)
      if case .tab(let tab) = try #require(tree.nodes[2]).properties {
        #expect(tab.badge == badge)
        #expect(tab.accessibilityLabel == (badge == nil ? nil : "Inbox messages"))
      } else {
        Issue.record("Missing native tab properties")
      }
      #expect(retained.allSatisfy { tree.nodes[$0.key] === $0.value })
    }
    let valid = TreeFixture.tab(2, key: "mail", title: "Mail", badge: "0", update: true)
    var invalid = [
      TreeFixture.tab(2, key: "mail", title: "Mail", badge: "", update: true),
      TreeFixture.tab(2, key: "mail", title: "Mail", accessibilityLabel: " ", update: true),
    ]
    for length in 0..<valid.body.count {
      invalid.append(WireOperation(opcode: valid.opcode, body: valid.body.prefix(length)))
    }
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try original.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
    }
    #expect(original.revision == 1)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualTabMetadataChangesFenceUnpresentedSelection() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-tabs")
      let root = try #require(session.tree.root)
      let original = session.tree.nodes
      #expect(try await session.presented(#require(session.ticket)))
      let change = try #require(
        session.tree.nodes.values.first { node in
          guard case .button = node.properties, let child = node.children.first,
            case .text(let text) = child.properties
          else { return false }
          return text.value == "Update tab metadata"
        })
      #expect(session.activate(change))
      #expect(try await session.refresh())
      #expect(!root.emit(.tabSelection(RenderTabKey("chat"))))
      #expect(try await session.presented(#require(session.ticket)))
      #expect(root.emit(.tabSelection(RenderTabKey("chat"))))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(original.allSatisfy { session.tree.nodes[$0.key] === $0.value })
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
