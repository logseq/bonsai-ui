import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func scrollTargets(
    ids: [Int64] = [-7, 9, 13], position: Int64? = -7,
    vertical: UInt8 = 0, fraction: Double = 1, spacing: Double = 0,
    alignment: UInt8 = 0, snapping: UInt8 = 1, enabled: UInt8 = 1,
    update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(62))
      if update { $0.integer(UInt64(511)) }
      $0.integer(vertical)
      $0.integer(UInt16(ids.count))
      for id in ids { $0.integer(id) }
      $0.integer(UInt8(position == nil ? 0 : 1))
      if let position { $0.integer(position) }
      $0.integer(fraction.bitPattern)
      $0.integer(spacing.bitPattern)
      $0.integer(alignment)
      $0.integer(snapping)
      $0.integer(enabled)
      $0.integer(UInt8(1))
      if !update {
        $0.integer(UInt16(enabled == 1 ? 1 : 0))
        if enabled == 1 {
          $0.integer(UInt16(55))
          $0.integer(UInt64(100))
        }
      }
    }
  }
  static func scrollTargetTree(_ properties: WireOperation = scrollTargets()) -> [WireOperation] {
    [
      properties, text(2, "First card"), text(3, "Second card"), text(4, "Third card"),
      children(1, [2, 3, 4]), root(1),
    ]
  }
}

@MainActor struct ScrollTargetsTests {
  @Test func targetScrollStagesAndReordersKeyedChildrenAtomically() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.scrollTargetTree())).tree
    #expect(store.nodes[1]?.kind == 62)
    let tree = RenderTree()
    tree.commit(store)
    let retained = try #require(tree.nodes[3])
    let next = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.scrollTargets(ids: [13, 9, -7], position: 9, update: true),
          TreeFixture.children(1, [4, 3, 2]),
        ], base: 1, revision: 2)
    ).tree
    tree.commit(next)
    #expect(tree.nodes[3] === retained)
    #expect(tree.nodes[1]?.scrollTargetsController?.position == 9)
  }

  @Test func malformedTargetsCannotPublishPartialFrames() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.scrollTargetTree())).tree
    for props in [
      TreeFixture.scrollTargets(ids: [-7, -7, 13], update: true),
      TreeFixture.scrollTargets(position: 99, update: true),
      TreeFixture.scrollTargets(position: nil, update: true),
      TreeFixture.scrollTargets(fraction: 0, update: true),
      TreeFixture.scrollTargets(fraction: 1.01, update: true),
      TreeFixture.scrollTargets(fraction: .nan, update: true),
      TreeFixture.scrollTargets(spacing: -1, update: true),
      TreeFixture.scrollTargets(alignment: 3, update: true),
      TreeFixture.scrollTargets(snapping: 2, update: true),
    ] {
      #expect(throws: (any Error).self) {
        try store.staging(TreeFixture.frame([props], base: 1, revision: 2))
      }
    }
    #expect(throws: (any Error).self) {
      try store.staging(TreeFixture.frame([TreeFixture.children(1, [2, 3])], base: 1, revision: 2))
    }
    let props = TreeFixture.scrollTargets(update: true)
    for length in 0..<props.body.count {
      #expect(throws: (any Error).self) {
        try store.staging(
          TreeFixture.frame(
            [WireOperation(opcode: props.opcode, body: props.body.prefix(length))], base: 1,
            revision: 2))
      }
    }
    #expect(store.revision == 1)
    let empty = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.scrollTargets(ids: [], position: nil), TreeFixture.children(1, []),
        TreeFixture.root(1),
      ])
    ).tree
    #expect(empty.nodes[1]?.children.isEmpty == true)
  }

  @Test func controlledPositionRestoresRejectionAndFencesReplacedOrRemovedTargets() throws {
    var store = try NodeStore().staging(TreeFixture.frame(TreeFixture.scrollTargetTree())).tree
    let tree = RenderTree()
    var events: [NativeEventPayload] = []
    tree.onInput = { _, event in
      events.append(event)
      return true
    }
    tree.commit(store)
    let node = try #require(tree.root)
    let controller = try #require(node.scrollTargetsController)
    let binding = controller.binding(emit: node.emit)
    _ = binding.wrappedValue
    binding.wrappedValue = 9
    #expect(events == [.scrollPosition(9)])
    let request = try #require(controller.pending)
    #expect(controller.position == 9)
    controller.resolve(request)
    #expect(controller.position == -7)
    #expect(controller.request(13, emit: node.emit))
    let latest = try #require(controller.pending)
    controller.resolve(request)
    #expect(controller.pending == latest)
    store = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.scrollTargets(position: 13, update: true)
        ], base: 1, revision: 2)
    ).tree
    tree.commit(store)
    controller.resolve(latest)
    #expect(controller.position == 13)
    let old = controller.binding(emit: node.emit)
    _ = old.wrappedValue
    let replacement = TreeFixture.operation(OperationId.updateEventBindings) {
      $0.integer(UInt64(1))
      $0.integer(UInt16(1))
      $0.integer(UInt16(55))
      $0.integer(UInt64(101))
    }
    store = try store.staging(TreeFixture.frame([replacement], base: 2, revision: 3)).tree
    tree.commit(store)
    let count = events.count
    old.wrappedValue = 9
    #expect(events.count == count)
    #expect(!controller.request(99, emit: node.emit))
    controller.dispose()
    #expect(!controller.request(9, emit: node.emit))
  }

  @Test func nativeHorizontalAndVerticalPositionsMoveActualScrollViews() async throws {
    initializeAccessibilityApplication()
    for vertical: UInt8 in [0, 1] {
      var store = try NodeStore().staging(
        TreeFixture.frame(
          TreeFixture.scrollTargetTree(
            TreeFixture.scrollTargets(vertical: vertical)
          ))
      ).tree
      let tree = RenderTree()
      tree.onInput = { _, _ in true }
      tree.commit(store)
      let host = NSHostingView(
        rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.contentView = host
      window.orderFront(nil)
      defer {
        window.orderOut(nil)
        window.contentView = nil
      }
      try await settleAccessibility(host)
      var pending: [NSView] = [host]
      var scroll: NSScrollView?
      while let view = pending.popLast() {
        if let value = view as? NSScrollView {
          scroll = value
          break
        }
        pending.append(contentsOf: view.subviews)
      }
      let native = try #require(scroll)
      let before = native.contentView.bounds.origin
      store = try store.staging(
        TreeFixture.frame(
          [
            TreeFixture.scrollTargets(position: 13, vertical: vertical, update: true)
          ], base: 1, revision: 2)
      ).tree
      tree.commit(store)
      try await settleAccessibility(host)
      let after = native.contentView.bounds.origin
      #expect(vertical == 1 ? after.y > before.y + 300 : after.x > before.x + 400)
    }
  }
}

