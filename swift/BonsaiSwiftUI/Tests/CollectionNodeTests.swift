import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

extension TreeFixture {
  static func collection(
    _ id: UInt64 = 1, keys: [String] = ["a", "b", "c"],
    extent: Double = 40, overrides: [(UInt32, Double)] = [], overscan: UInt32 = 4,
    expandMilliseconds: UInt32 = 0, collapseMilliseconds: UInt32 = 0,
    vertical: UInt8 = 1, initial: UInt8 = 0, initialKey: String? = nil,
    measurementRevision: Int64? = nil, update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(7))
      if update { $0.integer(UInt64(1023)) }
      $0.integer(UInt32(keys.count))
      for key in keys { try! $0.string(key) }
      $0.integer(extent.bitPattern)
      $0.integer(UInt32(overrides.count))
      for (index, extent) in overrides {
        $0.integer(index)
        $0.integer(extent.bitPattern)
      }
      $0.integer(overscan)
      $0.integer(expandMilliseconds)
      $0.integer(collapseMilliseconds)
      $0.integer(vertical)
      $0.integer(initial)
      $0.integer(UInt8(initialKey == nil ? 0 : 1))
      if let initialKey { try! $0.string(initialKey) }
      $0.integer(UInt8(measurementRevision == nil ? 0 : 1))
      if let measurementRevision { $0.integer(measurementRevision) }
      if !update {
        $0.integer(UInt16(1))
        $0.integer(UInt16(14))
        $0.integer(UInt64(20))
      }
    }
  }
  static func collectionWindow(
    _ id: UInt64 = 2, first: UInt32 = 1,
    keys: [String] = ["b", "c"], update: Bool = false
  ) -> WireOperation {
    operation(update ? OperationId.updateProps : OperationId.createNode) {
      $0.integer(id)
      $0.integer(UInt16(8))
      if update { $0.integer(UInt64(3)) }
      $0.integer(first)
      $0.integer(UInt32(keys.count))
      for key in keys { try! $0.string(key) }
      if !update { $0.integer(UInt16(0)) }
    }
  }
}

