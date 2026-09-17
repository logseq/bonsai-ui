import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func menu(
    items: [(Int64, UInt8, Bool, Bool, UInt8, Bool, UInt16)] = [
      (-7, 0, true, false, 0, true, 0), (9, 1, true, true, 0, true, 0),
    ], enabled: Bool = true, handler: UInt64? = 91, update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(61))
      if update { $0.integer(UInt64(3)) }
      $0.integer(UInt16(items.count))
      for (id, kind, active, selected, role, label, children) in items {
        $0.integer(id)
        $0.integer(kind)
        $0.integer(UInt8(active ? 1 : 0))
        $0.integer(UInt8(selected ? 1 : 0))
        $0.integer(role)
        $0.integer(UInt8(label ? 1 : 0))
        $0.integer(children)
      }
      $0.integer(UInt8(enabled ? 1 : 0))
      if !update {
        $0.integer(UInt16(handler == nil ? 0 : 1))
        if let handler {
          $0.integer(UInt16(54))
          $0.integer(handler)
        }
      }
    }
  }
  static func menuTree() -> [WireOperation] {
    [
      menu(), text(2, "Actions"), text(3, "Open"), text(4, "Pinned"), children(1, [2, 3, 4]),
      root(1),
    ]
  }
}

@MainActor struct MenuTests {
  @Test func retainedMenuRendersAfterAValidLabelReduction() async throws {
    _ = NSApplication.shared
    let tree = RenderTree()
    tree.commit(try NodeStore().staging(TreeFixture.frame(TreeFixture.menuTree())).tree)
    let node = try #require(tree.root)
    guard case .menu(let properties) = node.properties else {
      Issue.record("Expected a menu")
      return
    }
    let retained = NativeMenu(
      node: node, properties: properties, controller: try #require(node.menuController),
      activate: { _ in })
    let replacement = try NodeStore().staging(TreeFixture.frame([
      TreeFixture.menu(items: [(-7, 0, true, false, 0, true, 0)]),
      TreeFixture.text(2, "Actions"), TreeFixture.text(3, "Open"),
      TreeFixture.children(1, [2, 3]), TreeFixture.root(1),
    ], revision: 2)).tree
    tree.commit(replacement)
    let host = NSHostingView(rootView: retained)
    host.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = host
    window.orderFront(nil)
    try await Task.sleep(for: .milliseconds(50))
    host.layoutSubtreeIfNeeded()
    func menuButton(in view: NSView) -> NSPopUpButton? {
      if let button = view as? NSPopUpButton { return button }
      for child in view.subviews {
        if let button = menuButton(in: child) { return button }
      }
      return nil
    }
    let button = try #require(menuButton(in: host))
    let menu = try #require(button.menu)
    let cancellation = Timer(timeInterval: 0.05, repeats: true) { _ in
      MainActor.assumeIsolated { button.menu?.cancelTrackingWithoutAnimation() }
    }
    RunLoop.main.add(cancellation, forMode: .eventTracking)
    defer { cancellation.invalidate() }
    button.performClick(nil)
    #expect(menu.items.contains { $0.title == "Pinned" })
  }

  @Test func menuActionsRetainEveryRequestIncludingRepeatedSignedIds() throws {
    var queue = NativeEventQueue()
    for sequence in UInt64(1)...3 {
      let accepted = queue.append(
        NativeEvent(
          sequence: sequence, displayedRevision: 1, nodeID: 1, handlerID: 91,
          payload: .menuAction(-7)))
      #expect(accepted)
    }
    #expect(queue.events.map(\.payload) == [.menuAction(-7), .menuAction(-7), .menuAction(-7)])
  }

