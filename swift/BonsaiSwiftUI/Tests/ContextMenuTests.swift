import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func contextMenu(_ id: UInt64 = 3, enabled: Bool = true, update: Bool = false)
    -> WireOperation
  {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(146))
      if update { $0.integer(UInt64(1)) }
      $0.integer(UInt8(enabled ? 1 : 0))
      if !update { $0.integer(UInt16(0)) }
    }
  }
  static func contextAction(
    _ id: UInt64 = 4, key: String = "delete", title: String = "Delete", enabled: Bool = true,
    role: UInt8 = 1, symbol: String? = "trash", update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(147))
      if update { $0.integer(UInt64(31)) }
      try! $0.string(key)
      try! $0.string(title)
      $0.integer(UInt8(enabled ? 1 : 0))
      $0.integer(role)
      $0.integer(UInt8(symbol == nil ? 0 : 1))
      if let symbol { try! $0.string(symbol) }
      if !update {
        $0.integer(UInt16(enabled ? 1 : 0))
        if enabled {
          $0.integer(UInt16(EventTagId.press))
          $0.integer(id + 90)
        }
      }
    }
  }
  static func contextTree() -> [WireOperation] {
    [
      create(1, kind: 148), text(2, "Context target"), contextMenu(), contextAction(),
      children(1, [2, 3]), children(3, [4]), root(1),
    ]
  }
}

@MainActor struct ContextMenuTests {
  @Test func presentedActionsKeepTheirHandlerAndOneShotPresentationAcrossRebinding() throws {
    var store = try NodeStore().staging(TreeFixture.frame(TreeFixture.contextTree())).tree
    let tree = RenderTree()
    var calls: [RenderIdentity] = []
    var accept = true
    tree.onInput = { node, payload in
      guard accept, payload == .press else { return false }
      calls.append(node.id)
      return true
    }
    tree.commit(store)
    let owner = try #require(tree.nodes[3]?.contextMenuController)
    let old = owner.capture()
    let item = try #require(old.items.first)
    #expect(owner.perform(item, from: old))
    #expect(!owner.perform(item, from: old))
    let rebound = owner.capture()
    let rebind = TreeFixture.operation(OperationId.updateEventBindings) {
      $0.integer(UInt64(4))
      $0.integer(UInt16(1))
      $0.integer(UInt16(EventTagId.press))
      $0.integer(UInt64(194))
    }
    store = try store.staging(TreeFixture.frame([rebind], base: 1, revision: 2)).tree
    tree.commit(store)
    #expect(!owner.perform(try #require(rebound.items.first), from: rebound))
    let rejected = owner.capture()
    accept = false
    #expect(!owner.perform(try #require(rejected.items.first), from: rejected))
    accept = true
    #expect(!owner.perform(try #require(rejected.items.first), from: rejected))
    let current = owner.capture()
    #expect(owner.perform(try #require(current.items.first), from: current))
    #expect(calls == [item.id, item.id])
    let hidden = owner.capture()
    owner.setActive(false)
    owner.setActive(true)
    #expect(!owner.perform(try #require(hidden.items.first), from: hidden))
    let disposed = owner.capture()
    owner.dispose()
    #expect(!owner.perform(try #require(disposed.items.first), from: disposed))
  }

  @Test func freshPresentationRevokesOlderClosuresAndDisabledOrForeignItems() throws {
    let tree = RenderTree()
    tree.commit(try NodeStore().staging(TreeFixture.frame(TreeFixture.contextTree())).tree)
    tree.onInput = { _, _ in true }
    let owner = try #require(tree.nodes[3]?.contextMenuController)
    let old = owner.capture()
    let next = owner.capture()
    #expect(!owner.perform(try #require(old.items.first), from: old))
    let foreign = ContextMenuController(identity: RenderIdentity(epoch: 1, node: 99), enabled: true)
    #expect(!foreign.perform(try #require(next.items.first), from: next))
    owner.synchronize(enabled: false, actions: owner.actions)
    #expect(!owner.perform(try #require(next.items.first), from: next))
  }

