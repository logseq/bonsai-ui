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

@MainActor @Observable final class CollectionMeasurements {
  private(set) var generation: UInt64 = 0
  @ObservationIgnored private var context: CollectionMeasurementContext?
  @ObservationIgnored private var extents: [Data: Double] = [:]

  func advance() { generation &+= 1 }
  func clear() {
    extents.removeAll()
    advance()
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
    extents = extents.filter { key, _ in
      guard let before = old.indices[key], let after = next.indices[key] else { return false }
      return old.geometry.extent(at: before) == next.geometry.extent(at: after)
    }
    advance()
  }
  func geometry(for catalog: RenderCollectionCatalog) -> CollectionGeometry {
    guard catalog.measurementRevision != nil, !extents.isEmpty else { return catalog.geometry }
    var overrides = Dictionary(
      uniqueKeysWithValues: catalog.geometry.overrides.map { ($0.index, $0.extent) })
    for (key, extent) in extents {
      if let index = catalog.indices[key] { overrides[index] = extent }
    }
    // Accepted measurements are validated before publication.
    guard
      let geometry = try? CollectionGeometry(
        count: catalog.keys.count,
        defaultExtent: catalog.geometry.defaultExtent,
        overrides: overrides.sorted { $0.key < $1.key }.map {
          CollectionExtent(index: $0.key, extent: $0.value)
        })
    else {
      // A new, individually valid catalog can make the old measured adjustments
      // exceed the coordinate domain. Invalidate that cache before publishing.
      clear()
      return catalog.geometry
    }
    return geometry
  }
  func accept(_ extent: Double, key: Data, generation: UInt64, catalog: RenderCollectionCatalog)
    -> Bool
  {
    guard context != nil, generation == self.generation, catalog.indices[key] != nil,
      extent.isFinite, extent > 0, extent <= 9_007_199_254_740_992,
      extents[key] != extent
    else { return false }
    var overrides = Dictionary(
      uniqueKeysWithValues: catalog.geometry.overrides.map { ($0.index, $0.extent) })
    for (measuredKey, measuredExtent) in extents {
      if let index = catalog.indices[measuredKey] { overrides[index] = measuredExtent }
    }
    overrides[catalog.indices[key]!] = extent
    guard
      (try? CollectionGeometry(
        count: catalog.keys.count,
        defaultExtent: catalog.geometry.defaultExtent,
        overrides: overrides.sorted { $0.key < $1.key }.map {
          CollectionExtent(index: $0.key, extent: $0.value)
        })) != nil
    else { return false }
    extents[key] = extent
    return true
  }
}

private struct CollectionMeasurementSample: Equatable {
  let generation: UInt64
  let extent: Double
}

struct MeasuredCollectionRow<Content: View>: View {
  let controller: CollectionController
  let key: Data
  let generation: UInt64
  let vertical: Bool
  let content: Content

  var body: some View {
    let generation = generation
    let vertical = vertical
    return content.fixedSize(horizontal: !vertical, vertical: vertical)
      .onGeometryChange(for: CollectionMeasurementSample.self) { proxy in
        CollectionMeasurementSample(
          generation: generation,
          extent: vertical ? proxy.size.height : proxy.size.width)
      } action: { sample in
        controller.measure(sample.extent, key: key, generation: sample.generation)
      }
  }
}