struct CollectionNodeTests {
  @Test @MainActor func changingAxisRetainsLogicalAnchorAndRejectsRetiredMasks() throws {
    let keys = (0..<50).map(String.init)
    let initial = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.collection(keys: keys), TreeFixture.collectionWindow(first: 0, keys: []),
        TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    let tree = RenderTree()
    tree.commit(initial)
    let root = try #require(tree.root)
    let controller = try #require(root.collectionController)
    let viewport = controller.viewport
    viewport.observe(CGRect(x: 0, y: 407, width: 100, height: 200))
    var oldBody = TreeFixture.collection(keys: keys, update: true).body
    oldBody.replaceSubrange(10..<18, with: [63, 0, 0, 0, 0, 0, 0, 0])
    #expect(throws: (any Error).self) {
      try initial.staging(
        TreeFixture.frame(
          [
            WireOperation(opcode: OperationId.updateProps, body: oldBody)
          ], base: 1, revision: 2))
    }
    let next = try initial.staging(
      TreeFixture.frame(
        [
          TreeFixture.collection(keys: keys, vertical: 0, update: true)
        ], base: 1, revision: 2)
    ).tree
    tree.commit(next)
    #expect(tree.root === root && root.collectionController === controller)
    #expect(controller.viewport === viewport && !viewport.vertical)
    #expect(viewport.leadingOffset == 407 && viewport.visibleRange == 10..<13)
    let restored = try next.staging(
      TreeFixture.frame(
        [
          TreeFixture.collection(keys: keys, vertical: 1, update: true)
        ], base: 2, revision: 3)
    ).tree
    tree.commit(restored)
    #expect(viewport.vertical && viewport.leadingOffset == 407)
    #expect(viewport.visibleRange == 10..<16)
  }

  @Test @MainActor func evictingVisibleContentRequestsTheUnfilledWindowAgain() async throws {
    let model = RenderTree()
    let initial = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.collection(), TreeFixture.collectionWindow(first: 0, keys: ["a", "b", "c"]),
        TreeFixture.text(3, "A"), TreeFixture.text(4, "B"), TreeFixture.text(5, "C"),
        TreeFixture.children(1, [2]), TreeFixture.children(2, [3, 4, 5]), TreeFixture.root(1),
      ])
    ).tree
    model.commit(initial)
    let root = try #require(model.root)
    let hosting = NSHostingView(rootView: NativeNodeView(node: root, activate: { _ in }))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 40), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView = hosting
    defer {
      window.contentView = nil
      model.commit(NodeStore())
    }
    try await settleCollection(hosting)
    let controller = try #require(root.collectionController)
    let request = try #require(controller.request(handler: 20))
    controller.accepted(request, handler: 20)
    #expect(controller.request(handler: 20) == nil)
    let next = try initial.staging(
      TreeFixture.frame(
        [
          TreeFixture.collectionWindow(first: 0, keys: [], update: true),
          TreeFixture.children(2, []),
          TreeFixture.operation(OperationId.dropNode) { $0.integer(UInt64(3)) },
          TreeFixture.operation(OperationId.dropNode) { $0.integer(UInt64(4)) },
          TreeFixture.operation(OperationId.dropNode) { $0.integer(UInt64(5)) },
        ], base: 1, revision: 2)
    ).tree
    model.commit(next)
    try await settleCollection(hosting)
    #expect(controller.request(handler: 20) == request)
  }

  @Test func catalogAndWindowValidateAtomicallyWithExactKeyIdentity() throws {
    let initial = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.collection(), TreeFixture.collectionWindow(), TreeFixture.text(3, "B"),
        TreeFixture.text(4, "C"),
        TreeFixture.children(1, [2]), TreeFixture.children(2, [3, 4]), TreeFixture.root(1),
      ])
    ).tree
    for invalid in [
      TreeFixture.collection(keys: ["a", "a", "c"], update: true),
      TreeFixture.collection(keys: ["a", "", "c"], update: true),
      TreeFixture.collection(vertical: 2, update: true),
      TreeFixture.collection(extent: 0, update: true),
      TreeFixture.collection(extent: .infinity, update: true),
      TreeFixture.collection(overrides: [(3, 80)], update: true),
      TreeFixture.collection(overrides: [(2, 80), (1, 40)], update: true),
      TreeFixture.collectionWindow(first: 2, update: true),
      TreeFixture.collectionWindow(keys: ["a", "c"], update: true),
      TreeFixture.children(2, [3]),
    ] {
      #expect(throws: (any Error).self) {
        try initial.staging(TreeFixture.frame([invalid], base: 1, revision: 2))
      }
      #expect(initial.revision == 1)
    }
    for update in [
      TreeFixture.collectionWindow(update: true),
      TreeFixture.collection(expandMilliseconds: 240, collapseMilliseconds: 190, update: true),
    ] {
      for length in 0..<update.body.count {
        let invalid = WireOperation(opcode: update.opcode, body: update.body.prefix(length))
        #expect(throws: (any Error).self) {
          try initial.staging(TreeFixture.frame([invalid], base: 1, revision: 2))
        }
      }
    }
    #expect(throws: (any Error).self) {
      try NodeStore().staging(
        TreeFixture.frame([TreeFixture.collectionWindow(first: 0, keys: []), TreeFixture.root(2)]))
    }
    _ = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.collection(keys: ["é", "e\u{301}"]),
        TreeFixture.collectionWindow(first: 0, keys: ["é", "e\u{301}"]),
        TreeFixture.text(3, "A"), TreeFixture.text(4, "B"), TreeFixture.children(1, [2]),
        TreeFixture.children(2, [3, 4]), TreeFixture.root(1),
      ]))
  }
}

@MainActor private func collectionScroll(_ root: NSView) -> NSScrollView? {
  if let view = root as? NSScrollView { return view }
  return root.subviews.lazy.compactMap { collectionScroll($0) }.first
}
@MainActor private func settleCollection(_ hosting: NSView) async throws {
  for _ in 0..<10 {
    hosting.layoutSubtreeIfNeeded()
    hosting.displayIfNeeded()
    try await Task.sleep(for: .milliseconds(10))
  }
}

