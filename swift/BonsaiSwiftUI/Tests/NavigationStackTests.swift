import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func navigationStack(_ id: UInt64 = 1, title: String = "Inbox", handler: UInt64? = 90)
    -> WireOperation
  {
    operation(OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(13))
      try! $0.string(title)
      $0.integer(UInt16(handler == nil ? 0 : 1))
      if let handler {
        $0.integer(UInt16(50))
        $0.integer(handler)
      }
    }
  }
  static func destination(
    _ id: UInt64, key: String = "message", title: String = "Message", canPop: UInt8 = 1,
    update: Bool = false
  ) -> WireOperation {
    modifier(id, kind: 14, mask: 7, update: update) {
      try! $0.string(key)
      try! $0.string(title)
      $0.integer(canPop)
    }
  }
  static var navigationTree: [WireOperation] {
    [
      navigationStack(), text(2, "Inbox content"), destination(3), text(4, "Message content"),
      children(3, [4]), children(1, [2, 3]), root(1),
    ]
  }
}

@MainActor struct NavigationStackTests {
  @Test func nativeStackDisplaysDestinationAndRevealsRootAfterPathRequest() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    tree.commit(try NodeStore().staging(TreeFixture.frame(TreeFixture.navigationTree)).tree)
    var inputs = [NativeEventPayload]()
    tree.onInput = { _, payload in
      inputs.append(payload)
      return true
    }
    let host = NSHostingController(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    host.sceneBridgingOptions = .all
    let window = NSWindow(contentViewController: host)
    window.setContentSize(NSSize(width: 420, height: 300))
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentViewController = nil
    }
    try await settleAccessibility(host.view)
    #expect(
      accessibilityElements(host.view).contains {
        $0.value == "Message content" || $0.label == "Message content"
      })
    let controller = try #require(tree.root?.navigationController)
    #expect(controller.request([], emit: try #require(tree.root).emit))
    try await settleAccessibility(host.view)
    #expect(inputs.count == 1)
    let event = try #require(inputs.first)
    let bytes = try EventBatch.encode(
      epoch: 1,
      events: [
        NativeEvent(sequence: 1, displayedRevision: 1, nodeID: 1, handlerID: 90, payload: event)
      ])
    // A native path request reports the complete remaining path, in one event.
    #expect(bytes.suffix(4) == Data([0, 0, 0, 0]))
    #expect(
      accessibilityElements(host.view).contains {
        $0.value == "Inbox content" || $0.label == "Inbox content"
      })
  }

  @Test func navigationGraphsRejectInvalidOwnershipAndMalformedDestinationsAtomically() throws {
    let initial = try NodeStore().staging(TreeFixture.frame(TreeFixture.navigationTree)).tree
    for op in [
      TreeFixture.children(1, []), TreeFixture.children(1, [3, 2]), TreeFixture.children(3, []),
    ] {
      #expect(throws: (any Error).self) {
        try initial.staging(TreeFixture.frame([op], base: 1, revision: 2))
      }
    }
    for destination in [TreeFixture.destination(3, key: ""), TreeFixture.destination(3, canPop: 2)]
    {
      #expect(throws: (any Error).self) {
        try NodeStore().staging(
          TreeFixture.frame([
            TreeFixture.navigationStack(), TreeFixture.text(2, "Root"), destination,
            TreeFixture.text(4, "Child"), TreeFixture.children(3, [4]),
            TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
          ]))
      }
    }
    #expect(throws: (any Error).self) {
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.destination(1), TreeFixture.text(2, "Orphan"), TreeFixture.children(1, [2]),
          TreeFixture.root(1),
        ]))
    }
    #expect(throws: (any Error).self) {
      try NodeStore().staging(
        TreeFixture.frame([
          TreeFixture.navigationStack(), TreeFixture.text(2, "Root"), TreeFixture.destination(3),
          TreeFixture.text(4, "A"), TreeFixture.destination(5), TreeFixture.text(6, "B"),
          TreeFixture.children(3, [4]), TreeFixture.children(5, [6]),
          TreeFixture.children(1, [2, 3, 5]), TreeFixture.root(1),
        ]))
    }
    #expect(initial.revision == 1)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualNavigationExamplePushesAndAcceptsNativePathChanges() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-navigation")
      let root = try #require(session.tree.root)
      let controller = try #require(root.navigationController)
      #expect(controller.path.isEmpty)
      #expect(try await session.presented(#require(session.ticket)))
      let open = try #require(
        session.tree.nodes.values.first { if case .button = $0.properties { true } else { false } })
      #expect(session.activate(open))
      #expect(try await session.refresh())
      #expect(controller.path.count == 1)
      // A destination cannot request navigation against an unpresented path.
      #expect(!controller.request([], emit: root.emit))
      #expect(try await session.presented(#require(session.ticket)))
      #expect(controller.request([], emit: root.emit))
      #expect(controller.path.isEmpty)
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(session.tree.root === root && session.tree.nodes[open.id.node] === open)
      #expect(root.children.count == 1)
      #expect(!controller.request([], emit: root.emit))
      await session.close()
      #expect(!root.emit(.navigationPath([])))
    } catch {
      await session.close()
      throw error
    }
  }
}