  @Test func malformedMenuHierarchyCannotStage() throws {
    let bad: [[(Int64, UInt8, Bool, Bool, UInt8, Bool, UInt16)]] = [
      [], (0..<1025).map { (Int64($0), 0, true, false, 0, true, UInt16(0)) },
      [(-7, 5, true, false, 0, true, 0)],
      [(-7, 0, true, false, 0, true, 1)],
      [(-7, 0, true, false, 0, false, 0)],
      [(-7, 2, false, false, 0, true, 0)],
      [(-7, 0, true, true, 0, true, 0)],
      [(-7, 4, true, false, 0, true, 0)],
      [(-7, 0, true, false, 3, true, 0)],
      [(-7, 0, true, false, 0, true, 0), (-7, 0, true, false, 0, true, 0)],
      (1...33).map { (Int64($0), 4, true, false, 0, true, UInt16(1)) } + [
        (34, 0, true, false, 0, true, 0)
      ],
    ]
    for items in bad {
      #expect(throws: TreeError.invalidProperties) {
        _ = try NodeStore().staging(
          TreeFixture.frame([TreeFixture.menu(items: items), TreeFixture.root(1)]))
      }
    }
    #expect(throws: (any Error).self) {
      _ = try NodeStore().staging(
        TreeFixture.frame([TreeFixture.menu(enabled: false), TreeFixture.root(1)]))
    }
  }

  @Test func retainedMenuActionsCannotReachReplacedBindings() throws {
    let initial = try NodeStore().staging(TreeFixture.frame(TreeFixture.menuTree())).tree
    let tree = RenderTree()
    tree.commit(initial)
    let controller = try #require(tree.root?.menuController)
    var events = 0
    let action = controller.action(
      -7,
      emit: { _ in
        events += 1
        return true
      })
    action()
    let replaced = TreeFixture.operation(OperationId.updateEventBindings) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(1))
      $0.integer(UInt16(54))
      $0.integer(UInt64(92))
    }
    tree.commit(try initial.staging(TreeFixture.frame([replaced], base: 1, revision: 2)).tree)
    action()
    #expect(events == 1)
    #expect(controller.pending.isEmpty)
    controller.dispose()
    controller.action(
      -7,
      emit: { _ in
        events += 1
        return true
      })()
    #expect(events == 1)
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualGalleryMenuActionsRespectHierarchyAndOcamlOwnership() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    func button(_ title: String) throws -> RenderNodeState {
      let label = try #require(
        session.tree.nodes.values.first {
          if case .text(let text) = $0.properties { return text.value == title }
          return false
        })
      return try #require(session.tree.nodes.values.first { $0.children.contains { $0 === label } })
    }
    do {
      try await session.start(entrypoint: "native-menu")
      #expect(try await session.presented(#require(session.ticket)))
      let node = try #require(session.tree.nodes.values.first { $0.menuController != nil })
      let menu = try #require(node.menuController)
      #expect(menu.select(-7, emit: node.emit))
      #expect(menu.select(-7, emit: node.emit))
      try await flush()
      #expect(
        session.tree.nodes.values.contains {
          if case .text(let t) = $0.properties { return t.value == "Actions: -7,-7" }
          return false
        })
      #expect(!menu.select(11, emit: node.emit))
      #expect(!menu.select(22, emit: node.emit))
      #expect(!menu.select(20, emit: node.emit))
      #expect(menu.select(21, emit: node.emit))
      try await flush()
      #expect(menu.select(9, emit: node.emit))
      try await flush()
      #expect(menu.checked(9))
      #expect(menu.select(9, emit: node.emit))
      #expect(try await session.refresh())
      let echo = try #require(session.ticket)
      #expect(menu.select(9, emit: node.emit))
      #expect(try await session.presented(echo))
      try await flush()
      #expect(menu.checked(9))
      #expect(session.activate(try button("Ignore menu changes")))
      try await flush()
      for _ in 0..<2 {
        #expect(menu.select(9, emit: node.emit))
        #expect(!(try await session.refresh()))
        #expect(menu.checked(9))
      }
      let stale = menu.action(-7, emit: node.emit)
      #expect(session.activate(try button("Replace menu handler")))
      _ = try await session.refresh()
      #expect(!node.emit(.menuAction(-7)))
      #expect(try await session.presented(#require(session.ticket)))
      stale()
      #expect(!(try await session.refresh()))
      #expect(session.activate(try button("Disable menu")))
      try await flush()
      #expect(!menu.select(-7, emit: node.emit))
      #expect(session.activate(try button("Enable menu")))
      try await flush()
      session.isVisible = false
      #expect(!menu.select(-7, emit: node.emit))
      await session.close()
      #expect(!menu.select(-7, emit: node.emit))
    } catch {
      await session.close()
      throw error
    }
  }
}
