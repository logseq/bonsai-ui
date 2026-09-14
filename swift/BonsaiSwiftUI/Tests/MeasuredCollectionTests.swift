import AppKit
import SwiftUI
import Testing

@testable import BonsaiSwiftUI

@MainActor @Observable private final class MeasuredHostSettings {
  var width = 320.0
  var fontSize = 14.0
  var dynamicType = DynamicTypeSize.large
}

@MainActor private struct MeasuredHost: View {
  let root: RenderNodeState
  let settings: MeasuredHostSettings
  var body: some View {
    NativeNodeView(node: root, activate: { _ in })
      .font(.system(size: settings.fontSize))
      .dynamicTypeSize(settings.dynamicType)
      .frame(width: settings.width, height: 300)
  }
}

@MainActor struct MeasuredCollectionTests {
  @Test func nativeMeasurementsInvalidateAndPreserveTheVisibleKey() async throws {
    initializeAccessibilityApplication()
    let keys = (0..<10000).map(String.init)
    let visibleKeys = Array(keys[4998..<5005])
    let text = String(repeating: "Native text wraps with available width. ", count: 8)
    let children = (3...9).map(UInt64.init)
    let operations =
      [
        TreeFixture.collection(keys: keys, initial: 2, initialKey: "5000", measurementRevision: 0),
        TreeFixture.collectionWindow(first: 4998, keys: visibleKeys),
      ] + children.map { TreeFixture.text($0, text) } + [
        TreeFixture.children(2, children), TreeFixture.children(1, [2]), TreeFixture.root(1),
      ]
    var store = try NodeStore().staging(TreeFixture.frame(operations)).tree
    let tree = RenderTree()
    tree.commit(store)
    let root = try #require(tree.root)
    let controller = try #require(root.collectionController)
    let anchorRow = try #require(tree.nodes[5])
    let settings = MeasuredHostSettings()
    let host = NSHostingView(rootView: MeasuredHost(root: root, settings: settings))
    host.sizingOptions = []
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 320, height: 300),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    defer { window.contentView = nil }
    func settle() async throws {
      for _ in 0..<20 {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(15))
      }
    }
    func expectAnchor() throws {
      let geometry = controller.viewport.geometry
      let anchor = try #require(geometry.anchor(at: controller.viewport.leadingOffset))
      #expect(controller.catalog.keys[anchor.index] == Data("5000".utf8))
      #expect(anchor.offset < 1)
      #expect(tree.nodes[5] === anchorRow)
      #expect(tree.nodes.count == 9)
      func nativeScroll(_ view: NSView) -> NSScrollView? {
        (view as? NSScrollView) ?? view.subviews.lazy.compactMap(nativeScroll).first
      }
      let native = try #require(nativeScroll(host))
      #expect(abs(native.documentVisibleRect.minY - geometry.offset(at: 5000)) < 1)
    }
    try await settle()
    let initialHeight = controller.viewport.geometry.extent(at: 5000)
    #expect(initialHeight > 40)
    #expect(controller.viewport.geometry.extent(at: 0) == 40)
    try expectAnchor()
    settings.width = 180
    window.setContentSize(CGSize(width: 180, height: 300))
    try await settle()
    let narrowHeight = controller.viewport.geometry.extent(at: 5000)
    #expect(narrowHeight > initialHeight)
    try expectAnchor()
    // macOS test hosts supply the larger font explicitly; the category change
    // also exercises cache invalidation needed by native iOS Dynamic Type.
    settings.fontSize = 26
    settings.dynamicType = .accessibility3
    try await settle()
    #expect(controller.viewport.geometry.extent(at: 5000) > narrowHeight)
    try expectAnchor()
    let updated =
      [
        TreeFixture.collection(
          keys: keys, initial: 2, initialKey: "5000",
          measurementRevision: 1, update: true)
      ] + children.map { TreeFixture.text($0, "Short", update: true) }
    store = try store.staging(
      TreeFixture.frame(
        updated, base: store.revision,
        revision: store.revision + 1)
    ).tree
    tree.commit(store)
    try await settle()
    let shortHeight = Double(try raster(Text("Short").font(.system(size: 26))).height) - 16
    #expect(abs(controller.viewport.geometry.extent(at: 5000) - shortHeight) < 1)
    try expectAnchor()
    // Declared sizes remain a distinct contract, even for intrinsically short rows.
    store = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.collection(
            keys: keys, extent: 80, initial: 2, initialKey: "5000", update: true)
        ], base: store.revision, revision: store.revision + 1)
    ).tree
    tree.commit(store)
    try await settle()
    #expect(controller.viewport.geometry.extent(at: 5000) == 80)
    try expectAnchor()
  }

  @Test func invalidMeasurementRevisionsAndRetiredMasksRejectAtomically() throws {
    let initial = TreeFixture.frame([
      TreeFixture.collection(measurementRevision: 0),
      TreeFixture.collectionWindow(first: 0, keys: []),
      TreeFixture.children(1, [2]), TreeFixture.root(1),
    ])
    let state = try NodeStore().staging(initial).tree
    var retired = TreeFixture.collection(measurementRevision: 1, update: true).body
    retired.replaceSubrange(10..<18, with: [255, 1, 0, 0, 0, 0, 0, 0])
    for operation in [
      TreeFixture.collection(measurementRevision: -1, update: true),
      WireOperation(opcode: OperationId.updateProps, body: retired),
    ] {
      #expect(throws: (any Error).self) {
        try state.staging(TreeFixture.frame([operation], base: 1, revision: 2))
      }
      #expect(state.revision == 1)
    }
  }
}

