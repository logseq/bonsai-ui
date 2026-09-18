import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func toolbarEntry(
    _ id: UInt64, key: String, placement: UInt8 = 3, kind: UInt8 = 0, update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(149))
      if update { $0.integer(UInt64(7)) }
      try! $0.string(key)
      $0.integer(placement)
      $0.integer(kind)
      if !update { $0.integer(UInt16(0)) }
    }
  }
  static func toolbarChild(_ id: UInt64, key: String) -> WireOperation {
    operation(OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(150))
      try! $0.string(key)
      $0.integer(UInt16(0))
    }
  }
  static func toolbarTree() -> [WireOperation] {
    [
      create(1, kind: 74), create(10, kind: 151), text(2, "Content"),
      toolbarEntry(11, key: "first", kind: 1), toolbarChild(21, key: "action"),
      text(3, "Primary"), children(21, [3]), children(11, [21]),
      toolbarEntry(12, key: "second", kind: 1), toolbarChild(22, key: "action"),
      text(4, "Secondary"), children(22, [4]), children(12, [22]),
      toolbarEntry(13, key: "gap", kind: 3),
      children(10, [2]), children(1, [10, 11, 13, 12]), root(1),
    ]
  }
}

@MainActor struct ToolbarTests {
  @Test func toolbarPlacementChangesAndReorderingRetainContent() throws {
    let initial = try NodeStore().staging(TreeFixture.frame(TreeFixture.toolbarTree())).tree
    let tree = RenderTree()
    tree.commit(initial)
    let body = try #require(tree.nodes[2])
    let primary = try #require(tree.nodes[3])
    let updated = try initial.staging(
      TreeFixture.frame(
        [
          TreeFixture.toolbarEntry(11, key: "first", placement: 2, kind: 1, update: true),
          TreeFixture.children(1, [10, 12, 13, 11]),
        ], base: 1, revision: 2)
    ).tree
    tree.commit(updated)
    #expect(tree.nodes[2] === body)
    #expect(tree.nodes[3] === primary)
    #expect(tree.root?.children.map(\.id.node) == [10, 12, 13, 11])
    let drops = [UInt64(3), 4, 11, 12, 13, 21, 22].map { id in
      TreeFixture.operation(OperationId.dropNode) { $0.integer(id) }
    }
    let empty = try updated.staging(
      TreeFixture.frame(
        [TreeFixture.children(1, [10])] + drops, base: 2, revision: 3)
    ).tree
    tree.commit(empty)
    #expect(tree.nodes[2] === body)
  }

