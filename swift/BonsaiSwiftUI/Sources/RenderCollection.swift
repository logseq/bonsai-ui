import Foundation
import SwiftUI

struct RenderCollectionCatalog: Equatable, Sendable {
  let keys: [Data]
  let indices: [Data: Int]
  let geometry: CollectionGeometry
  let overscan: Int
  let timing: CollectionTiming
  let vertical: Bool
  var initialAnchor: Int = 0
  var initialKey: Data? = nil
  var measurementRevision: Int64? = nil

  static func readKeys(_ reader: inout WireReader) throws -> [Data] {
    let count = Int(try reader.integer(UInt32.self))
    guard count <= ProtocolLimits.maxNodes, count <= reader.remaining / 4 else {
      throw WireError.limitExceeded
    }
    var seen: Set<Data> = []
    var keys: [Data] = []
    for _ in 0..<count {
      let key = Data(try reader.string().utf8)
      guard !key.isEmpty, seen.insert(key).inserted else { throw CollectionError.invalidMetrics }
      keys.append(key)
    }
    return keys
  }
  static func decode(_ reader: inout WireReader) throws -> Self {
    let keys = try readKeys(&reader)
    let extent = try reader.finiteDouble()
    let count = Int(try reader.integer(UInt32.self))
    guard count <= keys.count else { throw CollectionError.invalidMetrics }
    var extents: [CollectionExtent] = []
    for _ in 0..<count {
      extents.append(
        CollectionExtent(
          index: Int(try reader.integer(UInt32.self)), extent: try reader.finiteDouble()))
    }
    let overscan = Int(try reader.integer(UInt32.self))
    let timing = try CollectionTiming(
      expandMilliseconds: reader.integer(UInt32.self),
      collapseMilliseconds: reader.integer(UInt32.self))
    let vertical = try reader.flag()
    let initialAnchor = try reader.choice(2)
    let initialKey = try reader.flag() ? Data(reader.string().utf8) : nil
    let measurementRevision =
      try reader.flag() ? Int64(bitPattern: reader.integer(UInt64.self)) : nil
    guard measurementRevision.map({ $0 >= 0 }) ?? true else { throw CollectionError.invalidMetrics }
    guard initialAnchor == 2 ? initialKey.map(keys.contains) == true : initialKey == nil
    else { throw CollectionError.invalidMetrics }
    return try Self(
      keys: keys,
      indices: Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($0.element, $0.offset) }),
      geometry: CollectionGeometry(count: keys.count, defaultExtent: extent, overrides: extents),
      overscan: overscan, timing: timing, vertical: vertical,
      initialAnchor: initialAnchor, initialKey: initialKey, measurementRevision: measurementRevision
    )
  }
}

struct RenderCollectionWindow: Equatable, Sendable {
  let firstIndex: Int
  let keys: [Data]
  static func decode(_ reader: inout WireReader) throws -> Self {
    let first = Int(try reader.integer(UInt32.self))
    return try Self(firstIndex: first, keys: RenderCollectionCatalog.readKeys(&reader))
  }
}

@MainActor final class CollectionController {
  let viewport: CollectionViewport
  let measurements = CollectionMeasurements()
  private(set) var catalog: RenderCollectionCatalog
  private var lastRequest: (handler: UInt64, range: Range<Int>)?
  private var window: RenderCollectionWindow?
  private var active = true
  private var rows: [Data: RenderIdentity] = [:]
  private var attachments: [Data: CollectionMeasurementToken] = [:]
  private var pendingMeasurements: [Data: (extent: Double, token: CollectionMeasurementToken)] = [:]
  private var measurementTask: Task<Void, Never>?
  private var measuredMounts: Set<UUID> = []

