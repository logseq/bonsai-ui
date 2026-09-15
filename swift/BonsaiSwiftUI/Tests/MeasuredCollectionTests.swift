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

@MainActor @Observable private final class MeasurementMountSettings {
  var visible = true
  var extent = 80.0
  var node: UInt64 = 3
}

@MainActor private struct MeasurementMountHost: View {
  let controller: CollectionController
  let settings: MeasurementMountSettings
  let vertical: Bool

  var body: some View {
    Group {
      if settings.visible {
        MeasuredCollectionRow(
          controller: controller, key: Data("row".utf8),
          identity: RenderIdentity(epoch: 1, node: settings.node), vertical: vertical,
          content: Color.clear.frame(
            width: vertical ? 80 : settings.extent,
            height: vertical ? settings.extent : 80))
      }
    }
    .frame(width: 320, height: 320, alignment: .topLeading)
  }
}

@MainActor struct MeasuredCollectionTests {
  @Test(arguments: [false, true])
  func nativeRowMeasurementsSurviveRemovalReplacementAndContextChanges(vertical: Bool)
    async throws
  {
    initializeAccessibilityApplication()
    let key = Data("row".utf8)
    let catalog = try RenderCollectionCatalog(
      keys: [key], indices: [key: 0],
      geometry: CollectionGeometry(count: 1, defaultExtent: 40), overscan: 4,
      timing: .immediate, vertical: vertical, measurementRevision: 0)
    let controller = CollectionController(catalog)
    let settings = MeasurementMountSettings()
    func synchronize() {
      controller.synchronize(
        RenderCollectionWindow(firstIndex: 0, keys: settings.visible ? [key] : []),
        rows: settings.visible ? [RenderIdentity(epoch: 1, node: settings.node)] : [])
    }
    func configure(_ width: Double) {
      controller.configureMeasurements(
        CollectionMeasurementContext(
          vertical: vertical, revision: 0, crossExtent: width,
          dynamicType: .large, direction: .leftToRight, fontFamily: nil))
    }
    synchronize()
    configure(320)
    let host = NSHostingView(
      rootView: MeasurementMountHost(
        controller: controller, settings: settings, vertical: vertical))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 320, height: 320),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    defer {
      window.contentView = nil
      controller.dispose()
    }
    func settle() async throws {
      for _ in 0..<15 {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(10))
      }
    }
    try await settle()
    #expect(controller.viewport.geometry.extent(at: 0) == 80)
    settings.extent = 110
    try await settle()
    #expect(controller.viewport.geometry.extent(at: 0) == 110)

    settings.visible = false
    synchronize()
    try await settle()
    settings.extent = 140
    settings.node = 4
    configure(240)
    #expect(controller.viewport.geometry.extent(at: 0) == 40)
    settings.visible = true
    synchronize()
    try await settle()
    #expect(controller.viewport.geometry.extent(at: 0) == 140)

    // An unchanged native size must be republished under the new context token.
    configure(180)
    #expect(controller.viewport.geometry.extent(at: 0) == 40)
    try await settle()
    #expect(controller.viewport.geometry.extent(at: 0) == 140)
  }

  @Test func unrelatedCommitsPreserveMeasurementsAndChangedSamplesBatch() async throws {
    var store = try NodeStore().staging(
      TreeFixture.frame([
        TreeFixture.collection(keys: ["a", "b"], measurementRevision: 0),
        TreeFixture.collectionWindow(first: 0, keys: ["a", "b"]),
        TreeFixture.text(3, "A"), TreeFixture.text(4, "B"),
        TreeFixture.children(2, [3, 4]), TreeFixture.children(1, [2]), TreeFixture.root(1),
      ])
    ).tree
    let tree = RenderTree()
    tree.commit(store)
    let controller = try #require(tree.root?.collectionController)
    controller.configureMeasurements(
      CollectionMeasurementContext(
        vertical: true, revision: 0, crossExtent: 320,
        dynamicType: .large, direction: .leftToRight, fontFamily: nil))
    let generation = controller.measurements.contextToken
    store = try store.staging(
      TreeFixture.frame(
        [
          TreeFixture.text(3, "Changed content", update: true)
        ], base: 1, revision: 2)
    ).tree
    tree.commit(store)
    #expect(controller.measurements.contextToken == generation)
    let old = controller.viewport.geometry
    for (key, id, extent) in [("a", UInt64(3), 80.0), ("b", UInt64(4), 90.0)] {
      let token = CollectionMeasurementToken(
        row: try #require(tree.nodes[id]).id, mount: UUID(), context: generation)
      controller.attachMeasurement(key: Data(key.utf8), token: token)
      controller.measure(extent, key: Data(key.utf8), token: token)
    }
    #expect(controller.viewport.geometry == old)
    for _ in 0..<20 { await Task.yield() }
    #expect(controller.viewport.geometry.extent(at: 0) == 80)
    #expect(controller.viewport.geometry.extent(at: 1) == 90)
  }

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
    let generation = cache.contextToken
    let key = Data("b".utf8)
    #expect(cache.accept([key: 90], context: generation, catalog: initial) != nil)
    let reordered = try catalog(["c", "a", "b", "d"])
    cache.reconcile(from: initial, to: reordered)
    #expect(cache.geometry(for: reordered).extent(at: 2) == 90)
    #expect(cache.accept([key: 100], context: generation, catalog: reordered) != nil)
    for invalid in [0, -1, Double.nan, Double.infinity, 9_007_199_254_740_992] {
      #expect(cache.accept([key: invalid], context: cache.contextToken, catalog: reordered) == nil)
    }
    #expect(cache.configure(context(180)))
    #expect(cache.geometry(for: reordered).extent(at: 2) == 40)
    #expect(cache.accept([key: 3e15], context: cache.contextToken, catalog: reordered) != nil)
    let changed = try catalog(
      ["c", "a", "b", "d"], overrides: [CollectionExtent(index: 0, extent: 6.1e15)])
    let beforeInvalidation = cache.contextToken
    cache.reconcile(from: reordered, to: changed)
    #expect(cache.geometry(for: changed) == changed.geometry)
    #expect(cache.contextToken != beforeInvalidation)
    #expect(cache.accept([key: 90], context: beforeInvalidation, catalog: changed) == nil)
  }
}