  @Test func malformedToolbarUpdatesLeavePublishedTreeUntouched() throws {
    let initial = try NodeStore().staging(TreeFixture.frame(TreeFixture.toolbarTree())).tree
    let invalid: [[WireOperation]] = [
      [TreeFixture.toolbarEntry(11, key: "first", placement: 10, kind: 1, update: true)],
      [TreeFixture.toolbarEntry(11, key: "first", kind: 4, update: true)],
      [TreeFixture.toolbarEntry(11, key: "second", kind: 1, update: true)],
      [
        TreeFixture.toolbarEntry(11, key: "first", placement: 1, kind: 1, update: true),
        TreeFixture.toolbarEntry(12, key: "second", placement: 1, kind: 1, update: true),
      ],
      [TreeFixture.children(1, [2, 11, 13, 12])],
      [TreeFixture.children(11, [21, 22]), TreeFixture.children(12, [])],
      [TreeFixture.children(11, [22]), TreeFixture.children(12, [21])],
      [TreeFixture.children(21, [4]), TreeFixture.children(22, [3])],
      [TreeFixture.children(13, [21]), TreeFixture.children(11, [])],
      [TreeFixture.toolbarEntry(11, key: "first", kind: 0, update: true)],
    ]
    for operations in invalid {
      #expect(throws: (any Error).self) {
        _ = try initial.staging(TreeFixture.frame(operations, base: 1, revision: 2))
      }
    }
    #expect(throws: TreeError.unavailableCapability("Bottom_bar", "macOS")) {
      _ = try initial.staging(
        TreeFixture.frame(
          [
            TreeFixture.toolbarEntry(11, key: "first", placement: 9, kind: 1, update: true)
          ], base: 1, revision: 2))
    }
    let update = TreeFixture.toolbarEntry(11, key: "first", kind: 1, update: true)
    for length in 0..<update.body.count {
      let truncated = WireOperation(opcode: update.opcode, body: update.body.prefix(length))
      #expect(throws: (any Error).self) {
        _ = try initial.staging(TreeFixture.frame([truncated], base: 1, revision: 2))
      }
    }
    #expect(initial.nodes[1]?.children == [10, 11, 13, 12])
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualToolbarRetainsCommandsAndRejectsStaleInput() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func button(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first { node in
          if case .button = node.properties {
            return node.children.contains { child in
              if case .text(let text) = child.properties { return text.value == title }
              return false
            }
          }
          return false
        })
    }
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    func text(_ value: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let text) = $0.properties { return text.value == value }
        return false
      }
    }
    do {
      try await session.start(entrypoint: "native-toolbar")
      #expect(try await session.presented(#require(session.ticket)))
      let command = try button("Toolbar action")
      #expect(session.activate(command))
      #expect(session.activate(command))
      try await flush()
      #expect(text("Toolbar actions: 2"))
      #expect(session.activate(try button("Reverse toolbar")))
      try await flush()
      #expect(try button("Toolbar action") === command)
      #expect(session.activate(try button("Move toolbar action")))
      _ = try await session.refresh()
      #expect(!session.activate(command))
      #expect(try await session.presented(#require(session.ticket)))
      #expect(session.activate(command))
      try await flush()
      #expect(text("Toolbar actions: 3"))
      #expect(session.activate(try button("Disable toolbar action")))
      try await flush()
      #expect(!session.activate(command))
      #expect(session.activate(try button("Enable toolbar action")))
      try await flush()
      #expect(session.activate(try button("Hide toolbar")))
      try await flush()
      #expect(!session.activate(command))
      #expect(session.activate(try button("Show toolbar")))
      try await flush()
      let replacement = try button("Toolbar action")
      #expect(replacement !== command)
      #expect(!session.activate(command))
      #expect(session.activate(replacement))
      try await flush()
      #expect(text("Toolbar actions: 4"))
      let pin = try #require(session.tree.nodes.values.first { $0.booleanControlController != nil })
      #expect(try #require(pin.booleanControlController).request(true, emit: pin.emit))
      try await flush()
      #expect(text("Toolbar pinned"))
      let menu = try #require(session.tree.nodes.values.first { $0.menuController != nil })
      #expect(try #require(menu.menuController).select(-7, emit: menu.emit))
      #expect(!menu.menuController!.select(9, emit: menu.emit))
      try await flush()
      #expect(text("Toolbar actions: 5"))
      session.isVisible = false
      #expect(!session.activate(replacement))
      await session.close()
      #expect(!session.activate(replacement))
    } catch {
      await session.close()
      throw error
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualToolbarGroupsExposeNativeControls() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-toolbar")
      #expect(try await session.presented(#require(session.ticket)))
      let host = NSHostingController(
        rootView:
          NativeNodeView(
            node: try #require(session.tree.root), activate: { _ = session.activate($0) }
          )
          .frame(width: 1000, height: 600))
      host.sceneBridgingOptions = .all
      let window = NSWindow(contentViewController: host)
      window.setContentSize(NSSize(width: 1000, height: 600))
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentViewController = nil
      }
      try await settleAccessibility(host.view)
      window.setContentSize(NSSize(width: 1000, height: 600))
      try await settleAccessibility(host.view)
      let toolbar = try #require(accessibilityElements(window).first { $0.role == "AXToolbar" })
      let elements = accessibilityElements(toolbar.object)
      let pin = try #require(elements.first { $0.label == "Pin toolbar" && $0.enabled })
      let action = try #require(elements.first { $0.label == "Toolbar action" && $0.enabled })
      #expect(pin.press())
      #expect(action.press())
      _ = try await session.refresh()
      #expect(try await session.presented(#require(session.ticket)))
      let texts = session.tree.nodes.values.compactMap { node -> String? in
        if case .text(let text) = node.properties { return text.value }
        return nil
      }
      #expect(texts.contains("Toolbar pinned"))
      #expect(texts.contains("Toolbar actions: 1"))
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualToolbarReparentingChangesTheActionOwner() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func button(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first { node in
          if case .button = node.properties {
            return node.children.contains {
              if case .text(let text) = $0.properties { return text.value == title }
              return false
            }
          }
          return false
        })
    }
    func flush() async throws {
      _ = try await session.refresh()
      #expect(try await session.presented(#require(session.ticket)))
    }
    do {
      try await session.start(entrypoint: "native-toolbar")
      #expect(try await session.presented(#require(session.ticket)))
      let original = try button("Toolbar action")
      #expect(session.activate(try button("Reparent toolbar action")))
      try await flush()
      let moved = try button("Toolbar action")
      #expect(moved !== original)
      #expect(!session.activate(original))
      #expect(session.activate(moved))
      try await flush()
      #expect(session.activate(try button("Reparent toolbar action")))
      try await flush()
      let returned = try button("Toolbar action")
      #expect(returned !== moved)
      #expect(returned !== original)
      #expect(!session.activate(original))
      #expect(!session.activate(moved))
      #expect(session.activate(returned))
      try await flush()
      #expect(
        session.tree.nodes.values.contains {
          if case .text(let value) = $0.properties { return value.value == "Toolbar actions: 2" }
          return false
        })
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