extension NativeRuntimeTests {
  @Test func scrollingPublishesOnlyTheWindowWithoutRepeatingTheCatalog() async throws {
    let runtime = try await NativeRuntime.open(entrypoint: "native-collection")
    do {
      let initial = try await runtime.pump(monotonicNanoseconds: 1)
      let frame = try WireFrame.decode(initial.bytes)
      var owner: UInt64 = 0
      var handler: UInt64 = 0
      for operation in frame.operations where operation.opcode == OperationId.createNode {
        var reader = WireReader(operation.body)
        let id = try reader.integer(UInt64.self)
        if try reader.integer(UInt16.self) == 7 {
          owner = id
          var bindings = WireReader(operation.body.suffix(12))
          handler = try #require(bindings.bindings()[EventTagId.visibleRangeChanged])
        }
      }
      #expect(owner > 0 && initial.bytes.count > 50000)
      try await runtime.acknowledge(initial, monotonicNanoseconds: 2)
      let event = NativeEvent(
        sequence: 1, displayedRevision: frame.revision, nodeID: owner,
        handlerID: handler, payload: .visibleRange(7500..<7515))
      let next = try await runtime.pump(
        monotonicNanoseconds: 3,
        events: EventBatch.encode(epoch: frame.epoch, events: [event]))
      var kinds: [UInt16] = []
      for operation in try WireFrame.decode(next.bytes).operations
      where operation.opcode == OperationId.createNode
        || operation.opcode == OperationId.updateProps
      {
        var reader = WireReader(operation.body)
        _ = try reader.integer(UInt64.self)
        kinds.append(try reader.integer(UInt16.self))
      }
      #expect(!kinds.contains(7) && kinds.contains(8) && next.bytes.count < 16384)
      try await runtime.acknowledge(next, monotonicNanoseconds: 4)
      await runtime.close()
    } catch {
      await runtime.close()
      throw error
    }
  }

