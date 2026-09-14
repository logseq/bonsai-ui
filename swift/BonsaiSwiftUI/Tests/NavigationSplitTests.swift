import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func navigationSplit(
    _ id: UInt64 = 1, visibility: UInt8 = 0, compact: UInt8 = 1,
    selection: String? = nil, hasContent: Bool = true, update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(15))
      if update { $0.integer(UInt64(63)) }
      $0.integer(visibility)
      $0.integer(compact)
      $0.integer(UInt8(selection == nil ? 0 : 1))
      if let selection { try! $0.string(selection) }
      try! $0.string("Folders")
      $0.integer(UInt8(hasContent ? 1 : 0))
      if hasContent { try! $0.string("Messages") }
      try! $0.string("Reading")
      if !update {
        $0.integer(UInt16(1))
        $0.integer(UInt16(51))
        $0.integer(UInt64(91))
      }
    }
  }
  static var splitTree: [WireOperation] {
    [
      navigationSplit(visibility: 1), text(2, "Folder list"), text(3, "Message list"),
      text(4, "Choose a message"), children(1, [2, 3, 4]), root(1),
    ]
  }
}

@MainActor struct NavigationSplitTests {
  @Test func splitColumnsRenderInANativeWideWindow() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(try NodeStore().staging(TreeFixture.frame(TreeFixture.splitTree)).tree)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    host.sizingOptions = []
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 500), styleMask: [.titled, .resizable],
      backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    let text = accessibilityElements(host).compactMap { $0.value ?? $0.label }
    for label in ["Folder list", "Message list", "Choose a message"] {
      #expect(text.contains(label))
    }
  }

  @Test func malformedSplitStateCannotReplaceTheDisplayedTree() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.splitTree)).tree
    let valid = TreeFixture.navigationSplit(selection: "message", update: true)
    let invalid = [
      TreeFixture.navigationSplit(visibility: 4, update: true),
      TreeFixture.navigationSplit(compact: 3, update: true),
      TreeFixture.navigationSplit(selection: "", update: true), TreeFixture.children(1, [2, 3]),
    ]
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
    }
    for size in 0..<valid.body.count {
      #expect(throws: (any Error).self) {
        try store.staging(
          TreeFixture.frame(
            [WireOperation(opcode: valid.opcode, body: valid.body.prefix(size))], base: 1,
            revision: 2))
      }
    }
    #expect(store.revision == 1)
  }
}

@MainActor struct NavigationSplitRequestTests {
  @Test func nativeColumnBindingsCoalesceWithoutLosingTheOtherField() throws {
    let initial = RenderSplitState(visibility: 1, compactColumn: 1, selectionKey: "message")
    let controller = NavigationSplitController(initial)
    var payloads = [NativeEventPayload]()
    let emit: (NativeEventPayload) -> Bool = {
      payloads.append($0)
      return true
    }
    let visibility = controller.visibilityBinding(emit: emit)
    let compact = controller.compactColumnBinding(emit: emit)
    visibility.wrappedValue = .doubleColumn
    compact.wrappedValue = .detail
    #expect(controller.state.visibility == 2)
    #expect(controller.state.compactColumn == 2)
    #expect(payloads.count == 2)
    var queue = NativeEventQueue()
    for (index, payload) in payloads.enumerated() {
      let admitted = queue.append(
        NativeEvent(
          sequence: UInt64(index + 1), displayedRevision: 1, nodeID: 1, handlerID: 1,
          payload: payload))
      #expect(admitted)
    }
    #expect(queue.events.count == 1)
    #expect(queue.events.first?.payload == .navigationSplit(controller.state))
    let first = RenderSplitState(visibility: 2, compactColumn: 1, selectionKey: "message")
    controller.synchronize(first)
    controller.resolve(first)
    #expect(controller.state.compactColumn == 2)
    controller.resolve(RenderSplitState(visibility: 2, compactColumn: 2, selectionKey: "message"))
    #expect(controller.state == first)
  }