@MainActor private final class ToolbarMenuCapture: NSObject {
  var menu: NSMenu?
  @objc func opened(_ notification: Notification) { menu = notification.object as? NSMenu }
}

@MainActor private func openToolbarMenu(_ open: @escaping @MainActor () -> Bool) async throws
  -> NSMenu
{
  let capture = ToolbarMenuCapture()
  NotificationCenter.default.addObserver(
    capture, selector: #selector(ToolbarMenuCapture.opened(_:)),
    name: NSMenu.didBeginTrackingNotification, object: nil)
  let cancellation = Timer(timeInterval: 0.05, repeats: true) { _ in
    MainActor.assumeIsolated { capture.menu?.cancelTrackingWithoutAnimation() }
  }
  RunLoop.main.add(cancellation, forMode: .eventTracking)
  defer {
    cancellation.invalidate()
    NotificationCenter.default.removeObserver(capture)
  }
  _ = await withCheckedContinuation { continuation in
    DispatchQueue.main.async { continuation.resume(returning: open()) }
  }
  return try #require(capture.menu)
}

extension NativeRuntimeTests {
  @Test @MainActor func actualToolbarOverflowKeepsNativeCommands() async throws {
    initializeAccessibilityApplication()
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(entrypoint: "native-toolbar")
      #expect(try await session.presented(#require(session.ticket)))
      let host = NSHostingController(
        rootView:
          NativeNodeView(
            node: try #require(session.tree.root), activate: { _ = session.activate($0) }
          )
          .frame(minWidth: 250, minHeight: 300))
      host.sceneBridgingOptions = .all
      let window = NSWindow(contentViewController: host)
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentViewController = nil
      }
      try await settleAccessibility(host.view)
      let toolbar = try #require(window.toolbar)
      #expect(try #require(toolbar.visibleItems).count < toolbar.items.count)
      let more = try #require(
        accessibilityElements(window).first { $0.label == "more toolbar items" })
      let menu = try await openToolbarMenu { more.press() }
      func items(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items + menu.items.flatMap { $0.submenu.map(items) ?? [] }
      }
      func command(_ title: String, in menu: NSMenu) throws -> NSMenuItem {
        try #require(
          items(menu).first { $0.title == title && $0.submenu == nil && $0.action != nil })
      }
      func invoke(_ item: NSMenuItem) throws {
        let owner = try #require(item.menu)
        owner.performActionForItem(at: owner.index(of: item))
      }
      func flush() async throws {
        _ = try await session.refresh()
        if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
      }
      func contains(_ text: String) -> Bool {
        session.tree.nodes.values.contains {
          if case .text(let value) = $0.properties { return value.value == text }
          return false
        }
      }
      #expect(items(menu).contains { $0.title == "Unavailable action" && !$0.isEnabled })
      let action = try command("Toolbar action", in: menu)
      try invoke(action)
      try await flush()
      #expect(contains("Toolbar actions: 1"))
      try invoke(command("Additional action", in: menu))
      try await flush()
      #expect(contains("Toolbar actions: 2"))
      try invoke(command("Pin toolbar", in: menu))
      try await flush()
      #expect(contains("Toolbar pinned"))
      let reparent = try #require(
        session.tree.nodes.values.first { node in
          if case .button = node.properties {
            return node.children.contains {
              if case .text(let text) = $0.properties {
                return text.value == "Reparent toolbar action"
              }
              return false
            }
          }
          return false
        })
      #expect(session.activate(reparent))
      try await flush()
      try await settleAccessibility(host.view)
      try invoke(action)
      try await flush()
      #expect(contains("Toolbar actions: 2"))
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}