extension NativeRuntimeTests {
  @Test(arguments: [false, true], [false, true]) @MainActor
  func actualMeasuredGalleryRetainsNativeAnchorAndBoundsOcamlRows(
    horizontal: Bool, rightToLeft: Bool
  ) async throws {
    let session = BonsaiSession()
    session.isVisible = true
    do {
      try await session.start(
        entrypoint: horizontal ? "native-measured-horizontal" : "native-measured")
      let owner = try #require(session.tree.nodes.values.first { $0.kind == 7 })
      let controller = try #require(owner.collectionController)
      #expect(controller.catalog.measurementRevision == 0)
      let host = NSHostingView(
        rootView: NativeNodeView(
          node: try #require(session.tree.root), activate: { session.activate($0) }
        ).environment(\.layoutDirection, rightToLeft ? .rightToLeft : .leftToRight))
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 660, height: 660),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.contentView = host
      defer { window.contentView = nil }
      func settle() async throws {
        for _ in 0..<12 {
          host.layoutSubtreeIfNeeded()
          try await Task.sleep(for: .milliseconds(15))
          if let ticket = session.ticket { _ = try await session.presented(ticket) }
          _ = try await session.refresh()
        }
      }
      func nativeScroll(_ view: NSView) -> NSScrollView? {
        (view as? NSScrollView) ?? view.subviews.lazy.compactMap(nativeScroll).first
      }
      try await settle()
      let native = try #require(nativeScroll(host))
      let estimate = horizontal ? 120.0 : 40.0
      #expect(controller.viewport.geometry.extent(at: 0) != estimate)
      #expect(controller.viewport.geometry.extent(at: 9999) == estimate)
      let target = controller.viewport.geometry.offset(at: 5000)
      if horizontal {
        controller.viewport.position.scrollTo(x: target)
      } else {
        controller.viewport.position.scrollTo(y: target)
      }
      try await settle()
      let key = controller.catalog.keys[5000]
      let rowWindow = try #require(owner.children.first)
      guard case .collectionWindow(let loaded) = rowWindow.properties else {
        Issue.record("Missing materialized collection window")
        await session.close()
        return
      }
      let row = rowWindow.children[try #require(loaded.keys.firstIndex(of: key))]
      func expectAnchor() throws {
        let index = try #require(controller.catalog.indices[key])
        let rect = native.documentVisibleRect
        let actual =
          horizontal
          ? (rightToLeft ? (native.documentView?.frame.width ?? 0) - rect.maxX : rect.minX)
          : rect.minY
        #expect(abs(actual - controller.viewport.geometry.offset(at: index)) < 1)
        #expect(session.tree.nodes.values.contains { $0 === row })
        #expect(rowWindow.children.count <= 50)
        #expect(controller.viewport.geometry.extent(at: index) != estimate)
      }
      try expectAnchor()
      let remove = try #require(
        session.tree.nodes.values.first {
          guard $0.kind == NodeKindId.button, let child = $0.children.first,
            case .text(let text) = child.properties
          else { return false }
          return text.value == "Remove first row"
        })
      #expect(session.activate(remove))
      try await settle()
      #expect(controller.catalog.keys.count == 9999)
      #expect(controller.catalog.indices[key] == 4999)
      try expectAnchor()
      await session.close()
    } catch {
      await session.close()
      throw error
    }
  }
}

extension MeasuredCollectionTests {
  @Test func measurementCacheUsesKeysAndRejectsStaleOrUnrepresentableSizes() throws {
    func catalog(_ names: [String], overrides: [CollectionExtent] = []) throws
      -> RenderCollectionCatalog
    {
      let keys = names.map { Data($0.utf8) }
      return try RenderCollectionCatalog(
        keys: keys,
        indices: Dictionary(
          uniqueKeysWithValues: keys.enumerated().map { ($0.element, $0.offset) }),
        geometry: CollectionGeometry(count: keys.count, defaultExtent: 40, overrides: overrides),
        overscan: 4, timing: .immediate, vertical: true, measurementRevision: 0)
    }
    let cache = CollectionMeasurements()
    let initial = try catalog(["a", "b", "c"])
    func context(_ width: Double) -> CollectionMeasurementContext {
      CollectionMeasurementContext(
        vertical: true, revision: 0, crossExtent: width,
        dynamicType: .large, direction: .leftToRight, fontFamily: nil)
    }
    #expect(cache.configure(context(320)))
    #expect(!cache.configure(context(320)))
    let generation = cache.generation
    let key = Data("b".utf8)
    #expect(cache.accept(90, key: key, generation: generation, catalog: initial))
    let reordered = try catalog(["c", "a", "b", "d"])
    cache.reconcile(from: initial, to: reordered)
    #expect(cache.geometry(for: reordered).extent(at: 2) == 90)
    #expect(!cache.accept(100, key: key, generation: generation, catalog: reordered))
    for invalid in [0, -1, Double.nan, Double.infinity, 9_007_199_254_740_992] {
      #expect(!cache.accept(invalid, key: key, generation: cache.generation, catalog: reordered))
    }
    #expect(cache.configure(context(180)))
    #expect(cache.geometry(for: reordered).extent(at: 2) == 40)
    #expect(cache.accept(3e15, key: key, generation: cache.generation, catalog: reordered))
    let changed = try catalog(
      ["c", "a", "b", "d"], overrides: [CollectionExtent(index: 0, extent: 6.1e15)])
    cache.reconcile(from: reordered, to: changed)
    let beforeInvalidation = cache.generation
    #expect(cache.geometry(for: changed) == changed.geometry)
    #expect(cache.generation != beforeInvalidation)
    #expect(!cache.accept(90, key: key, generation: beforeInvalidation, catalog: changed))
  }
}