  @Test func staleSplitBindingsAndRejectedAdmissionCannotChangeTheCurrentSelection() throws {
    let initial = RenderSplitState(visibility: 1, compactColumn: 1, selectionKey: "é")
    let controller = NavigationSplitController(initial)
    var events = [NativeEventPayload]()
    let binding = controller.visibilityBinding(emit: {
      events.append($0)
      return true
    })
    let changed = RenderSplitState(visibility: 1, compactColumn: 2, selectionKey: "e\u{301}")
    controller.synchronize(changed)
    binding.wrappedValue = .doubleColumn
    #expect(events.isEmpty && controller.state == changed)
    #expect(!controller.request(initial, emit: { _ in true }))
    let hidden = RenderSplitState(
      visibility: 2, compactColumn: 2, selectionKey: changed.selectionKey)
    #expect(!controller.request(hidden, emit: { _ in false }))
    #expect(controller.state == changed)
    controller.dispose()
    #expect(!controller.request(hidden, emit: { _ in true }))
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGallerySplitAcceptsChangesAndRestoresDeclinedRequests() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-split")
      let root = try #require(session.tree.root)
      let controller = try #require(root.splitController)
      let original = session.tree.nodes
      #expect(try await session.presented(#require(session.ticket)))
      func button(_ label: String) throws -> RenderNodeState {
        try #require(
          session.tree.nodes.values.first { node in
            guard case .button = node.properties, let child = node.children.first,
              case .text(let value) = child.properties
            else { return false }
            return value.value == label
          })
      }
      #expect(session.activate(try button("Select message")))
      #expect(try await session.refresh())
      let selected = controller.state
      #expect(selected.compactColumn == 2 && selected.selectionKey == "message-42")
      var hidden = selected
      hidden.visibility = 2
      #expect(!controller.request(hidden, emit: root.emit))
      #expect(try await session.presented(#require(session.ticket)))
      #expect(controller.request(hidden, emit: root.emit))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(controller.state == hidden)
      #expect(session.activate(try button("Keep columns unchanged")))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      var wanted = hidden
      wanted.visibility = 1
      #expect(controller.request(wanted, emit: root.emit))
      #expect(!(try await session.refresh()))
      #expect(controller.state == hidden)
      #expect(original.allSatisfy { session.tree.nodes[$0.key] === $0.value })
      await session.close()
      #expect(!root.emit(.navigationSplit(wanted)))
    } catch {
      await session.close()
      throw error
    }
  }
}

extension NavigationSplitRequestTests {
  @Test func aRetainedNativeBindingCanWriteAfterReadingTheNewSelection() {
    let controller = NavigationSplitController(
      RenderSplitState(visibility: 1, compactColumn: 1, selectionKey: nil))
    var events = [NativeEventPayload]()
    let binding = controller.visibilityBinding(emit: {
      events.append($0)
      return true
    })
    controller.synchronize(
      RenderSplitState(visibility: 1, compactColumn: 2, selectionKey: "new-message"))
    #expect(binding.wrappedValue == .all)
    binding.wrappedValue = .doubleColumn
    #expect(
      events == [
        .navigationSplit(
          RenderSplitState(visibility: 2, compactColumn: 2, selectionKey: "new-message"))
      ])
  }
}