  @Test func contextActionAndMenuIncarnationsCannotBeTransplantedBetweenOwners() throws {
    let initial = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.create(1, kind: 148), TreeFixture.create(2, kind: 148),
        TreeFixture.text(9, "Base"),
        TreeFixture.contextMenu(3), TreeFixture.contextMenu(7),
        TreeFixture.contextAction(4), TreeFixture.contextAction(5),
        TreeFixture.children(1, [2, 3]), TreeFixture.children(2, [9, 7]),
        TreeFixture.children(3, [4]), TreeFixture.children(7, [5]), TreeFixture.root(1),
      ])
    ).tree
    for change in [
      [TreeFixture.children(3, [5]), TreeFixture.children(7, [4])],
      [TreeFixture.children(1, [2, 7]), TreeFixture.children(2, [9, 3])],
    ] {
      #expect(throws: TreeError.invalidIdentity) {
        try initial.staging(TreeFixture.frame(change, base: 1, revision: 2))
      }
    }
  }

  @Test func ordinaryContextModifierStagesOnlyOwnedUniqueActions() throws {
    let initial = try NodeStore().staging(TreeFixture.frame(TreeFixture.contextTree())).tree
    #expect(initial.nodes[4]?.bindings[EventTagId.press] == 94)
    for mutation in [
      [TreeFixture.children(1, [3, 2])],
      [TreeFixture.root(3)],
      [TreeFixture.contextAction(5), TreeFixture.children(3, [4, 5])],
      [TreeFixture.contextAction(role: 2, update: true)],
      [TreeFixture.contextAction(title: " ", update: true)],
      [TreeFixture.contextAction(symbol: "", update: true)],
      [TreeFixture.children(4, [2])],
    ] {
      #expect(throws: (any Error).self) {
        try initial.staging(TreeFixture.frame(mutation, base: 1, revision: 2))
      }
    }
  }
}

@MainActor private final class ContextMenuCapture: NSObject {
  var menu: NSMenu?
  var onOpened: (() -> Void)?
  @objc func opened(_ notification: Notification) {
    menu = notification.object as? NSMenu
    onOpened?()
  }
}