  @Test(arguments: [false, true], [false, true]) @MainActor
  func actualGalleryExtentTargetsAnimateWithoutAdditionalOcamlFrames(
    horizontal: Bool, rightToLeft: Bool
  ) async throws {
    let compact: Double = horizontal ? 120 : 40
    let expanded: Double = horizontal ? 400 : 200
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(
        entrypoint: horizontal ? "native-collection-horizontal" : "native-collection")
      let owner = try #require(session.tree.nodes.values.first { $0.kind == 7 })
      let controller = try #require(owner.collectionController)
      let hosting = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }
        )
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
      let window = NSWindow(
        contentRect: NSRect(
          x: 0, y: 0, width: horizontal ? 660 : 420, height: horizontal ? 460 : 700),
        styleMask: [.borderless],
        backing: .buffered, defer: false)
      window.contentView = hosting
      defer { window.contentView = nil }
      try await settleCollection(hosting)
      #expect(try await session.presented(#require(session.ticket)))
      #expect(try await session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      let button = try #require(
        session.tree.nodes.values.first {
          guard $0.kind == NodeKindId.button, let child = $0.children.first,
            case .text(let text) = child.properties
          else { return false }
          return text.value == "Toggle row 10 expansion"
        })
      #expect(session.activate(button))
      #expect(try await session.refresh())
      let ticket = try #require(session.ticket)
      #expect(controller.catalog.geometry.extent(at: 10) == expanded)
      #expect(controller.viewport.geometry.extent(at: 10) < expanded)
      try await settleCollection(hosting)
      #expect(controller.viewport.geometry.extent(at: 10) > compact)
      #expect(controller.viewport.geometry.extent(at: 10) < expanded)
      #expect(session.ticket == ticket)
      try await Task.sleep(for: .milliseconds(250))
      try await settleCollection(hosting)
      #expect(controller.viewport.geometry.extent(at: 10) == expanded)
      #expect(session.ticket == ticket)
      #expect(try await session.presented(ticket))
      #expect(session.activate(button))
      #expect(try await session.refresh())
      #expect(controller.catalog.geometry.extent(at: 10) == compact)
      #expect(controller.viewport.geometry.extent(at: 10) > compact)
      session.isActive = false
      #expect(controller.viewport.geometry.extent(at: 10) == compact)
      session.isActive = true
      #expect(try await session.presented(#require(session.ticket)))
      #expect(session.activate(button))
      #expect(try await session.refresh())
      #expect(controller.viewport.geometry.extent(at: 10) < expanded)
      session.isVisible = false
      #expect(controller.viewport.geometry.extent(at: 10) == expanded)
      await session.close()
      #expect(controller.viewport.geometry.extent(at: 10) == expanded)
    } catch {
      await session.close()
      throw error
    }
  }

  @Test(arguments: [false, true], [false, true]) @MainActor
  func publicCollectionMountsAndSamplesWindowRequestsAfterPresentation(
    horizontal: Bool, rightToLeft: Bool
  )
    async throws
  {
    let extent: Double = horizontal ? 120 : 40
    let visible = horizontal ? 5 : 15
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(
        entrypoint: horizontal ? "native-collection-horizontal" : "native-collection")
      let collection = try #require(session.tree.nodes.values.first { $0.kind == 7 })
      let windowNode = try #require(collection.children.first)
      #expect(windowNode.children.isEmpty)
      let hosting = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }
        )
        .environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
      let nativeWindow = NSWindow(
        contentRect: NSRect(
          x: 0, y: 0, width: horizontal ? 660 : 420, height: horizontal ? 460 : 660),
        styleMask: [.borderless],
        backing: .buffered, defer: false)
      nativeWindow.contentView = hosting
      defer { nativeWindow.contentView = nil }
      try await settleCollection(hosting)
      let scroll = try #require(collectionScroll(hosting))
      let document = try #require(scroll.documentView)
      #expect(abs((horizontal ? document.frame.width : document.frame.height) - 10000 * extent) < 1)
      func move(_ offset: Double) {
        let x =
          rightToLeft ? document.frame.width - scroll.contentView.bounds.width - offset : offset
        scroll.contentView.scroll(to: horizontal ? CGPoint(x: x, y: 0) : CGPoint(x: 0, y: offset))
        scroll.reflectScrolledClipView(scroll.contentView)
      }
      func offset() -> Double {
        let rect = scroll.documentVisibleRect
        return horizontal ? (rightToLeft ? document.frame.width - rect.maxX : rect.minX) : rect.minY
      }
      #expect(try await !session.refresh())
      #expect(try await session.presented(#require(session.ticket)))
      #expect(try await session.refresh())
      if let ticket = session.ticket { #expect(try await session.presented(ticket)) }
      #expect(windowNode.children.count == visible + 4)
      let originalRow = windowNode.children[1]
      move(7500 * extent)
      try await settleCollection(hosting)
      #expect(try await session.refresh())
      #expect(collection.children.first === windowNode && windowNode.children.count == visible + 8)
      #expect(session.tree.nodes[originalRow.id.node] == nil)
      let anchored = windowNode.children[4]
      #expect(try await session.presented(#require(session.ticket)))
      let button = try #require(
        session.tree.nodes.values.first {
          guard $0.kind == NodeKindId.button, let child = $0.children.first,
            case .text(let text) = child.properties
          else { return false }
          return text.value == "Remove first row"
        })
      #expect(session.activate(button))
      #expect(try await session.refresh())
      try await settleCollection(hosting)
      #expect(abs(offset() - 7499 * extent) < 1)
      #expect(windowNode.children.contains { $0 === anchored })
      #expect(try await session.presented(#require(session.ticket)))
      if try await session.refresh(), let ticket = session.ticket {
        #expect(try await session.presented(ticket))
      }
      move(0)
      try await settleCollection(hosting)
      #expect(try await session.refresh())
      #expect(windowNode.children.count == visible + 4 && windowNode.children[0] !== originalRow)
      await session.close()
      #expect(session.tree.nodes.isEmpty)
    } catch {
      await session.close()
      throw error
    }
  }
}