extension NativeRuntimeTests {
  @Test @MainActor func actualCarouselKeepsPositionSeparateFromActionsAndRejectsObsoleteInput()
    async throws
  {
    let session = BonsaiSession()
    session.isVisible = true
    func contains(_ title: String) -> Bool {
      session.tree.nodes.values.contains {
        if case .text(let value) = $0.properties { return value.value == title }
        return false
      }
    }
    func target() throws -> RenderNodeState {
      try #require(session.tree.nodes.values.first { $0.scrollTargetsController != nil })
    }
    func button(_ title: String) throws -> RenderNodeState {
      let text = try #require(
        session.tree.nodes.values.first {
          if case .text(let text) = $0.properties { return text.value == title }
          return false
        })
      var node = text
      while true {
        if case .button = node.properties { return node }
        let child = node
        node = try #require(
          session.tree.nodes.values.first { $0.children.contains { $0 === child } })
      }
    }
    func flush() async throws {
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    func press(_ title: String) async throws {
      #expect(session.activate(try button(title)))
      try await flush()
    }
    do {
      try await session.start(entrypoint: "native-carousel")
      #expect(try await session.presented(#require(session.ticket)))
      var node = try target()
      var controller = try #require(node.scrollTargetsController)
      #expect(controller.position == -7)
      #expect(controller.request(9, emit: node.emit))
      #expect(controller.request(13, emit: node.emit))
      try await flush()
      #expect(controller.position == 13)
      #expect(contains("Position updates: 1"))
      let open = try button("Open second")
      #expect(session.activate(open))
      #expect(session.activate(open))
      try await flush()
      #expect(contains("Opened: 9 (2 actions)"))
      #expect(controller.position == 13)
      try await press("Ignore scroll changes")
      #expect(controller.request(9, emit: node.emit))
      #expect(!(try await session.refresh()))
      #expect(controller.position == 13)
      try await press("Accept scroll changes")
      let retained = try button("Open second")
      try await press("Reverse cards")
      #expect(try button("Open second") === retained)
      try await press("Remove last card")
      #expect(controller.position == -7)
      #expect(!controller.request(13, emit: node.emit))
      try await press("Restore last card")
      try await press("Use vertical layout")
      node = try target()
      controller = try #require(node.scrollTargetsController)
      #expect(contains("Axis: Vertical"))
      try await press("Go to last card")
      #expect(controller.position == 13)
      let old = controller.binding(emit: node.emit)
      _ = old.wrappedValue
      try await press("Replace scroll handler")
      old.wrappedValue = 9
      #expect(!(try await session.refresh()))
      try await press("Disable scrolling")
      #expect(!controller.request(9, emit: node.emit))
      try await press("Enable scrolling")
      session.isVisible = false
      #expect(!controller.request(9, emit: node.emit))
      session.isVisible = true
      try await press("Empty cards")
      #expect(controller.position == nil)
      #expect(try target().children.isEmpty)
      try await press("Restore cards")
      #expect(controller.position == -7)
      await session.close()
      #expect(!controller.request(9, emit: node.emit))
    } catch {
      await session.close()
      throw error
    }
  }
}

