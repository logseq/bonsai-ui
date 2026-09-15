import Foundation
import Observation
import SwiftUI

struct CollectionMeasurementContext: Equatable {
  let vertical: Bool
  let revision: Int64?
  let crossExtent: Double
  let dynamicType: DynamicTypeSize
  let direction: LayoutDirection
  let fontFamily: String?
}

struct CollectionMeasurementToken: Equatable {
  let row: RenderIdentity
  let mount: UUID
  let context: UInt64
}

@MainActor @Observable final class CollectionMeasurements {
  private(set) var contextToken: UInt64 = 0
  @ObservationIgnored private var context: CollectionMeasurementContext?
  @ObservationIgnored private var extents: [Data: Double] = [:]

  func clear() {
    extents.removeAll()
    contextToken &+= 1
  }
  func configure(_ value: CollectionMeasurementContext) -> Bool {
    guard value.crossExtent.isFinite, value.crossExtent > 0, context != value else { return false }
    context = value
    clear()
    return true
  }
  func reconcile(from old: RenderCollectionCatalog, to next: RenderCollectionCatalog) {
    if old.measurementRevision != next.measurementRevision || old.vertical != next.vertical {
      context = nil
      clear()
      return
    }
    // A changed declared size invalidates sizing knowledge. Append and reorder
    // alone preserve both cached extents and retained-row callback validity.
    for (key, before) in old.indices {
      if let after = next.indices[key],
        old.geometry.extent(at: before) != next.geometry.extent(at: after)
      {
        clear()
        return
      }
    }
    extents = extents.filter { next.indices[$0.key] != nil }
  }

  private func geometry(_ extents: [Data: Double], catalog: RenderCollectionCatalog) throws
    -> CollectionGeometry
  {
    var overrides = Dictionary(
      uniqueKeysWithValues: catalog.geometry.overrides.map { ($0.index, $0.extent) })
    for (key, extent) in extents {
      if let index = catalog.indices[key] { overrides[index] = extent }
    }
    return try CollectionGeometry(
      count: catalog.keys.count, defaultExtent: catalog.geometry.defaultExtent,
      overrides: overrides.sorted { $0.key < $1.key }.map {
        CollectionExtent(index: $0.key, extent: $0.value)
      })
  }

  func geometry(for catalog: RenderCollectionCatalog) -> CollectionGeometry {
    guard catalog.measurementRevision != nil, !extents.isEmpty else { return catalog.geometry }
    guard let geometry = try? geometry(extents, catalog: catalog) else {
      clear()
      return catalog.geometry
    }
    return geometry
  }

  func isChanged(_ extent: Double, key: Data, catalog: RenderCollectionCatalog) -> Bool {
    guard context != nil, let index = catalog.indices[key], extent.isFinite, extent > 0,
      extent <= 9_007_199_254_740_992
    else { return false }
    return (extents[key] ?? catalog.geometry.extent(at: index)) != extent
  }

  /// Validate once and publish the entire batch atomically.
  func accept(_ samples: [Data: Double], context: UInt64, catalog: RenderCollectionCatalog)
    -> CollectionGeometry?
  {
    guard self.context != nil, context == contextToken else { return nil }
    let changes = samples.filter { isChanged($0.value, key: $0.key, catalog: catalog) }
    guard !changes.isEmpty else { return nil }
    let candidate = extents.merging(changes, uniquingKeysWith: { _, next in next })
    guard let geometry = try? geometry(candidate, catalog: catalog) else { return nil }
    extents = candidate
    return geometry
  }
}

private struct CollectionMeasurementSample: Equatable {
  let token: CollectionMeasurementToken
  let extent: Double
}

struct MeasuredCollectionRow<Content: View>: View {
  let controller: CollectionController
  let key: Data
  let identity: RenderIdentity
  let vertical: Bool
  let content: Content
  // Keep the view value's initial state stable when its parent replaces a row
  // window. A fresh UUID here invalidates retained measurement wrappers too.
  @State private var mount: UUID?
  @State private var latest: CollectionMeasurementSample?

  var body: some View {
    let context = controller.measurements.contextToken
    let token = mount.map {
      CollectionMeasurementToken(row: identity, mount: $0, context: context)
    }
    let vertical = vertical
    return content.fixedSize(horizontal: !vertical, vertical: vertical)
      .onGeometryChange(for: CollectionMeasurementSample?.self) { proxy in
        guard let token else { return nil }
        return CollectionMeasurementSample(
          token: token, extent: vertical ? proxy.size.height : proxy.size.width)
      } action: { sample in
        guard let sample else { return }
        latest = sample
        controller.measure(sample.extent, key: key, token: sample.token)
      }
      .onAppear {
        if mount == nil { mount = UUID() }
        guard let token else { return }
        controller.attachMeasurement(key: key, token: token)
        if let latest, latest.token == token {
          controller.measure(latest.extent, key: key, token: token)
        }
      }
      .onChange(of: token) { _, token in
        guard let token else { return }
        controller.attachMeasurement(key: key, token: token)
        if let latest, latest.token == token {
          controller.measure(latest.extent, key: key, token: token)
        }
      }
      .onDisappear {
        if let mount { controller.detachMeasurement(key: key, mount: mount) }
      }
  }
}