@MainActor struct NavigationRequestTests {
  @Test func pendingBackRequestsAreBoundedAndRespectPolicyAndDisposal() throws {
    let tree = RenderTree()
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.navigationTree)).tree
    tree.commit(store)
    let controller = try #require(tree.root?.navigationController)
    let original = controller.path
    #expect(!controller.request([], emit: { _ in false }))
    #expect(controller.path == original)
    #expect(controller.request([], emit: { _ in true }))
    #expect(!controller.request([], emit: { _ in true }))
    controller.resolve()
    #expect(controller.path == original)
    tree.commit(
      try store.staging(
        TreeFixture.frame(
          [TreeFixture.destination(3, canPop: 0, update: true)], base: 1, revision: 2)
      ).tree)
    #expect(!controller.request([], emit: { _ in true }))
    controller.dispose()
    #expect(!controller.request([], emit: { _ in true }))
  }

  @Test func replacingAUnicodeRouteKeyChangesNativePathIdentity() throws {
    let tree = RenderTree()
    var ops = TreeFixture.navigationTree
    ops[2] = TreeFixture.destination(3, key: "é")
    let store = try NodeStore().staging(TreeFixture.frame(ops)).tree
    tree.commit(store)
    let controller = try #require(tree.root?.navigationController)
    let original = controller.path
    tree.commit(
      try store.staging(
        TreeFixture.frame(
          [TreeFixture.destination(3, key: "e\u{301}", update: true)], base: 1, revision: 2)
      ).tree)
    #expect(controller.path != original)
    var payload: NativeEventPayload?
    #expect(
      controller.request(
        [],
        emit: {
          payload = $0
          return true
        }))
    #expect(payload == .navigationPath([]))
  }

  @Test func multiPageBackIsOneEventAndCannotRemoveProtectedIntermediatePages() throws {
    let tree = RenderTree()
    let ops = [
      TreeFixture.navigationStack(), TreeFixture.text(2, "Root"),
      TreeFixture.destination(3, key: "a"), TreeFixture.text(4, "A"),
      TreeFixture.destination(5, key: "b"), TreeFixture.text(6, "B"),
      TreeFixture.children(3, [4]), TreeFixture.children(5, [6]),
      TreeFixture.children(1, [2, 3, 5]), TreeFixture.root(1),
    ]
    let store = try NodeStore().staging(TreeFixture.frame(ops)).tree
    tree.commit(store)
    let controller = try #require(tree.root?.navigationController)
    var payloads = [NativeEventPayload]()
    #expect(
      controller.request(
        [],
        emit: {
          payloads.append($0)
          return true
        }))
    #expect(payloads == [.navigationPath([])])
    controller.resolve()
    tree.commit(
      try store.staging(
        TreeFixture.frame(
          [TreeFixture.destination(3, key: "a", canPop: 0, update: true)], base: 1, revision: 2)
      ).tree)
    #expect(!controller.request([], emit: { _ in true }))
    #expect(
      controller.request(
        Array(controller.path.prefix(1)),
        emit: {
          payloads.append($0)
          return true
        }))
    #expect(payloads.last == .navigationPath(["a"]))
  }
}

extension NavigationRequestTests {
  @Test func staleNativeBindingCannotPopAReplacementDestination() throws {
    let tree = RenderTree()
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.navigationTree)).tree
    tree.commit(store)
    let controller = try #require(tree.root?.navigationController)
    var inputs = [NativeEventPayload]()
    let old = controller.binding(emit: {
      inputs.append($0)
      return true
    })
    tree.commit(
      try store.staging(
        TreeFixture.frame(
          [TreeFixture.destination(3, key: "replacement", update: true)], base: 1, revision: 2)
      ).tree)
    old.wrappedValue = []
    #expect(inputs.isEmpty)
    #expect(controller.path.count == 1)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualPathRequestsPreservePrefixesAndRestoreRejectedNativePops()
    async throws
  {
    for accepted in [true, false] {
      let session = BonsaiSession()
      session.isVisible = true
      do {
        try await session.start(
          entrypoint: accepted ? "native-navigation-paths" : "native-navigation-veto")
        let root = try #require(session.tree.root)
        let controller = try #require(root.navigationController)
        #expect(try await session.presented(#require(session.ticket)))
        let original = controller.path
        #expect(original.count == 2)
        session.isActive = false
        #expect(!controller.request(Array(original.prefix(1)), emit: root.emit))
        session.isActive = true
        #expect(controller.request(Array(original.prefix(1)), emit: root.emit))
        let changed = try await session.refresh()
        #expect(changed == accepted)
        if accepted {
          #expect(try await session.presented(#require(session.ticket)))
          #expect(controller.path == Array(original.prefix(1)))
          #expect(controller.request([], emit: root.emit))
          #expect(try await session.refresh())
          #expect(try await session.presented(#require(session.ticket)))
          #expect(controller.path.isEmpty)
        } else {
          #expect(controller.path == original)
          #expect(controller.request([], emit: root.emit))
          #expect(!(try await session.refresh()))
          #expect(controller.path == original)
        }
        await session.close()
      } catch {
        await session.close()
        throw error
      }
    }
  }
}