extension ScrollTargetsTests {
  @Test func previewCardsHonorAllAnchorsAndLayoutDirections() async throws {
    initializeAccessibilityApplication()
    for vertical: UInt8 in [0, 1] {
      for alignment: UInt8 in [0, 1, 2] {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
          for position: Int64 in [-7, 9, 13] {
            let tree = RenderTree()
            tree.onInput = { _, _ in true }
            tree.commit(
              try NodeStore().staging(
                TreeFixture.frame(
                  TreeFixture.scrollTargetTree(
                    TreeFixture.scrollTargets(
                      position: position, vertical: vertical, fraction: 0.6, spacing: 12,
                      alignment: alignment)
                  ))
              ).tree)
            let host = NSHostingView(
              rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in })
                .environment(\.layoutDirection, direction))
            let window = NSWindow(
              contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
              backing: .buffered, defer: false)
            window.contentView = host
            window.orderFront(nil)
            defer {
              window.orderOut(nil)
              window.contentView = nil
            }
            for _ in 0..<4 { try await settleAccessibility(host) }
            let label = try #require(
              accessibilityElements(host).first {
                $0.value
                  == (position == -7 ? "First card" : position == 9 ? "Second card" : "Third card")
              })
            let selector = NSSelectorFromString("accessibilityFrame")
            typealias Frame = @convention(c) (AnyObject, Selector) -> CGRect
            let get = unsafeBitCast(label.object.method(for: selector), to: Frame.self)
            let actual = get(label.object, selector)
            var scan: [NSView] = [host]
            var detail = ""
            while let view = scan.popLast() {
              if let scroll = view as? NSScrollView {
                detail =
                  "clip=\(scroll.contentView.bounds) doc=\(String(describing:scroll.documentView?.frame)) inset=\(scroll.contentInsets)"
                break
              }
              scan.append(contentsOf: view.subviews)
            }
            let bounds = window.convertToScreen(host.convert(host.bounds, to: nil))
            let length = vertical == 1 ? bounds.height : bounds.width
            let center = length * (0.3 + Double(alignment) * 0.2)
            let expected =
              vertical == 1
              ? bounds.maxY - center
              : direction == .leftToRight ? bounds.minX + center : bounds.maxX - center
            #expect(
              abs((vertical == 1 ? actual.midY : actual.midX) - expected) < 1,
              "axis=\(vertical) anchor=\(alignment) direction=\(direction) actual=\(actual) bounds=\(bounds) position=\(String(describing:tree.root?.scrollTargetsController?.position)) \(detail)"
            )
          }
        }
      }
    }
  }
}