extension MeasuredCollectionTests {
  @Test func queuedMeasurementsRespectMountContextAndAtomicGeometryValidation() async throws {
    let keys = [Data("a".utf8), Data("b".utf8)]
    let rows = [RenderIdentity(epoch: 1, node: 3), RenderIdentity(epoch: 1, node: 4)]
    let catalog = try RenderCollectionCatalog(
      keys: keys, indices: [keys[0]: 0, keys[1]: 1],
      geometry: CollectionGeometry(count: 2, defaultExtent: 40), overscan: 4,
      timing: .immediate, vertical: true, measurementRevision: 0)
    let controller = CollectionController(catalog)
    controller.synchronize(RenderCollectionWindow(firstIndex: 0, keys: keys), rows: rows)
    func configure(_ width: Double) {
      controller.configureMeasurements(
        CollectionMeasurementContext(
          vertical: true, revision: 0,
          crossExtent: width, dynamicType: .large, direction: .leftToRight, fontFamily: nil))
    }
    func attach(_ index: Int) -> CollectionMeasurementToken {
      let token = CollectionMeasurementToken(
        row: rows[index], mount: UUID(),
        context: controller.measurements.contextToken)
      controller.attachMeasurement(key: keys[index], token: token)
      return token
    }
    func flush() async { for _ in 0..<20 { await Task.yield() } }
    configure(320)
    let original = attach(0)
    controller.measure(80, key: keys[0], token: original)
    controller.detachMeasurement(key: keys[0], mount: original.mount)
    let remounted = attach(0)
    controller.measure(90, key: keys[0], token: original)
    await flush()
    #expect(controller.viewport.geometry == catalog.geometry)
    controller.measure(90, key: keys[0], token: remounted)
    configure(180)
    await flush()
    #expect(controller.viewport.geometry == catalog.geometry)
    let first = attach(0)
    let second = attach(1)
    controller.measure(3e15, key: keys[0], token: first)
    controller.measure(6.1e15, key: keys[1], token: second)
    await flush()
    #expect(controller.viewport.geometry == catalog.geometry)
    controller.measure(80, key: keys[0], token: first)
    controller.measure(90, key: keys[1], token: second)
    await flush()
    #expect(controller.viewport.geometry.totalExtent == 170)
    controller.detachMeasurement(key: keys[0], mount: first.mount)
    #expect(controller.measurements.geometry(for: catalog).extent(at: 0) == 80)
    controller.measure(100, key: keys[1], token: second)
    controller.dispose()
    await flush()
    #expect(controller.viewport.geometry.totalExtent == 170)
  }
}