@MainActor private func captureContextMenu(
  in host: NSView, at point: CGPoint, onOpened: (() -> Void)? = nil
) async throws -> NSMenu {
  let window = try #require(host.window)
  let event = try #require(
    NSEvent.mouseEvent(
      with: .rightMouseDown,
      location: host.convert(point, to: nil), modifierFlags: [], timestamp: 0,
      windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
  let capture = ContextMenuCapture()
  capture.onOpened = onOpened
  NotificationCenter.default.addObserver(
    capture, selector: #selector(ContextMenuCapture.opened(_:)),
    name: NSMenu.didBeginTrackingNotification, object: nil)
  let cancellation = Timer(timeInterval: 0.05, repeats: true) { _ in
    MainActor.assumeIsolated { capture.menu?.cancelTrackingWithoutAnimation() }
  }
  RunLoop.main.add(cancellation, forMode: .eventTracking)
  defer {
    cancellation.invalidate()
    NotificationCenter.default.removeObserver(capture)
  }
  await withCheckedContinuation { continuation in
    DispatchQueue.main.async {
      NSApp.sendEvent(event)
      continuation.resume()
    }
  }
  return try #require(capture.menu)
}

extension ContextMenuTests {
  @Test func hostedNativeContextMenuUsesThePresentedActionSnapshot() async throws {
    initializeAccessibilityApplication()
    let tree = RenderTree()
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.contextTree())).tree
    tree.commit(store)
    var calls = 0
    tree.onInput = { _, _ in
      calls += 1
      return true
    }
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 300, height: 100),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }
    try await settleAccessibility(host)
    let point = CGPoint(x: host.bounds.midX, y: host.bounds.midY)
    let native = try await captureContextMenu(in: host, at: point)
    native.update()
    let index = try #require(native.items.firstIndex { $0.title == "Delete" })
    #expect(native.items[index].image != nil)
    native.performActionForItem(at: index)
    #expect(calls == 1)
    native.performActionForItem(at: index)
    #expect(calls == 1)
    let rebind = TreeFixture.operation(OperationId.updateEventBindings) {
      $0.integer(UInt64(4))
      $0.integer(UInt16(1))
      $0.integer(UInt16(EventTagId.press))
      $0.integer(UInt64(194))
    }
    let updated = try store.staging(TreeFixture.frame([rebind], base: 1, revision: 2)).tree
    let stale = try await captureContextMenu(
      in: host, at: point, onOpened: { tree.commit(updated) })
    let staleIndex = try #require(stale.items.firstIndex { $0.title == "Delete" })
    try await settleAccessibility(host)
    stale.performActionForItem(at: staleIndex)
    #expect(calls == 1)
    let current = try await captureContextMenu(in: host, at: point)
    current.performActionForItem(
      at: try #require(current.items.firstIndex { $0.title == "Delete" }))
    #expect(calls == 2)
    let repeated = try await captureContextMenu(in: host, at: point)
    repeated.performActionForItem(
      at: try #require(repeated.items.firstIndex { $0.title == "Delete" }))
    #expect(calls == 3)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func nativeOutlineContextMenusKeepParentAndChildHandlerOwnership() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-outline")
      #expect(try await session.presented(#require(session.ticket)))
      func flush() async throws {
        _ = try await session.refresh()
        if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
      }
      func button(_ title: String) throws -> RenderNodeState {
        try #require(
          session.tree.nodes.values.first { node in
            guard case .button = node.properties else { return false }
            return node.children.contains {
              if case .text(let text) = $0.properties { return text.value == title }
              return false
            }
          })
      }
      func owner(_ title: String) throws -> ContextMenuController {
        try #require(
          session.tree.contextMenuNodes.first { node in
            node.children.contains {
              if case .contextAction(let action) = $0.properties { return action.title == title }
              return false
            }
          }?.contextMenuController)
      }
      func selected(_ value: String) -> Bool {
        session.tree.nodes.values.contains {
          if case .text(let text) = $0.properties { return text.value.contains(value) }
          return false
        }
      }
      let parent = try owner("Delete parent")
      let child = try owner("Delete child")
      initializeAccessibilityApplication()
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { _ = session.activate($0) }))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 650, height: 500),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      func table(in view: NSView) -> NSOutlineView? {
        (view as? NSOutlineView) ?? view.subviews.lazy.compactMap { table(in: $0) }.first
      }
      let outline = try #require(table(in: host))
      func menu(_ owner: ContextMenuController) async throws -> NSMenu {
        let rowID = try #require(session.tree.parents[owner.identity.node])
        let row = try #require(session.tree.nodes[rowID])
        let geometry = try #require(
          session.tree.listNodes.first?.listScrollController?.nativeHost.geometry(row.id))
        let point = host.convert(
          CGPoint(x: outline.bounds.midX, y: geometry.row.midY), from: outline)
        return try await captureContextMenu(in: host, at: point)
      }
      let parentMenu = try await menu(parent)
      #expect(parentMenu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["Delete parent"])
      let childMenu = try await menu(child)
      #expect(childMenu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["Delete child"])
      childMenu.performActionForItem(
        at: try #require(childMenu.items.firstIndex { $0.title == "Delete child" }))
      try await flush()
      #expect(selected("Actions 1 Delete child@0"))
      parentMenu.performActionForItem(
        at: try #require(parentMenu.items.firstIndex { $0.title == "Delete parent" }))
      try await flush()
      #expect(selected("Actions 2 Delete parent@0"))
      let beforeRebind = child.capture()
      #expect(session.activate(try button("Rebind actions")))
      try await flush()
      #expect(!child.perform(try #require(beforeRebind.items.first), from: beforeRebind))
      let beforeCollapse = child.capture()
      let parentRow = try #require(session.tree.nodes[session.tree.parents[parent.identity.node]!])
      #expect(try #require(parentRow.booleanControlController).request(false, emit: parentRow.emit))
      #expect(!child.perform(try #require(beforeCollapse.items.first), from: beforeCollapse))
      try await flush()
      #expect(try #require(parentRow.booleanControlController).request(true, emit: parentRow.emit))
      try await flush()
      #expect(!child.perform(try #require(beforeCollapse.items.first), from: beforeCollapse))
      let beforeMove = child.capture()
      #expect(session.activate(try button("Move child")))
      try await flush()
      let moved = try owner("Delete child")
      #expect(moved.identity != child.identity)
      #expect(!child.perform(try #require(beforeMove.items.first), from: beforeMove))
      let current = moved.capture()
      #expect(moved.perform(try #require(current.items.first), from: current))
      try await flush()
      #expect(selected("Actions 3 Delete child@1"))
      let inactive = moved.capture()
      session.isVisible = false
      session.isVisible = true
      #expect(!moved.perform(try #require(inactive.items.first), from: inactive))
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
