import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func hoverRegion(
    _ id: UInt64 = 1, blocks: UInt8 = 1, update: Bool = false, tags: [Int] = [5, 6]
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(52))
      if update { $0.integer(UInt64(1)) }
      $0.integer(blocks)
      if !update {
        $0.integer(UInt16(tags.count))
        for tag in tags {
          $0.integer(UInt16(tag))
          $0.integer(UInt64(tag + 100))
        }
      }
    }
  }
  static func hoverRegionTree(_ node: WireOperation = hoverRegion()) -> [WireOperation] {
    [node, text(2, "Hover target"), children(1, [2]), root(1)]
  }
}

@MainActor struct HoverRegionTests {
  @Test func rootReplacementMountsTheNewCaptureAndRejectsRetiredCallbacks() async throws {
    _ = NSApplication.shared
    let tree = RenderTree()
    var events: [RenderIdentity] = []
    tree.onInput = { node, _ in
      events.append(node.id)
      return true
    }
    let operations = TreeFixture.hoverRegionTree()
    tree.commit(try NodeStore().staging(TreeFixture.frame(operations)).tree)
    let first = try #require(tree.root?.hoverController)
    first.setCollecting(true)
    tree.hoverRouter.setPresented(true)
    let host = NSHostingView(
      rootView: NativeNodeView(node: try #require(tree.root), activate: { _ in }))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 240, height: 120),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.orderFront(nil)
    defer {
      tree.hoverRouter.reset()
      tree.commit(NodeStore())
      window.close()
    }
    func settle() async throws {
      for _ in 0..<10 {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
      }
    }
    func enter(_ view: AppKitHoverCapture) throws {
      let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
      let event = try #require(
        NSEvent.enterExitEvent(
          with: .mouseEntered, location: point,
          modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
          windowNumber: window.windowNumber, context: nil, eventNumber: 1, trackingNumber: 0,
          userData: nil))
      view.mouseEntered(with: event)
    }
    try await settle()
    #expect(first.view.window === window)
    try enter(first.view)
    #expect(events == [RenderIdentity(epoch: 7, node: 1)])
    let retired = try #require(first.view.onSample)
    tree.hoverRouter.discardSamples()
    tree.commit(try NodeStore().staging(TreeFixture.frame(operations, epoch: 8)).tree)
    let second = try #require(tree.root?.hoverController)
    second.setCollecting(true)
    host.rootView = NativeNodeView(node: try #require(tree.root), activate: { _ in })
    tree.hoverRouter.setPresented(true)
    try await settle()
    #expect(first.view.window == nil)
    #expect(second.view.window === window)
    retired(
      NativePointer(
        id: 0, localX: 1, localY: 1, globalX: 1, globalY: 1,
        kind: .mouse, buttons: 0), true)
    #expect(events.count == 1)
    try enter(second.view)
    #expect(events == [RenderIdentity(epoch: 7, node: 1), RenderIdentity(epoch: 8, node: 1)])
    #expect(second.view.bounds.size == first.view.bounds.size)
  }

  @Test func hoverDoesNotChangeContentLayoutAndRejectsMalformedFramesAtomically() throws {
    let store = try NodeStore().staging(TreeFixture.frame(TreeFixture.hoverRegionTree())).tree
    let tree = RenderTree()
    tree.commit(store)
    let actual = try raster(NativeNodeView(node: #require(tree.root), activate: { _ in }))
    let expected = try raster(Text("Hover target").font(.system(size: 17)))
    // ImageRenderer paints a placeholder for embedded NSViews; only geometry is comparable here.
    #expect(actual.width == expected.width && actual.height == expected.height)
    let update = TreeFixture.hoverRegion(blocks: 0, update: true)
    var invalid = [
      TreeFixture.hoverRegion(blocks: 2, update: true), TreeFixture.children(1, []),
      TreeFixture.children(1, [2, 2]),
    ]
    for length in 0..<update.body.count {
      invalid.append(WireOperation(opcode: update.opcode, body: update.body.prefix(length)))
    }
    invalid.append(WireOperation(opcode: update.opcode, body: update.body + Data([0])))
    for operation in invalid {
      #expect(throws: (any Error).self) {
        try store.staging(
          TreeFixture.frame(
            [TreeFixture.text(2, "Do not publish", update: true), operation], base: 1, revision: 2))
      }
      #expect(store.revision == 1)
    }
    for tags in [[], [5], [5, 5], [5, 6, 7], [1, 6]] {
      #expect(throws: (any Error).self) {
        try NodeStore().staging(
          TreeFixture.frame(TreeFixture.hoverRegionTree(TreeFixture.hoverRegion(tags: tags))))
      }
    }
  }
}

extension NativeRuntimeTests {
  @MainActor @Test func actualGalleryHoverFencesPresentationAndRetainsContent() async throws {
    let session = BonsaiSession()
    session.isVisible = true
    func named(_ text: String, _ node: RenderNodeState) -> Bool {
      if case .text(let value) = node.properties, value.value == text { return true }
      return node.children.contains { named(text, $0) }
    }
    func button(_ title: String) throws -> RenderNodeState {
      try #require(
        session.tree.nodes.values.first {
          if case .button = $0.properties { return named(title, $0) }
          return false
        })
    }
    func press(_ title: String) async throws {
      #expect(session.activate(try button(title)))
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
    }
    let pointer = NativePointer(
      id: 0, localX: 10, localY: 20, globalX: 50, globalY: 60, kind: .mouse, buttons: 3)
    do {
      try await session.start(entrypoint: "native-hover")
      let front = try #require(
        session.tree.nodes.values.first {
          $0.kind == 52 && named("Front hover", $0) && $0.children.first?.kind != 52
            && $0.children.count == 1 && !named("Inner action", $0)
        })
      let action = try button("Inner action")
      #expect(!front.emit(.pointerEnter(pointer)))
      #expect(try await session.presented(#require(session.ticket)))
      #expect(front.emit(.pointerEnter(pointer)))
      #expect(!front.emit(.pointerDown(pointer)))
      _ = try await session.refresh()
      #expect(!front.emit(.pointerLeave(pointer)))
      #expect(try await session.presented(#require(session.ticket)))
      #expect(named("Hover events: 1", try #require(session.tree.root)))
      try await press("Inner action")
      #expect(try button("Inner action") === action)
      let previousBinding = front.bindings
      try await press("Replace hover handlers")
      #expect(front.bindings != previousBinding)
      #expect(front.emit(.pointerLeave(pointer)))
      _ = try await session.refresh()
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
      session.isActive = false
      #expect(!front.emit(.pointerEnter(pointer)))
      session.isActive = true
      try await press("Hide front hover")
      #expect(!front.emit(.pointerEnter(pointer)))
      await session.close()
      #expect(!front.emit(.pointerEnter(pointer)))
    } catch {
      await session.close()
      throw error
    }
  }
}