  init(_ catalog: RenderCollectionCatalog) {
    self.catalog = catalog
    // Catalog decoding has already validated these values.
    let initialOffset: Double
    switch catalog.initialAnchor {
    case 1: initialOffset = catalog.geometry.totalExtent
    case 2: initialOffset = catalog.geometry.offset(at: catalog.indices[catalog.initialKey!]!)
    case 0: initialOffset = 0
    default: preconditionFailure("Invalid decoded initial collection position")
    }
    viewport = try! CollectionViewport(
      geometry: catalog.geometry, vertical: catalog.vertical, overscan: catalog.overscan,
      initialOffset: initialOffset)
  }
  func replace(_ next: RenderCollectionCatalog) {
    guard active, next != catalog else { return }
    if next.keys == catalog.keys, next.geometry == catalog.geometry,
      next.overscan == catalog.overscan, next.timing == catalog.timing,
      next.vertical == catalog.vertical
        && next.measurementRevision == catalog.measurementRevision
    {
      catalog = next
      return
    }
    var relocated: Int?
    var offset: Double?
    let sameKeys = catalog.keys == next.keys
    if !sameKeys, let anchor = viewport.geometry.anchor(at: viewport.leadingOffset) {
      relocated = next.indices[catalog.keys[anchor.index]]
      if relocated == nil {
        // If the anchor itself was deleted, prefer its next surviving item.
        for index in anchor.index..<catalog.keys.count {
          if let match = next.indices[catalog.keys[index]] {
            relocated = match
            break
          }
        }
        if relocated == nil {
          for index in stride(from: anchor.index - 1, through: 0, by: -1) {
            if let match = next.indices[catalog.keys[index]] {
              relocated = match
              break
            }
          }
        }
        offset = 0
      }
    }
    measurements.reconcile(from: catalog, to: next)
    viewport.replace(
      measurements.geometry(for: next), relocatedAnchorIndex: relocated,
      relocatedAnchorOffset: offset,
      overscan: next.overscan, timing: sameKeys ? next.timing : .immediate, vertical: next.vertical,
      preserveMeasurementAnchor: catalog.measurementRevision != nil
        || next.measurementRevision != nil)
    catalog = next
    lastRequest = nil
  }
  func request(handler: UInt64) -> Range<Int>? {
    guard active, viewport.isMounted, viewport.visibleRect.width > 0,
      viewport.visibleRect.height > 0
    else { return nil }
    let range = viewport.visibleRange
    if let lastRequest, lastRequest.handler == handler, lastRequest.range == range { return nil }
    return range
  }
  func synchronize(_ window: RenderCollectionWindow, rows: [RenderIdentity]) {
    self.rows = Dictionary(uniqueKeysWithValues: zip(window.keys, rows))
    attachments = attachments.filter { self.rows[$0.key] == $0.value.row }
    measuredMounts.formIntersection(Set(attachments.values.map(\.mount)))
    pendingMeasurements = pendingMeasurements.filter {
      validMeasurement(key: $0.key, token: $0.value.token)
    }
    guard self.window != window else { return }
    self.window = window
    let visible = viewport.visibleRange
    if !visible.isEmpty
      && (window.firstIndex > visible.lowerBound
        || window.firstIndex + window.keys.count < visible.upperBound)
    {
      lastRequest = nil
    }
  }
  func accepted(_ range: Range<Int>, handler: UInt64) { lastRequest = (handler, range) }
  func dispose() {
    active = false
    measurementTask?.cancel()
    measurementTask = nil
    pendingMeasurements.removeAll()
    attachments.removeAll()
    measuredMounts.removeAll()
    rows.removeAll()
    measurements.clear()
    viewport.finishAnimation()
    lastRequest = nil
  }

  func configureMeasurements(_ context: CollectionMeasurementContext) {
    guard active, catalog.measurementRevision != nil,
      measurements.configure(context)
    else { return }
    viewport.replace(
      measurements.geometry(for: catalog), timing: catalog.timing, preserveMeasurementAnchor: true)
  }

  func attachMeasurement(key: Data, token: CollectionMeasurementToken) {
    guard active, rows[key] == token.row, token.context == measurements.contextToken else { return }
    if let previous = attachments[key], previous.mount != token.mount {
      measuredMounts.remove(previous.mount)
    }
    attachments[key] = token
  }

  func detachMeasurement(key: Data, mount: UUID) {
    guard attachments[key]?.mount == mount else { return }
    measuredMounts.remove(mount)
    attachments.removeValue(forKey: key)
    pendingMeasurements.removeValue(forKey: key)
  }