extension NavigationSplitRequestTests {
  @Test func acceptingANativeEchoDoesNotInvalidateTheRetainedSystemBinding() {
    let controller = NavigationSplitController(
      RenderSplitState(visibility: 1, compactColumn: 1, selectionKey: "message"))
    var events = [NativeEventPayload]()
    let binding = controller.visibilityBinding(emit: {
      events.append($0)
      return true
    })
    _ = binding.wrappedValue
    binding.wrappedValue = .doubleColumn
    _ = binding.wrappedValue
    let submitted = controller.state
    controller.synchronize(submitted)
    controller.resolve(submitted)
    // The accepted response changes no native value, so SwiftUI need not read
    // its retained binding again before the next system-sidebar action.
    binding.wrappedValue = .all
    #expect(events.count == 2)
    #expect(controller.state.visibility == 1)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func columnEchoAwaitingPresentationDoesNotDropTheFinalNativeIntent() async throws
  {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-split")
      let root = try #require(session.tree.root)
      let controller = try #require(root.splitController)
      #expect(try await session.presented(#require(session.ticket)))
      let shown = controller.state
      var hidden = shown
      hidden.visibility = 2
      #expect(controller.request(hidden, emit: root.emit))
      #expect(try await session.refresh())
      let hiddenTicket = try #require(session.ticket)
      #expect(controller.request(shown, emit: root.emit))
      #expect(try await session.presented(hiddenTicket))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(controller.state == shown)
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension NavigationSplitTests {
  @Test func twoColumnsRenderWithoutAnEmptyMiddleColumn() async throws {
    initializeAccessibilityApplication()
    let operations: [WireOperation] = [
      TreeFixture.navigationSplit(visibility: 1, compact: 0, hasContent: false),
      TreeFixture.text(2, "Folder list"), TreeFixture.text(4, "Reading pane"),
      TreeFixture.children(1, [2, 4]), TreeFixture.root(1),
    ]
    let store = try NodeStore().staging(TreeFixture.frame(operations)).tree
    for invalid in [
      TreeFixture.navigationSplit(compact: 1, hasContent: false, update: true),
      TreeFixture.navigationSplit(compact: 0, hasContent: true, update: true),
      TreeFixture.children(1, [2]),
    ] {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([invalid], base: 1, revision: 2))
      }
    }
    #expect(store.revision == 1)
    let tree = RenderTree()
    tree.commit(store)
    let root = try #require(tree.root)
    let controller = try #require(root.splitController)
    var events = [NativeEventPayload]()
    let compact = controller.compactColumnBinding(emit: {
      events.append($0)
      return true
    })
    compact.wrappedValue = .content
    #expect(events.isEmpty && controller.state.compactColumn == 0)
    compact.wrappedValue = .detail
    #expect(events.count == 1 && controller.state.compactColumn == 2)
    let host = NSHostingView(rootView: NativeNodeView(node: root, activate: { _ in }))
    host.sizingOptions = []
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    let labels = accessibilityElements(host).compactMap { $0.value ?? $0.label }
    #expect(labels.contains("Folder list") && labels.contains("Reading pane"))
    func splits(_ view: NSView) -> [NSSplitView] {
      (view as? NSSplitView).map { [$0] } ?? view.subviews.flatMap(splits)
    }
    let split = try #require(splits(host).first)
    #expect(split.arrangedSubviews.count == 2)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualTwoColumnGalleryPreservesSelectionAndRejectsMissingContent()
    async throws
  {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-split-two-columns")
      let root = try #require(session.tree.root)
      let controller = try #require(root.splitController)
      #expect(root.children.count == 2 && controller.state.compactColumn == 0)
      let original = session.tree.nodes
      #expect(try await session.presented(#require(session.ticket)))
      var invalid = controller.state
      invalid.compactColumn = 1
      #expect(!root.emit(.navigationSplit(invalid)))
      #expect(!controller.request(invalid, emit: root.emit))
      func button(_ label: String) throws -> RenderNodeState {
        try #require(
          session.tree.nodes.values.first { node in
            guard case .button = node.properties, let child = node.children.first,
              case .text(let text) = child.properties
            else { return false }
            return text.value == label
          })
      }
      #expect(session.activate(try button("Select message")))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(controller.state.compactColumn == 2 && controller.state.selectionKey == "message-42")
      var hidden = controller.state
      hidden.visibility = 3
      #expect(controller.request(hidden, emit: root.emit))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(controller.state == hidden)
      #expect(session.activate(try button("Keep columns unchanged")))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      var shown = hidden
      shown.visibility = 1
      #expect(controller.request(shown, emit: root.emit))
      #expect(!(try await session.refresh()))
      #expect(controller.state == hidden)
      #expect(session.activate(try button("Clear selection")))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(controller.state.selectionKey == nil && controller.state.compactColumn == 0)
      #expect(original.allSatisfy { session.tree.nodes[$0.key] === $0.value })
      session.isVisible = false
      #expect(!root.emit(.navigationSplit(shown)))
      await session.close()
      #expect(!controller.request(shown, emit: root.emit))
    } catch {
      await session.close()
      throw error
    }
  }
}

extension NavigationSplitTests {
  @Test func removingTheMiddleColumnInvalidatesPendingContentRequests() throws {
    let initial = try NodeStore().staging(TreeFixture.frame(TreeFixture.splitTree)).tree
    let tree = RenderTree()
    tree.commit(initial)
    let root = try #require(tree.root)
    let controller = try #require(root.splitController)
    var pending = controller.state
    pending.visibility = 2
    #expect(controller.request(pending, emit: { _ in true }))
    let binding = controller.compactColumnBinding(emit: { _ in true })
    _ = binding.wrappedValue
    let updated = try initial.staging(
      TreeFixture.frame(
        [
          TreeFixture.navigationSplit(visibility: 1, compact: 0, hasContent: false, update: true),
          TreeFixture.children(1, [2, 4]),
          TreeFixture.operation(OperationId.dropNode) { $0.integer(UInt64(3)) },
        ], base: 1, revision: 2)
    ).tree
    tree.commit(updated)
    #expect(tree.root === root && root.splitController === controller)
    #expect(controller.state.visibility == 1 && controller.state.compactColumn == 0)
    binding.wrappedValue = .detail
    #expect(controller.state.compactColumn == 0)
    _ = binding.wrappedValue
    binding.wrappedValue = .content
    #expect(controller.state.compactColumn == 0)
    controller.resolve(pending)
    #expect(controller.state.compactColumn == 0)
    #expect(root.children.count == 2 && tree.nodes[3] == nil)
  }
}