  private func validMeasurement(key: Data, token: CollectionMeasurementToken) -> Bool {
    active && catalog.measurementRevision != nil && rows[key] == token.row
      && attachments[key] == token && token.context == measurements.contextToken
  }

  func measure(_ extent: Double, key: Data, token: CollectionMeasurementToken) {
    guard validMeasurement(key: key, token: token), extent.isFinite, extent > 0,
      extent <= 9_007_199_254_740_992
    else { return }
    // A newer equal sample also withdraws an earlier changed sample in this batch.
    guard measurements.isChanged(extent, key: key, catalog: catalog) else {
      measuredMounts.insert(token.mount)
      pendingMeasurements.removeValue(forKey: key)
      return
    }
    pendingMeasurements[key] = (extent, token)
    guard measurementTask == nil else { return }
    measurementTask = Task { @MainActor [weak self] in
      await Task.yield()
      guard !Task.isCancelled, let self else { return }
      self.flushMeasurements()
    }
  }

  private func flushMeasurements() {
    measurementTask = nil
    let valid = pendingMeasurements.filter {
      validMeasurement(key: $0.key, token: $0.value.token)
    }
    let animatedIndices = Set(
      valid.compactMap { key, sample in
        measuredMounts.contains(sample.token.mount) ? catalog.indices[key] : nil
      })
    measuredMounts.formUnion(valid.values.map { $0.token.mount })
    let samples = valid.mapValues(\.extent)
    pendingMeasurements.removeAll()
    guard
      let geometry = measurements.accept(
        samples, context: measurements.contextToken, catalog: catalog)
    else { return }
    viewport.replace(
      geometry, timing: catalog.timing, preserveMeasurementAnchor: true,
      animatedIndices: animatedIndices)
  }

}

struct NativeCollectionNodeView: View {
  @Environment(\.dynamicTypeSize) private var dynamicType
  @Environment(\.layoutDirection) private var direction
  @Environment(\.bonsaiFontFamily) private var fontFamily
  let node: RenderNodeState
  let controller: CollectionController
  let activate: @MainActor (RenderNodeState) -> Void

  var body: some View {
    let window = node.children[0]
    let dynamicType = dynamicType
    let direction = direction
    let fontFamily = fontFamily
    if case .collection(let catalog) = node.properties,
      case .collectionWindow(let properties) = window.properties
    {
      let vertical = catalog.vertical
      let measurementRevision = catalog.measurementRevision
      WindowedCollectionView(
        viewport: controller.viewport, firstIndex: properties.firstIndex,
        observation: node.scrollObserver, command: node.scrollCommand
      ) {
        ForEach(Array(window.children.enumerated()), id: \.element.id) { index, child in
          measuredChild(
            child, key: properties.keys[index], vertical: vertical,
            measured: measurementRevision != nil
          )
          .frame(
            width: vertical
              ? nil : controller.viewport.geometry.extent(at: properties.firstIndex + index),
            height: vertical
              ? controller.viewport.geometry.extent(at: properties.firstIndex + index) : nil
          )
          .frame(
            maxWidth: vertical ? .infinity : nil,
            maxHeight: vertical ? nil : .infinity
          )
          .clipped()
          .environment(\.collectionCoordinatesExtent, true)
        }
      }
      .onGeometryChange(for: CollectionMeasurementContext.self) { proxy in
        CollectionMeasurementContext(
          vertical: vertical, revision: measurementRevision,
          crossExtent: vertical ? proxy.size.width : proxy.size.height,
          dynamicType: dynamicType, direction: direction, fontFamily: fontFamily)
      } action: {
        controller.configureMeasurements($0)
      }
    }
  }

  @ViewBuilder private func measuredChild(
    _ child: RenderNodeState, key: Data, vertical: Bool, measured: Bool
  ) -> some View {
    if measured {
      MeasuredCollectionRow(
        controller: controller, key: key, identity: child.id,
        vertical: vertical,
        content: NativeNodeView(node: child, activate: activate))
    } else {
      NativeNodeView(node: child, activate: activate)
    }
  }
}
